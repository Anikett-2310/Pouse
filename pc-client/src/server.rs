use futures_util::{FutureExt, SinkExt, StreamExt};
use std::net::SocketAddr;
use std::sync::OnceLock;
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};
use tokio::net::{TcpListener, TcpStream};
use tokio::sync::broadcast;
use tokio_tungstenite::tungstenite::handshake::server::{Request, Response};
use tokio_tungstenite::tungstenite::Message;

use crate::input_owner::{InputOwner, TransportType};
use crate::pairing::redact_token;
use crate::protocol::PouseEvent;
use crate::remote_screen::host::{InputPermission, RemoteScreenHost, ResumeResult, StartResult};

const FRESHNESS_THRESHOLD_MS: u64 = 100;

static VIDEO_BROADCAST: OnceLock<broadcast::Sender<Vec<u8>>> = OnceLock::new();

pub fn get_video_broadcaster() -> &'static broadcast::Sender<Vec<u8>> {
    VIDEO_BROADCAST.get_or_init(|| {
        let (tx, _rx) = broadcast::channel(2); // Bounded capacity = 2 for latest-frame low-latency delivery
        tx
    })
}

pub fn extract_query_param(query: &str, key: &str) -> Option<String> {
    for pair in query.split('&') {
        let mut parts = pair.splitn(2, '=');
        if let (Some(k), Some(v)) = (parts.next(), parts.next()) {
            if k == key {
                return Some(v.to_string());
            }
        }
    }
    None
}

pub async fn run_server(port: u16) -> Result<(), Box<dyn std::error::Error>> {
    let addr = format!("0.0.0.0:{}", port);
    let listener = TcpListener::bind(&addr).await?;

    crate::pairing::print_pairing_info(port, false);

    while let Ok((stream, peer_addr)) = listener.accept().await {
        println!("New connection attempt from: {}", peer_addr);
        tokio::spawn(async move {
            if let Err(e) = handle_connection(stream, peer_addr).await {
                // A TCP reset (wsarecv/ECONNABORTED) is a routine abrupt disconnect —
                // treat it as informational rather than an error.
                println!("[WS] Connection from {} ended: {}", peer_addr, e);
            } else {
                println!("[WS] Connection closed cleanly: {}", peer_addr);
            }
        });
    }

    Ok(())
}

async fn handle_connection(stream: TcpStream, peer_addr: SocketAddr) -> Result<(), Box<dyn std::error::Error>> {
    stream.set_nodelay(true)?;

    let mut request_path = String::new();
    let mut request_query: Option<String> = None;

    let callback = |req: &Request, resp: Response| {
        request_path = req.uri().path().to_string();
        request_query = req.uri().query().map(|q| q.to_string());
        Ok(resp)
    };

    let ws_stream = tokio_tungstenite::accept_hdr_async(stream, callback).await?;
    println!("WebSocket handshake completed with {} on path '{}'", peer_addr, request_path);

    if request_path == "/screen" {
        let token = request_query.as_deref().and_then(|q| extract_query_param(q, "token"));
        handle_video_connection(ws_stream, peer_addr, token).await
    } else {
        handle_input_connection(ws_stream, peer_addr).await
    }
}

async fn handle_video_connection(
    ws_stream: tokio_tungstenite::WebSocketStream<TcpStream>,
    peer_addr: SocketAddr,
    token: Option<String>,
) -> Result<(), Box<dyn std::error::Error>> {
    let video_token = match token {
        Some(t) => t,
        None => {
            println!("[VIDEO WEBSOCKET] Rejected connection from {}: missing token parameter", peer_addr);
            return Ok(());
        }
    };

    let host = RemoteScreenHost::global();
    let is_valid = {
        let host_guard = host.lock().unwrap();
        host_guard.validate_video_token(&video_token)
    };

    if !is_valid {
        println!(
            "[VIDEO WEBSOCKET] Rejected connection from {}: invalid token {}",
            peer_addr,
            redact_token(&video_token)
        );
        return Ok(());
    }

    println!(
        "[VIDEO WEBSOCKET] Client connected to /screen: {} with token {}",
        peer_addr,
        redact_token(&video_token)
    );

    // Force an immediate IDR keyframe for newly connected video client
    {
        let host_guard = host.lock().unwrap();
        host_guard.force_keyframe();
    }

    let (mut ws_sender, mut ws_receiver) = ws_stream.split();
    let mut video_rx = get_video_broadcaster().subscribe();

    let mut drain_task = tokio::spawn(async move {
        while let Some(msg_res) = ws_receiver.next().await {
            match msg_res {
                Ok(Message::Close(_)) => break,
                Err(_) => break,
                _ => {}
            }
        }
    });

    loop {
        tokio::select! {
            res = video_rx.recv() => {
                match res {
                    Ok(access_unit) => {
                        let msg = Message::Binary(access_unit.into());
                        if let Err(e) = ws_sender.send(msg).await {
                            println!("[VIDEO WS] Peer {} disconnected during stream: {}", peer_addr, e);
                            break;
                        }
                    }
                    Err(broadcast::error::RecvError::Lagged(skipped)) => {
                        println!("[VIDEO WEBSOCKET] Lagged by {} frames for {} - dropped stale backlog to maintain low latency", skipped, peer_addr);
                    }
                    Err(broadcast::error::RecvError::Closed) => break,
                }
            }
            _ = &mut drain_task => {
                break;
            }
        }
    }

    println!("[VIDEO WEBSOCKET] Client disconnected from /screen: {}", peer_addr);
    Ok(())
}

