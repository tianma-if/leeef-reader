//! Portable library records. SQLite triggers journal each mutation in the same transaction.
//! Book references use file hashes, so independently imported copies converge without
//! changing the local IDs used by an open reader or by EdgeEver.
use crate::db::{self, AppState};
use rusqlite::{params, params_from_iter, types::Value as SqlValue, Connection, OptionalExtension};
use serde::{Deserialize, Serialize};
use serde_json::{Map, Value};
use std::{fs, path::PathBuf};

struct Table {
    name: &'static str,
    keys: &'static [&'static str],
    columns: &'static [&'static str],
}

const TABLES: &[Table] = &[
    Table {
        name: "books",
        keys: &["id"],
        columns: &[
            "id",
            "sha256",
            "title",
            "author",
            "description",
            "media_type",
            "rating",
            "is_deleted",
            "created_at",
            "updated_at",
        ],
    },
    Table {
        name: "tags",
        keys: &["id"],
        columns: &[
            "id",
            "name",
            "color",
            "is_deleted",
            "created_at",
            "updated_at",
        ],
    },
    Table {
        name: "bookshelves",
        keys: &["id"],
        columns: &[
            "id",
            "parent_id",
            "name",
            "sort_order",
            "is_deleted",
            "created_at",
            "updated_at",
        ],
    },
    Table {
        name: "excerpts",
        keys: &["id"],
        columns: &[
            "id",
            "book_id",
            "locator",
            "quote",
            "note",
            "color",
            "is_deleted",
            "created_at",
            "updated_at",
        ],
    },
    Table {
        name: "bookmarks",
        keys: &["id"],
        columns: &[
            "id",
            "book_id",
            "locator",
            "title",
            "note",
            "is_deleted",
            "created_at",
            "updated_at",
        ],
    },
    Table {
        name: "reading_progresses",
        keys: &["book_id"],
        columns: &[
            "book_id",
            "locator",
            "progress",
            "chapter_title",
            "page",
            "device_id",
            "updated_at",
        ],
    },
    Table {
        name: "reading_sessions",
        keys: &["id"],
        columns: &[
            "id",
            "book_id",
            "device_id",
            "started_at",
            "ended_at",
            "duration_seconds",
            "is_deleted",
            "updated_at",
        ],
    },
    Table {
        name: "bookshelf_entries",
        keys: &["bookshelf_id", "book_id"],
        columns: &["bookshelf_id", "book_id", "sort_order", "updated_at"],
    },
    Table {
        name: "book_tag_entries",
        keys: &["tag_id", "book_id"],
        columns: &["tag_id", "book_id", "updated_at"],
    },
];

