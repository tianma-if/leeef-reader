use rusqlite::{params, Connection, OptionalExtension};
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use std::fs;
use std::path::{Path, PathBuf};
use std::sync::{Arc, Mutex};
use uuid::Uuid;

#[derive(Clone)]
pub struct AppState {
    pub db: Arc<Mutex<Connection>>,
    pub root: PathBuf,
    pub device_id: String,
}

#[derive(Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Book {
    pub id: String,
    pub sha256: String,
    pub title: String,
    pub author: Option<String>,
    pub description: Option<String>,
    pub media_type: String,
    pub file_path: Option<String>,
    pub cover_path: Option<String>,
    pub rating: Option<f64>,
    pub is_available_locally: bool,
    pub created_at: String,
    pub updated_at: String,
    pub progress: f64,
    pub locator: Option<String>,
    pub chapter_title: Option<String>,
    pub tags: Vec<String>,
    #[serde(default)]
    pub shelf_ids: Vec<String>,
}

#[derive(Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Shelf {
    pub id: String,
    pub parent_id: Option<String>,
    pub name: String,
    pub sort_order: i64,
}

#[derive(Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Tag {
    pub id: String,
    pub name: String,
    pub color: i64,
}

#[derive(Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Excerpt {
    pub id: String,
    pub book_id: String,
    pub locator: String,
    pub quote: String,
    pub note: Option<String>,
    pub color: String,
    pub created_at: String,
    pub book_title: Option<String>,
}

#[derive(Clone)]
pub struct EdgeEverExcerptNote {
    pub book_id: String,
    pub instance_url: String,
    pub memo_id: String,
    pub revision: i64,
    pub remote_content_hash: String,
    pub local_content_hash: String,
}

#[derive(Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Bookmark {
    pub id: String,
    pub book_id: String,
    pub locator: String,
    pub title: Option<String>,
    pub note: Option<String>,
    pub created_at: String,
}

#[derive(Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Session {
    pub id: String,
    pub book_id: String,
    pub started_at: String,
    pub ended_at: String,
    pub duration_seconds: i64,
}

pub fn now() -> String {
    // Keep ISO-8601 text like Drift/MCP tests.
    chrono_like()
}

fn chrono_like() -> String {
    use std::time::{SystemTime, UNIX_EPOCH};
    let secs = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_secs();
    format!("{secs}")
}

pub fn sha256_hex(bytes: &[u8]) -> String {
    hex::encode(Sha256::digest(bytes))
}

