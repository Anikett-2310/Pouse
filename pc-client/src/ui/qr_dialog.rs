use std::sync::atomic::{AtomicBool, AtomicIsize, Ordering};
use windows::core::{HSTRING, PCWSTR};
use windows::Win32::Foundation::{COLORREF, HWND, LPARAM, LRESULT, RECT, WPARAM};
use windows::Win32::Graphics::Gdi::{
    BeginPaint, CreateSolidBrush, DeleteObject, EndPaint, FillRect, SetBkMode,
    SetTextColor, TextOutW, HBRUSH, PAINTSTRUCT, TRANSPARENT,
};
use windows::Win32::UI::WindowsAndMessaging::*;

static QR_WINDOW_OPEN: AtomicBool = AtomicBool::new(false);
static LAST_HWND: AtomicIsize = AtomicIsize::new(0);

pub fn show_qr_dialog() {
    if QR_WINDOW_OPEN.load(Ordering::SeqCst) {
        let hwnd_raw = LAST_HWND.load(Ordering::SeqCst);
        if hwnd_raw != 0 {
            unsafe {
                let _ = SetForegroundWindow(HWND(hwnd_raw as *mut _));
            }
            return;
        }
    }

    std::thread::spawn(|| {
        run_qr_window();
    });
}

fn run_qr_window() {
    unsafe {
        let (h_icon_big, h_icon_sm) = load_app_icon();
        let class_name = HSTRING::from("PouseQRDialogClass");
        let wnd_class = WNDCLASSW {
            lpfnWndProc: Some(qr_wnd_proc),
            lpszClassName: PCWSTR(class_name.as_ptr()),
            hbrBackground: HBRUSH(6 as *mut _), // COLOR_WINDOW + 1 (white)
            hCursor: LoadCursorW(None, IDC_ARROW).unwrap_or_default(),
            hIcon: h_icon_big,
            ..Default::default()
        };

        let _ = RegisterClassW(&wnd_class);

        let title = HSTRING::from("Pouse — Connect Mobile App");
        let width = 420;
        let height = 520;

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

        QR_WINDOW_OPEN.store(true, Ordering::SeqCst);
        LAST_HWND.store(hwnd.0 as isize, Ordering::SeqCst);

        let _ = ShowWindow(hwnd, SW_SHOW);
        let _ = SetForegroundWindow(hwnd);

        let mut msg = MSG::default();
        while GetMessageW(&mut msg, None, 0, 0).into() {
            let _ = TranslateMessage(&msg);
            DispatchMessageW(&msg);
        }

        QR_WINDOW_OPEN.store(false, Ordering::SeqCst);
        LAST_HWND.store(0, Ordering::SeqCst);
    }
}

