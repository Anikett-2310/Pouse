# Pouse Protocol Specification — V1

## Overview

The Pouse Protocol defines all messages exchanged between the Pouse Android
client (Flutter) and the Pouse Windows PC client (Rust).

Two transport layers carry the same protocol:

| Transport | Format | Framing |
|---|---|---|
| Wi-Fi | JSON over WebSocket | WebSocket frames |
| Bluetooth | JSON over RFCOMM | Newline-delimited (`\n`) |

---

## 1. Bluetooth Transport Handshake

Before any JSON events are exchanged over Bluetooth RFCOMM, a plain-text
handshake is performed:

```
Android → PC:   POUSE_HELLO\n
PC → Android:   POUSE_ACK\n
```

- The handshake confirms the Pouse protocol version and that the RFCOMM
  connection is a genuine Pouse session.
- **The PC does NOT acquire input ownership at this point.** Ownership is
  deferred to the first authorized Pouse JSON input event. See the
  Security Model for details.
- JSON input events sent before `POUSE_HELLO` or before Android-side TOFU
  authorization is granted are discarded.

### Test Sequence (diagnostic only)

```
Android → PC:   TEST:<seq>\n
PC → Android:   ACK:<seq>\n
```

Used during development and regression testing. Not present in production paths.

---

## 2. JSON Event Format

All input events are JSON objects with a mandatory `event` string field:

```json
{
  "event": "EVENT_NAME",
  "...payload": "values"
}
```

Wi-Fi events are sent as WebSocket text frames.  
Bluetooth events are sent as newline-terminated UTF-8 lines over RFCOMM.

---

## 3. Input Events

### 3.1 Pointer Movement (`MOVE`)

Sent continuously during finger drag. Represents relative cursor displacement.

```json
{ "event": "MOVE", "dx": 12.5, "dy": -4.2 }
```

| Field | Type | Description |
|---|---|---|
| `dx` | float | Horizontal displacement (screen pixels, scaled) |
| `dy` | float | Vertical displacement (screen pixels, scaled) |

---

### 3.2 Left Click (`LEFT_CLICK`)

Single tap gesture.

```json
{ "event": "LEFT_CLICK" }
```

---

### 3.3 Right Click (`RIGHT_CLICK`)

Two-finger tap gesture.

```json
{ "event": "RIGHT_CLICK" }
```

---

### 3.4 Double Click (`DOUBLE_CLICK`)

Double tap gesture.

```json
{ "event": "DOUBLE_CLICK" }
```

---

### 3.5 Button Down / Button Up (`BUTTON_DOWN` / `BUTTON_UP`)

Tap-and-hold drag initiation and release.

```json
{ "event": "BUTTON_DOWN", "button": "left" }
{ "event": "BUTTON_UP",   "button": "left" }
```

| Field | Type | Values |
|---|---|---|
| `button` | string | `"left"`, `"right"` |

---

### 3.6 Scroll (`SCROLL`)

Two-finger pan / swipe.

```json
{ "event": "SCROLL", "dx": 0.0, "dy": 15.0 }
```

| Field | Type | Description |
|---|---|---|
| `dx` | float | Horizontal scroll delta |
| `dy` | float | Vertical scroll delta |

---

### 3.7 Text Input (`TEXT_INPUT`)

Typed text from the soft keyboard.

```json
{ "event": "TEXT_INPUT", "text": "Hello world" }
```

| Field | Type | Description |
|---|---|---|
| `text` | string | UTF-8 string to inject into Windows |

---

### 3.8 Key Press (`KEY_PRESS`)

Special action key from the soft keyboard toolbar.

```json
{ "event": "KEY_PRESS", "key": "enter" }
```

| Field | Type | Values |
|---|---|---|
| `key` | string | `"enter"`, `"backspace"`, `"space"`, `"tab"`, `"escape"` |

---

### 3.9 Motion (`MOTION`)

Gyroscope/accelerometer-based motion control delta.

```json
{ "event": "MOTION", "dx": 3.1, "dy": -1.4 }
```

| Field | Type | Description |
|---|---|---|
| `dx` | float | Horizontal motion delta |
| `dy` | float | Vertical motion delta |

---

### 3.10 Zoom (`ZOOM`)

Pinch gesture zoom.

```json
{ "event": "ZOOM", "scale": 1.12 }
```

| Field | Type | Description |
|---|---|---|
| `scale` | float | Scale factor relative to previous event (> 1.0 = zoom in) |

---

### 3.11 OS Action (`OS_ACTION`)

Keyboard shortcut / OS action.

```json
{ "event": "OS_ACTION", "action": "copy" }
```

| Field | Type | Values |
|---|---|---|
| `action` | string | `"copy"`, `"paste"`, `"cut"`, `"undo"`, `"redo"`, `"select_all"`, `"switch_window"`, `"show_desktop"` |

---

### 3.12 Game Input (`GAME_INPUT`)

Analog stick / gaming mode input.

```json
{ "event": "GAME_INPUT", "dx": 0.5, "dy": -0.3 }
```

| Field | Type | Description |
|---|---|---|
| `dx` | float | Normalized horizontal axis (−1.0 to +1.0) |
| `dy` | float | Normalized vertical axis (−1.0 to +1.0) |

---

## 4. Keep-Alive

### 4.1 Ping / Pong (`PING` / `PONG`)

Sent periodically by Android to detect connection drops.

```json
{ "event": "PING" }
```

PC response:

```json
{ "event": "PONG" }
```

> **Note:** `PING` / `PONG` events do **not** trigger `InputOwner` acquisition
> over Bluetooth. Only substantive input events (cursor, click, scroll, etc.)
> cause ownership transfer.

---

## 5. Error Handling

- The PC client ignores unknown or malformed JSON events and logs a debug
  warning. Unknown events do not close the connection.
- Events received over Bluetooth before `POUSE_HELLO` / before Android TOFU
  authorization are silently discarded (defense in depth; Android's send gate
  is the primary guard).

---

## 6. BLE Discovery Payload

The PC client advertises a BLE manufacturer data payload for device discovery.
This is **not** a protocol event but a pre-connection beacon.

| Offset | Size | Value |
|---|---|---|
| 0 | 5 bytes | ASCII magic: `POUSE` |
| 5 | 1 byte | Protocol version: `0x01` |
| 6 | 6 bytes | Classic BR/EDR BD_ADDR (big-endian) |

The BLE Company ID is `0xFFFF` (Bluetooth SIG reserved for testing/development).
A registered Company ID must be obtained before production distribution.
