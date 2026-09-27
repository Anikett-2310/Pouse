use pc_client::server;
use pc_client::remote_screen::host::RemoteScreenHost;
use std::thread;

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    println!("Starting Pouse PC Client...");

    let reset_pairing = std::env::args().any(|arg| arg == "--reset-pairing");
    if reset_pairing {
        println!("[PAIRING] --reset-pairing flag detected. Generating new pairToken...");
        let new_token = pc_client::pairing::get_or_create_pair_token(true);
        RemoteScreenHost::global().lock().unwrap().set_pair_token(new_token);
    } else {
        // Initialize host singleton
        let _host = RemoteScreenHost::global();
    }

    // Spawn Bluetooth RFCOMM transport loop in background worker thread
    thread::spawn(|| {
        pc_client::rfcomm::run_rfcomm_client_loop();
    });

    // Run Wi-Fi WebSocket server on main async runtime
    server::run_server(8081).await?;
    Ok(())
}
