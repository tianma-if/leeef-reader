use crate::db::{self, AppState, EdgeEverExcerptNote};
use reqwest::{Client, Method, Url};
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use sha2::{Digest, Sha256};
use std::{
    collections::HashMap,
    sync::{Arc, Mutex, OnceLock},
    time::Duration,
};
use time::{format_description::FormatItem, macros::format_description, OffsetDateTime};

const DATE: &[FormatItem<'static>] = format_description!("[year]-[month]-[day]");

static SYNC_LOCKS: OnceLock<Mutex<HashMap<String, Arc<tokio::sync::Mutex<()>>>>> = OnceLock::new();

fn sync_lock(book_id: &str) -> Arc<tokio::sync::Mutex<()>> {
    let locks = SYNC_LOCKS.get_or_init(|| Mutex::new(HashMap::new()));
    let mut locks = locks
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner());
    locks
        .entry(book_id.to_string())
        .or_insert_with(|| Arc::new(tokio::sync::Mutex::new(())))
        .clone()
}

#[derive(Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
struct EdgeEverSettings {
    #[serde(default)]
    edge_ever_enabled: bool,
    #[serde(default)]
    edge_ever_endpoint: String,
    #[serde(default)]
    edge_ever_token: String,
    #[serde(default)]
    edge_ever_notebook_id: String,
}

