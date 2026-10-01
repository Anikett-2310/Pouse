# Pouse V1 — Security Model

## Overview

Pouse V1 uses a three-layer security model for Bluetooth connections.
Wi-Fi connections are trusted on the local network (no additional
application-layer authorization).

---

## Security Layers

### Layer 1 — OS Bluetooth Pairing (BR/EDR)

**What it provides:**  
Standard Windows ↔ Android Bluetooth pairing via passkey/PIN confirmation.
This is enforced by the OS before any RFCOMM connection can be established.

**Threat mitigated:**  
Prevents unknown, unpaired devices from connecting to the RFCOMM service.

**Limitation:**  
Bluetooth pairing authenticates the *hardware device*, not the application
running on it. A malicious app on a paired phone could connect to Pouse.

---

### Layer 2 — Pouse TOFU Authorization (Application-Layer Trust)

**What it provides:**  
A Trust-On-First-Use (TOFU) prompt is shown on the Android device the first
time it encounters a new PC (identified by Classic BD_ADDR). The user must
explicitly approve the PC before any input events are dispatched.

**Mechanics:**
- Trust is stored in the Android app's persistent preference store, keyed by
  the PC's Classic BD_ADDR.
- On first connection to a new PC, the Android `BluetoothRfcommService` gates
  all input sending with a UI dialog: "Trust PC `<BD_ADDR>`?".
  - **Trust** → trust record saved, input events begin flowing.
  - **Reject** → connection is torn down immediately.
- On subsequent connections to a trusted PC, the trust check passes silently.
- The user can revoke trust via "Forget PC" in the app's connection sheet.

**Threat mitigated:**  
Prevents a malicious or compromised paired phone from silently hijacking PC
input. Requires explicit user confirmation at the Android UI level for each
new PC identity.

**Trust identity:**  
Classic BD_ADDR (the permanent hardware MAC address of the Windows PC's
Bluetooth radio). This remains stable across BLE advertisement restarts and
RFCOMM reconnects.

**Limitation:**  
TOFU does not provide cryptographic mutual authentication. A sophisticated
attacker who can spoof the BD_ADDR after the first trust grant could bypass
this layer. Cryptographic mutual authentication (e.g., TLS over RFCOMM,
pre-shared key, or certificate pinning) is future work.

---

### Layer 3 — Deferred InputOwner Acquisition (PC-Side Gate)

**What it provides:**  
On the PC, the `InputOwner` (which controls which transport may inject OS
input) is **not** acquired on RFCOMM socket connection, and **not** on
`POUSE_HELLO` / `POUSE_ACK` handshake. It is acquired only on the **first
authorized Pouse input event** received over the Bluetooth connection.

**Why this matters:**  
HELLO/ACK completes before the Flutter TOFU prompt result is known to the PC.
Without this deferral, a Bluetooth connection from an untrusted Android device
could temporarily seize `InputOwner::Bluetooth`, displacing an active Wi-Fi
controller while the TOFU dialog is pending on the phone.

**Invariant:**

```
RFCOMM_CONNECTED  ≠  INPUT_AUTHORIZED
```

**Defense in depth:**  
Android's `sendEvent()` call is gated at the Dart layer: no Pouse events are
sent until the TOFU dialog result is received and trust is confirmed. The PC
side's deferred acquisition is a second, independent guard.

---

## Wi-Fi Transport Security

Wi-Fi connections are not subject to TOFU or InputOwner deferral. The
implicit trust model is: **same local network = authorized.**

This is appropriate for typical home/office LAN environments. For stronger
Wi-Fi security, future work could include:
- QR-token challenge verification (the pairing token already exists)
- IP allowlisting
- TLS WebSocket (`wss://`)

---

## InputOwner Arbitration

The `InputOwner` singleton enforces that only one transport can inject OS
input at a time:

- When Transport A holds ownership and Transport B sends an event, B's event
  is rejected and logged.
- When ownership switches (e.g., Bluetooth → Wi-Fi), all held keys and mouse
  buttons are released first to prevent stuck inputs.
- `InputOwner` is global state protected by `Mutex`.

---

## Bluetooth State Management

`BluetoothStateRestorer` saves Windows Bluetooth discoverability and
connectable state at Pouse startup and restores both on clean shutdown
(including `Ctrl+C`). This ensures Pouse does not permanently alter the
user's system Bluetooth settings.

---

## Known Limitations & Future Work

| Issue | Status |
|---|---|
| No cryptographic mutual authentication over RFCOMM | Future work |
| BLE Company ID is `0xFFFF` (test/dev reserved) | Must register before distribution |
| Wi-Fi has no application-layer authentication | Future work (QR token verification) |
| Android TOFU trust keyed to BD_ADDR (MAC spoofing risk) | Accepted for V1 |
| No Android signing certificate pinning | Future work |

---

## Threat Model Summary

| Threat | Layer 1 | Layer 2 | Layer 3 |
|---|---|---|---|
| Unknown device RFCOMM connect | ✅ OS pairing blocks | — | — |
| Paired phone silently injects input | — | ✅ TOFU prompt | — |
| Untrusted Bluetooth displaces Wi-Fi | — | ✅ Android gate | ✅ Deferred InputOwner |
| Malicious app on trusted paired phone | — | ✅ Per-BD_ADDR trust | — |
| BD_ADDR spoofing after trust grant | ❌ Not addressed | ❌ Not addressed | — |
