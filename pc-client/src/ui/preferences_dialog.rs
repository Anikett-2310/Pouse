use std::sync::atomic::{AtomicBool, AtomicIsize, Ordering};
use windows::core::{HSTRING, PCWSTR};
use windows::Win32::Foundation::{COLORREF, HWND, LPARAM, LRESULT, WPARAM};
use windows::Win32::Graphics::Gdi::{
    BeginPaint, EndPaint, SetBkMode, SetTextColor, TextOutW, HBRUSH, PAINTSTRUCT, TRANSPARENT,
};
use windows::Win32::UI::WindowsAndMessaging::*;

static PREF_WINDOW_OPEN: AtomicBool = AtomicBool::new(false);
static PREF_HWND: AtomicIsize = AtomicIsize::new(0);

const ID_EDIT_NAME: isize = 2001;
const ID_CHK_STARTUP: isize = 2002;
const ID_CHK_WIFI_PASS: isize = 2003;
const ID_EDIT_WIFI_PASS: isize = 2004;
const ID_BTN_SAVE: isize = 2005;
const ID_BTN_RESET_PAIRING: isize = 2006;
const ID_BTN_CANCEL: isize = 2007;
const ID_BTN_SHOW_QR: isize = 2008;
const ID_CHK_COMPAT_INPUT: isize = 2009;
const ID_LIST_RECENT: isize = 2010;

pub fn show_preferences_dialog() {
    if PREF_WINDOW_OPEN.load(Ordering::SeqCst) {
        let hwnd_raw = PREF_HWND.load(Ordering::SeqCst);
        if hwnd_raw != 0 {
            unsafe {
                let _ = SetForegroundWindow(HWND(hwnd_raw as *mut _));
            }
            return;
        }
    }

    std::thread::spawn(|| {
        run_preferences_window();
    });
}

fn run_preferences_window() {
    unsafe {
        let (h_icon_big, h_icon_sm) = super::qr_dialog::load_app_icon();
        let class_name = HSTRING::from("PousePreferencesClass");
        let wnd_class = WNDCLASSW {
            lpfnWndProc: Some(pref_wnd_proc),
            lpszClassName: PCWSTR(class_name.as_ptr()),
            hbrBackground: HBRUSH(6 as *mut _), // COLOR_WINDOW + 1
            hCursor: LoadCursorW(None, IDC_ARROW).unwrap_or_default(),
            hIcon: h_icon_big,
            ..Default::default()
        };

        let _ = RegisterClassW(&wnd_class);

        let title = HSTRING::from("Pouse Preferences");
        let width = 580;
        let height = 570;

        let screen_w = GetSystemMetrics(SM_CXSCREEN);
        let screen_h = GetSystemMetrics(SM_CYSCREEN);
        let x = (screen_w - width) / 2;
        let y = (screen_h - height) / 2;

        let hwnd = match CreateWindowExW(
            WINDOW_EX_STYLE::default(),
            PCWSTR(class_name.as_ptr()),
            PCWSTR(title.as_ptr()),
            WS_OVERLAPPED | WS_CAPTION | WS_SYSMENU | WS_MINIMIZEBOX | WS_VISIBLE,
            x,
            y,
            width,
            height,
            None,
            None,
            None,
            None,
        ) {
            Ok(h) => h,
            Err(_) => return,
        };

        let _ = SendMessageW(hwnd, WM_SETICON, WPARAM(ICON_BIG as usize), LPARAM(h_icon_big.0 as isize));
        let _ = SendMessageW(hwnd, WM_SETICON, WPARAM(ICON_SMALL as usize), LPARAM(h_icon_sm.0 as isize));

        PREF_WINDOW_OPEN.store(true, Ordering::SeqCst);
        PREF_HWND.store(hwnd.0 as isize, Ordering::SeqCst);

        let _ = ShowWindow(hwnd, SW_SHOW);
        let _ = SetForegroundWindow(hwnd);

        let mut msg = MSG::default();
        while GetMessageW(&mut msg, None, 0, 0).into() {
            let _ = TranslateMessage(&msg);
            DispatchMessageW(&msg);
        }

        PREF_WINDOW_OPEN.store(false, Ordering::SeqCst);
        PREF_HWND.store(0, Ordering::SeqCst);
    }
}

