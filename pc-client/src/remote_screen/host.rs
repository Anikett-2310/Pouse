use std::collections::HashSet;
use std::net::SocketAddr;
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::{Arc, Mutex, OnceLock};
use std::thread::{self, JoinHandle};
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};

static LAST_WGC_FRAME_TIME_MS: AtomicU64 = AtomicU64::new(0);
static LAST_ENCODED_FRAME_TIME_MS: AtomicU64 = AtomicU64::new(0);
static LAST_WS_SEND_TIME_MS: AtomicU64 = AtomicU64::new(0);
static KEYFRAME_REQUEST_COUNTER: AtomicU64 = AtomicU64::new(0);
static LAST_REQUESTED_KEYFRAME_ID: AtomicU64 = AtomicU64::new(0);

use crate::pairing::{get_or_create_pair_token, redact_token};
use crate::remote_screen::capture::WgcCapturer;
use crate::remote_screen::encoder::{EncoderResponse, MediaFoundationEncoder};
use crate::server::get_video_broadcaster;

pub enum StartResult {
    Ok {
        session_token: String,
        width: u32,
        height: u32,
    },
    AlreadyStarted {
        session_token: String,
        width: u32,
        height: u32,
    },
    Busy,
    NotAuthenticated,
    Error(String),
}

pub enum ResumeResult {
    Ok { session_token: String },
    Expired,
    NotAuthenticated,
}

#[derive(Debug, PartialEq, Eq)]
pub enum InputPermission {
    Allowed,
    Blocked,
}

pub struct RemoteScreenHost {
    pair_token: String,
    screen_session_token: Option<String>,
    owning_peer: Option<SocketAddr>,
    authenticated_peers: HashSet<SocketAddr>,
    reconnect_deadline: Option<Instant>,
    width: u32,
    height: u32,
    encoder: Option<Arc<MediaFoundationEncoder>>,
    capture_stop_signal: Option<Arc<AtomicBool>>,
    capture_thread: Option<JoinHandle<()>>,
}

static HOST_INSTANCE: OnceLock<Arc<Mutex<RemoteScreenHost>>> = OnceLock::new();

impl RemoteScreenHost {
    pub fn global() -> Arc<Mutex<Self>> {
        HOST_INSTANCE
            .get_or_init(|| {
                let pair_token = get_or_create_pair_token(false);
                println!(
                    "[REMOTE_SCREEN_HOST] Initialized with pairToken: {}",
                    redact_token(&pair_token)
                );
                Arc::new(Mutex::new(RemoteScreenHost {
                    pair_token,
                    screen_session_token: None,
                    owning_peer: None,
                    authenticated_peers: HashSet::new(),
                    reconnect_deadline: None,
                    width: 1920,
                    height: 1080,
                    encoder: None,
                    capture_stop_signal: None,
                    capture_thread: None,
                }))
            })
            .clone()
    }

    pub fn set_pair_token(&mut self, token: String) {
        self.pair_token = token;
    }

    pub fn pair_token(&self) -> &str {
        &self.pair_token
    }

    pub fn screen_session_token(&self) -> Option<&str> {
        self.screen_session_token.as_deref()
    }

    pub fn handle_auth(&mut self, peer: SocketAddr, token: &str) -> bool {
        if token == self.pair_token {
            self.authenticated_peers.insert(peer);
            println!(
                "[REMOTE_SCREEN_HOST] Peer {} authenticated successfully",
                peer
            );
            true
        } else {
            println!(
                "[REMOTE_SCREEN_HOST] Peer {} auth failed with token: {} (full: {})",
                peer,
                redact_token(token),
                token
            );
            false
        }
    }

    pub fn is_authenticated(&self, peer: &SocketAddr) -> bool {
        self.authenticated_peers.contains(peer)
    }

