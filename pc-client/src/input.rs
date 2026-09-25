use enigo::{Axis, Button, Coordinate, Direction, Enigo, Key, Keyboard, Mouse, Settings};
use crate::protocol::PouseEvent;

pub trait InputDriver {
    fn press_button(&mut self, button: Button);
    fn release_button(&mut self, button: Button);
    fn click_button(&mut self, button: Button);
    fn move_mouse(&mut self, x: i32, y: i32);
    fn scroll(&mut self, amount: i32, axis: Axis);
    fn text(&mut self, text: &str);
    fn key(&mut self, key: Key);
    fn press_key(&mut self, key: Key);
    fn release_key(&mut self, key: Key);
    fn newline(&mut self);

    fn task_view(&mut self);
    fn show_desktop(&mut self);
    fn prev_app(&mut self);
    fn next_app(&mut self);
    fn prev_virtual_desktop(&mut self);
    fn next_virtual_desktop(&mut self);
    fn browser_back(&mut self);
    fn browser_forward(&mut self);
}

pub struct EnigoDriver {
    enigo: Enigo,
    move_count: u64,
    last_log: std::time::Instant,
}

impl EnigoDriver {
    pub fn new() -> Result<Self, String> {
        let enigo = Enigo::new(&Settings::default())
            .map_err(|e| format!("Failed to initialize Enigo input handler: {:?}", e))?;
        Ok(Self {
            enigo,
            move_count: 0,
            last_log: std::time::Instant::now(),
        })
    }
}

impl InputDriver for EnigoDriver {
    fn press_button(&mut self, button: Button) {
        let _ = self.enigo.button(button, Direction::Press);
    }

    fn release_button(&mut self, button: Button) {
        let _ = self.enigo.button(button, Direction::Release);
    }

    fn click_button(&mut self, button: Button) {
        let _ = self.enigo.button(button, Direction::Click);
    }

    fn move_mouse(&mut self, x: i32, y: i32) {
        self.move_count += 1;
        if self.last_log.elapsed().as_secs() >= 1 || self.move_count % 100 == 0 {
            println!("[ENIGO DIAGNOSTIC] move_mouse executed: count={} | dx={} | dy={}", self.move_count, x, y);
            self.last_log = std::time::Instant::now();
        }
        let _ = self.enigo.move_mouse(x, y, Coordinate::Rel);
    }

    fn scroll(&mut self, amount: i32, axis: Axis) {
        let _ = self.enigo.scroll(amount, axis);
    }

    fn text(&mut self, text: &str) {
        let _ = self.enigo.text(text);
    }

    fn key(&mut self, key: Key) {
        let _ = self.enigo.key(key, Direction::Click);
    }

    fn press_key(&mut self, key: Key) {
        let _ = self.enigo.key(key, Direction::Press);
    }

    fn release_key(&mut self, key: Key) {
        let _ = self.enigo.key(key, Direction::Release);
    }

    fn newline(&mut self) {
        let _ = self.enigo.key(Key::Shift, Direction::Press);
        let _ = self.enigo.key(Key::Return, Direction::Click);
        let _ = self.enigo.key(Key::Shift, Direction::Release);
    }

    fn task_view(&mut self) {
        // 3-finger UP: Win + Tab
        let _ = self.enigo.key(Key::Meta, Direction::Press);
        let _ = self.enigo.key(Key::Tab, Direction::Click);
        let _ = self.enigo.key(Key::Meta, Direction::Release);
    }

    fn show_desktop(&mut self) {
        // 3-finger DOWN: Win + D
        let _ = self.enigo.key(Key::Meta, Direction::Press);
        let _ = self.enigo.key(Key::Unicode('d'), Direction::Click);
        let _ = self.enigo.key(Key::Meta, Direction::Release);
    }

    fn prev_app(&mut self) {
        // 3-finger LEFT: Alt + Shift + Tab
        let _ = self.enigo.key(Key::Alt, Direction::Press);
        let _ = self.enigo.key(Key::Shift, Direction::Press);
        let _ = self.enigo.key(Key::Tab, Direction::Click);
        let _ = self.enigo.key(Key::Shift, Direction::Release);
        let _ = self.enigo.key(Key::Alt, Direction::Release);
    }

