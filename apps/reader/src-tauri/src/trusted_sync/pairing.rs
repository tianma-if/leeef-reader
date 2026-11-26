use super::{
    apply_trusted_snapshot, capture_configuration, clean_device_name, configured_backend,
    decrypt_pairing_snapshot, derive_pairing_key, encrypt_pairing_snapshot, ensure_space,
    load_space, now_millis, pairing_code, pairing_proof, pairing_transport, sha256_text,
    update_roster, AppState, ConfigurationDocument, DiscoveryRequest, DiscoveryResponse,
    PairResponse, PairingSnapshot, SyncRuntime, SyncStatus, DISCOVERY_PORT, PAIRING_ALPHABET,
    PAIRING_TTL,
};
use axum::{
    extract::{DefaultBodyLimit, State},
    http::StatusCode,
    routing::post,
    Json, Router,
};
use base64::{engine::general_purpose::URL_SAFE_NO_PAD, Engine as _};
use hkdf::Hkdf;
use serde::{Deserialize, Serialize};
use sha2::Sha256;
use std::{
    net::Ipv4Addr,
    sync::{Arc, Mutex},
    time::Duration,
};
use tauri::{ipc::Channel, AppHandle};
use tokio::{
    net::{TcpListener, UdpSocket},
    sync::oneshot,
};
use tokio_util::sync::CancellationToken;
use uuid::Uuid;
use x25519_dalek::{PublicKey, StaticSecret};

const QR_PREFIX: &str = "leeef-pair:v1:";
const APPROVAL_TIMEOUT: Duration = Duration::from_secs(90);
#[cfg(any(test, target_os = "android", target_os = "ios"))]
const CODE_TIMEOUT: Duration = Duration::from_secs(12);
type PairError = (StatusCode, String);

#[derive(Clone, Debug, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct PairingPeer {
    pub(super) session_id: String,
    name: String,
    host_public_key: String,
    pub(super) addresses: Vec<Ipv4Addr>,
    pub(super) port: u16,
    pub(super) expires_at: u64,
}

impl PairingPeer {
    pub(super) fn valid(&self) -> bool {
        self.expires_at > now_millis()
            && self.port != 0
            && (1..=8).contains(&self.addresses.len())
            && self.name.len() <= 240
            && Uuid::parse_str(&self.session_id).is_ok()
            && pairing_transport::public_key(&self.host_public_key).is_some()
    }
}

#[derive(Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct PairingOffer {
    session_id: String,
    code: String,
    expires_at: u64,
    qr: Option<PairingQr>,
}

#[derive(Clone, Serialize)]
struct PairingQr {
    width: usize,
    modules: String,
}

#[derive(Deserialize, Serialize)]
struct PairingInvitation {
    peer: PairingPeer,
    code: String,
}

#[derive(Clone, Serialize)]
#[serde(rename_all = "camelCase")]
struct PairingApproval {
    id: String,
    device_name: String,
    verification: String,
}

#[derive(Serialize)]
pub struct PairingHostStatus {
    active: bool,
    completed: bool,
    pending: Option<PairingApproval>,
}

struct PendingApproval {
    display: PairingApproval,
    decision: Option<oneshot::Sender<bool>>,
}

pub(super) struct PairingSession {
    peer: PairingPeer,
    cancellation: CancellationToken,
    pending: Mutex<Option<PendingApproval>>,
    completed: Mutex<bool>,
}

struct PairHostState {
    app_state: AppState,
    runtime: SyncRuntime,
    code: String,
    secret: StaticSecret,
    session: Arc<PairingSession>,
}

#[derive(Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
struct PairRequest {
    session_id: String,
    device_id: String,
    #[serde(default)]
    device_name: String,
    client_public_key: String,
    proof: String,
}

#[derive(Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
struct ApprovalRequest {
    session_id: String,
    device_id: String,
    device_name: String,
    client_public_key: String,
}

