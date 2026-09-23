========================================================================
                      Pouse — Pocket Mouse (PC Client)
========================================================================

Pouse turns your smartphone into a wireless touchpad, mouse, and keyboard 
for your computer.

------------------------------------------------------------------------
REQUIREMENTS
------------------------------------------------------------------------
- Windows PC (Windows 10 or 11)
- Android phone with the Pouse Android app installed (.apk)
- Both your PC and phone connected to the same Wi-Fi network (or laptop mobile hotspot)

------------------------------------------------------------------------
QUICK START STEPS
------------------------------------------------------------------------
1. Extract the "Pouse-PC" folder to any convenient location on your PC.
2. Double-click "Pouse.exe" to launch the Pouse PC server.
3. If Windows Defender Firewall prompts you for network access permission, 
   select "Private networks" and click "Allow access".
4. The Pouse window will display your PC Name, Local IP Address, and a 
   QR code.
5. Open the Pouse app on your Android smartphone.
6. Tap the QR scanner icon next to the IP address box on your phone screen.
7. Point your phone camera at the QR code displayed in the Pouse PC window.
8. The phone app will automatically pair and display "CONNECTED".
9. Move your finger on the phone screen to control your PC mouse cursor!
10. Close the "Pouse.exe" window when you are finished using Pouse.

------------------------------------------------------------------------
TROUBLESHOOTING GUIDE
------------------------------------------------------------------------

[Problem 1: Phone and PC are not connecting]
- Make sure both your phone and PC are connected to the exact same Wi-Fi network.
- If using a router with isolated Guest Wi-Fi networks, switch both devices to 
  the main Wi-Fi network.
- Alternatively, enable "Mobile Hotspot" on your Windows laptop and connect 
  your phone directly to your laptop's hotspot.

[Problem 2: Windows Firewall is blocking the connection]
- Open the Windows Start menu, search for "Allow an app through Windows Firewall", 
  and click on it.
- Click "Change settings", find "Pouse" (or "pc-client"), and ensure the "Private" 
  checkbox is checked.
- Click OK and re-launch Pouse.exe.

[Problem 3: Camera QR scanner fails to scan]
- Ensure camera permissions are allowed on your phone.
- If scanning does not work, use the Manual IP Fallback:
  Look at the "Local IP Address" printed in the Pouse PC window (for example: 192.168.1.100).
  Type this IP address directly into the IP text box in the Pouse phone app, 
  and tap the "Connect" button.

[Problem 4: Mouse controls work, but UAC Administrator windows don't respond]
- Windows security prevents software input on administrative UAC prompts.
  If you need to control administrator windows, right-click "Pouse.exe" on your PC 
  and select "Run as administrator".

------------------------------------------------------------------------
SUPPORT & INFO
------------------------------------------------------------------------
Pouse V1 — Pocket Mouse Architecture
Local Wi-Fi WebSocket Protocol (Port 8081)
No cloud dependency or external servers required.
========================================================================