    fn next_app(&mut self) {
        // 3-finger RIGHT: Alt + Tab
        let _ = self.enigo.key(Key::Alt, Direction::Press);
        let _ = self.enigo.key(Key::Tab, Direction::Click);
        let _ = self.enigo.key(Key::Alt, Direction::Release);
    }

    fn prev_virtual_desktop(&mut self) {
        // 4-finger LEFT: Win + Ctrl + Left Arrow
        let _ = self.enigo.key(Key::Meta, Direction::Press);
        let _ = self.enigo.key(Key::Control, Direction::Press);
        let _ = self.enigo.key(Key::LeftArrow, Direction::Click);
        let _ = self.enigo.key(Key::Control, Direction::Release);
        let _ = self.enigo.key(Key::Meta, Direction::Release);
    }

    fn next_virtual_desktop(&mut self) {
        // 4-finger RIGHT: Win + Ctrl + Right Arrow
        let _ = self.enigo.key(Key::Meta, Direction::Press);
        let _ = self.enigo.key(Key::Control, Direction::Press);
        let _ = self.enigo.key(Key::RightArrow, Direction::Click);
        let _ = self.enigo.key(Key::Control, Direction::Release);
        let _ = self.enigo.key(Key::Meta, Direction::Release);
    }

    fn browser_back(&mut self) {
        // 2-finger SWIPE RIGHT: Alt + Left Arrow
        let _ = self.enigo.key(Key::Alt, Direction::Press);
        let _ = self.enigo.key(Key::LeftArrow, Direction::Click);
        let _ = self.enigo.key(Key::Alt, Direction::Release);
    }

    fn browser_forward(&mut self) {
        // 2-finger SWIPE LEFT: Alt + Right Arrow
        let _ = self.enigo.key(Key::Alt, Direction::Press);
        let _ = self.enigo.key(Key::RightArrow, Direction::Click);
        let _ = self.enigo.key(Key::Alt, Direction::Release);
    }
}

pub struct InputHandler<D = EnigoDriver> {
    driver: D,
    accum_x: f32,
    accum_y: f32,
    accum_scroll_x: f32,
    accum_scroll_y: f32,
    left_button_down: bool,
    right_button_down: bool,
    held_keys: std::collections::HashSet<String>,
}

fn map_key_name(key: &str) -> Option<Key> {
    match key.to_lowercase().as_str() {
        "w" => Some(Key::Unicode('w')),
        "a" => Some(Key::Unicode('a')),
        "s" => Some(Key::Unicode('s')),
        "d" => Some(Key::Unicode('d')),
        "arrow_up" | "up" => Some(Key::UpArrow),
        "arrow_down" | "down" => Some(Key::DownArrow),
        "arrow_left" | "left" => Some(Key::LeftArrow),
        "arrow_right" | "right" => Some(Key::RightArrow),
        "enter" | "return" => Some(Key::Return),
        "backspace" => Some(Key::Backspace),
        "space" => Some(Key::Space),
        "tab" => Some(Key::Tab),
        "escape" => Some(Key::Escape),
        s if s.chars().count() == 1 => Some(Key::Unicode(s.chars().next().unwrap())),
        _ => None,
    }
}

impl InputHandler<EnigoDriver> {
    pub fn new() -> Result<Self, String> {
        let driver = EnigoDriver::new()?;
        Ok(Self::with_driver(driver))
    }
}

impl<D: InputDriver> InputHandler<D> {
    pub fn with_driver(driver: D) -> Self {
        Self {
            driver,
            accum_x: 0.0,
            accum_y: 0.0,
            accum_scroll_x: 0.0,
            accum_scroll_y: 0.0,
            left_button_down: false,
            right_button_down: false,
            held_keys: std::collections::HashSet::new(),
        }
    }

    #[allow(dead_code)]
    pub fn left_button_down(&self) -> bool {
        self.left_button_down
    }