pub async fn start_pairing(state: AppState, runtime: SyncRuntime) -> Result<PairingOffer, String> {
    if load_space(&state)?.is_none() {
        configured_backend(&state)?;
    }
    ensure_space(&state)?;
    runtime.trigger();
    let listener = TcpListener::bind((Ipv4Addr::UNSPECIFIED, 0))
        .await
        .map_err(|error| format!("无法启动配对服务：{error}"))?;
    let code = pairing_code();
    let secret = StaticSecret::random_from_rng(rand::rngs::OsRng);
    let peer = PairingPeer {
        session_id: Uuid::new_v4().to_string(),
        name: device_name(),
        host_public_key: URL_SAFE_NO_PAD.encode(PublicKey::from(&secret).to_bytes()),
        addresses: pairing_transport::host_addresses(),
        port: listener
            .local_addr()
            .map_err(|error| error.to_string())?
            .port(),
        expires_at: now_millis() + PAIRING_TTL.as_millis() as u64,
    };
    let qr = if peer.addresses.is_empty() {
        None
    } else {
        Some(make_qr(&peer, &code)?)
    };
    let session = Arc::new(PairingSession {
        peer,
        cancellation: CancellationToken::new(),
        pending: Mutex::new(None),
        completed: Mutex::new(false),
    });
    if let Some(previous) = runtime
        .pairing
        .lock()
        .map_err(|error| error.to_string())?
        .replace(session.clone())
    {
        previous.cancellation.cancel();
    }
    let host = Arc::new(PairHostState {
        app_state: state,
        runtime,
        code: code.clone(),
        secret,
        session: session.clone(),
    });
    let router = Router::new()
        .route("/pair", post(pair_handler))
        .route("/pair/approve", post(approval_handler))
        .layer(DefaultBodyLimit::max(4096))
        .with_state(host.clone());
    let cancellation = session.cancellation.clone();
    tauri::async_runtime::spawn(async move {
        let _ = axum::serve(listener, router)
            .with_graceful_shutdown(cancellation.cancelled_owned())
            .await;
    });
    tauri::async_runtime::spawn(discovery_host(host));
    #[cfg(any(target_os = "macos", windows, target_os = "linux"))]
    tauri::async_runtime::spawn(advertise_bonjour(session.clone()));
    let expiry = session.cancellation.clone();
    tauri::async_runtime::spawn(async move {
        tokio::select! {
            _ = expiry.cancelled() => {}
            _ = tokio::time::sleep(PAIRING_TTL) => expiry.cancel(),
        }
    });
    Ok(PairingOffer {
        session_id: session.peer.session_id.clone(),
        code,
        expires_at: session.peer.expires_at,
        qr,
    })
}

pub(super) fn device_name() -> String {
    hostname::get()
        .ok()
        .and_then(|name| name.into_string().ok())
        .and_then(|name| clean_device_name(name.trim().trim_end_matches(".local")))
        .filter(|name| !matches!(name.as_str(), "localhost" | "localhost.localdomain"))
        .unwrap_or_else(|| {
            match std::env::consts::OS {
                "android" => "Android",
                "ios" => "iPhone / iPad",
                "macos" => "Mac",
                "windows" => "Windows",
                "linux" => "Linux",
                _ => "Leeef Reader",
            }
            .into()
        })
}

fn make_qr(peer: &PairingPeer, code: &str) -> Result<PairingQr, String> {
    let payload = encode_invitation(peer, code)?;
    let qr = qrcode::QrCode::with_error_correction_level(payload, qrcode::EcLevel::M)
        .map_err(|_| "无法生成配对二维码。")?;
    Ok(PairingQr {
        width: qr.width(),
        modules: qr
            .to_colors()
            .into_iter()
            .map(|color| {
                if color == qrcode::Color::Dark {
                    '1'
                } else {
                    '0'
                }
            })
            .collect(),
    })
}

fn encode_invitation(peer: &PairingPeer, code: &str) -> Result<String, String> {
    let invitation = PairingInvitation {
        peer: peer.clone(),
        code: code.into(),
    };
    let bytes = serde_json::to_vec(&invitation).map_err(|error| error.to_string())?;
    Ok(format!("{QR_PREFIX}{}", URL_SAFE_NO_PAD.encode(bytes)))
}

#[cfg(any(test, target_os = "android", target_os = "ios"))]
fn parse_qr(text: &str) -> Result<PairingInvitation, String> {
    let invalid = || "请扫描 Leeef Reader 配对页面显示的二维码。".to_string();
    let encoded = text
        .trim()
        .strip_prefix(QR_PREFIX)
        .filter(|text| text.len() <= 2048)
        .ok_or_else(invalid)?;
    let bytes = URL_SAFE_NO_PAD.decode(encoded).map_err(|_| invalid())?;
    let invitation: PairingInvitation = serde_json::from_slice(&bytes).map_err(|_| invalid())?;
    if !valid_code(&invitation.code) {
        return Err(invalid());
    }
    Ok(invitation)
}

