use super::{
    sha256_text, DiscoveryRequest, DiscoveryResponse, PairRequest, PairResponse, DISCOVERY_PORT,
};
use axum::http::StatusCode;
use base64::{engine::general_purpose::URL_SAFE_NO_PAD, Engine as _};
use std::{
    io,
    net::{Ipv4Addr, SocketAddr, SocketAddrV4},
    time::Duration,
};
use tauri::AppHandle;
use tokio::net::UdpSocket;

#[cfg(target_os = "android")]
use tauri_plugin_native_bridge::{NativeBridgeExt, PairingLink};

const DISCOVERY_TIMEOUT: Duration = Duration::from_secs(8);
const CONNECTION_TIMEOUT: Duration = Duration::from_secs(12);
const NOT_FOUND: &str =
    "找不到配对会话。请确认两台设备连接同一局域网，并在另一台设备上重新生成配对码。";
#[cfg(target_os = "android")]
const VPN_HINT: &str = "请在 VPN 或代理应用中允许局域网连接，或暂停 VPN 后重试。";

pub(super) struct PairingEndpoint {
    pub(super) session_id: String,
    pub(super) host_public_key: [u8; 32],
    address: SocketAddrV4,
    #[cfg(target_os = "android")]
    network: u64,
    #[cfg(target_os = "android")]
    vpn_active: bool,
}

struct DiscoveryRoute {
    #[cfg(target_os = "android")]
    link: PairingLink,
    #[cfg(target_os = "android")]
    vpn_active: bool,
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
        return (u32::from(_peer) & self.mask()) == (u32::from(self.link.address) & self.mask());
        #[cfg(not(target_os = "android"))]
        true
    }
}

pub(super) async fn discover(_app: &AppHandle, code: &str) -> Result<PairingEndpoint, String> {
    let request = serde_json::to_vec(&DiscoveryRequest {
        kind: "leeef-pair-discover".into(),
        code_hash: sha256_text(code),
    })
    .map_err(|error| error.to_string())?;

    #[cfg(not(target_os = "android"))]
    {
        discover_on_route(DiscoveryRoute {}, &request)
            .await
            .map_err(|error| format!("无法使用局域网配对：{error}"))?
            .ok_or_else(|| NOT_FOUND.into())
    }
    #[cfg(target_os = "android")]
    {
        let networks = _app
            .native_bridge()
            .pairing_networks()
            .await
            .map_err(|_| "无法读取局域网状态，请检查 Wi-Fi 连接后重试。")?;
        let vpn_active = networks.vpn_active;
        let mut attempts = tokio::task::JoinSet::new();
        for link in networks
            .links
            .into_iter()
            .filter(|link| (1..=30).contains(&link.prefix_length))
        {
            let route = DiscoveryRoute { link, vpn_active };
            let request = request.clone();
            attempts.spawn(async move { discover_on_route(route, &request).await });
        }
        if attempts.is_empty() {
            let message = "本机没有可用于配对的局域网连接。请连接 Wi-Fi 后重试。";
            return Err(if vpn_active {
                format!("{message}{VPN_HINT}")
            } else {
                message.into()
            });
        }
        while let Some(result) = attempts.join_next().await {
            if let Ok(Ok(Some(endpoint))) = result {
                return Ok(endpoint);
            }
        }
        Err(if vpn_active {
            format!("{NOT_FOUND}{VPN_HINT}")
        } else {
            NOT_FOUND.into()
        })
    }
}

