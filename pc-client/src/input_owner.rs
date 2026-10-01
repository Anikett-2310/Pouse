use std::net::SocketAddr;
use std::sync::{Mutex, OnceLock};

use crate::input::InputHandler;
use crate::protocol::PouseEvent;
use crate::remote_screen::host::{InputPermission, RemoteScreenHost};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum TransportType {
    Wifi,
    Bluetooth,
}

impl std::fmt::Display for TransportType {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            TransportType::Wifi => write!(f, "wifi"),
            TransportType::Bluetooth => write!(f, "bluetooth"),
        }
    }
}

pub struct InputOwner {
    handler: Mutex<Option<InputHandler>>,
    active_transport: Mutex<Option<TransportType>>,
}

static GLOBAL_INPUT_OWNER: OnceLock<InputOwner> = OnceLock::new();

impl InputOwner {
    pub fn global() -> &'static Self {
        GLOBAL_INPUT_OWNER.get_or_init(|| {
            let handler = match InputHandler::new() {
                Ok(h) => Some(h),
                Err(e) => {
                    eprintln!("[INPUT] Failed to initialize central InputHandler: {}", e);
                    None
                }
            };
            Self {
                handler: Mutex::new(handler),
                active_transport: Mutex::new(None),
            }
        })
    }

    /// Acquires active transport ownership for input dispatch.
    /// If another transport was active, releases its held buttons/keys first.
    pub fn acquire(&self, transport: TransportType) -> bool {
        let mut active = self.active_transport.lock().unwrap();
        if let Some(current) = *active {
            if current == transport {
                return true;
            }
            println!("[INPUT] ownership acquired: {} (switching from {})", transport, current);
            self.release_internal();
        } else {
            println!("[INPUT] ownership acquired: {}", transport);
        }
        *active = Some(transport);
        true
    }

    /// Releases active transport ownership if `transport` is current owner.
    pub fn release(&self, transport: TransportType) {
        let mut active = self.active_transport.lock().unwrap();
        if let Some(current) = *active {
            if current == transport {
                println!("[INPUT] ownership released: {}", transport);
                self.release_internal();
                *active = None;
            }
        }
    }

    fn release_internal(&self) {
        let mut handler_guard = self.handler.lock().unwrap();
        if let Some(handler) = handler_guard.as_mut() {
            handler.release_all();
        }
    }

    /// Handles input event from specified transport after checking Remote Screen lock & transport ownership.
    /// Returns true if event was processed, false if rejected.
    pub fn handle_event(&self, transport: TransportType, peer_addr: Option<&SocketAddr>, event: PouseEvent) -> bool {
        // 1. Check Remote Screen input permission locking if peer address is given
        if let Some(addr) = peer_addr {
            let host = RemoteScreenHost::global();
            let mut host_guard = host.lock().unwrap();
            let _ = host_guard.check_reconnect_timeout();
            if host_guard.can_process_input(addr) == InputPermission::Blocked {
                println!("[INPUT] rejected event from non-owner transport: {} (blocked peer: {})", transport, addr);
                return false;
            }
        }

        // 2. Ensure transport ownership
        let mut active = self.active_transport.lock().unwrap();
        match *active {
            Some(current) => {
                if current != transport {
                    println!("[INPUT] rejected event from non-owner transport: {} (active: {})", transport, current);
                    return false;
                }
            }
            None => {
                println!("[INPUT] ownership acquired: {}", transport);
                *active = Some(transport);
            }
        }

        // 3. Dispatch to shared InputHandler
        let mut handler_guard = self.handler.lock().unwrap();
        if let Some(handler) = handler_guard.as_mut() {
            handler.handle_event(event);
            true
        } else {
            false
        }
    }

    /// Explicitly releases held buttons/keys for transport.
    pub fn release_all(&self, transport: TransportType) {
        let active = self.active_transport.lock().unwrap();
        if let Some(current) = *active {
            if current == transport {
                self.release_internal();
            }
        }
    }
}