    pub fn handle_start_screen(
        &mut self,
        peer: SocketAddr,
        req_width: u32,
        req_height: u32,
    ) -> StartResult {
        if !self.is_authenticated(&peer) {
            return StartResult::NotAuthenticated;
        }

        // Check if session is already active or in reconnect window
        if let Some(token) = &self.screen_session_token {
            if self.owning_peer == Some(peer) {
                return StartResult::AlreadyStarted {
                    session_token: token.clone(),
                    width: self.width,
                    height: self.height,
                };
            }
            println!(
                "[REMOTE_SCREEN_HOST] Rejecting START_SCREEN from {}: session active by another client",
                peer
            );
            return StartResult::Busy;
        }

        let session_token = crate::pairing::generate_random_token();
        let w = if req_width == 0 { 1920 } else { req_width };
        let h = if req_height == 0 { 1080 } else { req_height };

        println!(
            "[REMOTE_SCREEN_HOST] Starting session for {} ({}x{}), sessionToken: {}",
            peer,
            w,
            h,
            redact_token(&session_token)
        );

        // Start capture and encoding pipeline
        let stop_signal = Arc::new(AtomicBool::new(false));
        let stop_signal_clone = stop_signal.clone();

        let capturer = match WgcCapturer::new(w, h) {
            Ok(c) => c,
            Err(e) => {
                let err_msg = format!("Capture init failed: {:?}", e);
                eprintln!("[REMOTE_SCREEN_HOST] {}", err_msg);
                return StartResult::Error(err_msg);
            }
        };

        let encoder = match MediaFoundationEncoder::start(
            capturer.d3d_device.clone(),
            capturer.d3d_context.clone(),
            w,
            h,
            false,
        ) {
            Ok(e) => Arc::new(e),
            Err(e) => {
                let err_msg = format!("Encoder init failed: {:?}", e);
                eprintln!("[REMOTE_SCREEN_HOST] {}", err_msg);
                return StartResult::Error(err_msg);
            }
        };

        let encoder_clone = encoder.clone();
        let broadcaster = get_video_broadcaster().clone();

        let capture_handle = thread::spawn(move || {
            let frame_interval = Duration::from_micros(33_333);
            let mut next_tick = Instant::now();
            let mut tick_count: u64 = 0;
            let mut last_tex = None;

            while !stop_signal_clone.load(Ordering::Relaxed) {
                let now = Instant::now();
                if now < next_tick {
                    thread::sleep(next_tick - now);
                }
                next_tick += frame_interval;
                tick_count += 1;

                let fresh_tex = capturer.get_next_texture().ok().flatten();
                let now_ms = SystemTime::now()
                    .duration_since(UNIX_EPOCH)
                    .unwrap_or_default()
                    .as_millis() as u64;

                let tex = if let Some(t) = fresh_tex {
                    LAST_WGC_FRAME_TIME_MS.store(now_ms, Ordering::Relaxed);
                    last_tex = Some(t.clone());
                    Some(t)
                } else {
                    last_tex.clone()
                };

                if let Some(t) = tex {
                    let _ = encoder_clone.encode_frame(t, 0, tick_count);
                }

                while let Some(resp) = encoder_clone.try_recv_response() {
                    if let EncoderResponse::EncodedSample { data, metrics } = resp {
                        let enc_now_ms = SystemTime::now()
                            .duration_since(UNIX_EPOCH)
                            .unwrap_or_default()
                            .as_millis() as u64;
                        LAST_ENCODED_FRAME_TIME_MS.store(enc_now_ms, Ordering::Relaxed);
                        if metrics.is_keyframe {
                            let pending_req = LAST_REQUESTED_KEYFRAME_ID.swap(0, Ordering::Relaxed);
                            let req_str = if pending_req > 0 {
                                format!(" #{}", pending_req)
                            } else {
                                String::new()
                            };
                            println!("[DIAGNOSTIC] IDR_ENCODED{}", req_str);
                            if broadcaster.send(data).is_ok() {
                                LAST_WS_SEND_TIME_MS.store(enc_now_ms, Ordering::Relaxed);
                                println!("[DIAGNOSTIC] IDR_SENT{}", req_str);
                            }
                        } else if broadcaster.send(data).is_ok() {
                            LAST_WS_SEND_TIME_MS.store(enc_now_ms, Ordering::Relaxed);
                        }
                    }
                }
            }

            let _ = encoder_clone.force_keyframe();
            println!("[REMOTE_SCREEN_HOST] Background capture & encoder thread stopped.");
        });

        self.screen_session_token = Some(session_token.clone());
        self.owning_peer = Some(peer);
        self.reconnect_deadline = None;
        self.width = w;
        self.height = h;
        self.encoder = Some(encoder);
        self.capture_stop_signal = Some(stop_signal);
        self.capture_thread = Some(capture_handle);

        StartResult::Ok {
            session_token,
            width: w,
            height: h,
        }
    }

