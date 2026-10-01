# 🖱️ Pouse — Pocket Mouse

> Turn the smartphone you already carry into a mouse for your PC.

Pouse is a wireless mouse platform that uses an Android smartphone as a
multi-mode input device for Windows, requiring no extra hardware.

Instead of building four separate applications, Pouse uses a shared protocol
and a single Windows PC client while multiple transport layers and input
technologies deliver different experiences.

---

## 🎯 Vision

> **"I need a mouse, but I don't have one with me."**

Your smartphone is already in your pocket.  
Pouse explores how far that device can replace dedicated mouse hardware.

---

## ✨ V1.0.0 — Production Features

Pouse turns your Android smartphone into a multi-mode input device and desktop companion for Windows 10/11, supporting independent Wi-Fi and Bluetooth transports.

### Input Modes & Utilities
| Mode / Utility | Technology | Status |
|---|---|---|
| **Touchpad** | Touchscreen with microtask-coalesced smooth cursor | ✅ Active |
| **Motion** | Accelerometer + Gyroscope air mouse | ✅ Active |
| **Touchless** | Front camera MediaPipe hand-tracking gestures | ✅ Active |
| **Gaming** | Virtual landscape gamepad with analog stick & triggers | ✅ Active |
| **Remote Screen** | Real-time 60 FPS H.264/DirectX screen mirror & direct touch | ✅ Active |
| **Utility Dock** | Collapsible header with shortcuts, guide & gesture cheatsheet | ✅ Active |
| **Media & OS Actions** | Dedicated volume, screen brightness & Windows Search (Win+S) | ✅ Active |

### Connection Transports
| Feature | Wi-Fi (LAN) | Bluetooth (RFCOMM) |
|---|---|---|
| **Connection Method** | Instant QR code scan or manual IP | BLE discovery beacon → RFCOMM |
| **Network Requirement** | Same local Wi-Fi / LAN | Zero network required (Offline) |
| **Security Model** | Cryptographic pair token + DPAPI | Trust-On-First-Use (TOFU) prompt |
| **Input Ownership** | Deferred InputOwner acquisition | Deferred InputOwner acquisition |
| **Reconnection** | Automatic reconnect | Automatic reconnect |

### 📖 User Documentation
- **[User Setup Guide](docs/user_guide.md)** — Step-by-step installation, connection, gesture controls, and utility dock usage.
- **[Troubleshooting Guide](docs/troubleshooting.md)** — Diagnostics for discovery, firewalls, Bluetooth pairing, and brightness control.
- **[Security Architecture](docs/security_model.md)** — Three-layer security model, TOFU mechanics, and DPAPI credential protection.
- **[Protocol Specification](protocol/PROTOCOL.md)** — JSON wire event protocol definitions.

---

## 📦 Quick Installation

