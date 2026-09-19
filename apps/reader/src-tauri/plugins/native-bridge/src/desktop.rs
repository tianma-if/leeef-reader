use serde::de::DeserializeOwned;
use tauri::{plugin::PluginApi, AppHandle, Runtime};

use crate::models::CaptureWebviewRegionRequest;

pub fn init<R: Runtime, C: DeserializeOwned>(
    app: &AppHandle<R>,
    _api: PluginApi<R, C>,
) -> crate::Result<NativeBridge<R>> {
    Ok(NativeBridge(app.clone()))
}

pub struct NativeBridge<R: Runtime>(AppHandle<R>);

impl<R: Runtime> NativeBridge<R> {
    pub fn capture_webview_region(
        &self,
        _window: &tauri::WebviewWindow<R>,
        _payload: CaptureWebviewRegionRequest,
    ) -> crate::Result<Vec<u8>> {
        // Desktop falls back to foliate's own paginator animation.
        Err(crate::Error::UnsupportedPlatformError)
    }

    pub fn pick_books(&self) -> crate::Result<Vec<crate::models::PickedBook>> {
        Err(crate::Error::UnsupportedPlatformError)
    }
}