#[derive(Clone)]
struct Config {
    base_url: Url,
    instance_url: String,
    token: String,
    notebook_id: String,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct SyncResult {
    pub configured: bool,
    pub synced: usize,
    pub skipped: usize,
    pub failed: usize,
    pub errors: Vec<String>,
}

#[derive(Clone, Deserialize, Serialize)]
pub struct Notebook {
    pub id: String,
    pub name: String,
}

#[derive(Deserialize)]
struct NotebookEnvelope {
    notebooks: Vec<Notebook>,
}

#[derive(Deserialize)]
struct MemoEnvelope {
    memo: Memo,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct Memo {
    id: String,
    revision: i64,
    content_hash: String,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct EditSession {
    id: String,
    base_revision: i64,
    base_content_hash: String,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct EditSessionEnvelope {
    edit_session: EditSession,
}

fn config(state: &AppState) -> Result<Option<Config>, String> {
    let raw = db::kv_get(state, "settings")?.unwrap_or_else(|| "{}".into());
    let settings: EdgeEverSettings = serde_json::from_str(&raw).map_err(|e| e.to_string())?;
    if !settings.edge_ever_enabled {
        return Ok(None);
    }
    if settings.edge_ever_endpoint.trim().is_empty() || settings.edge_ever_token.trim().is_empty() {
        return Err("EdgeEver 已启用，但实例地址或 API Token 未填写完整".into());
    }
    let mut base_url = Url::parse(settings.edge_ever_endpoint.trim())
        .map_err(|_| "EdgeEver 实例地址无效".to_string())?;
    let local_http = base_url.scheme() == "http"
        && matches!(base_url.host_str(), Some("localhost" | "127.0.0.1" | "::1"));
    if base_url.scheme() != "https" && !local_http {
        return Err("EdgeEver 实例必须使用 HTTPS（本机 localhost 除外）".into());
    }
    base_url.set_path("/");
    base_url.set_query(None);
    base_url.set_fragment(None);
    let instance_url = base_url.as_str().trim_end_matches('/').to_string();
    Ok(Some(Config {
        base_url,
        instance_url,
        token: settings.edge_ever_token.trim().to_string(),
        notebook_id: settings.edge_ever_notebook_id.trim().to_string(),
    }))
}

fn client() -> Result<Client, String> {
    Client::builder()
        .timeout(Duration::from_secs(20))
        .user_agent("Leeef-Reader/2")
        .build()
        .map_err(|e| e.to_string())
}

async fn request_json<T: for<'de> Deserialize<'de>>(
    client: &Client,
    config: &Config,
    method: Method,
    path: &str,
    body: Option<Value>,
) -> Result<T, String> {
    let url = config.base_url.join(path).map_err(|e| e.to_string())?;
    let mut request = client
        .request(method, url)
        .bearer_auth(&config.token)
        .header("Accept", "application/json");
    if let Some(body) = body {
        request = request.json(&body);
    }
    let response = request
        .send()
        .await
        .map_err(|e| format!("EdgeEver 连接失败：{e}"))?;
    let status = response.status();
    let bytes = response.bytes().await.map_err(|e| e.to_string())?;
    if !status.is_success() {
        let detail = serde_json::from_slice::<Value>(&bytes)
            .ok()
            .and_then(|value| {
                value
                    .pointer("/error/message")
                    .or_else(|| value.get("message"))
                    .and_then(Value::as_str)
                    .map(str::to_string)
            })
            .unwrap_or_else(|| status.to_string());
        return Err(format!(
            "EdgeEver 请求失败（{}）：{detail}",
            status.as_u16()
        ));
    }
    serde_json::from_slice(&bytes).map_err(|e| format!("EdgeEver 响应无效：{e}"))
}

fn excerpt_date(value: &str) -> String {
    value
        .parse::<i64>()
        .ok()
        .and_then(|seconds| OffsetDateTime::from_unix_timestamp(seconds).ok())
        .and_then(|date| date.format(DATE).ok())
        .unwrap_or_else(|| value.to_string())
}

fn markdown(state: &AppState, book_id: &str) -> Result<(String, String), String> {
    let book = db::list_books(state)?
        .into_iter()
        .find(|book| book.id == book_id)
        .ok_or_else(|| "book does not exist".to_string())?;
    let mut excerpts = db::list_excerpts(state, Some(book_id))?;
    excerpts.sort_by(|left, right| left.created_at.cmp(&right.created_at));
    let mut lines = vec![format!("# {}", book.title)];
    if let Some(author) = book.author.filter(|value| !value.trim().is_empty()) {
        lines.extend([String::new(), format!("作者：{author}")]);
    }
    lines.extend([String::new(), format!("书摘：{} 条", excerpts.len())]);
    for (index, excerpt) in excerpts.iter().enumerate() {
        lines.extend([
            String::new(),
            format!("## 书摘 {}", index + 1),
            String::new(),
        ]);
        lines.extend(
            excerpt
                .quote
                .replace("\r\n", "\n")
                .replace('\r', "\n")
                .trim_matches('\n')
                .split('\n')
                .map(|line| {
                    if line.is_empty() {
                        ">".into()
                    } else {
                        format!("> {line}")
                    }
                }),
        );
        if let Some(note) = excerpt.note.as_ref().filter(|value| !value.is_empty()) {
            lines.extend([
                String::new(),
                "**笔记**".into(),
                String::new(),
                note.replace("\r\n", "\n").replace('\r', "\n"),
            ]);
        }
        lines.extend([
            String::new(),
            format!("— 摘录于 {}", excerpt_date(&excerpt.created_at)),
        ]);
    }
    Ok((book.title, format!("{}\n", lines.join("\n"))))
}

fn digest(value: &str) -> String {
    hex::encode(Sha256::digest(value.as_bytes()))
}

pub async fn test(state: &AppState) -> Result<String, String> {
    let config = config(state)?.ok_or_else(|| "EdgeEver 同步尚未启用".to_string())?;
    let client = client()?;
    let path = format!(
        "api/v1/memos?notebookId={}&limit=1",
        urlencoding::encode(&config.notebook_id)
    );
    let _: Value = request_json(&client, &config, Method::GET, &path, None).await?;
    let _: NotebookEnvelope =
        request_json(&client, &config, Method::GET, "api/v1/notebooks", None).await?;
    Ok("连接成功，Token 具备 read:notebooks 与 read:memos 权限".into())
}

pub async fn notebooks(state: &AppState) -> Result<Vec<Notebook>, String> {
    let config = config(state)?.ok_or_else(|| "EdgeEver 同步尚未启用".to_string())?;
    let response: NotebookEnvelope =
        request_json(&client()?, &config, Method::GET, "api/v1/notebooks", None).await?;
    Ok(response.notebooks)
}

pub async fn sync_book(state: &AppState, book_id: &str) -> Result<bool, String> {
    let lock = sync_lock(book_id);
    let _guard = lock.lock().await;
    sync_book_unlocked(state, book_id).await
}

async fn sync_book_unlocked(state: &AppState, book_id: &str) -> Result<bool, String> {
    let Some(config) = config(state)? else {
        return Ok(false);
    };
    if config.notebook_id.is_empty() {
        return Err("尚未选择 EdgeEver 目标笔记本".into());
    }
    let (title, content) = markdown(state, book_id)?;
    let local_hash = digest(&content);
    let client = client()?;
    let existing = db::edgeever_excerpt_note(state, book_id, &config.instance_url)?;
    if existing
        .as_ref()
        .is_some_and(|link| link.local_content_hash == local_hash)
    {
        return Ok(false);
    }

    let memo = if let Some(link) = existing {
        let remote: MemoEnvelope = request_json(
            &client,
            &config,
            Method::GET,
            &format!("api/v1/memos/{}", urlencoding::encode(&link.memo_id)),
            None,
        )
        .await?;
        if remote.memo.revision != link.revision
            || remote.memo.content_hash != link.remote_content_hash
        {
            return Err("EdgeEver 笔记已在别处修改；为避免覆盖，已暂停该书同步".into());
        }
        let session: EditSessionEnvelope = request_json(
            &client,
            &config,
            Method::POST,
            &format!(
                "api/v1/memos/{}/edit-sessions",
                urlencoding::encode(&link.memo_id)
            ),
            Some(json!({})),
        )
        .await?;
        if session.edit_session.base_revision != link.revision
            || session.edit_session.base_content_hash != link.remote_content_hash
        {
            return Err("EdgeEver 笔记版本已变化；为避免覆盖，已暂停该书同步".into());
        }
        let updated: MemoEnvelope = request_json(
            &client,
            &config,
            Method::PATCH,
            &format!("api/v1/memos/{}", urlencoding::encode(&link.memo_id)),
            Some(json!({
                "expectedRevision": session.edit_session.base_revision,
                "expectedContentHash": session.edit_session.base_content_hash,
                "editSessionId": session.edit_session.id,
                "title": title,
                "contentMarkdown": content,
                "tags": ["Leeef Reader", "书摘"]
            })),
        )
        .await?;
        updated.memo
    } else {
        let created: MemoEnvelope = request_json(
            &client,
            &config,
            Method::POST,
            "api/v1/memos",
            Some(json!({
                "notebookId": config.notebook_id,
                "title": title,
                "contentMarkdown": content,
                "tags": ["Leeef Reader", "书摘"]
            })),
        )
        .await?;
        created.memo
    };
    db::save_edgeever_excerpt_note(
        state,
        &EdgeEverExcerptNote {
            book_id: book_id.to_string(),
            instance_url: config.instance_url,
            memo_id: memo.id,
            revision: memo.revision,
            remote_content_hash: memo.content_hash,
            local_content_hash: local_hash,
        },
    )?;
    Ok(true)
}

pub fn schedule(state: AppState, book_id: String) {
    tauri::async_runtime::spawn(async move {
        if let Err(error) = sync_book(&state, &book_id).await {
            let _ = db::save_edgeever_sync_error(&state, &book_id, &error);
        }
    });
}

pub async fn sync_all(state: &AppState) -> SyncResult {
    let configured_value = config(state).ok().flatten();
    let configured = configured_value.is_some();
    let mut result = SyncResult {
        configured,
        synced: 0,
        skipped: 0,
        failed: 0,
        errors: Vec::new(),
    };
    if !configured {
        result.errors.push("EdgeEver 同步尚未完整配置".into());
        return result;
    }
    let instance_url = configured_value
        .as_ref()
        .map(|value| value.instance_url.as_str())
        .unwrap_or_default();
    for book in db::list_books(state).unwrap_or_default() {
        let has_excerpts = !db::list_excerpts(state, Some(&book.id))
            .unwrap_or_default()
            .is_empty();
        let has_remote_note = db::edgeever_excerpt_note(state, &book.id, instance_url)
            .ok()
            .flatten()
            .is_some();
        if !has_excerpts && !has_remote_note {
            continue;
        }
        match sync_book(state, &book.id).await {
            Ok(true) => result.synced += 1,
            Ok(false) => result.skipped += 1,
            Err(error) => {
                result.failed += 1;
                let _ = db::save_edgeever_sync_error(state, &book.id, &error);
                result.errors.push(format!("{}：{error}", book.title));
            }
        }
    }
    result
}

#[cfg(test)]
mod tests {
    use super::*;
    use axum::{
        extract::State as AxumState,
        http::HeaderMap,
        routing::{get, post},
        Json, Router,
    };
    use std::sync::atomic::{AtomicUsize, Ordering};

    #[test]
    fn edgeever_markdown_contains_every_excerpt_date_and_line_break() {
        let root = tempfile::tempdir().expect("temporary app data directory");
        let state = db::open(root.path().to_path_buf()).expect("open database");
        let book = db::import_book(
            &state,
            "notes.txt",
            b"book",
            "书名",
            Some("作者"),
            "text/plain",
            None,
        )
        .expect("import book");
        db::upsert_excerpt(
            &state,
            &book.id,
            "epubcfi(/6/2)",
            "第一段\n\n第二段",
            None,
            "yellow",
        )
        .expect("create excerpt");

        let (_, output) = markdown(&state, &book.id).expect("render markdown");
        assert!(output.contains("> 第一段\n>\n> 第二段"));
        assert!(output.contains("— 摘录于 "));
        assert_eq!(output.matches("— 摘录于 ").count(), 1);
    }

    #[derive(Clone, Default)]
    struct MockEdgeEver {
        creates: Arc<AtomicUsize>,
        updates: Arc<AtomicUsize>,
    }

    #[tokio::test]
    async fn sync_creates_once_then_updates_the_same_memo() {
        let mock = MockEdgeEver::default();
        let app = Router::new()
            .route(
                "/api/v1/memos",
                post(
                    |AxumState(mock): AxumState<MockEdgeEver>, headers: HeaderMap| async move {
                        assert_eq!(headers.get("authorization").unwrap(), "Bearer token");
                        mock.creates.fetch_add(1, Ordering::SeqCst);
                        Json(json!({ "memo": {
                            "id": "memo-1", "revision": 1, "contentHash": "remote-hash-1"
                        }}))
                    },
                ),
            )
            .route(
                "/api/v1/memos/memo-1",
                get(|| async {
                    Json(json!({ "memo": {
                        "id": "memo-1", "revision": 1, "contentHash": "remote-hash-1"
                    }}))
                })
                .patch(
                    |AxumState(mock): AxumState<MockEdgeEver>, Json(body): Json<Value>| async move {
                        assert_eq!(body["expectedRevision"], 1);
                        assert_eq!(body["expectedContentHash"], "remote-hash-1");
                        assert_eq!(body["editSessionId"], "session-1");
                        mock.updates.fetch_add(1, Ordering::SeqCst);
                        Json(json!({ "memo": {
                            "id": "memo-1", "revision": 2, "contentHash": "remote-hash-2"
                        }}))
                    },
                ),
            )
            .route(
                "/api/v1/memos/memo-1/edit-sessions",
                post(|| async {
                    Json(json!({ "editSession": {
                        "id": "session-1", "baseRevision": 1,
                        "baseContentHash": "remote-hash-1"
                    }}))
                }),
            )
            .with_state(mock.clone());
        let listener = tokio::net::TcpListener::bind("127.0.0.1:0")
            .await
            .expect("bind mock EdgeEver");
        let address = listener.local_addr().expect("mock address");
        tokio::spawn(async move { axum::serve(listener, app).await.expect("mock server") });

        let root = tempfile::tempdir().expect("temporary app data directory");
        let state = db::open(root.path().to_path_buf()).expect("open database");
        db::kv_set(
            &state,
            "settings",
            &json!({
                "edgeEverEnabled": true,
                "edgeEverEndpoint": format!("http://{address}"),
                "edgeEverToken": "token",
                "edgeEverNotebookId": "notebook-1"
            })
            .to_string(),
        )
        .expect("save settings");
        let book = db::import_book(
            &state,
            "sync.txt",
            b"book",
            "同步测试",
            None,
            "text/plain",
            None,
        )
        .expect("import book");
        let excerpt_id =
            db::upsert_excerpt(&state, &book.id, "epubcfi(/6/2)", "原文", None, "yellow")
                .expect("create excerpt");

        assert!(sync_book(&state, &book.id).await.expect("first sync"));
        db::update_excerpt(
            &state,
            &excerpt_id,
            Some("修改后的原文"),
            Some("新增笔记"),
            "yellow",
        )
        .expect("update excerpt");
        assert!(sync_book(&state, &book.id).await.expect("second sync"));
        assert_eq!(mock.creates.load(Ordering::SeqCst), 1);
        assert_eq!(mock.updates.load(Ordering::SeqCst), 1);
    }
}
