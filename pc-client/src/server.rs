use futures_util::{SinkExt, StreamExt};
use std::net::SocketAddr;
use tokio::net::{TcpListener, TcpStream};
use tokio_tungstenite::tungstenite::Message;
use crate::input::InputHandler;
use crate::protocol::PouseEvent;

pub async fn run_server(port: u16) -> Result<(), Box<dyn std::error::Error>> {
    let addr = format!("0.0.0.0:{}", port);
    let listener = TcpListener::bind(&addr).await?;

    println!("==================================================");
    println!("  Pouse PC Client Server Listening on Port {}", port);
    println!("  Local WebSocket Address: ws://<YOUR_PC_IP>:{}", port);
    println!("==================================================");

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
    let ws_stream = tokio_tungstenite::accept_async(stream).await?;
    println!("WebSocket handshake completed with {}", peer_addr);

    let (mut ws_sender, mut ws_receiver) = ws_stream.split();
    let mut input_handler = InputHandler::new().map_err(|e| std::io::Error::new(std::io::ErrorKind::Other, e))?;

    while let Some(msg_result) = ws_receiver.next().await {
        match msg_result {
            Ok(Message::Text(text)) => {
                match PouseEvent::parse(&text) {
                    Ok(event) => {
                        if matches!(event, PouseEvent::Ping) {
                            let pong = serde_json::json!({ "event": "PONG" }).to_string();
                            let _ = ws_sender.send(Message::Text(pong.into())).await;
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