async fn discover_on_route(
    route: DiscoveryRoute,
    request: &[u8],
) -> io::Result<Option<PairingEndpoint>> {
    let socket = route.listen()?;
    let targets = route.targets();
    let mut buffer = [0_u8; 2048];
    let mut resend = tokio::time::interval(Duration::from_secs(1));
    resend.set_missed_tick_behavior(tokio::time::MissedTickBehavior::Skip);
    let discovery = async {
        loop {
            tokio::select! {
                _ = resend.tick() => {
                    let mut sent = false;
                    for target in targets {
                        sent |= socket.send_to(request, (target, DISCOVERY_PORT)).await.is_ok();
                    }
                    if !sent {
                        return Err(io::Error::other("无法发送配对广播"));
                    }
                }
                incoming = socket.recv_from(&mut buffer) => {
                    let (length, peer) = incoming?;
                    let SocketAddr::V4(peer) = peer else { continue };
                    if !route.contains(*peer.ip()) {
                        continue;
                    }
                    let Ok(offer) = serde_json::from_slice::<DiscoveryResponse>(&buffer[..length])
                    else { continue };
                    if offer.kind != "leeef-pair-offer" || offer.port == 0 || offer.session_id.is_empty() {
                        continue;
                    }
                    let Some(host_public_key) = URL_SAFE_NO_PAD.decode(&offer.host_public_key)
                        .ok().and_then(|key| key.try_into().ok())
                    else { continue };
                    return Ok(PairingEndpoint {
                        address: SocketAddrV4::new(*peer.ip(), offer.port),
                        session_id: offer.session_id,
                        host_public_key,
                        #[cfg(target_os = "android")]
                        network: route.link.handle,
                        #[cfg(target_os = "android")]
                        vpn_active: route.vpn_active,
                    });
                }
            }
        }
    };
    match tokio::time::timeout(DISCOVERY_TIMEOUT, discovery).await {
        Ok(result) => result.map(Some),
        Err(_) => Ok(None),
    }
}

impl PairingEndpoint {
    pub(super) async fn exchange(&self, request: &PairRequest) -> Result<PairResponse, String> {
        let (status, body) = self.post(request).await?;
        if !status.is_success() {
            return Err(String::from_utf8(body).unwrap_or_else(|_| "配对失败".into()));
        }
        serde_json::from_slice(&body).map_err(|_| "已有设备返回了无法读取的配对数据".into())
    }

    #[cfg(not(target_os = "android"))]
    async fn post(&self, request: &PairRequest) -> Result<(StatusCode, Vec<u8>), String> {
        let client = reqwest::Client::builder()
            .timeout(CONNECTION_TIMEOUT)
            .no_proxy()
            .redirect(reqwest::redirect::Policy::none())
            .build()
            .map_err(|error| error.to_string())?;
        let response = client
            .post(format!("http://{}/pair", self.address))
            .json(request)
            .send()
            .await
            .map_err(|_| "已找到配对设备，但无法连接。请检查发起配对的设备是否仍在线。")?;
        let status = response.status();
        let body = response.bytes().await.map_err(|error| error.to_string())?;
        Ok((status, body.to_vec()))
    }

    #[cfg(target_os = "android")]
    async fn post(&self, request: &PairRequest) -> Result<(StatusCode, Vec<u8>), String> {
        use http_body_util::{BodyExt, Full};
        use hyper::{body::Bytes, client::conn::http1, header, Request};
        use hyper_util::rt::TokioIo;

        let body = serde_json::to_vec(request).map_err(|error| error.to_string())?;
        let post = async {
            let socket = tokio::net::TcpSocket::new_v4()?;
            bind_to_network(&socket, self.network)?;
            let stream = socket.connect(self.address.into()).await?;
            let (mut sender, connection) = http1::handshake(TokioIo::new(stream)).await?;
            let request = Request::post("/pair")
                .header(header::HOST, self.address.to_string())
                .header(header::CONTENT_TYPE, "application/json")
                .header(header::CONNECTION, "close")
                .body(Full::new(Bytes::from(body)))?;
            let response = async {
                let response = sender.send_request(request).await?;
                let status = response.status();
                let body = response.into_body().collect().await?.to_bytes().to_vec();
                Ok((status, body))
            };
            tokio::select! {
                result = response => result,
                result = async {
                    connection.await?;
                    std::future::pending::<Result<_, hyper::Error>>().await
                } => result,
            }
            .map_err(Box::<dyn std::error::Error + Send + Sync>::from)
        };
        match tokio::time::timeout(CONNECTION_TIMEOUT, post).await {
            Ok(Ok(response)) => Ok(response),
            _ => {
                let error = "已找到配对设备，但无法连接。请检查发起配对的设备是否仍在线。";
                Err(if self.vpn_active {
                    format!("{error}{VPN_HINT}")
                } else {
                    error.into()
                })
            }
        }
    }
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
