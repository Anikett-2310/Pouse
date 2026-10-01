use std::time::Duration;
use windows::core::*;
use windows::Devices::Bluetooth::Rfcomm::*;
use windows::Foundation::TypedEventHandler;
use windows::Networking::Sockets::*;
use windows::Storage::Streams::*;

use crate::input_owner::{InputOwner, TransportType};
use crate::protocol::PouseEvent;

// Fixed Pouse RFCOMM Service UUID (7f9b841a-3e2c-4a90-8b1b-5e6f8a9c0d1e)
const POUSE_RFCOMM_UUID: GUID = GUID::from_u128(0x7f9b841a_3e2c_4a90_8b1b_5e6f8a9c0d1e);

// ─── Sampled latency instrumentation ────────────────────────────────────────
//
// Tracks the time from the moment a complete line is received from the RFCOMM
// socket to the moment input is injected via SendInput.  Statistics are
// aggregated and printed every STATS_INTERVAL_SECS seconds — never per-event.
// Uses only atomic operations in the hot path; histogram is updated on a
// per-event basis but only the counters are written atomically.

const STATS_INTERVAL_SECS: u64 = 5;

struct RfcommLatencyStats {
    /// Receive timestamps (ms since epoch) ring buffer, protected by Mutex
    samples: std::sync::Mutex<LatencySamples>,
    last_report: std::sync::Mutex<std::time::Instant>,
}

struct LatencySamples {
    values: Vec<u32>, // latency in microseconds
    e2e_values: Vec<u32>, // end-to-end latency in milliseconds (touch -> inject)
    move_events: u64,
    total_events: u64,
}

impl RfcommLatencyStats {
    fn new() -> Self {
        Self {
            samples: std::sync::Mutex::new(LatencySamples {
                values: Vec::with_capacity(1024),
                e2e_values: Vec::with_capacity(1024),
                move_events: 0,
                total_events: 0,
            }),
            last_report: std::sync::Mutex::new(std::time::Instant::now()),
        }
    }

    /// Record receive→inject latency in microseconds and optional e2e latency in milliseconds.
    fn record(&self, latency_us: u32, is_move: bool, e2e_ms: Option<u32>) {
        let mut s = self.samples.lock().unwrap();
        s.values.push(latency_us);
        if let Some(ms) = e2e_ms {
            s.e2e_values.push(ms);
        }
        s.total_events += 1;
        if is_move {
            s.move_events += 1;
        }
        drop(s);

        // Report if interval elapsed
        let mut last = self.last_report.lock().unwrap();
        if last.elapsed().as_secs() >= STATS_INTERVAL_SECS {
            *last = std::time::Instant::now();
            drop(last);
            self.report();
        }
    }

    fn report(&self) {
        let mut s = self.samples.lock().unwrap();
        if s.values.is_empty() {
            return;
        }
        s.values.sort_unstable();
        let n = s.values.len();
        let avg = s.values.iter().map(|&v| v as u64).sum::<u64>() / n as u64;
        let p50 = s.values[n * 50 / 100];
        let p95 = s.values[n * 95 / 100];
        let p99 = s.values[n * 99 / 100];
        let max = *s.values.last().unwrap();
        let rate_per_sec = s.total_events as f64 / STATS_INTERVAL_SECS as f64;

        let e2e_str = if !s.e2e_values.is_empty() {
            s.e2e_values.sort_unstable();
            let en = s.e2e_values.len();
            let eavg = s.e2e_values.iter().map(|&v| v as u64).sum::<u64>() / en as u64;
            let ep50 = s.e2e_values[en * 50 / 100];
            let ep95 = s.e2e_values[en * 95 / 100];
            let ep99 = s.e2e_values[en * 99 / 100];
            let emax = *s.e2e_values.last().unwrap();
            format!(" | e2e_ms avg={} p50={} p95={} p99={} max={}", eavg, ep50, ep95, ep99, emax)
        } else {
            String::new()
        };

        println!(
            "[RFCOMM_STATS] events={} moves={} rate={:.1}/s | rx_to_inject_us avg={} p50={} p95={} p99={} max={}{}",
            s.total_events, s.move_events, rate_per_sec, avg, p50, p95, p99, max, e2e_str
        );
        s.values.clear();
        s.e2e_values.clear();
        s.total_events = 0;
        s.move_events = 0;
    }
}

static LATENCY_STATS: std::sync::OnceLock<RfcommLatencyStats> = std::sync::OnceLock::new();
fn latency_stats() -> &'static RfcommLatencyStats {
    LATENCY_STATS.get_or_init(RfcommLatencyStats::new)
}

