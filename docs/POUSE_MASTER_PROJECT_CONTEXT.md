# Pouse — Master Project Context & Technical Handover

**Version:** 1.0.0  
**Document Purpose:** Self-contained technical reference for any future AI assistant, developer,
or new conversation to understand the Pouse project in full — without access to prior chat history.  
**Authoritative Date:** 2026-10-02  
**Source of Truth:** The repository at `c:\dev\Pouse` (GitHub: `Anikett-2310/Pouse`). Treat
current source files as the final authority on all implementation details.

---

## Table of Contents

1. [What Pouse Is](#1-what-pouse-is)
2. [Why It Exists — Vision & Differentiator](#2-why-it-exists)
3. [Implemented Features (V1.0.0)](#3-implemented-features)
4. [Repository Layout](#4-repository-layout)
5. [System Architecture Overview](#5-system-architecture-overview)
6. [Transport 1 — Wi-Fi (WebSocket)](#6-transport-1--wi-fi-websocket)
7. [Transport 2 — Bluetooth (RFCOMM)](#7-transport-2--bluetooth-rfcomm)
8. [BLE Discovery Beacon](#8-ble-discovery-beacon)
9. [Pouse Protocol — Complete Event Reference](#9-pouse-protocol--complete-event-reference)
10. [InputOwner — Transport Arbitration](#10-inputowner--transport-arbitration)
11. [Security Model — Three Layers](#11-security-model--three-layers)
12. [Remote Screen Architecture](#12-remote-screen-architecture)
13. [Android Mobile App — Flutter Architecture](#13-android-mobile-app--flutter-architecture)
14. [Android Kotlin Native Bridges](#14-android-kotlin-native-bridges)
15. [Rust PC Client — Module Map](#15-rust-pc-client--module-map)
16. [Configuration & Persistence](#16-configuration--persistence)
17. [Display Brightness Subsystem](#17-display-brightness-subsystem)
18. [System Tray & UI](#18-system-tray--ui)
19. [Technology Stack Summary](#19-technology-stack-summary)
20. [Build System](#20-build-system)
21. [Release State & Production Prerequisites](#21-release-state--production-prerequisites)
22. [Planned Future Modes (Roadmap)](#22-planned-future-modes-roadmap)
23. [DO NOT BREAK — Critical Invariants](#23-do-not-break--critical-invariants)
24. [Quick File Reference](#24-quick-file-reference)
25. [Current Truth (AI Handoff Reference)](#25-current-truth-ai-handoff-reference)

---

## 1. What Pouse Is

**Pouse** ("Pocket Mouse") is a wireless mouse platform that converts an Android smartphone into
a multi-mode input device and desktop companion for Windows 10/11. It requires no extra hardware
beyond the phone the user already carries.

- **Android App** (Flutter/Dart + Kotlin): Captures touch, motion, camera, and gesture input and
  transmits it as structured JSON events over the chosen transport.
- **Windows PC Client** (Rust): Receives events, arbitrates transport ownership, and injects them
  into Windows via the OS input APIs (`SendInput`, `enigo`).

Two independent transport paths are supported simultaneously:

| Transport | Channel | Framing |
|---|---|---|
| **Wi-Fi (LAN)** | TCP → WebSocket | WebSocket text frames |
| **Bluetooth** | Classic RFCOMM | Newline-delimited UTF-8 |

Both transports carry the **same JSON Pouse Protocol**. The PC client's `InputOwner` singleton
ensures exactly one transport can inject OS input at a time.

---

## 2. Why It Exists

> **"I need a mouse, but I don't have one with me."**

The core problem: a person needs to control a PC but has no physical mouse. They always have a
smartphone. Pouse explores how far that existing device can replace dedicated mouse hardware.

Pouse is **not** claiming smartphone-as-mouse is a new idea. Existing touchpad apps exist. The
differentiator is the **progressive exploration of multiple input technologies** (touchscreen,
inertial, optical, computer vision) all sharing the same PC-side protocol and architecture. As new
input modes are added, the Windows client does not need to change.

---

## 3. Implemented Features

### Input Modes

| Mode | Technology | Input Method |
|---|---|---|
| **Touchpad** | Multi-touch GestureDetector | 85% normal Touchpad Surface + 15% right-side Scroll Zone. 1-finger drag = move; 1-tap = left click; 2-tap = right click; double-tap = double click; 1-hold+drag = drag; 2-finger swipe = scroll; pinch = zoom/magnify |
| **Motion** | Accelerometer + Gyroscope (`sensors_plus`) | Hold center button and tilt/wave phone to move cursor |
| **Touchless** | Front camera + MediaPipe on-device hand tracking | Wave to move; pinch thumb+index = click |
| **Gaming** | Virtual landscape gamepad UI | Analog stick, D-pad, action buttons |
| **Remote Screen** | H.264/DirectX screen capture + Wi-Fi stream | Live PC monitor mirror with direct touch interaction (dedicated top-level mode) |

### Connection Transports

| Feature | Wi-Fi | Bluetooth |
|---|---|---|
| Discovery | QR code scan or manual IP entry | BLE advertisement beacon + auto-discover |
| Auth | Cryptographic pair token (validated by PC; optional DPAPI-encrypted Wi-Fi password) | Trust-On-First-Use (TOFU) dialog |
| Network needed | Same LAN (reachability only; token required) | None (pure Bluetooth) |
| Auto-reconnect | Yes | Yes |
| Remote Screen | Yes (required for video stream) | Controls only; if Wi-Fi is available, video uses Wi-Fi; if Bluetooth-only, app shows Wi-Fi is required (Bluetooth is never used for video) |

### Utility Dock (All Modes)

A collapsible header bar present in input screens providing quick access to PC controls and shortcuts:

- **Volume**: Vol-, Mute, Vol+
- **Brightness**: Bright- (-10%), Bright+ (+10%) — WMI for laptops, DDC/CI for external monitors
- **Windows Search**: Win+S shortcut
- **Task View**: Win+Tab (triggers Windows Task View overview)
- **Show Desktop**: Win+D
- **App Switcher**: Alt+Tab
- **Taskbar Apps**: Win+T (`VK_LWIN` + `VK_T` — cycle/activate taskbar apps)
- **Gesture Cheatsheet**: Help dialog with all gesture shortcuts
- **Soft Keyboard**: Send typed text to PC

> **Architecture Clarification — Remote Screen Location**:
> - Remote Screen is a **dedicated top-level mode** selected via the main bottom navigation bar.
> - Remote Screen is **NOT inside Utilities**.
> - There is **NO Remote Screen shortcut in Utilities**.

---

## 4. Repository Layout

```
Pouse/
├── mobile/                          # Flutter Android application
│   ├── lib/src/
│   │   ├── main_screen.dart         # Root UI, navigation, transport UI wiring
│   │   ├── transports/              # Transport abstraction + implementations
│   │   │   ├── pouse_transport.dart         # PouseTransport abstract interface
│   │   │   ├── transport_manager.dart       # Transactional transport switcher
│   │   │   ├── bluetooth_rfcomm_service.dart # BT RFCOMM client + TOFU gate
│   │   │   ├── bluetooth_discovery_service.dart # BLE scanner + BD_ADDR bridge
│   │   │   ├── bluetooth_hid_service.dart   # HID transport (alternate BT mode)
│   │   │   └── touchless_camera_service.dart # MediaPipe camera service
│   │   ├── views/
│   │   │   ├── touchpad_view.dart           # Touchpad mode UI
│   │   │   ├── motion_view.dart             # Motion/gyro mode UI
│   │   │   ├── touchless_view.dart          # Touchless hand-tracking UI
│   │   │   └── remote_screen_spike_view.dart # Remote Screen viewer UI
│   │   ├── widgets/
│   │   │   ├── shared_utilities_dock.dart   # Collapsible utility dock
│   │   │   ├── shared_os_actions_panel.dart # OS/media action buttons
│   │   │   ├── shared_keyboard_panel.dart   # Soft keyboard
│   │   │   ├── shared_gaming_panel.dart     # Gaming mode gamepad
│   │   │   ├── shared_gesture_guide_dialog.dart # Gesture cheatsheet
│   │   │   ├── shared_pc_controls_panel.dart # PC control shortcuts
│   │   │   └── shared_zoom_panel.dart       # Zoom/magnifier control
│   │   ├── websocket_service.dart           # Wi-Fi WebSocket transport impl
│   │   ├── pairing_payload.dart             # QR code pairing payload model
│   │   └── qr_scanner_screen.dart           # QR code scanner screen
│   └── android/app/src/main/kotlin/com/pouse/app/
│       ├── MainActivity.kt                  # Flutter entry + method channel registration
│       ├── BluetoothRfcommBridge.kt         # RFCOMM socket implementation
│       ├── BluetoothBleScannerBridge.kt     # BLE scanner (discover Pouse PCs)
│       ├── BluetoothHidBridge.kt            # HID profile bridge
│       ├── TouchlessCameraBridge.kt         # MediaPipe camera + ML Kit bridge
│       ├── TouchlessCameraPlatformView.kt   # Flutter platform view (camera preview)
│       ├── RemoteScreenBridge.kt            # Remote Screen control channel
│       ├── RemoteScreenDecoder.kt           # H.264 decoder (MediaCodec)
│       ├── RemoteScreenSession.kt           # Session lifecycle management
│       ├── RemoteScreenPlatformView.kt      # Flutter platform view (decoded video)
│       ├── HandSkeletonOverlayView.kt       # Hand landmark overlay (Touchless)
│       ├── PouseSocketWriter.kt             # Thread-safe RFCOMM socket writer
│       └── WifiNetworkBinder.kt             # Wi-Fi network binding helper
├── pc-client/
│   ├── Cargo.toml                   # Rust dependencies (see section 19)
│   ├── src/
│   │   ├── main.rs                  # Entry point: startup sequence, shutdown
│   │   ├── lib.rs                   # Module declarations
│   │   ├── server.rs                # Wi-Fi WebSocket server (tokio-tungstenite)
│   │   ├── rfcomm_server.rs         # BT RFCOMM server + handshake + latency stats
│   │   ├── rfcomm.rs                # RFCOMM utility helpers
│   │   ├── ble_advertiser.rs        # BLE advertisement publisher
│   │   ├── bluetooth_lifecycle.rs   # Save/restore Windows BT discoverability state
│   │   ├── input_owner.rs           # Transport ownership arbitration singleton
│   │   ├── input.rs                 # Windows input injection (enigo + SendInput)
│   │   ├── protocol.rs              # PouseEvent enum — JSON serde
│   │   ├── pairing.rs               # QR pair token generation and persistence
│   │   ├── config.rs                # AppConfig — JSON persistence, DPAPI encryption
│   │   ├── display.rs               # Brightness control (WMI + DDC/CI)
│   │   ├── magnifier.rs             # Windows Magnifier API control
│   │   ├── tray.rs                  # Win32 system tray icon + context menu
│   │   ├── ui/                      # Preferences window and QR display
│   │   ├── remote_screen/
│   │   │   ├── mod.rs               # Remote screen module root
│   │   │   ├── host.rs              # RemoteScreenHost singleton — session management
│   │   │   ├── capture.rs           # WgcCapturer — Windows Graphics Capture
│   │   │   ├── encoder.rs           # MediaFoundationEncoder — H.264 hardware encoding
│   │   │   ├── annexb.rs            # H.264 Annex B bitstream processing
│   │   │   └── video_processor.rs   # GPU frame processing pipeline
│   │   └── bin/                     # Dev-only POC binaries (NOT in production build)
├── protocol/
│   └── PROTOCOL.md                  # Pouse Protocol specification (canonical reference)
├── docs/
│   ├── POUSE_MASTER_PROJECT_CONTEXT.md  # This document
│   ├── v1_architecture.md           # Technical architecture diagrams
│   ├── security_model.md            # Security model and threat analysis
│   ├── v1_requirements.md           # V1 product requirements
│   ├── user_guide.md                # End-user installation and usage guide
│   └── troubleshooting.md           # Diagnostics guide
├── scripts/
│   └── sign_windows.ps1             # Authenticode signing script (future use)
├── tests/
│   └── README.md                    # Integration test notes
├── PROJECT.md                       # Original project vision and roadmap
└── README.md                        # Public-facing README
```

---

## 5. System Architecture Overview

```
+------------------------------------------------------------------+
|                      Android App (Flutter)                        |
|                                                                   |
|  +------------------------------------------------------------+  |
|  |  Input Capture Layer                                       |  |
|  |  TouchpadView  MotionView  TouchlessView  GamingPanel      |  |
|  +----------------------------+-------------------------------+  |
|                               | PouseTransport API               |
|  +----------------------------v-------------------------------+  |
|  |  TransportManager (owns exactly ONE active transport)      |  |
|  |  +---------------------+  +----------------------------+  |  |
|  |  |  WebSocketService   |  |  BluetoothRfcommService    |  |  |
|  |  |  (Wi-Fi transport)  |  |  (BT transport + TOFU gate)|  |  |
|  |  +---------+-----------+  +-----------+----------------+  |  |
|  +------------|---------------------------------|--------------+  |
+---------------|---------------------------------|------------------+
                |  JSON over WebSocket            |  JSON over RFCOMM
                |  (TCP port 8081)                |  (UUID: 7f9b841a-...)
                v                                 v
+------------------------------------------------------------------+
|                     Rust PC Client (Windows)                      |
|                                                                   |
|  +---------------------+  +--------------------------------+      |
|  |  Wi-Fi WS Server    |  |  BLE Advertiser               |      |
|  |  tokio-tungstenite  |  |  (WinRT LE Publisher)         |      |
|  |  port 8081          |  |  payload: POUSE + BD_ADDR     |      |
|  +---------+-----------+  +--------------------------------+      |
|            |                                                      |
|  +---------+--------------------------------------------------+  |
|  |  RFCOMM Server (WinRT RfcommServiceProvider)               |  |
|  |  UUID: 7f9b841a-3e2c-4a90-8b1b-5e6f8a9c0d1e              |  |
|  |  1. Accept socket  2. HELLO/ACK  3. Await authorized      |  |
|  +---------+--------------------------------------------------+  |
|            |                                                      |
|  +---------+--------------------------------------------------+  |
|  |  InputOwner (singleton, Mutex-protected)                   |  |
|  |  - Tracks active transport: WiFi | Bluetooth | None        |  |
|  |  - Rejects events from non-owner                           |  |
|  |  - Releases held keys/buttons on transport switch          |  |
|  |  - Guards Remote Screen input lock                         |  |
|  +---------+--------------------------------------------------+  |
|            |                                                      |
|  +---------+--------------------------------------------------+  |
|  |  InputHandler (enigo + Win32 SendInput)                    |  |
|  +---------+--------------------------------------------------+  |
|            |                                                      |
|            v                                                      |
|        Windows Cursor / Keyboard / Scroll / Media                |
+------------------------------------------------------------------+
```

---

## 6. Transport 1 — Wi-Fi (WebSocket)

### PC Client Side (server.rs)

- Binds `TcpListener` on `0.0.0.0:<port>` (default **8081**, configurable in preferences).
- Uses `tokio-tungstenite` for async WebSocket upgrade.
- Each accepted connection is spawned as a separate `tokio` task.
- URL path routing on WebSocket upgrade:
  - `/` or any non-`/screen` path: `handle_input_connection()` — normal Pouse JSON event stream.
  - `/screen?token=<token>`: `handle_video_connection()` — Remote Screen video stream.
- `TCP_NODELAY` is set on all sockets for minimum latency.
- A `tokio::sync::broadcast` channel (`VIDEO_BROADCAST`, capacity 2) delivers H.264 frames from
  the encoder to any active `/screen` WebSocket connections.
- Input ownership is acquired from `InputOwner` on the **first authorized event** received
  (not on WebSocket connect).

### Connection Flow

1. PC prints pairing info and QR code to console on startup.
2. Android scans QR and decodes `PairingPayload` JSON:
   ```json
   {
     "type": "pouse_pair", "version": 1,
     "name": "MY-PC", "host": "192.168.1.x", "port": 8081,
     "protocolVersion": 1,
     "pairToken": "<32-hex-char token>",
     "capabilities": ["touchpad","motion","touchless","screen"]
   }
   ```
3. Android opens WebSocket to `ws://<host>:<port>` and provides the pair token to authorize the session. Same-LAN reachability alone only provides network transport connectivity; the PC validates the pair token before accepting input.
4. If the PC has `requireWifiPassword = true`, Android must also provide the configured Wi-Fi password. The PC decrypts its DPAPI-encrypted stored password (`CryptUnprotectData`) and compares.

### Pairing Token (pairing.rs)

- 128-bit random cryptographic token generated using `BCryptGenRandom` (Windows CNG).
- Stored as an application pairing credential in `%APPDATA%\Pouse\config.json` under `security.pairToken` on the PC and in `SharedPreferences` on Android (not encrypted with DPAPI).
- Displayed redacted in logs: `"4f9a...****"`.
- Android sends the token with connections to authenticate pairing identity.
- Regenerated via `--reset-pairing` CLI flag or "Reset Pairing Token" in preferences.

---

## 7. Transport 2 — Bluetooth (RFCOMM)

### Bluetooth Architecture Summary

```
PC (Rust)                                    Android (Flutter + Kotlin)
-----------------------------------------    -----------------------------------------
BleAdvertiser                                BluetoothBleScannerBridge.kt
  WinRT BluetoothLEAdvertisementPublisher      BluetoothLeScanner (Android API)
  payload: POUSE magic + BD_ADDR               scans for POUSE_COMPANY_ID = 0xFFFF
                                               extracts Classic BD_ADDR from payload
                                             BluetoothRfcommService.dart
RfcommServer (rfcomm_server.rs)                BluetoothRfcommBridge.kt
  UUID: 7f9b841a-3e2c-4a90-8b1b-5e6f8a9c0d1e  connects RFCOMM socket to BD_ADDR
  WinRT RfcommServiceProvider                  sends POUSE_HELLO\n
  <- POUSE_HELLO                             TOFU check (dialog or silent pass)
  -> POUSE_ACK                           ->  sends JSON events only if trusted
  awaits first authorized input event
  InputOwner::Bluetooth acquired on first event
```

### RFCOMM Handshake Protocol

Over the raw RFCOMM socket (before any JSON events):

```
Android -> PC:   POUSE_HELLO\n
PC -> Android:   POUSE_ACK\n
```

This confirms both ends are running Pouse. The PC does **not** acquire `InputOwner` at this point.

### BufferedRfcommReader (Performance)

The early implementation called `LoadAsync(1)` per byte, causing 50-250 ms overhead per event.
The production implementation uses `BufferedRfcommReader`:

- Issues a single `LoadAsync(256)` to fill a local byte buffer.
- Scans the buffer for newline `\n` in memory.
- Only refills when the buffer is exhausted.
- Result: per-event read latency reduced from 50-250 ms to under 1 ms.

### RFCOMM Latency Statistics

`rfcomm_server.rs` maintains `RfcommLatencyStats`:

- Records receive-to-inject latency in microseconds for every event.
- Reports aggregated statistics (avg, p50, p95, p99, max) every **5 seconds** to the console.
- Stats include: total events, move events, event rate, rx_to_inject_us, and optional end-to-end ms.

### Service UUID

Fixed Pouse RFCOMM service UUID: `7f9b841a-3e2c-4a90-8b1b-5e6f8a9c0d1e`

This UUID is registered in both `rfcomm_server.rs` and `BluetoothRfcommBridge.kt`.

---

## 8. BLE Discovery Beacon

The PC advertises a BLE manufacturer data payload so the Android app can discover the PC without
the user needing to know the PC's IP address or Classic Bluetooth address.

### BLE Advertisement Payload Format

| Offset | Size | Value |
|---|---|---|
| 0 | 5 bytes | ASCII magic: `POUSE` |
| 5 | 1 byte | Protocol version: `0x01` |
| 6 | 6 bytes | Classic BR/EDR BD_ADDR (big-endian) |

### BLE Company ID

`0xFFFF` — Bluetooth SIG reserved for **development/testing only**.

> **CRITICAL DISTRIBUTION BLOCKER**: `0xFFFF` is strictly for development and testing and must **never** be represented as a production or public Bluetooth SIG identity. It is a current external public-distribution blocker for the BLE advertisement mechanism and MUST be replaced with an officially registered Bluetooth SIG Company Identifier prior to any public distribution. The constant is defined in:
> - `pc-client/src/ble_advertiser.rs`: `BLE_DEV_COMPANY_ID`
> - `mobile/android/app/src/main/kotlin/com/pouse/app/BluetoothBleScannerBridge.kt`: `POUSE_COMPANY_ID`

### BD_ADDR Discovery

`ble_advertiser.rs::get_local_classic_bd_addr()` discovers the PC's Classic BD_ADDR:

1. **Primary**: WinRT `BluetoothAdapter::GetDefaultAsync()` then `BluetoothAddress()`.
2. **Fallback**: Win32 `BluetoothFindFirstRadio` + `BluetoothGetRadioInfo`.
3. Returns `None` if no non-zero BD_ADDR can be obtained (Bluetooth unavailable).

### Bluetooth State Management (bluetooth_lifecycle.rs)

`BluetoothStateRestorer` saves the Windows Bluetooth discoverability and connectable state at
startup and restores both on clean shutdown (including Ctrl+C). This prevents Pouse from
permanently altering the user's system Bluetooth settings.

---

## 9. Pouse Protocol — Complete Event Reference

All events are JSON objects with a mandatory `"event"` string field.

- **Wi-Fi**: Sent as WebSocket text frames.
- **Bluetooth**: Sent as newline-terminated (`\n`) UTF-8 lines over RFCOMM.

The Rust enum `PouseEvent` in `protocol.rs` is the authoritative deserialization source.
Tag field is `"event"`, all event names are `SCREAMING_SNAKE_CASE`.

### Pointer / Mouse Events

| Event | JSON | Description |
|---|---|---|
| `MOVE` | `{"event":"MOVE","dx":12.5,"dy":-4.2}` | Relative cursor displacement (float). Optional `"t"` field: Android-side timestamp in ms for e2e latency tracking. |
| `ABS_MOVE` | `{"event":"ABS_MOVE","x":0.25,"y":0.75}` | Absolute cursor position as normalized [0,1] fractions of screen size. Used by Remote Screen touch. |
| `LEFT_CLICK` | `{"event":"LEFT_CLICK"}` | Single tap |
| `RIGHT_CLICK` | `{"event":"RIGHT_CLICK"}` | Two-finger tap |
| `DOUBLE_CLICK` | `{"event":"DOUBLE_CLICK"}` | Double tap |
| `BUTTON_DOWN` | `{"event":"BUTTON_DOWN","button":"left"}` | Drag start. `button`: `"left"` or `"right"` |
| `BUTTON_UP` | `{"event":"BUTTON_UP","button":"left"}` | Drag end |
| `SCROLL` | `{"event":"SCROLL","dx":0.0,"dy":15.0}` | Two-finger scroll. `dy` positive = scroll down |
| `ZOOM` | `{"event":"ZOOM","scale":1.12}` | Pinch zoom. `scale > 1.0` = zoom in |
| `SYSTEM_MAGNIFY` | `{"event":"SYSTEM_MAGNIFY","scale":2.5}` | Windows Magnifier API control |

### Keyboard / Text Events

| Event | JSON | Description |
|---|---|---|
| `TEXT_INPUT` | `{"event":"TEXT_INPUT","text":"Hello"}` | UTF-8 string injected via `enigo` |
| `KEY_PRESS` | `{"event":"KEY_PRESS","key":"enter"}` | Special key: `enter`, `backspace`, `space`, `tab`, `escape` |
| `KEY_DOWN` | `{"event":"KEY_DOWN","key":"ctrl"}` | Key held down (for combos) |
| `KEY_UP` | `{"event":"KEY_UP","key":"ctrl"}` | Key released |

### Gesture-Mapped Events

| Event | Trigger |
|---|---|
| `TWO_FINGER_BROWSER_BACK` | 2-finger swipe left |
| `TWO_FINGER_BROWSER_FORWARD` | 2-finger swipe right |
| `THREE_FINGER_UP` | 3-finger swipe up — Task View (Win+Tab) |
| `THREE_FINGER_DOWN` | 3-finger swipe down — Show Desktop (Win+D) |
| `THREE_FINGER_LEFT` | 3-finger swipe left — Prev virtual desktop |
| `THREE_FINGER_RIGHT` | 3-finger swipe right — Next virtual desktop |
| `FOUR_FINGER_LEFT` | 4-finger swipe left — Prev app (Alt+Shift+Tab) |
| `FOUR_FINGER_RIGHT` | 4-finger swipe right — Next app (Alt+Tab) |

### OS Utility Events

| Event | Action |
|---|---|
| `VOLUME_UP` | Media Volume+ VK |
| `VOLUME_DOWN` | Media Volume- VK |
| `VOLUME_MUTE` | Media Mute VK |
| `BRIGHTNESS_UP` | +10% brightness (WMI or DDC/CI) |
| `BRIGHTNESS_DOWN` | -10% brightness (WMI or DDC/CI) |
| `WINDOWS_SEARCH` | Win+S (Windows Search) |
| `TASKBAR_APPS` | Win+T (`VK_LWIN` + `VK_T` — cycle/activate taskbar apps) |

> **Keybinding Clarification — Task View vs. Taskbar Apps**:
> - **Task View** = `Win+Tab` (overview of virtual desktops & open windows; triggered by 3-finger swipe up or OS actions panel).
> - **Taskbar Apps** = `Win+T` (focuses and cycles through applications pinned to the Windows taskbar).
> - The actual PC client implementation in `pc-client/src/input.rs` uses `VK_LWIN` + `VK_T` (`VIRTUAL_KEY(0x54)`). These two actions are completely distinct and must never be confused.

### Gaming Event

| Event | JSON | Description |
|---|---|---|
| `GAME_INPUT` | `{"event":"GAME_INPUT","dx":0.5,"dy":-0.3}` | Normalized axis (-1.0 to +1.0) |

### Keep-Alive

| Event | Direction | Description |
|---|---|---|
| `PING` | Android to PC | Sent periodically to detect drops |
| `PONG` | PC to Android | Response to PING |

> **Critical**: `PING`/`PONG` do **NOT** trigger `InputOwner` acquisition over Bluetooth.
> Only substantive input events (cursor, click, scroll, keyboard, etc.) cause ownership transfer.

### Remote Screen Control Events (WebSocket /screen path only)

| Event | Direction | Description |
|---|---|---|
| `AUTH` | Android to PC | `{"event":"AUTH","token":"<pair_token>"}` — authenticate for screen session |
| `AUTH_OK` | PC to Android | `{"event":"AUTH_OK","status":"authenticated"}` |
| `START_SCREEN` | Android to PC | Request to begin screen capture and streaming |
| `SCREEN_METADATA` | PC to Android | `{"event":"SCREEN_METADATA","width":1920,"height":1080,"orientation":"landscape","sessionToken":"sess_..."}` |
| `RESUME_SCREEN` | Android to PC | Reconnect with `{"event":"RESUME_SCREEN","sessionToken":"sess_..."}` |
| `RESUME_OK` | PC to Android | Resume accepted |
| `STOP_SCREEN` | Android to PC | Stop capture session |
| `STOP_SCREEN_OK` | PC to Android | Capture stopped |
| `REQUEST_KEYFRAME` | Android to PC | Force H.264 IDR keyframe |
| `INPUT_BLOCKED` | PC to Android | Input rejected (reason in `"reason"` field) |
| `SESSION_BUSY` | PC to Android | Another session is active |
| `SESSION_EXPIRED` | PC to Android | Session token invalid/expired |
| `ERROR` | PC to Android | `{"event":"ERROR","code":"...","message":"..."}` |

### Error Handling

- The PC client ignores unknown or malformed JSON events and logs a debug warning.
- Unknown events do **not** close the connection.
- Events received over Bluetooth before `POUSE_HELLO`/before Android TOFU authorization are
  silently discarded.

---

## 10. InputOwner — Transport Arbitration

`InputOwner` is a global singleton (`OnceLock<InputOwner>` in `input_owner.rs`) that ensures
exactly one transport can inject OS input at any time.

### State

```rust
pub struct InputOwner {
    handler: Mutex<Option<InputHandler>>,           // The shared input injection engine
    active_transport: Mutex<Option<TransportType>>, // WiFi | Bluetooth | None
}
```

### Ownership Rules

1. **Acquisition**: When a transport sends the first authorized input event and no owner exists,
   ownership is granted silently. If a different transport was owner, the previous owner's held
   keys/buttons are released first, then ownership switches.
2. **Rejection**: If transport B sends an event while transport A owns input, B's event is rejected
   and logged. No state changes.
3. **Release**: When a transport disconnects, it calls `InputOwner::release(transport)`. Held
   keys/buttons are released.
4. **Remote Screen Guard**: `InputOwner::handle_event()` also checks
   `RemoteScreenHost::can_process_input(peer_addr)` before dispatching. If Remote Screen has an
   active session and the peer is not the owning Remote Screen client, input is blocked.

### The Critical Invariant

```
RFCOMM_CONNECTED  !=  INPUT_AUTHORIZED
```

A Bluetooth RFCOMM connection that has completed `POUSE_HELLO`/`POUSE_ACK` does **not** hold
`InputOwner`. The PC only acquires `InputOwner::Bluetooth` when the **first authorized Pouse
input event** arrives. This is the defense-in-depth partner to the Android-side TOFU gate.

---

## 11. Security Model — Three Layers

### Layer 1 — OS Bluetooth Pairing (BR/EDR)

Standard Windows and Android Bluetooth passkey/PIN pairing (enforced by the OS before any RFCOMM
connection can be established). Prevents unknown, unpaired devices from connecting.

**Limitation**: Pairing authenticates the hardware device, not the app running on it.

### Layer 2 — Pouse TOFU Authorization (Android Application Layer)

On the Android side, `BluetoothRfcommService` gates all event sending with a TOFU trust check:

- **First connection to a new PC**: The Android UI shows a dialog:
  `"Trust PC <BD_ADDR>?"` with **Trust & Authorize** / **Reject** options.
  - **Trust**: Trust record is saved to `SharedPreferences`, keyed by the PC's Classic BD_ADDR.
    JSON events begin flowing.
  - **Reject**: Connection is torn down immediately. No events are ever sent.
- **Subsequent connections to a trusted PC**: Trust check passes silently.
- **Revocation**: User can tap "Forget Device" in the app's connection sheet.

**Trust identity**: Classic BD_ADDR (permanent hardware MAC of the Windows Bluetooth radio).
Stable across BLE advertisement restarts and RFCOMM reconnects.

**Security Scope**: Bluetooth security relies strictly on OS-level pairing (Layer 1) + Pouse TOFU confirmation (Layer 2) + deferred InputOwner acquisition on the PC (Layer 3). No cryptographic mutual authentication exists for Bluetooth beyond those layers. BD_ADDR spoofing after trust grant is not addressed in V1.

### Layer 3 — Deferred InputOwner Acquisition (PC-Side Gate)

Even if a Bluetooth connection completes `POUSE_HELLO`/`POUSE_ACK`, the PC does not acquire
`InputOwner` until the first authorized input event arrives (see section 10). This is a second,
independent guard: if the Android TOFU dialog is pending, no events are sent, so the PC never
acquires ownership — even if the RFCOMM handshake completed.

### Wi-Fi Security Model

Same-LAN reachability provides **only network transport connectivity**, NOT application authorization. Pouse enforces application-layer security through the following mechanisms:

1. **Cryptographic Pair Token**:
   - On initial setup, the PC generates a 128-bit random pairing token via Windows CNG (`BCryptGenRandom`).
   - The token is transmitted out-of-band via the PC's pairing QR code and scanned by the Android app.
   - The pair token is an application pairing credential stored in Pouse configuration (`%APPDATA%\Pouse\config.json`) on Windows and in Android pairing state (`SharedPreferences`). It is validated by the PC on WebSocket connection before accepting input.
   - Phones lacking a valid pair token are rejected; same-LAN presence alone never grants application authorization.
   - *Note on credential storage*: The pair token is an application credential stored in configuration and is NOT encrypted with DPAPI (do not refer to it as DPAPI-protected).

2. **Optional Wi-Fi Password Gate**:
   - Users can enable `requireWifiPassword = true` in PC preferences as an additional gate.
   - On Windows, this password is encrypted at rest using Windows DPAPI (`CryptProtectData`) in `config.json` under `wifiPasswordEncrypted`.
   - When enabled, the Android client must supply this password in addition to the pair token to authorize input.

### Threat Model Table

| Threat | L1 (OS Pairing) | L2 (TOFU) | L3 (Deferred Owner) |
|---|---|---|---|
| Unknown device RFCOMM connect | Blocked | — | — |
| Paired phone silently injects input | — | TOFU prompt | — |
| Untrusted BT displaces active Wi-Fi | — | Android gate | Deferred InputOwner |
| Malicious app on trusted paired phone | — | Per-BD_ADDR trust | — |
| BD_ADDR spoofing after trust grant | Not addressed | Not addressed | — |

---

## 12. Remote Screen Architecture

Remote Screen streams the PC's primary monitor to the Android phone at up to 60 FPS using H.264
hardware encoding over the Wi-Fi WebSocket connection.

### PC-Side Pipeline

```
Primary Monitor
     |
     v
WgcCapturer (capture.rs)
  Windows Graphics Capture (WGC) API
  D3D11 hardware device, B8G8R8A8 pixel format
  Direct3D11CaptureFramePool (capacity: 2 frames)
  GraphicsCaptureSession -> StartCapture()
     |  ID3D11Texture2D frames
     v
GpuVideoProcessor (video_processor.rs)
  GPU-side format conversion / scaling
     |
     v
MediaFoundationEncoder (encoder.rs)
  Windows Media Foundation hardware H.264 encoder
  Low-latency mode (CODECAPI_AVLOW_LATENCY_MODE)
  No B-frames
  Force IDR keyframe on REQUEST_KEYFRAME event
  AnnexBProcessor strips MF container headers -> raw Annex B NAL units
     |  Vec<u8> encoded frames
     v
VIDEO_BROADCAST (server.rs)
  tokio::sync::broadcast channel (capacity: 2)
  Latest-frame-only delivery (old frames dropped)
     |
     v
WebSocket /screen connection
  Binary WebSocket frames sent to Android
```

### Android-Side Pipeline

```
WebSocket /screen connection
     |  Binary H.264 Annex B data
     v
RemoteScreenSession.kt
  Accumulates NAL units
     |
     v
RemoteScreenDecoder.kt
  Android MediaCodec H.264 hardware decoder
  Output surface: SurfaceTexture
     |
     v
RemoteScreenPlatformView.kt
  Flutter Platform View renders decoded frames
     |
     v
remote_screen_spike_view.dart
  Touch input -> ABS_MOVE + click events -> back to PC
```

### Session Lifecycle

1. Android sends `AUTH` with pair token. PC validates and responds `AUTH_OK`.
2. Android sends `START_SCREEN`. PC starts WGC capture + MF encoder.
3. PC sends `SCREEN_METADATA` with resolution and a `sessionToken` (UUID).
4. PC streams binary H.264 frames over WebSocket.
5. Android touch events on the screen surface are sent back as `ABS_MOVE` + `LEFT_CLICK` events
   over the input WebSocket connection.
6. On reconnect, Android sends `RESUME_SCREEN` with the `sessionToken`. PC responds `RESUME_OK`
   without restarting the encoder. A 30-second reconnect window is maintained.
7. `STOP_SCREEN` or connection drop stops capture and releases the encoder.

### Wi-Fi Requirement & Network Behavior

Remote Screen video requires an active Wi-Fi connection. Bluetooth RFCOMM bandwidth (~1 Mbps typical) is insufficient for real-time H.264 video (5–15 Mbps required).

The network routing behavior is strictly defined:
- **Remote Screen video uses Wi-Fi**: Bluetooth is never used for Remote Screen video streaming.
- **Dual connection active**: If Bluetooth control is active and Wi-Fi is also available, video streaming uses Wi-Fi while Bluetooth remains active for input controls.
- **Bluetooth-only active**: If Bluetooth-only is active without Wi-Fi, the app displays that Wi-Fi is required for Remote Screen video.
- **No auto-fallback**: Bluetooth does not "auto-fall-back" to Wi-Fi; Wi-Fi is a strict prerequisite for video streaming.

### Known Limitations

- Only captures the primary monitor.
- Blocked by Windows Secure Desktop (UAC prompts) and Lock Screen (Win+L).
- Requires up-to-date GPU drivers for hardware encode/decode on both sides.

---

## 13. Android Mobile App — Flutter Architecture

### Entry Point

`main_screen.dart` is the root widget. It owns:

- A `WebSocketService` instance (Wi-Fi transport).
- A `BluetoothRfcommService` instance (BT transport).
- A `TransportManager` that owns both and exposes the currently active one.
- Bottom navigation: Touchpad / Motion / Touchless / Gaming / Remote Screen.
- Top-level `SharedUtilitiesDock` present in every mode.

### PouseTransport Interface (pouse_transport.dart)

Abstract class defining the complete event API:

```dart
abstract class PouseTransport {
  TransportType get type;           // wifi | bluetooth
  ConnectionStatus get status;
  ValueNotifier<ConnectionStatus> get statusNotifier;
  bool get isConnected;

  void sendMove(double dx, double dy);
  void sendAbsMove(double x, double y);
  void sendLeftClick();
  void sendRightClick();
  void sendDoubleClick();
  void sendButtonDown([String button = 'left']);
  void sendButtonUp([String button = 'left']);
  void sendScroll(double dx, double dy);
  void sendTextInput(String text);
  void sendKeyPress(String key);
  void sendKeyDown(String key);
  void sendKeyUp(String key);
  void sendTwoFingerBrowserBack();
  void sendTwoFingerBrowserForward();
  void sendThreeFingerUp(); void sendThreeFingerDown();
  void sendThreeFingerLeft(); void sendThreeFingerRight();
  void sendFourFingerLeft(); void sendFourFingerRight();
  void sendSystemMagnify(double scale);
  void sendVolumeUp(); void sendVolumeDown(); void sendVolumeMute();
  void sendBrightnessUp(); void sendBrightnessDown();
  void sendWindowsSearch(); void sendTaskbarApps();
  void releaseAll();
}
```

### TransportManager (transport_manager.dart)

Owns exactly one active transport at a time (a `ChangeNotifier`). Key property:

**Transactional switching**: When the user switches transports, the new transport is connected
first. Only when it reaches `connected` or `connecting` state does `TransportManager` call
`releaseAll()` on the old transport, disconnect it, and swap `_activeTransport`. If the new
transport fails to connect, the old transport is preserved.

### WebSocketService (websocket_service.dart)

- Implements `PouseTransport` for Wi-Fi.
- Uses `web_socket_channel` package.
- Serializes all events to JSON strings.
- Manages connection status via `ValueNotifier<ConnectionStatus>`.
- Handles automatic reconnection.

### BluetoothRfcommService (transports/bluetooth_rfcomm_service.dart)

- Implements `PouseTransport` for Bluetooth.
- Delegates socket operations to `BluetoothRfcommBridge.kt` via Flutter method channels.
- TOFU gate: before sending any events to a new PC, shows a trust dialog.
  - Trust record persisted in `SharedPreferences` (key: `tofu_trust_<BD_ADDR>`).
  - `sendEvent()` is a no-op until TOFU is confirmed.
- Sends `POUSE_HELLO\n` after socket connect; waits for `POUSE_ACK\n`.

### Touchpad Gesture Detection

`touchpad_view.dart` uses Flutter's `GestureDetector` with a custom pan/tap handler and a split surface layout:

- **Surface Layout**: 85% normal Touchpad Surface (flex: 85) + 15% right-side Scroll Zone (flex: 15) separated by a visual divider.
- **Pan (85% surface)**: `MOVE` events with microtask coalescing for smooth cursor movement.
- **Single tap**: `LEFT_CLICK`.
- **Double tap**: `DOUBLE_CLICK`.
- **Two-finger tap**: `RIGHT_CLICK`.
- **Hold + pan**: `BUTTON_DOWN` + `MOVE` + `BUTTON_UP` sequence (text selection / drag-and-drop).
- **Two-finger pan / Scroll Zone (15%)**: `SCROLL` events with configurable sensitivity and natural direction.
- **Pinch**: `SYSTEM_MAGNIFY`.

### Motion Mode (motion_view.dart)

- Uses `sensors_plus` package to access gyroscope + accelerometer.
- When the center sensor button is held, sensor deltas are accumulated and sent as `MOVE` events.
- Releases cursor on button release.

### Touchless Mode (touchless_view.dart)

- Uses `TouchlessCameraBridge.kt` which runs MediaPipe Hand Landmark Detection on the front camera.
- Hand skeleton overlay rendered via `HandSkeletonOverlayView.kt` (Android Platform View).
- Palm position maps to cursor `MOVE`; thumb+index pinch maps to `LEFT_CLICK`.

---

## 14. Android Kotlin Native Bridges

All bridges communicate with Dart via Flutter **MethodChannels** and **EventChannels**.

| File | Channel Name | Responsibility |
|---|---|---|
| `BluetoothRfcommBridge.kt` | `com.pouse.app/bluetooth_rfcomm` | RFCOMM socket connect/disconnect/send/receive; `PouseSocketWriter` for thread-safe writes |
| `BluetoothBleScannerBridge.kt` | `com.pouse.app/bluetooth_ble_scanner` | BLE scan using `POUSE_COMPANY_ID=0xFFFF`; extracts BD_ADDR from manufacturer payload |
| `BluetoothHidBridge.kt` | `com.pouse.app/bluetooth_hid` | Bluetooth HID profile (alternate BT transport mode) |
| `TouchlessCameraBridge.kt` | `com.pouse.app/touchless_camera` | Front camera preview; MediaPipe hand landmark inference; emits landmark coordinates to Dart |
| `RemoteScreenBridge.kt` | `com.pouse.app/remote_screen` | Control channel for Remote Screen session events |
| `RemoteScreenDecoder.kt` | Internal | MediaCodec H.264 decoder; feeds `SurfaceTexture` |
| `RemoteScreenSession.kt` | Internal | WebSocket frame accumulation to NAL unit delivery to decoder |
| `WifiNetworkBinder.kt` | `com.pouse.app/wifi_binder` | Android API >= 21 network binding to ensure Wi-Fi is used even if mobile data is active |
| `HandSkeletonOverlayView.kt` | Platform View | Draws hand landmark skeleton overlay on camera preview |
| `PouseSocketWriter.kt` | Internal | Thread-safe write queue for RFCOMM socket |

### MainActivity.kt

Registers all MethodChannels and Platform View factories on startup. No application logic lives
here; it only wires the Kotlin bridges to the Flutter engine.

### Android Permissions Required

```xml
<uses-permission android:name="android.permission.BLUETOOTH" />
<uses-permission android:name="android.permission.BLUETOOTH_ADMIN" />
<uses-permission android:name="android.permission.BLUETOOTH_SCAN" />
<uses-permission android:name="android.permission.BLUETOOTH_CONNECT" />
<uses-permission android:name="android.permission.CAMERA" />
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
```

---

## 15. Rust PC Client — Module Map

### main.rs — Startup Sequence

1. Initialize `ConfigManager` (load/migrate config); handle `--reset-pairing` flag.
2. `display::init_brightness_support()` — probe WMI / DDC/CI.
3. `InputOwner::global()` — initialize the global singleton.
4. `BluetoothStateRestorer::initialize()` — save current BT discoverability state.
5. Spawn **BLE advertiser** thread (background; `mpsc::channel` for shutdown).
6. Spawn **RFCOMM server** thread (background; `mpsc::channel` for shutdown).
7. Build `tokio::runtime::Builder::new_multi_thread()` runtime.
8. Spawn **Wi-Fi WebSocket server** task in the Tokio runtime.
9. Spawn **Ctrl+C handler** thread.
10. Run **system tray message loop** on the main thread (or wait on `shutdown_rx` in headless mode).

**Shutdown sequence** (on tray quit or Ctrl+C):

- Send stop to Tokio runtime (Wi-Fi server).
- Send stop to BLE advertiser thread; join.
- Send stop to RFCOMM server thread; join.
- `BluetoothStateRestorer::restore()` — restore saved BT state.

CLI flags: `--reset-pairing`, `--no-tray` / `--headless`.

### input.rs — Input Injection

Provides `InputDriver` trait and two implementations:

- **`EnigoDriver`**: Uses `enigo` crate for standard mouse/keyboard injection.
- **`SendInputDriver`**: Direct Win32 `SendInput` for special keys (arrows, `OEM_PLUS/MINUS`,
  volume/media VKs) that `enigo` does not handle or handles incorrectly.
- **`InputHandler`**: Wraps the active driver; dispatches `PouseEvent` to driver calls.
  Tracks held buttons for `release_all()` on transport switch.
- Compatible Input Mode (`config.compatible_input_mode`): Falls back to pure `SendInput` path
  for legacy applications that do not accept `enigo`-injected input.

### config.rs — Configuration

Config file: `%APPDATA%\Pouse\config.json`

```json
{
  "version": 1,
  "general": {
    "deviceName": "MY-PC",
    "port": 8081,
    "startWithWindows": false,
    "minimizeToTrayOnClose": true,
    "compatibleInputMode": false
  },
  "security": {
    "pairToken": "<32-hex>",
    "wifiPasswordEncrypted": null,
    "requireWifiPassword": false
  },
  "recentDevices": []
}
```

`ConfigManager` is a global singleton (`OnceLock<Arc<Mutex<ConfigManager>>>`). The
`wifiPasswordEncrypted` field is encrypted with Windows DPAPI (`CryptProtectData`).

Legacy: If `%APPDATA%\Pouse\pairing.json` exists (old format), `ConfigManager` migrates its
`pairToken` value into `config.json` on first launch.

---

## 16. Configuration & Persistence

| Item | Location | Notes |
|---|---|---|
| App config | `%APPDATA%\Pouse\config.json` | JSON; pair token, port, startup, DPAPI password |
| Legacy pairing | `%APPDATA%\Pouse\pairing.json` | Migrated on startup; safe to delete after migration |
| Android TOFU store | Android `SharedPreferences` | Key: `tofu_trust_<BD_ADDR>` = `true`/`false` |
| Android pair token | Android `SharedPreferences` | Stored after first successful QR scan |
| Windows startup | `HKCU\Software\Microsoft\Windows\CurrentVersion\Run` `Pouse` | Set/cleared by installer task or preferences toggle |
| Firewall rule | Windows Firewall (TCP 8081, Private) | Created by Inno Setup installer; removed on uninstall |

---

## 17. Display Brightness Subsystem

`display.rs` provides platform-adaptive brightness control with two backends:

| Backend | API | Target |
|---|---|---|
| **WMI** | PowerShell `Get-CimInstance WmiMonitorBrightness` + `WmiMonitorBrightnessMethods` | Internal laptop displays |
| **DDC/CI** | `dxva2.dll` — `GetNumberOfPhysicalMonitors`, `GetMonitorBrightness`, `SetMonitorBrightness` | External desktop monitors (DDC/CI must be enabled in monitor OSD) |
| **Unsupported** | — | USB adapters, virtual displays, monitors without DDC/CI |

`init_brightness_support()` probes WMI first, then DDC/CI. The result is stored in a global
atomic `BACKEND`. Brightness steps +-10%, clamped 10%-100%.

---

## 18. System Tray & UI

`tray.rs` implements a Win32 system tray icon:

- Creates a hidden message-only `HWND` (`PouseTrayMessageWindowClass`).
- Registers a notification icon via `Shell_NotifyIconW`.
- Handles `WM_TRAY_CALLBACK` messages (right-click, left-click).

**Tray Context Menu Items:**

| Item | Label | Action |
|---|---|---|
| `IDM_HEADER` | "Pouse PC Client v1.0.0" (disabled header) | — |
| `IDM_SHOW_QR` | "Show IP & QR Code" | Prints QR/IP to console |
| `IDM_PREFERENCES` | "Preferences..." | Opens preferences window |
| `IDM_CHECK_UPDATES` | "Check for Updates" | Opens GitHub Releases in browser |
| `IDM_QUIT` | "Quit Pouse" | Sends shutdown signal |

The preferences window (`ui/` module) allows editing: device name, port, start with Windows,
compatible input mode, Wi-Fi password requirement, recent devices list, and pairing token reset.

---

## 19. Technology Stack Summary

### Android (Mobile)

| Component | Technology |
|---|---|
| UI Framework | Flutter (Dart) — SDK `^3.13.4` |
| Wi-Fi Transport | `web_socket_channel ^3.0.1` |
| QR Scanner | `mobile_scanner ^6.0.0` |
| IMU Sensors | `sensors_plus ^6.0.0` |
| Storage | `shared_preferences ^2.3.2` |
| BT/Camera Bridges | Kotlin (Android platform code) |
| Hand Tracking | MediaPipe (via Kotlin bridge) |
| H.264 Decode | Android `MediaCodec` (hardware) |
| Application ID | `com.pouse.app` |

### Windows PC Client (Rust)

| Component | Crate / API |
|---|---|
| Async runtime | `tokio 1.40` (multi-threaded, all features) |
| WebSocket server | `tokio-tungstenite 0.26` |
| JSON | `serde 1.0` + `serde_json 1.0` |
| Mouse/keyboard | `enigo 0.3` + Win32 `SendInput` |
| QR code | `qr2term 0.3`, `qrcode 0.14` |
| BLE advertising | WinRT `BluetoothLEAdvertisementPublisher` |
| RFCOMM server | WinRT `RfcommServiceProvider` + `StreamSocketListener` |
| Screen capture | WinRT `Windows.Graphics.Capture` (WGC) |
| H.264 encoding | Win32 `Windows.Media.Foundation` (hardware MF encoder) |
| D3D11 | `Win32::Graphics::Direct3D11` (GPU pipeline) |
| OS input/crypto | `windows 0.58` crate (comprehensive feature set) |
| Edition | Rust 2024 |

---

## 20. Build System

### PC Client (Rust)

```powershell
# Development build
cargo build --bin pc-client

# Release build (production binary)
cargo build --release --bin pc-client
# Output: pc-client\target\release\pc-client.exe

# Run tests (36 passed, verified)
cargo test
```

POC binaries in `src/bin/` (`ble_poc_winrt.rs`, `rfcomm_poc_win32.rs`, `rfcomm_poc_winrt.rs`) are
declared as separate `[[bin]]` targets and are **not** part of the `pc-client` production binary.

### Android (Flutter)

```bash
cd mobile

# Get dependencies
flutter pub get

# Build debug APK
flutter build apk --debug

# Build release APK (uses production upload keystore via key.properties)
flutter build apk --release

# Run tests (156 passed, verified; flutter analyze: 0 issues)
flutter test
```

**Android signing**: `build.gradle.kts` reads `mobile/android/key.properties`. The current Pouse Android release configuration uses the production upload keystore, and the release APK was previously verified locally with `apksigner`. If `key.properties` is absent in developer environments, Gradle falls back to the debug keystore.

### Inno Setup Installer (Windows)

```powershell
# Prerequisites: Inno Setup (iscc.exe) in PATH
# Build release binary first, then:
iscc.exe /DAppVersion=1.0.0 pc-client\installer\pouse_setup.iss
# Output: pc-client\installer\Output\Pouse-Setup-v1.0.0.exe
```

### Windows Signing Infrastructure (scripts/sign_windows.ps1)

Windows Authenticode signing infrastructure is prepared. A PowerShell 5.1-compatible script (`scripts/sign_windows.ps1`) auto-detects `signtool.exe` from Windows SDK. Accepts `-CertPath`, `-CertPassword`, `-TimestampUrl` parameters. Signs both `pc-client.exe` and the Inno Setup installer (which also includes a `SignTool` directive). Current release artifacts are built but unsigned because no production Authenticode certificate is currently available; signing is prepared rather than complete or publicly signed.

---

## 21. Release State & Distribution Model

### Current Release State & Verification (as of 2026-10-02)

| Item | Status | Notes |
|---|---|---|
| PC Client binary | Built (`cargo build --release`); **unsigned** | Prepared for Authenticode signing; currently unsigned pending production certificate (triggers Windows SmartScreen) |
| Android APK | **Production-signed** (verified) | Built using production upload keystore (`mobile/android/key.properties`); verified locally with `apksigner` |
| Windows Authenticode | **Prepared (unsigned)** | `scripts/sign_windows.ps1` and Inno Setup `SignTool` integration prepared; unsigned pending production certificate |
| Windows installer | Built (`Pouse-Setup-v1.0.0.exe`) | `pouse_setup.iss` complete; unsigned pending production certificate |
| BLE Company ID | `0xFFFF` (**blocker**) | Reserved for **development/testing only**; current external public-distribution blocker for the BLE advertisement mechanism; must not be represented as production/public Bluetooth SIG identity |
| Application ID | `com.pouse.app` | Production identity, permanently configured |
| Flutter test suite | **156 passed** | Verified clean |
| Rust test suite | **36 passed** | Verified clean |
| Flutter analyze | **0 issues** | Verified clean |

### Intended Distribution Model

The intended distribution model for Pouse 1.0.0 is direct web download:

- **Intended User-Facing Web Destinations**:
  - Landing page: `https://pouse.app`
  - Download page: `https://pouse.app/download`
  *(Note: These represent the designated/intended distribution URLs for release; this documentation does not claim the website is already live).*

- **Primary User-Facing Download Artifacts**:
  1. **Windows Installer**: `Pouse-Setup-v1.0.0.exe` (direct installer download)
  2. **Android App**: `app-release.apk` (direct APK download)

- **Distribution Scope Clarifications**:
  - **Google Play is NOT required**: The project distribution model targets direct APK distribution from `https://pouse.app/download`. Google Play Store publishing is not required for the current intended distribution model.
  - **Underlying File Hosting**: GitHub Releases may be used as an underlying binary file host/CDN for release assets if appropriate, but is not presented as the primary user-facing destination.

### Production Release Prerequisites Checklist

1. **Bluetooth SIG Company Identifier**:
   - Current state: `0xFFFF` (development/testing only).
   - Requirement: `0xFFFF` is an external public-distribution blocker for BLE advertising. Obtain an officially allocated 16-bit Company ID from the Bluetooth SIG and replace `BLE_DEV_COMPANY_ID` in `pc-client/src/ble_advertiser.rs` and `POUSE_COMPANY_ID` in `mobile/android/.../BluetoothBleScannerBridge.kt`.

2. **Android Release Keystore & Verification**:
   - Current state: Complete. The production upload keystore is configured via `key.properties`, and the release APK was previously verified locally with `apksigner`. Direct APK download is ready; Google Play submission is not required for the current distribution model.

3. **Windows Authenticode Code Signing**:
   - Current state: Prepared but currently unsigned.
   - Requirement: Obtain an EV Authenticode certificate or Azure Trusted Signing account. Sign `pc-client.exe` and `Pouse-Setup-v1.0.0.exe` using `scripts/sign_windows.ps1` to prevent Windows SmartScreen warnings.

4. **Compile Production Installer**:
   - Run Inno Setup (`iscc.exe`) to produce the final signed `Pouse-Setup-v1.0.0.exe` installer package.

5. **Deploy Artifacts to Web Host**:
   - Upload the Windows installer and Android APK to `https://pouse.app/download`.

---

## 22. Planned Future Modes (Roadmap)

Sourced from `PROJECT.md` and `README.md`. Do **not** add features not listed here without
explicit instruction.

| Mode | Status | Technology |
|---|---|---|
| Touchpad | V1 Complete | Touchscreen (85% surface + 15% scroll zone) |
| Motion | V1 Complete | Accelerometer + Gyroscope |
| Touchless | V1 Complete | Camera + MediaPipe hand tracking |
| Gaming | V1 Complete | Virtual landscape gamepad |
| Remote Screen | V1 Complete | H.264/DirectX/WGC screen mirror (dedicated top-level mode) |
| Optical Surface Mouse | **DROPPED / NOT CURRENTLY PLANNED** | Rear camera + optical flow |

> **Roadmap Status — Optical Surface Mouse**:
> Optical Surface Mouse is **DROPPED / NOT CURRENTLY PLANNED**. It is no longer an active roadmap commitment or planned future mode.

**Explicitly NOT in scope** (from `PROJECT.md`):
- Cloud infrastructure, WebRTC, macOS/Linux support.
- Universal clipboard, power controls, PC system monitoring.
- Optical Surface Mouse (dropped).

---

## 23. DO NOT BREAK — Critical Invariants

These constraints encode design decisions that are load-bearing for security and correctness.
Violating any of them can cause security regressions, stuck inputs, or transport conflicts.

### INV-1: RFCOMM_CONNECTED is NOT INPUT_AUTHORIZED

Never acquire `InputOwner::Bluetooth` on RFCOMM socket connection, HELLO, or ACK. Ownership
must only be acquired on the **first authorized Pouse input event**. Changing this would allow
untrusted Bluetooth connections to seize the input channel before the Android TOFU dialog resolves.

### INV-2: PING/PONG Must NOT Acquire InputOwner

`PING` and `PONG` events must be explicitly excluded from the set of events that trigger
`InputOwner` acquisition on either transport. These are keep-alive messages, not input.

### INV-3: Held Keys/Buttons Must Be Released on Transport Switch

When `InputOwner` switches from transport A to B, `InputHandler::release_all()` must be called on
behalf of transport A before ownership transfers. Failure causes stuck mouse buttons or keys.

### INV-4: TOFU Gate is Android-Side Primary; PC-Side is Defense-in-Depth

The Android `BluetoothRfcommService` is the **primary** gate: `sendEvent()` is a no-op until TOFU
is confirmed. The PC-side deferred `InputOwner` is a **secondary** guard. Both must remain active.

### INV-5: Config File Contains No Plaintext Passwords

The `wifiPasswordEncrypted` field in `config.json` must always be DPAPI-encrypted. Never store or
log the raw Wi-Fi password. Never print or expose the `pairToken` in full (always use `redact_token()`).

### INV-6: BLE_DEV_COMPANY_ID = 0xFFFF Must Not Ship in Production

`0xFFFF` is reserved by the Bluetooth SIG for **development/testing only** and must never be represented as a production or public Bluetooth SIG identity. It is a current external public-distribution blocker for the BLE advertisement mechanism. Any production build distributed publicly must replace `BLE_DEV_COMPANY_ID` in `ble_advertiser.rs` and `POUSE_COMPANY_ID` in `BluetoothBleScannerBridge.kt` with an officially allocated Company Identifier.

### INV-7: Remote Screen Requires Wi-Fi

Never route H.264 video data over the Bluetooth RFCOMM transport. The bandwidth is insufficient and would degrade the RFCOMM event stream. Remote Screen video uses Wi-Fi exclusively; Bluetooth is never used for video streaming and there is no automatic fallback.

### INV-8: Single Active Transport Per Input Channel

`TransportManager` on the Android side and `InputOwner` on the PC side must both ensure only one
transport is dispatching input events at any time. Do not bypass either gate.

### INV-9: Android Application ID is com.pouse.app (Permanent)

Do not change the Android `applicationId`. Changing it would break existing installations.

### INV-10: POC Binaries Are Not Production

The binaries in `pc-client/src/bin/` (`ble_poc_winrt.rs`, `rfcomm_poc_win32.rs`,
`rfcomm_poc_winrt.rs`) are development proof-of-concept programs. They must not be compiled into
or included in the `pc-client` (pouse-pc) production binary.

---

## 24. Quick File Reference

| File | What It Does |
|---|---|
| `pc-client/src/main.rs` | Startup, thread orchestration, shutdown |
| `pc-client/src/server.rs` | Wi-Fi WebSocket server, /screen routing |
| `pc-client/src/rfcomm_server.rs` | RFCOMM server, HELLO/ACK, buffered reader, latency stats |
| `pc-client/src/ble_advertiser.rs` | BLE beacon publisher, BD_ADDR discovery |
| `pc-client/src/input_owner.rs` | Transport arbitration singleton |
| `pc-client/src/input.rs` | InputDriver trait, EnigoDriver, SendInputDriver, InputHandler |
| `pc-client/src/protocol.rs` | PouseEvent enum — complete event definitions |
| `pc-client/src/pairing.rs` | Pair token generation, PairingPayload, QR print |
| `pc-client/src/config.rs` | AppConfig, ConfigManager, DPAPI encrypt/decrypt |
| `pc-client/src/display.rs` | Brightness (WMI / DDC/CI) |
| `pc-client/src/bluetooth_lifecycle.rs` | BT state save/restore |
| `pc-client/src/tray.rs` | Win32 system tray icon and menu |
| `pc-client/src/remote_screen/host.rs` | RemoteScreenHost — session, auth, input permission |
| `pc-client/src/remote_screen/capture.rs` | WgcCapturer — Windows Graphics Capture |
| `pc-client/src/remote_screen/encoder.rs` | MediaFoundationEncoder — H.264 hardware encode |
| `pc-client/src/remote_screen/annexb.rs` | H.264 Annex B bitstream processor |
| `mobile/lib/src/main_screen.dart` | Root Flutter UI, navigation |
| `mobile/lib/src/transports/pouse_transport.dart` | PouseTransport abstract interface |
| `mobile/lib/src/transports/transport_manager.dart` | Transactional transport switching |
| `mobile/lib/src/transports/bluetooth_rfcomm_service.dart` | BT RFCOMM client + TOFU gate |
| `mobile/lib/src/transports/bluetooth_discovery_service.dart` | BLE scanner + BD_ADDR bridge |
| `mobile/lib/src/websocket_service.dart` | Wi-Fi WebSocket transport |
| `mobile/android/.../BluetoothRfcommBridge.kt` | RFCOMM socket (Kotlin) |
| `mobile/android/.../BluetoothBleScannerBridge.kt` | BLE scanner (Kotlin) |
| `mobile/android/.../TouchlessCameraBridge.kt` | MediaPipe hand tracking |
| `mobile/android/.../RemoteScreenDecoder.kt` | H.264 MediaCodec decoder |
| `protocol/PROTOCOL.md` | Canonical protocol specification |
| `docs/security_model.md` | Security model and threat analysis |
| `docs/v1_architecture.md` | Architecture diagrams |
| `pc-client/installer/pouse_setup.iss` | Inno Setup installer script |
| `scripts/sign_windows.ps1` | Authenticode signing script |
| `mobile/android/app/build.gradle.kts` | Android build config, signing logic |
| `mobile/pubspec.yaml` | Flutter dependencies |
| `pc-client/Cargo.toml` | Rust dependencies |

---

## 25. Current Truth (AI Handoff Reference)

```
CURRENT VERSION:
Pouse 1.0.0

CURRENT MOBILE ID:
com.pouse.app

CURRENT WIFI PORT:
8081

CURRENT RFCOMM UUID:
7f9b841a-3e2c-4a90-8b1b-5e6f8a9c0d1e

CURRENT BLE COMPANY ID:
0xFFFF — development/testing only

INPUTOWNER INVARIANT:
RFCOMM_CONNECTED != INPUT_AUTHORIZED

REMOTE SCREEN:
Top-level mode, Wi-Fi video only

PC CONTROLS:
Volume / Mute / Brightness / Windows Search

OS ACTIONS:
Task View / Show Desktop / Taskbar Apps / Previous App / Next App / existing OS actions

TASKBAR APPS:
Win+T

TOUCHPAD:
85% normal Touchpad Surface + 15% right-side Scroll Zone

ANDROID DISTRIBUTION:
Direct APK download

WINDOWS DISTRIBUTION:
Direct installer download

WINDOWS AUTHENTICODE:
Prepared but currently unsigned pending production certificate

OPTICAL SURFACE MOUSE:
Dropped / not currently planned
```

---

*End of Pouse Master Project Context — v1.0.0*