    #[allow(dead_code)]
    pub fn right_button_down(&self) -> bool {
        self.right_button_down
    }

    #[allow(dead_code)]
    pub fn is_key_held(&self, key: &str) -> bool {
        self.held_keys.contains(key)
    }

    pub fn release_all(&mut self) {
        if self.left_button_down {
            self.driver.release_button(Button::Left);
            self.left_button_down = false;
        }
        if self.right_button_down {
            self.driver.release_button(Button::Right);
            self.right_button_down = false;
        }
        for key in self.held_keys.drain().collect::<Vec<_>>() {
            if let Some(k) = map_key_name(&key) {
                self.driver.release_key(k);
            }
        }
    }

    pub fn handle_event(&mut self, event: PouseEvent) {
        match event {
            PouseEvent::Move { dx, dy, .. } => {
                self.accum_x += dx;
                self.accum_y += dy;

                let ix = self.accum_x.trunc() as i32;
                let iy = self.accum_y.trunc() as i32;

                if ix != 0 || iy != 0 {
                    self.accum_x -= ix as f32;
                    self.accum_y -= iy as f32;
                    self.driver.move_mouse(ix, iy);
                }
            }
            PouseEvent::LeftClick => {
                self.driver.click_button(Button::Left);
            }
            PouseEvent::RightClick => {
                self.driver.click_button(Button::Right);
            }
            PouseEvent::DoubleClick => {
                self.driver.click_button(Button::Left);
                self.driver.click_button(Button::Left);
            }
            PouseEvent::ButtonDown { button } => {
                let b = match button.as_str() {
                    "right" => {
                        self.right_button_down = true;
                        Button::Right
                    }
                    _ => {
                        self.left_button_down = true;
                        Button::Left
                    }
                };
                self.driver.press_button(b);
            }
            PouseEvent::ButtonUp { button } => {
                let b = match button.as_str() {
                    "right" => {
                        if !self.right_button_down {
                            return;
                        }
                        self.right_button_down = false;
                        Button::Right
                    }
                    _ => {
                        if !self.left_button_down {
                            return;
                        }
                        self.left_button_down = false;
                        Button::Left
                    }
                };
                self.driver.release_button(b);
            }
            PouseEvent::Scroll { dx, dy } => {
                self.accum_scroll_x += dx;
                self.accum_scroll_y += dy;

                let sx = self.accum_scroll_x.trunc() as i32;
                let sy = self.accum_scroll_y.trunc() as i32;

                if sx != 0 {
                    self.accum_scroll_x -= sx as f32;
                    self.driver.scroll(sx, Axis::Horizontal);
                }
                if sy != 0 {
                    self.accum_scroll_y -= sy as f32;
                    self.driver.scroll(sy, Axis::Vertical);
                }
            }
            PouseEvent::TextInput { text } => {
                if text == "\n" || text == "\r\n" {
                    self.driver.newline();
                } else {
                    self.driver.text(&text);
                }
            }
            PouseEvent::KeyPress { key } => {
                if let Some(k) = map_key_name(&key) {
                    self.driver.key(k);
                }
            }
            PouseEvent::KeyDown { key } => {
                if let Some(k) = map_key_name(&key) {
                    self.held_keys.insert(key);
                    self.driver.press_key(k);
                }
            }
            PouseEvent::KeyUp { key } => {
                self.held_keys.remove(&key);
                if let Some(k) = map_key_name(&key) {
                    self.driver.release_key(k);
                }
            }
            PouseEvent::TwoFingerBrowserBack => {
                self.driver.browser_back();
            }
            PouseEvent::TwoFingerBrowserForward => {
                self.driver.browser_forward();
            }
            PouseEvent::ThreeFingerUp => {
                self.driver.task_view();
            }
            PouseEvent::ThreeFingerDown => {
                self.driver.show_desktop();
            }
            PouseEvent::ThreeFingerLeft => {
                self.driver.prev_app();
            }
            PouseEvent::ThreeFingerRight => {
                self.driver.next_app();
            }
            PouseEvent::FourFingerLeft => {
                self.driver.prev_virtual_desktop();
            }
            PouseEvent::FourFingerRight => {
                self.driver.next_virtual_desktop();
            }
            PouseEvent::Ping | PouseEvent::Pong => {}
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[derive(Debug, Default)]
    struct TestDriver {
        released_buttons: Vec<Button>,
        pressed_buttons: Vec<Button>,
        clicked_buttons: Vec<Button>,
        pressed_keys: Vec<Key>,
        released_keys: Vec<Key>,
        clicked_keys: Vec<Key>,
        gestures: Vec<&'static str>,
    }

    impl InputDriver for TestDriver {
        fn press_button(&mut self, button: Button) {
            self.pressed_buttons.push(button);
        }

        fn release_button(&mut self, button: Button) {
            self.released_buttons.push(button);
        }

        fn click_button(&mut self, button: Button) {
            self.clicked_buttons.push(button);
        }

        fn move_mouse(&mut self, _x: i32, _y: i32) {}

        fn scroll(&mut self, _amount: i32, _axis: Axis) {}

        fn text(&mut self, _text: &str) {}

        fn key(&mut self, key: Key) {
            self.clicked_keys.push(key);
        }

        fn press_key(&mut self, key: Key) {
            self.pressed_keys.push(key);
        }

        fn release_key(&mut self, key: Key) {
            self.released_keys.push(key);
        }

        fn newline(&mut self) {}

        fn task_view(&mut self) {
            self.gestures.push("task_view");
        }

        fn show_desktop(&mut self) {
            self.gestures.push("show_desktop");
        }

        fn prev_app(&mut self) {
            self.gestures.push("prev_app");
        }

        fn next_app(&mut self) {
            self.gestures.push("next_app");
        }

        fn prev_virtual_desktop(&mut self) {
            self.gestures.push("prev_virtual_desktop");
        }

        fn next_virtual_desktop(&mut self) {
            self.gestures.push("next_virtual_desktop");
        }

        fn browser_back(&mut self) {
            self.gestures.push("browser_back");
        }

        fn browser_forward(&mut self) {
            self.gestures.push("browser_forward");
        }
    }

    #[test]
    fn test_1_no_buttons_held_release_all_produces_no_releases() {
        let mut handler = InputHandler::with_driver(TestDriver::default());
        assert!(!handler.left_button_down());
        assert!(!handler.right_button_down());

        handler.release_all();

        assert!(handler.driver.released_buttons.is_empty());
    }

    #[test]
    fn test_2_left_held_release_all_releases_only_left() {
        let mut handler = InputHandler::with_driver(TestDriver::default());
        handler.handle_event(PouseEvent::ButtonDown {
            button: "left".to_string(),
        });
        assert!(handler.left_button_down());
        assert!(!handler.right_button_down());

        handler.release_all();

        assert_eq!(handler.driver.released_buttons, vec![Button::Left]);
        assert!(!handler.left_button_down());
    }

    #[test]
    fn test_3_right_held_release_all_releases_only_right() {
        let mut handler = InputHandler::with_driver(TestDriver::default());
        handler.handle_event(PouseEvent::ButtonDown {
            button: "right".to_string(),
        });
        assert!(!handler.left_button_down());
        assert!(handler.right_button_down());

        handler.release_all();

        assert_eq!(handler.driver.released_buttons, vec![Button::Right]);
        assert!(!handler.right_button_down());
    }

    #[test]
    fn test_4_both_held_release_all_releases_both() {
        let mut handler = InputHandler::with_driver(TestDriver::default());
        handler.handle_event(PouseEvent::ButtonDown {
            button: "left".to_string(),
        });
        handler.handle_event(PouseEvent::ButtonDown {
            button: "right".to_string(),
        });
        assert!(handler.left_button_down());
        assert!(handler.right_button_down());

        handler.release_all();

        assert_eq!(
            handler.driver.released_buttons,
            vec![Button::Left, Button::Right]
        );
        assert!(!handler.left_button_down());
        assert!(!handler.right_button_down());
    }

    #[test]
    fn test_5_left_held_and_button_up_release_all_produces_no_additional_release() {
        let mut handler = InputHandler::with_driver(TestDriver::default());
        handler.handle_event(PouseEvent::ButtonDown {
            button: "left".to_string(),
        });
        handler.handle_event(PouseEvent::ButtonUp {
            button: "left".to_string(),
        });
        assert!(!handler.left_button_down());

        let count_before = handler.driver.released_buttons.len();
        handler.release_all();
        assert_eq!(handler.driver.released_buttons.len(), count_before);
    }

    #[test]
    fn test_6_right_held_and_button_up_release_all_produces_no_additional_release() {
        let mut handler = InputHandler::with_driver(TestDriver::default());
        handler.handle_event(PouseEvent::ButtonDown {
            button: "right".to_string(),
        });
        handler.handle_event(PouseEvent::ButtonUp {
            button: "right".to_string(),
        });
        assert!(!handler.right_button_down());

        let count_before = handler.driver.released_buttons.len();
        handler.release_all();
        assert_eq!(handler.driver.released_buttons.len(), count_before);
    }

    #[test]
    fn test_7_release_all_idempotent() {
        let mut handler = InputHandler::with_driver(TestDriver::default());
        handler.handle_event(PouseEvent::ButtonDown {
            button: "left".to_string(),
        });

        handler.release_all();
        let count_after_first = handler.driver.released_buttons.len();

        handler.release_all();
        assert_eq!(handler.driver.released_buttons.len(), count_after_first);
    }

    #[test]
    fn test_regression_no_buttons_held_teardown_does_not_release_right_button() {
        let mut handler = InputHandler::with_driver(TestDriver::default());

        // Perform standard clicks and movements
        handler.handle_event(PouseEvent::LeftClick);
        handler.handle_event(PouseEvent::RightClick);
        handler.handle_event(PouseEvent::Move { dx: 15.0, dy: 5.0, t: None });

        // Simulate connection teardown
        handler.release_all();

        // Must NOT produce a Right button release
        assert!(!handler.driver.released_buttons.contains(&Button::Right));
        assert!(handler.driver.released_buttons.is_empty());
    }

    #[test]
    fn test_gestures_dispatched_to_driver() {
        let mut handler = InputHandler::with_driver(TestDriver::default());

        handler.handle_event(PouseEvent::TwoFingerBrowserBack);
        handler.handle_event(PouseEvent::TwoFingerBrowserForward);
        handler.handle_event(PouseEvent::ThreeFingerUp);
        handler.handle_event(PouseEvent::ThreeFingerDown);
        handler.handle_event(PouseEvent::ThreeFingerLeft);
        handler.handle_event(PouseEvent::ThreeFingerRight);
        handler.handle_event(PouseEvent::FourFingerLeft);
        handler.handle_event(PouseEvent::FourFingerRight);

        assert_eq!(
            handler.driver.gestures,
            vec![
                "browser_back",
                "browser_forward",
                "task_view",
                "show_desktop",
                "prev_app",
                "next_app",
                "prev_virtual_desktop",
                "next_virtual_desktop"
            ]
        );
    }

    #[test]
    fn test_key_hold_and_teardown_release() {
        let mut handler = InputHandler::with_driver(TestDriver::default());

        handler.handle_event(PouseEvent::KeyDown { key: "w".to_string() });
        assert!(handler.is_key_held("w"));
        assert_eq!(handler.driver.pressed_keys, vec![Key::Unicode('w')]);

        handler.handle_event(PouseEvent::KeyDown { key: "arrow_up".to_string() });
        assert!(handler.is_key_held("arrow_up"));
        assert_eq!(
            handler.driver.pressed_keys,
            vec![Key::Unicode('w'), Key::UpArrow]
        );

        // Teardown must release all held keys
        handler.release_all();
        assert!(!handler.is_key_held("w"));
        assert!(!handler.is_key_held("arrow_up"));

        assert_eq!(handler.driver.released_keys.len(), 2);
        assert!(handler.driver.released_keys.contains(&Key::Unicode('w')));
        assert!(handler.driver.released_keys.contains(&Key::UpArrow));
    }
}

