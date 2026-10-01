use std::time::Duration;
use windows::Devices::Bluetooth::Advertisement::*;
use windows::Foundation::TypedEventHandler;
use windows::Storage::Streams::*;

/// Configurable Manufacturer / Company Identifier for BLE Advertisement.
/// Note: 0xFFFF is reserved by Bluetooth SIG for test / development / internal use.
/// Do NOT present 0xFFFF as a final registered production company ID.
pub const BLE_DEV_COMPANY_ID: u16 = 0xFFFF;

/// Pouse BLE Discovery Payload constants
pub const BLE_MAGIC: &[u8] = b"POUSE";
pub const BLE_PROTOCOL_VERSION: u8 = 1;

/// Queries the local Bluetooth radio for its Classic BR/EDR hardware address (BD_ADDR).
/// Returns 6 bytes in standard big-endian format (MSB to LSB, e.g. [0xD0, 0x65, 0x78, 0xA1, 0x0E, 0x18]
/// corresponding to string "D0:65:78:A1:0E:18").
pub fn get_local_classic_bd_addr() -> Option<[u8; 6]> {
    use windows::Win32::Devices::Bluetooth::{
        BluetoothFindFirstRadio, BluetoothGetRadioInfo, BluetoothFindRadioClose,
        BLUETOOTH_FIND_RADIO_PARAMS, BLUETOOTH_RADIO_INFO,
    };
    use windows::Win32::Foundation::{CloseHandle, HANDLE};

    unsafe {
        let params = BLUETOOTH_FIND_RADIO_PARAMS {
            dwSize: std::mem::size_of::<BLUETOOTH_FIND_RADIO_PARAMS>() as u32,
        };
        let mut radio_handle = HANDLE::default();
        let find_handle = match BluetoothFindFirstRadio(&params, &mut radio_handle) {
            Ok(h) => h,
            Err(e) => {
                eprintln!("[BLE] BluetoothFindFirstRadio failed: {:?}", e);
                return None;
            }
        };

        let mut info = BLUETOOTH_RADIO_INFO {
            dwSize: std::mem::size_of::<BLUETOOTH_RADIO_INFO>() as u32,
            ..Default::default()
        };

        let get_info_res = BluetoothGetRadioInfo(radio_handle, &mut info);
        let _ = CloseHandle(radio_handle);
        let _ = BluetoothFindRadioClose(find_handle);

        if get_info_res != 0 {
            eprintln!("[BLE] BluetoothGetRadioInfo failed with error code: {}", get_info_res);
            return None;
        }

        // Win32 BLUETOOTH_ADDRESS stores the 48-bit address in rgBytes[0..6] as little-endian (rgBytes[0] = LSB).
        // Standard network/MAC format is big-endian (byte 0 = MSB, e.g. D0, byte 5 = LSB, e.g. 18).
        let rg = info.address.Anonymous.rgBytes;
        // Check if rgBytes is all zeros
        if rg.iter().all(|&b| b == 0) {
            eprintln!("[BLE] Local radio returned all-zero BD_ADDR");
            return None;
        }

        // Reorder from little-endian (rgBytes[0] = LSB) to big-endian (byte 0 = MSB)
        let big_endian_addr = [rg[5], rg[4], rg[3], rg[2], rg[1], rg[0]];
        println!(
            "[BLE] Classic BD_ADDR discovered: {:02X}:{:02X}:{:02X}:{:02X}:{:02X}:{:02X}",
            big_endian_addr[0], big_endian_addr[1], big_endian_addr[2],
            big_endian_addr[3], big_endian_addr[4], big_endian_addr[5]
        );
        Some(big_endian_addr)
    }
}


pub struct BleAdvertiser {
    publisher: Option<BluetoothLEAdvertisementPublisher>,
}

impl BleAdvertiser {
    pub fn new() -> Self {
        Self { publisher: None }
    }