#[cfg(any(target_os = "macos", windows, target_os = "linux"))]
fn bonjour_properties(peer: &PairingPeer) -> [(&'static str, String); 6] {
    [
        ("name", peer.name.clone()),
        ("id", peer.session_id.clone()),
        ("key", peer.host_public_key.clone()),
        ("port", peer.port.to_string()),
        ("expires", peer.expires_at.to_string()),
        (
            "addresses",
            peer.addresses
                .iter()
                .map(ToString::to_string)
                .collect::<Vec<_>>()
                .join(","),
        ),
    ]
}

#[cfg(target_os = "macos")]
async fn advertise_bonjour(session: Arc<PairingSession>) {
    use dns_sd_native::ServiceRegistrationBuilder;

    if session.peer.addresses.is_empty() {
        return;
    }
    let peer = &session.peer;
    let mut builder = ServiceRegistrationBuilder::new("_leeef-pair._tcp", peer.port);
    builder.name(&peer.session_id);
    for (key, value) in bonjour_properties(peer) {
        builder.add_txt_record_key_string(key, value);
    }
    let registration = tokio::select! {
        _ = session.cancellation.cancelled() => return,
        result = builder.register() => result,
    };
    if let Ok(registration) = registration {
        session.cancellation.cancelled().await;
        let _ = registration.unregister().await;
    }
}

#[cfg(any(windows, target_os = "linux"))]
async fn advertise_bonjour(session: Arc<PairingSession>) {
    use mdns_sd::{ServiceDaemon, ServiceInfo};

    if session.peer.addresses.is_empty() || session.cancellation.is_cancelled() {
        return;
    }
    let peer = &session.peer;
    let properties = bonjour_properties(peer);
    let addresses: Vec<_> = peer
        .addresses
        .iter()
        .copied()
        .map(std::net::IpAddr::V4)
        .collect();
    let host = format!("leeef-{}.local.", peer.session_id);
    let Ok(daemon) = ServiceDaemon::new() else {
        return;
    };
    if let Ok(info) = ServiceInfo::new(
        "_leeef-pair._tcp.local.",
        &peer.session_id,
        &host,
        addresses.as_slice(),
        peer.port,
        &properties[..],
    ) {
        let name = info.get_fullname().to_string();
        if daemon.register(info).is_ok() {
            session.cancellation.cancelled().await;
            if let Ok(result) = daemon.unregister(&name) {
                let _ = tokio::time::timeout(Duration::from_millis(750), result.recv_async()).await;
            }
        }
    }
    let _ = daemon.shutdown();
}

async fn discovery_host(host: Arc<PairHostState>) {
    // Give a just-cancelled session time to release the shared port.
    let socket = loop {
        match UdpSocket::bind((Ipv4Addr::UNSPECIFIED, DISCOVERY_PORT)).await {
            Ok(socket) => break socket,
            Err(error) if error.kind() == std::io::ErrorKind::AddrInUse => {
                tokio::select! {
                    _ = host.session.cancellation.cancelled() => return,
                    _ = tokio::time::sleep(Duration::from_millis(250)) => {}
                }
            }
            Err(_) => return,
        }
    };
    let peer = &host.session.peer;
    let nearby = serde_json::to_vec(peer).ok();
    let legacy = serde_json::to_vec(&DiscoveryResponse {
        kind: "leeef-pair-offer".into(),
        session_id: peer.session_id.clone(),
        port: peer.port,
        host_public_key: peer.host_public_key.clone(),
    })
    .ok();
    let code_hash = sha256_text(&host.code);
    let mut buffer = [0; 2048];
    loop {
        tokio::select! {
            _ = host.session.cancellation.cancelled() => return,
            result = socket.recv_from(&mut buffer) => {
                let Ok((length, sender)) = result else { return };
                let Ok(request) = serde_json::from_slice::<DiscoveryRequest>(&buffer[..length])
                    else { continue };
                let response = match request.kind.as_str() {
                    "leeef-pair-list" => nearby.as_deref(),
                    "leeef-pair-discover" if request.code_hash == code_hash => legacy.as_deref(),
                    _ => None,
                };
                if let Some(bytes) = response {
                    let _ = socket.send_to(bytes, sender).await;
                }
            }
        }
    }
}

pub async fn nearby_pairing_devices(
    app: &AppHandle,
    runtime: &SyncRuntime,
) -> Result<Vec<PairingPeer>, String> {
    let local_id = runtime
        .pairing
        .lock()
        .map_err(|error| error.to_string())?
        .as_ref()
        .map(|session| session.peer.session_id.clone());
    let mut devices = pairing_transport::nearby(app).await?;
    devices.retain(|peer| Some(&peer.session_id) != local_id.as_ref());
    devices.sort_by(|a, b| {
        a.name
            .cmp(&b.name)
            .then_with(|| a.session_id.cmp(&b.session_id))
    });
    devices.dedup_by(|a, b| a.session_id == b.session_id);
    Ok(devices)
}

fn current_session(
    runtime: &SyncRuntime,
    session_id: &str,
) -> Result<Option<Arc<PairingSession>>, String> {
    Ok(runtime
        .pairing
        .lock()
        .map_err(|error| error.to_string())?
        .as_ref()
        .filter(|session| session.peer.session_id == session_id)
        .cloned())
}

pub fn pairing_status(
    runtime: &SyncRuntime,
    session_id: &str,
) -> Result<PairingHostStatus, String> {
    let Some(session) = current_session(runtime, session_id)? else {
        return Ok(PairingHostStatus {
            active: false,
            completed: false,
            pending: None,
        });
    };
    let active = !session.cancellation.is_cancelled();
    let pending = session
        .pending
        .lock()
        .map_err(|error| error.to_string())?
        .as_ref()
        .filter(|request| request.decision.is_some() && active)
        .map(|request| request.display.clone());
    let completed = *session
        .completed
        .lock()
        .map_err(|error| error.to_string())?;
    Ok(PairingHostStatus {
        active,
        completed,
        pending,
    })
}

pub fn stop_pairing(runtime: &SyncRuntime, session_id: &str) -> Result<(), String> {
    if let Some(session) = current_session(runtime, session_id)? {
        session.cancellation.cancel();
    }
    Ok(())
}

pub fn decide_pairing(
    runtime: &SyncRuntime,
    session_id: &str,
    approval_id: &str,
    approve: bool,
) -> Result<(), String> {
    let outdated = || "配对请求已结束，请让对方重新发起。".to_string();
    let session = current_session(runtime, session_id)?
        .filter(|s| !s.cancellation.is_cancelled())
        .ok_or_else(outdated)?;
    let sender = session
        .pending
        .lock()
        .map_err(|error| error.to_string())?
        .as_mut()
        .filter(|request| request.display.id == approval_id)
        .and_then(|request| request.decision.take())
        .ok_or_else(outdated)?;
    sender.send(approve).map_err(|_| outdated())
}

fn check_session(session: &PairingSession, session_id: &str) -> Result<(), PairError> {
    if session.peer.session_id != session_id
        || session.cancellation.is_cancelled()
        || session.peer.expires_at <= now_millis()
    {
        return Err((
            StatusCode::UNAUTHORIZED,
            "配对邀请已过期，请重新开始。".into(),
        ));
    }
    Ok(())
}

async fn pair_handler(
    State(host): State<Arc<PairHostState>>,
    Json(request): Json<PairRequest>,
) -> Result<Json<PairResponse>, PairError> {
    check_session(&host.session, &request.session_id)?;
    if Uuid::parse_str(&request.device_id).is_err() {
        return Err(bad_request("设备标识无效。".into()));
    }
    let client_public = request_public_key(&request.client_public_key)?;
    let expected = pairing_proof(
        &host.code,
        &request.session_id,
        &request.device_id,
        &client_public,
    )
    .map_err(internal)?;
    if expected != request.proof {
        return Err((StatusCode::UNAUTHORIZED, "配对码不正确。".into()));
    }
    let shared = shared_secret(&host.secret, client_public).map_err(bad_request)?;
    let key = derive_pairing_key(&shared, &host.code, &request.session_id).map_err(internal)?;
    complete_pairing(
        &host,
        &request.device_id,
        clean_device_name(&request.device_name),
        &key,
    )
    .map(Json)
}

async fn approval_handler(
    State(host): State<Arc<PairHostState>>,
    Json(request): Json<ApprovalRequest>,
) -> Result<Json<PairResponse>, PairError> {
    check_session(&host.session, &request.session_id)?;
    if Uuid::parse_str(&request.device_id).is_err() {
        return Err(bad_request("设备标识无效。".into()));
    }
    let client_public = request_public_key(&request.client_public_key)?;
    let host_public = PublicKey::from(&host.secret).to_bytes();
    let shared = shared_secret(&host.secret, client_public).map_err(bad_request)?;
    let (verification, key) =
        approval_keys(&shared, &request.session_id, host_public, client_public)
            .map_err(internal)?;
    let name = clean_device_name(&request.device_name);
    wait_for_approval(
        &host.session,
        name.clone().unwrap_or_else(|| "未知设备".into()),
        verification,
    )
    .await?;
    complete_pairing(&host, &request.device_id, name, &key).map(Json)
}

struct PendingRequest<'a> {
    slot: &'a Mutex<Option<PendingApproval>>,
    id: String,
}

