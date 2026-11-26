use super::{
    now_millis, sha256_text, DiscoveryRequest, DiscoveryResponse, PairResponse, PairingPeer,
    DISCOVERY_PORT,
};
use axum::http::StatusCode;
use base64::{engine::general_purpose::URL_SAFE_NO_PAD, Engine as _};
use http_body_util::{BodyExt, Full};
use hyper::{body::Bytes, client::conn::http1, header, Request};
use hyper_util::rt::TokioIo;
use serde::Serialize;
#[cfg(not(target_os = "ios"))]
use std::collections::BTreeMap;
use std::{
    io,
    net::{Ipv4Addr, SocketAddr, SocketAddrV4},
    time::Duration,
};
use tauri::AppHandle;
use tokio::{
    net::{TcpSocket, TcpStream, UdpSocket},
    task::JoinSet,
    time::{interval, timeout},
};

#[cfg(any(target_os = "android", target_os = "ios"))]
use tauri_plugin_native_bridge::NativeBridgeExt;
#[cfg(target_os = "android")]
use tauri_plugin_native_bridge::PairingLink;

const DISCOVERY_TIMEOUT: Duration = Duration::from_secs(8);
#[cfg(not(target_os = "ios"))]
const SCAN_TIMEOUT: Duration = Duration::from_millis(1500);
const CONNECT_TIMEOUT: Duration = Duration::from_secs(4);
const NOT_FOUND: &str =
    "找不到配对会话。请确认两台设备连接同一局域网，并在另一台设备上重新生成配对码。";
const CONNECT_FAILED: &str = "无法连接配对设备。请确认两台设备可以在局域网互访，或导入配置文件。";
#[cfg(target_os = "android")]
const VPN_HINT: &str = "请在 VPN 或代理应用中允许局域网连接，或暂停 VPN 后重试。";

pub(super) struct PairingEndpoint {
    pub(super) session_id: String,
    pub(super) host_public_key: [u8; 32],
    address: SocketAddrV4,
    route: DiscoveryRoute,
}

#[derive(Clone)]
struct DiscoveryRoute {
    #[cfg(target_os = "android")]
    link: PairingLink,
    #[cfg(target_os = "ios")]
    interface: Option<std::num::NonZeroU32>,
}

impl DiscoveryRoute {
    fn listen(&self) -> io::Result<UdpSocket> {
        #[cfg(target_os = "android")]
        let address = self.link.address;
        #[cfg(not(target_os = "android"))]
        let address = Ipv4Addr::UNSPECIFIED;
        let socket = std::net::UdpSocket::bind((address, 0))?;
        #[cfg(target_os = "android")]
        bind_to_network(&socket, self.link.handle)?;
        socket.set_nonblocking(true)?;
        socket.set_broadcast(true)?;
        UdpSocket::from_std(socket)
    }

    fn targets(&self) -> [Ipv4Addr; 2] {
        #[cfg(target_os = "android")]
        let alternate = Ipv4Addr::from(u32::from(self.link.address) | !self.mask());
        #[cfg(not(target_os = "android"))]
        let alternate = Ipv4Addr::new(239, 255, 73, 73);
        [Ipv4Addr::BROADCAST, alternate]
    }

    #[cfg(target_os = "android")]
    fn mask(&self) -> u32 {
        u32::MAX << (32 - self.link.prefix_length)
    }

    fn contains(&self, _peer: Ipv4Addr) -> bool {
        #[cfg(target_os = "android")]
        return same_subnet(_peer, self.link.address, self.mask());
        #[cfg(not(target_os = "android"))]
        true
    }

    async fn connect(&self, address: SocketAddrV4) -> io::Result<TcpStream> {
        let socket = TcpSocket::new_v4()?;
        #[cfg(target_os = "android")]
        bind_to_network(&socket, self.link.handle)?;
        #[cfg(target_os = "ios")]
        if let Some(interface) = self.interface {
            socket2::SockRef::from(&socket).bind_device_by_index_v4(Some(interface))?;
        }
        timeout(CONNECT_TIMEOUT, socket.connect(address.into())).await?
    }
}

