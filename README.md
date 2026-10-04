# 🖱️ Pouse — Pocket Mouse

> Turn the smartphone you already carry into a multi-mode controller for your Windows PC.

Pouse is a wireless input platform that turns an Android smartphone into a multi-mode control device for Windows PCs, without requiring dedicated mouse hardware.

Instead of building separate desktop applications for every control method, Pouse uses a shared protocol, transport layer, and Windows input-owner architecture across multiple input technologies.

---

## 🎯 Vision

> **"I need a mouse, but I don't have one with me."**

Your smartphone is already in your pocket.

Pouse explores how far that device can go as a practical replacement for dedicated input hardware — from a traditional touchpad to motion control, hand tracking, gaming controls, and remote screen interaction.

---

# ✨ Pouse v1.0.0

Pouse v1.0.0 provides a multi-mode Android controller for Windows 10/11 with Wi-Fi and Bluetooth connectivity.

## Input Modes

| Mode | Technology | Status |
|---|---|---|
| **Touchpad** | Multi-touch surface with cursor, click, drag, scroll and gesture controls | ✅ Available |
| **Motion** | Accelerometer + gyroscope air mouse | ✅ Available |
| **Touchless** | Front-camera MediaPipe hand tracking | ✅ Available |
| **Gaming** | Virtual gamepad with directional controls, analog input and action buttons | ✅ Available |
| **Remote Screen** | Windows screen capture streamed to Android using H.264 over Wi-Fi | ✅ Available |

## Utilities

| Utility | Purpose |
|---|---|
| **Keyboard** | Send text and keyboard input to the Windows PC |
| **PC Controls** | Volume, mute, brightness and Windows Search |
| **OS Actions** | Task View, Show Desktop, Taskbar Apps, application switching and desktop actions |
| **Zoom** | Windows magnification controls |
| **Guide** | Setup, connection and gesture guidance |

---

# 🖐️ Touchpad

The Touchpad mode is designed around a familiar laptop-style touch surface.

### Surface layout

- Approximately **85% primary touch surface**
- Dedicated **right-side scroll zone**

### Supported interactions

- Single-finger cursor movement
- Tap for left click
- Double tap for double click
- Two-finger tap for right click
- Tap-and-hold for drag
- Two-finger vertical scrolling
- Horizontal two-finger navigation
- Multi-finger Windows actions
- Two-finger pinch for Windows magnification

---

# 🔌 Connection Methods

Pouse supports two independent transport methods.

| Feature | Wi-Fi | Bluetooth |
|---|---|---|
| **Transport** | WebSocket / JSON | Bluetooth RFCOMM / JSON |
| **Discovery / Pairing** | QR pairing or manual IP | Bluetooth discovery + RFCOMM |
| **Network requirement** | Same local Wi-Fi / LAN | No Wi-Fi required for input |
| **Authorization** | Pouse pair-token authorization | OS Bluetooth security + Pouse TOFU |
| **Input ownership** | Deferred authorization | Deferred authorization |
| **Reconnect** | Supported | Supported |

Pouse can support both transport layers, while maintaining a single active input owner for Windows input.

## Wi-Fi

Wi-Fi connects the Android device and Windows PC through the same local network.

Connection can be established using:

- QR pairing
- Manual IP and port entry

Being on the same LAN does **not** automatically authorize control. Pouse uses an application-level pairing token to authorize the Android device.

## Bluetooth

Bluetooth uses discovery to locate the Pouse PC and RFCOMM for the actual input/control channel.

Bluetooth does not require the Android device and PC to share a Wi-Fi network for supported input features.

Depending on the device and operating-system state, normal Bluetooth pairing/security may also be required.

---

# 🖥️ Remote Screen

Remote Screen is a **top-level Pouse mode**, not a utility.

The Windows client captures the PC display, encodes it using H.264, and streams it to Android over Wi-Fi.

### Architecture

```text
Windows Graphics Capture
        ↓
D3D11
        ↓
Media Foundation H.264
        ↓
Wi-Fi screen transport
        ↓
Android MediaCodec
        ↓
Android display
```

Remote Screen is designed for low-latency local-network screen viewing and supports up to 60 FPS depending on system conditions.

> **Important:** Bluetooth can carry supported input/control traffic, but it does not replace the Wi-Fi video transport required by Remote Screen.

---

# 🔐 Security

Pouse separates connection, authorization, and input ownership.

## Bluetooth Security

Bluetooth control uses multiple layers:

1. **OS Bluetooth Security**  
   Standard Windows ↔ Android Bluetooth security and pairing where required.

