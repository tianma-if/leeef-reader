use serde::{Deserialize, Serialize};

#[derive(Debug, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct CaptureWebviewRegionRequest {
    pub x: f64,
    pub y: f64,
    pub width: f64,
    pub height: f64,
    #[serde(default)]
    pub cover: bool,
}

#[derive(Debug, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct CoverProgressRequest {
    pub progress: f64,
    pub forward: bool,
    #[serde(default)]
    pub duration: u64,
}

#[derive(Debug, Clone, Default, Deserialize, Serialize)]
pub struct ProbeReadyResponse {
    pub ready: bool,
}

#[derive(Debug, Clone, Default, Deserialize, Serialize)]
pub struct CaptureWebviewRegionResponse {
    pub data: String,
}

#[derive(Debug, Clone, Default, Deserialize, Serialize)]
pub struct PickedBook {
    pub name: String,
    pub data: String,
}

#[derive(Debug, Clone, Default, Deserialize, Serialize)]
pub struct PickBooksResponse {
    pub files: Vec<PickedBook>,
}

#[derive(Debug, Clone, Default, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct SaveTextFileRequest {
    pub filename: String,
    pub content: String,
}

#[derive(Debug, Clone, Default, Deserialize, Serialize)]
pub struct SaveTextFileResponse {
    pub saved: bool,
}

#[derive(Debug, Clone, Default, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct MobileUpdateStatus {
    pub platform: String,
    pub state: String,
    pub current_version: Option<String>,
    pub available_version: Option<String>,
    pub bytes_downloaded: Option<u64>,
    pub total_bytes: Option<u64>,
}
