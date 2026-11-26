use aes_gcm::{
    aead::{Aead, KeyInit, Payload as AeadPayload},
    Aes256Gcm, Nonce,
};
use argon2::{Algorithm, Argon2, Params as Argon2Params, Version as Argon2Version};
use base64::{engine::general_purpose::URL_SAFE_NO_PAD, Engine as _};
use hkdf::Hkdf;
use hmac::{Hmac, Mac};
use rand::{seq::SliceRandom, RngCore};
use reqwest::{Client, Method, StatusCode, Url};
use serde::{Deserialize, Serialize};
use serde_json::{Map, Value};
use sha2::{Digest, Sha256};
use std::{
    collections::{BTreeMap, BTreeSet},
    error::Error as _,
    sync::{Arc, Mutex},
    time::{Duration, SystemTime, UNIX_EPOCH},
};
use tauri::{AppHandle, Emitter};
use tokio::sync::Notify;
use tokio_util::sync::CancellationToken;
#[cfg(test)]
use x25519_dalek::{PublicKey, StaticSecret};

use crate::db::{self, AppState};
use crate::library_sync::{self, Snapshot};

mod pairing;
mod pairing_transport;

#[cfg(any(target_os = "android", target_os = "ios"))]
pub use pairing::join_pairing_qr;
use pairing::PairingSession;
pub use pairing::{
    cancel_pairing_join, decide_pairing, join_pairing, join_pairing_peer, nearby_pairing_devices,
    pairing_status, start_pairing, stop_pairing, PairingHostStatus, PairingOffer, PairingPeer,
};

const SPACE_KEY: &str = "trusted_sync_space";
const DEVICES_KEY: &str = "trusted_sync_devices";
const DEVICE_NAMES_KEY: &str = "trusted_sync_device_names";
const VERSIONS_KEY: &str = "trusted_sync_settings_versions";
const PREVIOUS_BACKEND_KEY: &str = "trusted_sync_previous_backend";
const DISCOVERY_PORT: u16 = 43781;
const PAIRING_TTL: Duration = Duration::from_secs(300);
const PAIRING_ALPHABET: &[u8] = b"23456789ABCDEFGHJKLMNPQRSTUVWXYZ";
const RECOVERY_AAD: &[u8] = b"leeef-recovery-v1";

fn request_error(error: reqwest::Error) -> String {
    let mut message = error.to_string();
    let mut source = error.source();
    while let Some(cause) = source {
        message.push_str(": ");
        message.push_str(&cause.to_string());
        source = cause.source();
    }
    message
}

async fn send_webdav_request(
    request: reqwest::RequestBuilder,
) -> Result<reqwest::Response, String> {
    let retry = request.try_clone();
    match request.send().await {
        Ok(response) => Ok(response),
        Err(first_error) => {
            let first_error = request_error(first_error);
            let retry = retry.ok_or(first_error.clone())?;
            retry.send().await.map_err(|retry_error| {
                format!("{first_error}; 重试失败：{}", request_error(retry_error))
            })
        }
    }
}

#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
struct SpaceState {
    id: String,
    key: String,
}

impl SpaceState {
    fn key_bytes(&self) -> Result<[u8; 32], String> {
        let bytes = URL_SAFE_NO_PAD
            .decode(&self.key)
            .map_err(|e| e.to_string())?;
        bytes
            .try_into()
            .map_err(|_| "同步空间密钥格式无效".to_string())
    }
}

#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
struct ConfigurationEntry {
    value: Value,
    modified_at: u64,
    modified_by: String,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
struct ConfigurationDocument {
    version: u8,
    space_id: String,
    device_id: String,
    #[serde(default, skip_serializing_if = "BTreeMap::is_empty")]
    device_names: BTreeMap<String, String>,
    entries: BTreeMap<String, ConfigurationEntry>,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
struct ConfigurationVersion {
    digest: String,
    modified_at: u64,
    modified_by: String,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
struct EncryptedDocument {
    version: u8,
    nonce: String,
    ciphertext: String,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
struct RecoveryEnvelope {
    format: String,
    version: u8,
    kdf: String,
    salt: String,
    nonce: String,
    ciphertext: String,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
struct RecoveryPayload {
    version: u8,
    created_at: u64,
    space: SpaceState,
    devices: Vec<String>,
    configuration: ConfigurationDocument,
}

#[derive(Clone, Debug, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct SyncStatus {
    pub paired: bool,
    #[serde(default)]
    pub paired_devices: Vec<PairedDevice>,
    pub configured: bool,
    pub auto_sync: bool,
    pub running: bool,
    pub last_success_at: Option<u64>,
    pub last_error: Option<String>,
    pub applied_values: usize,
    pub last_attempt_at: Option<u64>,
    pub library_enabled: bool,
    pub pending_records: Option<usize>,
    pub progress: SyncProgress,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct PairedDevice {
    id: String,
    name: Option<String>,
}

#[derive(Clone, Debug, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct SyncProgress {
    pub phase: String,
    pub completed: usize,
    pub total: usize,
    pub current_item: Option<String>,
}

type ProgressReporter<'a> = &'a (dyn Fn(SyncProgress) + Send + Sync);

fn progress(
    report: ProgressReporter<'_>,
    phase: &str,
    completed: usize,
    total: usize,
    item: Option<String>,
) {
    report(SyncProgress {
        phase: phase.into(),
        completed,
        total,
        current_item: item,
    });
}

fn book_label(records: &[library_sync::Record], hash: &str, cover: bool) -> String {
    let title = records
        .iter()
        .find(|r| r.table == "books" && r.data["sha256"].as_str() == Some(hash))
        .and_then(|r| r.data["title"].as_str())
        .unwrap_or("未命名书籍");
    if cover {
        format!("{title} · 封面")
    } else {
        title.to_owned()
    }
}

#[derive(Clone)]
pub struct SyncRuntime {
    notify: Arc<Notify>,
    status: Arc<Mutex<SyncStatus>>,
    pairing: Arc<Mutex<Option<Arc<PairingSession>>>>,
    pairing_join: Arc<Mutex<Option<CancellationToken>>>,
}

impl Default for SyncRuntime {
    fn default() -> Self {
        Self {
            notify: Arc::new(Notify::new()),
            status: Arc::new(Mutex::new(SyncStatus::default())),
            pairing: Arc::new(Mutex::new(None)),
            pairing_join: Arc::new(Mutex::new(None)),
        }
    }
}

impl SyncRuntime {
    pub fn trigger(&self) {
        self.notify.notify_one();
    }

