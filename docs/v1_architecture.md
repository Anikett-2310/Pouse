# Pouse V1 — Technical Architecture

## Overview

Pouse V1 is a dual-transport, low-latency wireless input platform that
converts an Android smartphone into a Windows mouse and keyboard.

The system supports two independent transports — Wi-Fi (WebSocket) and
Bluetooth (RFCOMM) — arbitrated by a central `InputOwner` singleton on
the PC. Only one transport may inject OS input at a time.

---

## Component Architecture

```
┌──────────────────────────────────────────────────────────────────┐
│                         Android App (Flutter)                     │
│                                                                  │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │  Input Capture Layer                                     │   │
│  │  TouchpadGestureView  MotionController  KeyboardInputView│   │
│  └─────────────────────────────┬────────────────────────────┘   │
│                                │                                 │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │  Transport Manager (TransportManager)                    │   │
│  │                                                          │   │
│  │  ┌─────────────────────┐  ┌──────────────────────────┐  │   │
│  │  │  Wi-Fi Transport    │  │  Bluetooth Transport      │  │   │
│  │  │  WebSocket / JSON   │  │  BLE Scanner → RFCOMM    │  │   │
│  │  │  (active owner)     │  │  TOFU gate → JSON events │  │   │
│  │  └──────────┬──────────┘  └─────────────┬────────────┘  │   │
│  └─────────────┼───────────────────────────┼───────────────┘   │
└────────────────┼───────────────────────────┼───────────────────┘
                 │ Pouse Protocol (JSON)      │ Pouse Protocol (JSON)
                 │ TCP / WebSocket            │ Bluetooth RFCOMM
                 ▼                            ▼
┌──────────────────────────────────────────────────────────────────┐
│                     Rust PC Client (Windows)                      │
│                                                                  │
│  ┌─────────────────────┐  ┌────────────────────────────────┐    │
│  │  Wi-Fi WS Server    │  │  BLE Advertiser                │    │
│  │  tokio-tungstenite  │  │  (WinRT LE Publisher)          │    │
│  │  port 8081          │  │  payload: POUSE + BD_ADDR      │    │
│  └──────────┬──────────┘  └────────────────────────────────┘    │
│             │                                                    │
│  ┌──────────┴──────────────────────────────────────────────┐    │
│  │  RFCOMM Server                                          │    │
│  │  (WinRT RfcommServiceProvider)                          │    │
│  │  UUID: 7f9b841a-3e2c-4a90-8b1b-5e6f8a9c0d1e           │    │
│  │                                                         │    │
│  │  1. Accept socket                                       │    │
│  │  2. HELLO/ACK handshake                                 │    │
│  │  3. Await first authorized input event                  │    │
│  │  4. Acquire InputOwner on first authorized event        │    │
│  └──────────┬──────────────────────────────────────────────┘    │
│             │                                                    │
│  ┌──────────▼──────────────────────────────────────────────┐    │
│  │  InputOwner (singleton)                                 │    │
│  │                                                         │    │
│  │  - Tracks active transport (WiFi | Bluetooth | None)   │    │
│  │  - Rejects events from non-owner transport             │    │
│  │  - Releases held keys/buttons on transport switch      │    │
│  │  - Guards Remote Screen input lock                     │    │
│  └──────────┬──────────────────────────────────────────────┘    │
│             │                                                    │
│  ┌──────────▼──────────────────────────────────────────────┐    │
│  │  InputHandler (Windows OS)                              │    │
│  │  enigo / windows-sys SendInput                         │    │
│  └──────────┬──────────────────────────────────────────────┘    │
│             │                                                    │
│             ▼                                                    │
│         Windows Cursor / Keyboard / Scroll                       │
└──────────────────────────────────────────────────────────────────┘
```

---

## Key Modules

### Mobile (`mobile/`)

| File | Role |
|---|---|
| `lib/src/main_screen.dart` | Main UI, transport switcher |
| `lib/src/transports/transport_manager.dart` | Transport lifecycle management |
| `lib/src/transports/bluetooth_rfcomm_service.dart` | Bluetooth RFCOMM client + TOFU gate |
| `lib/src/transports/bluetooth_discovery_service.dart` | BLE scanner, BD_ADDR bridge |
| `android/.../BluetoothRfcommBridge.kt` | Kotlin RFCOMM socket implementation |
| `android/.../BluetoothBleScannerBridge.kt` | Kotlin BLE scanner bridge |
| `android/.../MainActivity.kt` | Android entry point + method channels |

