use std::time::{Duration, Instant};
use windows::core::*;
use windows::Devices::Bluetooth::Rfcomm::*;
use windows::Devices::Enumeration::*;
use windows::Networking::Sockets::*;
use windows::Storage::Streams::*;

// Unique Pouse RFCOMM Service UUID (must match Android BluetoothRfcommBridge.kt)
const POUSE_RFCOMM_UUID: GUID = GUID::from_u128(0x7f9b841a_3e2c_4a90_8b1b_5e6f8a9c0d1e);

fn main() -> Result<()> {
    println!("==================================================");
    println!("  Pouse Bluetooth Classic RFCOMM Test Client (Phase 1)");
    println!("  UUID: 7f9b841a-3e2c-4a90-8b1b-5e6f8a9c0d1e");
    println!("==================================================");

    let service_id = RfcommServiceId::FromUuid(POUSE_RFCOMM_UUID)?;
    let selector = RfcommDeviceService::GetDeviceSelector(&service_id)?;

    loop {
        println!("[RFCOMM] discovery started");
        let devices = match DeviceInformation::FindAllAsyncAqsFilter(&selector)?.get() {
            Ok(d) => d,
            Err(e) => {
                println!("[RFCOMM] error searching for devices: {:?}", e);
                std::thread::sleep(Duration::from_secs(2));
                continue;
            }
        };

        let count = devices.Size().unwrap_or(0);
        println!("[RFCOMM] devices/services found: {}", count);

        if count == 0 {
            println!("[RFCOMM] Pouse service not found on paired devices. Retrying in 2 seconds...");
            println!("[RFCOMM] Tip: Ensure phone is paired in Windows Bluetooth Settings & RFCOMM server is started in Pouse.");
            std::thread::sleep(Duration::from_secs(2));
            continue;
        }

        // Connect to first discovered Pouse RFCOMM service
        let target_dev = devices.GetAt(0)?;
        println!("[RFCOMM] Pouse service found on device: '{}' (ID: {})", target_dev.Name()?, target_dev.Id()?);

        println!("[RFCOMM] connecting...");
        let service = match RfcommDeviceService::FromIdAsync(&target_dev.Id()?)?.get() {
            Ok(s) => s,
            Err(e) => {
                println!("[RFCOMM] error initializing RfcommDeviceService: {:?}", e);
                std::thread::sleep(Duration::from_secs(2));
                continue;
            }
        };

        let socket = StreamSocket::new()?;
        let host_name = service.ConnectionHostName()?;
        let service_name = service.ConnectionServiceName()?;

        match socket.ConnectAsync(&host_name, &service_name)?.get() {
            Ok(_) => println!("[RFCOMM] connected"),
            Err(e) => {
                println!("[RFCOMM] error: connection failed with status {:?}", e);
                std::thread::sleep(Duration::from_secs(2));
                continue;
            }
        }

        let writer = DataWriter::CreateDataWriter(&socket.OutputStream()?)?;
        let reader = DataReader::CreateDataReader(&socket.InputStream()?)?;

        // 1. Handshake Phase: POUSE_HELLO -> POUSE_ACK
        if let Err(e) = send_line(&writer, "POUSE_HELLO") {
            println!("[RFCOMM] error sending POUSE_HELLO: {:?}", e);
            continue;
        }
        println!("[RFCOMM] sent: POUSE_HELLO");

        match read_line(&reader) {
            Ok(ack) => println!("[RFCOMM] received: {}", ack),
            Err(e) => {
                println!("[RFCOMM] error reading handshake response: {:?}", e);
                continue;
            }
        }

        // 2. 500-Message Echo & Latency Measurement Test
        println!("\n[RFCOMM] Starting 500-message bidirectional reliability & latency test...");
        let target_count = 500;
        let mut latencies: Vec<Duration> = Vec::with_capacity(target_count);
        let mut success_count = 0;
        let test_start_time = Instant::now();

        for i in 1..=target_count {
            let msg = format!("TEST:{}", i);
            let start = Instant::now();

            if let Err(e) = send_line(&writer, &msg) {
                println!("[RFCOMM] error sending message {}: {:?}", i, e);
                break;
            }

            match read_line(&reader) {
                Ok(resp) => {
                    let rtt = start.elapsed();
                    let expected = format!("ACK:{}", i);
                    if resp == expected {
                        success_count += 1;
                        latencies.push(rtt);
                        if i % 50 == 0 || i == 1 {
                            println!("[RFCOMM] [{}/{}] sent: {} | received: {} (RTT: {:.2?})", i, target_count, msg, resp, rtt);
                        }
                    } else {
                        println!("[RFCOMM] MISMATCH! Sent {}, received {}", msg, resp);
                    }
                }
                Err(e) => {
                    println!("[RFCOMM] error reading response for message {}: {:?}", i, e);
                    break;
                }
            }

            // Small 5ms pacing delay between test messages
            std::thread::sleep(Duration::from_millis(5));
        }

        let total_duration = test_start_time.elapsed();

        // 3. Print Detailed Percentile Latency & Reliability Summary
        println!("\n==================================================");
        println!("  PHASE 1 RFCOMM TEST RESULTS SUMMARY");
        println!("==================================================");
        println!("  Test Duration:     {:.2?}", total_duration);
        println!("  Sample Count:      {}", target_count);
        println!("  Messages ACKed:    {}/{}", success_count, target_count);
        println!("  Success Rate:      {:.2}%", (success_count as f64 / target_count as f64) * 100.0);
        println!("  Messages Lost:     {}", target_count - success_count);

        let mut min_ms = 0.0;
        let mut p50_ms = 0.0;
        let mut p95_ms = 0.0;
        let mut p99_ms = 0.0;
        let mut max_ms = 0.0;
        let mut avg_ms = 0.0;

        if !latencies.is_empty() {
            latencies.sort();
            let n = latencies.len();
            min_ms = latencies[0].as_secs_f64() * 1000.0;
            max_ms = latencies[n - 1].as_secs_f64() * 1000.0;
            p50_ms = latencies[(n as f64 * 0.50) as usize].as_secs_f64() * 1000.0;
            p95_ms = latencies[(n as f64 * 0.95).min((n - 1) as f64) as usize].as_secs_f64() * 1000.0;
            p99_ms = latencies[(n as f64 * 0.99).min((n - 1) as f64) as usize].as_secs_f64() * 1000.0;
            let total_us: u128 = latencies.iter().map(|d| d.as_micros()).sum();
            avg_ms = (total_us as f64 / n as f64) / 1000.0;

            println!("  Minimum RTT:       {:.2} ms", min_ms);
            println!("  p50 RTT (Median):  {:.2} ms", p50_ms);
            println!("  p95 RTT:           {:.2} ms", p95_ms);
            println!("  p99 RTT:           {:.2} ms", p99_ms);
            println!("  Maximum RTT:       {:.2} ms", max_ms);
            println!("  Average RTT:       {:.2} ms", avg_ms);
        }
        println!("==================================================");

        // 4. Save Persistent Machine-Readable JSON Result
        let args: Vec<String> = std::env::args().collect();
        let stage_label = if args.len() > 1 { &args[1] } else { "before_hid" };
        let timestamp = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap_or_default()
            .as_secs();

        let json_payload = format!(
            "{{\n  \"timestamp\": {},\n  \"git_commit\": \"f251618\",\n  \"stage\": \"{}\",\n  \"sample_count\": {},\n  \"acked_count\": {},\n  \"success_rate_pct\": {:.2},\n  \"min_rtt_ms\": {:.2},\n  \"p50_rtt_ms\": {:.2},\n  \"p95_rtt_ms\": {:.2},\n  \"p99_rtt_ms\": {:.2},\n  \"max_rtt_ms\": {:.2},\n  \"avg_rtt_ms\": {:.2},\n  \"status\": \"{}\"\n}}",
            timestamp,
            stage_label,
            target_count,
            success_count,
            (success_count as f64 / target_count as f64) * 100.0,
            min_ms,
            p50_ms,
            p95_ms,
            p99_ms,
            max_ms,
            avg_ms,
            if success_count == target_count { "PASS" } else { "PARTIAL" }
        );

        let out_dir = std::path::Path::new("tests/bluetooth/phase1/results");
        let _ = std::fs::create_dir_all(out_dir);
        let out_path = out_dir.join(format!("baseline_{}_{}.json", stage_label, timestamp));
        if std::fs::write(&out_path, &json_payload).is_ok() {
            println!("[RFCOMM] Baseline machine-readable test result saved to: {:?}", out_path);
        }

        println!("[RFCOMM] test complete. Disconnecting cleanly...");
        let _ = socket.Close();
        println!("[RFCOMM] disconnected");
        break;
    }

    Ok(())
}

fn send_line(writer: &DataWriter, text: &str) -> Result<()> {
    let payload = format!("{}\n", text);
    writer.WriteString(&HSTRING::from(&payload))?;
    writer.StoreAsync()?.get()?;
    Ok(())
}

fn read_line(reader: &DataReader) -> Result<String> {
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