async fn routes(_app: &AppHandle) -> Result<(Vec<DiscoveryRoute>, bool), String> {
    #[cfg(target_os = "android")]
    {
        let networks = _app
            .native_bridge()
            .pairing_networks()
            .await
            .map_err(|_| "无法读取局域网状态，请检查 Wi-Fi 连接后重试。")?;
        let routes: Vec<_> = networks
            .links
            .into_iter()
            .filter(|link| (1..=30).contains(&link.prefix_length))
            .map(|link| DiscoveryRoute { link })
            .collect();
        if routes.is_empty() {
            return Err(network_error(
                "本机没有可用于配对的局域网连接。请连接 Wi-Fi 后重试。",
                networks.vpn_active,
            ));
        }
        Ok((routes, networks.vpn_active))
    }
    #[cfg(not(target_os = "android"))]
    Ok((
        vec![DiscoveryRoute {
            #[cfg(target_os = "ios")]
            interface: None,
        }],
        false,
    ))
}

fn network_error(message: &str, _vpn_active: bool) -> String {
    #[cfg(target_os = "android")]
    if _vpn_active {
        return format!("{message}{VPN_HINT}");
    }
    message.into()
}

async fn broadcast(socket: &UdpSocket, route: &DiscoveryRoute, request: &[u8]) -> bool {
    let mut sent = false;
    for target in route.targets() {
        sent |= socket
            .send_to(request, (target, DISCOVERY_PORT))
            .await
            .is_ok();
    }
    sent
}

pub(super) async fn discover(app: &AppHandle, code: &str) -> Result<PairingEndpoint, String> {
    let request = DiscoveryRequest {
        kind: "leeef-pair-discover".into(),
        code_hash: sha256_text(code),
    };
    let request = serde_json::to_vec(&request).map_err(|error| error.to_string())?;
    let (routes, vpn_active) = routes(app).await?;
    let mut attempts = JoinSet::new();
    for route in routes {
        let request = request.clone();
        attempts.spawn(async move { discover_on_route(route, &request).await });
    }
    while let Some(result) = attempts.join_next().await {
        if let Ok(Ok(Some(endpoint))) = result {
            return Ok(endpoint);
        }
    }
    Err(network_error(NOT_FOUND, vpn_active))
}

async fn discover_on_route(
    route: DiscoveryRoute,
    request: &[u8],
) -> io::Result<Option<PairingEndpoint>> {
    let socket = route.listen()?;
    let mut buffer = [0_u8; 2048];
    let mut resend = interval(Duration::from_secs(1));
    resend.set_missed_tick_behavior(tokio::time::MissedTickBehavior::Skip);
    let discovery = async {
        loop {
            tokio::select! {
                _ = resend.tick() => {
                    if !broadcast(&socket, &route, request).await {
                        return Err(io::Error::other("无法发送配对广播"));
                    }
                }
                incoming = socket.recv_from(&mut buffer) => {
                    let (length, peer) = incoming?;
                    let SocketAddr::V4(peer) = peer else { continue };
                    if !route.contains(*peer.ip()) { continue; }
                    let Ok(offer) = serde_json::from_slice::<DiscoveryResponse>(&buffer[..length])
                    else { continue };
                    if offer.kind != "leeef-pair-offer" || offer.port == 0 || offer.session_id.is_empty() {
                        continue;
                    }
                    let Some(host_public_key) = public_key(&offer.host_public_key) else { continue };
                    return Ok(PairingEndpoint {
                        address: SocketAddrV4::new(*peer.ip(), offer.port),
                        session_id: offer.session_id,
                        host_public_key,
                        route,
                    });
                }
            }
        }
    };
    match timeout(DISCOVERY_TIMEOUT, discovery).await {
        Ok(result) => result.map(Some),
        Err(_) => Ok(None),
    }
}

