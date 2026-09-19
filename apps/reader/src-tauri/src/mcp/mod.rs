mod content;
mod server;

use serde::Serialize;
use std::sync::Mutex;
use tauri::{AppHandle, Manager};
use tokio_util::sync::CancellationToken;
use uuid::Uuid;

use crate::db::AppState;

pub struct McpHandle {
    pub cancel: Mutex<Option<CancellationToken>>,
    pub endpoint: Mutex<Option<String>>,
    pub token: Mutex<Option<String>>,
}

impl Default for McpHandle {
    fn default() -> Self {
        Self {
            cancel: Mutex::new(None),
            endpoint: Mutex::new(None),
            token: Mutex::new(None),
        }
    }
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct McpStatus {
    pub running: bool,
    pub endpoint: Option<String>,
    pub token: Option<String>,
    pub database_path: String,
}

pub fn start(app: &AppHandle, state: &AppState) -> Result<McpStatus, String> {
    let handle = app.state::<McpHandle>();
    if handle.cancel.lock().map_err(|e| e.to_string())?.is_some() {
        return status(app, state);
    }
    let token = format!("leeef-{}", Uuid::new_v4());
    let cancel = CancellationToken::new();
    let bind_state = state.clone();
    let bind_token = token.clone();
    let bind_cancel = cancel.clone();
    let addr = tauri::async_runtime::block_on(server::bind_and_serve(
        bind_state,
        bind_token,
        bind_cancel,
    ))?;
    *handle.endpoint.lock().map_err(|e| e.to_string())? = Some(format!("http://{addr}/mcp"));
    *handle.token.lock().map_err(|e| e.to_string())? = Some(token);
    *handle.cancel.lock().map_err(|e| e.to_string())? = Some(cancel);
    status(app, state)
}

pub fn stop(app: &AppHandle, state: &AppState) -> Result<McpStatus, String> {
    let handle = app.state::<McpHandle>();
    if let Some(cancel) = handle.cancel.lock().map_err(|e| e.to_string())?.take() {
        cancel.cancel();
    }
    *handle.endpoint.lock().map_err(|e| e.to_string())? = None;
    *handle.token.lock().map_err(|e| e.to_string())? = None;
    status(app, state)
}

pub fn status(app: &AppHandle, state: &AppState) -> Result<McpStatus, String> {
    let handle = app.state::<McpHandle>();
    let running = handle.cancel.lock().map_err(|e| e.to_string())?.is_some();
    let endpoint = handle.endpoint.lock().map_err(|e| e.to_string())?.clone();
    let token = handle.token.lock().map_err(|e| e.to_string())?.clone();
    Ok(McpStatus {
        running,
        endpoint,
        token,
        database_path: crate::db::database_path(state),
    })
}

#[cfg(test)]
mod tests {
    use super::server::bind_and_serve;
    use crate::db;
    use serde_json::{json, Value};
    use tokio_util::sync::CancellationToken;

    async fn spawn_server() -> (String, CancellationToken, db::AppState) {
        let root = std::env::temp_dir().join(format!("leeef-mcp-{}", uuid::Uuid::new_v4()));
        std::fs::create_dir_all(&root).unwrap();
        let state = db::open(root).unwrap();
        let cancel = CancellationToken::new();
        let addr = bind_and_serve(state.clone(), "secret".into(), cancel.clone())
            .await
            .unwrap();
        (format!("http://{addr}/mcp"), cancel, state)
    }

    async fn post(
        endpoint: &str,
        token: Option<&str>,
        session: &str,
        body: Value,
    ) -> (String, Value) {
        let client = reqwest::Client::new();
        let mut request = client
            .post(endpoint)
            .header("Content-Type", "application/json")
            .header("Accept", "application/json, text/event-stream")
            .body(body.to_string());
        if let Some(token) = token {
            request = request.header("Authorization", format!("Bearer {token}"));
        }
        if !session.is_empty() {
            request = request.header("Mcp-Session-Id", session);
        }
        let response = request.send().await.unwrap();
        let session_id = response
            .headers()
            .get("Mcp-Session-Id")
            .and_then(|value| value.to_str().ok())
            .unwrap_or(session)
            .to_string();
        let status = response.status();
        let text = response.text().await.unwrap_or_default();
        if status.as_u16() == 202 || text.is_empty() {
            return (session_id, json!({}));
        }
        let decoded = parse_mcp_body(&text)
            .unwrap_or_else(|| json!({"_status": status.as_u16(), "_body": text}));
        (session_id, decoded)
    }

    async fn initialize(endpoint: &str) -> String {
        let (session, initialize) = post(
            endpoint,
            Some("secret"),
            "",
            json!({
                "jsonrpc": "2.0",
                "id": 1,
                "method": "initialize",
                "params": {
                    "protocolVersion": "2025-11-25",
                    "capabilities": {},
                    "clientInfo": {"name": "test", "version": "1"}
                }
            }),
        )
        .await;
        assert!(initialize.get("result").is_some(), "{initialize:?}");
        post(
            endpoint,
            Some("secret"),
            &session,
            json!({"jsonrpc": "2.0", "method": "notifications/initialized"}),
        )
        .await;
        session
    }

    fn parse_mcp_body(text: &str) -> Option<Value> {
        if let Ok(value) = serde_json::from_str(text) {
            return Some(value);
        }
        text.lines().rev().find_map(|line| {
            line.strip_prefix("data:")
                .map(str::trim)
                .filter(|data| data.starts_with('{'))
                .and_then(|data| serde_json::from_str(data).ok())
        })
    }

    fn structured(response: &Value) -> &Value {
        &response["result"]["structuredContent"]
    }

