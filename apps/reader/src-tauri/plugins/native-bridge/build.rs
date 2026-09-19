const COMMANDS: &[&str] = &["capture_webview_region", "pick_books"];

fn main() {
    tauri_plugin::Builder::new(COMMANDS)
        .android_path("android")
        .ios_path("ios")
        .build();
}
