use tauri::{
    plugin::{Builder, TauriPlugin},
    Manager, Runtime,
};

mod commands;
mod error;
mod models;

pub use error::{Error, Result};
pub use models::*;

#[cfg(desktop)]
mod desktop;
#[cfg(mobile)]
mod mobile;

#[cfg(desktop)]
use desktop::NativeBridge;
#[cfg(mobile)]
use mobile::NativeBridge;

pub trait NativeBridgeExt<R: Runtime> {
    fn native_bridge(&self) -> &NativeBridge<R>;
}

impl<R: Runtime, T: Manager<R>> NativeBridgeExt<R> for T {
    fn native_bridge(&self) -> &NativeBridge<R> {
        self.state::<NativeBridge<R>>().inner()
    }
}

pub fn init<R: Runtime>() -> TauriPlugin<R> {
    Builder::new("native-bridge")
        .invoke_handler(tauri::generate_handler![
            commands::capture_webview_region,
            commands::set_cover_progress,
            commands::uncover_webview,
            commands::probe_webview_ready,
            commands::pick_books,
            commands::save_text_file
        ])
        .setup(|app, api| {
            #[cfg(mobile)]
            let native_bridge = mobile::init(app, api)?;
            #[cfg(desktop)]
            let native_bridge = desktop::init(app, api)?;
            app.manage(native_bridge);
            Ok(())
        })
        .build()
}
