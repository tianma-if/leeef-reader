use base64::Engine as _;
use serde::de::DeserializeOwned;
use tauri::{plugin::PluginApi, AppHandle, Manager, Runtime};

use crate::models::{CaptureWebviewRegionRequest, SaveTextFileRequest, SaveTextFileResponse};

const BOOK_EXTENSIONS: &[&str] = &["epub", "txt", "mobi", "azw3", "fb2", "pdf"];

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

    pub fn set_cover_progress(
        &self,
        _payload: crate::models::CoverProgressRequest,
    ) -> crate::Result<()> {
        Ok(())
    }

    pub fn uncover_webview(&self) -> crate::Result<()> {
        Ok(())
    }

    pub fn probe_webview_ready(&self) -> crate::Result<crate::models::ProbeReadyResponse> {
        Ok(crate::models::ProbeReadyResponse { ready: true })
    }

    pub async fn pick_books(&self) -> crate::Result<Vec<crate::models::PickedBook>> {
        let window = self.0.get_webview_window("main");
        let mut dialog = rfd::AsyncFileDialog::new()
            .set_title("导入电子书")
            .add_filter("电子书", BOOK_EXTENSIONS);
        if let Some(window) = window.as_ref() {
            dialog = dialog.set_parent(window);
        }
        let Some(files) = dialog.pick_files().await else {
            return Ok(Vec::new());
        };
        let mut picked = Vec::with_capacity(files.len());
        for file in files {
            let name = file.file_name();
            let bytes = std::fs::read(file.path()).map_err(|error| {
                crate::Error::NativeBridgeError(format!("无法读取 {name}：{error}"))
            })?;
            picked.push(crate::models::PickedBook {
                name,
                data: base64::engine::general_purpose::STANDARD.encode(bytes),
            });
        }
        Ok(picked)
    }

    pub async fn save_text_file(
        &self,
        payload: SaveTextFileRequest,
    ) -> crate::Result<SaveTextFileResponse> {
        let window = self.0.get_webview_window("main");
        let extension = std::path::Path::new(&payload.filename)
            .extension()
            .and_then(|value| value.to_str())
            .unwrap_or("txt");
        let mut dialog = rfd::AsyncFileDialog::new()
            .set_title("导出书摘")
            .set_file_name(&payload.filename)
            .add_filter("文本文件", &[extension]);
        if let Some(window) = window.as_ref() {
            dialog = dialog.set_parent(window);
        }
        let Some(file) = dialog.save_file().await else {
            return Ok(SaveTextFileResponse { saved: false });
        };
        std::fs::write(file.path(), payload.content.as_bytes()).map_err(|error| {
            crate::Error::NativeBridgeError(format!("无法保存导出文件：{error}"))
        })?;
        Ok(SaveTextFileResponse { saved: true })
    }

    pub fn check_mobile_update(&self) -> crate::Result<crate::models::MobileUpdateStatus> {
        Err(crate::Error::UnsupportedPlatformError)
    }

    pub fn start_mobile_update(&self) -> crate::Result<crate::models::MobileUpdateStatus> {
        Err(crate::Error::UnsupportedPlatformError)
    }

    pub fn complete_mobile_update(&self) -> crate::Result<()> {
        Err(crate::Error::UnsupportedPlatformError)
    }

    pub fn open_mobile_store(&self) -> crate::Result<()> {
        Err(crate::Error::UnsupportedPlatformError)
    }
}
