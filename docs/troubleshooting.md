# Pouse Troubleshooting Guide

**Version:** 1.0.0

This guide addresses common connection, input, security, and hardware questions.

---

## 1. Connection Troubleshooting

### A. PC Not Discovered over Wi-Fi / QR Code Fails
1. **Network Isolation / Guest Networks:** Many public, hotel, or guest Wi-Fi networks block client-to-client traffic (Client Isolation / AP Isolation). Ensure both devices are on a private home or office network, or connect your PC to a mobile hotspot hosted by your phone.
2. **Windows Firewall Blocking Port 8081:**
   - Ensure the Pouse PC Client is allowed through Windows Firewall.
   - Open PowerShell as Administrator and check the rule:
     ```powershell
     Get-NetFirewallRule -DisplayName "Pouse PC Client"
     ```
   - If missing, re-run `Pouse-Setup-v1.0.0.exe` and check *"Configure Windows Firewall rule"*, or manually allow TCP port 8081 for Private networks.
3. **Multiple Network Interfaces:** If your PC has multiple network adapters (Ethernet, Wi-Fi, VPNs, WSL virtual adapters), verify the IP address displayed in the Pouse QR window matches your Wi-Fi subnet (typically `192.168.x.x`). You can manually enter the correct IP in the mobile app.
4. **VPN Interference:** Active VPNs on either your PC or phone can route traffic away from the local subnet. Temporarily disconnect VPNs to verify local connectivity.

### B. Bluetooth Discovery / Connection Issues
1. **Initial OS Pairing Required:** Before connecting in Pouse, your phone must be paired with your Windows PC in standard Windows Bluetooth Settings (`Settings -> Bluetooth & devices -> Add device`).
2. **Bluetooth Adapter Disabled:** Verify Bluetooth is toggled ON on both your PC and phone.
3. **BLE Scan Timeouts:** On Android, ensure Nearby Devices permission is granted. If the PC does not appear in the discovery list, tap the Refresh icon or restart the Pouse mobile app.
4. **Bluetooth Off/On Cycle:** If RFCOMM connection fails with a socket error, toggle Bluetooth OFF and ON in Windows Action Center (`Win + A`), then reconnect in the app.

---

## 2. Security & TOFU (Trust-On-First-Use)

### A. Accidental TOFU Rejection
- If you tapped **Reject** on the "Trust This PC?" prompt on your phone, Pouse strictly blocks all input events from reaching the PC to protect you against rogue hosts.
- To re-authorize:
  1. In the Pouse mobile app, go to Settings / Saved Devices.
  2. Tap **Forget Device** next to the PC.
  3. Reconnect to the PC. The TOFU authorization prompt will re-appear, allowing you to select **Trust & Authorize**.

### B. Wi-Fi Password Rejection
- If the PC has enabled *"Require Wi-Fi Connection Password"* in Preferences:
  - Enter the matching password when prompted on your phone.
  - If you forgot the password, open Preferences on your PC (`Right-click tray icon -> Preferences...`) and enter a new password, or uncheck the requirement. The password on the PC is protected using Windows DPAPI.

---

## 3. Input & Display Controls

### A. Cursor Movement Stutters or Lags
1. **Wi-Fi Latency:** Wi-Fi congestion can cause intermittent packet latency. Switch to Bluetooth mode for guaranteed local low-latency control without network contention.
2. **Compatible Input Mode:** If your cursor stutters in specific full-screen games or legacy applications:
   - Open Preferences on your PC.
   - Enable **Compatible Input Mode (Standard SendInput fallback)**.
   - Click Save.

### B. Brightness Controls (Volume & Brightness Panel)
1. **Internal Laptop Displays:** Supported via Windows WMI (`WmiMonitorBrightness`). Brightness steps up/down by 10% (clamped between 10% and 100%).
2. **External Desktop Monitors:**
   - Supported via DDC/CI protocol (`dxva2.dll`) over DisplayPort / HDMI if your monitor firmware supports programmatic DDC/CI commands.
   - If your monitor firmware does not support DDC/CI or has DDC/CI disabled in its on-screen display (OSD) settings, brightness adjustment returns a clear unsupported error.
   - To enable: Open your monitor's physical hardware menu (OSD) and ensure **DDC/CI** is set to **Enabled**.
3. **Display Limitations:** USB display adapters, virtual display drivers, and certain multi-GPU docking stations do not expose WMI or DDC/CI brightness interfaces; on these displays, brightness adjustment is disabled.

### C. Windows Search Shortcut Not Responding
- The `Search` button in the utility dock triggers the native Windows shortcut `Win + S`. Ensure Windows Search is enabled and not disabled via Group Policy.

---

## 4. Remote Screen Issues

### A. "Wi-Fi Connection Required" Banner
- Remote Screen transmits real-time H.264/DirectX video frames requiring 5–15 Mbps bandwidth.
- Bluetooth RFCOMM bandwidth (typically ~1 Mbps) is insufficient for video streaming.
- If you are connected via Bluetooth, connect your phone to the same Wi-Fi network as the PC; Pouse will automatically use Wi-Fi for video while keeping Bluetooth active for controls.

### B. Black Screen or Stream Freezes
1. **DirectX / Hardware Encoder:** Pouse uses Windows Graphics Capture (WGC) and Windows Media Foundation (MF) hardware encoding. Ensure your PC GPU drivers (Intel, NVIDIA, AMD) are up to date.
2. **Lock Screen / UAC Prompts:** Windows OS security blocks third-party screen capture during Secure Desktop UAC prompts and Windows Lock Screen (`Win + L`). The stream resumes once you log back into your desktop.

---

## 5. Startup & Tray Behavior

### A. Pouse Doesn't Start with Windows
- Verify the setting is enabled in Preferences (`Start Pouse automatically with Windows`).
- Check Windows Task Manager -> **Startup apps** tab (`Ctrl + Shift + Esc`) and ensure **Pouse** is set to **Enabled**.
- Pouse startup runs under your user profile (`HKCU\Software\Microsoft\Windows\CurrentVersion\Run`) and starts minimized to the System Tray.

### B. Tray Icon Disappears or Is Hidden
- Windows 11 often places background tray icons into the overflow drawer. Click the upward arrow (`^`) in the taskbar notification area to find the Pouse icon.
- You can drag the Pouse icon out of the overflow drawer directly onto the visible taskbar.

---

## 6. Installer & Uninstallation

### A. SmartScreen "Unknown Publisher" Warning
- Standard for open-source applications prior to purchasing an EV Authenticode code signing certificate.
- To proceed: Click **More info** -> **Run anyway**.

### B. Clean Uninstallation
- To completely wipe all Pouse files, run the uninstaller via Windows Settings -> Installed apps.
- If you wish to remove stored pairing tokens and preferences, delete the user configuration folder at:
  `%APPDATA%\Pouse`
