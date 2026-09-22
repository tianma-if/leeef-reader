const COMMANDS: &[&str] = &[
    "capture_webview_region",
    "set_cover_progress",
    "uncover_webview",
    "probe_webview_ready",
    "pick_books",
    "save_text_file",
    "check_mobile_update",
    "start_mobile_update",
    "complete_mobile_update",
    "open_mobile_store",
];

fn main() {
    tauri_plugin::Builder::new(COMMANDS)
        .android_path("android")
        .ios_path("ios")
        .build();
}
