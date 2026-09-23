use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(tag = "event", rename_all = "SCREAMING_SNAKE_CASE")]
pub enum PouseEvent {
    Move {
        #[serde(default)]
        dx: f32,
        #[serde(default)]
        dy: f32,
    },
    LeftClick,
    RightClick,
    DoubleClick,
    ButtonDown {
        #[serde(default = "default_button")]
        button: String,
    },
    ButtonUp {
        #[serde(default = "default_button")]
        button: String,
    },
    Scroll {
        #[serde(default)]
        dx: f32,
        #[serde(default)]
        dy: f32,
    },
    TextInput {
        text: String,
    },
    KeyPress {
        key: String,
    },
    KeyDown {
        key: String,
    },
    KeyUp {
        key: String,
    },
    TwoFingerBrowserBack,
    TwoFingerBrowserForward,
    ThreeFingerUp,
    ThreeFingerDown,
    ThreeFingerLeft,
    ThreeFingerRight,
    FourFingerLeft,
    FourFingerRight,
    Ping,
    Pong,
}

fn default_button() -> String {
    "left".to_string()
}

impl PouseEvent {
    pub fn parse(json_str: &str) -> Result<Self, serde_json::Error> {
        serde_json::from_str(json_str)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_parse_move_event() {
        let json = r#"{"event":"MOVE","dx":15.5,"dy":-4.2}"#;
        let event = PouseEvent::parse(json).unwrap();
        match event {
            PouseEvent::Move { dx, dy } => {
                assert_eq!(dx, 15.5);
                assert_eq!(dy, -4.2);
            }
            _ => panic!("Expected Move event"),
        }
    }

    #[test]
    fn test_parse_clicks() {
        let event = PouseEvent::parse(r#"{"event":"LEFT_CLICK"}"#).unwrap();
        assert_eq!(event, PouseEvent::LeftClick);

        let event = PouseEvent::parse(r#"{"event":"RIGHT_CLICK"}"#).unwrap();
        assert_eq!(event, PouseEvent::RightClick);

        let event = PouseEvent::parse(r#"{"event":"DOUBLE_CLICK"}"#).unwrap();
        assert_eq!(event, PouseEvent::DoubleClick);
    }

    #[test]
    fn test_parse_scroll_and_keyboard() {
        let event = PouseEvent::parse(r#"{"event":"SCROLL","dx":0.0,"dy":10.0}"#).unwrap();
        match event {
            PouseEvent::Scroll { dy, .. } => assert_eq!(dy, 10.0),
            _ => panic!("Expected Scroll event"),
        }

        let event = PouseEvent::parse(r#"{"event":"TEXT_INPUT","text":"hello"}"#).unwrap();
        match event {
            PouseEvent::TextInput { text } => assert_eq!(text, "hello"),
            _ => panic!("Expected TextInput event"),
        }
    }

    #[test]
    fn test_parse_gestures_and_key_hold() {
        assert_eq!(
            PouseEvent::parse(r#"{"event":"TWO_FINGER_BROWSER_BACK"}"#).unwrap(),
            PouseEvent::TwoFingerBrowserBack
        );
        assert_eq!(
            PouseEvent::parse(r#"{"event":"TWO_FINGER_BROWSER_FORWARD"}"#).unwrap(),
            PouseEvent::TwoFingerBrowserForward
        );
        assert_eq!(
            PouseEvent::parse(r#"{"event":"THREE_FINGER_UP"}"#).unwrap(),
            PouseEvent::ThreeFingerUp
        );
        assert_eq!(
            PouseEvent::parse(r#"{"event":"THREE_FINGER_DOWN"}"#).unwrap(),
            PouseEvent::ThreeFingerDown
        );
        assert_eq!(
            PouseEvent::parse(r#"{"event":"THREE_FINGER_LEFT"}"#).unwrap(),
            PouseEvent::ThreeFingerLeft
        );
        assert_eq!(
            PouseEvent::parse(r#"{"event":"THREE_FINGER_RIGHT"}"#).unwrap(),
            PouseEvent::ThreeFingerRight
        );
        assert_eq!(
            PouseEvent::parse(r#"{"event":"FOUR_FINGER_LEFT"}"#).unwrap(),
            PouseEvent::FourFingerLeft
        );
        assert_eq!(
            PouseEvent::parse(r#"{"event":"FOUR_FINGER_RIGHT"}"#).unwrap(),
            PouseEvent::FourFingerRight
        );

        let kd = PouseEvent::parse(r#"{"event":"KEY_DOWN","key":"w"}"#).unwrap();
        assert_eq!(kd, PouseEvent::KeyDown { key: "w".to_string() });

        let ku = PouseEvent::parse(r#"{"event":"KEY_UP","key":"w"}"#).unwrap();
        assert_eq!(ku, PouseEvent::KeyUp { key: "w".to_string() });
    }
}
