use aes_gcm::{
    aead::{Aead, KeyInit},
    Aes256Gcm, Nonce,
};
use axum::{extract::State as AxumState, http::StatusCode, routing::post, Json, Router};
use base64::{engine::general_purpose::URL_SAFE_NO_PAD, Engine as _};
use hkdf::Hkdf;
use hmac::{Hmac, Mac};
use rand::{seq::SliceRandom, RngCore};
use reqwest::{Client, Method, Url};
use serde::{Deserialize, Serialize};
use serde_json::{Map, Value};
use sha2::{Digest, Sha256};
use std::{
    collections::{BTreeMap, BTreeSet},
    net::{IpAddr, Ipv4Addr, SocketAddr},
    sync::{
        atomic::{AtomicBool, Ordering},
        Arc, Mutex,
    },
    time::{Duration, SystemTime, UNIX_EPOCH},
};
use tauri::{AppHandle, Emitter};
use tokio::{net::UdpSocket, sync::Notify};
use tokio_util::sync::CancellationToken;
use x25519_dalek::{PublicKey, StaticSecret};

use crate::db::{self, AppState};

const SPACE_KEY: &str = "trusted_sync_space";
const DEVICES_KEY: &str = "trusted_sync_devices";
const VERSIONS_KEY: &str = "trusted_sync_settings_versions";
const PREVIOUS_BACKEND_KEY: &str = "trusted_sync_previous_backend";
const DISCOVERY_PORT: u16 = 43781;
const PAIRING_TTL: Duration = Duration::from_secs(300);
const PAIRING_ALPHABET: &[u8] = b"23456789ABCDEFGHJKLMNPQRSTUVWXYZ";

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

#[derive(Clone, Debug, Default, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct SyncStatus {
    pub paired: bool,
    pub configured: bool,
    pub auto_sync: bool,
    pub running: bool,
    pub last_success_at: Option<u64>,
    pub last_error: Option<String>,
    pub applied_values: usize,
}

#[derive(Clone)]
pub struct SyncRuntime {
    notify: Arc<Notify>,
    status: Arc<Mutex<SyncStatus>>,
    pairing_cancel: Arc<Mutex<Option<CancellationToken>>>,
}

