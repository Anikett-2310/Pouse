use serde::{Deserialize, Serialize};
use std::net::UdpSocket;

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct PairingPayload {
    #[serde(rename = "type")]
    pub payload_type: String,
    pub version: u32,
    pub name: String,
    pub host: String,
    pub port: u16,
}

impl PairingPayload {
    pub fn new(port: u16) -> Self {
        let host = get_local_ip().unwrap_or_else(|| "127.0.0.1".to_string());
        let name = std::env::var("COMPUTERNAME")
            .or_else(|_| std::env::var("HOSTNAME"))
            .unwrap_or_else(|_| "Pouse PC".to_string());

        Self {
            payload_type: "pouse_pair".to_string(),
            version: 1,
            name,
            host,
            port,
        }
    }

    pub fn to_json(&self) -> String {
        serde_json::to_string(self).unwrap_or_default()
    }
}

pub fn get_local_ip() -> Option<String> {
    let socket = UdpSocket::bind("0.0.0.0:0").ok()?;
    socket.connect("8.8.8.8:80").ok()?;
    let local_addr = socket.local_addr().ok()?;
    Some(local_addr.ip().to_string())
}

pub fn print_pairing_info(port: u16) {
    let payload = PairingPayload::new(port);
    let json_str = payload.to_json();

    println!("==================================================");
    println!("  Pouse PC Client Server Listening on Port {}", payload.port);
    println!("  PC Name: {}", payload.name);
    println!("  Local IP Address: {}", payload.host);
    println!("  WebSocket Address: ws://{}:{}", payload.host, payload.port);
    println!("==================================================");
    println!("  Scan QR code with Pouse Mobile App to pair:");
    println!();
    if let Err(e) = qr2term::print_qr(&json_str) {
        eprintln!("Failed to render QR code: {}", e);
    }
    println!("==================================================");
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_pairing_payload_serialization() {
        let payload = PairingPayload {
            payload_type: "pouse_pair".to_string(),
            version: 1,
            name: "Test PC".to_string(),
            host: "192.168.1.100".to_string(),
            port: 8081,
        };

        let json = payload.to_json();
        assert!(json.contains(r#""type":"pouse_pair""#));
        assert!(json.contains(r#""version":1"#));
        assert!(json.contains(r#""host":"192.168.1.100""#));
        assert!(json.contains(r#""port":8081"#));

        let deserialized: PairingPayload = serde_json::from_str(&json).unwrap();
        assert_eq!(payload, deserialized);
    }
}
