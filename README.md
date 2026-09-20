# 🖱️ Pouse — Pocket Mouse

> Turn the smartphone you already carry into a mouse for your PC.

Pouse is a wireless mouse platform that explores multiple ways of using a smartphone as a computer input device.

Instead of building four separate applications, Pouse uses a shared communication protocol and Windows client while different input technologies provide different mouse experiences.

## 🎯 Vision

The idea behind Pouse is simple:

> **"I need a mouse, but I don't have one with me."**

Your smartphone is already in your pocket.

Pouse explores how far that smartphone can replace dedicated mouse hardware through multiple input methods.

### Planned Mouse Modes

| Mode | Technology | Status |
|---|---|---|
| Touchpad | Smartphone touchscreen | ✅ Available |
| Motion | Accelerometer + gyroscope | 🚧 Planned |
| Optical | Phone camera + optical flow | 🚧 Planned |
| Touchless | Camera-based hand tracking | 🚧 Planned |

These are referred to internally as V1, V2, V3 and V4.

---

# ✨ Current Version

## V1 — Touchpad Mouse

The first working version turns the smartphone touchscreen into a wireless touchpad for Windows.

### Features

- 🖱️ Relative cursor movement
- 👆 Single-tap left click
- 👆👆 Double-tap double click
- ✌️ Two-finger tap right click
- 🖐️ Tap-and-hold drag
- ↕️ Vertical scrolling
- ↔️ Horizontal scrolling
- ⌨️ Soft keyboard input
- 🎚️ Mouse sensitivity control
- 🔄 Automatic reconnection handling
- 📡 Wireless local-network communication
- 📷 QR-based PC pairing
- 🔌 Manual IP connection fallback
- 📱 Android release APK
- 🪟 Portable Windows PC client

---

# 🏗️ Architecture

Pouse uses a shared protocol between the smartphone and PC.

```text
┌──────────────────────────────┐
│         Android App          │
│                              │
│ Touch / Motion / Optical /   │
│ Touchless Input              │
└──────────────┬───────────────┘
               │
               │ Pouse Protocol
               │ WebSocket / JSON
               ▼
┌──────────────────────────────┐
│       Rust PC Client         │
│                              │
│ Protocol + Input Processing  │
└──────────────┬───────────────┘
               │
               ▼
┌──────────────────────────────┐
│      Windows Native Input    │
│                              │
│          Cursor              │
└──────────────────────────────┘