pub fn open(root: PathBuf) -> Result<AppState, String> {
    fs::create_dir_all(root.join("books")).map_err(|e| e.to_string())?;
    fs::create_dir_all(root.join("covers")).map_err(|e| e.to_string())?;
    let db_path = root.join("leeef.sqlite");
    let db = Connection::open(&db_path).map_err(|e| e.to_string())?;
    db.execute_batch(
        r#"
        PRAGMA foreign_keys = ON;
        CREATE TABLE IF NOT EXISTS books (
          id TEXT PRIMARY KEY,
          sha256 TEXT NOT NULL UNIQUE,
          md5 TEXT,
          title TEXT NOT NULL,
          author TEXT,
          description TEXT,
          media_type TEXT NOT NULL,
          file_path TEXT,
          cover_path TEXT,
          cover_sha256 TEXT,
          rating REAL,
          is_available_locally INTEGER NOT NULL DEFAULT 1,
          is_deleted INTEGER NOT NULL DEFAULT 0,
          created_at TEXT NOT NULL,
          updated_at TEXT NOT NULL
        );
        CREATE TABLE IF NOT EXISTS book_id_aliases (
          alias_id TEXT PRIMARY KEY,
          canonical_id TEXT NOT NULL REFERENCES books(id) ON DELETE CASCADE
        );
        CREATE TABLE IF NOT EXISTS tags (
          id TEXT PRIMARY KEY,
          name TEXT NOT NULL,
          color INTEGER NOT NULL,
          is_deleted INTEGER NOT NULL DEFAULT 0,
          created_at TEXT NOT NULL,
          updated_at TEXT NOT NULL
        );
        CREATE TABLE IF NOT EXISTS book_tag_entries (
          tag_id TEXT NOT NULL REFERENCES tags(id) ON DELETE CASCADE,
          book_id TEXT NOT NULL REFERENCES books(id) ON DELETE CASCADE,
          updated_at TEXT NOT NULL,
          PRIMARY KEY(tag_id, book_id)
        );
        CREATE TABLE IF NOT EXISTS bookshelves (
          id TEXT PRIMARY KEY,
          parent_id TEXT REFERENCES bookshelves(id) ON DELETE SET NULL,
          name TEXT NOT NULL,
          sort_order INTEGER NOT NULL DEFAULT 0,
          is_deleted INTEGER NOT NULL DEFAULT 0,
          created_at TEXT NOT NULL,
          updated_at TEXT NOT NULL
        );
        CREATE TABLE IF NOT EXISTS bookshelf_entries (
          bookshelf_id TEXT NOT NULL REFERENCES bookshelves(id) ON DELETE CASCADE,
          book_id TEXT NOT NULL REFERENCES books(id) ON DELETE CASCADE,
          sort_order INTEGER NOT NULL DEFAULT 0,
          updated_at TEXT NOT NULL,
          PRIMARY KEY(bookshelf_id, book_id)
        );
        CREATE TABLE IF NOT EXISTS excerpts (
          id TEXT PRIMARY KEY,
          book_id TEXT NOT NULL REFERENCES books(id) ON DELETE CASCADE,
          locator TEXT NOT NULL,
          quote TEXT NOT NULL,
          note TEXT,
          color TEXT NOT NULL DEFAULT 'yellow',
          is_deleted INTEGER NOT NULL DEFAULT 0,
          created_at TEXT NOT NULL,
          updated_at TEXT NOT NULL
        );
        CREATE TABLE IF NOT EXISTS bookmarks (
          id TEXT PRIMARY KEY,
          book_id TEXT NOT NULL REFERENCES books(id) ON DELETE CASCADE,
          locator TEXT NOT NULL,
          title TEXT,
          note TEXT,
          is_deleted INTEGER NOT NULL DEFAULT 0,
          created_at TEXT NOT NULL,
          updated_at TEXT NOT NULL
        );
        CREATE TABLE IF NOT EXISTS reading_progresses (
          book_id TEXT PRIMARY KEY REFERENCES books(id) ON DELETE CASCADE,
          locator TEXT NOT NULL,
          progress REAL NOT NULL,
          chapter_title TEXT,
          page INTEGER,
          device_id TEXT NOT NULL,
          updated_at TEXT NOT NULL
        );
        CREATE TABLE IF NOT EXISTS reading_progress_history (
          operation_id TEXT PRIMARY KEY,
          book_id TEXT NOT NULL REFERENCES books(id) ON DELETE CASCADE,
          locator TEXT NOT NULL,
          progress REAL NOT NULL,
          chapter_title TEXT,
          page INTEGER,
          device_id TEXT NOT NULL,
          updated_at TEXT NOT NULL
        );
        CREATE TABLE IF NOT EXISTS reading_sessions (
          id TEXT PRIMARY KEY,
          book_id TEXT NOT NULL REFERENCES books(id) ON DELETE CASCADE,
          device_id TEXT NOT NULL,
          started_at TEXT NOT NULL,
          ended_at TEXT NOT NULL,
          duration_seconds INTEGER NOT NULL,
          is_deleted INTEGER NOT NULL DEFAULT 0,
          updated_at TEXT NOT NULL
        );
        CREATE TABLE IF NOT EXISTS sync_operations (
          operation_id TEXT PRIMARY KEY,
          device_id TEXT NOT NULL,
          entity_type TEXT NOT NULL,
          entity_id TEXT NOT NULL,
          kind TEXT NOT NULL,
          payload_json TEXT,
          occurred_at TEXT NOT NULL,
          applied_at TEXT
        );
        CREATE TABLE IF NOT EXISTS edgeever_excerpt_notes (
          book_id TEXT PRIMARY KEY REFERENCES books(id) ON DELETE CASCADE,
          instance_url TEXT NOT NULL,
          memo_id TEXT NOT NULL,
          revision INTEGER NOT NULL,
          remote_content_hash TEXT NOT NULL,
          local_content_hash TEXT NOT NULL,
          synced_at TEXT NOT NULL,
          last_error TEXT
        );
        CREATE TABLE IF NOT EXISTS audit_events (
          id TEXT PRIMARY KEY,
          caller TEXT NOT NULL,
          action TEXT NOT NULL,
          parameters_json TEXT NOT NULL,
          result TEXT NOT NULL,
          occurred_at TEXT NOT NULL
        );
        CREATE TABLE IF NOT EXISTS kv (
          key TEXT PRIMARY KEY,
          value TEXT NOT NULL
        );
        "#,
    )
    .map_err(|e| e.to_string())?;

    let device_id = {
        let existing: Option<String> = db
            .query_row("SELECT value FROM kv WHERE key = 'device_id'", [], |row| {
                row.get(0)
            })
            .optional()
            .map_err(|e| e.to_string())?;
        if let Some(id) = existing {
            id
        } else {
            let id = Uuid::new_v4().to_string();
            db.execute(
                "INSERT INTO kv(key, value) VALUES ('device_id', ?1)",
                params![id],
            )
            .map_err(|e| e.to_string())?;
            id
        }
    };

    Ok(AppState {
        db: Arc::new(Mutex::new(db)),
        root,
        device_id,
    })
}

fn log_op(
    db: &Connection,
    device_id: &str,
    entity_type: &str,
    entity_id: &str,
    kind: &str,
    payload: &str,
) {
    let _ = db.execute(
        "INSERT INTO sync_operations(operation_id, device_id, entity_type, entity_id, kind, payload_json, occurred_at)
         VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)",
        params![Uuid::new_v4().to_string(), device_id, entity_type, entity_id, kind, payload, now()],
    );
}