    pub fn status(&self, state: &AppState) -> SyncStatus {
        let mut status = self
            .status
            .lock()
            .map(|value| value.clone())
            .unwrap_or_default();
        if status.last_attempt_at.is_none() {
            if let Ok(Some(saved)) = db::kv_get(state, "sync_last_outcome") {
                if let Ok(previous) = serde_json::from_str::<SyncStatus>(&saved) {
                    status = previous;
                }
            }
        }
        status.library_enabled = settings_object(state)
            .ok()
            .and_then(|s| s.get("syncLibrary").and_then(Value::as_bool))
            .unwrap_or(false);
        status.pending_records = library_sync::pending_count(state).ok();
        refresh_paired_devices(state, &mut status);
        status.configured = configured_backend(state).is_ok();
        status.auto_sync = auto_sync_enabled(state);
        status
    }
}

pub fn start_background(app: AppHandle, state: AppState, runtime: SyncRuntime) {
    tauri::async_runtime::spawn(async move {
        let mut interval = tokio::time::interval(Duration::from_secs(30));
        interval.set_missed_tick_behavior(tokio::time::MissedTickBehavior::Delay);
        tokio::time::sleep(Duration::from_secs(2)).await;
        loop {
            if auto_sync_enabled(&state) {
                run_and_publish(&app, &state, &runtime).await;
            }
            tokio::select! {
                _ = runtime.notify.notified() => {
                    tokio::time::sleep(Duration::from_millis(800)).await;
                }
                _ = interval.tick() => {}
            }
        }
    });
}

pub async fn sync_now(
    app: &AppHandle,
    state: &AppState,
    runtime: &SyncRuntime,
) -> Result<SyncStatus, String> {
    run_and_publish(app, state, runtime).await;
    let status = runtime.status(state);
    if let Some(error) = &status.last_error {
        Err(error.clone())
    } else {
        Ok(status)
    }
}

async fn run_and_publish(app: &AppHandle, state: &AppState, runtime: &SyncRuntime) {
    {
        if let Ok(mut status) = runtime.status.lock() {
            if status.running {
                return;
            }
            if load_space(state).ok().flatten().is_none() {
                return;
            }
            if status.last_attempt_at.is_none() {
                if let Ok(Some(saved)) = db::kv_get(state, "sync_last_outcome") {
                    if let Ok(previous) = serde_json::from_str::<SyncStatus>(&saved) {
                        *status = previous;
                    }
                }
            }
            status.running = true;
            status.last_error = None;
            status.applied_values = 0;
            status.last_attempt_at = Some(now_millis());
            status.progress = SyncProgress {
                phase: "configuration".into(),
                ..Default::default()
            };
        }
    }

    let _ = app.emit("settings-sync-status", runtime.status(state));
    let report = |progress: SyncProgress| {
        if let Ok(mut status) = runtime.status.lock() {
            status.progress = progress;
        }
        let _ = app.emit("settings-sync-status", runtime.status(state));
    };
    let configuration = synchronize(state).await;
    let configuration_changed = configuration.as_ref().is_ok_and(|count| *count > 0);
    let library = if configuration.is_ok() {
        synchronize_library_with_progress(state, &report).await
    } else {
        Ok(0)
    };
    let library_changed = library.as_ref().is_ok_and(|count| *count > 0);
    let result = configuration.and_then(|count| library.map(|applied| count + applied));
    if let Ok(mut status) = runtime.status.lock() {
        status.running = false;
        refresh_paired_devices(state, &mut status);
        status.configured = configured_backend(state).is_ok();
        status.auto_sync = auto_sync_enabled(state);
        match result {
            Ok(applied) => {
                status.last_success_at = Some(now_millis());
                status.last_error = None;
                status.applied_values = applied;
                status.progress = SyncProgress {
                    phase: "complete".into(),
                    ..Default::default()
                };
            }
            Err(error) => status.last_error = Some(error),
        }
        status.library_enabled = settings_object(state)
            .ok()
            .and_then(|s| s.get("syncLibrary").and_then(Value::as_bool))
            .unwrap_or(false);
        status.pending_records = library_sync::pending_count(state).ok();
        // Publish the finished run before allowing another caller to start. Otherwise
        // a racing run could be persisted as running and block a future app launch.
        if let Ok(saved) = serde_json::to_string(&*status) {
            let _ = db::kv_set(state, "sync_last_outcome", &saved);
        }
        let _ = app.emit("settings-sync-status", status.clone());
    }
    if configuration_changed {
        let _ = app.emit("settings-synced", ());
    }
    if library_changed {
        let _ = app.emit("library-synced", ());
    }
}

pub fn save_settings(state: &AppState, value: Value) -> Result<(), String> {
    let previous = settings_object(state)?;
    let next = value.as_object().cloned().unwrap_or_default();
    if load_space(state)?.is_some()
        && backend_fingerprint(&previous) != backend_fingerprint(&next)
        && configured_backend_from(&previous).is_ok()
    {
        db::kv_set(
            state,
            PREVIOUS_BACKEND_KEY,
            &Value::Object(previous).to_string(),
        )?;
    }
    db::kv_set(state, "settings", &value.to_string())?;
    let _ = capture_configuration(state)?;
    Ok(())
}

fn portable_key(key: &str) -> bool {
    !matches!(
        key,
        "autoSync" | "syncLastError" | "syncLastSuccessAt" | "opdsCatalogs"
    )
}

fn auto_sync_enabled(state: &AppState) -> bool {
    settings_object(state)
        .ok()
        .and_then(|settings| settings.get("autoSync").and_then(Value::as_bool))
        .unwrap_or(true)
}

fn capture_configuration(state: &AppState) -> Result<BTreeMap<String, ConfigurationEntry>, String> {
    let settings = settings_object(state)?;
    let mut versions = load_versions(state)?;
    let keys: BTreeSet<String> = settings
        .keys()
        .filter(|key| portable_key(key))
        .cloned()
        .chain(versions.keys().cloned())
        .collect();
    let mut result = BTreeMap::new();
    let mut logical_now = now_millis();
    for key in keys {
        if !portable_key(&key) {
            continue;
        }
        let value = settings.get(&key).cloned().unwrap_or(Value::Null);
        let digest = value_digest(&value);
        let previous = versions.get(&key);
        let changed = previous.map(|item| item.digest.as_str()) != Some(digest.as_str());
        if changed {
            if let Some(previous) = previous {
                logical_now = logical_now.max(previous.modified_at.saturating_add(1));
            }
        }
        let version = if changed {
            ConfigurationVersion {
                digest,
                modified_at: logical_now,
                modified_by: state.device_id.clone(),
            }
        } else {
            previous
                .cloned()
                .expect("unchanged configuration has a version")
        };
        result.insert(
            key.clone(),
            ConfigurationEntry {
                value,
                modified_at: version.modified_at,
                modified_by: version.modified_by.clone(),
            },
        );
        versions.insert(key, version);
    }
    save_versions(state, &versions)?;
    Ok(result)
}

fn merge_configuration(
    state: &AppState,
    candidates: impl IntoIterator<Item = ConfigurationDocument>,
) -> Result<usize, String> {
    let local = capture_configuration(state)?;
    let mut winners = local;
    for document in candidates {
        for (key, entry) in document.entries {
            if !portable_key(&key) {
                continue;
            }
            let replace = winners.get(&key).is_none_or(|current| {
                (entry.modified_at, &entry.modified_by)
                    > (current.modified_at, &current.modified_by)
            });
            if replace {
                winners.insert(key, entry);
            }
        }
    }

    let mut settings = settings_object(state)?;
    let mut versions = load_versions(state)?;
    let mut changed = 0;
    for (key, entry) in winners {
        let current = settings.get(&key).cloned().unwrap_or(Value::Null);
        if value_digest(&current) != value_digest(&entry.value) {
            if entry.value.is_null() {
                settings.remove(&key);
            } else {
                settings.insert(key.clone(), entry.value.clone());
            }
            changed += 1;
        }
        versions.insert(
            key,
            ConfigurationVersion {
                digest: value_digest(&entry.value),
                modified_at: entry.modified_at,
                modified_by: entry.modified_by,
            },
        );
    }
    db::kv_set(state, "settings", &Value::Object(settings).to_string())?;
    save_versions(state, &versions)?;
    Ok(changed)
}

fn pairing_configuration(
    mut settings: Map<String, Value>,
    document: ConfigurationDocument,
) -> (
    Map<String, Value>,
    BTreeMap<String, ConfigurationVersion>,
    usize,
) {
    settings.retain(|key, _| !portable_key(key));
    let mut versions = BTreeMap::new();
    let mut changed = 0;
    for (key, entry) in document.entries {
        if !portable_key(&key) {
            continue;
        }
        if !entry.value.is_null() {
            settings.insert(key.clone(), entry.value.clone());
        }
        versions.insert(
            key,
            ConfigurationVersion {
                digest: value_digest(&entry.value),
                modified_at: entry.modified_at,
                modified_by: entry.modified_by,
            },
        );
        changed += 1;
    }
    (settings, versions, changed)
}

#[cfg(test)]
fn apply_pairing_configuration(
    state: &AppState,
    document: ConfigurationDocument,
) -> Result<usize, String> {
    let (settings, versions, changed) = pairing_configuration(settings_object(state)?, document);
    db::kv_set(state, "settings", &Value::Object(settings).to_string())?;
    save_versions(state, &versions)?;
    Ok(changed)
}

fn apply_trusted_snapshot(
    state: &AppState,
    snapshot: PairingSnapshot,
    replace_existing: bool,
) -> Result<usize, String> {
    if snapshot.configuration.version != 1 || snapshot.configuration.space_id != snapshot.space.id {
        return Err("同步配置与同步空间不匹配。".into());
    }
    snapshot.space.key_bytes()?;
    let mut db = state.db.lock().map_err(|error| error.to_string())?;
    let tx = db.transaction().map_err(|error| error.to_string())?;
    let existing = decode_space(db::kv_get_on(&tx, SPACE_KEY)?)?;
    let same_space = existing
        .as_ref()
        .is_some_and(|space| space.id == snapshot.space.id);
    if existing.is_some() && !same_space {
        if !replace_existing {
            return Err("当前设备已加入另一个同步空间，请确认替换后重试。".into());
        }
        db::kv_delete_on(&tx, PREVIOUS_BACKEND_KEY)?;
    }
    let mut devices = if same_space {
        load_devices_on(&tx)?
    } else {
        BTreeSet::new()
    };
    devices.extend(snapshot.devices);
    devices.insert(state.device_id.clone());
    let mut names = if same_space {
        load_device_names(&tx)?
    } else {
        BTreeMap::new()
    };
    for (id, name) in &snapshot.configuration.device_names {
        if devices.contains(id) {
            if let Some(name) = clean_device_name(name) {
                names.insert(id.clone(), name);
            }
        }
    }
    let current = decode_settings(db::kv_get_on(&tx, "settings")?);
    let (settings, versions, changed) = pairing_configuration(current, snapshot.configuration);
    db::kv_set_on(
        &tx,
        SPACE_KEY,
        &serde_json::to_string(&snapshot.space).map_err(|error| error.to_string())?,
    )?;
    write_roster(&tx, &devices, &names)?;
    db::kv_set_on(&tx, "settings", &Value::Object(settings).to_string())?;
    db::kv_set_on(
        &tx,
        VERSIONS_KEY,
        &serde_json::to_string(&versions).map_err(|error| error.to_string())?,
    )?;
    tx.commit().map_err(|error| error.to_string())?;
    Ok(changed)
}

async fn synchronize(state: &AppState) -> Result<usize, String> {
    let Some(space) = load_space(state)? else {
        return Ok(0);
    };
    let backend = configured_backend(state)?;
    let own = configuration_document(state, &space)?;
    let own_path = configuration_path(&space.id, &state.device_id);
    backend
        .put(&own_path, &encrypt_document(&own, &space.key_bytes()?)?)
        .await?;
    if let Some(previous_backend) = previous_backend(state) {
        // Devices still polling the old backend must see the new endpoint and
        // credentials before they can follow this device to the new backend.
        let _ = previous_backend
            .put(&own_path, &encrypt_document(&own, &space.key_bytes()?)?)
            .await;
    }

    let devices = load_devices(state)?;
    let mut documents = Vec::new();
    for device_id in devices {
        if device_id == state.device_id {
            continue;
        }
        let path = configuration_path(&space.id, &device_id);
        if let Some(bytes) = backend.get(&path).await? {
            let document: ConfigurationDocument = decrypt_document(&bytes, &space.key_bytes()?)?;
            if document.version == 1
                && document.space_id == space.id
                && document.device_id == device_id
            {
                documents.push(document);
            }
        }
    }
    remember_configuration_devices(state, &space, &documents)?;
    let changed = merge_configuration(state, documents)?;

    // Publish the merged view so another device can converge in one later pull.
    let merged = configuration_document(state, &space)?;
    backend
        .put(&own_path, &encrypt_document(&merged, &space.key_bytes()?)?)
        .await?;
    Ok(changed)
}

async fn publish_library(
    state: &AppState,
    space: &SpaceState,
    backend: &RemoteBackend,
    report: ProgressReporter<'_>,
) -> Result<(), String> {
    let key = space.key_bytes()?;
    let fingerprint = backend_fingerprint(&settings_object(state)?);
    // Capture records before enumerating files. A concurrent new import is included
    // in the next snapshot; this manifest never advertises a file before upload.
    let records = library_sync::records(state)?;
    progress(report, "preparing", 0, 0, None);
    let local_assets = library_sync::local_assets(state)?;
    let mut uploads = BTreeMap::new();
    let mut assets = Vec::new();
    for (asset, objects) in local_assets {
        for (hash, path) in objects {
            let cache_key = format!("library-upload:{}:{fingerprint}:{hash}", space.id);
            if db::kv_get(state, &cache_key)?.is_none() {
                let label = book_label(&records, &asset.book_hash, hash != asset.book_hash);
                uploads.entry(hash).or_insert((path, cache_key, label));
            }
        }
        assets.push(asset);
    }
    let total = uploads.len();
    progress(report, "uploading", 0, total, None);
    for (completed, (hash, (path, cache_key, label))) in uploads.into_iter().enumerate() {
        progress(report, "uploading", completed, total, Some(label));
        let bytes = std::fs::read(path).map_err(|e| e.to_string())?;
        if db::sha256_hex(&bytes) != hash {
            return Err("本地书籍文件已变化，请重新导入后同步".into());
        }
        let encrypted = encrypt_document(&URL_SAFE_NO_PAD.encode(&bytes), &key)?;
        backend
            .put(
                &format!("trusted/{}/library/objects/{hash}", space.id),
                &encrypted,
            )
            .await?;
        db::kv_set(state, &cache_key, "1")?;
        progress(report, "uploading", completed + 1, total, None);
    }
    if records.iter().any(|record| {
        record.table == "books"
            && !record.deleted
            && record.data["is_deleted"].as_i64() != Some(1)
            && !assets
                .iter()
                .any(|asset| record.data["sha256"].as_str() == Some(&asset.book_hash))
    }) {
        return Err("书库文件尚未齐全，补全文件后将继续同步".into());
    }
    let snapshot = Snapshot {
        version: 1,
        space_id: space.id.clone(),
        device_id: state.device_id.clone(),
        devices: load_devices(state)?,
        records,
        assets,
    };
    let uploaded_revision = snapshot
        .records
        .iter()
        .map(|record| record.modified_at)
        .max()
        .unwrap_or(0);
    progress(report, "publishing", 0, 0, None);
    backend
        .put(
            &format!(
                "trusted/{}/library/devices/{}.json",
                space.id, state.device_id
            ),
            &encrypt_document(&snapshot, &key)?,
        )
        .await?;
    db::kv_set(
        state,
        "library_last_uploaded_revision",
        &uploaded_revision.to_string(),
    )
}

#[cfg(test)]
async fn synchronize_library(state: &AppState) -> Result<usize, String> {
    synchronize_library_with_progress(state, &|_| {}).await
}

async fn synchronize_library_with_progress(
    state: &AppState,
    report: ProgressReporter<'_>,
) -> Result<usize, String> {
    if settings_object(state)?
        .get("syncLibrary")
        .and_then(Value::as_bool)
        != Some(true)
    {
        return Ok(0);
    }
    let Some(space) = load_space(state)? else {
        return Ok(0);
    };
    let backend = configured_backend(state)?;
    let key = space.key_bytes()?;
    publish_library(state, &space, &backend, report).await?;
    progress(report, "discovering", 0, 0, None);
    let mut devices: BTreeSet<String> = load_devices(state)?.into_iter().collect();
    devices.insert(state.device_id.clone());
    let mut visited = BTreeSet::new();
    let mut snapshots = Vec::new();
    while let Some(device) = devices
        .iter()
        .find(|device| !visited.contains(*device))
        .cloned()
    {
        visited.insert(device.clone());
        if uuid::Uuid::parse_str(&device).is_err() {
            return Err("同步设备标识无效".into());
        }
        if device == state.device_id {
            continue;
        }
        let path = format!("trusted/{}/library/devices/{device}.json", space.id);
        let Some(bytes) = backend.get(&path).await? else {
            continue;
        };
        let snapshot: Snapshot = decrypt_document(&bytes, &key)?;
        if snapshot.version != 1 || snapshot.space_id != space.id || snapshot.device_id != device {
            return Err("书库同步文档版本或身份不匹配".into());
        }
        devices.extend(snapshot.devices.iter().cloned());
        if devices.len() > 256 {
            return Err("同步设备数量超出支持范围".into());
        }
        snapshots.push(snapshot);
    }
    // Preserve losing remote versions as well as the winning version.
    let records: Vec<_> = snapshots
        .iter()
        .flat_map(|s| s.records.iter().cloned())
        .collect();
    let mut assets = BTreeMap::new();
    for snapshot in &snapshots {
        for asset in &snapshot.assets {
            assets
                .entry(asset.book_hash.clone())
                .or_insert_with(|| asset.clone());
        }
    }
    // Existing locally imported copies are reused rather than downloaded again.
    let local_hashes: BTreeSet<String> = library_sync::local_assets(state)?
        .into_iter()
        .flat_map(|(_, objects)| objects.into_iter().map(|(hash, _)| hash))
        .collect();
    let mut downloads = BTreeMap::new();
    for asset in assets.values() {
        for hash in std::iter::once(&asset.book_hash).chain(asset.cover_hash.iter()) {
            let path = library_sync::asset_path(state, hash)?;
            if path.is_file() || local_hashes.contains(hash) {
                continue;
            }
            downloads.entry(hash.clone()).or_insert_with(|| {
                book_label(&records, &asset.book_hash, hash != &asset.book_hash)
            });
        }
    }
    let total = downloads.len();
    progress(report, "downloading", 0, total, None);
    for (completed, (hash, label)) in downloads.into_iter().enumerate() {
        progress(report, "downloading", completed, total, Some(label));
        let encrypted = backend
            .get(&format!("trusted/{}/library/objects/{hash}", space.id))
            .await?
            .ok_or("远端书籍文件尚未上传完成，请稍后重试")?;
        let encoded: String = decrypt_document(&encrypted, &key)?;
        let bytes = URL_SAFE_NO_PAD.decode(encoded).map_err(|e| e.to_string())?;
        library_sync::store_asset(state, &hash, &bytes)?;
        progress(report, "downloading", completed + 1, total, None);
    }
    progress(report, "merging", 0, 0, None);
    update_roster(state, &space, |known, _| {
        known.extend(devices);
        Ok(())
    })?;
    // The next snapshot relays merged versions with their original clocks.
    // Finish network I/O before committing so a failed upload never hides applied changes.
    library_sync::merge(state, &records, &assets.into_values().collect::<Vec<_>>())
}

fn configuration_path(space_id: &str, device_id: &str) -> String {
    format!("trusted/{space_id}/config/{device_id}.json")
}

fn encrypt_document<T: Serialize>(value: &T, key: &[u8; 32]) -> Result<Vec<u8>, String> {
    let mut nonce = [0_u8; 12];
    rand::thread_rng().fill_bytes(&mut nonce);
    let cipher = Aes256Gcm::new_from_slice(key).map_err(|e| e.to_string())?;
    let plaintext = serde_json::to_vec(value).map_err(|e| e.to_string())?;
    let ciphertext = cipher
        .encrypt(Nonce::from_slice(&nonce), plaintext.as_ref())
        .map_err(|_| "无法加密同步配置".to_string())?;
    serde_json::to_vec(&EncryptedDocument {
        version: 1,
        nonce: URL_SAFE_NO_PAD.encode(nonce),
        ciphertext: URL_SAFE_NO_PAD.encode(ciphertext),
    })
    .map_err(|e| e.to_string())
}

fn decrypt_document<T: for<'de> Deserialize<'de>>(
    bytes: &[u8],
    key: &[u8; 32],
) -> Result<T, String> {
    let document: EncryptedDocument = serde_json::from_slice(bytes).map_err(|e| e.to_string())?;
    if document.version != 1 {
        return Err("不支持的配置文档版本".into());
    }
    let nonce = URL_SAFE_NO_PAD
        .decode(document.nonce)
        .map_err(|e| e.to_string())?;
    if nonce.len() != 12 {
        return Err("配置文档 nonce 无效".into());
    }
    let ciphertext = URL_SAFE_NO_PAD
        .decode(document.ciphertext)
        .map_err(|e| e.to_string())?;
    let cipher = Aes256Gcm::new_from_slice(key).map_err(|e| e.to_string())?;
    let plaintext = cipher
        .decrypt(Nonce::from_slice(&nonce), ciphertext.as_ref())
        .map_err(|_| "配置文档校验失败".to_string())?;
    serde_json::from_slice(&plaintext).map_err(|e| e.to_string())
}

pub fn export_recovery(state: &AppState, password: &str) -> Result<String, String> {
    validate_recovery_password(password)?;
    let space = match load_space(state)? {
        Some(space) => space,
        None => {
            configured_backend(state)?;
            ensure_space(state)?
        }
    };
    let mut devices = load_devices(state)?;
    if !devices.contains(&state.device_id) {
        devices.push(state.device_id.clone());
    }
    devices.sort();
    devices.dedup();
    let payload = RecoveryPayload {
        version: 1,
        created_at: now_millis(),
        configuration: configuration_document(state, &space)?,
        space,
        devices,
    };
    let mut salt = [0_u8; 16];
    let mut nonce = [0_u8; 12];
    rand::thread_rng().fill_bytes(&mut salt);
    rand::thread_rng().fill_bytes(&mut nonce);
    let key = recovery_key(password, &salt)?;
    let cipher = Aes256Gcm::new_from_slice(&key).map_err(|e| e.to_string())?;
    let plaintext = serde_json::to_vec(&payload).map_err(|e| e.to_string())?;
    let ciphertext = cipher
        .encrypt(
            Nonce::from_slice(&nonce),
            AeadPayload {
                msg: &plaintext,
                aad: RECOVERY_AAD,
            },
        )
        .map_err(|_| "无法加密恢复包".to_string())?;
    serde_json::to_string_pretty(&RecoveryEnvelope {
        format: "leeef-recovery".into(),
        version: 1,
        kdf: "argon2id-v1".into(),
        salt: URL_SAFE_NO_PAD.encode(salt),
        nonce: URL_SAFE_NO_PAD.encode(nonce),
        ciphertext: URL_SAFE_NO_PAD.encode(ciphertext),
    })
    .map_err(|e| e.to_string())
}

pub fn import_recovery(
    state: &AppState,
    package: &str,
    password: &str,
    replace_existing: bool,
) -> Result<usize, String> {
    validate_recovery_password(password)?;
    let envelope: RecoveryEnvelope =
        serde_json::from_str(package.trim()).map_err(|_| "恢复包格式无效".to_string())?;
    if envelope.format != "leeef-recovery" || envelope.version != 1 || envelope.kdf != "argon2id-v1"
    {
        return Err("不支持的恢复包版本".into());
    }
    let salt = URL_SAFE_NO_PAD
        .decode(envelope.salt)
        .map_err(|_| "恢复包格式无效".to_string())?;
    let nonce = URL_SAFE_NO_PAD
        .decode(envelope.nonce)
        .map_err(|_| "恢复包格式无效".to_string())?;
    let ciphertext = URL_SAFE_NO_PAD
        .decode(envelope.ciphertext)
        .map_err(|_| "恢复包格式无效".to_string())?;
    if salt.len() != 16 || nonce.len() != 12 {
        return Err("恢复包格式无效".into());
    }
    let key = recovery_key(password, &salt)?;
    let cipher = Aes256Gcm::new_from_slice(&key).map_err(|e| e.to_string())?;
    let plaintext = cipher
        .decrypt(
            Nonce::from_slice(&nonce),
            AeadPayload {
                msg: &ciphertext,
                aad: RECOVERY_AAD,
            },
        )
        .map_err(|_| "恢复密码错误或恢复包已损坏".to_string())?;
    let payload: RecoveryPayload =
        serde_json::from_slice(&plaintext).map_err(|_| "恢复包内容无效".to_string())?;
    if payload.version != 1 || payload.configuration.space_id != payload.space.id {
        return Err("恢复包内容无效".into());
    }
    apply_trusted_snapshot(
        state,
        PairingSnapshot {
            space: payload.space,
            devices: payload.devices,
            configuration: payload.configuration,
        },
        replace_existing,
    )
}

fn validate_recovery_password(password: &str) -> Result<(), String> {
    if password.chars().count() < 12 {
        return Err("恢复密码至少需要 12 个字符".into());
    }
    Ok(())
}

fn recovery_key(password: &str, salt: &[u8]) -> Result<[u8; 32], String> {
    let params = Argon2Params::new(32 * 1024, 3, 1, Some(32)).map_err(|e| e.to_string())?;
    let argon2 = Argon2::new(Algorithm::Argon2id, Argon2Version::V0x13, params);
    let mut key = [0_u8; 32];
    argon2
        .hash_password_into(password.as_bytes(), salt, &mut key)
        .map_err(|e| e.to_string())?;
    Ok(key)
}

#[derive(Clone)]
enum RemoteBackend {
    WebDav {
        client: Client,
        endpoint: Url,
        username: Option<String>,
        password: Option<String>,
    },
    S3 {
        client: Client,
        endpoint: Url,
        bucket: String,
        region: String,
        access_key: String,
        secret_key: String,
        prefix: String,
    },
}

impl RemoteBackend {
    async fn get(&self, path: &str) -> Result<Option<Vec<u8>>, String> {
        match self {
            Self::WebDav {
                client,
                endpoint,
                username,
                password,
            } => {
                let url = join_url(endpoint, path)?;
                let mut request = client.get(url);
                if let Some(username) = username {
                    request = request.basic_auth(username, password.as_deref());
                }
                let response = send_webdav_request(request).await?;
                if response.status() == StatusCode::NOT_FOUND {
                    return Ok(None);
                }
                if !response.status().is_success() {
                    return Err(format!("WebDAV 读取失败：{}", response.status()));
                }
                Ok(Some(
                    response.bytes().await.map_err(request_error)?.to_vec(),
                ))
            }
            Self::S3 { .. } => self.s3_request(Method::GET, path, &[]).await,
        }
    }