impl Drop for PendingRequest<'_> {
    fn drop(&mut self) {
        if let Ok(mut pending) = self.slot.lock() {
            if pending
                .as_ref()
                .is_some_and(|request| request.display.id == self.id)
            {
                pending.take();
            }
        }
    }
}

async fn wait_for_approval(
    session: &PairingSession,
    device_name: String,
    verification: String,
) -> Result<(), PairError> {
    let id = Uuid::new_v4().to_string();
    let (sender, receiver) = oneshot::channel();
    {
        let mut pending = session
            .pending
            .lock()
            .map_err(|error| internal(error.to_string()))?;
        if pending.is_some() {
            return Err((
                StatusCode::CONFLICT,
                "已有设备在等待确认，请稍后重试。".into(),
            ));
        }
        *pending = Some(PendingApproval {
            display: PairingApproval {
                id: id.clone(),
                device_name,
                verification,
            },
            decision: Some(sender),
        });
    }
    let _pending = PendingRequest {
        slot: &session.pending,
        id,
    };
    tokio::select! {
        _ = session.cancellation.cancelled() => {
            Err((StatusCode::GONE, "配对已结束，请重新开始。".into()))
        }
        response = tokio::time::timeout(APPROVAL_TIMEOUT, receiver) => match response {
            Ok(Ok(true)) => Ok(()),
            Ok(Ok(false)) => Err((StatusCode::FORBIDDEN, "另一台设备拒绝了配对。".into())),
            _ => Err((StatusCode::REQUEST_TIMEOUT, "等待确认超时，请重新配对。".into())),
        }
    }
}