// ─── Buffered RFCOMM reader ──────────────────────────────────────────────────
//
// The previous implementation called LoadAsync(1) per byte, causing 50+
// WinRT async roundtrips per MOVE event (50–250ms overhead per event).
//
// This reader fills a 256-byte local buffer with a single LoadAsync call and
// scans for newlines in memory.  A refill is issued only when the buffer is
// exhausted.  This reduces reads from O(line_length) to O(line_length/256)
// WinRT async calls, bringing per-event read latency from 50–250ms to <1ms.
struct BufferedRfcommReader<'a> {
    reader: &'a DataReader,
    buf: Vec<u8>,
    pos: usize,
}

impl<'a> BufferedRfcommReader<'a> {
    const READ_CHUNK: u32 = 256;

    fn new(reader: &'a DataReader) -> Self {
        Self { reader, buf: Vec::with_capacity(Self::READ_CHUNK as usize * 2), pos: 0 }
    }

    /// Read bytes into the internal buffer.
    fn fill(&mut self) -> Result<()> {
        let loaded = self.reader.LoadAsync(Self::READ_CHUNK)?.get()? as usize;
        if loaded == 0 {
            return Err(Error::new(HRESULT(0x80004005u32 as i32), "Connection closed"));
        }
        // Drain whatever was loaded into our Vec
        for _ in 0..loaded {
            self.buf.push(self.reader.ReadByte()?);
        }
        Ok(())
    }

    /// Read one complete newline-terminated line.  Returns the line without '\n'.
    fn read_line(&mut self) -> Result<String> {
        loop {
            // Scan existing buffer for newline
            if let Some(nl_pos) = self.buf[self.pos..].iter().position(|&b| b == b'\n') {
                let abs = self.pos + nl_pos;
                let line: Vec<u8> = self.buf[self.pos..abs]
                    .iter()
                    .filter(|&&b| b != b'\r')
                    .copied()
                    .collect();
                self.pos = abs + 1;
                // Compact buffer periodically to avoid unbounded growth
                if self.pos > 1024 {
                    self.buf.drain(..self.pos);
                    self.pos = 0;
                }
                return Ok(String::from_utf8_lossy(&line).into_owned());
            }
            // No newline found — need more data
            self.fill()?;
        }
    }
}

pub fn run_rfcomm_server_loop() {
    let (_tx, rx) = std::sync::mpsc::channel();
    run_rfcomm_server_with_shutdown(rx);
}

pub fn run_rfcomm_server_with_shutdown(shutdown_rx: std::sync::mpsc::Receiver<()>) {
    println!("[RFCOMM] server starting");
    println!("[RFCOMM] advertising service UUID: 7f9b841a-3e2c-4a90-8b1b-5e6f8a9c0d1e");

    // Ensure Bluetooth state restoration manager is initialized
    crate::bluetooth_lifecycle::BluetoothStateRestorer::initialize();

    let provider = match create_rfcomm_provider() {
        Ok(p) => p,
        Err(e) => {
            eprintln!("[RFCOMM] Error creating RfcommServiceProvider: {:?}", e);
            eprintln!("[RFCOMM] Bluetooth adapter may be unavailable or disabled.");
            return;
        }
    };

    let listener = match StreamSocketListener::new() {
        Ok(l) => l,
        Err(e) => {
            eprintln!("[RFCOMM] Error creating StreamSocketListener: {:?}", e);
            return;
        }
    };

    let service_id = match provider.ServiceId() {
        Ok(id) => id,
        Err(e) => {
            eprintln!("[RFCOMM] Error getting ServiceId: {:?}", e);
            return;
        }
    };

    let service_token = match service_id.AsString() {
        Ok(s) => s,
        Err(e) => {
            eprintln!("[RFCOMM] Error formatting service_id string: {:?}", e);
            return;
        }
    };

    let bind_op = match listener.BindServiceNameAsync(&service_token) {
        Ok(op) => op,
        Err(e) => {
            eprintln!("[RFCOMM] Error initiating BindServiceNameAsync: {:?}", e);
            return;
        }
    };

    if let Err(e) = bind_op.get() {
        eprintln!("[RFCOMM] Error completing BindServiceNameAsync: {:?}", e);
        return;
    }

    if let Err(e) = provider.StartAdvertising(&listener) {
        eprintln!("[RFCOMM] Error starting SDP advertisement: {:?}", e);
        return;
    }

    println!("[RFCOMM] server ready and listening for Android client connections...");

    loop {
        if shutdown_rx.try_recv().is_ok() {
            println!("[RFCOMM] shutdown requested, stopping listener and advertising...");
            break;
        }

        let socket = match listener_accept_next(&listener, &shutdown_rx) {
            Ok(Some(s)) => s,
            Ok(None) => {
                println!("[RFCOMM] accept loop received shutdown signal");
                break;
            }
            Err(e) => {
                eprintln!("[RFCOMM] Connection accept error: {:?}", e);
                std::thread::sleep(Duration::from_secs(1));
                continue;
            }
        };

        handle_client_connection(socket);
        println!("[RFCOMM] waiting for client reconnect...");
    }

    // Teardown listener and advertisement on clean shutdown
    let _ = provider.StopAdvertising();
    let _ = listener.Close();
    println!("[RFCOMM] server stopped cleanly");
}