    #[tokio::test]
    async fn requires_bearer_token() {
        let (endpoint, cancel, _) = spawn_server().await;
        let client = reqwest::Client::new();
        let response = client
            .post(&endpoint)
            .header("Content-Type", "application/json")
            .body("{}")
            .send()
            .await
            .unwrap();
        assert_eq!(response.status(), reqwest::StatusCode::UNAUTHORIZED);
        cancel.cancel();
    }

    #[tokio::test]
    async fn health_and_library_stats() {
        let (endpoint, cancel, state) = spawn_server().await;
        db::create_shelf(&state, "Later", None, 0).unwrap();
        let session = initialize(&endpoint).await;
        let (_, response) = post(
            &endpoint,
            Some("secret"),
            &session,
            json!({
                "jsonrpc": "2.0",
                "id": 2,
                "method": "tools/call",
                "params": {"name": "library_stats", "arguments": {}}
            }),
        )
        .await;
        let stats = structured(&response);
        assert_eq!(stats["books"], 0);
        assert_eq!(stats["pendingSyncOperations"], 1);
        cancel.cancel();
    }

    #[tokio::test]
    async fn lists_expected_tools_and_reads_content() {
        let (endpoint, cancel, state) = spawn_server().await;
        let book = db::import_book(
            &state,
            "hello.txt",
            b"Hello from Leeef",
            "Hello",
            Some("Leeef"),
            "text/plain",
            None,
        )
        .unwrap();
        let session = initialize(&endpoint).await;
        let (_, listed) = post(
            &endpoint,
            Some("secret"),
            &session,
            json!({"jsonrpc": "2.0", "id": 2, "method": "tools/list", "params": {}}),
        )
        .await;
        let names: Vec<String> = listed["result"]["tools"]
            .as_array()
            .unwrap()
            .iter()
            .filter_map(|tool| tool["name"].as_str().map(str::to_string))
            .collect();
        for name in [
            "list_books",
            "search_books",
            "get_book",
            "get_book_content",
            "update_book_metadata",
            "move_book",
            "delete_book",
            "list_excerpts",
            "search_excerpts",
            "create_excerpt",
            "update_excerpt",
            "delete_excerpt",
            "list_bookmarks",
            "create_bookmark",
            "update_bookmark",
            "delete_bookmark",
            "list_bookshelves",
            "create_bookshelf",
            "rename_bookshelf",
            "move_bookshelf",
            "delete_bookshelf",
            "add_book_to_bookshelf",
            "remove_book_from_bookshelf",
            "get_reading_progress",
            "update_reading_progress",
            "confirm_write",
            "apply_write",
        ] {
            assert!(
                names.contains(&name.to_string()),
                "missing {name} in {names:?}"
            );
        }
        let (_, content) = post(
            &endpoint,
            Some("secret"),
            &session,
            json!({
                "jsonrpc": "2.0",
                "id": 4,
                "method": "tools/call",
                "params": {"name": "get_book_content", "arguments": {"bookId": book.id}}
            }),
        )
        .await;
        assert_eq!(structured(&content)["content"], "Hello from Leeef");
        cancel.cancel();
    }

    #[tokio::test]
    async fn confirmed_excerpt_write_is_audited_and_idempotent() {
        let (endpoint, cancel, state) = spawn_server().await;
        let book = db::import_book(
            &state,
            "hello.txt",
            b"Hello from Leeef",
            "Hello",
            Some("Leeef"),
            "text/plain",
            None,
        )
        .unwrap();
        let session = initialize(&endpoint).await;
        let (_, planned) = post(
            &endpoint,
            Some("secret"),
            &session,
            json!({
                "jsonrpc": "2.0",
                "id": 2,
                "method": "tools/call",
                "params": {
                    "name": "create_excerpt",
                    "arguments": {
                        "bookId": book.id,
                        "locator": "epubcfi(/6/2)",
                        "quote": "Confirmed quote"
                    }
                }
            }),
        )
        .await;
        let plan_id = structured(&planned)["planId"].as_str().unwrap().to_string();
        let (_, rejected) = post(
            &endpoint,
            Some("secret"),
            &session,
            json!({
                "jsonrpc": "2.0",
                "id": 3,
                "method": "tools/call",
                "params": {
                    "name": "apply_write",
                    "arguments": {"planId": plan_id, "confirmationToken": "not-confirmed"}
                }
            }),
        )
        .await;
        assert!(
            rejected["result"]["isError"] == true || rejected.get("error").is_some(),
            "unconfirmed apply was not rejected: {rejected}"
        );
        let (_, confirmed) = post(
            &endpoint,
            Some("secret"),
            &session,
            json!({
                "jsonrpc": "2.0",
                "id": 4,
                "method": "tools/call",
                "params": {"name": "confirm_write", "arguments": {"planId": plan_id}}
            }),
        )
        .await;
        let token = structured(&confirmed)["confirmationToken"]
            .as_str()
            .unwrap()
            .to_string();
        let apply_body = json!({
            "jsonrpc": "2.0",
            "id": 5,
            "method": "tools/call",
            "params": {
                "name": "apply_write",
                "arguments": {"planId": plan_id, "confirmationToken": token}
            }
        });
        let (_, applied) = post(&endpoint, Some("secret"), &session, apply_body.clone()).await;
        if structured(&applied)["applied"] != true {
            panic!("apply response = {applied}");
        }
        let excerpts = db::list_excerpts(&state, Some(&book.id)).unwrap();
        assert_eq!(excerpts.len(), 1);
        assert_eq!(excerpts[0].quote, "Confirmed quote");
        let stats = db::library_stats(&state).unwrap();
        assert_eq!(stats.excerpts, 1);
        let (_, retried) = post(&endpoint, Some("secret"), &session, apply_body).await;
        assert_eq!(
            structured(&retried)["operationId"],
            structured(&applied)["operationId"]
        );
        cancel.cancel();
    }
}
