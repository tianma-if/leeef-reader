use crate::{
    db::{self, AppState},
    library_sync::{self, Asset, Record},
};
use aes_gcm::{
    aead::{Aead, KeyInit, Payload},
    Aes256Gcm, Nonce,
};
use argon2::{Algorithm, Argon2, Params, Version};
use base64::{engine::general_purpose::STANDARD, Engine};
use rand::RngCore;
use serde::{Deserialize, Serialize};
use std::collections::BTreeMap;

const AAD: &[u8] = b"leeef-library-backup-v1";
// The current native file bridge transfers text. Bound memory until streaming
// archives are available, and report the boundary rather than truncate a library.
const MAX_CONTENT_BYTES: usize = 128 * 1024 * 1024;

#[derive(Serialize, Deserialize)]
struct Backup {
    version: u8,
    records: Vec<Record>,
    assets: Vec<Asset>,
    objects: BTreeMap<String, String>,
}

#[derive(Serialize, Deserialize)]
struct Envelope {
    format: String,
    version: u8,
    salt: String,
    nonce: String,
    ciphertext: String,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Preview {
    pub books: usize,
    pub excerpts: usize,
    pub bookmarks: usize,
    pub bytes: usize,
    pub matching_books: usize,
}

fn derive(password: &str, salt: &[u8]) -> Result<[u8; 32], String> {
    if password.chars().count() < 12 {
        return Err("备份密码至少需要 12 个字符".into());
    }
    let mut key = [0; 32];
    let params = Params::new(32 * 1024, 3, 1, Some(32)).map_err(|e| e.to_string())?;
    Argon2::new(Algorithm::Argon2id, Version::V0x13, params)
        .hash_password_into(password.as_bytes(), salt, &mut key)
        .map_err(|e| e.to_string())?;
    Ok(key)
}

pub fn export(state: &AppState, password: &str) -> Result<String, String> {
    let mut salt = [0; 16];
    let mut nonce = [0; 12];
    rand::thread_rng().fill_bytes(&mut salt);
    rand::thread_rng().fill_bytes(&mut nonce);
    let key = derive(password, &salt)?;
    let records = library_sync::records(state)?;
    let mut objects = BTreeMap::new();
    let mut assets = Vec::new();
    let mut total = 0;
    for (asset, paths) in library_sync::local_assets(state)? {
        for (hash, path) in paths {
            if objects.contains_key(&hash) {
                continue;
            }
            let size = std::fs::metadata(&path).map_err(|e| e.to_string())?.len();
            if size > MAX_CONTENT_BYTES as u64 || total as u64 + size > MAX_CONTENT_BYTES as u64 {
                return Err(
                    "当前备份支持总计 128 MiB 的书籍与封面，请使用书库同步保存更大的书库".into(),
                );
            }
            let bytes = std::fs::read(path).map_err(|e| e.to_string())?;
            if db::sha256_hex(&bytes) != hash {
                return Err("书籍文件已变化，无法生成完整备份".into());
            }
            total += bytes.len();
            objects.insert(hash, STANDARD.encode(bytes));
        }
        assets.push(asset);
    }
    if serde_json::to_vec(&records).map_err(|e| e.to_string())?
        != serde_json::to_vec(&library_sync::records(state)?).map_err(|e| e.to_string())?
    {
        return Err("备份期间书库发生变化，请重试".into());
    }
    let backup = Backup {
        version: 1,
        records,
        assets,
        objects,
    };
    validate(&backup)?;
    let plaintext = serde_json::to_vec(&backup).map_err(|e| e.to_string())?;
    let cipher = Aes256Gcm::new_from_slice(&key).map_err(|e| e.to_string())?;
    let ciphertext = cipher
        .encrypt(
            Nonce::from_slice(&nonce),
            Payload {
                msg: &plaintext,
                aad: AAD,
            },
        )
        .map_err(|_| "备份加密失败")?;
    serde_json::to_string(&Envelope {
        format: "leeef-library-backup".into(),
        version: 1,
        salt: STANDARD.encode(salt),
        nonce: STANDARD.encode(nonce),
        ciphertext: STANDARD.encode(ciphertext),
    })
    .map_err(|e| e.to_string())
}

fn open(package: &str, password: &str) -> Result<Backup, String> {
    if package.len() > MAX_CONTENT_BYTES * 3 {
        return Err("备份文件超过当前支持大小".into());
    }
    let envelope: Envelope = serde_json::from_str(package).map_err(|_| "不是有效的书库备份文件")?;
    if envelope.format != "leeef-library-backup" || envelope.version != 1 {
        return Err("不支持此备份版本".into());
    }
    let salt = STANDARD.decode(envelope.salt).map_err(|_| "备份盐值无效")?;
    let nonce = STANDARD
        .decode(envelope.nonce)
        .map_err(|_| "备份随机数无效")?;
    if salt.len() != 16 || nonce.len() != 12 {
        return Err("备份加密参数无效".into());
    }
    let key = derive(password, &salt)?;
    let ciphertext = STANDARD
        .decode(envelope.ciphertext)
        .map_err(|_| "备份内容无效")?;
    let cipher = Aes256Gcm::new_from_slice(&key).map_err(|e| e.to_string())?;
    let plaintext = cipher
        .decrypt(
            Nonce::from_slice(&nonce),
            Payload {
                msg: &ciphertext,
                aad: AAD,
            },
        )
        .map_err(|_| "密码错误或备份已损坏")?;
    let backup: Backup = serde_json::from_slice(&plaintext).map_err(|_| "备份数据格式无效")?;
    validate(&backup)?;
    Ok(backup)
}

fn validate(backup: &Backup) -> Result<(), String> {
    if backup.version != 1 {
        return Err("不支持此书库版本".into());
    }
    let mut total: usize = 0;
    for (hash, encoded) in &backup.objects {
        if !library_sync::valid_hash(hash) {
            return Err("备份对象标识无效".into());
        }
        let bytes = STANDARD.decode(encoded).map_err(|_| "备份对象损坏")?;
        total = total.checked_add(bytes.len()).ok_or("备份过大")?;
        if total > MAX_CONTENT_BYTES {
            return Err("备份文件超过当前支持大小".into());
        }
        if db::sha256_hex(&bytes) != *hash {
            return Err("备份文件校验失败".into());
        }
    }
    for asset in &backup.assets {
        if !backup.objects.contains_key(&asset.book_hash)
            || asset
                .cover_hash
                .as_ref()
                .is_some_and(|hash| !backup.objects.contains_key(hash))
        {
            return Err("备份缺少书籍或封面文件".into());
        }
    }
    for record in &backup.records {
        if record.table == "books"
            && !record.deleted
            && record.data["is_deleted"].as_i64() != Some(1)
        {
            let hash = record.data["sha256"].as_str().ok_or("书籍缺少文件标识")?;
            if !backup.assets.iter().any(|asset| asset.book_hash == hash) {
                return Err("书库文件不完整，无法备份或恢复".into());
            }
        }
    }
    Ok(())
}

pub fn preview(state: &AppState, package: &str, password: &str) -> Result<Preview, String> {
    let backup = open(package, password)?;
    let local = db::list_books(state)?;
    let count = |table: &str| {
        backup
            .records
            .iter()
            .filter(|r| r.table == table && !r.deleted && r.data["is_deleted"].as_i64() != Some(1))
            .count()
    };
    let bytes = backup.objects.values().try_fold(0usize, |sum, value| {
        STANDARD
            .decode(value)
            .map(|bytes| sum + bytes.len())
            .map_err(|e| e.to_string())
    })?;
    Ok(Preview {
        books: count("books"),
        excerpts: count("excerpts"),
        bookmarks: count("bookmarks"),
        bytes,
        matching_books: backup
            .assets
            .iter()
            .filter(|asset| local.iter().any(|book| book.sha256 == asset.book_hash))
            .count(),
    })
}

pub fn restore(
    state: &AppState,
    package: &str,
    password: &str,
    prefer_backup: bool,
) -> Result<usize, String> {
    let mut backup = open(package, password)?;
    if prefer_backup {
        let current = library_sync::records(state)?;
        let mut clock = current
            .iter()
            .chain(backup.records.iter())
            .map(|r| r.modified_at)
            .max()
            .unwrap_or(0)
            .max(db::now().parse::<i64>().map_err(|e| e.to_string())? * 1000);
        for record in &mut backup.records {
            clock = clock.checked_add(1).ok_or("备份版本无效")?;
            record.modified_at = clock;
            record.device_id = state.device_id.clone();
        }
    }
    // Verify every object before touching database rows. Staged files are harmless
    // if the transactional merge rejects a malformed record.
    for (hash, encoded) in &backup.objects {
        library_sync::store_asset(
            state,
            hash,
            &STANDARD.decode(encoded).map_err(|e| e.to_string())?,
        )?;
    }
    library_sync::merge(state, &backup.records, &backup.assets)
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn encrypted_backup_restores_files_notes_progress_and_deleted_data_on_request() {
        let a_root = tempfile::tempdir().unwrap();
        let b_root = tempfile::tempdir().unwrap();
        let a = db::open(a_root.path().into()).unwrap();
        let b = db::open(b_root.path().into()).unwrap();
        let book = db::import_book(
            &a,
            "b.txt",
            b"book",
            "Book",
            None,
            "text/plain",
            Some(b"cover"),
        )
        .unwrap();
        let note =
            db::upsert_excerpt(&a, &book.id, "loc", "quote", Some("thought"), "yellow").unwrap();
        db::save_progress(&a, &book.id, "loc", 0.4, None, None).unwrap();
        let package = export(&a, "correct horse battery").unwrap();
        assert!(!package.contains("thought"));
        assert!(restore(&b, &package, "wrong password here", false).is_err());
        assert!(db::list_books(&b).unwrap().is_empty());
        assert_eq!(
            preview(&b, &package, "correct horse battery")
                .unwrap()
                .books,
            1
        );
        restore(&b, &package, "correct horse battery", false).unwrap();
        let restored = db::list_books(&b).unwrap().remove(0);
        assert_eq!(db::book_bytes(&b, &restored.id).unwrap(), b"book");
        assert_eq!(db::book_cover(&b, &restored.id).unwrap(), b"cover");
        assert_eq!(restored.locator.as_deref(), Some("loc"));
        assert_eq!(
            db::list_excerpts(&b, Some(&restored.id)).unwrap()[0]
                .note
                .as_deref(),
            Some("thought")
        );
        assert_eq!(
            restore(&b, &package, "correct horse battery", false).unwrap(),
            0
        );
        db::delete_excerpt(&b, &note).unwrap();
        restore(&b, &package, "correct horse battery", false).unwrap();
        assert!(db::list_excerpts(&b, Some(&restored.id))
            .unwrap()
            .is_empty());
        restore(&b, &package, "correct horse battery", true).unwrap();
        assert_eq!(db::list_excerpts(&b, Some(&restored.id)).unwrap().len(), 1);
    }
}
