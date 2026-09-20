# Pouse V1 Product & Technical Requirements

## 1. Overview
Pouse V1 enables an Android smartphone touchscreen to act as a wireless touchpad mouse and basic soft keyboard for a Windows PC over local Wi-Fi via WebSockets.

---

## 2. Scope Boundaries

### In-Scope (V1 Target)
1. **Touchpad Relative Cursor Movement**: Dragging a finger across the smartphone screen moves the Windows cursor by a proportional relative delta $(dx, dy)$.
2. **Left Click**: Single-finger tap on the touchpad triggers a left mouse button click.
3. **Double Click**: Rapid double tap triggers a double-click event.
4. **Right Click**: Two-finger tap triggers a right mouse button click.
5. **Drag & Select**: Tap-and-hold + drag movement simulates holding down the left mouse button while moving (`BUTTON_DOWN` -> `MOVE` -> `BUTTON_UP`).
6. **Two-Finger Scroll**: Swiping two fingers vertically or horizontally triggers mouse wheel scrolling (`SCROLL`).
7. **Phone Keyboard Input**: Soft keyboard on mobile emits text/character events and special keys (`Enter`, `Backspace`, `Space`, `Escape`, `Tab`) to the active PC window.
8. **Sensitivity Control**: Adjustable scaling factor on mobile to control cursor speed.
9. **Direct Connection**: Manual PC IP address input and status display (Disconnected / Connecting / Connected).

### Out-of-Scope (Forbidden in V1)
- V2 (Physical Motion / IMU mouse)
- V3 (Optical surface camera mouse)
- V4 (Touchless hand gesture tracking)
- Media player controls
- PC system statistics monitoring
- Universal clipboard sharing
- Power controls (Shutdown/Sleep)
- Remote desktop video stream
- WebRTC / Cloud servers / External relay servers
- macOS or Linux desktop targets

---

## 3. Performance & Quality Targets
- **Latency**: Sub-30ms input latency over standard 5GHz/2.4GHz home Wi-Fi networks.
- **Reliability**: Graceful handling of network disconnects without crashing the PC background server or freezing the Flutter UI.
- **Zero-Dependency Core**: PC client runs as a standalone lightweight Rust binary with minimal resource footprint (< 20MB RAM).
