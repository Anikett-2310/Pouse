# Pouse V1 Technical Architecture Document

## Overview

Pouse V1 establishes an incremental, low-latency client-server architecture converting an Android smartphone touchscreen into a Windows desktop mouse & keyboard.

---

## Component Architecture

```
┌─────────────────────────────────────────────────────────┐
│                    Mobile Client                        │
│                   (Flutter / Dart)                      │
│                                                         │
│  ┌───────────────────────┐  ┌────────────────────────┐  │
│  │ TouchpadGestureView   │  │   KeyboardInputView    │  │
│  └───────────┬───────────┘  └───────────┬────────────┘  │
│              │                          │               │
│              ▼                          ▼               │
│  ┌───────────────────────────────────────────────────┐  │
│  │               Sensitivity & Scaling               │  │
│  └──────────────────────────┬────────────────────────┘  │
│                             │                           │
│                             ▼                           │
│  ┌───────────────────────────────────────────────────┐  │
│  │               WebSocket Connection               │  │
│  └──────────────────────────┬────────────────────────┘  │
└─────────────────────────────┼───────────────────────────┘
                              │ JSON Event Stream (Wi-Fi)
                              ▼
┌─────────────────────────────────────────────────────────┐
│                     PC Client                           │
│                     (Rust / OS)                         │
│                                                         │
│  ┌───────────────────────────────────────────────────┐  │
│  │              tokio-tungstenite WS Server          │  │
│  └──────────────────────────┬────────────────────────┘  │
│                             │                           │
│                             ▼                           │
│  ┌───────────────────────────────────────────────────┐  │
│  │              Protocol Serde Parser                │  │
│  └──────────────────────────┬────────────────────────┘  │
│                             │                           │
│                             ▼                           │
│  ┌───────────────────────────────────────────────────┐  │
│  │             Windows OS Input Injector             │  │
│  │                (enigo / windows-sys)              │  │
│  └──────────────────────────┬────────────────────────┘  │
│                             │                           │
│                             ▼                           │
│                    Windows OS Cursor                    │
└─────────────────────────────────────────────────────────┘
```

---

## Technical Stack & Libraries

### Mobile (`mobile/`)
- **Framework**: Flutter (Dart)
- **Networking**: `web_socket_channel`
- **UI Components**: Custom `GestureDetector` touchpad surface with low-latency event callbacks.

### PC Client (`pc-client/`)
- **Runtime**: `tokio` (Async multi-threaded IO)
- **WebSocket Server**: `tokio-tungstenite`
- **Serialization**: `serde` & `serde_json`
- **Windows OS Input Simulation**: `enigo` (or direct Win32 `SendInput` via `windows-sys`)

---

## Core Operational Flow

1. **Server Launch**: Rust PC client starts a WebSocket listener on `0.0.0.0:8080`.
2. **Client Connection**: User enters PC IP address in Flutter app and connects via WebSocket (`ws://<pc-ip>:8080`).
3. **Gesture Capture**: 
   - `onPanUpdate` captures `(dx, dy)` pointer movement.
   - Sensitivity factor scales raw `(dx, dy)`.
4. **Event Serialization**: `MOVE(dx, dy)` JSON payload is sent over TCP/WebSocket.
5. **Input Execution**: Rust server receives payload, parses JSON, and invokes OS cursor displacement.
