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
