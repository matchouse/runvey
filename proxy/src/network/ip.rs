use std::{
    net::{IpAddr, Ipv6Addr, SocketAddr, ToSocketAddrs},
    vec::IntoIter,
};

#[derive(Clone, Copy, Debug)]
pub struct Endpoint {
    addr: u128,
    meta: u64,
}

const PORT_MASK: u64 = 0x0000_0000_0000_FFFF;
const HEALTH_BIT: u64 = 0x8000_0000_0000_0000;

impl Endpoint {
    pub fn new(ip: IpAddr, port: u16, healthy: bool) -> Self {
        // 1. Normalize everything to IPv6 (u128)
        let addr_bits = match ip {
            IpAddr::V4(v4) => v4.to_ipv6_mapped().to_bits(),
            IpAddr::V6(v6) => v6.to_bits(),
        };

        let mut meta = port as u64;
        if healthy {
            meta |= HEALTH_BIT;
        }

        Self {
            addr: addr_bits,
            meta,
        }
    }

    pub fn is_healthy(&self) -> bool {
        (self.meta & HEALTH_BIT) != 0
    }

    pub fn set_healthy(&mut self, healthy: bool) {
        if healthy {
            self.meta |= HEALTH_BIT;
        } else {
            self.meta &= !HEALTH_BIT;
        }
    }

    pub fn to_socket_addr(&self) -> std::net::SocketAddr {
        let ip = Ipv6Addr::from(self.addr);
        let port = (self.meta & PORT_MASK) as u16;

        match ip.to_ipv4_mapped() {
            Some(v4) => std::net::SocketAddr::new(IpAddr::V4(v4), port),
            None => std::net::SocketAddr::new(IpAddr::V6(ip), port),
        }
    }
}

impl ToSocketAddrs for Endpoint {
    type Iter = IntoIter<SocketAddr>;

    fn to_socket_addrs(&self) -> std::io::Result<Self::Iter> {
        let addr = self.to_socket_addr();

        Ok(vec![addr].into_iter())
    }
}
