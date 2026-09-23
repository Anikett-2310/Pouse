import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../input_source.dart';
import '../mouse_mode_manager.dart';
import '../websocket_service.dart';

/// Concrete [InputSource] for V2 Motion Mouse (Air Mouse).
///
/// Uses smartphone IMU sensors (accelerometer & gyroscope) to derive
/// gravity-referenced world pitch and yaw physical rotations, translating them
/// into smooth, roll-invariant 2D cursor movement events on Windows.
class MotionSource extends ChangeNotifier implements InputSource {
  static const String prefSensitivityKey = 'pouse_motion_sensitivity';
  static const double defaultSensitivity = 20.0; // px / degree

  final WebSocketService _wsService;

  WebSocketService get wsService => _wsService;

  bool _isActive = false;
  bool _isTracking = false;
  bool _isSettling = false;

  double sensitivity = defaultSensitivity;

  StreamSubscription<AccelerometerEvent>? _accelSub;
  StreamSubscription<GyroscopeEvent>? _gyroSub;

  Timer? _settlingTimer;
  DateTime? _lastGyroTime;

  // Continuous gravity estimation (low-pass EMA)
  double _gx = 0.0;
  double _gy = 0.0;
  double _gz = 9.81;

  final Stream<AccelerometerEvent>? _customAccelStream;
  final Stream<GyroscopeEvent>? _customGyroStream;

  MotionSource(
    this._wsService, {
    Stream<AccelerometerEvent>? accelStream,
    Stream<GyroscopeEvent>? gyroStream,
  })  : _customAccelStream = accelStream,
        _customGyroStream = gyroStream {
    _loadSensitivity();
  }

