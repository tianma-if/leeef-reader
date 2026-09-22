use serde::de::DeserializeOwned;
use tauri::{
    plugin::{PluginApi, PluginHandle},
    AppHandle, Runtime,
};

use crate::models::{
    CaptureWebviewRegionRequest, CaptureWebviewRegionResponse, CoverProgressRequest, PickedBook,
    ProbeReadyResponse, SaveTextFileRequest, SaveTextFileResponse,
};

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

    pub fn set_cover_progress(&self, payload: CoverProgressRequest) -> crate::Result<()> {
        self.0
            .run_mobile_plugin::<()>("set_cover_progress", payload)?;
        Ok(())
    }

    pub fn uncover_webview(&self) -> crate::Result<()> {
        self.0.run_mobile_plugin::<()>("uncover_webview", ())?;
        Ok(())
    }

    pub fn probe_webview_ready(&self) -> crate::Result<ProbeReadyResponse> {
        Ok(self.0.run_mobile_plugin("probe_webview_ready", ())?)
    }

    pub fn pick_books(&self) -> crate::Result<Vec<PickedBook>> {
        let response: crate::models::PickBooksResponse =
            self.0.run_mobile_plugin("pick_books", ())?;
        Ok(response.files)
    }

    pub fn save_text_file(
        &self,
        payload: SaveTextFileRequest,
    ) -> crate::Result<SaveTextFileResponse> {
        Ok(self.0.run_mobile_plugin("save_text_file", payload)?)
    }

    pub fn check_mobile_update(&self) -> crate::Result<crate::models::MobileUpdateStatus> {
        Ok(self.0.run_mobile_plugin("check_mobile_update", ())?)
    }

    pub fn start_mobile_update(&self) -> crate::Result<crate::models::MobileUpdateStatus> {
        Ok(self.0.run_mobile_plugin("start_mobile_update", ())?)
    }

    pub fn complete_mobile_update(&self) -> crate::Result<()> {
        self.0
            .run_mobile_plugin::<()>("complete_mobile_update", ())?;
        Ok(())
    }

    pub fn open_mobile_store(&self) -> crate::Result<()> {
        self.0.run_mobile_plugin::<()>("open_mobile_store", ())?;
        Ok(())
    }
}