fn complete_pairing(
    host: &PairHostState,
    device_id: &str,
    device_name: Option<String>,
    key: &[u8; 32],
) -> Result<PairResponse, PairError> {
    let mut completed = host
        .session
        .completed
        .lock()
        .map_err(|error| internal(error.to_string()))?;
    check_session(&host.session, &host.session.peer.session_id)?;
    if *completed {
        return Err((StatusCode::CONFLICT, "这次配对邀请已使用。".into()));
    }
    let space = ensure_space(&host.app_state).map_err(internal)?;
    let entries = capture_configuration(&host.app_state).map_err(internal)?;
    let response = update_roster(&host.app_state, &space, |devices, names| {
        devices.extend([host.app_state.device_id.clone(), device_id.into()]);
        if let Some(name) = device_name {
            names.insert(device_id.into(), name);
        }
        names.insert(
            host.app_state.device_id.clone(),
            host.session.peer.name.clone(),
        );
        let snapshot = PairingSnapshot {
            space: space.clone(),
            devices: devices.iter().cloned().collect(),
            configuration: ConfigurationDocument {
                version: 1,
                space_id: space.id.clone(),
                device_id: host.app_state.device_id.clone(),
                device_names: names.clone(),
                entries,
            },
        };
        encrypt_pairing_snapshot(&snapshot, key)
    })
    .map_err(internal)?;
    *completed = true;
    host.runtime.trigger();
    host.session.cancellation.cancel();
    Ok(response)
}

fn bad_request(error: String) -> PairError {
    (StatusCode::BAD_REQUEST, error)
}