    async fn put(&self, path: &str, bytes: &[u8]) -> Result<(), String> {
        match self {
            Self::WebDav {
                client,
                endpoint,
                username,
                password,
            } => {
                ensure_webdav_parents(
                    client,
                    endpoint,
                    path,
                    username.as_deref(),
                    password.as_deref(),
                )
                .await?;
                let url = join_url(endpoint, path)?;
                let mut request = client.put(url).body(bytes.to_vec());
                if let Some(username) = username {
                    request = request.basic_auth(username, password.as_deref());
                }
                let response = send_webdav_request(request).await?;
                if !response.status().is_success() {
                    return Err(format!("WebDAV 写入失败：{}", response.status()));
                }
                Ok(())
            }
            Self::S3 { .. } => {
                let _ = self.s3_request(Method::PUT, path, bytes).await?;
                Ok(())
            }
        }
    }

    async fn s3_request(
        &self,
        method: Method,
        path: &str,
        body: &[u8],
    ) -> Result<Option<Vec<u8>>, String> {
        let Self::S3 {
            client,
            endpoint,
            bucket,
            region,
            access_key,
            secret_key,
            prefix,
        } = self
        else {
            return Err("内部同步后端错误".into());
        };
        let object_key = [prefix.trim_matches('/'), path]
            .into_iter()
            .filter(|part| !part.is_empty())
            .collect::<Vec<_>>()
            .join("/");
        let relative = format!("{}/{}", bucket.trim_matches('/'), object_key);
        let url = join_url(endpoint, &relative)?;
        let (authorization, amz_date, payload_hash) =
            sign_s3(&method, &url, body, region, access_key, secret_key)?;
        let response = client
            .request(method.clone(), url)
            .header("x-amz-date", amz_date)
            .header("x-amz-content-sha256", payload_hash)
            .header("authorization", authorization)
            .body(body.to_vec())
            .send()
            .await
            .map_err(|e| e.to_string())?;
        if method == Method::GET && response.status() == StatusCode::NOT_FOUND {
            return Ok(None);
        }
        if !response.status().is_success() {
            return Err(format!("S3 请求失败：{}", response.status()));
        }
        if method == Method::GET {
            Ok(Some(
                response.bytes().await.map_err(|e| e.to_string())?.to_vec(),
            ))
        } else {
            Ok(Some(Vec::new()))
        }
    }
}

fn configured_backend(state: &AppState) -> Result<RemoteBackend, String> {
    let settings = settings_object(state)?;
    configured_backend_from(&settings)
}

fn configured_backend_from(settings: &Map<String, Value>) -> Result<RemoteBackend, String> {
    let backend = string_setting(settings, "syncBackend").unwrap_or_default();
    let endpoint = string_setting(settings, "syncEndpoint")
        .filter(|value| !value.trim().is_empty())
        .ok_or_else(|| "请先在桌面端配置同步地址".to_string())?;
    let endpoint = Url::parse(&endpoint).map_err(|e| format!("同步地址无效：{e}"))?;
    let client = Client::builder()
        .timeout(Duration::from_secs(30))
        .build()
        .map_err(|e| e.to_string())?;
    match backend.as_str() {
        "webdav" => Ok(RemoteBackend::WebDav {
            client,
            endpoint,
            username: string_setting(settings, "syncUsername"),
            password: string_setting(settings, "syncPassword"),
        }),
        "s3" => Ok(RemoteBackend::S3 {
            client,
            endpoint,
            bucket: required_setting(settings, "syncBucket", "S3 Bucket")?,
            region: string_setting(settings, "syncRegion").unwrap_or_else(|| "us-east-1".into()),
            access_key: required_setting(settings, "syncAccessKey", "S3 Access Key")?,
            secret_key: required_setting(settings, "syncSecretKey", "S3 Secret Key")?,
            prefix: string_setting(settings, "syncPrefix").unwrap_or_else(|| "leeef".into()),
        }),
        _ => Err("请先选择 S3 或 WebDAV 同步后端".into()),
    }
}

fn previous_backend(state: &AppState) -> Option<RemoteBackend> {
    let settings = db::kv_get(state, PREVIOUS_BACKEND_KEY)
        .ok()
        .flatten()
        .and_then(|raw| serde_json::from_str::<Value>(&raw).ok())?;
    configured_backend_from(settings.as_object()?).ok()
}

fn backend_fingerprint(settings: &Map<String, Value>) -> String {
    const KEYS: &[&str] = &[
        "syncBackend",
        "syncEndpoint",
        "syncUsername",
        "syncPassword",
        "syncBucket",
        "syncRegion",
        "syncAccessKey",
        "syncSecretKey",
        "syncPrefix",
    ];
    let values: BTreeMap<_, _> = KEYS
        .iter()
        .map(|key| (*key, settings.get(*key).cloned().unwrap_or(Value::Null)))
        .collect();
    value_digest(&serde_json::to_value(values).unwrap_or(Value::Null))
}

fn required_setting(
    settings: &Map<String, Value>,
    key: &str,
    label: &str,
) -> Result<String, String> {
    string_setting(settings, key)
        .filter(|value| !value.trim().is_empty())
        .ok_or_else(|| format!("请填写 {label}"))
}

fn string_setting(settings: &Map<String, Value>, key: &str) -> Option<String> {
    settings.get(key)?.as_str().map(ToOwned::to_owned)
}

fn join_url(base: &Url, relative: &str) -> Result<Url, String> {
    let mut value = base.as_str().trim_end_matches('/').to_string();
    value.push('/');
    value.push_str(relative.trim_start_matches('/'));
    Url::parse(&value).map_err(|e| e.to_string())
}

async fn ensure_webdav_parents(
    client: &Client,
    endpoint: &Url,
    path: &str,
    username: Option<&str>,
    password: Option<&str>,
) -> Result<(), String> {
    let parts: Vec<_> = path.split('/').collect();
    for end in 1..parts.len() {
        let url = join_url(endpoint, &parts[..end].join("/"))?;
        let mut request = client.request(Method::from_bytes(b"MKCOL").unwrap(), url);
        if let Some(username) = username {
            request = request.basic_auth(username, password);
        }
        let response = send_webdav_request(request).await?;
        let status = response.status();
        response.bytes().await.map_err(request_error)?;
        if !(status.is_success()
            || status == StatusCode::METHOD_NOT_ALLOWED
            || status == StatusCode::CONFLICT)
        {
            return Err(format!("WebDAV 创建目录失败：{status}"));
        }
    }
    Ok(())
}

fn sign_s3(
    method: &Method,
    url: &Url,
    body: &[u8],
    region: &str,
    access_key: &str,
    secret_key: &str,
) -> Result<(String, String, String), String> {
    let now = time::OffsetDateTime::now_utc();
    let month = u8::from(now.month());
    let date = format!("{:04}{:02}{:02}", now.year(), month, now.day());
    let amz_date = format!(
        "{}T{:02}{:02}{:02}Z",
        date,
        now.hour(),
        now.minute(),
        now.second()
    );
    let payload_hash = hex::encode(Sha256::digest(body));
    let host = match url.port() {
        Some(port) => format!("{}:{port}", url.host_str().ok_or("S3 地址缺少主机名")?),
        None => url.host_str().ok_or("S3 地址缺少主机名")?.to_string(),
    };
    let canonical_headers =
        format!("host:{host}\nx-amz-content-sha256:{payload_hash}\nx-amz-date:{amz_date}\n");
    let signed_headers = "host;x-amz-content-sha256;x-amz-date";
    let canonical_request = format!(
        "{}\n{}\n{}\n{}\n{}\n{}",
        method.as_str(),
        url.path(),
        url.query().unwrap_or(""),
        canonical_headers,
        signed_headers,
        payload_hash
    );
    let scope = format!("{date}/{region}/s3/aws4_request");
    let string_to_sign = format!(
        "AWS4-HMAC-SHA256\n{amz_date}\n{scope}\n{}",
        hex::encode(Sha256::digest(canonical_request.as_bytes()))
    );
    let date_key = hmac_sha256(format!("AWS4{secret_key}").as_bytes(), date.as_bytes())?;
    let region_key = hmac_sha256(&date_key, region.as_bytes())?;
    let service_key = hmac_sha256(&region_key, b"s3")?;
    let signing_key = hmac_sha256(&service_key, b"aws4_request")?;
    let signature = hex::encode(hmac_sha256(&signing_key, string_to_sign.as_bytes())?);
    let authorization = format!(
        "AWS4-HMAC-SHA256 Credential={access_key}/{scope}, SignedHeaders={signed_headers}, Signature={signature}"
    );
    Ok((authorization, amz_date, payload_hash))
}

fn hmac_sha256(key: &[u8], data: &[u8]) -> Result<Vec<u8>, String> {
    let mut mac = <Hmac<Sha256> as Mac>::new_from_slice(key).map_err(|e| e.to_string())?;
    mac.update(data);
    Ok(mac.finalize().into_bytes().to_vec())
}

#[derive(Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
struct PairResponse {
    nonce: String,
    ciphertext: String,
}

#[derive(Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
struct PairingSnapshot {
    space: SpaceState,
    devices: Vec<String>,
    configuration: ConfigurationDocument,
}

#[derive(Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
struct DiscoveryRequest {
    kind: String,
    code_hash: String,
}

#[derive(Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
struct DiscoveryResponse {
    kind: String,
    session_id: String,
    port: u16,
    host_public_key: String,
}

fn pairing_proof(
    code: &str,
    session_id: &str,
    device_id: &str,
    public_key: &[u8; 32],
) -> Result<String, String> {
    let mut mac =
        <Hmac<Sha256> as Mac>::new_from_slice(code.as_bytes()).map_err(|e| e.to_string())?;
    mac.update(session_id.as_bytes());
    mac.update(device_id.as_bytes());
    mac.update(public_key);
    Ok(URL_SAFE_NO_PAD.encode(mac.finalize().into_bytes()))
}

fn derive_pairing_key(
    shared_secret: &[u8],
    code: &str,
    session_id: &str,
) -> Result<[u8; 32], String> {
    let hkdf = Hkdf::<Sha256>::new(Some(code.as_bytes()), shared_secret);
    let mut key = [0_u8; 32];
    hkdf.expand(session_id.as_bytes(), &mut key)
        .map_err(|_| "无法派生配对密钥".to_string())?;
    Ok(key)
}

fn encrypt_pairing_snapshot(
    snapshot: &PairingSnapshot,
    key: &[u8; 32],
) -> Result<PairResponse, String> {
    let mut nonce = [0_u8; 12];
    rand::thread_rng().fill_bytes(&mut nonce);
    let cipher = Aes256Gcm::new_from_slice(key).map_err(|e| e.to_string())?;
    let plaintext = serde_json::to_vec(snapshot).map_err(|e| e.to_string())?;
    let ciphertext = cipher
        .encrypt(Nonce::from_slice(&nonce), plaintext.as_ref())
        .map_err(|_| "无法加密配对快照".to_string())?;
    Ok(PairResponse {
        nonce: URL_SAFE_NO_PAD.encode(nonce),
        ciphertext: URL_SAFE_NO_PAD.encode(ciphertext),
    })
}

fn decrypt_pairing_snapshot(
    response: &PairResponse,
    key: &[u8; 32],
) -> Result<PairingSnapshot, String> {
    let nonce = URL_SAFE_NO_PAD
        .decode(&response.nonce)
        .map_err(|e| e.to_string())?;
    if nonce.len() != 12 {
        return Err("配对快照 nonce 无效".into());
    }
    let ciphertext = URL_SAFE_NO_PAD
        .decode(&response.ciphertext)
        .map_err(|e| e.to_string())?;
    let cipher = Aes256Gcm::new_from_slice(key).map_err(|e| e.to_string())?;
    let plaintext = cipher
        .decrypt(Nonce::from_slice(&nonce), ciphertext.as_ref())
        .map_err(|_| "配对快照校验失败".to_string())?;
    serde_json::from_slice(&plaintext).map_err(|e| e.to_string())
}

fn pairing_code() -> String {
    let mut rng = rand::thread_rng();
    (0..12)
        .map(|_| *PAIRING_ALPHABET.choose(&mut rng).unwrap() as char)
        .collect()
}

fn ensure_space(state: &AppState) -> Result<SpaceState, String> {
    let mut db = state.db.lock().map_err(|error| error.to_string())?;
    let tx = db.transaction().map_err(|error| error.to_string())?;
    if let Some(space) = decode_space(db::kv_get_on(&tx, SPACE_KEY)?)? {
        return Ok(space);
    }
    let mut key = [0_u8; 32];
    rand::thread_rng().fill_bytes(&mut key);
    let space = SpaceState {
        id: uuid::Uuid::new_v4().to_string(),
        key: URL_SAFE_NO_PAD.encode(key),
    };
    db::kv_set_on(
        &tx,
        SPACE_KEY,
        &serde_json::to_string(&space).map_err(|error| error.to_string())?,
    )?;
    write_roster(
        &tx,
        &BTreeSet::from([state.device_id.clone()]),
        &BTreeMap::new(),
    )?;
    tx.commit().map_err(|error| error.to_string())?;
    Ok(space)
}

fn load_space(state: &AppState) -> Result<Option<SpaceState>, String> {
    decode_space(db::kv_get(state, SPACE_KEY)?)
}

fn decode_space(value: Option<String>) -> Result<Option<SpaceState>, String> {
    value
        .map(|value| serde_json::from_str(&value).map_err(|error| error.to_string()))
        .transpose()
}

fn load_devices(state: &AppState) -> Result<Vec<String>, String> {
    Ok(db::kv_get(state, DEVICES_KEY)?
        .and_then(|value| serde_json::from_str(&value).ok())
        .unwrap_or_else(|| vec![state.device_id.clone()]))
}

fn load_devices_on(db: &rusqlite::Connection) -> Result<BTreeSet<String>, String> {
    Ok(db::kv_get_on(db, DEVICES_KEY)?
        .and_then(|value| serde_json::from_str(&value).ok())
        .unwrap_or_default())
}

fn load_device_names(db: &rusqlite::Connection) -> Result<BTreeMap<String, String>, String> {
    Ok(db::kv_get_on(db, DEVICE_NAMES_KEY)?
        .and_then(|value| serde_json::from_str(&value).ok())
        .unwrap_or_default())
}

fn clean_device_name(name: &str) -> Option<String> {
    let name: String = name
        .trim()
        .chars()
        .filter(|c| !c.is_control())
        .take(60)
        .collect();
    (!name.is_empty()).then_some(name)
}

fn check_roster_space(db: &rusqlite::Connection, space: &SpaceState) -> Result<(), String> {
    if decode_space(db::kv_get_on(db, SPACE_KEY)?)?.is_some_and(|current| current.id == space.id) {
        Ok(())
    } else {
        Err("同步空间已更换，请重试。".into())
    }
}

fn configuration_document(
    state: &AppState,
    space: &SpaceState,
) -> Result<ConfigurationDocument, String> {
    let mut device_names = {
        let db = state.db.lock().map_err(|error| error.to_string())?;
        check_roster_space(&db, space)?;
        load_device_names(&db)?
    };
    device_names.insert(state.device_id.clone(), pairing::device_name());
    Ok(ConfigurationDocument {
        version: 1,
        space_id: space.id.clone(),
        device_id: state.device_id.clone(),
        device_names,
        entries: capture_configuration(state)?,
    })
}

fn refresh_paired_devices(state: &AppState, status: &mut SyncStatus) {
    status.paired = false;
    status.paired_devices.clear();
    let Ok(db) = state.db.lock() else { return };
    status.paired = decode_space(db::kv_get_on(&db, SPACE_KEY).ok().flatten())
        .ok()
        .flatten()
        .is_some();
    if !status.paired {
        return;
    }
    let names = load_device_names(&db).unwrap_or_default();
    status.paired_devices = load_devices_on(&db)
        .unwrap_or_default()
        .into_iter()
        .filter(|id| id != &state.device_id)
        .map(|id| PairedDevice {
            name: names.get(&id).cloned(),
            id,
        })
        .collect();
    status.paired_devices.sort_by(|a, b| {
        a.name
            .is_none()
            .cmp(&b.name.is_none())
            .then_with(|| a.name.cmp(&b.name))
            .then_with(|| a.id.cmp(&b.id))
    });
}

fn write_roster(
    db: &rusqlite::Connection,
    devices: &BTreeSet<String>,
    names: &BTreeMap<String, String>,
) -> Result<(), String> {
    db::kv_set_on(
        db,
        DEVICES_KEY,
        &serde_json::to_string(devices).map_err(|e| e.to_string())?,
    )?;
    db::kv_set_on(
        db,
        DEVICE_NAMES_KEY,
        &serde_json::to_string(names).map_err(|e| e.to_string())?,
    )
}

fn update_roster<T>(
    state: &AppState,
    space: &SpaceState,
    update: impl FnOnce(&mut BTreeSet<String>, &mut BTreeMap<String, String>) -> Result<T, String>,
) -> Result<T, String> {
    let mut db = state.db.lock().map_err(|error| error.to_string())?;
    let tx = db.transaction().map_err(|error| error.to_string())?;
    check_roster_space(&tx, space)?;
    let mut devices = load_devices_on(&tx)?;
    let mut names = load_device_names(&tx)?;
    let result = update(&mut devices, &mut names)?;
    if devices.len() > 256 {
        return Err("同步设备数量超出支持范围".into());
    }
    write_roster(&tx, &devices, &names)?;
    tx.commit().map_err(|error| error.to_string())?;
    Ok(result)
}

fn remember_configuration_devices(
    state: &AppState,
    space: &SpaceState,
    documents: &[ConfigurationDocument],
) -> Result<(), String> {
    update_roster(state, space, |devices, names| {
        for document in documents {
            for (id, name) in &document.device_names {
                if id == &state.device_id || uuid::Uuid::parse_str(id).is_err() {
                    continue;
                }
                if let Some(name) = clean_device_name(name) {
                    devices.insert(id.clone());
                    if id == &document.device_id {
                        names.insert(id.clone(), name);
                    } else {
                        names.entry(id.clone()).or_insert(name);
                    }
                }
            }
        }
        Ok(())
    })
}

fn settings_object(state: &AppState) -> Result<Map<String, Value>, String> {
    Ok(decode_settings(db::kv_get(state, "settings")?))
}

fn decode_settings(value: Option<String>) -> Map<String, Value> {
    value
        .and_then(|raw| serde_json::from_str(&raw).ok())
        .unwrap_or_default()
}

fn load_versions(state: &AppState) -> Result<BTreeMap<String, ConfigurationVersion>, String> {
    Ok(db::kv_get(state, VERSIONS_KEY)?
        .and_then(|value| serde_json::from_str(&value).ok())
        .unwrap_or_default())
}

fn save_versions(
    state: &AppState,
    versions: &BTreeMap<String, ConfigurationVersion>,
) -> Result<(), String> {
    db::kv_set(
        state,
        VERSIONS_KEY,
        &serde_json::to_string(versions).map_err(|e| e.to_string())?,
    )
}

fn value_digest(value: &Value) -> String {
    hex::encode(Sha256::digest(value.to_string().as_bytes()))
}

fn sha256_text(value: &str) -> String {
    hex::encode(Sha256::digest(value.as_bytes()))
}

fn now_millis() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_millis() as u64
}

#[cfg(test)]
mod tests {
    use super::*;
    use axum::{
        body::Bytes,
        extract::{Path, State as AxumState},
        http::StatusCode,
        routing::get,
        Router,
    };
    use std::collections::HashMap;
    use std::net::Ipv4Addr;
    use tempfile::tempdir;