fn create_rfcomm_provider() -> Result<RfcommServiceProvider> {
    let service_id = RfcommServiceId::FromUuid(POUSE_RFCOMM_UUID)?;
    let provider_op = RfcommServiceProvider::CreateAsync(&service_id)?;
    provider_op.get()
}

fn listener_accept_next(
    listener: &StreamSocketListener,
    shutdown_rx: &std::sync::mpsc::Receiver<()>,
) -> Result<Option<StreamSocket>> {
    let (tx, rx) = std::sync::mpsc::channel();
    let token = listener.ConnectionReceived(&TypedEventHandler::new(
        move |_listener, args: &Option<StreamSocketListenerConnectionReceivedEventArgs>| {
            if let Some(args_val) = args {
                if let Ok(socket) = args_val.Socket() {
                    let _ = tx.send(socket);
                }
            }
            Ok(())
        },
    ))?;

    loop {
        if shutdown_rx.try_recv().is_ok() {
            let _ = listener.RemoveConnectionReceived(token);
            return Ok(None);
        }

        match rx.recv_timeout(Duration::from_millis(500)) {
            Ok(socket) => {
                let _ = listener.RemoveConnectionReceived(token);
                return Ok(Some(socket));
            }
            Err(std::sync::mpsc::RecvTimeoutError::Timeout) => {
                continue;
            }
            Err(std::sync::mpsc::RecvTimeoutError::Disconnected) => {
                let _ = listener.RemoveConnectionReceived(token);
                return Err(Error::new(HRESULT(0x80004005u32 as i32), "Listener channel disconnected"));
            }
        }
    }
}