    pub fn handle_resume_screen(
        &mut self,
        peer: SocketAddr,
        token: &str,
    ) -> ResumeResult {
        if !self.is_authenticated(&peer) {
            return ResumeResult::NotAuthenticated;
        }

        if let Some(active_token) = &self.screen_session_token {
            if active_token == token {
                self.owning_peer = Some(peer);
                self.reconnect_deadline = None;
                println!(
                    "[REMOTE_SCREEN_HOST] Re-associated control socket for {} with session: {}",
                    peer,
                    redact_token(token)
                );
                return ResumeResult::Ok {
                    session_token: active_token.clone(),
                };
            }
        }

        println!(
            "[REMOTE_SCREEN_HOST] RESUME_SCREEN failed for {}: invalid/expired token {}",
            peer,
            redact_token(token)
        );
        ResumeResult::Expired
    }

    pub fn handle_stop_screen(&mut self, peer: SocketAddr) -> bool {
        println!(
            "[REMOTE_SCREEN_HOST] STOP_SCREEN requested by peer {}",
            peer
        );
        self.teardown_session();
        true
    }

    pub fn handle_peer_disconnect(&mut self, peer: SocketAddr) -> bool {
        self.authenticated_peers.remove(&peer);

        if self.owning_peer == Some(peer) {
            self.owning_peer = None;
            self.reconnect_deadline = Some(Instant::now() + Duration::from_secs(15));
            if let Some(token) = &self.screen_session_token {
                println!(
                    "[REMOTE_SCREEN_HOST] Owning peer {} disconnected. Entered 15-second grace period for session {}",
                    peer,
                    redact_token(token)
                );
            }
            true
        } else {
            false
        }
    }

    pub fn check_reconnect_timeout(&mut self) -> bool {
        if self.screen_session_token.is_some() && self.owning_peer.is_none() {
            if let Some(deadline) = self.reconnect_deadline {
                if Instant::now() >= deadline {
                    println!("[REMOTE_SCREEN_HOST] Reconnect grace period (15s) expired. Tearing down session.");
                    self.teardown_session();
                    return true;
                }
            }
        }
        false
    }

    pub fn validate_video_token(&self, token: &str) -> bool {
        if let Some(active_token) = &self.screen_session_token {
            if active_token == token {
                return true;
            }
        }
        false
    }

    pub fn force_keyframe(&self) {
        if let Some(encoder) = &self.encoder {
            let req_id = KEYFRAME_REQUEST_COUNTER.fetch_add(1, Ordering::SeqCst) + 1;
            LAST_REQUESTED_KEYFRAME_ID.store(req_id, Ordering::Relaxed);
            let _ = encoder.force_keyframe();
            let wgc_t = LAST_WGC_FRAME_TIME_MS.load(Ordering::Relaxed);
            let enc_t = LAST_ENCODED_FRAME_TIME_MS.load(Ordering::Relaxed);
            let ws_t = LAST_WS_SEND_TIME_MS.load(Ordering::Relaxed);
            let now = SystemTime::now()
                .duration_since(UNIX_EPOCH)
                .unwrap_or_default()
                .as_millis() as u64;
            println!(
                "[DIAGNOSTIC] KEYFRAME_REQUEST #{}\n[DIAGNOSTIC] [KEYFRAME_REQUESTED] lastWgcMs={} lastEncMs={} lastWsSendMs={} timestamp={}",
                req_id,
                if wgc_t == 0 { 0 } else { now.saturating_sub(wgc_t) },
                if enc_t == 0 { 0 } else { now.saturating_sub(enc_t) },
                if ws_t == 0 { 0 } else { now.saturating_sub(ws_t) },
                now
            );
        }
    }

    pub fn can_process_input(&self, peer: &SocketAddr) -> InputPermission {
        if !self.is_authenticated(peer) {
            return InputPermission::Blocked;
        }
        if self.screen_session_token.is_some() {
            if self.owning_peer == Some(*peer) {
                InputPermission::Allowed
            } else {
                InputPermission::Blocked
            }
        } else {
            InputPermission::Allowed
        }
    }