    fn state(name: &str) -> AppState {
        db::open(tempdir().unwrap().keep().join(name)).unwrap()
    }

    #[test]
    fn last_outcome_survives_restart_but_scope_and_pending_count_are_live() {
        let root = tempfile::tempdir().unwrap();
        let state = db::open(root.path().into()).unwrap();
        let saved = SyncStatus {
            last_attempt_at: Some(123),
            last_success_at: Some(100),
            last_error: Some("offline".into()),
            progress: SyncProgress {
                phase: "downloading".into(),
                completed: 1,
                total: 2,
                current_item: Some("Book".into()),
            },
            ..Default::default()
        };
        db::kv_set(
            &state,
            "sync_last_outcome",
            &serde_json::to_string(&saved).unwrap(),
        )
        .unwrap();
        db::kv_set(
            &state,
            "settings",
            r#"{"syncLibrary":true,"autoSync":false}"#,
        )
        .unwrap();
        db::import_book(
            &state,
            "test.txt",
            b"pending",
            "Pending",
            None,
            "text/plain",
            None,
        )
        .unwrap();
        let status = SyncRuntime::default().status(&state);
        assert_eq!(status.last_success_at, Some(100));
        assert_eq!(status.last_error.as_deref(), Some("offline"));
        assert_eq!(status.progress.current_item.as_deref(), Some("Book"));
        assert!(!status.running);
        assert!(status.library_enabled);
        assert!(!status.auto_sync);
        assert_eq!(status.pending_records, Some(1));
    }