2. **Pouse TOFU Authorization**  
   On first use, Android asks the user to explicitly trust a discovered Pouse PC. Trust is keyed to the PC's Classic Bluetooth address and can be forgotten later.

3. **Deferred InputOwner Acquisition**  
   A Bluetooth connection does not automatically gain Windows input ownership. Ownership is acquired only when an authorized input event is received.

```text
RFCOMM_CONNECTED != INPUT_AUTHORIZED
```

HELLO/ACK handshakes and connection-level control messages do not acquire input ownership.

## Wi-Fi Authorization

Network connectivity and authorization are separate concepts.

The Pouse QR/manual connection flow carries the information needed by the Windows client to validate the Android device's pairing request.

Where applicable, stored Wi-Fi credentials are protected using Windows DPAPI.

## Input Ownership

Pouse uses a centralized `InputOwner` mechanism so that only one authorized transport controls Windows input at a time.

Held keyboard and mouse states are also released when required during transport switches and disconnects.

For more detail, see [`docs/security_model.md`](docs/security_model.md).

---

# 🏗️ Architecture

```text
┌─────────────────────────────────────────────────────┐
│                 Android App (Flutter)               │
│                                                     │
│ Touchpad / Motion / Touchless / Gaming / Keyboard  │
│ Remote Screen / Utilities                          │
│                                                     │
│  ┌────────────────────┐  ┌────────────────────────┐ │
│  │   Wi-Fi Transport  │  │ Bluetooth Transport    │ │
│  │ WebSocket + JSON   │  │ RFCOMM + JSON          │ │
│  └─────────┬──────────┘  └───────────┬────────────┘ │
└────────────┼─────────────────────────┼──────────────┘
             │                         │
             │      Pouse Protocol     │
             │      (JSON Events)      │
             ▼                         ▼
┌─────────────────────────────────────────────────────┐
│               Rust Windows PC Client                │
│                                                     │
│  ┌─────────────────────┐  ┌──────────────────────┐ │
│  │ WebSocket Server    │  │ RFCOMM Server        │ │
│  │ Wi-Fi input         │  │ Bluetooth input      │ │
│  └──────────┬──────────┘  └──────────┬───────────┘ │
│             │                        │             │
│             └────────────┬───────────┘             │
│                          ▼                         │
│                 ┌─────────────────┐               │
│                 │   InputOwner    │               │
│                 │ Input arbitration│              │
│                 └────────┬────────┘               │
│                          ▼                        │
│                 ┌─────────────────┐              │
│                 │ Windows Input   │              │
│                 │ SendInput/enigo │              │
│                 └─────────────────┘              │
└─────────────────────────────────────────────────────┘
```

The architecture separates:

- Input sources
- Transport
- Authorization
- Input ownership
- Windows input injection

This allows multiple Android input technologies to share the same Windows desktop infrastructure.

---

# 📦 Installation

## Windows PC

Download the current Windows installer from the Pouse GitHub Release:

