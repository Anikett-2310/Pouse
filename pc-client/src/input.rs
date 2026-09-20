use enigo::{Axis, Button, Coordinate, Direction, Enigo, Key, Keyboard, Mouse, Settings};
use crate::protocol::PouseEvent;

pub struct InputHandler {
    enigo: Enigo,
    accum_x: f32,
    accum_y: f32,
}

impl InputHandler {
    pub fn new() -> Result<Self, String> {
        let enigo = Enigo::new(&Settings::default())
            .map_err(|e| format!("Failed to initialize Enigo input handler: {:?}", e))?;
        Ok(Self {
            enigo,
            accum_x: 0.0,
            accum_y: 0.0,
        })
    }

    pub fn release_all(&mut self) {
        let _ = self.enigo.button(Button::Left, Direction::Release);
        let _ = self.enigo.button(Button::Right, Direction::Release);
    }

    pub fn handle_event(&mut self, event: PouseEvent) {
        match event {
            PouseEvent::Move { dx, dy } => {
                self.accum_x += dx;
                self.accum_y += dy;

                let ix = self.accum_x.trunc() as i32;
                let iy = self.accum_y.trunc() as i32;

                if ix != 0 || iy != 0 {
                    self.accum_x -= ix as f32;
                    self.accum_y -= iy as f32;
                    let _ = self.enigo.move_mouse(ix, iy, Coordinate::Rel);
                }
            }
            PouseEvent::LeftClick => {
                let _ = self.enigo.button(Button::Left, Direction::Click);
            }
            PouseEvent::RightClick => {
                let _ = self.enigo.button(Button::Right, Direction::Click);
            }
            PouseEvent::DoubleClick => {
                let _ = self.enigo.button(Button::Left, Direction::Click);
                let _ = self.enigo.button(Button::Left, Direction::Click);
            }
            PouseEvent::ButtonDown { button } => {
                let b = match button.as_str() {
                    "right" => Button::Right,
                    _ => Button::Left,
                };
                let _ = self.enigo.button(b, Direction::Press);
            }
            PouseEvent::ButtonUp { button } => {
                let b = match button.as_str() {
                    "right" => Button::Right,
                    _ => Button::Left,
                };
                let _ = self.enigo.button(b, Direction::Release);
            }
            PouseEvent::Scroll { dy, .. } => {
                let sy = dy.round() as i32;
                if sy != 0 {
                    let _ = self.enigo.scroll(sy, Axis::Vertical);
                }
            }
            PouseEvent::TextInput { text } => {
                let _ = self.enigo.text(&text);
            }
            PouseEvent::KeyPress { key } => {
                let k = match key.to_lowercase().as_str() {
                    "enter" | "return" => Key::Return,
                    "backspace" => Key::Backspace,
                    "space" => Key::Space,
                    "tab" => Key::Tab,
                    "escape" => Key::Escape,
                    _ => return,
                };
                let _ = self.enigo.key(k, Direction::Click);
            }
            PouseEvent::Ping | PouseEvent::Pong => {}
        }
    }
}