fn internal(error: String) -> PairError {
    (StatusCode::INTERNAL_SERVER_ERROR, error)
}

fn request_public_key(encoded: &str) -> Result<[u8; 32], PairError> {
    pairing_transport::public_key(encoded).ok_or_else(|| bad_request("设备公钥无效。".into()))
}

fn shared_secret(secret: &StaticSecret, other: [u8; 32]) -> Result<[u8; 32], String> {
    let shared = secret.diffie_hellman(&PublicKey::from(other));
    if !shared.was_contributory() {
        return Err("设备公钥无效。".into());
    }
    Ok(shared.to_bytes())
}

fn approval_keys(
    shared: &[u8; 32],
    session_id: &str,
    host_public: [u8; 32],
    client_public: [u8; 32],
) -> Result<(String, [u8; 32]), String> {
    let hkdf = Hkdf::<Sha256>::new(Some(session_id.as_bytes()), shared);
    let mut context = b"leeef-approved-pair-v1".to_vec();
    context.extend(host_public);
    context.extend(client_public);
    let mut output = [0; 38];
    hkdf.expand(&context, &mut output)
        .map_err(|_| "无法派生配对密钥。")?;
    let key = output[..32].try_into().unwrap();
    let verification = output[32..]
        .chunks_exact(2)
        .map(|part| hex::encode_upper(part))
        .collect::<Vec<_>>()
        .join(" ");
    Ok((verification, key))
}

fn valid_code(code: &str) -> bool {
    code.len() == 12 && code.bytes().all(|byte| PAIRING_ALPHABET.contains(&byte))
}

fn code_request(
    state: &AppState,
    session_id: &str,
    code: &str,
    public_key: [u8; 32],
) -> Result<PairRequest, String> {
    Ok(PairRequest {
        session_id: session_id.into(),
        device_id: state.device_id.clone(),
        device_name: device_name(),
        client_public_key: URL_SAFE_NO_PAD.encode(public_key),
        proof: pairing_proof(code, session_id, &state.device_id, &public_key)?,
    })
}

pub async fn join_pairing(
    app: &AppHandle,
    state: &AppState,
    runtime: &SyncRuntime,
    code: &str,
    replace_existing: bool,
) -> Result<SyncStatus, String> {
    let code = code.trim().to_ascii_uppercase();
    if !valid_code(&code) {
        return Err("请输入已有设备显示的 12 位配对码。".into());
    }
    let endpoint = pairing_transport::discover(app, &code).await?;
    let secret = StaticSecret::random_from_rng(rand::rngs::OsRng);
    let request = code_request(
        state,
        &endpoint.session_id,
        &code,
        PublicKey::from(&secret).to_bytes(),
    )?;
    let shared = shared_secret(&secret, endpoint.host_public_key)?;
    let key = derive_pairing_key(&shared, &code, &endpoint.session_id)?;
    let response = endpoint.exchange(&request).await?;
    apply_response(state, runtime, &response, &key, replace_existing)
}

#[cfg(any(target_os = "android", target_os = "ios"))]
pub async fn join_pairing_qr(
    app: &AppHandle,
    state: &AppState,
    runtime: &SyncRuntime,
    text: &str,
    replace_existing: bool,
) -> Result<SyncStatus, String> {
    let invitation = parse_qr(text)?;
    let stream = pairing_transport::direct(app, &invitation.peer).await?;
    exchange_invitation(stream, state, runtime, invitation, replace_existing).await
}

#[cfg(any(test, target_os = "android", target_os = "ios"))]
async fn exchange_invitation(
    stream: tokio::net::TcpStream,
    state: &AppState,
    runtime: &SyncRuntime,
    invitation: PairingInvitation,
    replace_existing: bool,
) -> Result<SyncStatus, String> {
    let PairingInvitation { peer, code } = invitation;
    let host_public =
        pairing_transport::public_key(&peer.host_public_key).ok_or("配对公钥无效。")?;
    let secret = StaticSecret::random_from_rng(rand::rngs::OsRng);
    let request = code_request(
        state,
        &peer.session_id,
        &code,
        PublicKey::from(&secret).to_bytes(),
    )?;
    let shared = shared_secret(&secret, host_public)?;
    let key = derive_pairing_key(&shared, &code, &peer.session_id)?;
    let response = pairing_transport::exchange(stream, "/pair", &request, CODE_TIMEOUT).await?;
    apply_response(state, runtime, &response, &key, replace_existing)
}

