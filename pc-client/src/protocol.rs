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
    AbsMove {
        #[serde(default)]
        x: f32,
        #[serde(default)]
        y: f32,
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
    SystemMagnify {
        #[serde(default = "default_scale")]
        scale: f32,
    },
    Ping,
    Pong,

    // Phase 5C Discrete OS Utility Controls
    VolumeUp,
    VolumeDown,
    VolumeMute,
    BrightnessUp,
    BrightnessDown,
    WindowsSearch,
    TaskbarApps,

    // Remote Screen Production Protocol Events
    Auth {
        token: String,
    },
    AuthOk {
        #[serde(default = "default_auth_status")]
        status: String,
    },
    StartScreen,
    ScreenMetadata {
        width: u32,
        height: u32,
        #[serde(default = "default_orientation")]
        orientation: String,
        #[serde(rename = "sessionToken")]
        session_token: String,
    },
    ResumeScreen {
        #[serde(rename = "sessionToken")]
        session_token: String,
    },
    ResumeOk,
    StopScreen,
    StopScreenOk,
    RequestKeyframe,
    InputBlocked {
        #[serde(default)]
        reason: String,
    },
    SessionBusy,
    SessionExpired,
    Error {
        code: String,
        message: String,
    },
}

fn default_button() -> String {
    "left".to_string()
}

fn default_auth_status() -> String {
    "authenticated".to_string()
}

fn default_orientation() -> String {
    "landscape".to_string()
}

fn default_scale() -> f32 {
    1.0
}

impl PouseEvent {
    pub fn parse(json_str: &str) -> Result<Self, serde_json::Error> {
        serde_json::from_str(json_str)
    }

    pub fn to_json(&self) -> String {
        serde_json::to_string(self).unwrap_or_default()
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
    fn test_parse_abs_move_event() {
        let json = r#"{"event":"ABS_MOVE","x":0.25,"y":0.75}"#;
        let event = PouseEvent::parse(json).unwrap();
        match event {
            PouseEvent::AbsMove { x, y } => {
                assert_eq!(x, 0.25);
                assert_eq!(y, 0.75);
            }
            _ => panic!("Expected AbsMove event"),
        }
    }

    #[test]
    fn test_parse_remote_screen_control_protocol_events() {
        let auth_json = r#"{"event":"AUTH","token":"4f9a1c8b3e2d6f0a"}"#;
        let auth_event = PouseEvent::parse(auth_json).unwrap();
        match auth_event {
            PouseEvent::Auth { token } => assert_eq!(token, "4f9a1c8b3e2d6f0a"),
            _ => panic!("Expected Auth event"),
        }

        let metadata_json = r#"{"event":"SCREEN_METADATA","width":1920,"height":1080,"orientation":"landscape","sessionToken":"sess_12345"}"#;
        let meta_event = PouseEvent::parse(metadata_json).unwrap();
        match meta_event {
            PouseEvent::ScreenMetadata { width, height, session_token, .. } => {
                assert_eq!(width, 1920);
                assert_eq!(height, 1080);
                assert_eq!(session_token, "sess_12345");
            }
            _ => panic!("Expected ScreenMetadata event"),
        }

        let resume_json = r#"{"event":"RESUME_SCREEN","sessionToken":"sess_12345"}"#;
        let resume_event = PouseEvent::parse(resume_json).unwrap();
        match resume_event {
            PouseEvent::ResumeScreen { session_token } => assert_eq!(session_token, "sess_12345"),
            _ => panic!("Expected ResumeScreen event"),
        }

        assert_eq!(PouseEvent::parse(r#"{"event":"START_SCREEN"}"#).unwrap(), PouseEvent::StartScreen);
        assert_eq!(PouseEvent::parse(r#"{"event":"STOP_SCREEN"}"#).unwrap(), PouseEvent::StopScreen);
        assert_eq!(PouseEvent::parse(r#"{"event":"REQUEST_KEYFRAME"}"#).unwrap(), PouseEvent::RequestKeyframe);
        assert_eq!(PouseEvent::parse(r#"{"event":"SESSION_BUSY"}"#).unwrap(), PouseEvent::SessionBusy);
        assert_eq!(PouseEvent::parse(r#"{"event":"SESSION_EXPIRED"}"#).unwrap(), PouseEvent::SessionExpired);
    }

    #[test]
    fn test_parse_system_magnify_event() {
        let json = r#"{"event":"SYSTEM_MAGNIFY","scale":2.5}"#;
        let event = PouseEvent::parse(json).unwrap();
        match event {
            PouseEvent::SystemMagnify { scale } => assert_eq!(scale, 2.5),
            _ => panic!("Expected SystemMagnify event"),
        }
    }

    #[test]
    fn test_parse_phase5c_discrete_events() {
        assert_eq!(PouseEvent::parse(r#"{"event":"VOLUME_UP"}"#).unwrap(), PouseEvent::VolumeUp);
        assert_eq!(PouseEvent::parse(r#"{"event":"VOLUME_DOWN"}"#).unwrap(), PouseEvent::VolumeDown);
        assert_eq!(PouseEvent::parse(r#"{"event":"VOLUME_MUTE"}"#).unwrap(), PouseEvent::VolumeMute);
        assert_eq!(PouseEvent::parse(r#"{"event":"BRIGHTNESS_UP"}"#).unwrap(), PouseEvent::BrightnessUp);
        assert_eq!(PouseEvent::parse(r#"{"event":"BRIGHTNESS_DOWN"}"#).unwrap(), PouseEvent::BrightnessDown);
        assert_eq!(PouseEvent::parse(r#"{"event":"WINDOWS_SEARCH"}"#).unwrap(), PouseEvent::WindowsSearch);
        assert_eq!(PouseEvent::parse(r#"{"event":"TASKBAR_APPS"}"#).unwrap(), PouseEvent::TaskbarApps);
    }
}