pub fn list_books(state: &AppState) -> Result<Vec<Book>, String> {
    let db = state.db.lock().map_err(|e| e.to_string())?;
    let mut stmt = db
        .prepare(
            "SELECT b.id, b.sha256, b.title, b.author, b.description, b.media_type, b.file_path,
                    b.cover_path, b.rating, b.is_available_locally, b.created_at, b.updated_at,
                    COALESCE(p.progress, 0), p.locator, p.chapter_title
             FROM books b
             LEFT JOIN reading_progresses p ON p.book_id = b.id
             WHERE b.is_deleted = 0
             ORDER BY COALESCE(p.updated_at, b.updated_at) DESC",
        )
        .map_err(|e| e.to_string())?;
    let rows = stmt
        .query_map([], |row| {
            Ok(Book {
                id: row.get(0)?,
                sha256: row.get(1)?,
                title: row.get(2)?,
                author: row.get(3)?,
                description: row.get(4)?,
                media_type: row.get(5)?,
                file_path: row.get(6)?,
                cover_path: row.get(7)?,
                rating: row.get(8)?,
                is_available_locally: row.get::<_, i64>(9)? != 0,
                created_at: row.get(10)?,
                updated_at: row.get(11)?,
                progress: row.get(12)?,
                locator: row.get(13)?,
                chapter_title: row.get(14)?,
                tags: vec![],
                shelf_ids: vec![],
            })
        })
        .map_err(|e| e.to_string())?;
    let mut books = Vec::new();
    for row in rows {
        books.push(row.map_err(|e| e.to_string())?);
    }
    for book in &mut books {
        let mut tag_stmt = db
            .prepare(
                "SELECT t.name FROM tags t
                 JOIN book_tag_entries e ON e.tag_id = t.id
                 WHERE e.book_id = ?1 AND t.is_deleted = 0",
            )
            .map_err(|e| e.to_string())?;
        book.tags = tag_stmt
            .query_map(params![book.id], |row| row.get(0))
            .map_err(|e| e.to_string())?
            .filter_map(|r| r.ok())
            .collect();
        let mut shelf_stmt = db
            .prepare("SELECT bookshelf_id FROM bookshelf_entries WHERE book_id = ?1")
            .map_err(|e| e.to_string())?;
        book.shelf_ids = shelf_stmt
            .query_map(params![book.id], |row| row.get(0))
            .map_err(|e| e.to_string())?
            .filter_map(|r| r.ok())
            .collect();
    }
    Ok(books)
}

pub fn book_cover(state: &AppState, id: &str) -> Result<Vec<u8>, String> {
    let db = state.db.lock().map_err(|e| e.to_string())?;
    let path: Option<String> = db
        .query_row(
            "SELECT cover_path FROM books WHERE id = ?1 AND is_deleted = 0",
            params![id],
            |row| row.get(0),
        )
        .optional()
        .map_err(|e| e.to_string())?
        .flatten();
    let Some(path) = path.filter(|value| !value.is_empty()) else {
        return Ok(Vec::new());
    };
    match fs::read(path) {
        Ok(bytes) => Ok(bytes),
        Err(_) => Ok(Vec::new()),
    }
}

pub fn import_book(
    state: &AppState,
    name: &str,
    bytes: &[u8],
    title: &str,
    author: Option<&str>,
    media_type: &str,
    cover: Option<&[u8]>,
) -> Result<Book, String> {
    let hash = sha256_hex(bytes);
    let db = state.db.lock().map_err(|e| e.to_string())?;
    if let Some(existing) = db
        .query_row(
            "SELECT id FROM books WHERE sha256 = ?1 AND is_deleted = 0",
            params![hash],
            |row| row.get::<_, String>(0),
        )
        .optional()
        .map_err(|e| e.to_string())?
    {
        return Err(format!("已存在相同文件：{existing}"));
    }
    let id = Uuid::new_v4().to_string();
    let ext = Path::new(name)
        .extension()
        .and_then(|s| s.to_str())
        .unwrap_or("epub");
    let file_path = state.root.join("books").join(format!("{id}.{ext}"));
    fs::write(&file_path, bytes).map_err(|e| e.to_string())?;
    let cover_path = if let Some(cover_bytes) = cover {
        let path = state.root.join("covers").join(format!("{id}.img"));
        fs::write(&path, cover_bytes).map_err(|e| e.to_string())?;
        Some(path.to_string_lossy().into_owned())
    } else {
        None
    };
    let ts = now();
    db.execute(
        "INSERT INTO books(id, sha256, title, author, media_type, file_path, cover_path,
            is_available_locally, is_deleted, created_at, updated_at)
         VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, 1, 0, ?8, ?8)",
        params![
            id,
            hash,
            title,
            author,
            media_type,
            file_path.to_string_lossy().as_ref(),
            cover_path,
            ts
        ],
    )
    .map_err(|e| e.to_string())?;
    log_op(&db, &state.device_id, "book", &id, "create", title);
    drop(db);
    list_books(state)?
        .into_iter()
        .find(|book| book.id == id)
        .ok_or_else(|| "导入后未找到书籍".into())
}

pub fn delete_book(state: &AppState, id: &str) -> Result<(), String> {
    let db = state.db.lock().map_err(|e| e.to_string())?;
    db.execute(
        "UPDATE books SET is_deleted = 1, updated_at = ?2 WHERE id = ?1",
        params![id, now()],
    )
    .map_err(|e| e.to_string())?;
    log_op(&db, &state.device_id, "book", id, "delete", "{}");
    Ok(())
}

pub fn update_book(
    state: &AppState,
    id: &str,
    title: Option<&str>,
    author: Option<&str>,
    rating: Option<f64>,
    description: Option<&str>,
) -> Result<(), String> {
    let db = state.db.lock().map_err(|e| e.to_string())?;
    let ts = now();
    let changed = db
        .execute(
            "UPDATE books SET
                title = COALESCE(?2, title),
                author = COALESCE(?3, author),
                rating = COALESCE(?4, rating),
                description = COALESCE(?5, description),
                updated_at = ?6
             WHERE id = ?1 AND is_deleted = 0",
            params![id, title, author, rating, description, ts],
        )
        .map_err(|e| e.to_string())?;
    if changed == 0 {
        return Err("book does not exist".into());
    }
    log_op(
        &db,
        &state.device_id,
        "book",
        id,
        "upsert",
        &serde_json::json!({
            "title": title,
            "author": author,
            "rating": rating,
            "description": description
        })
        .to_string(),
    );
    Ok(())
}

