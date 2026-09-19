mod db;
mod mcp;

use db::AppState;
use serde::Deserialize;
use tauri::ipc::Response;
use tauri::{Manager, State};

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct ImportPayload {
    name: String,
    data: String,
    title: String,
    author: Option<String>,
    media_type: String,
    cover: Option<String>,
}

#[tauri::command]
fn list_books(state: State<AppState>) -> Result<Vec<db::Book>, String> {
    db::list_books(&state)
}

#[tauri::command]
fn import_book(state: State<AppState>, payload: ImportPayload) -> Result<db::Book, String> {
    use base64::Engine as _;
    let bytes = base64::engine::general_purpose::STANDARD
        .decode(payload.data)
        .map_err(|e| e.to_string())?;
    let cover = payload
        .cover
        .as_ref()
        .map(|c| {
            base64::engine::general_purpose::STANDARD
                .decode(c)
                .map_err(|e| e.to_string())
        })
        .transpose()?;
    db::import_book(
        &state,
        &payload.name,
        &bytes,
        &payload.title,
        payload.author.as_deref(),
        &payload.media_type,
        cover.as_deref(),
    )
}

#[tauri::command]
fn delete_book(state: State<AppState>, id: String) -> Result<(), String> {
    db::delete_book(&state, &id)
}

#[tauri::command]
fn update_book(
    state: State<AppState>,
    id: String,
    title: Option<String>,
    author: Option<String>,
    rating: Option<f64>,
) -> Result<(), String> {
    db::update_book(
        &state,
        &id,
        title.as_deref(),
        author.as_deref(),
        rating,
        None,
    )
}

#[tauri::command]
fn book_bytes(state: State<AppState>, id: String) -> Result<Response, String> {
    Ok(Response::new(db::book_bytes(&state, &id)?))
}

#[tauri::command]
fn book_cover(state: State<AppState>, id: String) -> Result<Response, String> {
    Ok(Response::new(db::book_cover(&state, &id)?))
}

#[tauri::command]
fn save_progress(
    state: State<AppState>,
    book_id: String,
    locator: String,
    progress: f64,
    chapter_title: Option<String>,
) -> Result<(), String> {
    db::save_progress(
        &state,
        &book_id,
        &locator,
        progress,
        chapter_title.as_deref(),
        None,
    )
}

#[tauri::command]
fn list_excerpts(
    state: State<AppState>,
    book_id: Option<String>,
) -> Result<Vec<db::Excerpt>, String> {
    db::list_excerpts(&state, book_id.as_deref())
}

#[tauri::command]
fn create_excerpt(
    state: State<AppState>,
    book_id: String,
    locator: String,
    quote: String,
    note: Option<String>,
    color: String,
) -> Result<(), String> {
    db::upsert_excerpt(&state, &book_id, &locator, &quote, note.as_deref(), &color)?;
    Ok(())
}

#[tauri::command]
fn delete_excerpt(state: State<AppState>, id: String) -> Result<(), String> {
    db::delete_excerpt(&state, &id)
}

#[tauri::command]
fn list_bookmarks(state: State<AppState>, book_id: String) -> Result<Vec<db::Bookmark>, String> {
    db::list_bookmarks(&state, Some(&book_id))
}

#[tauri::command]
fn add_bookmark(
    state: State<AppState>,
    book_id: String,
    locator: String,
    title: Option<String>,
) -> Result<(), String> {
    db::add_bookmark(&state, &book_id, &locator, title.as_deref(), None)?;
    Ok(())
}

#[tauri::command]
fn delete_bookmark(state: State<AppState>, id: String) -> Result<(), String> {
    db::delete_bookmark(&state, &id)
}

#[tauri::command]
fn list_shelves(state: State<AppState>) -> Result<Vec<db::Shelf>, String> {
    db::list_shelves(&state)
}

#[tauri::command]
fn create_shelf(
    state: State<AppState>,
    name: String,
    parent_id: Option<String>,
) -> Result<(), String> {
    db::create_shelf(&state, &name, parent_id.as_deref(), 0)?;
    Ok(())
}

