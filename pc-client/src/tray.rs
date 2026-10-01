use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::mpsc::Sender;
use std::sync::OnceLock;
use windows::core::{HSTRING, PCWSTR};
use windows::Win32::Foundation::{HWND, LPARAM, LRESULT, POINT, WPARAM};
use windows::Win32::UI::Shell::{
    Shell_NotifyIconW, NIF_ICON, NIF_MESSAGE, NIF_TIP, NIM_ADD, NIM_DELETE, NOTIFYICONDATAW,
};
use windows::Win32::UI::WindowsAndMessaging::*;

const WM_TRAY_CALLBACK: u32 = WM_USER + 101;

const IDM_HEADER: usize = 3001;
const IDM_SHOW_QR: usize = 3002;
const IDM_PREFERENCES: usize = 3003;
const IDM_CHECK_UPDATES: usize = 3004;
const IDM_QUIT: usize = 3005;

static SHUTDOWN_TX: OnceLock<Sender<()>> = OnceLock::new();
static TRAY_RUNNING: AtomicBool = AtomicBool::new(false);

pub struct SystemTray {
    hwnd: HWND,
}

impl SystemTray {
    pub fn new(shutdown_tx: Sender<()>) -> Result<Self, String> {
        let _ = SHUTDOWN_TX.set(shutdown_tx);
        unsafe {
            let class_name = HSTRING::from("PouseTrayMessageWindowClass");
            let wnd_class = WNDCLASSW {
                lpfnWndProc: Some(tray_wnd_proc),
                lpszClassName: PCWSTR(class_name.as_ptr()),
                ..Default::default()
            };

            let _ = RegisterClassW(&wnd_class);

            let hwnd = CreateWindowExW(
                WINDOW_EX_STYLE::default(),
                PCWSTR(class_name.as_ptr()),
                PCWSTR(class_name.as_ptr()),
                WINDOW_STYLE::default(),
                0,
                0,
                0,
                0,
                None, // Message-only or hidden top-level window
                None,
                None,
                None,
            ).map_err(|e| format!("Failed to create tray message window: {:?}", e))?;

            // Add icon to system notification area
            let mut nid = NOTIFYICONDATAW {
                cbSize: std::mem::size_of::<NOTIFYICONDATAW>() as u32,
                hWnd: hwnd,
                uID: 1,
                uFlags: NIF_MESSAGE | NIF_ICON | NIF_TIP,
                uCallbackMessage: WM_TRAY_CALLBACK,
                hIcon: LoadIconW(None, IDI_APPLICATION).unwrap_or_default(),
                ..Default::default()
            };

            let tip = "Pouse PC Client";
            let tip_u16: Vec<u16> = tip.encode_utf16().collect();
            for (i, &c) in tip_u16.iter().enumerate().take(nid.szTip.len() - 1) {
                nid.szTip[i] = c;
            }

            let ok = Shell_NotifyIconW(NIM_ADD, &nid);
            if !ok.as_bool() {
                eprintln!("[TRAY] Warning: Shell_NotifyIconW(NIM_ADD) returned false");
            } else {
                println!("[TRAY] System tray icon registered successfully.");
            }

            TRAY_RUNNING.store(true, Ordering::SeqCst);
            Ok(Self { hwnd })
        }
    }

    /// Enter the Win32 message pump on the current thread until WM_QUIT is received.
    pub fn run_message_loop(&self) {
        unsafe {
            let mut msg = MSG::default();
            while GetMessageW(&mut msg, None, 0, 0).into() {
                let _ = TranslateMessage(&msg);
                DispatchMessageW(&msg);
            }
        }
        self.cleanup();
    }

    pub fn cleanup(&self) {
        if TRAY_RUNNING.swap(false, Ordering::SeqCst) {
            unsafe {
                let mut nid = NOTIFYICONDATAW {
                    cbSize: std::mem::size_of::<NOTIFYICONDATAW>() as u32,
                    hWnd: self.hwnd,
                    uID: 1,
                    ..Default::default()
                };
                let _ = Shell_NotifyIconW(NIM_DELETE, &mut nid);
                let _ = DestroyWindow(self.hwnd);
            }
            println!("[TRAY] System tray icon removed cleanly.");
        }
    }
}

unsafe extern "system" fn tray_wnd_proc(
    hwnd: HWND,
    msg: u32,
    wparam: WPARAM,
    lparam: LPARAM,
) -> LRESULT {
    unsafe {
        match msg {
            WM_TRAY_CALLBACK => {
                let event = (lparam.0 & 0xFFFF) as u32;
                match event {
                    WM_RBUTTONUP | WM_CONTEXTMENU => {
                        show_tray_popup_menu(hwnd);
                    }
                    WM_LBUTTONUP | WM_LBUTTONDBLCLK => {
                        crate::ui::qr_dialog::show_qr_dialog();
                    }
                    _ => {}
                }
                LRESULT(0)
            }
            WM_COMMAND => {
                let id = (wparam.0 & 0xFFFF) as usize;
                match id {
                    IDM_SHOW_QR => {
                        crate::ui::qr_dialog::show_qr_dialog();
                    }
                    IDM_PREFERENCES => {
                        crate::ui::preferences_dialog::show_preferences_dialog();
                    }
                    IDM_CHECK_UPDATES => {
                        check_for_updates_informational(hwnd);
                    }
                    IDM_QUIT => {
                        println!("[TRAY] User clicked Quit Pouse from tray menu.");
                        if let Some(tx) = SHUTDOWN_TX.get() {
                            let _ = tx.send(());
                        }
                        PostQuitMessage(0);
                    }
                    _ => {}
                }
                LRESULT(0)
            }
            WM_DESTROY => {
                PostQuitMessage(0);
                LRESULT(0)
            }
            _ => DefWindowProcW(hwnd, msg, wparam, lparam),
        }
    }
}