### PC Client (`pc-client/src/`)

| File | Role |
|---|---|
| `main.rs` | Entry point: starts BLE, RFCOMM, Wi-Fi servers |
| `server.rs` | Wi-Fi WebSocket server (tokio-tungstenite) |
| `rfcomm_server.rs` | Bluetooth RFCOMM server, HELLO/ACK handshake, input gating |
| `ble_advertiser.rs` | BLE advertisement publisher, BD_ADDR bridge payload |
| `bluetooth_lifecycle.rs` | Windows BT discoverability save/restore on shutdown |
| `input_owner.rs` | Transport ownership arbitration singleton |
| `input.rs` | Windows OS input injection (enigo + SendInput) |
| `protocol.rs` | Pouse JSON event deserialization |
| `pairing.rs` | Wi-Fi QR pairing token management |
| `remote_screen/` | Remote screen host for secondary PC control |

---

## Technical Stack

### Mobile
- **Framework**: Flutter (Dart)
- **Networking**: `web_socket_channel` (Wi-Fi), Kotlin RFCOMM socket (Bluetooth)
- **BLE**: Kotlin `BluetoothLeScanner` → Dart FFI bridge
- **UI**: Custom `GestureDetector` touchpad with low-latency event callbacks

### PC Client
- **Runtime**: `tokio` (async multi-threaded I/O)
- **Wi-Fi Server**: `tokio-tungstenite` WebSocket
- **Bluetooth**: WinRT `RfcommServiceProvider`, `BluetoothLEAdvertisementPublisher`
- **Serialization**: `serde` + `serde_json`
- **OS Input**: `enigo` + Win32 `SendInput` via `windows-sys`

---

## Operational Flow

### Wi-Fi Connection
1. PC client starts WebSocket listener on `0.0.0.0:8081`.
2. User scans QR code or enters IP manually in Android app.
3. Android opens WebSocket and begins sending Pouse JSON events.
4. `InputOwner` is acquired on first event from Wi-Fi transport.

### Bluetooth Connection
1. PC starts BLE advertisement with payload: `POUSE` magic + protocol version + Classic BD_ADDR.
2. Android scans BLE, identifies Pouse beacon by magic bytes, extracts BD_ADDR.
3. Android initiates OS Bluetooth pairing (if not already paired).
4. Android checks TOFU trust store:
   - **Untrusted PC**: Shows "Trust this PC?" prompt. Input is gated until user accepts.
   - **Trusted PC**: Connects directly.
5. Android connects RFCOMM socket to discovered BD_ADDR and Pouse service UUID.
6. Android sends `POUSE_HELLO`; PC responds `POUSE_ACK`. Handshake complete.
7. Android begins sending authorized Pouse JSON events.
8. **PC acquires `InputOwner::Bluetooth` only on the first authorized input event** (not on socket connect or HELLO/ACK).
9. On disconnect: `InputOwner` is released if it was acquired; Windows Bluetooth state is restored.

---

## InputOwner Invariant

```
RFCOMM_CONNECTED  ≠  INPUT_AUTHORIZED
```

A raw Bluetooth socket connection (even after HELLO/ACK) does **not** grant
input ownership. Only the first authorized input event triggers acquisition.

This prevents a new/untrusted Bluetooth connection from displacing an active
Wi-Fi controller while the Android TOFU prompt is pending.

---

## Bluetooth Lifecycle Management

`BluetoothStateRestorer` (`bluetooth_lifecycle.rs`) queries and saves the
Windows Bluetooth discoverability and connectable state at startup, then
restores both on clean shutdown or `Ctrl+C`. This prevents Pouse from
permanently altering the user's Bluetooth system settings.

---

## POC Binaries

The `pc-client/src/bin/` directory contains independent proof-of-concept
binaries (`ble_poc_winrt.rs`, `rfcomm_poc_win32.rs`, `rfcomm_poc_winrt.rs`)
used during development. They are declared as separate `[[bin]]` targets in
`Cargo.toml` and are **not** compiled into the production `pouse-pc` binary.
