use std::sync::Mutex;
use std::sync::OnceLock;

#[cfg(target_os = "windows")]
mod win_mag {
    use std::sync::atomic::{AtomicBool, Ordering};
    use windows::Win32::Foundation::{BOOL, POINT};
    use windows::Win32::System::LibraryLoader::{GetProcAddress, LoadLibraryW};
    use windows::Win32::UI::WindowsAndMessaging::{
        GetCursorPos, GetSystemMetrics, SM_CXSCREEN, SM_CYSCREEN,
    };

    type MagInitFn = unsafe extern "system" fn() -> BOOL;
    type MagUninitFn = unsafe extern "system" fn() -> BOOL;
    type MagSetFullscreenTransformFn = unsafe extern "system" fn(f32, i32, i32) -> BOOL;

    pub struct WinMagnifier {
        _library: windows::Win32::Foundation::HMODULE,
        mag_init: MagInitFn,
        mag_uninit: MagUninitFn,
        mag_set_transform: MagSetFullscreenTransformFn,
        initialized: AtomicBool,
    }

    unsafe impl Send for WinMagnifier {}
    unsafe impl Sync for WinMagnifier {}

    impl WinMagnifier {
        pub fn load() -> Option<Self> {
            unsafe {
                let dll_name: Vec<u16> = "Magnification.dll\0".encode_utf16().collect();
                let hmodule = LoadLibraryW(windows::core::PCWSTR(dll_name.as_ptr())).ok()?;

                let init_str = b"MagInitialize\0";
                let uninit_str = b"MagUninitialize\0";
                let set_transform_str = b"MagSetFullscreenTransform\0";

                let p_init = GetProcAddress(hmodule, windows::core::PCSTR(init_str.as_ptr()))?;
                let p_uninit = GetProcAddress(hmodule, windows::core::PCSTR(uninit_str.as_ptr()))?;
                let p_set_transform = GetProcAddress(hmodule, windows::core::PCSTR(set_transform_str.as_ptr()))?;

                let mag_init: MagInitFn = std::mem::transmute(p_init);
                let mag_uninit: MagUninitFn = std::mem::transmute(p_uninit);
                let mag_set_transform: MagSetFullscreenTransformFn = std::mem::transmute(p_set_transform);

                Some(Self {
                    _library: hmodule,
                    mag_init,
                    mag_uninit,
                    mag_set_transform,
                    initialized: AtomicBool::new(false),
                })
            }
        }

        pub fn set_magnification(&self, scale: f32) {
            let scale = scale.clamp(1.0, 4.0);
            if scale <= 1.001 {
                if self.initialized.load(Ordering::SeqCst) {
                    unsafe {
                        let _ = (self.mag_set_transform)(1.0, 0, 0);
                        let _ = (self.mag_uninit)();
                    }
                    self.initialized.store(false, Ordering::SeqCst);
                }
                return;
            }

            if !self.initialized.load(Ordering::SeqCst) {
                let ok = unsafe { (self.mag_init)() };
                if ok.as_bool() {
                    self.initialized.store(true, Ordering::SeqCst);
                } else {
                    eprintln!("[MAGNIFIER] MagInitialize failed");
                    return;
                }
            }

            let (cursor_x, cursor_y) = unsafe {
                let mut pt = POINT { x: 0, y: 0 };
                if GetCursorPos(&mut pt).is_ok() {
                    (pt.x, pt.y)
                } else {
                    (0, 0)
                }
            };

            let screen_width = unsafe { GetSystemMetrics(SM_CXSCREEN) };
            let screen_height = unsafe { GetSystemMetrics(SM_CYSCREEN) };

            let view_w = screen_width as f32 / scale;
            let view_h = screen_height as f32 / scale;

            let target_x = cursor_x as f32 - view_w / 2.0;
            let target_y = cursor_y as f32 - view_h / 2.0;

            let max_x = (screen_width as f32 - view_w).max(0.0) as i32;
            let max_y = (screen_height as f32 - view_h).max(0.0) as i32;

            let x_offset = (target_x.round() as i32).clamp(0, max_x);
            let y_offset = (target_y.round() as i32).clamp(0, max_y);

            unsafe {
                let _ = (self.mag_set_transform)(scale, x_offset, y_offset);
            }
        }
    }

    impl Drop for WinMagnifier {
        fn drop(&mut self) {
            if self.initialized.load(Ordering::SeqCst) {
                unsafe {
                    let _ = (self.mag_set_transform)(1.0, 0, 0);
                    let _ = (self.mag_uninit)();
                }
            }
        }
    }
}

pub struct MagnifierManager {
    current_scale: Mutex<f32>,
    #[cfg(target_os = "windows")]
    win_mag: Option<win_mag::WinMagnifier>,
}

unsafe impl Send for MagnifierManager {}
unsafe impl Sync for MagnifierManager {}

impl MagnifierManager {
    pub fn global() -> &'static Self {
        static INSTANCE: OnceLock<MagnifierManager> = OnceLock::new();
        INSTANCE.get_or_init(|| {
            #[cfg(target_os = "windows")]
            let win_mag = win_mag::WinMagnifier::load();
            MagnifierManager {
                current_scale: Mutex::new(1.0),
                #[cfg(target_os = "windows")]
                win_mag,
            }
        })
    }

    pub fn set_scale(&self, scale: f32) {
        let clamped = scale.clamp(1.0, 4.0);
        let mut curr = self.current_scale.lock().unwrap();
        *curr = clamped;
        #[cfg(target_os = "windows")]
        if let Some(mag) = &self.win_mag {
            mag.set_magnification(clamped);
        }
    }

    pub fn update_cursor(&self) {
        let curr = *self.current_scale.lock().unwrap();
        if curr > 1.001 {
            #[cfg(target_os = "windows")]
            if let Some(mag) = &self.win_mag {
                mag.set_magnification(curr);
            }
        }
    }

    pub fn reset(&self) {
        self.set_scale(1.0);
    }

    pub fn current_scale(&self) -> f32 {
        *self.current_scale.lock().unwrap()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_magnifier_scale_clamping() {
        let manager = MagnifierManager::global();
        manager.set_scale(0.5);
        assert_eq!(manager.current_scale(), 1.0);

        manager.set_scale(2.5);
        assert_eq!(manager.current_scale(), 2.5);

        manager.set_scale(5.0);
        assert_eq!(manager.current_scale(), 4.0);

        manager.reset();
        assert_eq!(manager.current_scale(), 1.0);
    }
}
