# Pouse — Product & Architecture Direction

## 1. Product Direction

Pouse is a single unified Android application that provides multiple ways to use a smartphone as a computer mouse.

The different approaches are treated as **Mouse Modes**, not separate applications or separate APKs.

### Mouse Modes

| Internal Version | User-Facing Mode | Input Technology | Status |
|---|---|---|---|
| V1 | Touchpad | Touchscreen | ✅ Complete |
| V2 | Motion | Gyroscope + Accelerometer | Planned |
| V3 | Optical | Rear Camera + Optical Flow | Planned |
| V4 | Touchless | Camera + Hand Tracking | Planned |

The user installs **one Pouse application** and selects the desired Mouse Mode inside the application.

---

# 2. Core Product Principle

> **One Pouse app. One PC client. One communication protocol. Multiple input modes.**

Users should not need separate APKs for V1, V2, V3, or V4.

The version numbers represent development milestones.  
The user-facing concept is **Mouse Modes**.

---

# 3. Shared Connection Layer

PC pairing and communication are independent of the selected Mouse Mode.

The user should:

1. Open Pouse.
2. Pair with the PC using QR or manual IP.
3. Establish the connection.
4. Select or switch Mouse Modes without reconnecting.

Concept:

```text
Pouse
  ↓
Connect to PC
  ↓
QR / Manual IP
  ↓
Connected
  ↓
Select Mouse Mode