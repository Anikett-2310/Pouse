; =====================================================================
; Pouse PC Client — Inno Setup Installer Script
; =====================================================================
; Builds a Windows standalone installer packaging pc-client.exe.
;
; Prerequisites:
;   1. Build release binary: cargo build --release --bin pc-client
;   2. (Optional) Sign pc-client.exe with Authenticode before compilation
;   3. Compile installer with Inno Setup Compiler (iscc.exe)
;      Example: iscc.exe /DAppVersion=1.0.0 pc-client\installer\pouse_setup.iss
; =====================================================================

#define MyAppName "Pouse PC Client"
#ifndef MyAppVersion
  #define MyAppVersion "1.0.0"
#endif
#define MyAppPublisher "Pouse Project"
#define MyAppURL "https://github.com/Anikett-2310/Pouse"
#define MyAppExeName "pc-client.exe"

[Setup]
AppId={{5E97D4F2-4821-4F2A-A816-C6E7216A427F}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
AppSupportURL={#MyAppURL}
AppUpdatesURL={#MyAppURL}
DefaultDirName={autopf}\Pouse
DefaultGroupName=Pouse
AllowNoIcons=yes
OutputDir=Output
OutputBaseFilename=Pouse-Setup-v{#MyAppVersion}
SetupIconFile=..\assets\pouse.ico
Compression=lzma2/ultra64
SolidCompression=yes
WizardStyle=modern
ArchitecturesInstallIn64BitMode=x64compatible
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog commandline
UsedUserAreasWarning=no
#ifdef SignTool
SignTool={#SignTool}
SignedUninstaller=yes
#endif

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked
Name: "startup"; Description: "Start Pouse automatically on Windows startup"; GroupDescription: "Startup options:"; Flags: unchecked
Name: "firewall"; Description: "Configure Windows Firewall rule for Wi-Fi connection (TCP Port 8081, Private networks)"; GroupDescription: "Network configuration:"; Flags: checkedonce

[Files]
Source: "..\target\release\{#MyAppExeName}"; DestDir: "{app}"; Flags: ignoreversion

[Registry]
Root: HKCU; Subkey: "Software\Microsoft\Windows\CurrentVersion\Run"; ValueType: string; ValueName: "Pouse"; ValueData: """{app}\{#MyAppExeName}"""; Tasks: startup; Flags: uninsdeletevalue

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{group}\{cm:UninstallProgram,{#MyAppName}}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
; Inbound Windows Firewall rule for Pouse PC Client (TCP 8081 on Private/Domain networks)
Filename: "{sys}\netsh.exe"; Parameters: "advfirewall firewall add rule name=""Pouse PC Client"" dir=in action=allow program=""{app}\{#MyAppExeName}"" enable=yes protocol=TCP localport=8081 profile=private,domain"; Flags: runhidden; StatusMsg: "Configuring Windows Firewall rule..."; Tasks: firewall; Check: IsAdminInstallMode
Filename: "{app}\{#MyAppExeName}"; Description: "{cm:LaunchProgram,{#StringChange(MyAppName, '&', '&&')}}"; Flags: nowait postinstall skipifsilent

[UninstallRun]
; Remove inbound Windows Firewall rule on clean uninstall
Filename: "{sys}\netsh.exe"; Parameters: "advfirewall firewall delete rule name=""Pouse PC Client"" program=""{app}\{#MyAppExeName}"""; RunOnceId: "DelFirewallRule"; Flags: runhidden; Check: IsAdminInstallMode