unsafe fn show_tray_popup_menu(hwnd: HWND) {
    unsafe {
        let menu = match CreatePopupMenu() {
            Ok(m) => m,
            Err(_) => return,
        };

        let header = HSTRING::from("Pouse PC Client");
        let show_qr = HSTRING::from("Show IP && QR Code");
        let prefs = HSTRING::from("Preferences...");
        let updates = HSTRING::from("Check for Updates...");
        let quit = HSTRING::from("Quit Pouse");

        let _ = AppendMenuW(menu, MF_STRING | MF_GRAYED, IDM_HEADER, PCWSTR(header.as_ptr()));
        let _ = AppendMenuW(menu, MF_SEPARATOR, 0, PCWSTR::null());
        let _ = AppendMenuW(menu, MF_STRING, IDM_SHOW_QR, PCWSTR(show_qr.as_ptr()));
        let _ = AppendMenuW(menu, MF_STRING, IDM_PREFERENCES, PCWSTR(prefs.as_ptr()));
        let _ = AppendMenuW(menu, MF_STRING, IDM_CHECK_UPDATES, PCWSTR(updates.as_ptr()));
        let _ = AppendMenuW(menu, MF_SEPARATOR, 0, PCWSTR::null());
        let _ = AppendMenuW(menu, MF_STRING, IDM_QUIT, PCWSTR(quit.as_ptr()));

        let mut pt = POINT::default();
        let _ = GetCursorPos(&mut pt);

        // Required by Shell_NotifyIcon documentation to make popup menus dismiss properly
        let _ = SetForegroundWindow(hwnd);
        let _ = TrackPopupMenuEx(
            menu,
            TPM_RIGHTBUTTON.0,
            pt.x,
            pt.y,
            hwnd,
            None,
        );
        let _ = PostMessageW(hwnd, WM_NULL, WPARAM(0), LPARAM(0));
        let _ = DestroyMenu(menu);
    }
}

/// Phase 5C Informational Update Check:
/// Compares local CARGO_PKG_VERSION against official GitHub Releases URL.
/// Strictly informational: opens release page in browser if new version exists.
/// Never downloads or executes arbitrary binaries automatically.
fn check_for_updates_informational(hwnd: HWND) {
    let hwnd_raw = hwnd.0 as isize;
    std::thread::spawn(move || {
        let hwnd = HWND(hwnd_raw as *mut _);
        let current_version = env!("CARGO_PKG_VERSION");
        let title = HSTRING::from("Pouse Update Check");

        // Inform user checking is in progress or query GitHub API
        let client = std::process::Command::new("powershell")
            .args(["-NoProfile", "-WindowStyle", "Hidden", "-Command",
                "try { (Invoke-RestMethod -Uri 'https://api.github.com/repos/Anikett-2310/Pouse/releases/latest' -UserAgent 'PouseUpdateCheck').tag_name } catch { 'ERROR' }"])
            .output();

        let latest_tag = if let Ok(out) = client {
            String::from_utf8_lossy(&out.stdout).trim().to_string()
        } else {
            "ERROR".to_string()
        };

        if latest_tag.is_empty() || latest_tag == "ERROR" {
            let msg = HSTRING::from(format!(
                "Pouse version: v{}\nCould not reach GitHub Releases API.\nPlease check https://github.com/Anikett-2310/Pouse/releases manually.",
                current_version
            ));
            unsafe {
                let _ = MessageBoxW(hwnd, PCWSTR(msg.as_ptr()), PCWSTR(title.as_ptr()), MB_OK | MB_ICONINFORMATION);
            }
        } else {
            let clean_latest = latest_tag.trim_start_matches('v');
            if clean_latest > current_version {
                let msg = HSTRING::from(format!(
                    "A new version of Pouse is available!\n\nCurrent: v{}\nLatest:  {}\n\nClick OK to open the official release page in your browser.",
                    current_version, latest_tag
                ));
                let res = unsafe {
                    MessageBoxW(hwnd, PCWSTR(msg.as_ptr()), PCWSTR(title.as_ptr()), MB_OKCANCEL | MB_ICONINFORMATION)
                };
                if res == IDOK {
                    let url = format!("https://github.com/Anikett-2310/Pouse/releases/tag/{}", latest_tag);
                    let _ = std::process::Command::new("rundll32")
                        .args(["url.dll,FileProtocolHandler", &url])
                        .spawn();
                }
            } else {
                let msg = HSTRING::from(format!(
                    "You are running the latest version of Pouse (v{}).",
                    current_version
                ));
                unsafe {
                    let _ = MessageBoxW(hwnd, PCWSTR(msg.as_ptr()), PCWSTR(title.as_ptr()), MB_OK | MB_ICONINFORMATION);
                }
            }
        }
    });
}
