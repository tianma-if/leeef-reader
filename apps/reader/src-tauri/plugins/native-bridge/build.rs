const COMMANDS: &[&str] = &[
    "capture_webview_region",
    "set_cover_progress",
    "uncover_webview",
    "probe_webview_ready",
    "pick_books",
];

fn main() {
    tauri_plugin::Builder::new(COMMANDS)
        .android_path("android")
        .ios_path("ios")
        .build();
}