impl Default for SyncRuntime {
    fn default() -> Self {
        Self {
            notify: Arc::new(Notify::new()),
            status: Arc::new(Mutex::new(SyncStatus::default())),
            pairing_cancel: Arc::new(Mutex::new(None)),
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
        status.paired = load_space(state).ok().flatten().is_some();
        status.configured = configured_backend(state).is_ok();
        status.auto_sync = auto_sync_enabled(state);
        status
    }

    fn replace_pairing(&self, cancellation: CancellationToken) -> Result<(), String> {
        let mut current = self.pairing_cancel.lock().map_err(|e| e.to_string())?;
        if let Some(previous) = current.replace(cancellation) {
            previous.cancel();
        }
        Ok(())
    }
}

pub fn start_background(app: AppHandle, state: AppState, runtime: SyncRuntime) {
    tauri::async_runtime::spawn(async move {
        let mut interval = tokio::time::interval(Duration::from_secs(15 * 60));
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
            status.running = true;
            status.last_error = None;
        }
    }

    let result = synchronize(state).await;
    let mut changed = false;
    if let Ok(mut status) = runtime.status.lock() {
        status.running = false;
        status.paired = load_space(state).ok().flatten().is_some();
        status.configured = configured_backend(state).is_ok();
        status.auto_sync = auto_sync_enabled(state);
        match result {
            Ok(applied) => {
                changed = applied > 0;
                status.last_success_at = Some(now_millis());
                status.last_error = None;
                status.applied_values = applied;
            }
            Err(error) => status.last_error = Some(error),
        }
        let _ = app.emit("settings-sync-status", status.clone());
    }
    if changed {
        let _ = app.emit("settings-synced", ());
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
    !matches!(key, "autoSync" | "syncLastError" | "syncLastSuccessAt")
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

fn apply_pairing_configuration(
    state: &AppState,
    document: ConfigurationDocument,
) -> Result<usize, String> {
    let mut settings = settings_object(state)?;
    let local_only: BTreeMap<String, Value> = settings
        .iter()
        .filter(|(key, _)| !portable_key(key))
        .map(|(key, value)| (key.clone(), value.clone()))
        .collect();
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
    for (key, value) in local_only {
        settings.insert(key, value);
    }
    db::kv_set(state, "settings", &Value::Object(settings).to_string())?;
    save_versions(state, &versions)?;
    Ok(changed)
}

async fn synchronize(state: &AppState) -> Result<usize, String> {
    let Some(space) = load_space(state)? else {
        return Ok(0);
    };
    let backend = configured_backend(state)?;
    let entries = capture_configuration(state)?;
    let own = ConfigurationDocument {
        version: 1,
        space_id: space.id.clone(),
        device_id: state.device_id.clone(),
        entries,
    };
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
            if document.space_id == space.id && document.device_id == device_id {
                documents.push(document);
            }
        }
    }
    let changed = merge_configuration(state, documents)?;

    // Publish the merged view so another device can converge in one later pull.
    let merged = ConfigurationDocument {
        version: 1,
        space_id: space.id.clone(),
        device_id: state.device_id.clone(),
        entries: capture_configuration(state)?,
    };
    backend
        .put(&own_path, &encrypt_document(&merged, &space.key_bytes()?)?)
        .await?;
    Ok(changed)
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
                let response = request.send().await.map_err(|e| e.to_string())?;
                if response.status() == StatusCode::NOT_FOUND {
                    return Ok(None);
                }
                if !response.status().is_success() {
                    return Err(format!("WebDAV 读取失败：{}", response.status()));
                }
                Ok(Some(
                    response.bytes().await.map_err(|e| e.to_string())?.to_vec(),
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
                let response = request.send().await.map_err(|e| e.to_string())?;
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
        let response = request.send().await.map_err(|e| e.to_string())?;
        if !(response.status().is_success()
            || response.status() == StatusCode::METHOD_NOT_ALLOWED
            || response.status() == StatusCode::CONFLICT)
        {
            return Err(format!("WebDAV 创建目录失败：{}", response.status()));
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

#[derive(Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct PairingOffer {
    pub code: String,
    pub expires_at: u64,
}

struct PairHostState {
    app_state: AppState,
    runtime: SyncRuntime,
    code: String,
    session_id: String,
    secret: Arc<StaticSecret>,
    public_key: [u8; 32],
    completed: AtomicBool,
    cancellation: CancellationToken,
}

#[derive(Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
struct PairRequest {
    session_id: String,
    device_id: String,
    client_public_key: String,
    proof: String,
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

pub async fn start_pairing(state: AppState, runtime: SyncRuntime) -> Result<PairingOffer, String> {
    // A successful pairing must leave the new device with a usable route for
    // later updates, so validate and seed the remote configuration first.
    let _ = ensure_space(&state)?;
    synchronize(&state).await?;
    let code = pairing_code();
    let session_id = uuid::Uuid::new_v4().to_string();
    let cancellation = CancellationToken::new();
    runtime.replace_pairing(cancellation.clone())?;
    tokio::time::sleep(Duration::from_millis(25)).await;
    let discovery_socket = UdpSocket::bind((Ipv4Addr::UNSPECIFIED, DISCOVERY_PORT))
        .await
        .map_err(|e| format!("无法启动局域网发现：{e}"))?;
    let secret = Arc::new(StaticSecret::random_from_rng(rand::rngs::OsRng));
    let public_key = PublicKey::from(secret.as_ref()).to_bytes();
    let listener = tokio::net::TcpListener::bind((Ipv4Addr::UNSPECIFIED, 0))
        .await
        .map_err(|e| format!("无法启动配对服务：{e}"))?;
    let port = listener.local_addr().map_err(|e| e.to_string())?.port();
    let host = Arc::new(PairHostState {
        app_state: state,
        runtime,
        code: code.clone(),
        session_id: session_id.clone(),
        secret,
        public_key,
        completed: AtomicBool::new(false),
        cancellation: cancellation.clone(),
    });
    let router = Router::new()
        .route("/pair", post(pair_handler))
        .with_state(host.clone());
    tauri::async_runtime::spawn({
        let cancellation = cancellation.clone();
        async move {
            let _ = axum::serve(listener, router)
                .with_graceful_shutdown(cancellation.cancelled_owned())
                .await;
        }
    });
    tauri::async_runtime::spawn(discovery_host(host, port, discovery_socket));
    tauri::async_runtime::spawn({
        let cancellation = cancellation.clone();
        async move {
            tokio::time::sleep(PAIRING_TTL).await;
            cancellation.cancel();
        }
    });
    Ok(PairingOffer {
        code,
        expires_at: now_millis() + PAIRING_TTL.as_millis() as u64,
    })
}

async fn discovery_host(host: Arc<PairHostState>, port: u16, socket: UdpSocket) {
    let mut buffer = [0_u8; 2048];
    loop {
        tokio::select! {
            _ = host.cancellation.cancelled() => return,
            incoming = socket.recv_from(&mut buffer) => {
                let Ok((length, peer)) = incoming else { continue };
                let Ok(request) = serde_json::from_slice::<DiscoveryRequest>(&buffer[..length]) else { continue };
                if request.kind != "leeef-pair-discover" || request.code_hash != sha256_text(&host.code) {
                    continue;
                }
                let response = DiscoveryResponse {
                    kind: "leeef-pair-offer".into(),
                    session_id: host.session_id.clone(),
                    port,
                    host_public_key: URL_SAFE_NO_PAD.encode(host.public_key),
                };
                if let Ok(bytes) = serde_json::to_vec(&response) {
                    let _ = socket.send_to(&bytes, peer).await;
                }
            }
        }
    }
}

async fn pair_handler(
    AxumState(host): AxumState<Arc<PairHostState>>,
    Json(request): Json<PairRequest>,
) -> Result<Json<PairResponse>, (StatusCode, String)> {
    if request.session_id != host.session_id {
        return Err((StatusCode::UNAUTHORIZED, "配对会话无效".into()));
    }
    let client_public_bytes = URL_SAFE_NO_PAD
        .decode(&request.client_public_key)
        .map_err(|_| (StatusCode::BAD_REQUEST, "设备公钥无效".into()))?;
    let client_public: [u8; 32] = client_public_bytes
        .try_into()
        .map_err(|_| (StatusCode::BAD_REQUEST, "设备公钥无效".into()))?;
    let expected = pairing_proof(
        &host.code,
        &host.session_id,
        &request.device_id,
        &client_public,
    )
    .map_err(internal_pair_error)?;
    if expected != request.proof {
        return Err((StatusCode::UNAUTHORIZED, "配对码不正确".into()));
    }
    if host.completed.swap(true, Ordering::AcqRel) {
        return Err((StatusCode::CONFLICT, "该配对码已使用".into()));
    }

    let space = ensure_space(&host.app_state).map_err(internal_pair_error)?;
    let mut devices = load_devices(&host.app_state).map_err(internal_pair_error)?;
    if !devices.contains(&host.app_state.device_id) {
        devices.push(host.app_state.device_id.clone());
    }
    if !devices.contains(&request.device_id) {
        devices.push(request.device_id.clone());
    }
    devices.sort();
    devices.dedup();
    save_devices(&host.app_state, &devices).map_err(internal_pair_error)?;
    let configuration = ConfigurationDocument {
        version: 1,
        space_id: space.id.clone(),
        device_id: host.app_state.device_id.clone(),
        entries: capture_configuration(&host.app_state).map_err(internal_pair_error)?,
    };
    let snapshot = PairingSnapshot {
        space,
        devices,
        configuration,
    };
    let shared = host.secret.diffie_hellman(&PublicKey::from(client_public));
    let key = derive_pairing_key(shared.as_bytes(), &host.code, &host.session_id)
        .map_err(internal_pair_error)?;
    let response = encrypt_pairing_snapshot(&snapshot, &key).map_err(internal_pair_error)?;
    host.runtime.trigger();
    let cancellation = host.cancellation.clone();
    tauri::async_runtime::spawn(async move {
        tokio::time::sleep(Duration::from_millis(250)).await;
        cancellation.cancel();
    });
    Ok(Json(response))
}

fn internal_pair_error(error: String) -> (StatusCode, String) {
    (StatusCode::INTERNAL_SERVER_ERROR, error)
}

pub async fn join_pairing(
    state: &AppState,
    runtime: &SyncRuntime,
    code: &str,
) -> Result<SyncStatus, String> {
    let code = code.trim().to_ascii_uppercase();
    if code.len() != 12 || !code.bytes().all(|item| PAIRING_ALPHABET.contains(&item)) {
        return Err("请输入桌面端显示的 12 位配对码".into());
    }
    let (offer, host_address) = discover_pairing_host(&code).await?;
    let client_secret = StaticSecret::random_from_rng(rand::rngs::OsRng);
    let client_public = PublicKey::from(&client_secret).to_bytes();
    let request = PairRequest {
        session_id: offer.session_id.clone(),
        device_id: state.device_id.clone(),
        client_public_key: URL_SAFE_NO_PAD.encode(client_public),
        proof: pairing_proof(&code, &offer.session_id, &state.device_id, &client_public)?,
    };
    let url = format!("http://{}:{}/pair", host_address.ip(), offer.port);
    let response = Client::builder()
        .timeout(Duration::from_secs(12))
        .build()
        .map_err(|e| e.to_string())?
        .post(url)
        .json(&request)
        .send()
        .await
        .map_err(|e| format!("无法连接桌面端：{e}"))?;
    if !response.status().is_success() {
        return Err(response.text().await.unwrap_or_else(|_| "配对失败".into()));
    }
    let payload: PairResponse = response.json().await.map_err(|e| e.to_string())?;
    let host_public_bytes = URL_SAFE_NO_PAD
        .decode(offer.host_public_key)
        .map_err(|e| e.to_string())?;
    let host_public: [u8; 32] = host_public_bytes
        .try_into()
        .map_err(|_| "桌面端临时公钥无效".to_string())?;
    let shared = client_secret.diffie_hellman(&PublicKey::from(host_public));
    let key = derive_pairing_key(shared.as_bytes(), &code, &offer.session_id)?;
    let snapshot = decrypt_pairing_snapshot(&payload, &key)?;
    db::kv_set(
        state,
        SPACE_KEY,
        &serde_json::to_string(&snapshot.space).map_err(|e| e.to_string())?,
    )?;
    save_devices(state, &snapshot.devices)?;
    apply_pairing_configuration(state, snapshot.configuration)?;
    runtime.trigger();
    Ok(runtime.status(state))
}

async fn discover_pairing_host(code: &str) -> Result<(DiscoveryResponse, SocketAddr), String> {
    let socket = UdpSocket::bind((Ipv4Addr::UNSPECIFIED, 0))
        .await
        .map_err(|e| e.to_string())?;
    socket.set_broadcast(true).map_err(|e| e.to_string())?;
    let request = serde_json::to_vec(&DiscoveryRequest {
        kind: "leeef-pair-discover".into(),
        code_hash: sha256_text(code),
    })
    .map_err(|e| e.to_string())?;
    let targets = [
        SocketAddr::new(IpAddr::V4(Ipv4Addr::BROADCAST), DISCOVERY_PORT),
        SocketAddr::new(IpAddr::V4(Ipv4Addr::new(239, 255, 73, 73)), DISCOVERY_PORT),
    ];
    for target in targets {
        let _ = socket.send_to(&request, target).await;
    }
    let mut buffer = [0_u8; 2048];
    let deadline = tokio::time::Instant::now() + Duration::from_secs(8);
    loop {
        let remaining = deadline.saturating_duration_since(tokio::time::Instant::now());
        if remaining.is_zero() {
            return Err("未在局域网中找到该配对会话，请确认两台设备连接同一网络".into());
        }
        match tokio::time::timeout(remaining, socket.recv_from(&mut buffer)).await {
            Ok(Ok((length, address))) => {
                let Ok(response) = serde_json::from_slice::<DiscoveryResponse>(&buffer[..length])
                else {
                    continue;
                };
                if response.kind == "leeef-pair-offer" {
                    return Ok((response, address));
                }
            }
            _ => return Err("未在局域网中找到该配对会话，请确认两台设备连接同一网络".into()),
        }
    }
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
    if let Some(space) = load_space(state)? {
        return Ok(space);
    }
    let mut key = [0_u8; 32];
    rand::thread_rng().fill_bytes(&mut key);
    let space = SpaceState {
        id: uuid::Uuid::new_v4().to_string(),
        key: URL_SAFE_NO_PAD.encode(key),
    };
    db::kv_set(
        state,
        SPACE_KEY,
        &serde_json::to_string(&space).map_err(|e| e.to_string())?,
    )?;
    save_devices(state, std::slice::from_ref(&state.device_id))?;
    Ok(space)
}

fn load_space(state: &AppState) -> Result<Option<SpaceState>, String> {
    db::kv_get(state, SPACE_KEY)?
        .map(|value| serde_json::from_str(&value).map_err(|e| e.to_string()))
        .transpose()
}

fn load_devices(state: &AppState) -> Result<Vec<String>, String> {
    Ok(db::kv_get(state, DEVICES_KEY)?
        .and_then(|value| serde_json::from_str(&value).ok())
        .unwrap_or_else(|| vec![state.device_id.clone()]))
}

fn save_devices(state: &AppState, devices: &[String]) -> Result<(), String> {
    db::kv_set(
        state,
        DEVICES_KEY,
        &serde_json::to_string(devices).map_err(|e| e.to_string())?,
    )
}

fn settings_object(state: &AppState) -> Result<Map<String, Value>, String> {
    let value = db::kv_get(state, "settings")?
        .and_then(|raw| serde_json::from_str::<Value>(&raw).ok())
        .unwrap_or_else(|| Value::Object(Map::new()));
    Ok(value.as_object().cloned().unwrap_or_default())
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
    use axum::{body::Bytes, extract::Path, http::StatusCode, routing::get};
    use std::collections::HashMap;
    use tempfile::tempdir;

    fn state(name: &str) -> AppState {
        db::open(tempdir().unwrap().keep().join(name)).unwrap()
    }

    #[test]
    fn configuration_merge_uses_latest_value_per_field() {
        let state = state("merge");
        save_settings(
            &state,
            serde_json::json!({"theme":"paper","fontSize":18,"autoSync":true}),
        )
        .unwrap();
        let local = capture_configuration(&state).unwrap();
        let timestamp = local["theme"].modified_at + 10;
        let remote = ConfigurationDocument {
            version: 1,
            space_id: "space".into(),
            device_id: "remote".into(),
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
            ]),
        };
        assert_eq!(merge_configuration(&state, [remote]).unwrap(), 2);
        let settings = settings_object(&state).unwrap();
        assert_eq!(settings["theme"], "night");
        assert_eq!(settings["fontSize"], 22);
        assert_eq!(settings["autoSync"], true);
    }

    #[test]
    fn encrypted_configuration_rejects_wrong_key() {
        let document = ConfigurationDocument {
            version: 1,
            space_id: "space".into(),
            device_id: "device".into(),
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
            .with_state(documents);
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
        let devices = vec![desktop.device_id.clone(), phone.device_id.clone()];
        save_devices(&desktop, &devices).unwrap();
        db::kv_set(&phone, SPACE_KEY, &serde_json::to_string(&space).unwrap()).unwrap();
        save_devices(&phone, &devices).unwrap();
        apply_pairing_configuration(
            &phone,
            ConfigurationDocument {
                version: 1,
                space_id: space.id,
                device_id: desktop.device_id.clone(),
                entries: capture_configuration(&desktop).unwrap(),
            },
        )
        .unwrap();

        synchronize(&desktop).await.unwrap();
        let mut updated = settings_object(&desktop).unwrap();
        updated.insert("theme".into(), Value::String("night".into()));
        save_settings(&desktop, Value::Object(updated)).unwrap();
        synchronize(&desktop).await.unwrap();
        assert_eq!(synchronize(&phone).await.unwrap(), 1);
        assert_eq!(settings_object(&phone).unwrap()["theme"], "night");

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
    }
}
