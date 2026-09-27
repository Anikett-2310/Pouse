use serde::{Deserialize, Serialize};
use std::fs;
use std::net::UdpSocket;
use std::path::PathBuf;

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct PairingPayload {
    #[serde(rename = "type")]
    pub payload_type: String,
    pub version: u32,
    pub name: String,
    pub host: String,
    pub port: u16,
    #[serde(rename = "protocolVersion")]
    pub protocol_version: u32,
    #[serde(rename = "pairToken")]
    pub pair_token: String,
    pub capabilities: Vec<String>,
}

impl PairingPayload {
    pub fn new(port: u16, reset_pairing: bool) -> Self {
        let host = get_local_ip().unwrap_or_else(|| "127.0.0.1".to_string());
        let name = std::env::var("COMPUTERNAME")
            .or_else(|_| std::env::var("HOSTNAME"))
            .unwrap_or_else(|_| "Pouse PC".to_string());
        let pair_token = get_or_create_pair_token(reset_pairing);

        Self {
            payload_type: "pouse_pair".to_string(),
            version: 1,
            name,
            host,
            port,
            protocol_version: 1,
            pair_token,
            capabilities: vec![
                "touchpad".to_string(),
                "motion".to_string(),
                "touchless".to_string(),
                "screen".to_string(),
            ],
        }
    }

    pub fn to_json(&self) -> String {
        serde_json::to_string(self).unwrap_or_default()
    }
}

pub fn get_pairing_file_path() -> PathBuf {
    if let Ok(appdata) = std::env::var("APPDATA") {
        let dir = PathBuf::from(appdata).join("Pouse");
        let _ = fs::create_dir_all(&dir);
        dir.join("pairing.json")
    } else {
        PathBuf::from("pairing.json")
    }
}

pub fn generate_random_token() -> String {
    let mut bytes = [0u8; 16];
    unsafe {
        use windows::Win32::Security::Cryptography::{BCryptGenRandom, BCRYPT_USE_SYSTEM_PREFERRED_RNG};
        let _ = BCryptGenRandom(None, &mut bytes, BCRYPT_USE_SYSTEM_PREFERRED_RNG);
    }
    bytes.iter().map(|b| format!("{:02x}", b)).collect()
}

pub fn redact_token(token: &str) -> String {
    if token.len() <= 8 {
        "****".to_string()
    } else {
        format!("{}...****", &token[..4])
    }
}

pub fn get_or_create_pair_token(reset: bool) -> String {
    let path = get_pairing_file_path();
    if !reset && path.exists() {
        if let Ok(content) = fs::read_to_string(&path) {
            if let Ok(json) = serde_json::from_str::<serde_json::Value>(&content) {
                if let Some(token) = json.get("pairToken").and_then(|v| v.as_str()) {
                    if !token.trim().is_empty() {
                        return token.trim().to_string();
                    }
                }
            }
        }
    }

    let new_token = generate_random_token();
    let payload_data = serde_json::json!({
        "pairToken": new_token
    });
    if let Ok(str_val) = serde_json::to_string_pretty(&payload_data) {
        let _ = fs::write(&path, str_val);
    }
    new_token
}

pub fn get_local_ip() -> Option<String> {
    let socket = UdpSocket::bind("0.0.0.0:0").ok()?;
    socket.connect("8.8.8.8:80").ok()?;
    let local_addr = socket.local_addr().ok()?;
    Some(local_addr.ip().to_string())
}

pub fn print_pairing_info(port: u16, reset_pairing: bool) {
    let payload = PairingPayload::new(port, reset_pairing);
    let json_str = payload.to_json();

    println!("==================================================");
    println!("  Pouse PC Client Server Listening on Port {}", payload.port);
    println!("  PC Name: {}", payload.name);
    println!("  Local IP Address: {}", payload.host);
    println!("  WebSocket Address: ws://{}:{}", payload.host, payload.port);
    println!("  Pairing Token: {}", redact_token(&payload.pair_token));
    println!("  Capabilities: {:?}", payload.capabilities);
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
            protocol_version: 1,
            pair_token: "4f9a1c8b3e2d6f0a5c7b9e1d3f5a7c9b".to_string(),
            capabilities: vec!["touchpad".to_string(), "screen".to_string()],
        };

        let json = payload.to_json();
        assert!(json.contains(r#""type":"pouse_pair""#));
        assert!(json.contains(r#""version":1"#));
        assert!(json.contains(r#""host":"192.168.1.100""#));
        assert!(json.contains(r#""port":8081"#));
        assert!(json.contains(r#""protocolVersion":1"#));
        assert!(json.contains(r#""pairToken":"4f9a1c8b3e2d6f0a5c7b9e1d3f5a7c9b""#));
        assert!(json.contains(r#""capabilities":["touchpad","screen"]"#));

        let deserialized: PairingPayload = serde_json::from_str(&json).unwrap();
        assert_eq!(payload, deserialized);
    }

    #[test]
    fn test_persistent_pair_token_lifecycle() {
        let token1 = get_or_create_pair_token(false);
        assert_eq!(token1.len(), 32);

        // Subsequent call returns same token
        let token2 = get_or_create_pair_token(false);
        assert_eq!(token1, token2);

        // Reset pairing generates new token
        let token3 = get_or_create_pair_token(true);
        assert_eq!(token3.len(), 32);
        assert_ne!(token1, token3);
    }

    #[test]
    fn test_redact_token() {
        let token = "4f9a1c8b3e2d6f0a5c7b9e1d3f5a7c9b";
        let redacted = redact_token(token);
        assert_eq!(redacted, "4f9a...****");
        assert!(!redacted.contains("3e2d6f0a"));
    }
}