    /// Starts BLE advertisement in a non-blocking background loop.
    /// If BLE hardware is unavailable or publisher fails, logs error and returns gracefully without crashing.
    pub fn start(&mut self) {
        println!("[BLE] advertiser starting");

        let publisher = match BluetoothLEAdvertisementPublisher::new() {
            Ok(pub_obj) => pub_obj,
            Err(e) => {
                eprintln!("[BLE] publisher error: Failed to create publisher: {:?}", e);
                eprintln!("[BLE] adapter unavailable or unsupported on this system.");
                return;
            }
        };

        let mfr_data = match BluetoothLEManufacturerData::new() {
            Ok(mfr) => mfr,
            Err(e) => {
                eprintln!("[BLE] publisher error: Failed to create manufacturer data: {:?}", e);
                return;
            }
        };

        if let Err(e) = mfr_data.SetCompanyId(BLE_DEV_COMPANY_ID) {
            eprintln!("[BLE] publisher error: Failed to set company ID: {:?}", e);
            return;
        }

        // Query local Classic BD_ADDR
        let classic_bd_addr = get_local_classic_bd_addr().unwrap_or([0u8; 6]);

        // Payload format: MAGIC ("POUSE" - 5 bytes) + PROTOCOL_VERSION (0x01 - 1 byte) + Classic BD_ADDR (6 bytes big-endian)
        let writer = match DataWriter::new() {
            Ok(w) => w,
            Err(e) => {
                eprintln!("[BLE] publisher error: Failed to create DataWriter: {:?}", e);
                return;
            }
        };

        if let Err(e) = writer.WriteBytes(BLE_MAGIC) {
            eprintln!("[BLE] publisher error: Failed to write magic bytes: {:?}", e);
            return;
        }

        if let Err(e) = writer.WriteByte(BLE_PROTOCOL_VERSION) {
            eprintln!("[BLE] publisher error: Failed to write protocol version: {:?}", e);
            return;
        }

        if let Err(e) = writer.WriteBytes(&classic_bd_addr) {
            eprintln!("[BLE] publisher error: Failed to write classic BD_ADDR bytes: {:?}", e);
            return;
        }
        println!(
            "[BLE] advertising payload includes Classic BD_ADDR: {:02X}:{:02X}:{:02X}:{:02X}:{:02X}:{:02X}",
            classic_bd_addr[0], classic_bd_addr[1], classic_bd_addr[2],
            classic_bd_addr[3], classic_bd_addr[4], classic_bd_addr[5]
        );

        let buffer = match writer.DetachBuffer() {
            Ok(buf) => buf,
            Err(e) => {
                eprintln!("[BLE] publisher error: Failed to detach buffer: {:?}", e);
                return;
            }
        };

        if let Err(e) = mfr_data.SetData(&buffer) {
            eprintln!("[BLE] publisher error: Failed to set manufacturer payload data: {:?}", e);
            return;
        }

        let adv = match publisher.Advertisement() {
            Ok(a) => a,
            Err(e) => {
                eprintln!("[BLE] publisher error: Failed to access Advertisement object: {:?}", e);
                return;
            }
        };

        let mfr_list = match adv.ManufacturerData() {
            Ok(list) => list,
            Err(e) => {
                eprintln!("[BLE] publisher error: Failed to access ManufacturerData list: {:?}", e);
                return;
            }
        };

        if let Err(e) = mfr_list.Append(&mfr_data) {
            eprintln!("[BLE] publisher error: Failed to append manufacturer data: {:?}", e);
            return;
        }

        // StatusChanged handler for diagnostic logging
        let status_token = publisher.StatusChanged(&TypedEventHandler::new(
            move |_sender: &Option<BluetoothLEAdvertisementPublisher>, args: &Option<BluetoothLEAdvertisementPublisherStatusChangedEventArgs>| {
                if let Some(status_args) = args {
                    let status = status_args.Status().unwrap_or_default();
                    let error = status_args.Error().unwrap_or_default();
                    println!("[BLE] status changed -> Status: {:?} | Error: {:?}", status, error);
                    if status == BluetoothLEAdvertisementPublisherStatus::Aborted {
                        eprintln!("[BLE] publisher aborted. Error code: {:?}", error);
                    }
                }
                Ok(())
            },
        ));

        if let Err(e) = status_token {
            eprintln!("[BLE] Warning: Failed to register StatusChanged listener: {:?}", e);
        }

        match publisher.Start() {
            Ok(_) => {
                let status = publisher.Status().unwrap_or_default();
                println!("[BLE] advertiser started (Status: {:?})", status);
                self.publisher = Some(publisher);
            }
            Err(e) => {
                eprintln!("[BLE] publisher error: Start() failed: {:?}", e);
            }
        }
    }

    pub fn stop(&mut self) {
        if let Some(pub_obj) = self.publisher.take() {
            println!("[BLE] advertiser stopping");
            let _ = pub_obj.Stop();
            println!("[BLE] advertiser stopped");
        }
    }
}

impl Drop for BleAdvertiser {
    fn drop(&mut self) {
        self.stop();
    }
}

/// Helper to launch BLE advertiser task in background thread
pub fn run_ble_advertiser_loop() {
    let mut advertiser = BleAdvertiser::new();
    advertiser.start();
    // Keep thread alive while process runs
    loop {
        std::thread::sleep(Duration::from_secs(3600));
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_classic_bd_addr_encode_decode_round_trip() {
        let expected_str = "D0:65:78:A1:0E:18";
        let bytes: [u8; 6] = [0xD0, 0x65, 0x78, 0xA1, 0x0E, 0x18];

        // Format to string (Network Big-Endian format)
        let formatted = format!(
            "{:02X}:{:02X}:{:02X}:{:02X}:{:02X}:{:02X}",
            bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5]
        );
        assert_eq!(formatted, expected_str);

        // Parse from string back to bytes
        let parsed_bytes: Vec<u8> = formatted
            .split(':')
            .map(|s| u8::from_str_radix(s, 16).expect("Valid hex byte"))
            .collect();
        assert_eq!(parsed_bytes.as_slice(), &bytes);
    }

    #[test]
    fn test_local_classic_bd_addr_query() {
        // Query local hardware radio - should succeed on Windows test machine with Bluetooth
        if let Some(addr) = get_local_classic_bd_addr() {
            println!("Local Classic BD_ADDR found: {:?}", addr);
            assert!(addr.iter().any(|&b| b != 0), "BD_ADDR should not be all zeros");
        }
    }
}

