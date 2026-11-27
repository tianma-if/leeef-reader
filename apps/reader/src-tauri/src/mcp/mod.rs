mod content;
mod import;
mod reading;
mod server;

use serde::{Deserialize, Serialize};
use std::sync::Mutex;
use tauri::AppHandle;
use tokio_util::sync::CancellationToken;
use uuid::Uuid;

use crate::db::{self, AppState};

// Keep the opt-in and credentials on this device, outside synced settings.
const CONNECTION_KEY: &str = "mcp_connection";

#[derive(Deserialize, Serialize)]
struct Connection {
    port: u16,
    token: String,
}

pub struct McpHandle {
    runtime: Mutex<McpRuntime>,
    app: Option<AppHandle>,
}

#[derive(Default)]
struct McpRuntime {
    server: Option<RunningServer>,
    error: Option<String>,
}

struct RunningServer {
    connection: Connection,
    cancel: CancellationToken,
}

impl Drop for RunningServer {
    fn drop(&mut self) {
        self.cancel.cancel();
    }
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct McpStatus {
    running: bool,
    endpoint: Option<String>,
    token: Option<String>,
    database_path: String,
    error: Option<String>,
}

impl McpHandle {
    pub fn restore(state: &AppState, app: Option<AppHandle>) -> Self {
        let mut runtime = McpRuntime::default();
        match load_connection(state).and_then(|connection| {
            connection
                .map(|connection| launch(state, Some(connection), app.clone()))
                .transpose()
        }) {
            Ok(server) => runtime.server = server,
            Err(error) => runtime.error = Some(error),
        }
        Self {
            runtime: Mutex::new(runtime),
            app,
        }
    }

    pub fn start(&self, state: &AppState) -> Result<McpStatus, String> {
        let mut runtime = self.runtime.lock().map_err(|e| e.to_string())?;
        if runtime.running_server().is_none() {
            let saved = load_connection(state)?;
            runtime.server = Some(launch(state, saved, self.app.clone())?);
        }
        runtime.error = None;
        Ok(runtime.status(state))
    }

    pub fn stop(&self, state: &AppState) -> Result<McpStatus, String> {
        let mut runtime = self.runtime.lock().map_err(|e| e.to_string())?;
        {
            let db = state.db.lock().map_err(|e| e.to_string())?;
            db::kv_delete_on(&db, CONNECTION_KEY)?;
        }
        runtime.server = None;
        runtime.error = None;
        Ok(runtime.status(state))
    }

    pub fn status(&self, state: &AppState) -> Result<McpStatus, String> {
        Ok(self
            .runtime
            .lock()
            .map_err(|e| e.to_string())?
            .status(state))
    }
}

impl McpRuntime {
    fn running_server(&self) -> Option<&RunningServer> {
        self.server
            .as_ref()
            .filter(|server| !server.cancel.is_cancelled())
    }

    fn status(&self, state: &AppState) -> McpStatus {
        let server = self.running_server();
        McpStatus {
            running: server.is_some(),
            endpoint: server
                .map(|server| format!("http://127.0.0.1:{}/mcp", server.connection.port)),
            token: server.map(|server| server.connection.token.clone()),
            database_path: db::database_path(state),
            error: self.error.clone(),
        }
    }
}

fn load_connection(state: &AppState) -> Result<Option<Connection>, String> {
    db::kv_get(state, CONNECTION_KEY)?
        .map(|stored| serde_json::from_str(&stored).map_err(|e| e.to_string()))
        .transpose()
}

fn launch(
    state: &AppState,
    saved: Option<Connection>,
    app: Option<AppHandle>,
) -> Result<RunningServer, String> {
    tauri::async_runtime::block_on(async {
        let listener = server::bind(saved.as_ref().map_or(0, |connection| connection.port)).await?;
        let connection = match saved {
            Some(connection) => connection,
            None => {
                let connection = Connection {
                    port: listener.local_addr().map_err(|e| e.to_string())?.port(),
                    token: format!("leeef-{}", Uuid::new_v4()),
                };
                let json = serde_json::to_string(&connection).map_err(|e| e.to_string())?;
                db::kv_set(state, CONNECTION_KEY, &json)?;
                connection
            }
        };
        let cancel = CancellationToken::new();
        server::serve(
            listener,
            state.clone(),
            connection.token.clone(),
            cancel.clone(),
            app,
        );
        Ok(RunningServer { connection, cancel })
    })
}

#[cfg(test)]
mod tests {
    use super::{load_connection, server, McpHandle};
    use crate::db;
    use serde_json::{json, Value};
    use tokio_util::sync::CancellationToken;