    #[test]
    fn configuration_merge_uses_latest_value_per_field() {
        let state = state("merge");
        save_settings(
            &state,
            serde_json::json!({
                "theme": "paper", "fontSize": 18, "autoSync": true, "opdsCatalogs": []
            }),
        )
        .unwrap();
        let local = capture_configuration(&state).unwrap();
        assert!(!local.contains_key("opdsCatalogs"));
        let timestamp = local["theme"].modified_at + 10;
        let remote = ConfigurationDocument {
            version: 1,
            space_id: "space".into(),
            device_id: "remote".into(),
            device_names: BTreeMap::new(),
            entries: BTreeMap::from([
                (
                    "theme".into(),
                    ConfigurationEntry {
                        value: Value::String("night".into()),
                        modified_at: timestamp,
                        modified_by: "remote".into(),
                    },
                ),
                (
                    "fontSize".into(),
                    ConfigurationEntry {
                        value: Value::from(22),
                        modified_at: timestamp,
                        modified_by: "remote".into(),
                    },
                ),
                (
                    "autoSync".into(),
                    ConfigurationEntry {
                        value: Value::Bool(false),
                        modified_at: timestamp,
                        modified_by: "remote".into(),
                    },
                ),
                (
                    "opdsCatalogs".into(),
                    ConfigurationEntry {
                        value: serde_json::json!([{"name": "Legacy", "url": "https://example.com"}]),
                        modified_at: timestamp,
                        modified_by: "remote".into(),
                    },
                ),
            ]),
        };
        assert_eq!(merge_configuration(&state, [remote]).unwrap(), 2);
        let settings = settings_object(&state).unwrap();
        assert_eq!(settings["theme"], "night");
        assert_eq!(settings["fontSize"], 22);
        assert_eq!(settings["autoSync"], true);
        assert_eq!(settings["opdsCatalogs"], serde_json::json!([]));
    }

