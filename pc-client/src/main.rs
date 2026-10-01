#![windows_subsystem = "windows"]

use pc_client::remote_screen::host::RemoteScreenHost;
use pc_client::server;
use pc_client::tray::SystemTray;
use std::thread;

fn main() -> Result<(), Box<dyn std::error::Error>> {
    println!("Starting Pouse PC Client...");

    // 1. Initialize configuration & migrate legacy pairing.json if needed
    let config_mgr = pc_client::config::ConfigManager::global();

    let reset_pairing = std::env::args().any(|arg| arg == "--reset-pairing");
    if reset_pairing {
        println!("[PAIRING] --reset-pairing flag detected. Generating new pairToken...");
        let new_token = pc_client::pairing::generate_random_token();
        config_mgr.set_pair_token(new_token.clone());
        RemoteScreenHost::global().lock().unwrap().set_pair_token(new_token);
    } else {
        // Initialize host singleton with current token
        let _host = RemoteScreenHost::global();
    }

    // 2. Initialize display brightness detection engine
    pc_client::display::init_brightness_support();

    // 3. Initialize central InputOwner singleton
    let _input_owner = pc_client::input_owner::InputOwner::global();

    // 4. Initialize Windows Bluetooth state manager (queries and stores discoverability state)
    pc_client::bluetooth_lifecycle::BluetoothStateRestorer::initialize();

    // 5. Spawn BLE advertiser in background worker thread with shutdown receiver
    let (ble_stop_tx, ble_stop_rx) = std::sync::mpsc::channel();
    let ble_handle = thread::spawn(move || {
        let mut advertiser = pc_client::ble_advertiser::BleAdvertiser::new();
        advertiser.start();
        let _ = ble_stop_rx.recv();
        advertiser.stop();
    });

    // 6. Spawn Bluetooth RFCOMM server in background worker thread with shutdown receiver
    let (rfcomm_stop_tx, rfcomm_stop_rx) = std::sync::mpsc::channel();
    let rfcomm_handle = thread::spawn(move || {
        pc_client::rfcomm_server::run_rfcomm_server_with_shutdown(rfcomm_stop_rx);
    });

    // 7. Channel for coordinating shutdown between Tray / Ctrl+C and background tasks
    let (shutdown_tx, shutdown_rx) = std::sync::mpsc::channel();
    let shutdown_tx_ctrlc = shutdown_tx.clone();

    // Spawn multi-threaded Tokio runtime for Wi-Fi WebSocket server
    let rt = tokio::runtime::Builder::new_multi_thread()
        .enable_all()
        .build()?;

    let (tokio_stop_tx, mut tokio_stop_rx) = tokio::sync::oneshot::channel::<()>();

    let port = config_mgr.get_config().general.port;
    let _wifi_handle = thread::spawn(move || {
        rt.block_on(async {
            tokio::select! {
                res = server::run_server(port) => {
                    if let Err(e) = res {
                        eprintln!("[SERVER] Wi-Fi server exited: {}", e);
                    }
                }
                _ = &mut tokio_stop_rx => {
                    println!("[SERVER] Wi-Fi server received shutdown signal.");
                }
            }
        });
    });

    // Ctrl+C signal handler thread
    thread::spawn(move || {
        // Simple polling or ctrlc wait
        let rt_signal = tokio::runtime::Builder::new_current_thread().enable_all().build();
        if let Ok(rt) = rt_signal {
            rt.block_on(async {
                let _ = tokio::signal::ctrl_c().await;
                println!("\n[SHUTDOWN] Received Ctrl+C / SIGINT signal.");
                let _ = shutdown_tx_ctrlc.send(());
            });
        }
    });

    let no_tray = std::env::args().any(|arg| arg == "--no-tray" || arg == "--headless");

    if !no_tray {
        match SystemTray::new(shutdown_tx) {
            Ok(tray) => {
                println!("[TRAY] Running system tray message loop on main thread...");
                tray.run_message_loop();
            }
            Err(e) => {
                eprintln!("[TRAY] Could not initialize system tray ({}), falling back to console wait.", e);
                let _ = shutdown_rx.recv();
            }
        }
    } else {
        println!("[SERVER] Running in headless mode (no system tray). Waiting for shutdown signal...");
        let _ = shutdown_rx.recv();
    }

    // 8. Graceful shutdown sequence
    println!("[SHUTDOWN] Initiating graceful shutdown of background services...");
    let _ = tokio_stop_tx.send(());

    println!("[SHUTDOWN] Stopping BLE advertiser...");
    let _ = ble_stop_tx.send(());
    let _ = ble_handle.join();

    println!("[SHUTDOWN] Stopping RFCOMM server...");
    let _ = rfcomm_stop_tx.send(());
    let _ = rfcomm_handle.join();

    println!("[SHUTDOWN] Restoring system Bluetooth state...");
    pc_client::bluetooth_lifecycle::BluetoothStateRestorer::restore();

    println!("[SHUTDOWN] Clean shutdown complete.");
    Ok(())
}
