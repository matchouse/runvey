use async_trait::async_trait;
use hickory_server::ServerFuture;
use hickory_server::authority::AuthorityObject;
use hickory_server::proto::rr::rdata::TXT;
use hickory_server::proto::rr::{LowerName, Name, RData, Record};
use hickory_server::{
    authority::Catalog, authority::ZoneType, store::in_memory::InMemoryAuthority,
};
use instant_acme::{Account, Key};
use pingora::prelude::background_service;
use pingora::server::{ListenFds, ShutdownWatch};
use pingora::services::Service;
use pingora::services::background::BackgroundService;
use pingora::{
    Result,
    http::RequestHeader,
    lb::LoadBalancer,
    prelude::{HttpPeer, RoundRobin},
    proxy,
    server::Server,
};
use std::net::SocketAddr;
use std::net::UdpSocket as StdUdpSocket;
use std::os::fd::{AsRawFd, FromRawFd};
use std::{
    net::{IpAddr, Ipv4Addr},
    sync::Arc,
};
use tokio::net::UdpSocket;

use crate::network::ip::Endpoint;
use log::info;

mod network;

pub struct LB(Arc<LoadBalancer<RoundRobin>>);

#[async_trait]
impl proxy::ProxyHttp for LB {
    type CTX = ();
    fn new_ctx(&self) -> Self::CTX {
        ()
    }

    async fn upstream_peer(
        &self,
        _session: &mut proxy::Session,
        _ctx: &mut Self::CTX,
    ) -> Result<Box<HttpPeer>> {
        let upstream = self.0.select(b"", 256).unwrap();
        info!("upstream peer is: {upstream:?}");

        // Set SNI to one.one.one.one
        let peer = Box::new(HttpPeer::new(upstream, false, "".to_string()));
        Ok(peer)
    }

    async fn upstream_request_filter(
        &self,
        _session: &mut proxy::Session,
        _upstream_request: &mut RequestHeader,
        _ctx: &mut Self::CTX,
    ) -> Result<()> {
        Ok(())
    }
}

pub struct DnsService {}

impl DnsService {
    pub fn new() -> Self {
        Self {}
    }
}

#[async_trait]
impl Service for DnsService {
    fn name(&self) -> &str {
        "HickoryDNS"
    }

    // The signature matches your provided snippet
    async fn start_service(
        &mut self,
        fds: Option<ListenFds>, // We ignore FDS for now (fresh bind every time)
        mut shutdown: ShutdownWatch,
        _listeners_per_fd: usize, // Ignored for this custom service
    ) {
        info!("Initializing DNS Service on {}", "127.0.0.1:1053");

        let mut catalog = hickory_server::authority::Catalog::new();
        let origin = Name::from_ascii("acme.example.com.").expect("failed to create dns name");
        let authority = InMemoryAuthority::empty(origin.clone(), ZoneType::Primary, false);
        let txt = TXT::new(vec!["hello from proxy".to_string()]);
        let txt_record = Record::from_rdata(origin.clone(), 300, RData::TXT(txt));

        authority.upsert(txt_record, 0).await;

        let authority_obj: Arc<dyn AuthorityObject> = Arc::new(authority);
        let lowername = LowerName::new(&origin);

        catalog.upsert(lowername, vec![authority_obj.clone()]);

        let mut server = ServerFuture::new(catalog);
        let udp_socket = if let Some(fds) = fds.as_ref() {
            let mut fds_lock = fds.lock().await;

            if let Some(&fd) = fds_lock.get("0.0.0.0:1053") {
                unsafe { StdUdpSocket::from_raw_fd(fd) }
            } else {
                let sock = StdUdpSocket::bind("0.0.0.0:1053").expect("Failed to bind UDP");
                fds_lock.add("0.0.0.0:1053".to_string(), sock.as_raw_fd());
                sock
            }
        } else {
            StdUdpSocket::bind("0.0.0.0:1053").expect("Failed to bind UDP")
        };

        udp_socket
            .set_nonblocking(true)
            .expect("failed to set non-blocking");
        let tokio_udp = tokio::net::UdpSocket::from_std(udp_socket)
            .expect("failed to convert std udp to tokio udp");
        server.register_socket(tokio_udp);

        println!("DNS Service Started.");

        tokio::select! {
            result = server.block_until_done() => {
                if let Err(e) = result {
                    eprintln!("DNS Server crashed: {}", e);
                }
            }
            _ = shutdown.changed() => {
                println!("Shutdown signal received. Stopping DNS Service...");
            }
        }
    }
}

fn main() {
    env_logger::init();
    let mut my_server = Server::new(None).unwrap();
    my_server.bootstrap();

    let endpoint = Endpoint::new(IpAddr::V4(Ipv4Addr::new(127, 0, 0, 0)), 8080, false);
    let upstreams = LoadBalancer::try_from_iter([
        endpoint,
        Endpoint::new(IpAddr::V4(Ipv4Addr::new(127, 0, 0, 0)), 8081, false),
    ])
    .unwrap();
    let mut lb = proxy::http_proxy_service(&my_server.configuration, LB(Arc::new(upstreams)));
    lb.add_tcp("0.0.0.0:6188");

    let dns_service = DnsService::new();

    my_server.add_service(dns_service);
    my_server.add_service(lb);
    my_server.run_forever();
}