    async fn spawn_server() -> (String, CancellationToken, db::AppState) {
        let root = std::env::temp_dir().join(format!("leeef-mcp-{}", uuid::Uuid::new_v4()));
        std::fs::create_dir_all(&root).unwrap();
        let state = db::open(root).unwrap();
        let cancel = CancellationToken::new();
        let listener = server::bind(0).await.unwrap();
        let addr = listener.local_addr().unwrap();
        server::serve(
            listener,
            state.clone(),
            "secret".into(),
            cancel.clone(),
            None,
        );
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

    #[test]
    fn connection_is_opt_in_and_survives_restart_until_disabled() {
        let root = tempfile::tempdir().unwrap();
        let state = db::open(root.path().to_owned()).unwrap();
        let first = McpHandle::restore(&state, None);
        assert!(!first.status(&state).unwrap().running);
        let original = first.start(&state).unwrap();
        assert!(original.running);
        assert_eq!(first.start(&state).unwrap().token, original.token);

        let occupied = McpHandle::restore(&state, None).status(&state).unwrap();
        assert!(!occupied.running);
        assert!(occupied.error.is_some());

        let port = load_connection(&state).unwrap().unwrap().port;
        drop(first);
        tauri::async_runtime::block_on(async {
            tokio::time::timeout(std::time::Duration::from_secs(3), async {
                while server::bind(port).await.is_err() {
                    tokio::time::sleep(std::time::Duration::from_millis(10)).await;
                }
            })
            .await
            .expect("MCP listener should release its port on shutdown");
        });
        let restarted = McpHandle::restore(&state, None);
        let status = restarted.status(&state).unwrap();
        assert!(status.running);
        assert_eq!(status.endpoint, original.endpoint);
        assert_eq!(status.token, original.token);

        assert!(!restarted.stop(&state).unwrap().running);
        assert!(load_connection(&state).unwrap().is_none());
        assert!(
            !McpHandle::restore(&state, None)
                .status(&state)
                .unwrap()
                .running
        );
        assert_ne!(restarted.start(&state).unwrap().token, original.token);
        restarted.stop(&state).unwrap();
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
            "import_book",
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
            "get_reading_recap",
            "get_reading_activity",
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

    fn recap_test_epub() -> Vec<u8> {
        use std::io::{Cursor, Write};
        let mut zip = zip::ZipWriter::new(Cursor::new(Vec::new()));
        for (path, text) in [
            ("META-INF/container.xml", r#"<container><rootfiles><rootfile full-path="Book/main.opf" media-type="application/oebps-package+xml"/></rootfiles></container>"#),
            ("Book/main.opf", r#"<package><metadata/><manifest><item id="chapter" href="text/chapter%201.xhtml" media-type="application/xhtml+xml"/></manifest><spine><itemref idref="chapter"/></spine></package>"#),
            ("Book/text/chapter 1.xhtml", "<html><head/><body><p>Earlier paragraph</p><p>Read🙂 Secret after the saved point</p><p>Future paragraph</p></body></html>"),
        ] {
            zip.start_file(path, zip::write::SimpleFileOptions::default()).unwrap();
            zip.write_all(text.as_bytes()).unwrap();
        }
        zip.finish().unwrap().into_inner()
    }

    #[tokio::test]
    async fn reading_tools_return_citations_bounded_recaps_and_date_scoped_activity() {
        use time::{format_description::well_known::Rfc3339, OffsetDateTime};

        let (endpoint, cancel, state) = spawn_server().await;
        let first = db::import_book(
            &state,
            "first.epub",
            &recap_test_epub(),
            "First",
            None,
            "application/epub+zip",
            None,
        )
        .unwrap();
        let second = db::import_book(
            &state,
            "second.txt",
            b"second",
            "Second",
            None,
            "text/plain",
            None,
        )
        .unwrap();
        let first_range = "epubcfi(/6/2!/4/2,/1:0,/1:7)";
        let first_excerpt = db::upsert_excerpt(
            &state,
            &first.id,
            first_range,
            "Earlier paragraph",
            Some("注意力的例子"),
            "yellow",
        )
        .unwrap();
        db::save_excerpt_chapters(
            &state,
            &first.id,
            &[(
                first_range.into(),
                db::ExcerptChapter {
                    key: "chapter".into(),
                    title: "Opening".into(),
                },
            )],
        )
        .unwrap();
        let second_excerpt = db::upsert_excerpt(
            &state,
            &second.id,
            first_range,
            "Time to focus",
            Some("另一条笔记"),
            "yellow",
        )
        .unwrap();
        let overlapping = db::upsert_excerpt(
            &state,
            &first.id,
            "epubcfi(/6/2!/4/4,/1:6,/1:20)",
            "Hidden selection",
            None,
            "red",
        )
        .unwrap();
        let future = db::upsert_excerpt(
            &state,
            &first.id,
            "epubcfi(/6/2!/4/6,/1:0,/1:6)",
            "Future paragraph",
            None,
            "red",
        )
        .unwrap();
        let stop = "epubcfi(/6/2!/4/4,/1:7,/1:20)";
        db::save_progress(&state, &first.id, stop, 0.4, Some("Opening"), None).unwrap();

        let from = "2026-11-16T00:00:00+08:00";
        let to = "2026-11-23T00:00:00+08:00";
        let start = OffsetDateTime::parse(from, &Rfc3339)
            .unwrap()
            .unix_timestamp();
        let end = OffsetDateTime::parse(to, &Rfc3339)
            .unwrap()
            .unix_timestamp();
        {
            let conn = state.db.lock().unwrap();
            for (id, created) in [
                (&first_excerpt, start.to_string()),
                (&second_excerpt, "2026-11-17T00:00:00+08:00".into()),
                (&overlapping, end.to_string()),
                (&future, (end + 1).to_string()),
            ] {
                conn.execute(
                    "UPDATE excerpts SET created_at=?2 WHERE id=?1",
                    (&id, created),
                )
                .unwrap();
            }
            for (id, start, end) in [
                ("left", start - 30, start + 20),
                ("right", end - 50, end + 30),
            ] {
                conn.execute("INSERT INTO reading_sessions(id,book_id,device_id,started_at,ended_at,duration_seconds,updated_at) VALUES(?1,?2,?3,?4,?5,?6,?5)",
                    (id, &first.id, &state.device_id, start.to_string(), end.to_string(), end - start)).unwrap();
            }
        }

        let session = initialize(&endpoint).await;
        let call = |name: &str, arguments: Value| {
            post(
                &endpoint,
                Some("secret"),
                &session,
                json!({
                    "jsonrpc": "2.0", "id": 2, "method": "tools/call",
                    "params": {"name": name, "arguments": arguments}
                }),
            )
        };
        let mut search = json!({"query":"注意力", "queries":["FOCUS"], "notesOnly":true, "color":"yellow", "from":from, "to":to, "limit":1});
        let (_, page) = call("search_excerpts", search.clone()).await;
        assert_eq!(structured(&page)["nextOffset"], 1);
        search["offset"] = 1.into();
        let (_, next) = call("search_excerpts", search).await;
        assert!(structured(&next)["nextOffset"].is_null());
        let citations = [&page, &next].map(|response| &structured(response)["excerpts"][0]);
        let citation = citations
            .iter()
            .find(|item| item["bookTitle"] == "First")
            .unwrap();
        assert_eq!(citation["chapterTitle"], "Opening");
        assert_eq!(citation["quote"], "Earlier paragraph");
        assert_eq!(citation["note"], "注意力的例子");
        assert_eq!(
            citation["openUrl"],
            format!("leeef-reader://excerpt/{first_excerpt}")
        );
        assert!(citations.iter().any(|item| item["bookTitle"] == "Second"));

        let (_, recap) = call("get_reading_recap", json!({"bookId":first.id})).await;
        let recap = structured(&recap);
        assert_eq!(recap["precedingText"], "Earlier paragraph Read🙂");
        assert_eq!(recap["excerpts"].as_array().unwrap().len(), 1);
        assert_eq!(recap["excerpts"][0]["id"], first_excerpt);
        assert_eq!(recap["progress"]["locator"], stop);
        assert_eq!(
            recap["progress"]["resumeUrl"],
            format!("leeef-reader://resume/{}", first.id)
        );
        let (_, latest) = call("get_reading_recap", json!({})).await;
        assert_eq!(structured(&latest)["bookId"], first.id);
        let (_, unread) = call("get_reading_recap", json!({"bookId":second.id})).await;
        assert!(structured(&unread)["progress"].is_null());
        assert!(structured(&unread)["precedingText"].is_null());

        let (_, report) = call(
            "get_reading_activity",
            json!({"from":from, "to":to, "limit":1}),
        )
        .await;
        let report = structured(&report);
        assert_eq!(report["readingSeconds"], 70);
        assert_eq!(report["sessionCount"], 2);
        assert_eq!(report["booksRead"], 1);
        assert_eq!(report["excerptCount"], 2);
        assert_eq!(report["noteCount"], 2);
        assert_eq!(report["books"][0]["title"], "First");
        assert_eq!(report["nextOffset"], 1);
        let (_, report) = call(
            "get_reading_activity",
            json!({"from":from, "to":to, "offset":1}),
        )
        .await;
        assert_eq!(structured(&report)["books"][0]["title"], "Second");
        assert_eq!(structured(&report)["books"][0]["readingSeconds"], 0);
        assert_eq!(
            db::get_reading_progress(&state, &first.id).unwrap().locator,
            stop
        );
        cancel.cancel();
    }

    #[tokio::test]
    async fn ebook_import_requires_confirmation_and_preserves_the_reviewed_file() {
        let (endpoint, cancel, state) = spawn_server().await;
        let session = initialize(&endpoint).await;
        let source = tempfile::tempdir().unwrap();
        let path = source.path().join("Review me.TXT");
        let original = b"Chapter 1\nApproved text";
        std::fs::write(&path, original).unwrap();

        let call = |name: &str, arguments: Value| {
            let request = json!({
                "jsonrpc": "2.0",
                "id": 2,
                "method": "tools/call",
                "params": {"name": name, "arguments": arguments}
            });
            async { post(&endpoint, Some("secret"), &session, request).await.1 }
        };
        let is_error = |response: &Value| {
            response["result"]["isError"] == true || response.get("error").is_some()
        };

        assert!(is_error(
            &call("import_book", json!({"path": "relative.txt"})).await
        ));
        let planned = call("import_book", json!({"path": path, "author": "Leeef"})).await;
        let plan = structured(&planned);
        assert!(plan["summary"].as_str().unwrap().contains("Review me.TXT"));
        let plan_id = plan["planId"].as_str().unwrap();
        let unconfirmed = json!({"planId": plan_id, "confirmationToken": "wrong"});
        assert!(is_error(&call("apply_write", unconfirmed).await));
        assert!(db::list_books(&state).unwrap().is_empty());
        assert_eq!(
            std::fs::read_dir(state.root.join("books")).unwrap().count(),
            0
        );

        let confirmed = call("confirm_write", json!({"planId": plan_id})).await;
        let token = &structured(&confirmed)["confirmationToken"];
        let apply = json!({"planId": plan_id, "confirmationToken": token});
        assert!(db::list_books(&state).unwrap().is_empty());
        std::fs::write(&path, b"Chapter 1\nModified text").unwrap();
        assert!(is_error(&call("apply_write", apply.clone()).await));
        assert!(db::list_books(&state).unwrap().is_empty());

        std::fs::write(&path, original).unwrap();
        state
            .db
            .lock()
            .unwrap()
            .execute_batch(
                "CREATE TEMP TRIGGER fail_audit BEFORE INSERT ON audit_events
             BEGIN SELECT RAISE(ABORT, 'audit unavailable'); END;",
            )
            .unwrap();
        assert!(is_error(&call("apply_write", apply.clone()).await));
        assert_eq!(db::list_books(&state).unwrap().len(), 1);
        state
            .db
            .lock()
            .unwrap()
            .execute_batch("DROP TRIGGER fail_audit")
            .unwrap();

        let applied = call("apply_write", apply.clone()).await;
        assert_eq!(structured(&applied)["applied"], true, "{applied}");
        let book_id = structured(&applied)["entityId"].as_str().unwrap();
        let retried = call("apply_write", apply).await;
        assert_eq!(structured(&retried), structured(&applied));

        let books = db::list_books(&state).unwrap();
        assert_eq!(books.len(), 1);
        assert_eq!(books[0].id, book_id);
        assert_eq!(books[0].title, "Review me");
        assert_eq!(books[0].author.as_deref(), Some("Leeef"));
        assert_eq!(books[0].media_type, "text/plain");
        assert_eq!(db::book_bytes(&state, book_id).unwrap(), original);
        let content = call("get_book_content", json!({"bookId": book_id})).await;
        assert_eq!(structured(&content)["content"], "Chapter 1\nApproved text");

        let duplicate = call("import_book", json!({"path": path})).await;
        let duplicate_id = &structured(&duplicate)["planId"];
        let confirmed = call("confirm_write", json!({"planId": duplicate_id})).await;
        let token = &structured(&confirmed)["confirmationToken"];
        assert!(is_error(
            &call(
                "apply_write",
                json!({"planId": duplicate_id, "confirmationToken": token})
            )
            .await
        ));
        assert_eq!(db::list_books(&state).unwrap().len(), 1);
        assert_eq!(
            db::library_stats(&state).unwrap().pending_sync_operations,
            1
        );

        let db = state.db.lock().unwrap();
        let audit: String = db
            .query_row(
                "SELECT parameters_json FROM audit_events WHERE action = 'import_book'",
                [],
                |row| row.get(0),
            )
            .unwrap();
        let audit: Value = serde_json::from_str(&audit).unwrap();
        assert_eq!(audit["entityId"], book_id);
        assert_eq!(audit["payload"]["sha256"], db::sha256_hex(original));
        assert!(!audit.to_string().contains("Approved text"));
        cancel.cancel();
    }

    #[tokio::test]
    async fn epub_import_saves_embedded_metadata_and_cover() {
        use std::io::{Cursor, Write};

        let (endpoint, cancel, state) = spawn_server().await;
        let session = initialize(&endpoint).await;
        let source = tempfile::tempdir().unwrap();
        let call = |name: &str, arguments: Value| {
            let request = json!({
                "jsonrpc": "2.0",
                "id": 2,
                "method": "tools/call",
                "params": {"name": name, "arguments": arguments}
            });
            async { post(&endpoint, Some("secret"), &session, request).await.1 }
        };

        let cover = br#"<svg xmlns="http://www.w3.org/2000/svg" width="1" height="1"/>"#;
        let cases = [
            (
                "Modern.epub",
                r#"properties="cover-image""#,
                "cover%20art.svg",
                None,
                None,
            ),
            (
                "Legacy.epub",
                "",
                "cover%20art.svg",
                Some("Custom title"),
                Some("Custom author"),
            ),
            (
                "Missing cover.epub",
                r#"properties="cover-image""#,
                "missing.svg",
                None,
                None,
            ),
        ];

        for (filename, properties, href, title, author) in cases {
            let mut zip = zip::ZipWriter::new(Cursor::new(Vec::new()));
            let legacy_cover = if properties.is_empty() {
                r#"<meta name="cover" content="art"/>"#
            } else {
                ""
            };
            let opf = format!(
                r#"<package xmlns="http://www.idpf.org/2007/opf">
                  <metadata xmlns:d="http://purl.org/dc/elements/1.1/">
                    <d:title>Tea &amp; Books</d:title><d:creator>Book Author</d:creator>
                    {legacy_cover}
                  </metadata>
                  <manifest><item href="../Images/{href}" {properties} id="art" media-type="image/svg+xml"/></manifest>
                </package>"#,
            );
            for (name, bytes) in [
                (
                    "META-INF/container.xml",
                    br#"<container><rootfiles><rootfile full-path="Book/main.opf" media-type="application/oebps-package+xml"/></rootfiles></container>"#.as_slice(),
                ),
                ("Book/main.opf", opf.as_bytes()),
                ("Images/cover art.svg", cover.as_slice()),
            ] {
                zip.start_file(name, zip::write::SimpleFileOptions::default()).unwrap();
                zip.write_all(bytes).unwrap();
            }
            let original = zip.finish().unwrap().into_inner();
            let path = source.path().join(filename);
            std::fs::write(&path, &original).unwrap();
            let planned = call(
                "import_book",
                json!({"path": path, "title": title, "author": author}),
            )
            .await;
            let plan = structured(&planned);
            let expected_title = title.unwrap_or("Tea & Books");
            let expected_author = author.unwrap_or("Book Author");
            let summary = plan["summary"].as_str().unwrap();
            assert!(summary.contains(expected_title) && summary.contains(expected_author));
            let plan_id = &plan["planId"];
            let confirmed = call("confirm_write", json!({"planId": plan_id})).await;
            let token = &structured(&confirmed)["confirmationToken"];
            let applied = call(
                "apply_write",
                json!({"planId": plan_id, "confirmationToken": token}),
            )
            .await;
            let book_id = structured(&applied)["entityId"].as_str().unwrap();
            let book = db::list_books(&state)
                .unwrap()
                .into_iter()
                .find(|book| book.id == book_id)
                .unwrap();
            assert_eq!(book.title, expected_title);
            assert_eq!(book.author.as_deref(), Some(expected_author));
            assert_eq!(db::book_bytes(&state, book_id).unwrap(), original);
            if href == "missing.svg" {
                assert!(book.cover_path.is_none());
            } else {
                assert_eq!(db::book_cover(&state, book_id).unwrap(), cover);
            }
        }
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
