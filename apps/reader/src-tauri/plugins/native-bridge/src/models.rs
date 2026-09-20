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