  Future<void> _loadSensitivity() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getDouble(prefSensitivityKey);
      if (saved != null) {
        sensitivity = saved;
        notifyListeners();
      }
    } catch (_) {}
  }

  void setSensitivity(double value) {
    if (sensitivity == value) return;
    sensitivity = value;
    notifyListeners();
  }

  Future<void> saveSensitivity(double value) async {
    setSensitivity(value);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(prefSensitivityKey, value);
    } catch (_) {}
  }

  @override
  MouseMode get mode => MouseMode.motion;

  @override
  String get displayName => 'Motion';

  @override
  bool get isActive => _isActive;

  /// Whether hold-to-move tracking is currently active and settled.
  bool get isTracking => _isTracking && !_isSettling;

  /// Whether in the 120ms post-touch settling phase.
  bool get isSettling => _isTracking && _isSettling;

  @override
  void activate() {
    if (_isActive) return;
    _isActive = true;
    _startSensorStreams();
    notifyListeners();
  }

  @override
  void deactivate() {
    if (!_isActive) return;
    _isActive = false;
    stopTracking();
    _stopSensorStreams();
    notifyListeners();
  }

  /// Start hold-to-move tracking (triggered on finger contact / pointer down).
  void startTracking() {
    if (!_isActive) return;

    _isTracking = true;
    _isSettling = true;
    _lastGyroTime = DateTime.now();

    // Cancel any existing settling timer
    _settlingTimer?.cancel();

    // 120 ms settling period to absorb touch impact tremor
    _settlingTimer = Timer(const Duration(milliseconds: 120), () {
      if (_isTracking) {
        _isSettling = false;
        notifyListeners();
      }
    });

    notifyListeners();
  }

  /// Stop hold-to-move tracking (triggered on finger release / pointer up / forced release).
  void stopTracking() {
    _settlingTimer?.cancel();
    _isTracking = false;
    _isSettling = false;
    _lastGyroTime = null;
    notifyListeners();
  }

  void _startSensorStreams() {
    _accelSub?.cancel();
    _gyroSub?.cancel();

    try {
      final aStream = _customAccelStream ??
          accelerometerEventStream(samplingPeriod: SensorInterval.gameInterval);
      _accelSub = aStream.listen(_onAccelerometerEvent, onError: (_) {});
    } catch (e) {
      debugPrint('Accelerometer stream error: $e');
    }

    try {
      final gStream = _customGyroStream ??
          gyroscopeEventStream(samplingPeriod: SensorInterval.gameInterval);
      _gyroSub = gStream.listen(_onGyroscopeEvent, onError: (_) {});
    } catch (e) {
      debugPrint('Gyroscope stream error: $e');
    }
  }

  void _stopSensorStreams() {
    _accelSub?.cancel();
    _accelSub = null;
    _gyroSub?.cancel();
    _gyroSub = null;
  }

  void _onAccelerometerEvent(AccelerometerEvent event) {
    if (!_isActive) return;

    // Low-pass EMA filter for static gravity estimation (alpha = 0.85)
    const alpha = 0.85;
    _gx = alpha * _gx + (1.0 - alpha) * event.x;
    _gy = alpha * _gy + (1.0 - alpha) * event.y;
    _gz = alpha * _gz + (1.0 - alpha) * event.z;
  }

  void _onGyroscopeEvent(GyroscopeEvent event) {
    if (!_isActive || !_isTracking || _isSettling) return;

    final now = DateTime.now();
    if (_lastGyroTime == null) {
      _lastGyroTime = now;
      return;
    }

    final dtMs = now.difference(_lastGyroTime!).inMicroseconds / 1000000.0;
    _lastGyroTime = now;

    // Clamp dt to reasonable bounds (10ms to 50ms) to avoid delta spikes
    final dt = dtMs.clamp(0.01, 0.05);

    // Body angular rates (rad/s)
    final wx = event.x;
    final wy = event.y;
    final wz = event.z;

    // Normalize current estimated gravity vector
    final gNorm = math.sqrt(_gx * _gx + _gy * _gy + _gz * _gz);
    if (gNorm < 0.1) return;

    final gx = _gx / gNorm;
    final gy = _gy / gNorm;
    final gz = _gz / gNorm;

    // 1. World Yaw Rate: Projection of gyro vector onto gravity axis
    final omegaYaw = wx * gx + wy * gy + wz * gz;

    // 2. Projection of phone longitudinal axis y_screen (0, 1, 0) onto horizontal plane
    // v_f = y_screen - (y_screen . g) * g = (0 - gy*gx, 1 - gy*gy, 0 - gy*gz)
    final vfx = -gy * gx;
    final vfy = 1.0 - gy * gy;
    final vfz = -gy * gz;
    final mag = math.sqrt(vfx * vfx + vfy * vfy + vfz * vfz);

    double omegaPitch;

    // Singularity protection (phone pointing straight up or straight down)
    if (mag < 0.05) {
      // Degenerate vertical orientation fallback: use body +X axis (1, 0, 0)
      if (mag < 0.02) {
        omegaPitch = 0.0; // Extreme singularity clamping
      } else {
        omegaPitch = wx; // Fallback pitch rate
      }
    } else {
      // Normal case: pitch axis u_pitch = normalize(g x v_f)
      final fX = vfx / mag;
      final fY = vfy / mag;
      final fZ = vfz / mag;

      final ux = gy * fZ - gz * fY;
      final uy = gz * fX - gx * fZ;
      final uz = gx * fY - gy * fX;

      final uNorm = math.sqrt(ux * ux + uy * uy + uz * uz);
      if (uNorm > 0.001) {
        omegaPitch = wx * (ux / uNorm) + wy * (uy / uNorm) + wz * (uz / uNorm);
      } else {
        omegaPitch = wx;
      }
    }

    // Dead zone check (0.03 rad/s threshold ~ 1.7 deg/s)
    final totalSpeedRad = math.sqrt(omegaYaw * omegaYaw + omegaPitch * omegaPitch);
    if (totalSpeedRad < 0.03) return;

    // Angular displacements in degrees
    final dDegYaw = omegaYaw * dt * (180.0 / math.pi);
    final dDegPitch = omegaPitch * dt * (180.0 / math.pi);

    // Speed in deg/s for nonlinear acceleration calculation
    final speedYaw = dDegYaw.abs() / dt;
    final speedPitch = dDegPitch.abs() / dt;

    // Nonlinear acceleration gain curve
    final gainYaw = _calculateGain(speedYaw);
    final gainPitch = _calculateGain(speedPitch);

    // Calculate screen pixel deltas
    // Counter-clockwise yaw -> cursor left (-dx)
    // Physical phone tilt up -> cursor up (-dy in Windows screen space)
    final dx = -dDegYaw * sensitivity * gainYaw;
    final dy = dDegPitch * sensitivity * gainPitch;

    // Clamp maximum delta per event (150 px limit)
    final clampedDx = dx.clamp(-150.0, 150.0);
    final clampedDy = dy.clamp(-150.0, 150.0);

    if (clampedDx.abs() >= 0.1 || clampedDy.abs() >= 0.1) {
      _wsService.sendMove(clampedDx, clampedDy);
    }
  }

  double _calculateGain(double speedDegPerSec) {
    const v0 = 30.0; // Base speed threshold (deg/s)
    const gamma = 0.8;
    const alpha = 1.3;

    if (speedDegPerSec <= v0) return 1.0;
    final gain = 1.0 + gamma * math.pow(speedDegPerSec / v0, alpha);
    return gain.clamp(1.0, 5.0);
  }

  /// Sends a left click event to the PC.
  void sendLeftClick() {
    _wsService.sendLeftClick();
  }

  /// Sends a right click event to the PC.
  void sendRightClick() {
    _wsService.sendRightClick();
  }

  /// Sends a double click event to the PC.
  void sendDoubleClick() {
    _wsService.sendDoubleClick();
  }
}