pub(super) fn public_key(encoded: &str) -> Option<[u8; 32]> {
    URL_SAFE_NO_PAD.decode(encoded).ok()?.try_into().ok()
}

pub(super) async fn nearby(app: &AppHandle) -> Result<Vec<PairingPeer>, String> {
    #[cfg(target_os = "ios")]
    {
        let payload: serde_json::Value = app
            .native_bridge()
            .browse_pairing_devices()
            .await
            .map_err(|error| error.to_string())?;
        let devices = payload.get("devices").and_then(serde_json::Value::as_array);
        Ok(devices
            .into_iter()
            .flatten()
            .filter_map(|device| serde_json::from_value::<PairingPeer>(device.clone()).ok())
            .filter(PairingPeer::valid)
            .collect())
    }
    #[cfg(not(target_os = "ios"))]
    {
        let (routes, vpn_active) = routes(app).await?;
        let mut attempts = JoinSet::new();
        for route in routes {
            attempts.spawn(scan_route(route));
        }
        let mut devices = BTreeMap::<String, PairingPeer>::new();
        let mut sent = false;
        while let Some(result) = attempts.join_next().await {
            if let Ok(Ok(found)) = result {
                sent = true;
                for device in found {
                    let known = devices
                        .entry(device.session_id.clone())
                        .or_insert_with(|| device.clone());
                    for address in device.addresses {
                        if !known.addresses.contains(&address) && known.addresses.len() < 8 {
                            known.addresses.push(address);
                        }
                    }
                }
            }
        }
        if !sent {
            return Err(network_error("无法搜索局域网内的设备。", vpn_active));
        }
        Ok(devices.into_values().collect())
    }
}

#[cfg(not(target_os = "ios"))]
async fn scan_route(route: DiscoveryRoute) -> io::Result<Vec<PairingPeer>> {
    let socket = route.listen()?;
    let request = br#"{"kind":"leeef-pair-list","codeHash":""}"#;
    if !broadcast(&socket, &route, request).await {
        return Err(io::Error::other("无法发送发现广播"));
    }
    let mut devices = Vec::new();
    let mut buffer = [0_u8; 2048];
    let _ = timeout(SCAN_TIMEOUT, async {
        loop {
            let Ok((length, sender)) = socket.recv_from(&mut buffer).await else {
                break;
            };
            let SocketAddr::V4(sender) = sender else {
                continue;
            };
            if !route.contains(*sender.ip()) {
                continue;
            }
            let Ok(mut peer) = serde_json::from_slice::<PairingPeer>(&buffer[..length]) else {
                continue;
            };
            // The address that actually answered is the most useful one on this route.
            peer.addresses = vec![*sender.ip()];
            if peer.valid() && devices.len() < 64 {
                devices.push(peer);
            }
        }
    })
    .await;
    Ok(devices)
}

fn same_subnet(a: Ipv4Addr, b: Ipv4Addr, mask: u32) -> bool {
    mask != 0 && (u32::from(a) & mask) == (u32::from(b) & mask)
}

fn lan_interfaces() -> impl Iterator<Item = (if_addrs::Ifv4Addr, Option<u32>)> {
    if_addrs::get_if_addrs()
        .unwrap_or_default()
        .into_iter()
        .filter_map(|interface| {
            if interface.is_loopback()
                || interface.is_p2p
                || !interface.is_oper_up()
                || ["utun", "tun", "tap", "wg", "tailscale", "awdl", "llw"]
                    .iter()
                    .any(|prefix| interface.name.starts_with(prefix))
            {
                return None;
            }
            match interface.addr {
                if_addrs::IfAddr::V4(address) if !address.ip.is_unspecified() => {
                    Some((address, interface.index))
                }
                _ => None,
            }
        })
}

pub(super) fn host_addresses() -> Vec<Ipv4Addr> {
    let mut addresses: Vec<_> = lan_interfaces().map(|(address, _)| address.ip).collect();
    addresses.sort_by_key(|address| (address.is_link_local(), *address));
    addresses.dedup();
    addresses.truncate(8);
    addresses
}