    #[test]
    fn encrypted_configuration_rejects_wrong_key() {
        let document = ConfigurationDocument {
            version: 1,
            space_id: "space".into(),
            device_id: "device".into(),
            device_names: BTreeMap::new(),
            entries: BTreeMap::new(),
        };
        let bytes = encrypt_document(&document, &[7; 32]).unwrap();
        let decoded: ConfigurationDocument = decrypt_document(&bytes, &[7; 32]).unwrap();
        assert_eq!(decoded.device_id, "device");
        assert!(decrypt_document::<ConfigurationDocument>(&bytes, &[8; 32]).is_err());
    }

    #[test]
    fn pairing_snapshot_uses_shared_secret_and_code() {
        let left = StaticSecret::random_from_rng(rand::rngs::OsRng);
        let right = StaticSecret::random_from_rng(rand::rngs::OsRng);
        let left_shared = left.diffie_hellman(&PublicKey::from(&right));
        let right_shared = right.diffie_hellman(&PublicKey::from(&left));
        let left_key =
            derive_pairing_key(left_shared.as_bytes(), "23456789ABCD", "session").unwrap();
        let right_key =
            derive_pairing_key(right_shared.as_bytes(), "23456789ABCD", "session").unwrap();
        assert_eq!(left_key, right_key);
    }

