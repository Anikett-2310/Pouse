use serde::{Deserialize, Serialize};
use std::fs;
use std::path::{Path, PathBuf};
use std::sync::{Arc, Mutex, OnceLock};

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct GeneralConfig {
    #[serde(rename = "deviceName")]
    pub device_name: String,
    pub port: u16,
    #[serde(rename = "startWithWindows")]
    pub start_with_windows: bool,
    #[serde(rename = "minimizeToTrayOnClose")]
    pub minimize_to_tray_on_close: bool,
    #[serde(rename = "compatibleInputMode")]
    pub compatible_input_mode: bool,
}

impl Default for GeneralConfig {
    fn default() -> Self {
        let name = std::env::var("COMPUTERNAME")
            .or_else(|_| std::env::var("HOSTNAME"))
            .unwrap_or_else(|_| "Pouse PC".to_string());
        Self {
            device_name: name,
            port: 8081,
            start_with_windows: false,
            minimize_to_tray_on_close: true,
            compatible_input_mode: false,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct SecurityConfig {
    #[serde(rename = "pairToken")]
    pub pair_token: String,
    #[serde(rename = "wifiPasswordEncrypted")]
    pub wifi_password_encrypted: Option<String>,
    #[serde(rename = "requireWifiPassword")]
    pub require_wifi_password: bool,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct RecentDevice {
    pub name: String,
    pub address: String,
    #[serde(rename = "lastSeen")]
    pub last_seen: u64,
    pub transport: String,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct AppConfig {
    pub version: u32,
    pub general: GeneralConfig,
    pub security: SecurityConfig,
    #[serde(rename = "recentDevices")]
    pub recent_devices: Vec<RecentDevice>,
}

impl AppConfig {
    pub fn new_with_token(pair_token: String) -> Self {
        Self {
            version: 1,
            general: GeneralConfig::default(),
            security: SecurityConfig {
                pair_token,
                wifi_password_encrypted: None,
                require_wifi_password: false,
            },
            recent_devices: Vec::new(),
        }
    }
}

pub fn get_config_dir() -> PathBuf {
    if let Ok(appdata) = std::env::var("APPDATA") {
        let dir = PathBuf::from(appdata).join("Pouse");
        let _ = fs::create_dir_all(&dir);
        dir
    } else {
        PathBuf::from(".")
    }
}

pub fn get_config_file_path() -> PathBuf {
    get_config_dir().join("config.json")
}

pub fn get_legacy_pairing_file_path() -> PathBuf {
    get_config_dir().join("pairing.json")
}

#[cfg(target_os = "windows")]
unsafe extern "system" {
    fn LocalFree(hmem: *mut std::ffi::c_void) -> *mut std::ffi::c_void;
}

#[cfg(target_os = "windows")]
pub fn encrypt_credential_dpapi(plain: &str) -> Result<String, String> {
    use windows::core::PCWSTR;
    use windows::Win32::Security::Cryptography::{CryptProtectData, CRYPT_INTEGER_BLOB};

    let bytes = plain.as_bytes();
    let data_in = CRYPT_INTEGER_BLOB {
        cbData: bytes.len() as u32,
        pbData: bytes.as_ptr() as *mut u8,
    };
    let mut data_out = CRYPT_INTEGER_BLOB {
        cbData: 0,
        pbData: std::ptr::null_mut(),
    };

    let ok = unsafe {
        CryptProtectData(
            &data_in,
            PCWSTR::null(),
            None,
            None,
            None,
            1, // CRYPTPROTECT_UI_FORBIDDEN
            &mut data_out,
        )
    };

    if ok.is_err() {
        return Err("CryptProtectData failed".to_string());
    }

    let slice = unsafe { std::slice::from_raw_parts(data_out.pbData, data_out.cbData as usize) };
    let b64 = simple_base64_encode(slice);

    unsafe {
        LocalFree(data_out.pbData as _);
    }

    Ok(b64)
}

#[cfg(target_os = "windows")]
pub fn decrypt_credential_dpapi(b64: &str) -> Result<String, String> {
    use windows::Win32::Security::Cryptography::{CryptUnprotectData, CRYPT_INTEGER_BLOB};

    let ciphertext = simple_base64_decode(b64).map_err(|e| format!("Invalid Base64: {}", e))?;
    let data_in = CRYPT_INTEGER_BLOB {
        cbData: ciphertext.len() as u32,
        pbData: ciphertext.as_ptr() as *mut u8,
    };
    let mut data_out = CRYPT_INTEGER_BLOB {
        cbData: 0,
        pbData: std::ptr::null_mut(),
    };

    let ok = unsafe {
        CryptUnprotectData(
            &data_in,
            None,
            None,
            None,
            None,
            1, // CRYPTPROTECT_UI_FORBIDDEN
            &mut data_out,
        )
    };

    if ok.is_err() {
        return Err("CryptUnprotectData failed (cannot decrypt on this machine/user)".to_string());
    }

    let slice = unsafe { std::slice::from_raw_parts(data_out.pbData, data_out.cbData as usize) };
    let result = String::from_utf8(slice.to_vec()).map_err(|_| "Decrypted data is not valid UTF-8".to_string());

    unsafe {
        LocalFree(data_out.pbData as _);
    }

    result
}

#[cfg(not(target_os = "windows"))]
pub fn encrypt_credential_dpapi(plain: &str) -> Result<String, String> {
    Ok(simple_base64_encode(plain.as_bytes()))
}

#[cfg(not(target_os = "windows"))]
pub fn decrypt_credential_dpapi(b64: &str) -> Result<String, String> {
    let bytes = simple_base64_decode(b64).map_err(|e| e.to_string())?;
    String::from_utf8(bytes).map_err(|_| "Invalid UTF-8".to_string())
}

// ─── Minimal Base64 encoder/decoder (zero external crate dependency) ────────

const B64_CHARS: &[u8; 64] = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

pub fn simple_base64_encode(data: &[u8]) -> String {
    let mut result = String::new();
    let mut i = 0;
    while i < data.len() {
        let b0 = data[i];
        let b1 = if i + 1 < data.len() { data[i + 1] } else { 0 };
        let b2 = if i + 2 < data.len() { data[i + 2] } else { 0 };

        let n = ((b0 as u32) << 16) | ((b1 as u32) << 8) | (b2 as u32);

        result.push(B64_CHARS[((n >> 18) & 63) as usize] as char);
        result.push(B64_CHARS[((n >> 12) & 63) as usize] as char);
        if i + 1 < data.len() {
            result.push(B64_CHARS[((n >> 6) & 63) as usize] as char);
        } else {
            result.push('=');
        }
        if i + 2 < data.len() {
            result.push(B64_CHARS[(n & 63) as usize] as char);
        } else {
            result.push('=');
        }
        i += 3;
    }
    result
}

pub fn simple_base64_decode(s: &str) -> Result<Vec<u8>, &'static str> {
    let s = s.trim();
    if s.is_empty() {
        return Ok(Vec::new());
    }
    let mut out = Vec::with_capacity(s.len() * 3 / 4);
    let mut buf = [0u8; 4];
    let mut buf_len = 0;

    for &b in s.as_bytes() {
        if b == b'=' {
            break;
        }
        let val = match b {
            b'A'..=b'Z' => b - b'A',
            b'a'..=b'z' => b - b'a' + 26,
            b'0'..=b'9' => b - b'0' + 52,
            b'+' => 62,
            b'/' => 63,
            b'\r' | b'\n' | b' ' => continue,
            _ => return Err("Invalid base64 character"),
        };
        buf[buf_len] = val;
        buf_len += 1;
        if buf_len == 4 {
            let n = ((buf[0] as u32) << 18) | ((buf[1] as u32) << 12) | ((buf[2] as u32) << 6) | (buf[3] as u32);
            out.push(((n >> 16) & 0xFF) as u8);
            out.push(((n >> 8) & 0xFF) as u8);
            out.push((n & 0xFF) as u8);
            buf_len = 0;
        }
    }

    if buf_len == 2 {
        let n = ((buf[0] as u32) << 18) | ((buf[1] as u32) << 12);
        out.push(((n >> 16) & 0xFF) as u8);
    } else if buf_len == 3 {
        let n = ((buf[0] as u32) << 18) | ((buf[1] as u32) << 12) | ((buf[2] as u32) << 6);
        out.push(((n >> 16) & 0xFF) as u8);
        out.push(((n >> 8) & 0xFF) as u8);
    }

    Ok(out)
}

// ─── Config Manager & Safe Migration ────────────────────────────────────────

pub struct ConfigManager {
    config: Arc<Mutex<AppConfig>>,
    config_path: PathBuf,
}

static GLOBAL_CONFIG: OnceLock<ConfigManager> = OnceLock::new();

impl ConfigManager {
    pub fn global() -> &'static ConfigManager {
        GLOBAL_CONFIG.get_or_init(|| {
            let config_path = get_config_file_path();
            let legacy_path = get_legacy_pairing_file_path();
            Self::load_or_migrate(&config_path, &legacy_path)
        })
    }

    pub fn load_or_migrate(config_path: &Path, legacy_path: &Path) -> Self {
        // 1. If config.json exists, load it
        if config_path.exists() {
            if let Ok(content) = fs::read_to_string(config_path) {
                if let Ok(config) = serde_json::from_str::<AppConfig>(&content) {
                    println!("[CONFIG] Configuration loaded successfully.");
                    return Self {
                        config: Arc::new(Mutex::new(config)),
                        config_path: config_path.to_path_buf(),
                    };
                } else {
                    eprintln!("[CONFIG] Warning: config.json corrupted, checking for migration or defaults.");
                }
            }
        }

        // 2. If config.json does NOT exist, check for legacy pairing.json
        if legacy_path.exists() {
            if let Ok(content) = fs::read_to_string(legacy_path) {
                if let Ok(json) = serde_json::from_str::<serde_json::Value>(&content) {
                    if let Some(token) = json.get("pairToken").and_then(|v| v.as_str()) {
                        let trimmed = token.trim();
                        if !trimmed.is_empty() {
                            // Backup existing pairing.json
                            let backup_path = legacy_path.with_extension("json.bak");
                            let _ = fs::copy(legacy_path, &backup_path);

                            let app_config = AppConfig::new_with_token(trimmed.to_string());
                            let mgr = Self {
                                config: Arc::new(Mutex::new(app_config)),
                                config_path: config_path.to_path_buf(),
                            };
                            mgr.save();
                            // Strict non-leak log requirement
                            println!("[CONFIG] Existing pairing configuration migrated successfully.");
                            return mgr;
                        }
                    }
                }
            }
        }

        // 3. Fallback: generate clean new configuration with fresh cryptographic token
        let fresh_token = crate::pairing::generate_random_token();
        let app_config = AppConfig::new_with_token(fresh_token);
        let mgr = Self {
            config: Arc::new(Mutex::new(app_config)),
            config_path: config_path.to_path_buf(),
        };
        mgr.save();
        println!("[CONFIG] Initial configuration initialized.");
        mgr
    }

    pub fn get_config(&self) -> AppConfig {
        self.config.lock().unwrap().clone()
    }

    pub fn set_config(&self, new_cfg: AppConfig) {
        {
            let mut cfg = self.config.lock().unwrap();
            *cfg = new_cfg;
        }
        self.save();
    }

    pub fn get_pair_token(&self) -> String {
        self.config.lock().unwrap().security.pair_token.clone()
    }

    pub fn set_pair_token(&self, new_token: String) {
        {
            let mut cfg = self.config.lock().unwrap();
            cfg.security.pair_token = new_token;
        }
        self.save();
    }

    pub fn get_wifi_password(&self) -> Option<String> {
        let cfg = self.config.lock().unwrap();
        if !cfg.security.require_wifi_password {
            return None;
        }
        let b64 = cfg.security.wifi_password_encrypted.as_ref()?;
        match decrypt_credential_dpapi(b64) {
            Ok(pass) => Some(pass),
            Err(e) => {
                eprintln!("[SECURITY] Stored Wi-Fi password could not be decrypted: {}", e);
                None
            }
        }
    }

    pub fn set_wifi_password(&self, password: Option<&str>) -> Result<(), String> {
        let (encrypted, required) = match password {
            Some(p) if !p.trim().is_empty() => {
                let enc = encrypt_credential_dpapi(p.trim())?;
                (Some(enc), true)
            }
            _ => (None, false),
        };

        {
            let mut cfg = self.config.lock().unwrap();
            cfg.security.wifi_password_encrypted = encrypted;
            cfg.security.require_wifi_password = required;
        }
        self.save();
        Ok(())
    }

    pub fn add_recent_device(&self, name: String, address: String, transport: String) {
        let now = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap_or_default()
            .as_secs();

        let mut cfg = self.config.lock().unwrap();
        // Remove existing entry for same address to prevent duplicates
        cfg.recent_devices.retain(|d| d.address != address);
        cfg.recent_devices.insert(0, RecentDevice {
            name,
            address,
            last_seen: now,
            transport,
        });
        // Retain at most 10 recent devices for UI history
        cfg.recent_devices.truncate(10);
        drop(cfg);
        self.save();
    }

    pub fn save(&self) {
        let cfg = self.config.lock().unwrap();
        if let Ok(json_str) = serde_json::to_string_pretty(&*cfg) {
            let tmp_path = self.config_path.with_extension("json.tmp");
            if fs::write(&tmp_path, json_str).is_ok() {
                let _ = fs::rename(&tmp_path, &self.config_path);
            }
        }
    }
}

// ─── Windows Startup Registration (HKCU - No Admin Required) ─────────────────

#[cfg(target_os = "windows")]
pub fn set_windows_startup(enable: bool) -> Result<(), String> {
    use windows::core::{HSTRING, PCWSTR};
    use windows::Win32::System::Registry::{
        RegCloseKey, RegDeleteValueW, RegOpenKeyExW, RegSetValueExW, HKEY_CURRENT_USER,
        KEY_SET_VALUE, REG_SZ,
    };

    let subkey = HSTRING::from("Software\\Microsoft\\Windows\\CurrentVersion\\Run");
    let mut hkey = windows::Win32::System::Registry::HKEY::default();

    let status = unsafe {
        RegOpenKeyExW(
            HKEY_CURRENT_USER,
            PCWSTR(subkey.as_ptr()),
            0,
            KEY_SET_VALUE,
            &mut hkey,
        )
    };

    if status.is_err() {
        return Err("Failed to open HKCU Run registry key".to_string());
    }

    let value_name = HSTRING::from("Pouse");

    let result = if enable {
        if let Ok(current_exe) = std::env::current_exe() {
            let exe_str = format!("\"{}\" --minimized", current_exe.to_string_lossy());
            let exe_hstring = HSTRING::from(&exe_str);
            let bytes_len = (exe_hstring.len() + 1) * 2;
            let res = unsafe {
                RegSetValueExW(
                    hkey,
                    PCWSTR(value_name.as_ptr()),
                    0,
                    REG_SZ,
                    Some(std::slice::from_raw_parts(exe_hstring.as_ptr() as *const u8, bytes_len)),
                )
            };
            if res.is_ok() { Ok(()) } else { Err("RegSetValueExW failed".to_string()) }
        } else {
            Err("Failed to get current executable path".to_string())
        }
    } else {
        let res = unsafe { RegDeleteValueW(hkey, PCWSTR(value_name.as_ptr())) };
        // Deleting non-existent value is acceptable
        if res.is_ok() || res.0 == 2 { Ok(()) } else { Err("RegDeleteValueW failed".to_string()) }
    };

    unsafe { let _ = RegCloseKey(hkey); }
    result
}

#[cfg(not(target_os = "windows"))]
pub fn set_windows_startup(_enable: bool) -> Result<(), String> {
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_base64_roundtrip() {
        let sample = b"Pouse Secure Wi-Fi Password 1234!@#$%^&*()_+";
        let encoded = simple_base64_encode(sample);
        let decoded = simple_base64_decode(&encoded).unwrap();
        assert_eq!(sample.as_slice(), decoded.as_slice());
    }

    #[test]
    fn test_dpapi_roundtrip() {
        let secret = "super_secret_wifi_pass_123";
        let encrypted = encrypt_credential_dpapi(secret).unwrap();
        assert_ne!(secret, encrypted);
        let decrypted = decrypt_credential_dpapi(&encrypted).unwrap();
        assert_eq!(secret, decrypted);
    }

    #[test]
    fn test_config_migration_idempotent() {
        let temp_dir = std::env::temp_dir();
        let rand_id = crate::pairing::generate_random_token();
        let cfg_path = temp_dir.join(format!("test_config_{}.json", rand_id));
        let legacy_path = temp_dir.join(format!("test_legacy_{}.json", rand_id));
        let backup_path = legacy_path.with_extension("json.bak");

        let _ = fs::remove_file(&cfg_path);
        let _ = fs::remove_file(&legacy_path);
        let _ = fs::remove_file(&backup_path);

        // Create legacy pairing file
        let legacy_content = r#"{"pairToken": "migrated_token_1234567890abcdef"}"#;
        fs::write(&legacy_path, legacy_content).unwrap();

        // 1. Initial migration
        let mgr = ConfigManager::load_or_migrate(&cfg_path, &legacy_path);
        assert_eq!(mgr.get_pair_token(), "migrated_token_1234567890abcdef");
        assert!(cfg_path.exists());
        assert!(backup_path.exists());
        // Verify recent_devices is strictly empty on migration (no implicit trust conversion)
        assert!(mgr.get_config().recent_devices.is_empty());

        // 2. Subsequent load must load from config.json
        let mgr2 = ConfigManager::load_or_migrate(&cfg_path, &legacy_path);
        assert_eq!(mgr2.get_pair_token(), "migrated_token_1234567890abcdef");

        // Clean up
        let _ = fs::remove_file(&cfg_path);
        let _ = fs::remove_file(&legacy_path);
        let _ = fs::remove_file(&backup_path);
    }
}