pub(super) async fn direct(app: &AppHandle, peer: &PairingPeer) -> Result<TcpStream, String> {
    if !peer.valid() {
        return Err(if peer.expires_at <= now_millis() {
            "配对邀请已过期，请在另一台设备上重新开始配对。".into()
        } else {
            "配对邀请格式无效。".into()
        });
    }
    let (routes, vpn_active) = routes(app).await?;
    #[cfg(not(target_os = "android"))]
    let interfaces: Vec<_> = lan_interfaces().collect();
    let mut attempts = JoinSet::new();
    for route in routes {
        for &ip in &peer.addresses {
            if !route.contains(ip) {
                continue;
            }
            let address = SocketAddrV4::new(ip, peer.port);
            #[cfg(not(target_os = "android"))]
            let Some((_, _index)) = interfaces
                .iter()
                .find(|(local, _)| same_subnet(ip, local.ip, u32::from(local.netmask)))
            else {
                continue;
            };
            #[cfg(target_os = "ios")]
            let route = DiscoveryRoute {
                interface: _index.and_then(std::num::NonZeroU32::new),
            };
            #[cfg(not(target_os = "ios"))]
            let route = route.clone();
            attempts.spawn(async move { route.connect(address).await });
        }
    }
    while let Some(result) = attempts.join_next().await {
        if let Ok(Ok(stream)) = result {
            return Ok(stream);
        }
    }
    Err(network_error(CONNECT_FAILED, vpn_active))
}

impl PairingEndpoint {
    pub(super) async fn exchange(&self, request: &impl Serialize) -> Result<PairResponse, String> {
        let stream = self
            .route
            .connect(self.address)
            .await
            .map_err(|_| CONNECT_FAILED)?;
        exchange(stream, "/pair", request, Duration::from_secs(12)).await
    }
}

pub(super) async fn exchange(
    stream: TcpStream,
    path: &'static str,
    request: &impl Serialize,
    response_timeout: Duration,
) -> Result<PairResponse, String> {
    let body = serde_json::to_vec(request).map_err(|error| error.to_string())?;
    let host = stream.peer_addr().map_err(|_| CONNECT_FAILED)?.to_string();
    let request = Request::post(path)
        .header(header::HOST, host)
        .header(header::CONTENT_TYPE, "application/json")
        .header(header::CONNECTION, "close")
        .body(Full::new(Bytes::from(body)))
        .map_err(|error| error.to_string())?;
    let post = async {
        let (mut sender, connection) = http1::handshake(TokioIo::new(stream)).await?;
        let response = async {
            let response = sender.send_request(request).await?;
            let status = response.status();
            let body = response.into_body().collect().await?.to_bytes();
            Ok((status, body))
        };
        tokio::select! {
            result = response => result,
            result = async {
                connection.await?;
                std::future::pending::<Result<_, hyper::Error>>().await
            } => result,
        }
    };
    let (status, body) = timeout(response_timeout, post)
        .await
        .map_err(|_| "等待配对响应超时，请重试。")?
        .map_err(|_| CONNECT_FAILED)?;
    if status != StatusCode::OK {
        return Err(String::from_utf8(body.to_vec()).unwrap_or_else(|_| "配对失败。".into()));
    }
    serde_json::from_slice(&body).map_err(|_| "已有设备返回了无法读取的配对数据。".into())
}

#[cfg(target_os = "android")]
fn bind_to_network(socket: &impl std::os::fd::AsRawFd, network: u64) -> io::Result<()> {
    #[link(name = "android")]
    extern "C" {
        fn android_setsocknetwork(network: u64, fd: std::ffi::c_int) -> std::ffi::c_int;
    }
    // The socket is still unconnected, and its owner keeps the descriptor alive for this call.
    if unsafe { android_setsocknetwork(network, socket.as_raw_fd()) } == 0 {
        Ok(())
    } else {
        Err(io::Error::last_os_error())
    }
}
