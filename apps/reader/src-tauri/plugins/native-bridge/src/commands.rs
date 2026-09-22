use tauri::{command, AppHandle, Runtime};

use crate::models::{
    CaptureWebviewRegionRequest, CoverProgressRequest, ProbeReadyResponse, SaveTextFileRequest,
    SaveTextFileResponse,
};
use crate::{NativeBridgeExt, Result};

#[command]
pub(crate) async fn capture_webview_region<R: Runtime>(
    app: AppHandle<R>,
    window: tauri::WebviewWindow<R>,
    payload: CaptureWebviewRegionRequest,
) -> Result<tauri::ipc::Response> {
    let bytes = app
        .native_bridge()
        .capture_webview_region(&window, payload)?;
    Ok(tauri::ipc::Response::new(bytes))
}

#[command]
pub(crate) async fn set_cover_progress<R: Runtime>(
    app: AppHandle<R>,
    payload: CoverProgressRequest,
) -> Result<()> {
    app.native_bridge().set_cover_progress(payload)
}

#[command]
pub(crate) async fn uncover_webview<R: Runtime>(app: AppHandle<R>) -> Result<()> {
    app.native_bridge().uncover_webview()
}

#[command]
pub(crate) async fn probe_webview_ready<R: Runtime>(
    app: AppHandle<R>,
) -> Result<ProbeReadyResponse> {
    app.native_bridge().probe_webview_ready()
}

#[command]
pub(crate) async fn pick_books<R: Runtime>(
    app: AppHandle<R>,
) -> Result<Vec<crate::models::PickedBook>> {
    #[cfg(desktop)]
    {
        app.native_bridge().pick_books().await
    }
    #[cfg(mobile)]
    {
        app.native_bridge().pick_books()
    }
}

#[command]
pub(crate) async fn save_text_file<R: Runtime>(
    app: AppHandle<R>,
    payload: SaveTextFileRequest,
) -> Result<SaveTextFileResponse> {
    #[cfg(desktop)]
    {
        app.native_bridge().save_text_file(payload).await
    }
    #[cfg(mobile)]
    {
        app.native_bridge().save_text_file(payload)
    }
}

#[command]
pub(crate) async fn check_mobile_update<R: Runtime>(
    app: AppHandle<R>,
) -> Result<crate::models::MobileUpdateStatus> {
    app.native_bridge().check_mobile_update()
}

#[command]
pub(crate) async fn start_mobile_update<R: Runtime>(
    app: AppHandle<R>,
) -> Result<crate::models::MobileUpdateStatus> {
    app.native_bridge().start_mobile_update()
}

#[command]
pub(crate) async fn complete_mobile_update<R: Runtime>(app: AppHandle<R>) -> Result<()> {
    app.native_bridge().complete_mobile_update()
}

#[command]
pub(crate) async fn open_mobile_store<R: Runtime>(app: AppHandle<R>) -> Result<()> {
    app.native_bridge().open_mobile_store()
}
