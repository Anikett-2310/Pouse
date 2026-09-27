use std::time::Duration;
use windows::core::*;
use windows::Devices::Bluetooth::Rfcomm::*;
use windows::Devices::Enumeration::*;
use windows::Networking::Sockets::*;
use windows::Storage::Streams::*;

use crate::input::InputHandler;
use crate::protocol::PouseEvent;

// Fixed Pouse RFCOMM Service UUID (7f9b841a-3e2c-4a90-8b1b-5e6f8a9c0d1e)
const POUSE_RFCOMM_UUID: GUID = GUID::from_u128(0x7f9b841a_3e2c_4a90_8b1b_5e6f8a9c0d1e);

/// Background RFCOMM client loop running alongside the WebSocket server.
///
/// Automatically discovers paired Android phones advertising the Pouse RFCOMM service UUID,
/// establishes a stream connection, and feeds incoming JSON events directly into the
/// shared Pouse [InputHandler] input injection pipeline.
pub fn run_rfcomm_client_loop() {
    println!("[RFCOMM] Background Bluetooth RFCOMM transport task initialized.");

    let service_id = match RfcommServiceId::FromUuid(POUSE_RFCOMM_UUID) {
        Ok(id) => id,
        Err(e) => {
            eprintln!("[RFCOMM] Error initializing RfcommServiceId: {:?}", e);
            return;
        }
    };

    let selector = match RfcommDeviceService::GetDeviceSelector(&service_id) {
        Ok(sel) => sel,
        Err(e) => {
            eprintln!("[RFCOMM] Error getting device selector: {:?}", e);
            return;
        }
    };

    loop {
        let devices = match DeviceInformation::FindAllAsyncAqsFilter(&selector) {
            Ok(async_op) => match async_op.get() {
                Ok(d) => d,
                Err(e) => {
                    eprintln!("[RFCOMM] Error finding paired RFCOMM devices: {:?}", e);
                    std::thread::sleep(Duration::from_secs(3));
                    continue;
                }
            },
            Err(e) => {
                eprintln!("[RFCOMM] Error starting device discovery query: {:?}", e);
                std::thread::sleep(Duration::from_secs(3));
                continue;
            }
        };

        let count = devices.Size().unwrap_or(0);
        if count == 0 {
            // Silence routine polling when no phone server is listening
            std::thread::sleep(Duration::from_secs(3));
            continue;
        }

        let target_dev = match devices.GetAt(0) {
            Ok(dev) => dev,
            Err(_) => {
                std::thread::sleep(Duration::from_secs(2));
                continue;
            }
        };

        let dev_name = target_dev.Name().unwrap_or_default().to_string();
        let dev_id = target_dev.Id().unwrap_or_default();
        println!("[RFCOMM] Found Pouse Bluetooth service on device: '{}'", dev_name);

        let service = match RfcommDeviceService::FromIdAsync(&dev_id) {
            Ok(op) => match op.get() {
                Ok(s) => s,
                Err(e) => {
                    eprintln!("[RFCOMM] Error binding to RfcommDeviceService: {:?}", e);
                    std::thread::sleep(Duration::from_secs(2));
                    continue;
                }
            },
            Err(e) => {
                eprintln!("[RFCOMM] Error getting RfcommDeviceService: {:?}", e);
                std::thread::sleep(Duration::from_secs(2));
                continue;
            }
        };

        let socket = match StreamSocket::new() {
            Ok(s) => s,
            Err(e) => {
                eprintln!("[RFCOMM] Error creating StreamSocket: {:?}", e);
                std::thread::sleep(Duration::from_secs(2));
                continue;
            }
        };

        let host_name = match service.ConnectionHostName() {
            Ok(h) => h,
            Err(e) => {
                eprintln!("[RFCOMM] Error getting ConnectionHostName: {:?}", e);
                std::thread::sleep(Duration::from_secs(2));
                continue;
            }
        };

        let service_name = match service.ConnectionServiceName() {
            Ok(s) => s,
            Err(e) => {
                eprintln!("[RFCOMM] Error getting ConnectionServiceName: {:?}", e);
                std::thread::sleep(Duration::from_secs(2));
                continue;
            }
        };

        println!("[RFCOMM] Connecting to '{}' over Bluetooth RFCOMM...", dev_name);
        match socket.ConnectAsync(&host_name, &service_name) {
            Ok(op) => match op.get() {
                Ok(_) => println!("[RFCOMM] Connected to '{}' over Bluetooth RFCOMM!", dev_name),
                Err(e) => {
                    eprintln!("[RFCOMM] Failed to connect to '{}': {:?}", dev_name, e);
                    std::thread::sleep(Duration::from_secs(2));
                    continue;
                }
            },
            Err(e) => {
                eprintln!("[RFCOMM] ConnectAsync error: {:?}", e);
                std::thread::sleep(Duration::from_secs(2));
                continue;
            }
        }

        let writer = match DataWriter::CreateDataWriter(&socket.OutputStream().unwrap()) {
            Ok(w) => w,
            Err(e) => {
                eprintln!("[RFCOMM] Error creating DataWriter: {:?}", e);
                std::thread::sleep(Duration::from_secs(2));
                continue;
            }
        };

        let reader = match DataReader::CreateDataReader(&socket.InputStream().unwrap()) {
            Ok(r) => r,
            Err(e) => {
                eprintln!("[RFCOMM] Error creating DataReader: {:?}", e);
                std::thread::sleep(Duration::from_secs(2));
                continue;
            }
        };

        // Handshake: Send POUSE_HELLO
        let _ = send_line(&writer, "POUSE_HELLO");

        // Initialize shared InputHandler for this connection instance
        let mut input_handler = match InputHandler::new() {
            Ok(h) => h,
            Err(e) => {
                eprintln!("[RFCOMM] Failed to initialize InputHandler: {}", e);
                let _ = socket.Close();
                std::thread::sleep(Duration::from_secs(2));
                continue;
            }
        };

        println!("[RFCOMM] Input pipeline active for Bluetooth transport.");

        loop {
            match read_line(&reader) {
                Ok(line) => {
                    let trimmed = line.trim();
                    if trimmed.is_empty() {
                        continue;
                    }

                    if trimmed == "POUSE_HELLO" || trimmed == "POUSE_ACK" {
                        continue;
                    }

                    if trimmed.starts_with("TEST:") {
                        let seq = &trimmed[5..];
                        let ack = format!("ACK:{}", seq);
                        let _ = send_line(&writer, &ack);
                        continue;
                    }

                    match PouseEvent::parse(trimmed) {
                        Ok(event) => {
                            if matches!(event, PouseEvent::Ping) {
                                let _ = send_line(&writer, r#"{"event":"PONG"}"#);
                            } else {
                                input_handler.handle_event(event);
                            }
                        }
                        Err(e) => {
                            eprintln!("[RFCOMM] JSON parse error: {} (raw: '{}')", e, trimmed);
                        }
                    }
                }
                Err(e) => {
                    println!("[RFCOMM] Disconnected from '{}' ({:?})", dev_name, e);
                    break;
                }
            }
        }

        // Safety release: guarantee held mouse buttons & keys are released on disconnect
        input_handler.release_all();
        let _ = socket.Close();
        println!("[RFCOMM] Connection closed cleanly. Retrying discovery in 2 seconds...");
        std::thread::sleep(Duration::from_secs(2));
    }
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
