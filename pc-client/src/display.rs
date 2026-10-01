use std::process::Command;
use std::sync::atomic::{AtomicBool, AtomicI32, AtomicIsize, Ordering};
#[cfg(target_os = "windows")]
use std::os::windows::process::CommandExt;

const CREATE_NO_WINDOW: u32 = 0x08000000;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum BrightnessBackend {
    Unsupported = 0,
    Wmi = 1,
    DdcCi = 2,
}

static BACKEND: AtomicI32 = AtomicI32::new(BrightnessBackend::Unsupported as i32);
static CURRENT_BRIGHTNESS: AtomicI32 = AtomicI32::new(100);
static INITIALIZED: AtomicBool = AtomicBool::new(false);
static DDC_MONITOR_HANDLE: AtomicIsize = AtomicIsize::new(0);

#[derive(Clone, Copy)]
#[repr(C)]
struct PhysicalMonitor {
    h_physical_monitor: *mut std::ffi::c_void,
    sz_physical_monitor_description: [u16; 128],
}

type GetNumberOfPhysicalMonitorsFn =
    unsafe extern "system" fn(*mut std::ffi::c_void, *mut u32) -> i32;
type GetPhysicalMonitorsFn =
    unsafe extern "system" fn(*mut std::ffi::c_void, u32, *mut PhysicalMonitor) -> i32;
type GetMonitorBrightnessFn =
    unsafe extern "system" fn(*mut std::ffi::c_void, *mut u32, *mut u32, *mut u32) -> i32;
type SetMonitorBrightnessFn =
    unsafe extern "system" fn(*mut std::ffi::c_void, u32) -> i32;

/// Probe Windows display brightness support:
/// 1. Internal laptop/WinRT displays via WMI (WmiMonitorBrightness).
/// 2. External monitors via DDC/CI (dxva2.dll).
/// 3. If neither is available, brightness is strictly marked Unsupported.
pub fn init_brightness_support() {
    if INITIALIZED.swap(true, Ordering::SeqCst) {
        return;
    }

    #[cfg(target_os = "windows")]
    {
        // 1. Probe WMI for internal laptop displays
        if let Some(wmi_level) = probe_wmi() {
            CURRENT_BRIGHTNESS.store(wmi_level, Ordering::Relaxed);
            BACKEND.store(BrightnessBackend::Wmi as i32, Ordering::SeqCst);
            println!(
                "[DISPLAY] Internal display brightness control active via WMI (initial level: {}%)",
                wmi_level
            );
            return;
        }

        // 2. Probe DDC/CI via dxva2.dll for external desktop monitors
        if let Some((handle, ddc_level)) = probe_ddc_ci() {
            DDC_MONITOR_HANDLE.store(handle, Ordering::SeqCst);
            CURRENT_BRIGHTNESS.store(ddc_level, Ordering::Relaxed);
            BACKEND.store(BrightnessBackend::DdcCi as i32, Ordering::SeqCst);
            println!(
                "[DISPLAY] External monitor brightness control active via DDC/CI (initial level: {}%)",
                ddc_level
            );
            return;
        }
    }

    // 3. Neither supported
    BACKEND.store(BrightnessBackend::Unsupported as i32, Ordering::SeqCst);
    println!("[DISPLAY] Brightness control NOT supported on this display configuration (WMI & DDC/CI unavailable)");
}

#[cfg(target_os = "windows")]
fn probe_wmi() -> Option<i32> {
    let mut cmd = Command::new("powershell");
    cmd.args([
        "-NoProfile",
        "-WindowStyle",
        "Hidden",
        "-Command",
        "(Get-CimInstance -Namespace root/wmi -ClassName WmiMonitorBrightness -ErrorAction SilentlyContinue).CurrentBrightness",
    ]);
    cmd.creation_flags(CREATE_NO_WINDOW);

    if let Ok(output) = cmd.output() {
        if output.status.success() {
            let text = String::from_utf8_lossy(&output.stdout).trim().to_string();
            if let Ok(val) = text.parse::<i32>() {
                return Some(val.clamp(0, 100));
            }
        }
    }
    None
}