**[Pouse v1.0.0 Releases](https://github.com/Anikett-2310/Pouse/releases)**

Current installer:

```text
Pouse-Setup-v1.0.0.exe
```

## Android

Pouse is distributed directly as an APK.

Current release:

```text
app-release.apk
```

Download the APK from the official Pouse download page or the GitHub release.

Production Android application ID:

```text
com.pouse.app
```

Camera access is required for QR scanning and Touchless mode.

Bluetooth permissions are required for Bluetooth functionality.

> Pouse currently uses direct APK distribution and does not depend on Google Play.

---

# 🧰 Pouse CLI

Pouse includes a command-line interface for Windows installation and management.

## Install

```bash
npm install -g pouse-cli
```

## Install Pouse

```bash
pouse install
```

## Update Pouse

```bash
pouse update
```

## Uninstall Pouse

```bash
pouse uninstall
```

## Other commands

```bash
pouse --version
pouse --help
```

## CLI Platform Support

| Platform | Status |
|---|---|
| Windows | ✅ Supported |
| Linux | 🔮 Planned |
| macOS | 🔮 Planned |

The CLI discovers Pouse releases through the GitHub Releases API and verifies the Windows installer using its published SHA-256 checksum by default.

Current public npm package:

```text
pouse-cli@1.0.0
```

**npm:** https://www.npmjs.com/package/pouse-cli

---

# 🌐 Website

Current website:

**https://pouse-webs.vercel.app/**

Download page:

**https://pouse-webs.vercel.app/download**

The permanent public domain is intended to be:

**https://pouse.app**

once the custom domain is connected and deployed.

---

# 📚 Documentation

| Document | Description |
|---|---|
| [`docs/user_guide.md`](docs/user_guide.md) | User setup, connection methods, gestures and utilities |
| [`docs/troubleshooting.md`](docs/troubleshooting.md) | Discovery, firewall, Bluetooth and device troubleshooting |
| [`docs/security_model.md`](docs/security_model.md) | Security model and authorization architecture |
| [`docs/v1_architecture.md`](docs/v1_architecture.md) | V1 technical architecture |
| [`docs/v1_requirements.md`](docs/v1_requirements.md) | V1 product requirements |
| [`protocol/PROTOCOL.md`](protocol/PROTOCOL.md) | Pouse JSON event protocol |

---

# 📁 Repository Structure

```text
Pouse/
├── .github/                # GitHub Actions and repository automation
├── .vscode/                # VS Code project configuration
├── cli/                    # Pouse command-line interface
├── docs/                   # Product, architecture and security documentation
├── mobile/                 # Flutter Android application
├── pc-client/              # Rust Windows desktop client
├── protocol/               # Shared protocol documentation
├── scripts/                # Build and release tooling
└── tests/                  # Supporting test utilities
```

---

# 🧪 Development & Testing

## Android

```text
Flutter
Dart
Kotlin
Android Bluetooth APIs
MediaPipe
Android MediaCodec
```

## Windows

```text
Rust
Tokio
tokio-tungstenite
Windows APIs
enigo / SendInput
Windows Graphics Capture
Direct3D 11
Media Foundation
```

## CLI

```text
Node.js
npm
GitHub Releases API
SHA-256 verification
```

Pouse includes automated validation for areas such as:

- CLI argument parsing
- Release discovery
- Checksum verification
- Windows process handling
- Windows registry detection
- Security helpers
- Mobile widget behavior
- Transport and input-related components

---

# 🚧 Current Release Limitations

Pouse v1.0.0 is publicly distributed, but some release infrastructure is still being finalized.

## Windows Authenticode

The Windows installer and desktop binary currently do not have a production Authenticode signature.

Windows may therefore display an unknown-publisher or SmartScreen warning during installation.

## Bluetooth BLE Company Identifier

The current Bluetooth discovery implementation uses:

```text
0xFFFF
```

as a development/testing Company Identifier.

This is **not a production Bluetooth SIG Company Identifier** and should not be interpreted as a finalized public Bluetooth identity.

## Platform Support

The current desktop client officially targets:

```text
Windows 10 / Windows 11
```

Linux and macOS desktop clients are not currently supported.

---

# 🗺️ Roadmap

| Feature | Status |
|---|---|
| Touchpad | ✅ Available |
| Motion | ✅ Available |
| Touchless | ✅ Available |
| Gaming | ✅ Available |
| Remote Screen | ✅ Available |
| Keyboard | ✅ Available |
| PC Controls | ✅ Available |
| Windows OS Actions | ✅ Available |
| Optical Surface Mouse | ❌ Dropped / not currently planned |
| Linux PC Client | 🔮 Future |
| macOS PC Client | 🔮 Future |
| iOS Support | 🔮 Future |

The roadmap may evolve as development continues.

---

# 💡 Design Philosophy

### One Device, Many Input Methods

A smartphone can provide more than a basic touchpad.

### Shared Infrastructure

Different input technologies share the same protocol and Windows desktop client rather than requiring separate desktop applications.

### Local-First Control

Core Pouse control functionality operates locally between the Android device and Windows PC.

### Explicit Authorization

Connectivity and authorization are treated as separate concepts.

### No Extra Hardware

Pouse is built around devices the user already owns.

---

# 📄 License

No open-source license has been declared for this repository at this time.

Until a license is added, the source code should not be assumed to be available for unrestricted reuse, modification, or redistribution.

---

# 🚀 Release

## Pouse v1.0.0

### Windows

[Download Pouse for Windows](https://github.com/Anikett-2310/Pouse/releases/tag/v1.0.0)

```text
Pouse-Setup-v1.0.0.exe
```

### Android

[Download Pouse for Android](https://github.com/Anikett-2310/Pouse/releases/tag/v1.0.0)

```text
app-release.apk
```

### CLI

[View pouse-cli on npm](https://www.npmjs.com/package/pouse-cli)

```bash
npm install -g pouse-cli
```

---

# 🔗 Links

| Resource | Link |
|---|---|
| **Website** | https://pouse-webs.vercel.app/ |
| **Downloads** | https://pouse-webs.vercel.app/download |
| **GitHub** | https://github.com/Anikett-2310/Pouse |
| **Releases** | https://github.com/Anikett-2310/Pouse/releases |
| **npm** | https://www.npmjs.com/package/pouse-cli |

---

<p align="center">
  Built with Flutter, Rust, and a smartphone you already have.
</p>