async fn handle_input_connection(
    ws_stream: tokio_tungstenite::WebSocketStream<TcpStream>,
    peer_addr: SocketAddr,
) -> Result<(), Box<dyn std::error::Error>> {
    let (mut ws_sender, mut ws_receiver) = ws_stream.split();
    let input_owner = InputOwner::global();
    input_owner.acquire(TransportType::Wifi);
    let host = RemoteScreenHost::global();

    let mut min_clock_offset: Option<i64> = None;
    let mut consecutive_stale_count: u32 = 0;
    let mut fresh_move_count: u64 = 0;
    let mut stale_move_count: u64 = 0;
    let mut coalesced_move_count: u64 = 0;
    let mut move_received_count: u64 = 0;
    let mut move_applied_count: u64 = 0;
    let mut last_diag_log = Instant::now();

    while let Some(msg_result) = ws_receiver.next().await {
        let t_recv_mono = Instant::now();
        match msg_result {
            Ok(Message::Text(text)) => {
                match PouseEvent::parse(&text) {
                    Ok(event) => {
                        // Check input permissions and session timeout
                        let input_perm = {
                            let mut host_guard = host.lock().unwrap();
                            let _ = host_guard.check_reconnect_timeout();
                            host_guard.can_process_input(&peer_addr)
                        };

                        // Control protocol events bypass input locking
                        match &event {
                            PouseEvent::Auth { token } => {
                                let (is_ok, resp) = {
                                    let mut host_guard = host.lock().unwrap();
                                    if host_guard.handle_auth(peer_addr, token) {
                                        (true, serde_json::json!({ "event": "AUTH_OK" }).to_string())
                                    } else {
                                        (false, serde_json::json!({
                                            "event": "ERROR",
                                            "message": "Invalid pairToken"
                                        }).to_string())
                                    }
                                };
                                let _ = ws_sender.send(Message::Text(resp.into())).await;
                                if !is_ok {
                                    println!("[SECURITY] Rejecting and disconnecting peer {} due to invalid pairToken", peer_addr);
                                    break;
                                }
                                continue;
                            }
                            PouseEvent::StartScreen => {
                                let resp = {
                                    let mut host_guard = host.lock().unwrap();
                                    let res = host_guard.handle_start_screen(peer_addr, 1920, 1080);
                                    match res {
                                        StartResult::Ok { session_token, width, height } |
                                        StartResult::AlreadyStarted { session_token, width, height } => {
                                            serde_json::json!({
                                                "event": "SCREEN_METADATA",
                                                "screenSessionToken": session_token,
                                                "width": width,
                                                "height": height
                                            }).to_string()
                                        }
                                        StartResult::Busy => {
                                            serde_json::json!({
                                                "event": "SESSION_BUSY",
                                                "message": "Another Remote Screen session is active"
                                            }).to_string()
                                        }
                                        StartResult::NotAuthenticated => {
                                            serde_json::json!({
                                                "event": "ERROR",
                                                "message": "Not authenticated"
                                            }).to_string()
                                        }
                                        StartResult::Error(err) => {
                                            serde_json::json!({
                                                "event": "ERROR",
                                                "message": err
                                            }).to_string()
                                        }
                                    }
                                };
                                let _ = ws_sender.send(Message::Text(resp.into())).await;
                                continue;
                            }
                            PouseEvent::ResumeScreen { session_token } => {
                                let resp = {
                                    let mut host_guard = host.lock().unwrap();
                                    let res = host_guard.handle_resume_screen(peer_addr, session_token);
                                    match res {
                                        ResumeResult::Ok { session_token } => {
                                            serde_json::json!({
                                                "event": "RESUME_OK",
                                                "screenSessionToken": session_token
                                            }).to_string()
                                        }
                                        ResumeResult::Expired => {
                                            serde_json::json!({
                                                "event": "SESSION_EXPIRED",
                                                "message": "Session token invalid or expired"
                                            }).to_string()
                                        }
                                        ResumeResult::NotAuthenticated => {
                                            serde_json::json!({
                                                "event": "ERROR",
                                                "message": "Not authenticated"
                                            }).to_string()
                                        }
                                    }
                                };
                                let _ = ws_sender.send(Message::Text(resp.into())).await;
                                continue;
                            }
                            PouseEvent::StopScreen => {
                                {
                                    let mut host_guard = host.lock().unwrap();
                                    host_guard.handle_stop_screen(peer_addr);
                                }
                                input_owner.release_all(TransportType::Wifi);
                                let resp = serde_json::json!({ "event": "STOP_SCREEN_OK" }).to_string();
                                let _ = ws_sender.send(Message::Text(resp.into())).await;
                                continue;
                            }
                            PouseEvent::RequestKeyframe => {
                                let host_guard = host.lock().unwrap();
                                host_guard.force_keyframe();
                                continue;
                            }
                            PouseEvent::Ping => {
                                let pong = serde_json::json!({ "event": "PONG" }).to_string();
                                let _ = ws_sender.send(Message::Text(pong.into())).await;
                                continue;
                            }
                            _ => {}
                        }

                        // Input event evaluation
                        if input_perm == InputPermission::Blocked {
                            println!("[INPUT BLOCKED] Peer {} blocked because Remote Screen is active by another client", peer_addr);
                            let blocked_msg = serde_json::json!({
                                "event": "INPUT_BLOCKED",
                                "message": "Remote Screen session active by another client"
                            }).to_string();
                            let _ = ws_sender.send(Message::Text(blocked_msg.into())).await;
                            continue;
                        }

                        // Process allowed input event
                        if let PouseEvent::Move { dx, dy, t } = event {
                            move_received_count += 1;
                            let now_ms = SystemTime::now()
                                .duration_since(UNIX_EPOCH)
                                .unwrap_or_default()
                                .as_millis() as u64;

                            let mut age_ms: u64 = 0;
                            if let Some(t_send) = t {
                                let raw_diff = (now_ms as i64) - (t_send as i64);
                                match min_clock_offset {
                                    None => min_clock_offset = Some(raw_diff),
                                    Some(curr_min) => {
                                        if raw_diff < curr_min {
                                            min_clock_offset = Some(raw_diff);
                                        }
                                    }
                                }
                                let off = min_clock_offset.unwrap_or(raw_diff);
                                age_ms = (raw_diff - off).max(0) as u64;
                            }

                            if age_ms > FRESHNESS_THRESHOLD_MS {
                                consecutive_stale_count += 1;
                                if consecutive_stale_count >= 3 {
                                    if let Some(t_send) = t {
                                        let raw_diff = (now_ms as i64) - (t_send as i64);
                                        min_clock_offset = Some(raw_diff);
                                        age_ms = 0;
                                        consecutive_stale_count = 0;
                                        println!("[MOVE PIPELINE] Clock offset auto-resynced to {}ms", raw_diff);
                                    }
                                } else {
                                    stale_move_count += 1;
                                    println!(
                                        "[MOVE PIPELINE] DROPPED STALE MOVE: age={}ms (>{}ms) | t_recv_mono={:?} | fresh={} | stale={} | coalesced={}",
                                        age_ms, FRESHNESS_THRESHOLD_MS, t_recv_mono, fresh_move_count, stale_move_count, coalesced_move_count
                                    );
                                    continue;
                                }
                            } else {
                                consecutive_stale_count = 0;
                            }

                            fresh_move_count += 1;
                            let mut accum_dx = dx;
                            let mut accum_dy = dy;
                            let mut batch_queue_len = 0;

                            while let Some(Some(Ok(Message::Text(next_text)))) = ws_receiver.next().now_or_never() {
                                batch_queue_len += 1;
                                match PouseEvent::parse(&next_text) {
                                    Ok(PouseEvent::Move { dx: d2_x, dy: d2_y, t: t2 }) => {
                                        move_received_count += 1;
                                        let next_now_ms = SystemTime::now()
                                            .duration_since(UNIX_EPOCH)
                                            .unwrap_or_default()
                                            .as_millis() as u64;
                                        let mut age2: u64 = 0;
                                        if let Some(t2_send) = t2 {
                                            let raw2 = (next_now_ms as i64) - (t2_send as i64);
                                            if let Some(curr) = min_clock_offset {
                                                if raw2 < curr {
                                                    min_clock_offset = Some(raw2);
                                                }
                                            }
                                            let off2 = min_clock_offset.unwrap_or(raw2);
                                            age2 = (raw2 - off2).max(0) as u64;
                                        }

                                        if age2 <= FRESHNESS_THRESHOLD_MS {
                                            accum_dx += d2_x;
                                            accum_dy += d2_y;
                                            fresh_move_count += 1;
                                            coalesced_move_count += 1;
                                        } else {
                                            stale_move_count += 1;
                                        }
                                    }
                                    Ok(other) => {
                                        if accum_dx != 0.0 || accum_dy != 0.0 {
                                            move_applied_count += 1;
                                            input_owner.handle_event(TransportType::Wifi, Some(&peer_addr), PouseEvent::Move { dx: accum_dx, dy: accum_dy, t: None });
                                            accum_dx = 0.0;
                                            accum_dy = 0.0;
                                        }
                                        if matches!(other, PouseEvent::Ping) {
                                            let pong = serde_json::json!({ "event": "PONG" }).to_string();
                                            let _ = ws_sender.send(Message::Text(pong.into())).await;
                                        } else {
                                            if !matches!(other, PouseEvent::Move { .. }) {
                                                println!("[{}] Processing event: {:?}", peer_addr, other);
                                            }
                                            input_owner.handle_event(TransportType::Wifi, Some(&peer_addr), other);
                                        }
                                        break;
                                    }
                                    Err(err) => {
                                        eprintln!("Failed to parse JSON event from {}: {} (raw: {})", peer_addr, err, next_text);
                                        break;
                                    }
                                }
                            }

                            if accum_dx != 0.0 || accum_dy != 0.0 {
                                move_applied_count += 1;
                                input_owner.handle_event(TransportType::Wifi, Some(&peer_addr), PouseEvent::Move { dx: accum_dx, dy: accum_dy, t: None });
                            }

                            if last_diag_log.elapsed().as_secs() >= 1 || batch_queue_len > 2 {
                                println!(
                                    "[MOVE PIPELINE] recv={} | applied={} | age={}ms | queue={} | fresh={} | stale={} | coalesced={}",
                                    move_received_count, move_applied_count, age_ms, batch_queue_len, fresh_move_count, stale_move_count, coalesced_move_count
                                );
                                last_diag_log = Instant::now();
                            }
                        } else {
                            println!("[{}] Processing event: {:?}", peer_addr, event);
                            input_owner.handle_event(TransportType::Wifi, Some(&peer_addr), event);
                        }
                    }
                    Err(err) => {
                        eprintln!("Failed to parse JSON event from {}: {} (raw: {})", peer_addr, err, text);
                    }
                }
            }
            Ok(Message::Ping(payload)) => {
                let _ = ws_sender.send(Message::Pong(payload)).await;
            }
            Ok(Message::Close(_)) => {
                break;
            }
            Err(e) => {
                // Abrupt disconnects (TCP reset, connection aborted) are normal when
                // the phone app is backgrounded or the network drops. Log at info level.
                println!("[WS] Peer {} disconnected abruptly: {}", peer_addr, e);
                break;
            }
            _ => {}
        }
    }

    input_owner.release(TransportType::Wifi);

    let entered_grace_period = {
        let mut host_guard = host.lock().unwrap();
        host_guard.handle_peer_disconnect(peer_addr)
    };

    if entered_grace_period {
        tokio::spawn(async move {
            tokio::time::sleep(Duration::from_secs(15)).await;
            let host_instance = RemoteScreenHost::global();
            let mut host_guard = host_instance.lock().unwrap();
            host_guard.check_reconnect_timeout();
        });
    }

    Ok(())
}
