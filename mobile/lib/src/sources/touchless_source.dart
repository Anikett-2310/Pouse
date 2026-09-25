import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../input_source.dart';
import '../mouse_mode_manager.dart';
import '../transports/pouse_transport.dart';
import '../transports/touchless_camera_service.dart';

/// Concrete [InputSource] implementation for V4 Touchless / Invisible Mouse.
///
/// Converts real-time index fingertip spatial movement deltas received from native
/// CameraX + MediaPipe engine into logical Pouse pointer events dispatched strictly
/// through the active [PouseTransport].
class TouchlessSource extends ChangeNotifier implements InputSource {
  static const String prefSensitivityKey = 'pouse_touchless_sensitivity';
  static const String prefTouchlessScrollSensitivityKey = 'pouse_touchless_scroll_sensitivity';
  static const String prefTouchlessHorizontalModeKey = 'pouse_touchless_horizontal_mode';

  static const double defaultSensitivity = 1.0;
  static const double defaultTouchlessScrollSensitivity = 0.5;
  static const String defaultHorizontalMode = 'browser';

  PouseTransport _transport;
  final TouchlessCameraService cameraService;

  PouseTransport get transport => _transport;

  void setTransport(PouseTransport transport) {
    _transport = transport;
    notifyListeners();
  }

  bool _isActive = false;
  double sensitivity = defaultSensitivity;
  double touchlessScrollSensitivity = defaultTouchlessScrollSensitivity;
  String horizontalMode = defaultHorizontalMode;

  StreamSubscription<Offset>? _moveSub;
  StreamSubscription<Offset>? _scrollSub;
  StreamSubscription<void>? _leftClickSub;
  StreamSubscription<void>? _rightClickSub;
  StreamSubscription<void>? _doubleClickSub;
  StreamSubscription<String>? _buttonDownSub;
  StreamSubscription<String>? _buttonUpSub;
  StreamSubscription<void>? _browserForwardSub;
  StreamSubscription<void>? _browserBackSub;
  StreamSubscription<void>? _threeFingerUpSub;
  StreamSubscription<void>? _threeFingerDownSub;
  StreamSubscription<void>? _threeFingerLeftSub;
  StreamSubscription<void>? _threeFingerRightSub;
  StreamSubscription<void>? _fourFingerLeftSub;
  StreamSubscription<void>? _fourFingerRightSub;

  TouchlessSource(
    this._transport, {
    TouchlessCameraService? service,
  }) : cameraService = service ?? TouchlessCameraService() {
    _loadSensitivity();
  }