unsafe extern "system" fn pref_wnd_proc(
    hwnd: HWND,
    msg: u32,
    wparam: WPARAM,
    lparam: LPARAM,
) -> LRESULT {
    unsafe {
        match msg {
            WM_CREATE => {
                let mgr = crate::config::ConfigManager::global();
                let cfg = mgr.get_config();
                let edit_class = HSTRING::from("EDIT");
                let btn_class = HSTRING::from("BUTTON");
                let list_class = HSTRING::from("LISTBOX");

                // 1. Device Name Input (Y = 18)
                let name_hstr = HSTRING::from(&cfg.general.device_name);
                let _ = CreateWindowExW(
                    WINDOW_EX_STYLE::default(),
                    PCWSTR(edit_class.as_ptr()),
                    PCWSTR(name_hstr.as_ptr()),
                    WS_CHILD | WS_VISIBLE | WS_BORDER | WINDOW_STYLE(ES_AUTOHSCROLL as u32),
                    140,
                    18,
                    390,
                    26,
                    hwnd,
                    HMENU(ID_EDIT_NAME as _),
                    None,
                    None,
                );

                // 2. Show QR Button (Y = 54)
                let show_qr_text = HSTRING::from("Show Connection QR Code...");
                let _ = CreateWindowExW(
                    WINDOW_EX_STYLE::default(),
                    PCWSTR(btn_class.as_ptr()),
                    PCWSTR(show_qr_text.as_ptr()),
                    WS_CHILD | WS_VISIBLE,
                    310,
                    54,
                    220,
                    28,
                    hwnd,
                    HMENU(ID_BTN_SHOW_QR as _),
                    None,
                    None,
                );

                // 3. Startup Checkbox (Y = 94)
                let chk_startup_text = HSTRING::from("Start Pouse automatically with Windows");
                let chk_startup = CreateWindowExW(
                    WINDOW_EX_STYLE::default(),
                    PCWSTR(btn_class.as_ptr()),
                    PCWSTR(chk_startup_text.as_ptr()),
                    WS_CHILD | WS_VISIBLE | WINDOW_STYLE(BS_AUTOCHECKBOX as u32),
                    30,
                    94,
                    500,
                    24,
                    hwnd,
                    HMENU(ID_CHK_STARTUP as _),
                    None,
                    None,
                )
                .unwrap_or_default();

                if cfg.general.start_with_windows {
                    let _ = SendMessageW(chk_startup, BM_SETCHECK, WPARAM(1), LPARAM(0));
                }

                // 4. Compatible Input Mode Checkbox (Y = 124)
                let chk_compat_text =
                    HSTRING::from("Compatible Input Mode (Standard SendInput fallback)");
                let chk_compat = CreateWindowExW(
                    WINDOW_EX_STYLE::default(),
                    PCWSTR(btn_class.as_ptr()),
                    PCWSTR(chk_compat_text.as_ptr()),
                    WS_CHILD | WS_VISIBLE | WINDOW_STYLE(BS_AUTOCHECKBOX as u32),
                    30,
                    124,
                    500,
                    24,
                    hwnd,
                    HMENU(ID_CHK_COMPAT_INPUT as _),
                    None,
                    None,
                )
                .unwrap_or_default();

                if cfg.general.compatible_input_mode {
                    let _ = SendMessageW(chk_compat, BM_SETCHECK, WPARAM(1), LPARAM(0));
                }

                // 5. Recent Devices Listbox (Y = 178)
                // Note: Strictly connection history only. Does not grant trust or input authorization.
                let h_list = CreateWindowExW(
                    WINDOW_EX_STYLE::default(),
                    PCWSTR(list_class.as_ptr()),
                    PCWSTR::null(),
                    WS_CHILD | WS_VISIBLE | WS_BORDER | WS_VSCROLL | WINDOW_STYLE(LBS_NOTIFY as u32),
                    30,
                    178,
                    500,
                    85,
                    hwnd,
                    HMENU(ID_LIST_RECENT as _),
                    None,
                    None,
                )
                .unwrap_or_default();

                if cfg.recent_devices.is_empty() {
                    let none_w = HSTRING::from("No recent devices connected yet");
                    let _ = SendMessageW(h_list, LB_ADDSTRING, WPARAM(0), LPARAM(none_w.as_ptr() as isize));
                } else {
                    for dev in &cfg.recent_devices {
                        let item_text = format!("{} ({}) - {}", dev.name, dev.address, dev.transport);
                        let item_w = HSTRING::from(&item_text);
                        let _ = SendMessageW(h_list, LB_ADDSTRING, WPARAM(0), LPARAM(item_w.as_ptr() as isize));
                    }
                }

                // 6. Security: Wi-Fi Password Checkbox (Y = 276)
                let chk_pass_text = HSTRING::from("Require Wi-Fi Connection Password");
                let chk_pass = CreateWindowExW(
                    WINDOW_EX_STYLE::default(),
                    PCWSTR(btn_class.as_ptr()),
                    PCWSTR(chk_pass_text.as_ptr()),
                    WS_CHILD | WS_VISIBLE | WINDOW_STYLE(BS_AUTOCHECKBOX as u32),
                    30,
                    276,
                    500,
                    24,
                    hwnd,
                    HMENU(ID_CHK_WIFI_PASS as _),
                    None,
                    None,
                )
                .unwrap_or_default();

                if cfg.security.require_wifi_password {
                    let _ = SendMessageW(chk_pass, BM_SETCHECK, WPARAM(1), LPARAM(0));
                }

                // 7. Password Edit Field (Y = 306)
                let existing_pass = mgr.get_wifi_password().unwrap_or_default();
                let pass_hstr = HSTRING::from(&existing_pass);
                let _ = CreateWindowExW(
                    WINDOW_EX_STYLE::default(),
                    PCWSTR(edit_class.as_ptr()),
                    PCWSTR(pass_hstr.as_ptr()),
                    WS_CHILD
                        | WS_VISIBLE
                        | WS_BORDER
                        | WINDOW_STYLE((ES_PASSWORD | ES_AUTOHSCROLL) as u32),
                    140,
                    306,
                    390,
                    26,
                    hwnd,
                    HMENU(ID_EDIT_WIFI_PASS as _),
                    None,
                    None,
                );

                // 8. Reset Pairing Token Button (Y = 372)
                let reset_text = HSTRING::from("Reset Pairing Token");
                let _ = CreateWindowExW(
                    WINDOW_EX_STYLE::default(),
                    PCWSTR(btn_class.as_ptr()),
                    PCWSTR(reset_text.as_ptr()),
                    WS_CHILD | WS_VISIBLE,
                    30,
                    372,
                    180,
                    30,
                    hwnd,
                    HMENU(ID_BTN_RESET_PAIRING as _),
                    None,
                    None,
                );

                // 9. Save & Cancel Action Buttons (Y = 470)
                let save_text = HSTRING::from("Save");
                let _ = CreateWindowExW(
                    WINDOW_EX_STYLE::default(),
                    PCWSTR(btn_class.as_ptr()),
                    PCWSTR(save_text.as_ptr()),
                    WS_CHILD | WS_VISIBLE | WINDOW_STYLE(BS_DEFPUSHBUTTON as u32),
                    320,
                    470,
                    100,
                    32,
                    hwnd,
                    HMENU(ID_BTN_SAVE as _),
                    None,
                    None,
                );

                let cancel_text = HSTRING::from("Cancel");
                let _ = CreateWindowExW(
                    WINDOW_EX_STYLE::default(),
                    PCWSTR(btn_class.as_ptr()),
                    PCWSTR(cancel_text.as_ptr()),
                    WS_CHILD | WS_VISIBLE,
                    430,
                    470,
                    100,
                    32,
                    hwnd,
                    HMENU(ID_BTN_CANCEL as _),
                    None,
                    None,
                );

                LRESULT(0)
            }
            WM_PAINT => {
                let mut ps = PAINTSTRUCT::default();
                let hdc = BeginPaint(hwnd, &mut ps);

                let _ = SetBkMode(hdc, TRANSPARENT);
                let _ = SetTextColor(hdc, COLORREF(0x00222222));

                // General Labels
                let lbl_name: Vec<u16> = "PC Name:".encode_utf16().collect();
                let _ = TextOutW(hdc, 30, 22, &lbl_name);

                let payload = crate::pairing::PairingPayload::new(8081, false);
                let host_str = format!("Host / IP: {}:{}", payload.host, payload.port);
                let host_w: Vec<u16> = host_str.encode_utf16().collect();
                let _ = TextOutW(hdc, 30, 60, &host_w);

                let recent_header: Vec<u16> =
                    "Recent Devices (UI History only — does not authorize input):"
                        .encode_utf16()
                        .collect();
                let _ = TextOutW(hdc, 30, 156, &recent_header);

                // Security Labels
                let lbl_pass: Vec<u16> = "Password:".encode_utf16().collect();
                let _ = TextOutW(hdc, 30, 310, &lbl_pass);

                let note: Vec<u16> =
                    "Note: Password is encrypted with Windows DPAPI (zero plaintext storage)."
                        .encode_utf16()
                        .collect();
                let _ = TextOutW(hdc, 30, 342, &note);

                let reset_hint: Vec<u16> =
                    "Resetting disconnects currently paired devices."
                        .encode_utf16()
                        .collect();
                let _ = TextOutW(hdc, 225, 378, &reset_hint);

                let _ = EndPaint(hwnd, &ps);
                LRESULT(0)
            }
            WM_COMMAND => {
                let id = (wparam.0 & 0xFFFF) as isize;
                match id {
                    ID_BTN_SHOW_QR => {
                        crate::ui::qr_dialog::show_qr_dialog();
                    }
                    ID_BTN_CANCEL => {
                        let _ = DestroyWindow(hwnd);
                    }
                    ID_BTN_RESET_PAIRING => {
                        let confirm_title = HSTRING::from("Confirm Reset");
                        let confirm_msg = HSTRING::from("Resetting the pairing token will disconnect currently paired mobile devices.\nDo you want to continue?");
                        let res = MessageBoxW(
                            hwnd,
                            PCWSTR(confirm_msg.as_ptr()),
                            PCWSTR(confirm_title.as_ptr()),
                            MB_YESNO | MB_ICONWARNING,
                        );
                        if res == IDYES {
                            let new_token = crate::pairing::generate_random_token();
                            crate::config::ConfigManager::global().set_pair_token(new_token);
                            let done_msg = HSTRING::from(
                                "Pairing token reset. Scan the QR code on your phone to re-pair.",
                            );
                            let _ = MessageBoxW(
                                hwnd,
                                PCWSTR(done_msg.as_ptr()),
                                PCWSTR(confirm_title.as_ptr()),
                                MB_OK | MB_ICONINFORMATION,
                            );
                        }
                    }
                    ID_BTN_SAVE => {
                        // 1. Read Device Name
                        let mut name_buf = [0u16; 128];
                        let h_edit = GetDlgItem(hwnd, ID_EDIT_NAME as i32).unwrap_or_default();
                        let len = GetWindowTextW(h_edit, &mut name_buf);
                        let new_name = String::from_utf16_lossy(&name_buf[..len as usize])
                            .trim()
                            .to_string();

                        // 2. Read Startup Checkbox
                        let h_startup = GetDlgItem(hwnd, ID_CHK_STARTUP as i32).unwrap_or_default();
                        let is_startup =
                            SendMessageW(h_startup, BM_GETCHECK, WPARAM(0), LPARAM(0)).0 == 1;

                        // 3. Read Compatible Input Mode Checkbox
                        let h_compat =
                            GetDlgItem(hwnd, ID_CHK_COMPAT_INPUT as i32).unwrap_or_default();
                        let is_compat =
                            SendMessageW(h_compat, BM_GETCHECK, WPARAM(0), LPARAM(0)).0 == 1;

                        // 4. Read Password Checkbox & Text
                        let h_chk_pass =
                            GetDlgItem(hwnd, ID_CHK_WIFI_PASS as i32).unwrap_or_default();
                        let req_pass =
                            SendMessageW(h_chk_pass, BM_GETCHECK, WPARAM(0), LPARAM(0)).0 == 1;

                        let mut pass_buf = [0u16; 128];
                        let h_pass = GetDlgItem(hwnd, ID_EDIT_WIFI_PASS as i32).unwrap_or_default();
                        let pass_len = GetWindowTextW(h_pass, &mut pass_buf);
                        let pass_str = String::from_utf16_lossy(&pass_buf[..pass_len as usize])
                            .trim()
                            .to_string();

                        // Update Config
                        let mgr = crate::config::ConfigManager::global();
                        let mut cfg = mgr.get_config();
                        if !new_name.is_empty() {
                            cfg.general.device_name = new_name;
                        }
                        cfg.general.start_with_windows = is_startup;
                        cfg.general.compatible_input_mode = is_compat;
                        cfg.security.require_wifi_password = req_pass;
                        mgr.set_config(cfg);

                        // Sync Windows Startup registry
                        let _ = crate::config::set_windows_startup(is_startup);

                        // Sync DPAPI password
                        if req_pass && !pass_str.is_empty() {
                            let _ = mgr.set_wifi_password(Some(&pass_str));
                        } else {
                            let _ = mgr.set_wifi_password(None);
                        }

                        mgr.save();
                        let _ = DestroyWindow(hwnd);
                    }
                    _ => {}
                }
                LRESULT(0)
            }
            WM_CLOSE => {
                let _ = DestroyWindow(hwnd);
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
