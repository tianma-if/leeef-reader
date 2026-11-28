mod note;

use crate::db::{self, AppState, EdgeEverExcerptNote};
use note::{ExcerptNote, LegacyBody};
use reqwest::{Client, Method, StatusCode, Url};
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use sha2::{Digest, Sha256};
use std::{
    collections::HashMap,
    sync::{Arc, Mutex, OnceLock},
    time::{Duration, SystemTime, UNIX_EPOCH},
};
const IMPORT_ID: &str = "b87b6dfa-1284-4382-9bb5-cea4e59e0ed4";
const FORMAT_VERSION: &str = "v2:";
const INITIAL_SYNC_KEY: &str = "edgeever_initial_sync_scheduled";

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
pub(crate) struct EdgeEverSettings {
    #[serde(default)]
    edge_ever_enabled: bool,
    #[serde(default)]
    edge_ever_endpoint: String,
    #[serde(default)]
    edge_ever_token: String,
    #[serde(default)]
    edge_ever_notebook_id: String,
    #[serde(default)]
    edge_ever_notebook_label: Option<Notebook>,
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
    #[serde(skip_serializing_if = "Option::is_none")]
    slug: Option<String>,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct SyncStatus {
    enabled: bool,
    configured: bool,
    notebook_selected: bool,
    notebook_name: Option<String>,
    target_key: Option<String>,
    last_attempt: Option<SyncAttempt>,
}

#[derive(Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
struct SyncAttempt {
    finished_at: u64,
    succeeded: bool,
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
    content_json: Value,
    content_markdown: String,
    #[serde(default)]
    is_deleted: bool,
}

#[derive(Deserialize)]
struct ImportEnvelope {
    results: Vec<ImportResult>,
}

#[derive(Deserialize)]
struct ImportResult {
    status: String,
    memo: Option<Memo>,
    error: Option<String>,
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

fn load_settings(state: &AppState) -> Result<EdgeEverSettings, String> {
    let raw = db::kv_get(state, "settings")?.unwrap_or_else(|| "{}".into());
    serde_json::from_str(&raw).map_err(|e| e.to_string())
}

fn config(state: &AppState) -> Result<Option<Config>, String> {
    config_from_settings(&load_settings(state)?)
}

fn config_from_settings(settings: &EdgeEverSettings) -> Result<Option<Config>, String> {
    if !settings.edge_ever_enabled {
        return Ok(None);
    }
    if settings.edge_ever_endpoint.trim().is_empty() || settings.edge_ever_token.trim().is_empty() {
        return Err("EdgeEver 已启用，但实例地址或 API Token 未填写完整".into());
    }
    let base_url = instance_base_url(&settings.edge_ever_endpoint)?;
    let instance_url = base_url.as_str().trim_end_matches('/').to_string();
    Ok(Some(Config {
        base_url,
        instance_url,
        token: settings.edge_ever_token.trim().to_string(),
        notebook_id: settings.edge_ever_notebook_id.trim().to_string(),
    }))
}

pub(crate) fn persist_settings(state: &AppState, value: &Value) -> Result<(), String> {
    let raw = value.to_string();
    let is_configured = |raw: &str| {
        serde_json::from_str::<EdgeEverSettings>(raw)
            .is_ok_and(|settings| matches!(config_from_settings(&settings), Ok(Some(_))))
    };

    let mut db = state.db.lock().map_err(|e| e.to_string())?;
    let tx = db.transaction().map_err(|e| e.to_string())?;
    let mut queued = false;
    if db::kv_get_on(&tx, INITIAL_SYNC_KEY)?.is_none() {
        // Treat an already enabled installation as initialized when upgrading.
        let was_configured = db::kv_get_on(&tx, "settings")?
            .as_deref()
            .is_some_and(is_configured);
        if was_configured || is_configured(&raw) {
            if !was_configured {
                db::queue_existing_edgeever_books(&tx)?;
                queued = true;
            }
            db::kv_set_on(&tx, INITIAL_SYNC_KEY, "1")?;
        }
    }
    db::kv_set_on(&tx, "settings", &raw)?;
    tx.commit().map_err(|e| e.to_string())?;
    if queued {
        state.edgeever_sync_trigger.notify_one();
    }
    Ok(())
}

fn instance_base_url(value: &str) -> Result<Url, String> {
    let mut base_url = Url::parse(value.trim()).map_err(|_| "EdgeEver 实例地址无效".to_string())?;
    let local_http = base_url.scheme() == "http"
        && matches!(base_url.host_str(), Some("localhost" | "127.0.0.1" | "::1"));
    if base_url.scheme() != "https" && !local_http {
        return Err("EdgeEver 实例必须使用 HTTPS（本机 localhost 除外）".into());
    }
    base_url.set_path("/");
    base_url.set_query(None);
    base_url.set_fragment(None);
    Ok(base_url)
}

fn target_key(base_url: &Url, notebook_id: &str) -> String {
    digest(&format!("{base_url}\n{notebook_id}"))
}

pub fn status(state: &AppState) -> Result<SyncStatus, String> {
    let settings = load_settings(state)?;
    let notebook_id = settings.edge_ever_notebook_id.trim();
    let notebook_selected = !notebook_id.is_empty();
    let target_key = instance_base_url(&settings.edge_ever_endpoint)
        .ok()
        .map(|base_url| target_key(&base_url, notebook_id));
    let configured = target_key.is_some() && !settings.edge_ever_token.trim().is_empty();
    let (cached_name, last_attempt) = if let Some(key) = &target_key {
        (
            db::kv_get(state, &format!("edgeever_notebook_name:{key}"))?,
            db::kv_get(state, &format!("edgeever_last_attempt:{key}"))?
                .and_then(|value| serde_json::from_str(&value).ok()),
        )
    } else {
        (None, None)
    };
    let notebook_name = if notebook_selected {
        cached_name.or_else(|| {
            settings
                .edge_ever_notebook_label
                .filter(|notebook| notebook.id == notebook_id && !notebook.name.trim().is_empty())
                .map(|notebook| notebook.name)
        })
    } else {
        Some("等待分类".into())
    };
    Ok(SyncStatus {
        enabled: settings.edge_ever_enabled,
        configured,
        notebook_selected,
        notebook_name,
        target_key: target_key.filter(|_| configured && settings.edge_ever_enabled),
        last_attempt,
    })
}

fn client() -> Result<Client, String> {
    Client::builder()
        .timeout(Duration::from_secs(20))
        .redirect(reqwest::redirect::Policy::none())
        .user_agent("Leeef-Reader/2")
        .build()
        .map_err(|e| e.to_string())
}

struct RequestError {
    status: Option<StatusCode>,
    message: String,
}

impl From<String> for RequestError {
    fn from(message: String) -> Self {
        Self {
            status: None,
            message,
        }
    }
}

impl From<RequestError> for String {
    fn from(error: RequestError) -> Self {
        error.message
    }
}

async fn request_json<T: for<'de> Deserialize<'de>>(
    client: &Client,
    config: &Config,
    method: Method,
    path: &str,
    body: Option<Value>,
) -> Result<T, RequestError> {
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
        return Err(RequestError {
            status: Some(status),
            message: format!("EdgeEver 请求失败（{}）：{detail}", status.as_u16()),
        });
    }
    serde_json::from_slice(&bytes).map_err(|e| format!("EdgeEver 响应无效：{e}").into())
}

fn digest(value: &str) -> String {
    hex::encode(Sha256::digest(value.as_bytes()))
}

async fn list_notebooks(client: &Client, config: &Config) -> Result<Vec<Notebook>, String> {
    let response: NotebookEnvelope =
        request_json(client, config, Method::GET, "api/v1/notebooks", None).await?;
    Ok(response.notebooks)
}

fn inbox_notebook_id(notebooks: &[Notebook]) -> Result<&str, String> {
    notebooks
        .iter()
        .find(|notebook| {
            notebook.id == "nb_inbox"
                || (notebook.id.starts_with("ws_") && notebook.id.ends_with("_inbox"))
        })
        .or_else(|| notebooks.iter().find(|notebook| notebook.slug.as_deref() == Some("inbox")))
        .map(|notebook| notebook.id.as_str())
        .ok_or_else(|| "无法访问 EdgeEver 的「等待分类」，请检查 Token 的笔记本权限或选择其他笔记本".into())
}

fn command_config(state: &AppState, draft: Option<EdgeEverSettings>) -> Result<Config, String> {
    match draft {
        Some(settings) => config_from_settings(&settings),
        None => config(state),
    }?
    .ok_or_else(|| "EdgeEver 同步尚未启用".to_string())
}

pub(crate) async fn test(state: &AppState, draft: Option<EdgeEverSettings>) -> Result<String, String> {
    let config = command_config(state, draft)?;
    let client = client()?;
    let notebooks = list_notebooks(&client, &config).await?;
    let notebook_id = if config.notebook_id.is_empty() {
        inbox_notebook_id(&notebooks)?
    } else {
        &config.notebook_id
    };
    let path = format!(
        "api/v1/memos?notebookId={}&limit=1",
        urlencoding::encode(notebook_id)
    );
    let _: Value = request_json(&client, &config, Method::GET, &path, None).await?;
    Ok("连接成功，Token 具备 read:notebooks 与 read:memos 权限".into())
}

pub(crate) async fn notebooks(
    state: &AppState,
    draft: Option<EdgeEverSettings>,
) -> Result<Vec<Notebook>, String> {
    let config = command_config(state, draft)?;
    let notebooks = list_notebooks(&client()?, &config).await?;
    if let Some(notebook) = notebooks
        .iter()
        .find(|notebook| notebook.id == config.notebook_id)
    {
        let key = target_key(&config.base_url, &config.notebook_id);
        let _ = db::kv_set(
            state,
            &format!("edgeever_notebook_name:{key}"),
            &notebook.name,
        );
    }
    Ok(notebooks)
}

pub async fn sync_book(state: &AppState, book_id: &str) -> Result<bool, String> {
    let lock = sync_lock(book_id);
    let _guard = lock.lock().await;
    let Some(config) = config(state)? else {
        return Ok(false);
    };
    let generation = db::edgeever_pending_generation(state, book_id)?;
    let result = sync_book_unlocked(state, book_id, &config).await;
    if !matches!(result, Ok(None)) {
        let key = target_key(&config.base_url, &config.notebook_id);
        let attempt = SyncAttempt {
            finished_at: SystemTime::now()
                .duration_since(UNIX_EPOCH)
                .unwrap_or_default()
                .as_millis() as u64,
            succeeded: result.is_ok(),
        };
        if let Ok(value) = serde_json::to_string(&attempt) {
            let _ = db::kv_set(state, &format!("edgeever_last_attempt:{key}"), &value);
        }
    }
    let changed = result?.unwrap_or(false);
    if let Some(generation) = generation {
        db::finish_edgeever_book(state, book_id, generation)?;
    }
    Ok(changed)
}

async fn sync_book_unlocked(
    state: &AppState,
    book_id: &str,
    config: &Config,
) -> Result<Option<bool>, String> {
    let existing = db::edgeever_excerpt_note(state, book_id, &config.instance_url)?;
    let excerpts = db::list_excerpts(state, Some(book_id))?;
    if excerpts.is_empty() && existing.is_none() {
        return Ok(None);
    }
    let book = db::list_books(state)?
        .into_iter()
        .find(|book| book.id == book_id)
        .ok_or("book does not exist")?;
    let note = ExcerptNote::new(book.author.as_deref(), &excerpts);
    let local_hash = format!("{FORMAT_VERSION}{}", digest(&note.markdown));
    let client = client()?;
    let (memo, changed) = if let Some(link) = &existing {
        update_memo(
            &client,
            config,
            &link.memo_id,
            &note,
            &local_hash,
            Some(link),
        )
        .await?
    } else {
        let notebook_id = if config.notebook_id.is_empty() {
            let notebooks = list_notebooks(&client, config).await?;
            inbox_notebook_id(&notebooks)?.to_string()
        } else {
            config.notebook_id.clone()
        };
        let title: String = book
            .title
            .trim()
            .chars()
            .scan(0, |length, ch| {
                *length += ch.len_utf16();
                (*length <= 160).then_some(ch)
            })
            .collect();
        let response: ImportEnvelope = request_json(
            &client,
            config,
            Method::POST,
            "api/v1/imports/memos",
            Some(json!({
                "importId": IMPORT_ID,
                "format": "markdown",
                "notebookId": notebook_id,
                "items": [{
                    "externalId": book.sha256,
                    "title": title,
                    "contentMarkdown": note.markdown,
                    "tags": ["Leeef Reader", "书摘"]
                }]
            })),
        )
        .await?;
        let result = response
            .results
            .into_iter()
            .next()
            .ok_or("EdgeEver 未返回导入结果")?;
        let memo = result.memo.ok_or_else(|| {
            result
                .error
                .unwrap_or_else(|| "EdgeEver 未返回可同步的笔记".into())
        })?;
        if memo.is_deleted {
            return Err("EdgeEver 中的书摘笔记已移到废纸篓".into());
        }
        if result.status == "created" {
            (memo, true)
        } else {
            update_memo(&client, config, &memo.id, &note, &local_hash, None).await?
        }
    };
    db::save_edgeever_excerpt_note(
        state,
        &EdgeEverExcerptNote {
            book_id: book_id.to_string(),
            instance_url: config.instance_url.clone(),
            memo_id: memo.id,
            revision: memo.revision,
            remote_content_hash: memo.content_hash,
            local_content_hash: local_hash,
        },
    )?;
    Ok(Some(changed))
}

async fn update_memo(
    client: &Client,
    config: &Config,
    memo_id: &str,
    note: &ExcerptNote,
    local_hash: &str,
    link: Option<&EdgeEverExcerptNote>,
) -> Result<(Memo, bool), String> {
    let path = format!("api/v1/memos/{}", urlencoding::encode(memo_id));
    let edit_path = format!("{path}/edit-sessions");
    for _ in 0..4 {
        let remote: MemoEnvelope = request_json(client, config, Method::GET, &path, None).await?;
        let remote = remote.memo;
        let prior_body_matches =
            link.is_some_and(|link| link.remote_content_hash == remote.content_hash);
        if prior_body_matches && link.is_some_and(|link| link.local_content_hash == local_hash) {
            return Ok((remote, false));
        }
        let legacy = match link {
            Some(link) if !link.local_content_hash.starts_with(FORMAT_VERSION) => {
                if prior_body_matches {
                    LegacyBody::Unchanged
                } else {
                    LegacyBody::Edited
                }
            }
            _ => LegacyBody::Unknown,
        };
        let (merged, markdown) =
            note.merge(&remote.content_json, &remote.content_markdown, legacy)?;
        if merged == remote.content_json
            && markdown
                .as_deref()
                .is_none_or(|markdown| markdown == remote.content_markdown)
        {
            return Ok((remote, false));
        }

        let session: EditSessionEnvelope =
            request_json(client, config, Method::POST, &edit_path, Some(json!({}))).await?;
        let session = session.edit_session;
        if session.base_revision != remote.revision
            || session.base_content_hash != remote.content_hash
        {
            continue;
        }
        let mut body = json!({
            "expectedRevision": session.base_revision,
            "expectedContentHash": session.base_content_hash,
            "editSessionId": session.id,
            "contentJson": merged
        });
        if let Some(markdown) = markdown {
            body["contentMarkdown"] = json!(markdown);
        }
        let updated =
            request_json::<MemoEnvelope>(client, config, Method::PATCH, &path, Some(body)).await;
        match updated {
            Ok(updated) => return Ok((updated.memo, true)),
            Err(error) if error.status == Some(StatusCode::CONFLICT) => continue,
            Err(error) => return Err(error.into()),
        }
    }
    Err("EdgeEver 笔记在同步期间连续变动，请稍后重试".into())
}

pub fn schedule(state: AppState, book_id: String) {
    if !matches!(config(&state), Ok(Some(_))) {
        return;
    }
    let _ = db::queue_edgeever_book(&state, &book_id);
    tauri::async_runtime::spawn(async move {
        if let Err(error) = sync_book(&state, &book_id).await {
            let _ = db::save_edgeever_sync_error(&state, &book_id, &error);
        }
    });
}

pub fn start_background(state: AppState) {
    tauri::async_runtime::spawn(async move {
        loop {
            tokio::select! {
                _ = tokio::time::sleep(Duration::from_secs(30)) => {},
                _ = state.edgeever_sync_trigger.notified() => {},
            }
            if !matches!(config(&state), Ok(Some(_))) {
                continue;
            }
            for book_id in db::pending_edgeever_books(&state).unwrap_or_default() {
                if let Err(error) = sync_book(&state, &book_id).await {
                    let _ = db::save_edgeever_sync_error(&state, &book_id, &error);
                }
            }
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
        extract::{Query, State as AxumState},
        http::HeaderMap,
        response::IntoResponse,
        routing::{get, post},
        Json, Router,
    };
    use std::sync::atomic::{AtomicBool, AtomicUsize, Ordering};

    fn excerpt_date(text: &str) -> bool {
        let mut parts = text.split('-');
        let year = parts.next();
        let month = parts.next();
        let day = parts.next();
        matches!(
            (year, month, day, parts.next()),
            (Some(year), Some(month), Some(day), None)
                if year.len() == 4
                    && month.len() == 2
                    && day.len() == 2
                    && [year, month, day]
                        .into_iter()
                        .all(|part| part.bytes().all(|byte| byte.is_ascii_digit()))
        )
    }

    #[test]
    fn edgeever_markdown_groups_excerpts_in_order_and_places_annotations_under_quotes() {
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
        let locators = [
            ("epubcfi(/6/10!/4,/1:0,/1:8)", "后面的章节", None, "第三章"),
            (
                "epubcfi(/6/2[a^,b]!/4,/1:10,/1:12)",
                "补划的书摘",
                None,
                "第一章",
            ),
            (
                "epubcfi(/6/2[a^,b]!/4,/1:2,/1:10)",
                "第一段\n\n第二段",
                Some("我的批注"),
                "第一章",
            ),
        ];
        for (locator, quote, annotation, chapter) in locators {
            db::upsert_excerpt(&state, &book.id, locator, quote, annotation, "yellow").unwrap();
            db::save_excerpt_chapters(
                &state,
                &book.id,
                &[(
                    locator.into(),
                    db::ExcerptChapter {
                        key: chapter.into(),
                        title: chapter.into(),
                    },
                )],
            )
            .unwrap();
        }
        let mut excerpts = db::list_excerpts(&state, Some(&book.id)).unwrap();
        for excerpt in &mut excerpts {
            excerpt.created_at = match excerpt.quote.as_str() {
                "补划的书摘" => "2026-11-27T01:41:05+08:00",
                _ => "1795714865",
            }
            .into();
        }
        let note = ExcerptNote::new(book.author.as_deref(), &excerpts);
        let instant = time::macros::datetime!(2026-11-26 17:41:05 UTC);
        let local = instant.to_offset(time::UtcOffset::local_offset_at(instant).unwrap());
        let timestamp = format!(
            "{:04}-{:02}-{:02}",
            local.year(),
            u8::from(local.month()),
            local.day(),
        );
        let output = note.markdown;
        assert!(output.contains(&format!(
            "### 第一章\n\n> 第一段\n>\n> 第二段\n>\n> {timestamp}\n\n**批注** 我的批注\n\n> 补划的书摘"
        )));
        assert!(output.contains(&format!(
            "> 补划的书摘\n>\n> {timestamp}\n\n### 第三章\n\n> 后面的章节"
        )));
        assert_eq!(output.matches(&format!("> {timestamp}")).count(), 3);
        assert!(!output.contains("摘录于"));
        let timestamps: Vec<_> = note
            .nodes
            .iter()
            .filter(|node| node["type"] == "blockquote")
            .map(|node| {
                let footer = node["content"].as_array().unwrap().last().unwrap();
                footer["content"][0]["text"].as_str().unwrap()
            })
            .collect();
        assert_eq!(timestamps, [timestamp.as_str(); 3]);
        assert_eq!(output.matches("### 第一章").count(), 1);
        for omitted in ["页码", "读后感"] {
            assert!(!output.contains(omitted));
        }
    }

    #[test]
    fn edgeever_migrates_an_edited_legacy_note_without_removing_surrounding_blocks() {
        let before = json!({ "type": "image", "attrs": { "src": "edgeever://resource/test", "width": 240 } });
        let after =
            json!({ "type": "paragraph", "content": [{ "type": "text", "text": "手写正文" }] });
        let legacy = json!({ "type": "doc", "content": [
            before,
            { "type": "heading", "attrs": { "level": 1 }, "content": [{ "type": "text", "text": "旧书名" }] },
            { "type": "paragraph", "content": [{ "type": "text", "text": "书摘：1 条" }] },
            { "type": "heading", "attrs": { "level": 2 }, "content": [{ "type": "text", "text": "书摘 1" }] },
            { "type": "blockquote", "content": [{ "type": "paragraph", "content": [{ "type": "text", "text": "原来的书摘" }] }] },
            { "type": "paragraph", "content": [{ "type": "text", "text": "— 摘录于 2026-11-26" }] },
            after
        ]});
        let note = ExcerptNote::new(None, &[]);
        let legacy_markdown = "![封面](edgeever://resource/test)\n\n# 旧书名\n\n书摘：1 条\n\n## 书摘 1\n\n> 原来的书摘\n\n— 摘录于 2026-11-26\n\n<!-- 手写备注 -->\n手写正文";
        let (merged, markdown) = note
            .merge(&legacy, legacy_markdown, LegacyBody::Edited)
            .unwrap();
        let blocks = merged["content"].as_array().unwrap();
        assert_eq!(blocks.first(), Some(&before));
        assert_eq!(blocks.last(), Some(&after));
        assert_eq!(&blocks[1..blocks.len() - 1], note.nodes.as_slice());
        let markdown = markdown.unwrap();
        assert!(markdown.starts_with("![封面](edgeever://resource/test)\n\n"));
        assert!(markdown.ends_with("\n\n<!-- 手写备注 -->\n手写正文"));
        assert_eq!(
            note.merge(&merged, &markdown, LegacyBody::Unknown).unwrap(),
            (merged, Some(markdown))
        );
    }

    #[derive(Clone, Default)]
    struct MockEdgeEver {
        creates: Arc<AtomicUsize>,
        updates: Arc<AtomicUsize>,
        import_notebooks: Arc<Mutex<Vec<String>>>,
        memo: Arc<Mutex<Value>>,
        fail_next_update: Arc<AtomicBool>,
        fail_next_import: Arc<AtomicBool>,
    }

    #[tokio::test]
    async fn sync_reuses_the_memo_and_overwrites_only_excerpts_after_a_concurrent_edit() {
        let mock = MockEdgeEver::default();
        let app = Router::new()
            .route(
                "/api/v1/notebooks",
                get(|| async {
                    Json(json!({ "notebooks": [
                        { "id": "notebook-1", "name": "阅读摘录" },
                        { "id": "ws_default_inbox", "name": "Inbox", "slug": "inbox" }
                    ] }))
                }),
            )
            .route(
                "/api/v1/memos",
                get(|Query(query): Query<HashMap<String, String>>| async move {
                    assert_eq!(query["notebookId"], "ws_default_inbox");
                    Json(json!({ "memos": [] }))
                }),
            )
            .route(
                "/api/v1/imports/memos",
                post(
                    |AxumState(mock): AxumState<MockEdgeEver>, headers: HeaderMap, Json(body): Json<Value>| async move {
                        assert_eq!(headers.get("authorization").unwrap(), "Bearer token");
                        assert_eq!(body["importId"], IMPORT_ID);
                        assert_eq!(body["format"], "markdown");
                        assert_eq!(body["items"][0]["externalId"], digest("book"));
                        assert_eq!(body["items"][0]["title"], "同步测试");
                        let markdown = body["items"][0]["contentMarkdown"].as_str().unwrap();
                        let timestamp = markdown
                            .lines()
                            .find_map(|line| line.strip_prefix("> ").filter(|text| excerpt_date(text)))
                            .expect("timestamp in the first import");
                        assert!(markdown.contains("> 原文\n>\n"));
                        mock.import_notebooks.lock().unwrap().push(body["notebookId"].as_str().unwrap().to_string());
                        if mock.fail_next_import.swap(false, Ordering::SeqCst) {
                            return StatusCode::SERVICE_UNAVAILABLE.into_response();
                        }
                        let mut memo = mock.memo.lock().unwrap();
                        if !memo.is_null() {
                            return Json(json!({ "results": [{ "status": "skipped", "memo": *memo }] })).into_response();
                        }
                        mock.creates.fetch_add(1, Ordering::SeqCst);
                        let mut nodes = ExcerptNote::new(None, &[]).nodes;
                        nodes.insert(2, json!({
                            "type": "blockquote", "content": [
                                { "type": "paragraph", "content": [{ "type": "text", "text": "原文" }] },
                                { "type": "paragraph", "content": [{ "type": "text", "text": timestamp }] },
                            ]
                        }));
                        *memo = json!({
                            "id": "memo-1", "revision": 1, "contentHash": "remote-hash-1",
                            "contentMarkdown": body["items"][0]["contentMarkdown"],
                            "title": "同步测试", "tags": ["书摘"], "contentJson": { "type": "doc", "content": nodes }
                        });
                        Json(json!({ "results": [{ "status": "created", "memo": *memo }] })).into_response()
                    },
                ),
            )
            .route(
                "/api/v1/memos/memo-1",
                get(|AxumState(mock): AxumState<MockEdgeEver>| async move {
                    Json(json!({ "memo": *mock.memo.lock().unwrap() }))
                })
                .patch(
                    |AxumState(mock): AxumState<MockEdgeEver>, Json(body): Json<Value>| async move {
                        assert!(body.get("title").is_none());
                        assert!(body.get("tags").is_none());
                        if mock.fail_next_update.swap(false, Ordering::SeqCst) {
                            return StatusCode::SERVICE_UNAVAILABLE.into_response();
                        }
                        let mut memo = mock.memo.lock().unwrap();
                        assert_eq!(body["expectedRevision"], memo["revision"]);
                        assert_eq!(body["expectedContentHash"], memo["contentHash"]);
                        assert_eq!(body["editSessionId"], "session-1");
                        let revision = memo["revision"].as_i64().unwrap() + 1;
                        memo["revision"] = json!(revision);
                        memo["contentHash"] = json!(format!("remote-hash-{revision}"));
                        if mock.updates.fetch_add(1, Ordering::SeqCst) == 0 {
                            memo["contentJson"]["content"].as_array_mut().unwrap().push(json!({
                                "type": "paragraph", "content": [{ "type": "text", "text": "并发写入的正文" }]
                            }));
                            memo["contentMarkdown"] = json!(format!("{}\n\n并发写入的正文", memo["contentMarkdown"].as_str().unwrap()));
                            return (StatusCode::CONFLICT, Json(json!({ "error": { "message": "retry" } }))).into_response();
                        }
                        memo["contentJson"] = body["contentJson"].clone();
                        memo["contentMarkdown"] = body["contentMarkdown"].clone();
                        Json(json!({ "memo": *memo })).into_response()
                    },
                ),
            )
            .route(
                "/api/v1/memos/memo-1/edit-sessions",
                post(|AxumState(mock): AxumState<MockEdgeEver>| async move {
                    let memo = mock.memo.lock().unwrap();
                    Json(json!({ "editSession": {
                        "id": "session-1", "baseRevision": memo["revision"],
                        "baseContentHash": memo["contentHash"]
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
        let settings = json!({
                "edgeEverEnabled": true,
                "edgeEverEndpoint": format!("http://{address}"),
                "edgeEverToken": "token",
                "edgeEverNotebookId": "notebook-1"
        });
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
        let created_at = db::list_excerpts(&state, Some(&book.id)).unwrap()[0]
            .created_at
            .clone();

        let draft = serde_json::from_value(settings.clone()).unwrap();
        notebooks(&state, Some(draft)).await.unwrap();
        assert!(!status(&state).unwrap().enabled);
        assert!(db::pending_edgeever_books(&state).unwrap().is_empty());

        let mut incomplete_settings = settings.clone();
        incomplete_settings["edgeEverToken"] = json!("");
        crate::trusted_sync::save_settings(&state, incomplete_settings).unwrap();
        assert!(db::pending_edgeever_books(&state).unwrap().is_empty());

        crate::trusted_sync::save_settings(&state, settings.clone()).unwrap();
        tokio::time::timeout(Duration::from_secs(1), state.edgeever_sync_trigger.notified())
            .await
            .expect("first valid save wakes the sync worker");
        assert_eq!(
            db::pending_edgeever_books(&state).unwrap(),
            [book.id.clone()]
        );
        let initial = status(&state).unwrap();
        assert!(initial.enabled && initial.configured && initial.notebook_selected);
        assert!(initial.last_attempt.is_none());
        assert_eq!(initial.notebook_name.as_deref(), Some("阅读摘录"));

        mock.fail_next_import.store(true, Ordering::SeqCst);
        assert!(sync_book(&state, &book.id).await.is_err());
        assert!(!status(&state).unwrap().last_attempt.unwrap().succeeded);
        assert_eq!(
            db::pending_edgeever_books(&state).unwrap(),
            [book.id.clone()]
        );
        assert!(
            db::edgeever_excerpt_note(&state, &book.id, &format!("http://{address}"))
                .unwrap()
                .is_none()
        );
        assert!(sync_book(&state, &book.id).await.expect("first sync"));
        assert!(status(&state).unwrap().last_attempt.unwrap().succeeded);
        crate::trusted_sync::save_settings(&state, settings.clone()).unwrap();
        let mut disabled_settings = settings.clone();
        disabled_settings["edgeEverEnabled"] = json!(false);
        crate::trusted_sync::save_settings(&state, disabled_settings).unwrap();
        crate::trusted_sync::save_settings(&state, settings.clone()).unwrap();
        assert!(db::pending_edgeever_books(&state).unwrap().is_empty());
        {
            let mut memo = mock.memo.lock().unwrap();
            memo["title"] = json!("手动改过的标题");
            memo["tags"] = json!(["手动改过的标签"]);
            memo["revision"] = json!(2);
            memo["contentHash"] = json!("remote-hash-2");
            memo["contentMarkdown"] = json!(format!(
                "<!-- 用户备注 -->\n![图](edgeever://resource/example)\n\n{}",
                memo["contentMarkdown"]
                    .as_str()
                    .unwrap()
                    .replace("> 原文", "> EdgeEver 手改的书摘")
            ));
            let nodes = memo["contentJson"]["content"].as_array_mut().unwrap();
            nodes[2]["content"][0]["content"][0]["text"] = json!("EdgeEver 手改的书摘");
            nodes.insert(
                0,
                json!({
                    "type": "image", "attrs": { "src": "edgeever://resource/example", "width": 240 }
                }),
            );
        }
        // A manual sync restores the source excerpt even without a local edit.
        assert!(sync_book(&state, &book.id)
            .await
            .expect("refresh the same excerpt"));
        {
            let memo = mock.memo.lock().unwrap();
            assert_eq!(memo["title"], "手动改过的标题");
            assert_eq!(memo["tags"], json!(["手动改过的标签"]));
            let blocks = memo["contentJson"]["content"].as_array().unwrap();
            assert_eq!(blocks.first().unwrap()["attrs"]["width"], 240);
            assert_eq!(
                blocks.last().unwrap()["content"][0]["text"],
                "并发写入的正文"
            );
            assert!(memo["contentMarkdown"]
                .as_str()
                .unwrap()
                .starts_with("<!-- 用户备注 -->\n"));
            assert!(memo["contentMarkdown"]
                .as_str()
                .unwrap()
                .ends_with("\n\n并发写入的正文"));
            assert!(memo["contentJson"].to_string().contains("原文"));
            assert!(!memo["contentJson"]
                .to_string()
                .contains("EdgeEver 手改的书摘"));
        }
        db::update_excerpt(
            &state,
            &excerpt_id,
            Some("修改后的原文"),
            Some("新增笔记"),
            "yellow",
        )
        .expect("update excerpt");
        db::queue_edgeever_book(&state, &book.id).unwrap();
        mock.fail_next_update.store(true, Ordering::SeqCst);
        assert!(sync_book(&state, &book.id).await.is_err());
        assert_eq!(
            db::pending_edgeever_books(&state).unwrap(),
            [book.id.clone()]
        );
        let state = db::open(root.path().to_path_buf()).unwrap();
        assert!(!status(&state).unwrap().last_attempt.unwrap().succeeded);
        assert_eq!(
            status(&state).unwrap().notebook_name.as_deref(),
            Some("阅读摘录")
        );
        assert_eq!(
            db::pending_edgeever_books(&state).unwrap(),
            [book.id.clone()]
        );
        assert!(sync_book(&state, &book.id).await.expect("update excerpt"));
        assert!(status(&state).unwrap().last_attempt.unwrap().succeeded);
        assert!(db::pending_edgeever_books(&state).unwrap().is_empty());
        assert!(!sync_book(&state, &book.id).await.expect("unchanged note"));
        assert_eq!(
            db::list_excerpts(&state, Some(&book.id)).unwrap()[0].created_at,
            created_at
        );
        {
            let memo = mock.memo.lock().unwrap();
            let blocks = memo["contentJson"]["content"].as_array().unwrap();
            let quote = blocks
                .iter()
                .find(|block| block["type"] == "blockquote")
                .unwrap();
            let footer = quote["content"].as_array().unwrap().last().unwrap();
            let markdown = memo["contentMarkdown"].as_str().unwrap();
            let timestamp = footer["content"][0]["text"].as_str().unwrap();
            assert!(excerpt_date(timestamp));
            assert!(!timestamp.contains("摘录于"));
            assert!(markdown.contains(&format!(
                "> 修改后的原文\n>\n> {timestamp}\n\n**批注** 新增笔记"
            )));
        }
        db::delete_excerpt(&state, &excerpt_id).unwrap();
        assert!(sync_book(&state, &book.id)
            .await
            .expect("delete final excerpt"));
        assert!(!mock.memo.lock().unwrap()["contentJson"]
            .to_string()
            .contains("新增笔记"));

        let second_root = tempfile::tempdir().unwrap();
        let second_state = db::open(second_root.path().to_path_buf()).unwrap();
        let mut default_settings = settings.clone();
        default_settings["edgeEverNotebookId"] = json!("");
        db::kv_set(&second_state, "settings", &default_settings.to_string()).unwrap();
        let default_status = status(&second_state).unwrap();
        assert!(default_status.configured);
        assert_eq!(default_status.notebook_name.as_deref(), Some("等待分类"));
        test(&second_state, None).await.unwrap();
        let imported = db::import_book(
            &second_state,
            "other-filename.txt",
            b"book",
            "同步测试",
            None,
            "text/plain",
            None,
        )
        .unwrap();
        db::upsert_excerpt(
            &second_state,
            &imported.id,
            "epubcfi(/6/2)",
            "原文",
            None,
            "yellow",
        )
        .unwrap();
        assert!(sync_book(&second_state, &imported.id).await.unwrap());
        let linked =
            db::edgeever_excerpt_note(&second_state, &imported.id, &format!("http://{address}"))
                .unwrap()
                .unwrap();
        assert_eq!(linked.memo_id, "memo-1");
        assert_eq!(
            *mock.import_notebooks.lock().unwrap(),
            ["notebook-1", "notebook-1", "ws_default_inbox"]
        );
        assert!(status(&second_state).unwrap().last_attempt.unwrap().succeeded);
        assert_eq!(mock.creates.load(Ordering::SeqCst), 1);
        assert_eq!(mock.updates.load(Ordering::SeqCst), 5);
        let mut changed_target = settings;
        changed_target["edgeEverNotebookId"] = json!("notebook-2");
        changed_target["edgeEverNotebookLabel"] = json!({ "id": "notebook-2", "name": "精读" });
        db::kv_set(&state, "settings", &changed_target.to_string()).unwrap();
        let changed = status(&state).unwrap();
        assert_eq!(changed.notebook_name.as_deref(), Some("精读"));
        assert_ne!(changed.target_key, initial.target_key);
        assert!(changed.last_attempt.is_none());
    }
}
