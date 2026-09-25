use futures_util::{FutureExt, SinkExt, StreamExt};
use std::net::SocketAddr;
use std::time::{Instant, SystemTime, UNIX_EPOCH};
use tokio::net::{TcpListener, TcpStream};
use tokio_tungstenite::tungstenite::Message;
use crate::input::InputHandler;
use crate::protocol::PouseEvent;

const FRESHNESS_THRESHOLD_MS: u64 = 100;

pub async fn run_server(port: u16) -> Result<(), Box<dyn std::error::Error>> {
    let addr = format!("0.0.0.0:{}", port);
    let listener = TcpListener::bind(&addr).await?;

    crate::pairing::print_pairing_info(port);

    while let Ok((stream, peer_addr)) = listener.accept().await {
        println!("New connection from: {}", peer_addr);
        tokio::spawn(async move {
            if let Err(e) = handle_connection(stream, peer_addr).await {
                eprintln!("Connection error from {}: {}", peer_addr, e);
            }
            println!("Connection closed: {}", peer_addr);
        });
    }

    Ok(())
}

async fn handle_connection(stream: TcpStream, peer_addr: SocketAddr) -> Result<(), Box<dyn std::error::Error>> {
    stream.set_nodelay(true)?;
    let ws_stream = tokio_tungstenite::accept_async(stream).await?;
    println!("WebSocket handshake completed with {}", peer_addr);

    let (mut ws_sender, mut ws_receiver) = ws_stream.split();
    let mut input_handler = InputHandler::new().map_err(|e| std::io::Error::new(std::io::ErrorKind::Other, e))?;
    
    // Latency & queue age diagnostic state
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
                        if matches!(event, PouseEvent::Ping) {
                            let pong = serde_json::json!({ "event": "PONG" }).to_string();
                            let _ = ws_sender.send(Message::Text(pong.into())).await;
                        } else if let PouseEvent::Move { dx, dy, t } = event {
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

                            // Freshness Policy with Auto-Resync Safety Net:
                            // If clock drift or anomaly causes 3 consecutive MOVE events to evaluate as stale (>100ms),
                            // automatically re-calibrate clock offset to current raw_diff immediately.
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

                            // Latest-First Coalescing: Consume pending MOVE events from stream buffer
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
                                        // Flush accumulated fresh MOVE first before handling non-move event
                                        if accum_dx != 0.0 || accum_dy != 0.0 {
                                            move_applied_count += 1;
                                            input_handler.handle_event(PouseEvent::Move { dx: accum_dx, dy: accum_dy, t: None });
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
                                            input_handler.handle_event(other);
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
                                input_handler.handle_event(PouseEvent::Move { dx: accum_dx, dy: accum_dy, t: None });
                            }

                            // Throttled Pipeline Diagnostics
                            if last_diag_log.elapsed().as_secs() >= 1 || batch_queue_len > 2 {
                                println!(
                                    "[MOVE PIPELINE] recv={} | applied={} | age={}ms | queue={} | fresh={} | stale={} | coalesced={}",
                                    move_received_count, move_applied_count, age_ms, batch_queue_len, fresh_move_count, stale_move_count, coalesced_move_count
                                );
                                last_diag_log = Instant::now();
                            }
                        } else {
                            println!("[{}] Processing event: {:?}", peer_addr, event);
                            input_handler.handle_event(event);
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
                eprintln!("WebSocket error: {}", e);
                break;
            }
            _ => {}
        }
    }

    input_handler.release_all();
    Ok(())
}