    #[test]
    fn encrypted_recovery_package_restores_space_and_configuration() {
        let source = state("recovery-source");
        save_settings(
            &source,
            serde_json::json!({
                "theme": "night",
                "aiKey": "secret-key",
                "syncBackend": "webdav",
                "syncEndpoint": "https://dav.example.com/leeef"
            }),
        )
        .unwrap();
        let source_space = ensure_space(&source).unwrap();
        let package = export_recovery(&source, "correct horse battery staple").unwrap();
        assert!(!package.contains("secret-key"));

        let restored = state("recovery-target");
        save_settings(&restored, serde_json::json!({"autoSync": false})).unwrap();
        assert!(
            import_recovery(&restored, &package, "wrong password but long enough", false,).is_err()
        );
        import_recovery(&restored, &package, "correct horse battery staple", false).unwrap();
        assert_eq!(load_space(&restored).unwrap().unwrap().id, source_space.id);
        let settings = settings_object(&restored).unwrap();
        assert_eq!(settings["theme"], "night");
        assert_eq!(settings["aiKey"], "secret-key");
        assert_eq!(settings["autoSync"], false);
    }

    #[test]
    fn recovery_does_not_replace_another_space_without_confirmation() {
        let source = state("recovery-replace-source");
        save_settings(&source, serde_json::json!({"theme": "sepia"})).unwrap();
        ensure_space(&source).unwrap();
        let package = export_recovery(&source, "twelve-character-password").unwrap();

        let target = state("recovery-replace-target");
        let old_space = ensure_space(&target).unwrap();
        let old_peer = uuid::Uuid::new_v4().to_string();
        update_roster(&target, &old_space, |devices, names| {
            devices.insert(old_peer.clone());
            names.insert(old_peer.clone(), "Old peer".into());
            Ok(())
        })
        .unwrap();
        assert!(import_recovery(&target, &package, "twelve-character-password", false,).is_err());
        assert_eq!(
            SyncRuntime::default().status(&target).paired_devices[0].id,
            old_peer
        );
        assert!(import_recovery(&target, &package, "twelve-character-password", true,).is_ok());
        let restored = SyncRuntime::default().status(&target);
        assert_eq!(restored.paired_devices.len(), 1);
        assert_eq!(restored.paired_devices[0].id, source.device_id);
        assert!(restored.paired_devices[0].name.is_some());
    }