pub fn book_bytes(state: &AppState, id: &str) -> Result<Vec<u8>, String> {
    let db = state.db.lock().map_err(|e| e.to_string())?;
    let path: String = db
        .query_row(
            "SELECT file_path FROM books WHERE id = ?1 AND is_deleted = 0",
            params![id],
            |row| row.get(0),
        )
        .map_err(|e| e.to_string())?;
    drop(db);
    fs::read(path).map_err(|e| e.to_string())
}

pub fn save_progress(
    state: &AppState,
    book_id: &str,
    locator: &str,
    progress: f64,
    chapter_title: Option<&str>,
    page: Option<i64>,
) -> Result<(), String> {
    let db = state.db.lock().map_err(|e| e.to_string())?;
    let ts = now();
    db.execute(
        "INSERT INTO reading_progresses(book_id, locator, progress, chapter_title, page, device_id, updated_at)
         VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)
         ON CONFLICT(book_id) DO UPDATE SET
           locator = excluded.locator,
           progress = excluded.progress,
           chapter_title = excluded.chapter_title,
           page = excluded.page,
           device_id = excluded.device_id,
           updated_at = excluded.updated_at",
        params![book_id, locator, progress, chapter_title, page, state.device_id, ts],
    )
    .map_err(|e| e.to_string())?;
    log_op(
        &db,
        &state.device_id,
        "readingProgress",
        book_id,
        "upsert",
        &serde_json::json!({
            "locator": locator,
            "progress": progress,
            "chapterTitle": chapter_title,
            "page": page
        })
        .to_string(),
    );
    Ok(())
}

pub fn list_excerpts(state: &AppState, book_id: Option<&str>) -> Result<Vec<Excerpt>, String> {
    let db = state.db.lock().map_err(|e| e.to_string())?;
    let sql = if book_id.is_some() {
        "SELECT e.id, e.book_id, e.locator, e.quote, e.note, e.color, e.created_at, b.title
         FROM excerpts e JOIN books b ON b.id = e.book_id
         WHERE e.is_deleted = 0 AND e.book_id = ?1 ORDER BY e.updated_at DESC"
    } else {
        "SELECT e.id, e.book_id, e.locator, e.quote, e.note, e.color, e.created_at, b.title
         FROM excerpts e JOIN books b ON b.id = e.book_id
         WHERE e.is_deleted = 0 ORDER BY e.updated_at DESC"
    };
    let mut stmt = db.prepare(sql).map_err(|e| e.to_string())?;
    let map_row = |row: &rusqlite::Row| {
        Ok(Excerpt {
            id: row.get(0)?,
            book_id: row.get(1)?,
            locator: row.get(2)?,
            quote: row.get(3)?,
            note: row.get(4)?,
            color: row.get(5)?,
            created_at: row.get(6)?,
            book_title: row.get(7)?,
        })
    };
    let rows = if let Some(id) = book_id {
        stmt.query_map(params![id], map_row)
    } else {
        stmt.query_map([], map_row)
    }
    .map_err(|e| e.to_string())?;
    rows.collect::<Result<Vec<_>, _>>()
        .map_err(|e| e.to_string())
}

pub fn upsert_excerpt(
    state: &AppState,
    book_id: &str,
    locator: &str,
    quote: &str,
    note: Option<&str>,
    color: &str,
) -> Result<String, String> {
    let db = state.db.lock().map_err(|e| e.to_string())?;
    let id = Uuid::new_v4().to_string();
    let ts = now();
    db.execute(
        "INSERT INTO excerpts(id, book_id, locator, quote, note, color, is_deleted, created_at, updated_at)
         VALUES (?1, ?2, ?3, ?4, ?5, ?6, 0, ?7, ?7)",
        params![id, book_id, locator, quote, note, color, ts],
    )
    .map_err(|e| e.to_string())?;
    log_op(
        &db,
        &state.device_id,
        "excerpt",
        &id,
        "upsert",
        &serde_json::json!({
            "id": id, "bookId": book_id, "locator": locator,
            "quote": quote, "note": note, "color": color
        })
        .to_string(),
    );
    Ok(id)
}

pub fn update_excerpt(
    state: &AppState,
    id: &str,
    quote: Option<&str>,
    note: Option<&str>,
    color: &str,
) -> Result<(), String> {
    let db = state.db.lock().map_err(|e| e.to_string())?;
    let changed = db
        .execute(
            "UPDATE excerpts SET quote = COALESCE(?2, quote), note = ?3, color = ?4, updated_at = ?5
             WHERE id = ?1 AND is_deleted = 0",
            params![id, quote, note, color, now()],
        )
        .map_err(|e| e.to_string())?;
    if changed == 0 {
        return Err("excerpt does not exist".into());
    }
    log_op(&db, &state.device_id, "excerpt", id, "upsert", "{}");
    Ok(())
}

pub fn excerpt_book_id(state: &AppState, id: &str) -> Result<String, String> {
    let db = state.db.lock().map_err(|e| e.to_string())?;
    db.query_row(
        "SELECT book_id FROM excerpts WHERE id = ?1",
        params![id],
        |row| row.get(0),
    )
    .optional()
    .map_err(|e| e.to_string())?
    .ok_or_else(|| "excerpt does not exist".into())
}