#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Record {
    pub table: String,
    pub key: String,
    pub modified_at: i64,
    pub device_id: String,
    pub deleted: bool,
    pub data: Value,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Asset {
    pub book_hash: String,
    pub cover_hash: Option<String>,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Snapshot {
    pub version: u8,
    pub space_id: String,
    pub device_id: String,
    pub devices: Vec<String>,
    pub records: Vec<Record>,
    pub assets: Vec<Asset>,
}

fn expression(table: &Table, column: &str, row: &str) -> String {
    if table.name == "books" && column == "id" {
        format!("{row}.sha256")
    } else if column == "book_id" {
        format!("(SELECT sha256 FROM books WHERE id = {row}.book_id)")
    } else {
        format!("{row}.{column}")
    }
}

fn key_sql(table: &Table, row: &str) -> String {
    format!(
        "json_array({})",
        table
            .keys
            .iter()
            .map(|key| expression(table, key, row))
            .collect::<Vec<_>>()
            .join(",")
    )
}

fn data_sql(table: &Table, row: &str) -> String {
    format!(
        "json_object({})",
        table
            .columns
            .iter()
            .map(|column| format!("'{column}',{}", expression(table, column, row)))
            .collect::<Vec<_>>()
            .join(",")
    )
}

pub fn initialize(db: &Connection) -> Result<(), String> {
    db.execute_batch("CREATE TABLE IF NOT EXISTS library_sync_records (
        entity_table TEXT NOT NULL, entity_key TEXT NOT NULL, modified_at INTEGER NOT NULL,
        device_id TEXT NOT NULL, deleted INTEGER NOT NULL, data_json TEXT NOT NULL,
        PRIMARY KEY(entity_table, entity_key));
        CREATE INDEX IF NOT EXISTS library_sync_clock ON library_sync_records(modified_at);
        CREATE TABLE IF NOT EXISTS library_sync_control (id INTEGER PRIMARY KEY CHECK(id=1), applying INTEGER NOT NULL);
        INSERT OR IGNORE INTO library_sync_control VALUES(1,0);
        CREATE TABLE IF NOT EXISTS library_sync_conflicts (
          entity_table TEXT NOT NULL, entity_key TEXT NOT NULL, modified_at INTEGER NOT NULL,
          device_id TEXT NOT NULL, deleted INTEGER NOT NULL, data_json TEXT NOT NULL,
          PRIMARY KEY(entity_table, entity_key, modified_at, device_id));")
        .map_err(|e| e.to_string())?;
    for table in TABLES {
        for (event, row, deleted) in [
            ("INSERT", "NEW", 0),
            ("UPDATE", "NEW", 0),
            ("DELETE", "OLD", 1),
        ] {
            let archive = if matches!(table.name, "excerpts" | "reading_progresses")
                && event != "INSERT"
            {
                // Upgrade existing journals as well as new databases. Keep the previous
                // local version before edits/deletions, including offline mutations.
                db.execute_batch(&format!(
                    "DROP TRIGGER IF EXISTS library_sync_{}_{event}",
                    table.name
                ))
                .map_err(|e| e.to_string())?;
                format!("INSERT OR IGNORE INTO library_sync_conflicts SELECT * FROM library_sync_records WHERE entity_table='{}' AND entity_key={};", table.name, key_sql(table, "OLD"))
            } else {
                String::new()
            };
            let key = key_sql(table, row);
            let data = data_sql(table, row);
            // A monotonic clock survives same-millisecond edits and clock rollback.
            let sql = format!("CREATE TRIGGER IF NOT EXISTS library_sync_{}_{event}
              AFTER {event} ON {} WHEN (SELECT applying FROM library_sync_control WHERE id=1)=0
              BEGIN
                {archive}
                INSERT INTO library_sync_records VALUES ('{}', {key},
                  MAX(CAST(strftime('%s','now') AS INTEGER)*1000 + CAST(substr(strftime('%f','now'),4,3) AS INTEGER),
                      COALESCE((SELECT MAX(modified_at)+1 FROM library_sync_records),0)),
                  (SELECT value FROM kv WHERE key='device_id'), {deleted}, {data})
                ON CONFLICT(entity_table,entity_key) DO UPDATE SET modified_at=excluded.modified_at,
                  device_id=excluded.device_id, deleted=excluded.deleted, data_json=excluded.data_json;
              END;", table.name, table.name, table.name);
            db.execute_batch(&sql).map_err(|e| e.to_string())?;
        }
        // Bootstrap pre-sync libraries using the original modification time.
        let sql = format!("INSERT OR IGNORE INTO library_sync_records
          SELECT '{}', {}, COALESCE(CASE WHEN r.updated_at NOT GLOB '*[^0-9]*'
            THEN CAST(r.updated_at AS INTEGER)*1000 ELSE CAST(strftime('%s',r.updated_at) AS INTEGER)*1000 END,0),
            (SELECT value FROM kv WHERE key='device_id'),0,{} FROM {} r", table.name, key_sql(table,"r"), data_sql(table,"r"), table.name);
        db.execute(&sql, []).map_err(|e| e.to_string())?;
    }
    // Older clients already retain the content of soft-deleted excerpts in
    // their journal; expose it for recovery even without a pre-delete version.
    db.execute("INSERT OR IGNORE INTO library_sync_conflicts SELECT * FROM library_sync_records WHERE entity_table='excerpts' AND (deleted=1 OR json_extract(data_json,'$.is_deleted')=1)", []).map_err(|e| e.to_string())?;
    Ok(())
}

pub fn records(state: &AppState) -> Result<Vec<Record>, String> {
    let db = state.db.lock().map_err(|e| e.to_string())?;
    let mut stmt = db.prepare("SELECT entity_table,entity_key,modified_at,device_id,deleted,data_json FROM library_sync_records ORDER BY entity_table,entity_key").map_err(|e| e.to_string())?;
    let rows = stmt
        .query_map([], |row| {
            Ok((
                row.get::<_, String>(0)?,
                row.get::<_, String>(1)?,
                row.get::<_, i64>(2)?,
                row.get::<_, String>(3)?,
                row.get::<_, bool>(4)?,
                row.get::<_, String>(5)?,
            ))
        })
        .map_err(|e| e.to_string())?;
    rows.map(|row| {
        let (table, key, modified_at, device_id, deleted, json) = row.map_err(|e| e.to_string())?;
        Ok(Record {
            table,
            key,
            modified_at,
            device_id,
            deleted,
            data: serde_json::from_str(&json).map_err(|e| e.to_string())?,
        })
    })
    .collect()
}

pub fn pending_count(state: &AppState) -> Result<usize, String> {
    let db = state.db.lock().map_err(|e| e.to_string())?;
    db.query_row("SELECT COUNT(*) FROM library_sync_records WHERE modified_at>COALESCE((SELECT CAST(value AS INTEGER) FROM kv WHERE key='library_last_uploaded_revision'),0)", [], |r| r.get(0)).map_err(|e| e.to_string())
}

pub fn valid_hash(hash: &str) -> bool {
    hash.len() == 64
        && hash
            .bytes()
            .all(|c| c.is_ascii_digit() || (b'a'..=b'f').contains(&c))
}

pub fn asset_path(state: &AppState, hash: &str) -> Result<PathBuf, String> {
    if !valid_hash(hash) {
        return Err("无效的书库对象哈希".into());
    }
    Ok(state.root.join("sync-objects").join(hash))
}

pub fn store_asset(state: &AppState, hash: &str, bytes: &[u8]) -> Result<(), String> {
    if db::sha256_hex(bytes) != hash {
        return Err("下载的书库文件校验失败".into());
    }
    let path = asset_path(state, hash)?;
    fs::create_dir_all(path.parent().unwrap()).map_err(|e| e.to_string())?;
    let temp = path.with_extension(format!("{}.tmp", uuid::Uuid::new_v4()));
    fs::write(&temp, bytes).map_err(|e| e.to_string())?;
    fs::rename(&temp, path).map_err(|e| e.to_string())
}

/// Collect paths under the database lock, then read bytes without blocking reading mutations.
pub fn local_assets(state: &AppState) -> Result<Vec<(Asset, Vec<(String, PathBuf)>)>, String> {
    let paths = {
        let db = state.db.lock().map_err(|e| e.to_string())?;
        let mut stmt = db.prepare("SELECT sha256,file_path,cover_path FROM books WHERE is_deleted=0 AND is_available_locally=1").map_err(|e| e.to_string())?;
        let rows = stmt
            .query_map([], |row| {
                Ok((
                    row.get::<_, String>(0)?,
                    row.get::<_, Option<String>>(1)?,
                    row.get::<_, Option<String>>(2)?,
                ))
            })
            .map_err(|e| e.to_string())?;
        rows.collect::<Result<Vec<_>, _>>()
            .map_err(|e| e.to_string())?
    };
    let mut result = Vec::new();
    for (hash, file, cover) in paths {
        let Some(file) = file else {
            continue;
        };
        if !std::path::Path::new(&file).is_file() {
            return Err("书籍文件已丢失，请重新导入后再同步".into());
        }
        let mut objects = vec![(hash.clone(), PathBuf::from(file))];
        let cover_hash =
            if let Some(path) = cover.filter(|path| std::path::Path::new(path).is_file()) {
                let bytes = fs::read(&path).map_err(|e| e.to_string())?;
                let hash = db::sha256_hex(&bytes);
                objects.push((hash.clone(), PathBuf::from(path)));
                Some(hash)
            } else {
                None
            };
        result.push((
            Asset {
                book_hash: hash,
                cover_hash,
            },
            objects,
        ));
    }
    Ok(result)
}

fn sql_value(value: &Value) -> Result<SqlValue, String> {
    Ok(match value {
        Value::Null => SqlValue::Null,
        Value::Bool(v) => SqlValue::Integer(i64::from(*v)),
        Value::String(v) => SqlValue::Text(v.clone()),
        Value::Number(v) => {
            if let Some(i) = v.as_i64() {
                SqlValue::Integer(i)
            } else {
                SqlValue::Real(v.as_f64().ok_or("无效数字")?)
            }
        }
        _ => return Err("书库记录包含不支持的数据类型".into()),
    })
}

fn validate(record: &Record, table: &Table) -> Result<(), String> {
    let data = record.data.as_object().ok_or("无效的书库记录")?;
    if record.modified_at < 0 || record.device_id.is_empty() || data.len() != table.columns.len() {
        return Err("无效的书库记录版本".into());
    }
    for column in table.columns {
        sql_value(data.get(*column).ok_or("书库记录缺少字段")?)?;
    }
    let key = Value::Array(table.keys.iter().map(|key| data[*key].clone()).collect());
    if key.to_string() != record.key {
        return Err("书库记录标识不匹配".into());
    }
    let hash = if table.name == "books" {
        data.get("sha256")
    } else {
        data.get("book_id")
    };
    if let Some(hash) = hash {
        if !hash.as_str().map(valid_hash).unwrap_or(false) {
            return Err("书库记录引用了无效书籍".into());
        }
    }
    if table.name == "books" && data["id"] != data["sha256"] {
        return Err("书籍标识与文件不一致".into());
    }
    Ok(())
}

fn localize(db: &Connection, table: &Table, data: &Value) -> Result<Map<String, Value>, String> {
    let mut data = data.as_object().ok_or("无效的书库记录")?.clone();
    let column = if table.name == "books" {
        "id"
    } else {
        "book_id"
    };
    if let Some(hash) = data.get(column).and_then(Value::as_str) {
        let id: Option<String> = db
            .query_row("SELECT id FROM books WHERE sha256=?1", [hash], |row| {
                row.get(0)
            })
            .optional()
            .map_err(|e| e.to_string())?;
        data.insert(
            column.into(),
            Value::String(id.unwrap_or_else(|| hash.to_owned())),
        );
    }
    Ok(data)
}

pub fn merge(state: &AppState, incoming: &[Record], assets: &[Asset]) -> Result<usize, String> {
    let mut db = state.db.lock().map_err(|e| e.to_string())?;
    let tx = db.transaction().map_err(|e| e.to_string())?;
    let changed = merge_transaction(&tx, state, incoming, assets)?;
    tx.commit().map_err(|e| e.to_string())?;
    Ok(changed)
}

fn merge_transaction(
    tx: &Connection,
    state: &AppState,
    incoming: &[Record],
    assets: &[Asset],
) -> Result<usize, String> {
    tx.execute_batch(
        "PRAGMA defer_foreign_keys=ON; UPDATE library_sync_control SET applying=1 WHERE id=1;",
    )
    .map_err(|e| e.to_string())?;
    let mut changed = 0;
    for table in TABLES {
        for record in incoming.iter().filter(|r| r.table == table.name) {
            validate(record, table)?;
            let current: Option<(i64,String,String,bool)> = tx.query_row("SELECT modified_at,device_id,data_json,deleted FROM library_sync_records WHERE entity_table=?1 AND entity_key=?2",params![record.table,record.key],|r|Ok((r.get(0)?,r.get(1)?,r.get(2)?,r.get(3)?))).optional().map_err(|e|e.to_string())?;
            if let Some((time, device, data, deleted)) = current {
                let differs = deleted != record.deleted
                    || serde_json::from_str::<Value>(&data).map_err(|e| e.to_string())?
                        != record.data;
                if (record.modified_at, record.device_id.as_str()) <= (time, device.as_str()) {
                    if differs && matches!(table.name, "excerpts" | "reading_progresses") {
                        tx.execute("INSERT OR IGNORE INTO library_sync_conflicts VALUES(?1,?2,?3,?4,?5,?6)", params![record.table,record.key,record.modified_at,record.device_id,record.deleted,record.data.to_string()]).map_err(|e|e.to_string())?;
                    }
                    continue;
                }
                // Keep replaced reading positions and notes available for recovery/audit.
                if matches!(table.name, "excerpts" | "reading_progresses") && differs {
                    tx.execute("INSERT OR IGNORE INTO library_sync_conflicts SELECT * FROM library_sync_records WHERE entity_table=?1 AND entity_key=?2",params![record.table,record.key]).map_err(|e|e.to_string())?;
                }
            }
            let data = localize(&tx, table, &record.data)?;
            if record.deleted {
                let where_clause = table
                    .keys
                    .iter()
                    .map(|key| format!("{key}=?"))
                    .collect::<Vec<_>>()
                    .join(" AND ");
                let values = table
                    .keys
                    .iter()
                    .map(|key| sql_value(&data[*key]))
                    .collect::<Result<Vec<_>, _>>()?;
                tx.execute(
                    &format!("DELETE FROM {} WHERE {where_clause}", table.name),
                    params_from_iter(values),
                )
                .map_err(|e| e.to_string())?;
            } else {
                let mut columns = table.columns.join(",");
                let mut placeholders = table
                    .columns
                    .iter()
                    .map(|_| "?")
                    .collect::<Vec<_>>()
                    .join(",");
                if table.name == "books" {
                    columns.push_str(",is_available_locally");
                    placeholders.push_str(",0");
                }
                let updates = table
                    .columns
                    .iter()
                    .filter(|c| !table.keys.contains(c))
                    .map(|c| format!("{c}=excluded.{c}"))
                    .collect::<Vec<_>>()
                    .join(",");
                let values = table
                    .columns
                    .iter()
                    .map(|column| sql_value(&data[*column]))
                    .collect::<Result<Vec<_>, _>>()?;
                tx.execute(&format!("INSERT INTO {} ({columns}) VALUES ({placeholders}) ON CONFLICT({}) DO UPDATE SET {updates}",table.name,table.keys.join(",")),params_from_iter(values)).map_err(|e|e.to_string())?;
            }
            tx.execute("INSERT INTO library_sync_records VALUES(?1,?2,?3,?4,?5,?6) ON CONFLICT(entity_table,entity_key) DO UPDATE SET modified_at=excluded.modified_at,device_id=excluded.device_id,deleted=excluded.deleted,data_json=excluded.data_json",params![record.table,record.key,record.modified_at,record.device_id,record.deleted,record.data.to_string()]).map_err(|e|e.to_string())?;
            changed += 1;
        }
    }
    if incoming
        .iter()
        .any(|r| !TABLES.iter().any(|t| t.name == r.table))
    {
        return Err("书库包含未知的数据类型，请更新应用".into());
    }
    for asset in assets {
        let file = asset_path(state, &asset.book_hash)?;
        if !file.is_file() {
            continue;
        }
        let cover = asset
            .cover_hash
            .as_ref()
            .map(|hash| asset_path(state, hash))
            .transpose()?;
        let cover = cover
            .filter(|path| path.is_file())
            .map(|path| path.to_string_lossy().into_owned());
        changed += tx.execute("UPDATE books SET file_path=?2,cover_path=COALESCE(?3,cover_path),is_available_locally=1 WHERE sha256=?1 AND (is_available_locally=0 OR file_path IS NOT ?2 OR (cover_path IS NULL AND ?3 IS NOT NULL))",params![asset.book_hash,file.to_string_lossy(),cover]).map_err(|e|e.to_string())?;
    }
    tx.execute("UPDATE library_sync_control SET applying=0 WHERE id=1", [])
        .map_err(|e| e.to_string())?;
    Ok(changed)
}

#[derive(Clone, Debug, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct Revision {
    modified_at: i64,
    device_id: String,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct HistoryEntry {
    id: i64,
    book_title: String,
    restorable: bool,
    record: Record,
    current: Option<Record>,
}

fn read_record(row: &rusqlite::Row<'_>) -> rusqlite::Result<Record> {
    let json: String = row.get(5)?;
    let data = serde_json::from_str(&json).map_err(|e| {
        rusqlite::Error::FromSqlConversionFailure(5, rusqlite::types::Type::Text, Box::new(e))
    })?;
    Ok(Record {
        table: row.get(0)?,
        key: row.get(1)?,
        modified_at: row.get(2)?,
        device_id: row.get(3)?,
        deleted: row.get(4)?,
        data,
    })
}

fn current_record(db: &Connection, record: &Record) -> Result<Option<Record>, String> {
    db.query_row(
        "SELECT * FROM library_sync_records WHERE entity_table=?1 AND entity_key=?2",
        params![record.table, record.key],
        read_record,
    )
    .optional()
    .map_err(|e| e.to_string())
}

pub fn history(
    state: &AppState,
    before_id: Option<i64>,
    kind: Option<&str>,
) -> Result<Vec<HistoryEntry>, String> {
    let db = state.db.lock().map_err(|e| e.to_string())?;
    if kind.is_some_and(|k| !matches!(k, "excerpts" | "reading_progresses")) {
        return Err("不支持的历史类型".into());
    }
    // Rowid cursor remains stable when new versions are archived during browsing.
    let mut stmt = db.prepare("SELECT *,rowid FROM library_sync_conflicts WHERE entity_table IN ('excerpts','reading_progresses') AND (?1 IS NULL OR rowid<?1) AND (?2 IS NULL OR entity_table=?2) ORDER BY rowid DESC LIMIT 30").map_err(|e| e.to_string())?;
    let rows = stmt
        .query_map(params![before_id, kind], |row| {
            Ok((row.get::<_, i64>(6)?, read_record(row)?))
        })
        .map_err(|e| e.to_string())?;
    rows.map(|row| {
        let (id, record) = row.map_err(|e| e.to_string())?;
        let book: Option<(String, bool)> = db
            .query_row(
                "SELECT title,is_deleted=0 FROM books WHERE sha256=?1",
                [record.data["book_id"].as_str().unwrap_or("")],
                |row| Ok((row.get(0)?, row.get(1)?)),
            )
            .optional()
            .map_err(|e| e.to_string())?;
        let current = current_record(&db, &record)?;
        Ok(HistoryEntry {
            id,
            book_title: book
                .as_ref()
                .map(|b| b.0.clone())
                .unwrap_or_else(|| "已移除的书籍".into()),
            restorable: book.is_some_and(|b| b.1),
            record,
            current,
        })
    })
    .collect()
}

pub fn restore_history(
    state: &AppState,
    id: i64,
    expected: Option<Revision>,
) -> Result<(), String> {
    let mut db = state.db.lock().map_err(|e| e.to_string())?;
    let tx = db.transaction().map_err(|e| e.to_string())?;
    let mut record = tx.query_row("SELECT * FROM library_sync_conflicts WHERE rowid=?1 AND entity_table IN ('excerpts','reading_progresses')", [id], read_record).optional().map_err(|e| e.to_string())?.ok_or("历史版本不存在，请刷新后重试")?;
    let actual = current_record(&tx, &record)?.map(|r| Revision {
        modified_at: r.modified_at,
        device_id: r.device_id,
    });
    if actual != expected {
        return Err("当前记录已有新修改，请刷新历史并重新确认恢复".into());
    }
    let available: bool = tx
        .query_row(
            "SELECT EXISTS(SELECT 1 FROM books WHERE sha256=?1 AND is_deleted=0)",
            [record.data["book_id"].as_str().unwrap_or("")],
            |r| r.get(0),
        )
        .map_err(|e| e.to_string())?;
    if !available {
        return Err("请先恢复或重新导入这本书，再恢复历史版本".into());
    }
    // Recovery is a fresh local mutation, never a rollback of the sync clock.
    record.modified_at = tx.query_row("SELECT MAX(CAST(strftime('%s','now') AS INTEGER)*1000, COALESCE((SELECT MAX(modified_at)+1 FROM library_sync_records),0), COALESCE((SELECT MAX(modified_at)+1 FROM library_sync_conflicts),0))", [], |r| r.get(0)).map_err(|e| e.to_string())?;
    record.device_id = state.device_id.clone();
    record.deleted = false;
    if record.table == "excerpts" {
        record.data["is_deleted"] = Value::from(0);
    }
    if record.table == "reading_progresses" {
        record.data["device_id"] = Value::from(state.device_id.clone());
    }
    record.data["updated_at"] = Value::from((record.modified_at / 1000).to_string());
    merge_transaction(&tx, state, &[record], &[])?;
    tx.commit().map_err(|e| e.to_string())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn book(state: &AppState) -> db::Book {
        db::import_book(
            state,
            "book.txt",
            b"same book",
            "Test",
            None,
            "text/plain",
            None,
        )
        .unwrap()
    }

    fn revision(entry: &HistoryEntry) -> Option<Revision> {
        entry.current.as_ref().map(|r| Revision {
            modified_at: r.modified_at,
            device_id: r.device_id.clone(),
        })
    }

    #[test]
    fn restores_deleted_excerpt_as_new_version_and_syncs_without_losing_current_history() {
        let root = tempfile::tempdir().unwrap();
        let other_root = tempfile::tempdir().unwrap();
        let state = db::open(root.path().into()).unwrap();
        let other = db::open(other_root.path().into()).unwrap();
        let local = book(&state);
        let id = db::upsert_excerpt(
            &state,
            &local.id,
            "cfi",
            "quote",
            Some("original"),
            "yellow",
        )
        .unwrap();
        db::update_excerpt(&state, &id, None, Some("edited"), "yellow").unwrap();
        db::delete_excerpt(&state, &id).unwrap();
        let old_snapshot = records(&state).unwrap();
        merge(&other, &old_snapshot, &[]).unwrap();
        assert!(db::list_excerpts(&state, None).unwrap().is_empty());
        let entry = history(&state, None, Some("excerpts"))
            .unwrap()
            .into_iter()
            .find(|e| e.record.data["note"] == "original")
            .unwrap();
        let old_revision = revision(&entry).unwrap();
        restore_history(&state, entry.id, Some(old_revision.clone())).unwrap();
        assert_eq!(
            db::list_excerpts(&state, None).unwrap()[0].note.as_deref(),
            Some("original")
        );
        let restored = records(&state)
            .unwrap()
            .into_iter()
            .find(|r| r.table == "excerpts")
            .unwrap();
        assert!(restored.modified_at > old_revision.modified_at);
        assert_eq!(restored.device_id, state.device_id);
        assert!(history(&state, None, None)
            .unwrap()
            .iter()
            .any(|e| e.record.data["is_deleted"] == 1));
        merge(&other, &records(&state).unwrap(), &[]).unwrap();
        assert_eq!(
            db::list_excerpts(&other, None).unwrap()[0].note.as_deref(),
            Some("original")
        );
        merge(&state, &old_snapshot, &[]).unwrap();
        assert_eq!(db::list_excerpts(&state, None).unwrap().len(), 1);
    }

    #[test]
    fn restore_rejects_stale_preview_and_missing_book_atomically() {
        let root = tempfile::tempdir().unwrap();
        let state = db::open(root.path().into()).unwrap();
        let local = book(&state);
        db::save_progress(&state, &local.id, "first", 0.1, None, None).unwrap();
        db::save_progress(&state, &local.id, "second", 0.2, None, None).unwrap();
        let entry = history(&state, None, None).unwrap().remove(0);
        db::save_progress(&state, &local.id, "third", 0.3, None, None).unwrap();
        assert!(restore_history(&state, entry.id, revision(&entry))
            .unwrap_err()
            .contains("新修改"));
        assert_eq!(
            db::list_books(&state).unwrap()[0].locator.as_deref(),
            Some("third")
        );
        let fresh = history(&state, None, None)
            .unwrap()
            .into_iter()
            .find(|e| e.id == entry.id)
            .unwrap();
        restore_history(&state, fresh.id, revision(&fresh)).unwrap();
        assert_eq!(
            db::list_books(&state).unwrap()[0].locator.as_deref(),
            Some("first")
        );
        state
            .db
            .lock()
            .unwrap()
            .execute("UPDATE books SET is_deleted=1 WHERE id=?1", [&local.id])
            .unwrap();
        let deleted = history(&state, None, None).unwrap().remove(0);
        assert!(!deleted.restorable);
        assert!(restore_history(&state, deleted.id, revision(&deleted))
            .unwrap_err()
            .contains("重新导入"));
        // A rejected transaction must not disable future local journaling.
        db::save_progress(&state, &local.id, "fourth", 0.4, None, None).unwrap();
        assert!(records(&state)
            .unwrap()
            .iter()
            .any(|r| r.data["locator"] == "fourth"));
    }

    #[test]
    fn history_cursor_filter_and_upgrade_preserve_recoverable_content() {
        let root = tempfile::tempdir().unwrap();
        let state = db::open(root.path().into()).unwrap();
        let local = book(&state);
        for n in 0..36 {
            db::save_progress(
                &state,
                &local.id,
                &n.to_string(),
                n as f64 / 100.0,
                None,
                None,
            )
            .unwrap();
        }
        let first = history(&state, None, None).unwrap();
        assert_eq!(first.len(), 30);
        db::save_progress(&state, &local.id, "new", 0.9, None, None).unwrap();
        let second = history(&state, Some(first.last().unwrap().id), None).unwrap();
        assert_eq!(second.len(), 5);
        assert!(second.iter().all(|b| !first.iter().any(|a| a.id == b.id)));
        let id = db::upsert_excerpt(&state, &local.id, "cfi", "legacy", None, "yellow").unwrap();
        db::delete_excerpt(&state, &id).unwrap();
        {
            let db = state.db.lock().unwrap();
            db.execute(
                "DELETE FROM library_sync_conflicts WHERE entity_table='excerpts'",
                [],
            )
            .unwrap();
            initialize(&db).unwrap();
            initialize(&db).unwrap();
        }
        let legacy = history(&state, None, Some("excerpts")).unwrap();
        assert_eq!(legacy.len(), 1);
        restore_history(&state, legacy[0].id, revision(&legacy[0])).unwrap();
        assert_eq!(db::list_excerpts(&state, None).unwrap()[0].quote, "legacy");
        assert!(history(&state, None, Some("books")).is_err());
        assert!(restore_history(&state, i64::MAX, None).is_err());
    }

    #[test]
    fn hard_deletion_preserves_identical_payload_as_a_recoverable_version() {
        let root = tempfile::tempdir().unwrap();
        let state = db::open(root.path().into()).unwrap();
        let local = book(&state);
        db::upsert_excerpt(&state, &local.id, "cfi", "retained", None, "yellow").unwrap();
        let mut remote = records(&state)
            .unwrap()
            .into_iter()
            .find(|r| r.table == "excerpts")
            .unwrap();
        remote.modified_at += 100;
        remote.deleted = true;
        merge(&state, &[remote], &[]).unwrap();
        assert!(db::list_excerpts(&state, None).unwrap().is_empty());
        let entry = history(&state, None, None).unwrap().remove(0);
        restore_history(&state, entry.id, revision(&entry)).unwrap();
        assert_eq!(
            db::list_excerpts(&state, None).unwrap()[0].quote,
            "retained"
        );
    }

    #[test]
    fn independently_imported_books_merge_notes_tags_and_reading_data_without_duplicates() {
        let a_root = tempfile::tempdir().unwrap();
        let b_root = tempfile::tempdir().unwrap();
        let a = db::open(a_root.path().into()).unwrap();
        let b = db::open(b_root.path().into()).unwrap();
        let abook = book(&a);
        let bbook = book(&b);
        let shelf = db::create_shelf(&a, "Study", None, 0).unwrap();
        db::add_book_to_shelf(&a, &shelf, &abook.id, 0).unwrap();
        db::create_tag(&a, "Tag", 123).unwrap();
        let tag = db::list_tags(&a).unwrap()[0].id.clone();
        db::set_book_tag(&a, &abook.id, &tag, true).unwrap();
        db::upsert_excerpt(&a, &abook.id, "cfi", "Quote", Some("Note"), "yellow").unwrap();
        db::add_bookmark(&a, &abook.id, "cfi", Some("Mark"), None).unwrap();
        db::save_progress(&a, &abook.id, "later", 0.8, None, None).unwrap();
        db::record_session(&a, &abook.id, 30).unwrap();
        let snapshot = records(&a).unwrap();
        assert!(merge(&b, &snapshot, &[]).unwrap() > 0);
        let books = db::list_books(&b).unwrap();
        assert_eq!(books.len(), 1);
        assert_eq!(books[0].id, bbook.id);
        assert_eq!(books[0].tags, vec!["Tag"]);
        assert_eq!(books[0].shelf_ids, vec![shelf.clone()]);
        assert_eq!(db::list_excerpts(&b, Some(&bbook.id)).unwrap().len(), 1);
        assert_eq!(db::list_bookmarks(&b, Some(&bbook.id)).unwrap().len(), 1);
        assert_eq!(db::list_sessions(&b).unwrap().len(), 1);
        assert_eq!(merge(&b, &snapshot, &[]).unwrap(), 0);
        db::remove_book_from_shelf(&a, &shelf, &abook.id).unwrap();
        db::set_book_tag(&a, &abook.id, &tag, false).unwrap();
        merge(&b, &records(&a).unwrap(), &[]).unwrap();
        merge(&b, &snapshot, &[]).unwrap();
        let books = db::list_books(&b).unwrap();
        assert!(books[0].tags.is_empty());
        assert!(books[0].shelf_ids.is_empty());
    }

    #[test]
    fn backtracking_uses_latest_position_and_keeps_replaced_position() {
        let a_root = tempfile::tempdir().unwrap();
        let b_root = tempfile::tempdir().unwrap();
        let a = db::open(a_root.path().into()).unwrap();
        let b = db::open(b_root.path().into()).unwrap();
        let abook = book(&a);
        db::save_progress(&a, &abook.id, "far", 0.8, None, None).unwrap();
        merge(&b, &records(&a).unwrap(), &[]).unwrap();
        let bbook = db::list_books(&b).unwrap().remove(0);
        db::save_progress(&b, &bbook.id, "back", 0.2, None, None).unwrap();
        merge(&a, &records(&b).unwrap(), &[]).unwrap();
        assert_eq!(
            db::list_books(&a).unwrap()[0].locator.as_deref(),
            Some("back")
        );
        let count: i64 = a.db.lock().unwrap().query_row("SELECT count(*) FROM library_sync_conflicts WHERE entity_table='reading_progresses'",[],|r|r.get(0)).unwrap();
        assert_eq!(count, 1);
    }

    #[test]
    fn invalid_snapshot_rolls_back_and_does_not_disable_local_journaling() {
        let root = tempfile::tempdir().unwrap();
        let state = db::open(root.path().into()).unwrap();
        let local = book(&state);
        let mut snapshot = records(&state).unwrap();
        snapshot[0].modified_at += 100;
        snapshot[0].data["title"] = Value::String("Do not apply".into());
        snapshot.push(Record {
            table: "unknown".into(),
            key: "[]".into(),
            modified_at: 0,
            device_id: "bad".into(),
            deleted: false,
            data: Value::Null,
        });
        assert!(merge(&state, &snapshot, &[]).is_err());
        assert_eq!(db::list_books(&state).unwrap()[0].title, "Test");
        db::update_book(&state, &local.id, Some("Updated"), None, None, None).unwrap();
        assert_eq!(records(&state).unwrap()[0].data["title"], "Updated");
    }

    #[test]
    fn downloaded_assets_are_verified_and_cannot_escape_storage() {
        let root = tempfile::tempdir().unwrap();
        let state = db::open(root.path().into()).unwrap();
        let hash = db::sha256_hex(b"book");
        assert!(store_asset(&state, &hash, b"corrupt").is_err());
        assert!(asset_path(&state, "../../outside").is_err());
        store_asset(&state, &hash, b"book").unwrap();
        assert_eq!(
            fs::read(asset_path(&state, &hash).unwrap()).unwrap(),
            b"book"
        );
    }
}