### Windows PC
Download and run **`Pouse-Setup-v1.0.0.exe`** from [Releases](https://github.com/Anikett-2310/Pouse/releases). It supports clean per-user installation without administrator prompts, optional startup configuration, and an automatic firewall rule.

### Android Handset
Install **`app-release.apk`** from [Releases](https://github.com/Anikett-2310/Pouse/releases) (or via Google Play Store once published). Granted permissions include Bluetooth and Camera (for QR pairing and touchless mode).

---

## 🏗️ Architecture

```text
┌──────────────────────────────────────────────┐
│              Android App (Flutter)            │
│                                              │
│  Touch / Motion / Touchless / Gaming Input   │
│                                              │
│  ┌──────────────────┐  ┌───────────────────┐ │
│  │  Wi-Fi Transport │  │ Bluetooth Transport│ │
│  │  WebSocket/JSON  │  │ BLE → RFCOMM/JSON │ │
│  └────────┬─────────┘  └────────┬──────────┘ │
└───────────┼─────────────────────┼────────────┘
            │ Pouse Protocol      │ Pouse Protocol
            │ (JSON Events)       │ (JSON Events)
            ▼                     ▼
┌──────────────────────────────────────────────┐
│            Rust PC Client (Windows)           │
│                                              │
│  ┌─────────────────┐  ┌──────────────────┐   │
│  │ WebSocket Server│  │  RFCOMM Server   │   │
│  │ (tokio-tungstenite)  │ (WinRT/Win32)  │   │
│  └────────┬────────┘  └────────┬─────────┘   │
│           │                   │              │
│           └──────────┬────────┘              │
│                      ▼                       │
│           ┌────────────────────┐             │
│           │   InputOwner       │             │
│           │ (ownership arbiter)│             │
│           └────────┬───────────┘             │
│                    ▼                         │
│           ┌────────────────────┐             │
│           │  Windows OS Input  │             │
│           │  (SendInput API)   │             │
│           └────────────────────┘             │
└──────────────────────────────────────────────┘
```

---

## 🔒 Security

Pouse uses a three-layer security model for Bluetooth connections:

1. **OS Bluetooth Pairing** — Standard Windows ↔ Android BR/EDR pairing via PIN/passkey.
2. **Pouse TOFU Authorization** — First-use trust prompt shown on the Android device. The user must explicitly approve any new PC before it can receive input. Trust is keyed to the PC's Classic BD_ADDR and persisted on the device.
3. **Deferred InputOwner Acquisition** — The PC-side `InputOwner` is only acquired on the *first authorized input event*, never on raw RFCOMM socket connection or HELLO/ACK. This prevents an untrusted Bluetooth connection from displacing an active Wi-Fi session while the TOFU prompt is pending.

See [`docs/security_model.md`](docs/security_model.md) for full details.

---

## 📁 Repository Layout

```
Pouse/
├── mobile/               # Flutter Android application
│   └── android/          # Android-specific platform code (Kotlin/JVM)
├── pc-client/            # Rust Windows PC client
│   └── src/
│       ├── main.rs       # Entry point (BLE + RFCOMM + Wi-Fi startup)
│       ├── server.rs     # Wi-Fi WebSocket server
│       ├── rfcomm_server.rs  # Bluetooth RFCOMM server + TOFU gating
│       ├── ble_advertiser.rs # BLE advertisement (discovery beacon)
│       ├── bluetooth_lifecycle.rs  # Windows BT state save/restore
│       ├── input_owner.rs    # Transport ownership arbitration
│       ├── input.rs          # Windows OS input injection
│       └── protocol.rs       # Pouse JSON event definitions
├── protocol/
│   └── PROTOCOL.md       # Pouse protocol specification
├── docs/
│   ├── v1_architecture.md    # Technical architecture document
│   ├── security_model.md     # Security model & threat analysis
│   └── v1_requirements.md    # V1 product requirements
└── tests/                # Integration test helpers
```

---

## 🚧 Planned Modes

| Mode | Technology | Version |
|---|---|---|
| Touchpad | Touchscreen | ✅ V1 |
| Motion | Accelerometer + Gyroscope | ✅ V1 |
| Touchless | Camera-based hand tracking | ✅ V1 |
| Optical | Camera + optical flow | 🚧 V2 |

---

## 🚀 Release Preparation & Environment State

Pouse is currently configured for development verification and release-candidate packaging preparation. Public distribution requires completing the following external signing and administrative prerequisites:

### Current Development State
- **BLE Company ID**: `0xFFFF` (Bluetooth SIG reserved identifier for internal test/development).
- **Windows Binary**: Unsigned `pc-client.exe` (triggers Windows SmartScreen / UAC unknown publisher prompt).
- **Android Signing**: Debug keystore fallback (`build.gradle.kts` automatically falls back to debug signing when `key.properties` is absent).
- **Android Application ID**: Production identity `com.pouse.app` (migrated in Phase 5A).

### Production Release Prerequisites
1. **Bluetooth SIG Company Identifier**: Obtain an officially allocated 16-bit Company Identifier to replace `0xFFFF` in `pc-client/src/ble_advertiser.rs` (`BLE_DEV_COMPANY_ID`) and `mobile/.../BluetoothBleScannerBridge.kt` (`POUSE_COMPANY_ID`).
2. **Android Production Identity**: Configured as permanent production identifier `com.pouse.app` across Android, iOS, macOS, and Linux.
3. **Android Release Keystore**: Generate production PKCS12/JKS keystore, supply credentials via `mobile/android/key.properties` (never committed), and build signed AAB/APK.
4. **Windows Code Signing**: Obtain an Authenticode code-signing certificate (EV or Azure Trusted Signing), sign `pc-client.exe` and the Inno Setup installer (`pc-client/installer/pouse_setup.iss`) using `scripts/sign_windows.ps1`.
5. **Windows Installer**: Compile `pc-client/installer/pouse_setup.iss` using Inno Setup compiler (`iscc.exe`) to produce signed distribution package `Pouse-Setup-v1.0.0.exe`.
