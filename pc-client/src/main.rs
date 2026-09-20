mod input;
mod pairing;
mod protocol;
mod server;

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    println!("Starting Pouse PC Client...");
    server::run_server(8081).await?;
    Ok(())
}