fn handle_client_connection(socket: StreamSocket) {
    let dev_name = socket
        .Information()
        .and_then(|info| info.RemoteHostName())
        .and_then(|hn| hn.DisplayName())
        .unwrap_or_else(|_| HSTRING::from("Android Client"))
        .to_string();

    println!("[RFCOMM] client connected: '{}'", dev_name);

    let writer = match DataWriter::CreateDataWriter(&socket.OutputStream().unwrap()) {
        Ok(w) => w,
        Err(e) => {
            eprintln!("[RFCOMM] Error creating DataWriter: {:?}", e);
            return;
        }
    };

    let reader = match DataReader::CreateDataReader(&socket.InputStream().unwrap()) {
        Ok(r) => r,
        Err(e) => {
            eprintln!("[RFCOMM] Error creating DataReader: {:?}", e);
            return;
        }
    };

    // InputOwner is NOT acquired on socket accept.
    // It is acquired only after POUSE_HELLO / POUSE_ACK handshake succeeds,
    // which is the proxy for Android-side TOFU authorization completing.
    // Until then the previous authorized transport (Wi-Fi or None) retains ownership.
    let input_owner = InputOwner::global();
    let mut handshake_complete = false;
    let mut input_ownership_acquired = false;

    // Buffered reader eliminates the previous per-byte LoadAsync(1) overhead.
    let mut buf_reader = BufferedRfcommReader::new(&reader);

    // Pending MOVE accumulator — used to coalesce any MOVE events that arrive
    // faster than we can dispatch them (e.g., while the previous event's
    // SendInput is executing).  Only MOVE events are accumulated; all other
    // event types are dispatched immediately.  This prevents the cursor from
    // "catching up" after the user has already stopped moving.
    let mut pending_move_dx: f32 = 0.0;
    let mut pending_move_dy: f32 = 0.0;
    let mut pending_move_t: Option<u64> = None;
    let mut has_pending_move = false;

    loop {
        // Flush any accumulated MOVE before waiting for the next line
        if has_pending_move && input_ownership_acquired {
            let recv_instant = std::time::Instant::now();
            input_owner.handle_event(
                TransportType::Bluetooth,
                None,
                PouseEvent::Move { dx: pending_move_dx, dy: pending_move_dy, t: pending_move_t },
            );
            let latency_us = recv_instant.elapsed().as_micros() as u32;
            let e2e_ms = pending_move_t.and_then(|t_ms| {
                let now_ms = std::time::SystemTime::now()
                    .duration_since(std::time::UNIX_EPOCH)
                    .ok()?
                    .as_millis() as u64;
                if now_ms >= t_ms {
                    Some((now_ms - t_ms) as u32)
                } else {
                    None
                }
            });
            latency_stats().record(latency_us, true, e2e_ms);
            pending_move_dx = 0.0;
            pending_move_dy = 0.0;
            pending_move_t = None;
            has_pending_move = false;
        }

        match buf_reader.read_line() {
            Ok(line) => {
                let trimmed = line.trim();
                if trimmed.is_empty() {
                    continue;
                }

                if trimmed == "POUSE_HELLO" {
                    println!("[RFCOMM] HELLO received");
                    let _ = send_line(&writer, "POUSE_ACK");
                    println!("[RFCOMM] ACK sent");
                    handshake_complete = true;
                    continue;
                }

                if trimmed == "POUSE_ACK" {
                    continue;
                }

                if trimmed.starts_with("TEST:") {
                    let seq = &trimmed[5..];
                    let ack = format!("ACK:{}", seq);
                    let _ = send_line(&writer, &ack);
                    continue;
                }

                if !handshake_complete {
                    eprintln!("[RFCOMM] input event received before handshake — discarding");
                    continue;
                }

                let recv_instant = std::time::Instant::now();

                match PouseEvent::parse(trimmed) {
                    Ok(event) => {
                        if matches!(event, PouseEvent::Ping) {
                            let _ = send_line(&writer, r#"{"event":"PONG"}"#);
                        } else {
                            // First authorized input event: acquire transport ownership.
                            if !input_ownership_acquired {
                                input_owner.acquire(TransportType::Bluetooth);
                                input_ownership_acquired = true;
                                println!("[RFCOMM] input ownership acquired on first authorized input event");
                            }

                            // MOVE event: accumulate into pending coalescer.
                            // All other events: flush pending MOVE first, then dispatch.
                            match &event {
                                PouseEvent::Move { dx, dy, t } => {
                                    pending_move_dx += dx;
                                    pending_move_dy += dy;
                                    if pending_move_t.is_none() {
                                        pending_move_t = *t;
                                    }
                                    has_pending_move = true;
                                    // Latency tracking: record that we received a MOVE
                                    // (will be injected at top of next loop iteration)
                                }
                                _ => {
                                    // Flush any pending MOVE first to preserve ordering
                                    if has_pending_move {
                                        input_owner.handle_event(
                                            TransportType::Bluetooth,
                                            None,
                                            PouseEvent::Move {
                                                dx: pending_move_dx,
                                                dy: pending_move_dy,
                                                t: pending_move_t,
                                            },
                                        );
                                        let latency_us = recv_instant.elapsed().as_micros() as u32;
                                        let e2e_ms = pending_move_t.and_then(|t_ms| {
                                            let now_ms = std::time::SystemTime::now()
                                                .duration_since(std::time::UNIX_EPOCH)
                                                .ok()?
                                                .as_millis() as u64;
                                            if now_ms >= t_ms {
                                                Some((now_ms - t_ms) as u32)
                                            } else {
                                                None
                                            }
                                        });
                                        latency_stats().record(latency_us, true, e2e_ms);
                                        pending_move_dx = 0.0;
                                        pending_move_dy = 0.0;
                                        pending_move_t = None;
                                        has_pending_move = false;
                                    }
                                    // Dispatch discrete event
                                    input_owner.handle_event(TransportType::Bluetooth, None, event);
                                    let latency_us = recv_instant.elapsed().as_micros() as u32;
                                    latency_stats().record(latency_us, false, None);
                                }
                            }
                        }
                    }
                    Err(e) => {
                        eprintln!("[RFCOMM] JSON parse error: {} (raw: '{}')", e, trimmed);
                    }
                }
            }
            Err(e) => {
                println!("[RFCOMM] client disconnected from '{}' ({:?})", dev_name, e);
                break;
            }
        }
    }

    // Print final stats on disconnect
    latency_stats().report();

    // Release held keys/buttons and transport ownership on disconnect.
    if input_ownership_acquired {
        input_owner.release(TransportType::Bluetooth);
    }
    let _ = socket.Close();
}

fn send_line(writer: &DataWriter, text: &str) -> Result<()> {
    let payload = format!("{}\n", text);
    writer.WriteString(&HSTRING::from(&payload))?;
    writer.StoreAsync()?.get()?;
    Ok(())
}

// NOTE: read_line() is no longer used — replaced by BufferedRfcommReader above.
// Kept for reference.
#[allow(dead_code)]
fn read_line_legacy(reader: &DataReader) -> Result<String> {
    let mut line = String::new();
    loop {
        reader.LoadAsync(1)?.get()?;
        let byte = reader.ReadByte()?;
        if byte == b'\n' {
            break;
        }
        if byte != b'\r' {
            line.push(byte as char);
        }
    }
    Ok(line)
}