    pub fn teardown_session(&mut self) {
        if let Some(token) = &self.screen_session_token {
            println!(
                "[REMOTE_SCREEN_HOST] Tearing down Remote Screen session {}",
                redact_token(token)
            );
        }

        if let Some(stop_signal) = self.capture_stop_signal.take() {
            stop_signal.store(true, Ordering::Relaxed);
        }

        if let Some(handle) = self.capture_thread.take() {
            let _ = handle.join();
        }

        self.encoder = None;
        self.screen_session_token = None;
        self.owning_peer = None;
        self.reconnect_deadline = None;
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::net::SocketAddr;

    #[test]
    fn test_post_remote_screen_input_ownership_reversion() {
        let pair_token = "test_pair_token_12345678".to_string();
        let mut host = RemoteScreenHost {
            pair_token,
            screen_session_token: None,
            owning_peer: None,
            authenticated_peers: HashSet::new(),
            reconnect_deadline: None,
            width: 1920,
            height: 1080,
            encoder: None,
            capture_stop_signal: None,
            capture_thread: None,
        };

        let peer_a: SocketAddr = "192.168.1.10:1000".parse().unwrap();
        let peer_b: SocketAddr = "192.168.1.20:2000".parse().unwrap();

        // 1. Authenticate both peers
        assert!(host.handle_auth(peer_a, "test_pair_token_12345678"));
        assert!(host.handle_auth(peer_b, "test_pair_token_12345678"));

        // 2. Peer A starts Remote Screen session
        host.screen_session_token = Some("session_abc_123".to_string());
        host.owning_peer = Some(peer_a);

        // 3. Verify Peer A is allowed and Peer B is blocked
        assert_eq!(host.can_process_input(&peer_a), InputPermission::Allowed);
        assert_eq!(host.can_process_input(&peer_b), InputPermission::Blocked);

        // 4. Peer B attempts start -> Busy
        match host.handle_start_screen(peer_b, 1920, 1080) {
            StartResult::Busy => {}
            _ => panic!("Expected StartResult::Busy for Peer B"),
        }

        // 5. Peer A stops Remote Screen
        assert!(host.handle_stop_screen(peer_a));

        // 6. Verify input ownership reverted: BOTH Peer A and Peer B are allowed normal input
        assert_eq!(host.can_process_input(&peer_a), InputPermission::Allowed);
        assert_eq!(host.can_process_input(&peer_b), InputPermission::Allowed);
        assert!(host.screen_session_token().is_none());
    }

    #[test]
    fn test_unauthenticated_peer_input_blocked() {
        let pair_token = "test_pair_token_12345678".to_string();
        let mut host = RemoteScreenHost {
            pair_token,
            screen_session_token: None,
            owning_peer: None,
            authenticated_peers: HashSet::new(),
            reconnect_deadline: None,
            width: 1920,
            height: 1080,
            encoder: None,
            capture_stop_signal: None,
            capture_thread: None,
        };

        let peer_auth: SocketAddr = "192.168.1.10:1000".parse().unwrap();
        let peer_unauth: SocketAddr = "192.168.1.20:2000".parse().unwrap();

        assert!(host.handle_auth(peer_auth, "test_pair_token_12345678"));
        assert!(!host.handle_auth(peer_unauth, "wrong_token"));

        assert_eq!(host.can_process_input(&peer_auth), InputPermission::Allowed);
        assert_eq!(host.can_process_input(&peer_unauth), InputPermission::Blocked);
    }

    #[test]
    fn test_single_keyframe_request_flow() {
        let pair_token = "test_pair_token_12345678".to_string();
        let host = RemoteScreenHost {
            pair_token,
            screen_session_token: None,
            owning_peer: None,
            authenticated_peers: HashSet::new(),
            reconnect_deadline: None,
            width: 1920,
            height: 1080,
            encoder: None,
            capture_stop_signal: None,
            capture_thread: None,
        };

        // Calling force_keyframe when encoder is None does not panic or loop
        host.force_keyframe();
        assert!(host.screen_session_token().is_none());
    }
}