pub fn edgeever_excerpt_note(
    state: &AppState,
    book_id: &str,
    instance_url: &str,
) -> Result<Option<EdgeEverExcerptNote>, String> {
    let db = state.db.lock().map_err(|e| e.to_string())?;
    db.query_row(
        "SELECT book_id, instance_url, memo_id, revision, remote_content_hash, local_content_hash
         FROM edgeever_excerpt_notes WHERE book_id = ?1 AND instance_url = ?2",
        params![book_id, instance_url],
        |row| {
            Ok(EdgeEverExcerptNote {
                book_id: row.get(0)?,
                instance_url: row.get(1)?,
                memo_id: row.get(2)?,
                revision: row.get(3)?,
                remote_content_hash: row.get(4)?,
                local_content_hash: row.get(5)?,
            })
        },
    )
    .optional()
    .map_err(|e| e.to_string())
}

pub fn save_edgeever_excerpt_note(
    state: &AppState,
    link: &EdgeEverExcerptNote,
) -> Result<(), String> {
    let db = state.db.lock().map_err(|e| e.to_string())?;
    db.execute(
        "INSERT INTO edgeever_excerpt_notes(
           book_id, instance_url, memo_id, revision, remote_content_hash, local_content_hash,
           synced_at, last_error
         ) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, NULL)
         ON CONFLICT(book_id) DO UPDATE SET
           instance_url = excluded.instance_url,
           memo_id = excluded.memo_id,
           revision = excluded.revision,
           remote_content_hash = excluded.remote_content_hash,
           local_content_hash = excluded.local_content_hash,
           synced_at = excluded.synced_at,
           last_error = NULL",
        params![
            link.book_id,
            link.instance_url,
            link.memo_id,
            link.revision,
            link.remote_content_hash,
            link.local_content_hash,
            now()
        ],
    )
    .map_err(|e| e.to_string())?;
    Ok(())
}

pub fn save_edgeever_sync_error(
    state: &AppState,
    book_id: &str,
    error: &str,
) -> Result<(), String> {
    let db = state.db.lock().map_err(|e| e.to_string())?;
    db.execute(
        "UPDATE edgeever_excerpt_notes SET last_error = ?2 WHERE book_id = ?1",
        params![book_id, error],
    )
    .map_err(|e| e.to_string())?;
    Ok(())
}

pub fn delete_excerpt(state: &AppState, id: &str) -> Result<(), String> {
    let db = state.db.lock().map_err(|e| e.to_string())?;
    let changed = db
        .execute(
            "UPDATE excerpts SET is_deleted = 1, updated_at = ?2 WHERE id = ?1 AND is_deleted = 0",
            params![id, now()],
        )
        .map_err(|e| e.to_string())?;
    if changed == 0 {
        return Err("excerpt does not exist".into());
    }
    log_op(&db, &state.device_id, "excerpt", id, "delete", "{}");
    Ok(())
}

pub fn list_bookmarks(state: &AppState, book_id: Option<&str>) -> Result<Vec<Bookmark>, String> {
    let db = state.db.lock().map_err(|e| e.to_string())?;
    let sql = if book_id.is_some() {
        "SELECT id, book_id, locator, title, note, created_at FROM bookmarks
         WHERE is_deleted = 0 AND book_id = ?1 ORDER BY created_at DESC"
    } else {
        "SELECT id, book_id, locator, title, note, created_at FROM bookmarks
         WHERE is_deleted = 0 ORDER BY created_at DESC"
    };
    let mut stmt = db.prepare(sql).map_err(|e| e.to_string())?;
    let map_row = |row: &rusqlite::Row| {
        Ok(Bookmark {
            id: row.get(0)?,
            book_id: row.get(1)?,
            locator: row.get(2)?,
            title: row.get(3)?,
            note: row.get(4)?,
            created_at: row.get(5)?,
        })
    };
    let rows = if let Some(id) = book_id {
        stmt.query_map(params![id], map_row)
    } else {
        stmt.query_map([], map_row)
    }
    .map_err(|e| e.to_string())?;
    rows.collect::<Result<Vec<_>, _>>()
        .map_err(|e| e.to_string())
}

pub fn add_bookmark(
    state: &AppState,
    book_id: &str,
    locator: &str,
    title: Option<&str>,
    note: Option<&str>,
) -> Result<String, String> {
    let db = state.db.lock().map_err(|e| e.to_string())?;
    let id = Uuid::new_v4().to_string();
    let ts = now();
    db.execute(
        "INSERT INTO bookmarks(id, book_id, locator, title, note, is_deleted, created_at, updated_at)
         VALUES (?1, ?2, ?3, ?4, ?5, 0, ?6, ?6)",
        params![id, book_id, locator, title, note, ts],
    )
    .map_err(|e| e.to_string())?;
    log_op(
        &db,
        &state.device_id,
        "bookmark",
        &id,
        "upsert",
        &serde_json::json!({
            "id": id, "bookId": book_id, "locator": locator, "title": title, "note": note
        })
        .to_string(),
    );
    Ok(id)
}

pub fn update_bookmark(
    state: &AppState,
    id: &str,
    title: Option<&str>,
    note: Option<&str>,
) -> Result<(), String> {
    let db = state.db.lock().map_err(|e| e.to_string())?;
    let changed = db
        .execute(
            "UPDATE bookmarks SET title = COALESCE(?2, title), note = COALESCE(?3, note), updated_at = ?4
             WHERE id = ?1 AND is_deleted = 0",
            params![id, title, note, now()],
        )
        .map_err(|e| e.to_string())?;
    if changed == 0 {
        return Err("bookmark does not exist".into());
    }
    log_op(&db, &state.device_id, "bookmark", id, "upsert", "{}");
    Ok(())
}

