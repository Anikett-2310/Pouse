use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(tag = "event", rename_all = "SCREAMING_SNAKE_CASE")]
pub enum PouseEvent {
    Move {
        #[serde(default)]
        dx: f32,
        #[serde(default)]
        dy: f32,
        #[serde(default)]
        t: Option<u64>,
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
        let json = r#"{"event":"MOVE","dx":15.5,"dy":-4.2,"t":1727210000000}"#;
        let event = PouseEvent::parse(json).unwrap();
        match event {
            PouseEvent::Move { dx, dy, t } => {
                assert_eq!(dx, 15.5);
                assert_eq!(dy, -4.2);
                assert_eq!(t, Some(1727210000000));
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
}
