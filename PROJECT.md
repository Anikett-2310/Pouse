# Pouse — Pocket Mouse

## Vision

Pouse is a cross-device platform that explores how a smartphone can replace a dedicated computer mouse.

The core problem is simple:

A person may need a mouse to control a computer but may not have a physical mouse with them. They already have a smartphone, so Pouse turns that smartphone into a mouse/controller.

Pouse is NOT claiming that smartphone-as-mouse is a new invention. Existing touchpad mouse apps already exist.

The project differentiator is the progressive exploration of multiple input methods using the same smartphone-to-PC architecture.

## Roadmap

Pouse has four planned input modes:

### V1 — Touchpad Mouse
The smartphone touchscreen acts as a wireless touchpad.

Capabilities:
- Relative cursor movement
- Single tap = left click
- Double tap = double click
- Two-finger tap = right click
- Tap and hold + movement = drag
- Two-finger swipe = vertical scrolling
- Optional horizontal scrolling
- Phone keyboard for text input
- Sensitivity control

### V2 — Physical Motion Mouse
The user physically moves the smartphone like an air mouse.

Potential technologies:
- Accelerometer
- Gyroscope
- Sensor fusion
- Gravity compensation
- Orientation estimation
- Drift handling

V2 must be implemented only after V1 is stable.

### V3 — Optical Surface Mouse
The smartphone rear camera observes a surface such as a desk and estimates movement using computer vision.

Potential technologies:
- Optical flow
- Feature tracking
- Camera processing
- Movement estimation

V3 must be implemented only after V2 is stable.

### V4 — Touchless / Invisible Mouse
The smartphone remains stationary while its camera tracks hand/finger movement and gestures.

Potential technologies:
- Hand landmark detection
- Computer vision
- Gesture recognition

V4 must be implemented only after V3 is stable.

## Architecture

All four versions must share the same PC-side architecture and protocol.

The input method changes, but the output abstraction remains the same:

Touch / IMU / Optical Flow / Hand Tracking
        ↓
Universal Pouse Input Events
        ↓
Pouse Protocol
        ↓
Rust PC Client
        ↓
Windows Native Input
        ↓
Windows Cursor / Keyboard

Examples of universal events:

MOVE(dx, dy)
LEFT_CLICK
RIGHT_CLICK
BUTTON_DOWN
BUTTON_UP
SCROLL
KEY_DOWN
KEY_UP
PING
PONG

The PC client must not contain separate implementations for V1, V2, V3 and V4. Each input mode should eventually produce the same protocol events.

## Current Development Target

Only V1 is being implemented now.

V1 target:

Android smartphone → local Wi-Fi → WebSocket → Rust Windows PC client → Windows mouse/keyboard input.

The first technical milestone is:

Flutter touchscreen
→ Wi-Fi
→ WebSocket
→ Rust
→ Windows cursor movement

After cursor movement works reliably, implement:

1. Left click
2. Right click
3. Double click
4. Drag
5. Scrolling
6. Keyboard input
7. Sensitivity and smoothing
8. Connection handling
9. Pairing/polish

## Technology Stack

Mobile:
- Flutter
- Dart
- Android initially

PC:
- Rust
- Windows initially

Communication:
- Local Wi-Fi
- WebSocket initially
- No cloud dependency for normal operation

The protocol should use a clear structured format, initially JSON unless there is a strong technical reason to choose another format.

## Repository Structure

The intended structure is:

mobile/
pc-client/
protocol/
docs/
tests/

mobile/ contains the Flutter Android application.

pc-client/ contains the Rust Windows client.

protocol/ contains the shared Pouse protocol specification.

docs/ contains architecture and technical documentation.

tests/ contains shared/integration testing where appropriate.

## V1 Scope Restrictions

Do NOT implement the following as part of the current V1 unless explicitly requested later:

- Media player controls
- PC system monitoring
- Universal clipboard
- Power controls
- Remote desktop
- Cloud infrastructure
- WebRTC
- macOS support
- Linux support
- V2 motion tracking
- V3 optical tracking
- V4 hand tracking

These may be considered future extensions, but they are not current implementation scope.

## Development Principles

Prioritize a working end-to-end prototype over feature quantity.

Build incrementally.

Do not implement complex discovery, pairing or polish before basic communication and cursor control work.

Do not prematurely optimize.

Keep the protocol independent from the Flutter UI and Rust implementation.

Keep the architecture extensible so V2, V3 and V4 can reuse the same protocol and PC client.

The immediate goal is a reliable V1, not a complete implementation of all four roadmap versions.
