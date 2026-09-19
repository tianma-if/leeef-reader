use crate::db::AppState;
use serde::Serialize;
use std::io::{BufRead, BufReader};
use std::path::PathBuf;
use std::process::{Child, Command, Stdio};
use std::sync::Mutex;
use tauri::{AppHandle, Manager};

pub struct McpHandle {
    pub child: Mutex<Option<Child>>,
    pub endpoint: Mutex<Option<String>>,
    pub token: Mutex<Option<String>>,
}

impl Default for McpHandle {
    fn default() -> Self {
        Self {
            child: Mutex::new(None),
            endpoint: Mutex::new(None),
            token: Mutex::new(None),
        }
    }
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct McpStatus {
    pub running: bool,
    pub endpoint: Option<String>,
    pub database_path: String,
}

fn sidecar_path(app: &AppHandle) -> Option<PathBuf> {
    let name = if cfg!(windows) { "leeef-mcp.exe" } else { "leeef-mcp" };
    let mut candidates = Vec::new();
    if let Ok(dir) = app.path().resource_dir() {
        candidates.push(dir.join(name));
    }
    if let Ok(exe) = std::env::current_exe() {
        if let Some(dir) = exe.parent() {
            candidates.push(dir.join(name));
            candidates.push(dir.join("sidecars").join(name));
        }
    }
    candidates.push(
        PathBuf::from(env!("CARGO_MANIFEST_DIR"))
            .join("../../../sidecars/leeef-mcp/build")
            .join(name),
    );
    candidates.into_iter().find(|path| path.is_file())
}

pub fn start(app: &AppHandle, state: &AppState) -> Result<McpStatus, String> {
    let handle = app.state::<McpHandle>();
    if handle.child.lock().map_err(|e| e.to_string())?.is_some() {
        return status(app, state);
    }
    let bin = sidecar_path(app).ok_or("找不到 leeef-mcp 可执行文件")?;
    let token: String = {
        use std::time::{SystemTime, UNIX_EPOCH};
        format!(
            "leeef-{}",
            SystemTime::now()
                .duration_since(UNIX_EPOCH)
                .unwrap_or_default()
                .as_nanos()
        )
    };
    let mut child = Command::new(&bin)
        .args([
            "--listen",
            "127.0.0.1:0",
            "--database",
            &state.root.join("leeef.sqlite").to_string_lossy(),
            "--device-id",
            &state.device_id,
            "--writable",
        ])
        .env("LEEEF_MCP_TOKEN", &token)
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .map_err(|e| format!("启动 MCP 失败: {e}"))?;
    let stdout = child.stdout.take().ok_or("MCP 没有 stdout")?;
    let mut line = String::new();
    BufReader::new(stdout)
        .read_line(&mut line)
        .map_err(|e| e.to_string())?;
    let parsed: serde_json::Value =
        serde_json::from_str(line.trim()).map_err(|e| format!("MCP handshake: {e} {line}"))?;
    let endpoint = parsed
        .get("endpoint")
        .and_then(|v| v.as_str())
        .ok_or("MCP 未返回 endpoint")?
        .to_string();
    *handle.endpoint.lock().map_err(|e| e.to_string())? = Some(endpoint);
    *handle.token.lock().map_err(|e| e.to_string())? = Some(token);
    *handle.child.lock().map_err(|e| e.to_string())? = Some(child);
    status(app, state)
}

pub fn stop(app: &AppHandle, state: &AppState) -> Result<McpStatus, String> {
    let handle = app.state::<McpHandle>();
    if let Some(mut child) = handle.child.lock().map_err(|e| e.to_string())?.take() {
        let _ = child.kill();
        let _ = child.wait();
    }
    *handle.endpoint.lock().map_err(|e| e.to_string())? = None;
    *handle.token.lock().map_err(|e| e.to_string())? = None;
    status(app, state)
}

pub fn status(app: &AppHandle, state: &AppState) -> Result<McpStatus, String> {
    let handle = app.state::<McpHandle>();
    let running = handle.child.lock().map_err(|e| e.to_string())?.is_some();
    let endpoint = handle.endpoint.lock().map_err(|e| e.to_string())?.clone();
    Ok(McpStatus {
        running,
        endpoint,
        database_path: crate::db::database_path(state),
    })
}