#[cfg(target_os = "windows")]
fn probe_ddc_ci() -> Option<(isize, i32)> {
    use windows::core::s;
    use windows::Win32::Foundation::{BOOL, LPARAM, RECT};
    use windows::Win32::Graphics::Gdi::{EnumDisplayMonitors, HDC, HMONITOR};
    use windows::Win32::System::LibraryLoader::{GetProcAddress, LoadLibraryA};

    unsafe {
        let dxva2 = LoadLibraryA(s!("dxva2.dll")).ok()?;
        let get_count_proc = GetProcAddress(dxva2, s!("GetNumberOfPhysicalMonitorsFromHMONITOR"))?;
        let get_mons_proc = GetProcAddress(dxva2, s!("GetPhysicalMonitorsFromHMONITOR"))?;
        let get_bright_proc = GetProcAddress(dxva2, s!("GetMonitorBrightness"))?;

        let get_count: GetNumberOfPhysicalMonitorsFn = std::mem::transmute(get_count_proc);
        let get_mons: GetPhysicalMonitorsFn = std::mem::transmute(get_mons_proc);
        let get_bright: GetMonitorBrightnessFn = std::mem::transmute(get_bright_proc);

        unsafe extern "system" fn enum_proc(
            hmon: HMONITOR,
            _hdc: HDC,
            _rect: *mut RECT,
            lparam: LPARAM,
        ) -> BOOL {
            unsafe {
                let list = &mut *(lparam.0 as *mut Vec<HMONITOR>);
                list.push(hmon);
                BOOL(1)
            }
        }

        let mut hmon_list = Vec::<HMONITOR>::new();
        let _ = EnumDisplayMonitors(
            HDC::default(),
            None,
            Some(enum_proc),
            LPARAM(&mut hmon_list as *mut _ as isize),
        );

        for hmon in hmon_list {
            let mut num_physical: u32 = 0;
            if get_count(hmon.0, &mut num_physical) != 0 && num_physical > 0 {
                let mut phys_mons = vec![
                    PhysicalMonitor {
                        h_physical_monitor: std::ptr::null_mut(),
                        sz_physical_monitor_description: [0; 128],
                    };
                    num_physical as usize
                ];

                if get_mons(hmon.0, num_physical, phys_mons.as_mut_ptr()) != 0 {
                    for pm in phys_mons {
                        let mut min: u32 = 0;
                        let mut cur: u32 = 0;
                        let mut max: u32 = 0;
                        if get_bright(pm.h_physical_monitor, &mut min, &mut cur, &mut max) != 0 {
                            return Some((pm.h_physical_monitor as isize, cur as i32));
                        }
                    }
                }
            }
        }
    }

    None
}

/// Returns the detected brightness backend.
pub fn get_brightness_backend() -> BrightnessBackend {
    if !INITIALIZED.load(Ordering::Relaxed) {
        init_brightness_support();
    }
    match BACKEND.load(Ordering::Relaxed) {
        1 => BrightnessBackend::Wmi,
        2 => BrightnessBackend::DdcCi,
        _ => BrightnessBackend::Unsupported,
    }
}

/// Returns whether the connected Windows display supports programmatic brightness adjustment.
pub fn is_brightness_supported() -> bool {
    get_brightness_backend() != BrightnessBackend::Unsupported
}

/// Adjust brightness by delta (-10 or +10). Clamps between 10% and 100%.
/// Returns Ok(new_brightness) if supported, or Err if unsupported.
pub fn adjust_brightness(delta: i32) -> Result<i32, &'static str> {
    let backend = get_brightness_backend();
    if backend == BrightnessBackend::Unsupported {
        return Err("Brightness adjustment not supported on this display");
    }

    let current = CURRENT_BRIGHTNESS.load(Ordering::Relaxed);
    let next = (current + delta).clamp(10, 100);
    CURRENT_BRIGHTNESS.store(next, Ordering::Relaxed);

    #[cfg(target_os = "windows")]
    match backend {
        BrightnessBackend::Wmi => {
            // Execute WmiSetBrightness in a background thread to prevent blocking
            std::thread::spawn(move || {
                let mut cmd = Command::new("powershell");
                let script = format!(
                    "(Get-WmiObject -Namespace root/wmi -Class WmiMonitorBrightnessMethods).WmiSetBrightness(1, {})",
                    next
                );
                cmd.args(["-NoProfile", "-WindowStyle", "Hidden", "-Command", &script]);
                cmd.creation_flags(CREATE_NO_WINDOW);
                let _ = cmd.output();
            });
        }
        BrightnessBackend::DdcCi => {
            let handle_val = DDC_MONITOR_HANDLE.load(Ordering::SeqCst);
            if handle_val != 0 {
                std::thread::spawn(move || {
                    use windows::core::s;
                    use windows::Win32::System::LibraryLoader::{GetProcAddress, LoadLibraryA};
                    unsafe {
                        if let Ok(dxva2) = LoadLibraryA(s!("dxva2.dll")) {
                            if let Some(set_proc) =
                                GetProcAddress(dxva2, s!("SetMonitorBrightness"))
                            {
                                let set_bright: SetMonitorBrightnessFn =
                                    std::mem::transmute(set_proc);
                                set_bright(handle_val as *mut std::ffi::c_void, next as u32);
                            }
                        }
                    }
                });
            }
        }
        BrightnessBackend::Unsupported => {
            return Err("Brightness adjustment not supported on this display");
        }
    }

    Ok(next)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_brightness_clamping() {
        assert_eq!((-50 + 10).clamp(10, 100), 10);
        assert_eq!((150 + 10).clamp(10, 100), 100);
        assert_eq!((50 + 10).clamp(10, 100), 60);
    }

    #[test]
    fn test_unsupported_returns_err() {
        BACKEND.store(BrightnessBackend::Unsupported as i32, Ordering::SeqCst);
        INITIALIZED.store(true, Ordering::SeqCst);
        assert!(!is_brightness_supported());
        assert_eq!(
            adjust_brightness(10),
            Err("Brightness adjustment not supported on this display")
        );
    }

    #[test]
    fn test_wmi_and_ddc_capability_probe_safe() {
        // Calling init_brightness_support must not panic or cause memory access violation
        init_brightness_support();
        let _ = is_brightness_supported();
        let _ = get_brightness_backend();
    }

    #[test]
    fn test_wmi_adjust_brightness_roundtrip() {
        init_brightness_support();
        if get_brightness_backend() == BrightnessBackend::Wmi {
            let res = adjust_brightness(-10);
            assert!(res.is_ok());
            let mid = res.unwrap();
            assert!(mid >= 10 && mid <= 100);
            let res2 = adjust_brightness(10);
            assert!(res2.is_ok());
        }
    }
}