unsafe extern "system" fn qr_wnd_proc(
    hwnd: HWND,
    msg: u32,
    wparam: WPARAM,
    lparam: LPARAM,
) -> LRESULT {
    unsafe {
        match msg {
            WM_PAINT => {
                let mut ps = PAINTSTRUCT::default();
                let hdc = BeginPaint(hwnd, &mut ps);

                // Fetch pairing payload without logging secret
                let payload = crate::pairing::PairingPayload::new(8081, false);
                let json_str = payload.to_json();
                let host_info = format!("Server: ws://{}:{}", payload.host, payload.port);
                let pc_info = format!("PC Name: {}", payload.name);
                let scan_tip = "Scan this QR code with the Pouse Mobile App to pair:";

                let _ = SetBkMode(hdc, TRANSPARENT);
                let _ = SetTextColor(hdc, COLORREF(0x00222222));

                // Header text
                let host_w: Vec<u16> = host_info.encode_utf16().collect();
                let _ = TextOutW(hdc, 20, 15, &host_w);

                let pc_w: Vec<u16> = pc_info.encode_utf16().collect();
                let _ = TextOutW(hdc, 20, 35, &pc_w);

                let tip_w: Vec<u16> = scan_tip.encode_utf16().collect();
                let _ = TextOutW(hdc, 20, 60, &tip_w);

                // Render QR Code in 300x300 box
                if let Ok(code) = qrcode::QrCode::new(json_str.as_bytes()) {
                    let qr_width = code.width();
                    let display_size = 280;
                    let module_size = (display_size / qr_width).max(1);
                    let start_x = (420 - (module_size * qr_width)) / 2;
                    let start_y = 90;

                    let black_brush = CreateSolidBrush(COLORREF(0x00000000));
                    let white_brush = CreateSolidBrush(COLORREF(0x00FFFFFF));

                    // Background border rect
                    let bg_rect = RECT {
                        left: start_x as i32 - 10,
                        top: start_y as i32 - 10,
                        right: (start_x + module_size * qr_width) as i32 + 10,
                        bottom: (start_y + module_size * qr_width) as i32 + 10,
                    };
                    FillRect(hdc, &bg_rect, white_brush);

                    // Draw QR modules
                    let colors = code.to_colors();
                    for row in 0..qr_width {
                        for col in 0..qr_width {
                            let color = colors[row * qr_width + col];
                            if color == qrcode::Color::Dark {
                                let rect = RECT {
                                    left: (start_x + col * module_size) as i32,
                                    top: (start_y + row * module_size) as i32,
                                    right: (start_x + (col + 1) * module_size) as i32,
                                    bottom: (start_y + (row + 1) * module_size) as i32,
                                };
                                FillRect(hdc, &rect, black_brush);
                            }
                        }
                    }

                    let _ = DeleteObject(black_brush);
                    let _ = DeleteObject(white_brush);
                }

                // Footer note (strict no secret logging / exposure)
                let note = "Keep this screen visible during first-time pairing.";
                let note_w: Vec<u16> = note.encode_utf16().collect();
                let _ = TextOutW(hdc, 50, 420, &note_w);

                let _ = EndPaint(hwnd, &ps);
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

pub(crate) unsafe fn load_app_icon() -> (HICON, HICON) {
    unsafe {
        let mut h_big = HICON::default();
        let mut h_sm = HICON::default();

        // 1. Try loading Resource 1 from compiled PE
        if let Ok(hinstance) = windows::Win32::System::LibraryLoader::GetModuleHandleW(None) {
            if let Ok(handle) = LoadImageW(
                hinstance,
                PCWSTR(1 as *const u16),
                IMAGE_ICON,
                GetSystemMetrics(SM_CXICON),
                GetSystemMetrics(SM_CYICON),
                LR_DEFAULTCOLOR,
            ) {
                h_big = HICON(handle.0);
            }
            if let Ok(handle) = LoadImageW(
                hinstance,
                PCWSTR(1 as *const u16),
                IMAGE_ICON,
                GetSystemMetrics(SM_CXSMICON),
                GetSystemMetrics(SM_CYSMICON),
                LR_DEFAULTCOLOR,
            ) {
                h_sm = HICON(handle.0);
            }
        }

        // 2. Try loading from file assets/pouse.ico if resource not yet bound
        if h_big.is_invalid() || h_big.0.is_null() {
            for path in ["assets/pouse.ico", "../assets/pouse.ico"] {
                let wide: Vec<u16> = path.encode_utf16().chain(std::iter::once(0)).collect();
                if let Ok(handle) = LoadImageW(
                    None,
                    PCWSTR(wide.as_ptr()),
                    IMAGE_ICON,
                    GetSystemMetrics(SM_CXICON),
                    GetSystemMetrics(SM_CYICON),
                    LR_LOADFROMFILE | LR_DEFAULTCOLOR,
                ) {
                    h_big = HICON(handle.0);
                }
                if let Ok(handle) = LoadImageW(
                    None,
                    PCWSTR(wide.as_ptr()),
                    IMAGE_ICON,
                    GetSystemMetrics(SM_CXSMICON),
                    GetSystemMetrics(SM_CYSMICON),
                    LR_LOADFROMFILE | LR_DEFAULTCOLOR,
                ) {
                    h_sm = HICON(handle.0);
                }
                if !h_big.is_invalid() && !h_big.0.is_null() {
                    break;
                }
            }
        }

        if h_big.is_invalid() || h_big.0.is_null() {
            h_big = LoadIconW(None, IDI_APPLICATION).unwrap_or_default();
        }
        if h_sm.is_invalid() || h_sm.0.is_null() {
            h_sm = h_big;
        }

        (h_big, h_sm)
    }
}
