use serde::de::DeserializeOwned;
use tauri::{
    plugin::{PluginApi, PluginHandle},
    AppHandle, Runtime,
};

use crate::models::{CaptureWebviewRegionRequest, CaptureWebviewRegionResponse};

#[cfg(target_os = "ios")]
tauri::ios_plugin_binding!(init_plugin_native_bridge);

pub fn init<R: Runtime, C: DeserializeOwned>(
    _app: &AppHandle<R>,
    api: PluginApi<R, C>,
) -> crate::Result<NativeBridge<R>> {
    #[cfg(target_os = "android")]
    let handle = api.register_android_plugin("dev.leeef.native_bridge", "NativeBridgePlugin")?;
    #[cfg(target_os = "ios")]
    let handle = api.register_ios_plugin(init_plugin_native_bridge)?;
    Ok(NativeBridge(handle))
}

pub struct NativeBridge<R: Runtime>(PluginHandle<R>);

impl<R: Runtime> NativeBridge<R> {
    pub fn capture_webview_region(
        &self,
        _window: &tauri::WebviewWindow<R>,
        payload: CaptureWebviewRegionRequest,
    ) -> crate::Result<Vec<u8>> {
        use base64::Engine as _;
        let response: CaptureWebviewRegionResponse = self
            .0
            .run_mobile_plugin("capture_webview_region", payload)?;
        base64::engine::general_purpose::STANDARD
            .decode(response.data)
            .map_err(|e| crate::Error::NativeBridgeError(format!("invalid capture payload: {e}")))
    }
}