pub fn delete_bookmark(state: &AppState, id: &str) -> Result<(), String> {
    let db = state.db.lock().map_err(|e| e.to_string())?;
    let changed = db
        .execute(
            "UPDATE bookmarks SET is_deleted = 1, updated_at = ?2 WHERE id = ?1 AND is_deleted = 0",
            params![id, now()],
        )
        .map_err(|e| e.to_string())?;
    if changed == 0 {
        return Err("bookmark does not exist".into());
    }
    log_op(&db, &state.device_id, "bookmark", id, "delete", "{}");
    Ok(())
}

pub fn list_shelves(state: &AppState) -> Result<Vec<Shelf>, String> {
    let db = state.db.lock().map_err(|e| e.to_string())?;
    let mut stmt = db
        .prepare(
            "SELECT id, parent_id, name, sort_order FROM bookshelves
             WHERE is_deleted = 0 ORDER BY sort_order, name",
        )
        .map_err(|e| e.to_string())?;
    let rows = stmt
        .query_map([], |row| {
            Ok(Shelf {
                id: row.get(0)?,
                parent_id: row.get(1)?,
                name: row.get(2)?,
                sort_order: row.get(3)?,
            })
        })
        .map_err(|e| e.to_string())?;
    rows.collect::<Result<Vec<_>, _>>()
        .map_err(|e| e.to_string())
}

pub fn add_book_to_shelf(
    state: &AppState,
    shelf_id: &str,
    book_id: &str,
    sort_order: i64,
) -> Result<(), String> {
    let db = state.db.lock().map_err(|e| e.to_string())?;
    db.execute(
        "INSERT INTO bookshelf_entries(bookshelf_id, book_id, sort_order, updated_at)
         VALUES (?1, ?2, ?3, ?4)
         ON CONFLICT(bookshelf_id, book_id) DO UPDATE SET
           sort_order = excluded.sort_order,
           updated_at = excluded.updated_at",
        params![shelf_id, book_id, sort_order, now()],
    )
    .map_err(|e| e.to_string())?;
    log_op(
        &db,
        &state.device_id,
        "bookshelfEntry",
        &format!("{shelf_id}--{book_id}"),
        "upsert",
        &serde_json::json!({"bookshelfId": shelf_id, "bookId": book_id, "sortOrder": sort_order})
            .to_string(),
    );
    Ok(())
}

pub fn remove_book_from_shelf(
    state: &AppState,
    shelf_id: &str,
    book_id: &str,
) -> Result<(), String> {
    let db = state.db.lock().map_err(|e| e.to_string())?;
    db.execute(
        "DELETE FROM bookshelf_entries WHERE bookshelf_id = ?1 AND book_id = ?2",
        params![shelf_id, book_id],
    )
    .map_err(|e| e.to_string())?;
    log_op(
        &db,
        &state.device_id,
        "bookshelfEntry",
        &format!("{shelf_id}--{book_id}"),
        "delete",
        &serde_json::json!({"bookshelfId": shelf_id, "bookId": book_id}).to_string(),
    );
    Ok(())
}

pub fn create_shelf(
    state: &AppState,
    name: &str,
    parent_id: Option<&str>,
    sort_order: i64,
) -> Result<String, String> {
    let db = state.db.lock().map_err(|e| e.to_string())?;
    let id = Uuid::new_v4().to_string();
    let ts = now();
    db.execute(
        "INSERT INTO bookshelves(id, parent_id, name, sort_order, is_deleted, created_at, updated_at)
         VALUES (?1, ?2, ?3, ?4, 0, ?5, ?5)",
        params![id, parent_id, name, sort_order, ts],
    )
    .map_err(|e| e.to_string())?;
    log_op(
        &db,
        &state.device_id,
        "bookshelf",
        &id,
        "upsert",
        &serde_json::json!({"id": id, "name": name, "parentId": parent_id, "sortOrder": sort_order})
            .to_string(),
    );
    Ok(id)
}

pub fn rename_shelf(state: &AppState, id: &str, name: &str) -> Result<(), String> {
    let db = state.db.lock().map_err(|e| e.to_string())?;
    let changed = db
        .execute(
            "UPDATE bookshelves SET name = ?2, updated_at = ?3 WHERE id = ?1 AND is_deleted = 0",
            params![id, name, now()],
        )
        .map_err(|e| e.to_string())?;
    if changed == 0 {
        return Err("bookshelf does not exist".into());
    }
    log_op(&db, &state.device_id, "bookshelf", id, "upsert", name);
    Ok(())
}

pub fn move_shelf(
    state: &AppState,
    id: &str,
    parent_id: Option<&str>,
    sort_order: i64,
) -> Result<(), String> {
    if parent_id == Some(id) {
        return Err("a bookshelf cannot contain itself".into());
    }
    let db = state.db.lock().map_err(|e| e.to_string())?;
    if let Some(parent) = parent_id {
        let mut cursor = parent.to_string();
        loop {
            if cursor == id {
                return Err("moving the bookshelf would create a cycle".into());
            }
            let next: Option<String> = db
                .query_row(
                    "SELECT parent_id FROM bookshelves WHERE id = ?1 AND is_deleted = 0",
                    params![cursor],
                    |row| row.get(0),
                )
                .optional()
                .map_err(|e| e.to_string())?
                .flatten();
            match next {
                Some(value) => cursor = value,
                None => break,
            }
        }
    }
    let changed = db
        .execute(
            "UPDATE bookshelves SET parent_id = ?2, sort_order = ?3, updated_at = ?4
             WHERE id = ?1 AND is_deleted = 0",
            params![id, parent_id, sort_order, now()],
        )
        .map_err(|e| e.to_string())?;
    if changed == 0 {
        return Err("bookshelf does not exist".into());
    }
    log_op(&db, &state.device_id, "bookshelf", id, "upsert", "{}");
    Ok(())
}

