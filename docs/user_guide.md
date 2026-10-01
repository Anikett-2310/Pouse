# Pouse User Guide

**Version:** 1.0.0  
**Supported Platforms:** Windows 10/11 (PC Client), Android 7.0+ (Mobile App)

---

## 1. What is Pouse?

Pouse (*Pocket Mouse*) turns the Android smartphone you already carry into a wireless multi-mode mouse, touchpad, and utility controller for your Windows PC — requiring no dongles or extra hardware.

Pouse operates over two independent connection paths:
- **Wi-Fi (LAN):** High-speed local WebSocket communication with instant QR pairing, supporting low-latency touchpad/motion/gaming input and live Remote Screen streaming.
- **Bluetooth (RFCOMM):** Direct, infrastructure-free control that works without an active Wi-Fi network, secured by Trust-On-First-Use (TOFU) authorization.

---

## 2. Installation

### Windows PC Installation
1. Download `Pouse-Setup-v1.0.0.exe` from the official [Pouse GitHub Releases](https://github.com/Anikett-2310/Pouse/releases).
2. Run the installer:
   - **Per-User (Default):** Installs cleanly into your user application directory (`%LOCALAPPDATA%\Programs\Pouse`) without requiring administrator elevation.
   - **System-Wide:** Can be installed for all users if run as Administrator.
3. Select optional installation tasks:
   - *Create a desktop shortcut*
   - *Start Pouse automatically on Windows startup*
   - *Configure Windows Firewall rule (Port 8081)*
4. Once installed, Pouse launches into your Windows System Tray (notification area).

> [!NOTE]
> Until an EV Authenticode code signing certificate is attached, Windows SmartScreen may display an *"Unknown Publisher"* warning. Click **More info -> Run anyway** to proceed.

### Android Installation
1. Download `app-release.apk` from the official [Pouse GitHub Releases](https://github.com/Anikett-2310/Pouse/releases) (or install via Google Play once published).
2. Open the APK on your Android device and confirm installation.
3. Grant requested permissions:
   - **Nearby Devices / Bluetooth:** Required for discovering and connecting to your PC over Bluetooth without internet.
   - **Camera:** Required for scanning the connection QR code and for the Touchless hand-tracking mode.

---

## 3. First Connection Setup

### A. Wi-Fi Setup (Recommended for Home / Office Networks)
1. Ensure your PC and Android phone are connected to the same local Wi-Fi network.
2. On your PC, left-click the **Pouse tray icon** or right-click and select **Show IP & QR Code**. A window with a QR code and local IP address appears.
3. On your phone, tap **Scan QR Code** and point your camera at the PC screen.
4. The phone automatically connects via WebSocket and exchanges the cryptographic pairing token.
5. If your camera is unavailable, you can manually enter the PC's IP address and port (default: `8081`) shown in the QR window.

### B. Bluetooth Setup (Offline / Travel Mode)
1. Ensure Bluetooth is enabled on both your PC and Android phone.
2. Pair your phone with your Windows PC in standard Windows Bluetooth Settings (`Win + I -> Bluetooth & devices -> Add device`).
3. In the Pouse mobile app, select the **Bluetooth** transport tab.
4. The app scans for your paired PC using Bluetooth Low Energy (BLE) discovery. Tap **Connect**.
5. **TOFU Trust Prompt (Security):**
   - On the first connection, Pouse displays a **Trust This PC?** authorization prompt showing the PC's Bluetooth identity (`BD_ADDR`).
   - Tap **Trust & Authorize**.
   - Input is strictly blocked until you approve. Once trusted, your phone remembers the PC for automatic reconnection.

---

## 4. Input Modes

Switch between modes anytime using the bottom navigation bar:

### 1. Touchpad Mode
- **Move Cursor:** Drag one finger across the surface.
- **Left Click:** Tap with one finger.
- **Right Click:** Tap with two fingers.
- **Double Click:** Double-tap with one finger.
- **Drag & Drop:** Tap and hold, then drag.
- **Vertical / Horizontal Scroll:** Drag two fingers vertically or horizontally.
- **Zoom / Magnifier:** Pinch out to activate Windows Magnifier zoom; pinch in to reduce.
- **Soft Keyboard:** Tap the keyboard icon in the utility dock to send text.

### 2. Motion Mode
- Uses your phone's gyroscope and accelerometer as an air mouse.
- Hold down the center sensor button and tilt/wave your phone to move the PC cursor. Release to freeze cursor position.

### 3. Touchless Mode (Camera Tracking)
- Uses your phone's front camera and on-device MediaPipe vision AI to track hand gestures without touching the screen.
- Wave to move, pinch thumb and index finger to click.

### 4. Gaming Mode
- Transforms your phone into a landscape gamepad with analog stick, directional pad, and action buttons.

---

## 5. Collapsible Utility Dock & OS Actions

At the top of every input screen sits the **Utility Dock**:
- **Expand / Collapse:** Tap or drag the center handle pill to collapse the dock when you need maximum touchpad area, or expand it for utility controls.
- **Remote Screen Shortcut:** One-tap button (`Monitor` icon) to launch Remote Screen.
- **Gesture Guide:** Tap the `Help (?)` icon to open the multi-touch shortcut cheatsheet.
- **OS & Media Actions Panel:**
  - **Volume:** `Vol -`, `Mute`, `Vol +`
  - **Brightness:** `Bright -` (-10%), `Bright +` (+10%)
  - **Windows Search:** Instant `Win + S` shortcut
  - **Task View:** Open Windows virtual desktop overview (`Win + Tab`)
  - **Show Desktop:** Minimize all windows (`Win + D`)
  - **App Switcher:** `Alt + Tab` navigation

---

## 6. Remote Screen (Live PC Mirroring)

Remote Screen streams your PC monitor directly to your phone screen over your local Wi-Fi network at up to 60 FPS:
- **Starting a Session:** Tap the Remote Screen icon in the utility dock.
- **Direct Interaction:** Touch directly on your phone screen to click and interact with PC desktop elements.
- **Wi-Fi Guard:** Because real-time video encoding requires local LAN bandwidth, Remote Screen requires an active Wi-Fi connection. If connected via Bluetooth, Pouse seamlessly uses Wi-Fi for video while keeping Bluetooth active for controls.

---

## 7. Windows Startup & Preferences

Access preferences anytime by right-clicking the tray icon and selecting **Preferences...**:
- **Device Name:** Customize your PC's broadcast name.
- **Start Pouse automatically with Windows:** Automatically starts Pouse minimized to the tray when your PC boots. (Saved in `HKCU\Software\Microsoft\Windows\CurrentVersion\Run`).
- **Compatible Input Mode:** Fallback input mode for legacy applications.
- **Require Wi-Fi Password:** Optional secondary connection password, encrypted using Windows DPAPI.
- **Recent Devices:** View connection history (strictly informational UI history).
- **Reset Pairing Token:** Invalidates previous QR codes and forces reconnection.

---

## 8. Uninstallation

### Windows
- Open **Settings -> Installed apps**, select **Pouse PC Client**, and click **Uninstall**.
- Alternatively, run `unins000.exe` in the installation directory.
- The uninstaller cleanly removes all application binaries, shortcuts, startup registry entries, and Windows Firewall rules.
- Application configuration is stored in `%APPDATA%\Pouse` and can be deleted if you wish to remove all settings.

### Android
- Long-press the **Pouse** app icon on your home screen and select **Uninstall**.
