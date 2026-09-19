use tauri::{command, AppHandle, Runtime};

use crate::models::CaptureWebviewRegionRequest;
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