pub async fn join_pairing_peer(
    app: &AppHandle,
    state: &AppState,
    runtime: &SyncRuntime,
    peer: PairingPeer,
    verification: Channel<String>,
    replace_existing: bool,
) -> Result<SyncStatus, String> {
    let cancellation = CancellationToken::new();
    if let Some(previous) = runtime
        .pairing_join
        .lock()
        .map_err(|error| error.to_string())?
        .replace(cancellation.clone())
    {
        previous.cancel();
    }
    let join = async {
        let stream = pairing_transport::direct(app, &peer).await?;
        let host_public =
            pairing_transport::public_key(&peer.host_public_key).ok_or("配对公钥无效。")?;
        let secret = StaticSecret::random_from_rng(rand::rngs::OsRng);
        let client_public = PublicKey::from(&secret).to_bytes();
        let shared = shared_secret(&secret, host_public)?;
        let (comparison, key) =
            approval_keys(&shared, &peer.session_id, host_public, client_public)?;
        verification
            .send(comparison)
            .map_err(|error| error.to_string())?;
        let request = ApprovalRequest {
            session_id: peer.session_id,
            device_id: state.device_id.clone(),
            device_name: device_name(),
            client_public_key: URL_SAFE_NO_PAD.encode(client_public),
        };
        let response = pairing_transport::exchange(
            stream,
            "/pair/approve",
            &request,
            APPROVAL_TIMEOUT + Duration::from_secs(5),
        )
        .await?;
        Ok::<_, String>((response, key))
    };
    let (response, key) = tokio::select! {
        biased;
        _ = cancellation.cancelled() => return Err("配对已取消。".into()),
        result = join => result?,
    };
    apply_response(state, runtime, &response, &key, replace_existing)
}

pub fn cancel_pairing_join(runtime: &SyncRuntime) -> Result<(), String> {
    if let Some(cancellation) = runtime
        .pairing_join
        .lock()
        .map_err(|error| error.to_string())?
        .take()
    {
        cancellation.cancel();
    }
    Ok(())
}