#[tauri::command]
fn add_book_to_shelf(
    state: State<AppState>,
    shelf_id: String,
    book_id: String,
) -> Result<(), String> {
    db::add_book_to_shelf(&state, &shelf_id, &book_id, 0)
}

#[tauri::command]
fn remove_book_from_shelf(
    state: State<AppState>,
    shelf_id: String,
    book_id: String,
) -> Result<(), String> {
    db::remove_book_from_shelf(&state, &shelf_id, &book_id)
}

#[tauri::command]
fn list_tags(state: State<AppState>) -> Result<Vec<db::Tag>, String> {
    db::list_tags(&state)
}

#[tauri::command]
fn create_tag(state: State<AppState>, name: String, color: i64) -> Result<(), String> {
    db::create_tag(&state, &name, color)
}

#[tauri::command]
fn set_book_tag(
    state: State<AppState>,
    book_id: String,
    tag_id: String,
    on: bool,
) -> Result<(), String> {
    db::set_book_tag(&state, &book_id, &tag_id, on)
}

#[tauri::command]
fn record_session(state: State<AppState>, book_id: String, seconds: i64) -> Result<(), String> {
    db::record_session(&state, &book_id, seconds)
}

#[tauri::command]
fn list_sessions(state: State<AppState>) -> Result<Vec<db::Session>, String> {
    db::list_sessions(&state)
}

#[tauri::command]
fn get_settings(state: State<AppState>) -> Result<serde_json::Value, String> {
    let raw = db::kv_get(&state, "settings")?;
    Ok(raw
        .and_then(|s| serde_json::from_str(&s).ok())
        .unwrap_or_else(|| serde_json::json!({})))
}

#[tauri::command]
fn save_settings(state: State<AppState>, value: serde_json::Value) -> Result<(), String> {
    db::kv_set(&state, "settings", &value.to_string())
}

#[tauri::command]
fn mcp_database_path(state: State<AppState>) -> String {
    db::database_path(&state)
}

#[tauri::command]
fn mcp_start(app: tauri::AppHandle, state: State<AppState>) -> Result<mcp::McpStatus, String> {
    mcp::start(&app, &state)
}

#[tauri::command]
fn mcp_stop(app: tauri::AppHandle, state: State<AppState>) -> Result<mcp::McpStatus, String> {
    mcp::stop(&app, &state)
}

#[tauri::command]
fn mcp_status(app: tauri::AppHandle, state: State<AppState>) -> Result<mcp::McpStatus, String> {
    mcp::status(&app, &state)
}

#[tauri::command]
fn pairing_code(state: State<AppState>) -> Result<String, String> {
    let code = format!("{:06}", (uuid::Uuid::new_v4().as_u128() % 1_000_000) as u32);
    db::kv_set(&state, "pairing_code", &code)?;
    Ok(code)
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .plugin(tauri_plugin_opener::init())
        .plugin(tauri_plugin_native_bridge::init())
        .setup(|app| {
            let root = app.path().app_data_dir().map_err(|e| e.to_string())?;
            std::fs::create_dir_all(&root)?;
            let state = db::open(root)?;
            app.manage(state);
            app.manage(mcp::McpHandle::default());
            Ok(())
        })
        .invoke_handler(tauri::generate_handler![
            list_books,
            import_book,
            delete_book,
            update_book,
            book_bytes,
            book_cover,
            save_progress,
            list_excerpts,
            create_excerpt,
            delete_excerpt,
            list_bookmarks,
            add_bookmark,
            delete_bookmark,
            list_shelves,
            create_shelf,
            add_book_to_shelf,
            remove_book_from_shelf,
            list_tags,
            create_tag,
            set_book_tag,
            record_session,
            list_sessions,
            get_settings,
            save_settings,
            mcp_database_path,
            mcp_start,
            mcp_stop,
            mcp_status,
            pairing_code
        ])
        .run(tauri::generate_context!())
        .expect("error while running Leeef Reader");
}