pub fn delete_shelf(state: &AppState, id: &str) -> Result<(), String> {
    let db = state.db.lock().map_err(|e| e.to_string())?;
    let ts = now();
    let changed = db
        .execute(
            "UPDATE bookshelves SET is_deleted = 1, updated_at = ?2 WHERE id = ?1 AND is_deleted = 0",
            params![id, ts],
        )
        .map_err(|e| e.to_string())?;
    if changed == 0 {
        return Err("bookshelf does not exist".into());
    }
    db.execute(
        "UPDATE bookshelves SET parent_id = NULL, updated_at = ?2 WHERE parent_id = ?1",
        params![id, ts],
    )
    .map_err(|e| e.to_string())?;
    log_op(&db, &state.device_id, "bookshelf", id, "delete", "{}");
    Ok(())
}

pub fn move_book_to_shelf(
    state: &AppState,
    book_id: &str,
    shelf_id: &str,
    sort_order: i64,
) -> Result<(), String> {
    let previous = {
        let db = state.db.lock().map_err(|e| e.to_string())?;
        let mut stmt = db
            .prepare("SELECT bookshelf_id FROM bookshelf_entries WHERE book_id = ?1 AND bookshelf_id <> ?2")
            .map_err(|e| e.to_string())?;
        let rows = stmt
            .query_map(params![book_id, shelf_id], |row| row.get::<_, String>(0))
            .map_err(|e| e.to_string())?
            .collect::<Result<Vec<_>, _>>()
            .map_err(|e| e.to_string())?;
        rows
    };
    for previous_id in previous {
        remove_book_from_shelf(state, &previous_id, book_id)?;
    }
    add_book_to_shelf(state, shelf_id, book_id, sort_order)
}

pub fn list_tags(state: &AppState) -> Result<Vec<Tag>, String> {
    let db = state.db.lock().map_err(|e| e.to_string())?;
    let mut stmt = db
        .prepare("SELECT id, name, color FROM tags WHERE is_deleted = 0 ORDER BY name")
        .map_err(|e| e.to_string())?;
    let rows = stmt
        .query_map([], |row| {
            Ok(Tag {
                id: row.get(0)?,
                name: row.get(1)?,
                color: row.get(2)?,
            })
        })
        .map_err(|e| e.to_string())?;
    rows.collect::<Result<Vec<_>, _>>()
        .map_err(|e| e.to_string())
}

pub fn create_tag(state: &AppState, name: &str, color: i64) -> Result<(), String> {
    let db = state.db.lock().map_err(|e| e.to_string())?;
    db.execute(
        "INSERT INTO tags(id, name, color, is_deleted, created_at, updated_at)
         VALUES (?1, ?2, ?3, 0, ?4, ?4)",
        params![Uuid::new_v4().to_string(), name, color, now()],
    )
    .map_err(|e| e.to_string())?;
    Ok(())
}

pub fn set_book_tag(state: &AppState, book_id: &str, tag_id: &str, on: bool) -> Result<(), String> {
    let db = state.db.lock().map_err(|e| e.to_string())?;
    if on {
        db.execute(
            "INSERT OR REPLACE INTO book_tag_entries(tag_id, book_id, updated_at) VALUES (?1, ?2, ?3)",
            params![tag_id, book_id, now()],
        )
        .map_err(|e| e.to_string())?;
    } else {
        db.execute(
            "DELETE FROM book_tag_entries WHERE tag_id = ?1 AND book_id = ?2",
            params![tag_id, book_id],
        )
        .map_err(|e| e.to_string())?;
    }
    Ok(())
}

pub fn record_session(state: &AppState, book_id: &str, seconds: i64) -> Result<(), String> {
    let db = state.db.lock().map_err(|e| e.to_string())?;
    let ts = now();
    db.execute(
        "INSERT INTO reading_sessions(id, book_id, device_id, started_at, ended_at, duration_seconds, is_deleted, updated_at)
         VALUES (?1, ?2, ?3, ?4, ?4, ?5, 0, ?4)",
        params![Uuid::new_v4().to_string(), book_id, state.device_id, ts, seconds],
    )
    .map_err(|e| e.to_string())?;
    Ok(())
}

pub fn list_sessions(state: &AppState) -> Result<Vec<Session>, String> {
    let db = state.db.lock().map_err(|e| e.to_string())?;
    let mut stmt = db
        .prepare(
            "SELECT id, book_id, started_at, ended_at, duration_seconds FROM reading_sessions
             WHERE is_deleted = 0 ORDER BY started_at DESC",
        )
        .map_err(|e| e.to_string())?;
    let rows = stmt
        .query_map([], |row| {
            Ok(Session {
                id: row.get(0)?,
                book_id: row.get(1)?,
                started_at: row.get(2)?,
                ended_at: row.get(3)?,
                duration_seconds: row.get(4)?,
            })
        })
        .map_err(|e| e.to_string())?;
    rows.collect::<Result<Vec<_>, _>>()
        .map_err(|e| e.to_string())
}