    #[tokio::test]
    async fn desktop_change_reaches_paired_device_on_next_sync() {
        type Documents = Arc<Mutex<HashMap<String, Vec<u8>>>>;
        async fn read(
            AxumState(documents): AxumState<Documents>,
            Path(path): Path<String>,
        ) -> Result<Vec<u8>, StatusCode> {
            documents
                .lock()
                .unwrap()
                .get(&path)
                .cloned()
                .ok_or(StatusCode::NOT_FOUND)
        }
        async fn write(
            AxumState(documents): AxumState<Documents>,
            Path(path): Path<String>,
            body: Bytes,
        ) -> StatusCode {
            documents.lock().unwrap().insert(path, body.to_vec());
            StatusCode::NO_CONTENT
        }

        let documents: Documents = Arc::new(Mutex::new(HashMap::new()));
        let listener = tokio::net::TcpListener::bind((Ipv4Addr::LOCALHOST, 0))
            .await
            .unwrap();
        let address = listener.local_addr().unwrap();
        let router = Router::new()
            .route("/{*path}", get(read).put(write))
            .with_state(documents.clone());
        tokio::spawn(async move { axum::serve(listener, router).await.unwrap() });

        let desktop = state("desktop-sync");
        let phone = state("phone-sync");
        let endpoint = format!("http://{address}");
        save_settings(
            &desktop,
            serde_json::json!({
                "theme": "paper",
                "syncBackend": "webdav",
                "syncEndpoint": endpoint
            }),
        )
        .unwrap();
        let space = ensure_space(&desktop).unwrap();
        let devices = serde_json::to_string(&[&desktop.device_id, &phone.device_id]).unwrap();
        db::kv_set(&desktop, DEVICES_KEY, &devices).unwrap();
        db::kv_set(&phone, SPACE_KEY, &serde_json::to_string(&space).unwrap()).unwrap();
        db::kv_set(&phone, DEVICES_KEY, &devices).unwrap();
        let legacy = SyncRuntime::default().status(&phone);
        assert_eq!(legacy.paired_devices.len(), 1);
        assert_eq!(legacy.paired_devices[0].id, desktop.device_id);
        assert!(legacy.paired_devices[0].name.is_none());
        apply_pairing_configuration(
            &phone,
            ConfigurationDocument {
                version: 1,
                space_id: space.id.clone(),
                device_id: desktop.device_id.clone(),
                device_names: BTreeMap::new(),
                entries: capture_configuration(&desktop).unwrap(),
            },
        )
        .unwrap();

        let tablet_id = uuid::Uuid::new_v4().to_string();
        update_roster(&desktop, &space, |ids, names| {
            ids.insert(tablet_id.clone());
            names.insert(tablet_id.clone(), "Test tablet".into());
            Ok(())
        })
        .unwrap();
        synchronize(&desktop).await.unwrap();
        let mut updated = settings_object(&desktop).unwrap();
        updated.insert("theme".into(), Value::String("night".into()));
        save_settings(&desktop, Value::Object(updated)).unwrap();
        synchronize(&desktop).await.unwrap();
        assert_eq!(synchronize(&phone).await.unwrap(), 1);
        assert_eq!(settings_object(&phone).unwrap()["theme"], "night");
        let synced = SyncRuntime::default().status(&phone);
        assert_eq!(synced.paired_devices.len(), 2);
        assert!(synced
            .paired_devices
            .iter()
            .any(|device| device.id == desktop.device_id && device.name.is_some()));
        assert!(synced
            .paired_devices
            .iter()
            .any(|device| device.id == tablet_id && device.name.as_deref() == Some("Test tablet")));

        let mut migrated = settings_object(&desktop).unwrap();
        migrated.insert("theme".into(), Value::String("sepia".into()));
        migrated.insert(
            "syncEndpoint".into(),
            Value::String(format!("{endpoint}/next")),
        );
        save_settings(&desktop, Value::Object(migrated)).unwrap();
        synchronize(&desktop).await.unwrap();
        assert!(synchronize(&phone).await.unwrap() >= 2);
        let phone_settings = settings_object(&phone).unwrap();
        assert_eq!(phone_settings["theme"], "sepia");
        assert_eq!(phone_settings["syncEndpoint"], format!("{endpoint}/next"));
        synchronize(&phone).await.unwrap();

        let mut settings = settings_object(&desktop).unwrap();
        settings.insert("syncLibrary".into(), Value::Bool(true));
        save_settings(&desktop, Value::Object(settings)).unwrap();
        let book = db::import_book(
            &desktop,
            "test.txt",
            b"private book content",
            "Book",
            None,
            "text/plain",
            Some(b"cover bytes"),
        )
        .unwrap();
        db::save_progress(&desktop, &book.id, "chapter-3", 0.3, None, None).unwrap();
        synchronize(&desktop).await.unwrap();
        let reports = Mutex::new(Vec::<SyncProgress>::new());
        let report = |p| reports.lock().unwrap().push(p);
        synchronize_library_with_progress(&desktop, &report)
            .await
            .unwrap();
        assert!(reports
            .lock()
            .unwrap()
            .iter()
            .any(|p| p.phase == "uploading" && p.completed == 2 && p.total == 2));
        assert!(reports
            .lock()
            .unwrap()
            .iter()
            .any(|p| p.current_item.as_deref() == Some("Book")));
        assert_eq!(library_sync::pending_count(&desktop).unwrap(), 0);
        reports.lock().unwrap().clear();
        synchronize(&phone).await.unwrap();
        let object_path = format!(
            "next/trusted/{}/library/objects/{}",
            load_space(&desktop).unwrap().unwrap().id,
            book.sha256
        );
        let ciphertext = documents.lock().unwrap().remove(&object_path).unwrap();
        assert!(!String::from_utf8_lossy(&ciphertext).contains("private book content"));
        assert!(synchronize_library_with_progress(&phone, &report)
            .await
            .is_err());
        assert_eq!(reports.lock().unwrap().last().unwrap().phase, "downloading");
        assert!(reports
            .lock()
            .unwrap()
            .last()
            .unwrap()
            .current_item
            .is_some());
        assert!(db::list_books(&phone).unwrap().is_empty());
        documents.lock().unwrap().insert(object_path, ciphertext);
        reports.lock().unwrap().clear();
        assert!(
            synchronize_library_with_progress(&phone, &report)
                .await
                .unwrap()
                > 0
        );
        assert!(reports
            .lock()
            .unwrap()
            .iter()
            .any(|p| p.phase == "downloading" && p.completed == p.total && p.total > 0));
        assert_eq!(reports.lock().unwrap().last().unwrap().phase, "merging");
        let phone_book = db::list_books(&phone).unwrap().remove(0);
        assert_eq!(
            db::book_bytes(&phone, &phone_book.id).unwrap(),
            b"private book content"
        );
        assert_eq!(
            db::book_cover(&phone, &phone_book.id).unwrap(),
            b"cover bytes"
        );
        assert_eq!(phone_book.locator.as_deref(), Some("chapter-3"));
        let excerpt = db::upsert_excerpt(
            &phone,
            &phone_book.id,
            "chapter-3",
            "quote",
            Some("offline note"),
            "yellow",
        )
        .unwrap();
        db::save_progress(&phone, &phone_book.id, "chapter-1", 0.1, None, None).unwrap();
        synchronize_library(&phone).await.unwrap();
        synchronize_library(&desktop).await.unwrap();
        assert_eq!(
            db::list_excerpts(&desktop, Some(&book.id)).unwrap()[0]
                .note
                .as_deref(),
            Some("offline note")
        );
        assert_eq!(
            db::list_books(&desktop).unwrap()[0].locator.as_deref(),
            Some("chapter-1")
        );
        db::delete_excerpt(&phone, &excerpt).unwrap();
        synchronize_library(&phone).await.unwrap();
        synchronize_library(&desktop).await.unwrap();
        assert!(db::list_excerpts(&desktop, Some(&book.id))
            .unwrap()
            .is_empty());
        assert_eq!(synchronize_library(&desktop).await.unwrap(), 0);
    }
}