  Future<void> _loadSensitivity() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedSens = prefs.getDouble(prefSensitivityKey);
      if (savedSens != null) {
        sensitivity = savedSens;
      }
      final savedScrollSens = prefs.getDouble(prefTouchlessScrollSensitivityKey);
      if (savedScrollSens != null) {
        touchlessScrollSensitivity = savedScrollSens;
      }
      final savedHorizontalMode = prefs.getString(prefTouchlessHorizontalModeKey);
      if (savedHorizontalMode != null) {
        horizontalMode = savedHorizontalMode;
      }
      notifyListeners();
    } catch (_) {}
  }

  void setSensitivity(double value) {
    if (sensitivity == value) return;
    sensitivity = value;
    cameraService.setSensitivity(value);
    notifyListeners();
  }

  Future<void> saveSensitivity(double value) async {
    setSensitivity(value);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(prefSensitivityKey, value);
    } catch (_) {}
  }

  void setTouchlessScrollSensitivity(double value) {
    if (touchlessScrollSensitivity == value) return;
    touchlessScrollSensitivity = value;
    notifyListeners();
  }

  Future<void> saveTouchlessScrollSensitivity(double value) async {
    setTouchlessScrollSensitivity(value);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(prefTouchlessScrollSensitivityKey, value);
    } catch (_) {}
  }

  void setHorizontalMode(String mode) {
    if (horizontalMode == mode) return;
    horizontalMode = mode;
    notifyListeners();
    _saveHorizontalMode(mode);
  }

  Future<void> _saveHorizontalMode(String mode) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(prefTouchlessHorizontalModeKey, mode);
    } catch (_) {}
  }

  @override
  MouseMode get mode => MouseMode.touchless;

  @override
  String get displayName => 'Touchless';

  @override
  bool get isActive => _isActive;

  @override
  void activate() {
    if (_isActive) return;
    _isActive = true;
    _startTracking();
    notifyListeners();
  }

  @override
  void deactivate() {
    if (!_isActive) return;
    _isActive = false;
    _stopTracking();
    _transport.releaseAll();
    notifyListeners();
  }

  void _startTracking() {
    _stopTracking();
    cameraService.startTracking(sensitivity: sensitivity);
    _moveSub = cameraService.moveStream.listen(_onMoveDelta, onError: (_) {});
    _scrollSub = cameraService.scrollStream.listen((delta) {
      if (_isActive) {
        final scaledDx = delta.dx * touchlessScrollSensitivity;
        final scaledDy = delta.dy * touchlessScrollSensitivity;
        _transport.sendScroll(scaledDx, scaledDy);
      }
    }, onError: (_) {});
    _leftClickSub = cameraService.leftClickStream.listen((_) {
      if (_isActive) _transport.sendLeftClick();
    }, onError: (_) {});
    _rightClickSub = cameraService.rightClickStream.listen((_) {
      if (_isActive) _transport.sendRightClick();
    }, onError: (_) {});
    _doubleClickSub = cameraService.doubleClickStream.listen((_) {
      if (_isActive) _transport.sendDoubleClick();
    }, onError: (_) {});
    _buttonDownSub = cameraService.buttonDownStream.listen((btn) {
      if (_isActive) _transport.sendButtonDown(btn);
    }, onError: (_) {});
    _buttonUpSub = cameraService.buttonUpStream.listen((btn) {
      if (_isActive) _transport.sendButtonUp(btn);
    }, onError: (_) {});
    _browserForwardSub = cameraService.browserForwardStream.listen((_) {
      if (_isActive) {
        if (horizontalMode == 'presentation') {
          _transport.sendKeyPress('ArrowLeft');
        } else {
          _transport.sendTwoFingerBrowserForward();
        }
      }
    }, onError: (_) {});
    _browserBackSub = cameraService.browserBackStream.listen((_) {
      if (_isActive) {
        if (horizontalMode == 'presentation') {
          _transport.sendKeyPress('ArrowRight');
        } else {
          _transport.sendTwoFingerBrowserBack();
        }
      }
    }, onError: (_) {});
    _threeFingerUpSub = cameraService.threeFingerUpStream.listen((_) {
      if (_isActive) _transport.sendThreeFingerUp();
    }, onError: (_) {});
    _threeFingerDownSub = cameraService.threeFingerDownStream.listen((_) {
      if (_isActive) _transport.sendThreeFingerDown();
    }, onError: (_) {});
    _threeFingerLeftSub = cameraService.threeFingerLeftStream.listen((_) {
      if (_isActive) _transport.sendThreeFingerLeft();
    }, onError: (_) {});
    _threeFingerRightSub = cameraService.threeFingerRightStream.listen((_) {
      if (_isActive) _transport.sendThreeFingerRight();
    }, onError: (_) {});
    _fourFingerLeftSub = cameraService.fourFingerLeftStream.listen((_) {
      if (_isActive) _transport.sendFourFingerLeft();
    }, onError: (_) {});
    _fourFingerRightSub = cameraService.fourFingerRightStream.listen((_) {
      if (_isActive) _transport.sendFourFingerRight();
    }, onError: (_) {});
  }

  void _stopTracking() {
    _moveSub?.cancel();
    _moveSub = null;
    _scrollSub?.cancel();
    _scrollSub = null;
    _leftClickSub?.cancel();
    _leftClickSub = null;
    _rightClickSub?.cancel();
    _rightClickSub = null;
    _doubleClickSub?.cancel();
    _doubleClickSub = null;
    _buttonDownSub?.cancel();
    _buttonDownSub = null;
    _buttonUpSub?.cancel();
    _buttonUpSub = null;
    _browserForwardSub?.cancel();
    _browserForwardSub = null;
    _browserBackSub?.cancel();
    _browserBackSub = null;
    _threeFingerUpSub?.cancel();
    _threeFingerUpSub = null;
    _threeFingerDownSub?.cancel();
    _threeFingerDownSub = null;
    _threeFingerLeftSub?.cancel();
    _threeFingerLeftSub = null;
    _threeFingerRightSub?.cancel();
    _threeFingerRightSub = null;
    _fourFingerLeftSub?.cancel();
    _fourFingerLeftSub = null;
    _fourFingerRightSub?.cancel();
    _fourFingerRightSub = null;
    cameraService.stopTracking();
  }

  void _onMoveDelta(Offset delta) {
    if (!_isActive) return;
    if (delta.dx.abs() >= 0.1 || delta.dy.abs() >= 0.1) {
      _transport.sendMove(delta.dx, delta.dy);
    }
  }

  @override
  void dispose() {
    deactivate();
    cameraService.dispose();
    super.dispose();
  }
}