fn apply_response(
    state: &AppState,
    runtime: &SyncRuntime,
    response: &PairResponse,
    key: &[u8; 32],
    replace_existing: bool,
) -> Result<SyncStatus, String> {
    let snapshot = decrypt_pairing_snapshot(response, key)?;
    apply_trusted_snapshot(state, snapshot, replace_existing)?;
    runtime.trigger();
    Ok(runtime.status(state))
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::{db, trusted_sync::load_devices};
    use tokio::net::TcpStream;

    #[test]
    fn qr_contains_a_short_lived_direct_invitation() {
        let peer = PairingPeer {
            session_id: Uuid::new_v4().to_string(),
            name: "Test desktop".into(),
            host_public_key: URL_SAFE_NO_PAD.encode([22; 32]),
            addresses: vec![Ipv4Addr::new(192, 168, 1, 50)],
            port: 43782,
            expires_at: now_millis() + 60_000,
        };
        let code = pairing_code();
        let text = encode_invitation(&peer, &code).unwrap();
        let invitation = parse_qr(&text).unwrap();
        assert_eq!(invitation.code, code);
        assert_eq!(invitation.peer.addresses, peer.addresses);
        assert!(invitation.peer.valid());
        let qr = make_qr(&peer, &code).unwrap();
        assert_eq!(qr.width * qr.width, qr.modules.len());
        assert!(parse_qr("https://example.com").is_err());
        let mut expired = invitation.peer;
        expired.expires_at = 1;
        assert!(!expired.valid());
    }

    #[tokio::test]
    async fn qr_joins_over_tcp_without_discovery_or_manual_approval() {
        let home = tempfile::tempdir().unwrap();
        let desktop = db::open(home.path().join("desktop")).unwrap();
        let phone = db::open(home.path().join("phone")).unwrap();
        let space = ensure_space(&desktop).unwrap();
        let runtime = SyncRuntime::default();
        let offer = start_pairing(desktop.clone(), runtime.clone())
            .await
            .unwrap();
        let session = current_session(&runtime, &offer.session_id)
            .unwrap()
            .unwrap();
        let payload = encode_invitation(&session.peer, &offer.code).unwrap();
        let invitation = parse_qr(&payload).unwrap();
        let stream = TcpStream::connect((Ipv4Addr::LOCALHOST, session.peer.port))
            .await
            .unwrap();
        let result =
            exchange_invitation(stream, &phone, &SyncRuntime::default(), invitation, false)
                .await
                .unwrap();
        assert!(result.paired);
        assert_eq!(result.paired_devices.len(), 1);
        assert_eq!(result.paired_devices[0].id, desktop.device_id);
        assert_eq!(
            result.paired_devices[0].name.as_deref(),
            Some(session.peer.name.as_str())
        );
        let host_status = runtime.status(&desktop);
        assert_eq!(host_status.paired_devices.len(), 1);
        assert_eq!(host_status.paired_devices[0].id, phone.device_id);
        assert!(host_status.paired_devices[0].name.is_some());
        assert_eq!(load_space(&phone).unwrap().unwrap().id, space.id);
        assert!(
            pairing_status(&runtime, &offer.session_id)
                .unwrap()
                .completed
        );
    }

    #[tokio::test]
    async fn nearby_pairing_requires_approval_and_reuses_the_encrypted_snapshot() {
        let home = tempfile::tempdir().unwrap();
        let desktop = db::open(home.path().join("desktop")).unwrap();
        let phone = db::open(home.path().join("phone")).unwrap();
        let space = ensure_space(&desktop).unwrap();
        db::kv_set(
            &desktop,
            "settings",
            r#"{"theme":"night","aiKey":"test-key"}"#,
        )
        .unwrap();
        let runtime = SyncRuntime::default();
        let offer = start_pairing(desktop.clone(), runtime.clone())
            .await
            .unwrap();
        let session = current_session(&runtime, &offer.session_id)
            .unwrap()
            .unwrap();
        let host_public = pairing_transport::public_key(&session.peer.host_public_key).unwrap();
        let client_secret = StaticSecret::random_from_rng(rand::rngs::OsRng);
        let client_public = PublicKey::from(&client_secret).to_bytes();
        let shared = shared_secret(&client_secret, host_public).unwrap();
        let (verification, key) =
            approval_keys(&shared, &offer.session_id, host_public, client_public).unwrap();

        for approve in [false, true] {
            let request = ApprovalRequest {
                session_id: offer.session_id.clone(),
                device_id: phone.device_id.clone(),
                device_name: "Test phone".into(),
                client_public_key: URL_SAFE_NO_PAD.encode(client_public),
            };
            let client = TcpStream::connect((Ipv4Addr::LOCALHOST, session.peer.port))
                .await
                .unwrap();
            let reply = tokio::spawn(async move {
                pairing_transport::exchange(
                    client,
                    "/pair/approve",
                    &request,
                    Duration::from_secs(3),
                )
                .await
            });
            let pending = tokio::time::timeout(Duration::from_secs(2), async {
                loop {
                    if let Some(pending) =
                        pairing_status(&runtime, &offer.session_id).unwrap().pending
                    {
                        break pending;
                    }
                    tokio::time::sleep(Duration::from_millis(10)).await;
                }
            })
            .await
            .unwrap();
            assert_eq!(pending.verification, verification);
            assert!(!reply.is_finished());
            assert!(!load_devices(&desktop).unwrap().contains(&phone.device_id));
            decide_pairing(&runtime, &offer.session_id, &pending.id, approve).unwrap();
            let result = reply.await.unwrap();
            if approve {
                let response = result.unwrap();
                let joined =
                    apply_response(&phone, &SyncRuntime::default(), &response, &key, false)
                        .unwrap();
                assert!(joined.paired);
                let host_status = runtime.status(&desktop);
                assert_eq!(
                    host_status.paired_devices[0].name.as_deref(),
                    Some("Test phone")
                );
                assert_eq!(load_space(&phone).unwrap().unwrap().id, space.id);
                assert_eq!(
                    super::super::settings_object(&phone).unwrap()["aiKey"],
                    "test-key"
                );
            } else {
                assert!(result.err().unwrap().contains("拒绝"));
            }
        }
        let status = pairing_status(&runtime, &offer.session_id).unwrap();
        assert!(status.completed);
        assert!(!status.active);
    }
}
