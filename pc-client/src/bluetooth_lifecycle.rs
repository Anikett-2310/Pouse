use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Mutex;
use windows::Win32::Devices::Bluetooth::{
    BluetoothEnableDiscovery, BluetoothEnableIncomingConnections, BluetoothIsDiscoverable,
};

/// Tracks and manages Windows system Bluetooth state during Pouse execution.
/// Ensures system discoverability and incoming connection states are safely recorded
/// at startup and cleanly restored upon process shutdown or teardown.
pub struct BluetoothStateRestorer {
    was_discoverable: Option<bool>,
    incoming_modified: bool,
    restored: AtomicBool,
}

static RESTORER: Mutex<Option<BluetoothStateRestorer>> = Mutex::new(None);

impl BluetoothStateRestorer {
    /// Queries the current Bluetooth discoverability state and configures the radio
    /// for incoming Pouse RFCOMM connections. Strictly idempotent.
    pub fn initialize() {
        let mut guard = RESTORER.lock().unwrap();
        if guard.is_some() {
            return; // Already initialized; do not query or overwrite again
        }

        println!("[BT_LIFECYCLE] Initializing Windows Bluetooth state manager...");

        let was_discoverable = unsafe {
            let res = BluetoothIsDiscoverable(None);
            let val = res.as_bool();
            println!("[BT_LIFECYCLE] Initial discoverability state queried: {}", val);
            Some(val)
        };

        // Enable incoming connections required for RFCOMM server
        let inc_res = unsafe { BluetoothEnableIncomingConnections(None, true) };
        println!(
            "[BT_LIFECYCLE] incoming connections enabled: {}",
            inc_res.as_bool()
        );

        // Enable discovery so phone BLE scanner can discover and pair
        let disc_res = unsafe { BluetoothEnableDiscovery(None, true) };
        println!(
            "[BT_LIFECYCLE] discoverability enabled: {}",
            disc_res.as_bool()
        );

        *guard = Some(BluetoothStateRestorer {
            was_discoverable,
            incoming_modified: inc_res.as_bool(),
            restored: AtomicBool::new(false),
        });
    }

    /// Restores the original discoverability and incoming connection states.
    /// Safe to call multiple times (idempotent).
    pub fn restore() {
        let mut guard = RESTORER.lock().unwrap();
        if let Some(restorer) = guard.as_mut() {
            if restorer.restored.swap(true, Ordering::SeqCst) {
                return; // Already restored
            }

            println!("[BT_LIFECYCLE] Restoring system Bluetooth state...");

            // Restore discoverability if it was previously false
            if let Some(was_disc) = restorer.was_discoverable {
                if !was_disc {
                    unsafe {
                        let res = BluetoothEnableDiscovery(None, false);
                        if res.as_bool() {
                            println!("[BT_LIFECYCLE] System discoverability restored to original state (false)");
                        } else {
                            eprintln!("[BT_LIFECYCLE] Warning: Failed to restore discoverability to false");
                        }
                    }
                } else {
                    println!("[BT_LIFECYCLE] Discoverability was originally true; leaving enabled as found");
                }
            }

            // Restore incoming connections if discoverability was originally false and we modified it
            if restorer.incoming_modified && restorer.was_discoverable == Some(false) {
                unsafe {
                    let res = BluetoothEnableIncomingConnections(None, false);
                    if res.as_bool() {
                        println!("[BT_LIFECYCLE] System incoming-connections restored to original state (false)");
                    } else {
                        eprintln!("[BT_LIFECYCLE] Warning: Failed to restore incoming connections to false");
                    }
                }
            }

            println!("[BT_LIFECYCLE] Windows Bluetooth state restoration complete.");
        }
    }
}

/// Standalone convenience wrapper for global restoration
pub fn restore_bluetooth_state() {
    BluetoothStateRestorer::restore();
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_bluetooth_state_initialization_and_idempotency() {
        BluetoothStateRestorer::initialize();
        BluetoothStateRestorer::restore();
        // Second call should be a safe no-op
        BluetoothStateRestorer::restore();
    }
}