pub fn kv_get(state: &AppState, key: &str) -> Result<Option<String>, String> {
    let db = state.db.lock().map_err(|e| e.to_string())?;
    db.query_row("SELECT value FROM kv WHERE key = ?1", params![key], |row| {
        row.get(0)
    })
    .optional()
    .map_err(|e| e.to_string())
}

pub fn kv_set(state: &AppState, key: &str, value: &str) -> Result<(), String> {
    let db = state.db.lock().map_err(|e| e.to_string())?;
    db.execute(
        "INSERT INTO kv(key, value) VALUES (?1, ?2)
         ON CONFLICT(key) DO UPDATE SET value = excluded.value",
        params![key, value],
    )
    .map_err(|e| e.to_string())?;
    Ok(())
}

pub fn kv_delete(state: &AppState, key: &str) -> Result<(), String> {
    let db = state.db.lock().map_err(|e| e.to_string())?;
    db.execute("DELETE FROM kv WHERE key = ?1", params![key])
        .map_err(|e| e.to_string())?;
    Ok(())
}

pub fn database_path(state: &AppState) -> String {
    state
        .root
        .join("leeef.sqlite")
        .to_string_lossy()
        .into_owned()
}

#[derive(Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct LibraryStats {
    pub books: i64,
    pub excerpts: i64,
    pub bookmarks: i64,
    pub pending_sync_operations: i64,
}

pub fn library_stats(state: &AppState) -> Result<LibraryStats, String> {
    let db = state.db.lock().map_err(|e| e.to_string())?;
    let count = |sql: &str| -> Result<i64, String> {
        db.query_row(sql, [], |row| row.get(0))
            .map_err(|e| e.to_string())
    };
    Ok(LibraryStats {
        books: count("SELECT count(*) FROM books WHERE is_deleted = 0")?,
        excerpts: count("SELECT count(*) FROM excerpts WHERE is_deleted = 0")?,
        bookmarks: count("SELECT count(*) FROM bookmarks WHERE is_deleted = 0")?,
        pending_sync_operations: count(
            "SELECT count(*) FROM sync_operations WHERE applied_at IS NULL",
        )?,
    })
}

#[derive(Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ReadingProgress {
    pub book_id: String,
    pub locator: String,
    pub progress: f64,
    pub chapter_title: Option<String>,
    pub page: Option<i64>,
    pub device_id: String,
    pub updated_at: String,
}

pub fn get_reading_progress(state: &AppState, book_id: &str) -> Result<ReadingProgress, String> {
    let db = state.db.lock().map_err(|e| e.to_string())?;
    db.query_row(
        "SELECT book_id, locator, progress, chapter_title, page, device_id, updated_at
         FROM reading_progresses WHERE book_id = ?1",
        params![book_id],
        |row| {
            Ok(ReadingProgress {
                book_id: row.get(0)?,
                locator: row.get(1)?,
                progress: row.get(2)?,
                chapter_title: row.get(3)?,
                page: row.get(4)?,
                device_id: row.get(5)?,
                updated_at: row.get(6)?,
            })
        },
    )
    .optional()
    .map_err(|e| e.to_string())?
    .ok_or_else(|| "reading progress does not exist".into())
}

pub fn shelf_book_ids(state: &AppState, shelf_id: &str) -> Result<Vec<String>, String> {
    let db = state.db.lock().map_err(|e| e.to_string())?;
    let mut stmt = db
        .prepare(
            "SELECT book_id FROM bookshelf_entries WHERE bookshelf_id = ?1 ORDER BY sort_order",
        )
        .map_err(|e| e.to_string())?;
    let ids = stmt
        .query_map(params![shelf_id], |row| row.get(0))
        .map_err(|e| e.to_string())?
        .collect::<Result<Vec<_>, _>>()
        .map_err(|e| e.to_string())?;
    Ok(ids)
}

pub fn audit(
    state: &AppState,
    action: &str,
    parameters: &serde_json::Value,
    result: &str,
) -> Result<(), String> {
    let db = state.db.lock().map_err(|e| e.to_string())?;
    db.execute(
        "INSERT INTO audit_events(id, caller, action, parameters_json, result, occurred_at)
         VALUES (?1, 'mcp', ?2, ?3, ?4, ?5)",
        params![
            Uuid::new_v4().to_string(),
            action,
            parameters.to_string(),
            result,
            now()
        ],
    )
    .map_err(|e| e.to_string())?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn excerpt_storage_preserves_internal_line_breaks() {
        let root = tempfile::tempdir().expect("temporary app data directory");
        let state = open(root.path().to_path_buf()).expect("open database");
        let book = import_book(
            &state,
            "line-breaks.txt",
            b"book",
            "Line breaks",
            None,
            "text/plain",
            None,
        )
        .expect("import book");
        let quote = "第一段\n第二行\n\n第二段";
        let note = "想法一\n想法二";

        upsert_excerpt(
            &state,
            &book.id,
            "epubcfi(/6/2)",
            quote,
            Some(note),
            "#c4a35a",
        )
        .expect("create excerpt");

        let excerpts = list_excerpts(&state, Some(&book.id)).expect("list excerpts");
        assert_eq!(excerpts.len(), 1);
        assert_eq!(excerpts[0].quote, quote);
        assert_eq!(excerpts[0].note.as_deref(), Some(note));
    }
}
