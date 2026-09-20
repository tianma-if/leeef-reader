use tauri::{command, AppHandle, Runtime};

use crate::models::{CaptureWebviewRegionRequest, CoverProgressRequest, ProbeReadyResponse};
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
