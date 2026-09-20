# Pouse Protocol Specification — V1 (JSON over WebSocket)

## Overview

The Pouse Protocol defines structured JSON event messages exchanged over a WebSocket connection between the Pouse Mobile client (Flutter) and the Pouse PC client (Rust).

All events sent from Mobile to PC share a uniform JSON structure.

---

## Message Format

Every message is a JSON object containing an `event` field (string) and optional event-specific payload parameters:

```json
{
  "event": "EVENT_NAME",
  "...payload": "values"
}
```

---

## Event Definitions

### 1. Pointer Movement (`MOVE`)

Sent continuously during finger drag on the touchpad area to represent relative cursor displacement.

```json
{
  "event": "MOVE",
  "dx": 12.5,
  "dy": -4.2
}
```

- `dx` (number, float): Relative horizontal offset in screen pixels.
- `dy` (number, float): Relative vertical offset in screen pixels.

---

### 2. Single Left Click (`LEFT_CLICK`)

Emitted on single tap gesture.

```json
{
  "event": "LEFT_CLICK"
}
```

---

### 3. Right Click (`RIGHT_CLICK`)

Emitted on two-finger tap gesture.

```json
{
  "event": "RIGHT_CLICK"
}
```

---

### 4. Double Click (`DOUBLE_CLICK`)

Emitted on double tap gesture.

```json
{
  "event": "DOUBLE_CLICK"
}
```

---

### 5. Button Down / Button Up (Drag Support)

Emitted for tap-and-hold gestures to perform window dragging or text selection.

```json
{
  "event": "BUTTON_DOWN",
  "button": "left"
}
```

```json
{
  "event": "BUTTON_UP",
  "button": "left"
}
```

- `button` (string): `"left"` or `"right"`.

---

### 6. Scrolling (`SCROLL`)

Emitted during two-finger pan/swipe gesture.

```json
{
  "event": "SCROLL",
  "dx": 0.0,
  "dy": 15.0
}
```

- `dx` (number, float): Horizontal scroll delta.
- `dy` (number, float): Vertical scroll delta.

---

### 7. Keyboard Input (`TEXT_INPUT` & `KEY_PRESS`)

Emitted when typing via soft keyboard or pressing action keys (Backspace, Enter, Space).

```json
{
  "event": "TEXT_INPUT",
  "text": "Hello world"
}
```

```json
{
  "event": "KEY_PRESS",
  "key": "enter"
}
```

Supported special key codes: `"enter"`, `"backspace"`, `"space"`, `"tab"`, `"escape"`.

---

### 8. Heartbeat (`PING` / `PONG`)

Keep-alive ping sent periodically to detect connection drops.

```json
{
  "event": "PING"
}
```

Server response:

```json
{
  "event": "PONG"
}
```

---

## Error Handling

If the PC client receives an unparseable or unknown event message, it ignores the event and logs a debug warning without crashing or closing the WebSocket connection.
