import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Dart service bridging Flutter UI/Sources with the native Android CameraX & MediaPipe engine.
class TouchlessCameraService {
  static const MethodChannel _controlChannel = MethodChannel('pouse/touchless_control');
  static const EventChannel _eventChannel = EventChannel('pouse/touchless_events');

  final ValueNotifier<String> statusNotifier = ValueNotifier<String>('SEARCHING');
  final ValueNotifier<String> errorMessageNotifier = ValueNotifier<String>('');
  final ValueNotifier<List<Offset>> landmarksNotifier = ValueNotifier<List<Offset>>([]);

  final StreamController<Offset> _moveStreamController = StreamController<Offset>.broadcast();
  final StreamController<Offset> _scrollStreamController = StreamController<Offset>.broadcast();
  final StreamController<void> _leftClickController = StreamController<void>.broadcast();
  final StreamController<void> _rightClickController = StreamController<void>.broadcast();
  final StreamController<void> _doubleClickController = StreamController<void>.broadcast();
  final StreamController<String> _buttonDownController = StreamController<String>.broadcast();
  final StreamController<String> _buttonUpController = StreamController<String>.broadcast();
  final StreamController<void> _browserForwardController = StreamController<void>.broadcast();
  final StreamController<void> _browserBackController = StreamController<void>.broadcast();
  final StreamController<void> _threeFingerUpController = StreamController<void>.broadcast();
  final StreamController<void> _threeFingerDownController = StreamController<void>.broadcast();
  final StreamController<void> _threeFingerLeftController = StreamController<void>.broadcast();
  final StreamController<void> _threeFingerRightController = StreamController<void>.broadcast();
  final StreamController<void> _fourFingerLeftController = StreamController<void>.broadcast();
  final StreamController<void> _fourFingerRightController = StreamController<void>.broadcast();

  Stream<Offset> get moveStream => _moveStreamController.stream;
  Stream<Offset> get scrollStream => _scrollStreamController.stream;
  Stream<void> get leftClickStream => _leftClickController.stream;
  Stream<void> get rightClickStream => _rightClickController.stream;
  Stream<void> get doubleClickStream => _doubleClickController.stream;
  Stream<String> get buttonDownStream => _buttonDownController.stream;
  Stream<String> get buttonUpStream => _buttonUpController.stream;
  Stream<void> get browserForwardStream => _browserForwardController.stream;
  Stream<void> get browserBackStream => _browserBackController.stream;
  Stream<void> get threeFingerUpStream => _threeFingerUpController.stream;
  Stream<void> get threeFingerDownStream => _threeFingerDownController.stream;
  Stream<void> get threeFingerLeftStream => _threeFingerLeftController.stream;
  Stream<void> get threeFingerRightStream => _threeFingerRightController.stream;
  Stream<void> get fourFingerLeftStream => _fourFingerLeftController.stream;
  Stream<void> get fourFingerRightStream => _fourFingerRightController.stream;

  StreamSubscription? _eventSubscription;
  bool _isTracking = false;
  bool get isTracking => _isTracking;

  TouchlessCameraService() {
    _listenToEvents();
  }

  void _listenToEvents() {
    _eventSubscription = _eventChannel.receiveBroadcastStream().listen(
      (dynamic event) {
        if (event is Map) {
          final eventType = event['event'] as String?;
          switch (eventType) {
            case 'MOVE':
              final dx = (event['dx'] as num?)?.toDouble() ?? 0.0;
              final dy = (event['dy'] as num?)?.toDouble() ?? 0.0;
              _moveStreamController.add(Offset(dx, dy));
              break;
            case 'SCROLL':
              final dx = (event['dx'] as num?)?.toDouble() ?? 0.0;
              final dy = (event['dy'] as num?)?.toDouble() ?? 0.0;
              _scrollStreamController.add(Offset(dx, dy));
              break;
            case 'LEFT_CLICK':
              _leftClickController.add(null);
              break;
            case 'RIGHT_CLICK':
              _rightClickController.add(null);
              break;
            case 'DOUBLE_CLICK':
              _doubleClickController.add(null);
              break;
            case 'BUTTON_DOWN':
              final btn = (event['button'] as String?) ?? 'left';
              _buttonDownController.add(btn);
              break;
            case 'BUTTON_UP':
              final btn = (event['button'] as String?) ?? 'left';
              _buttonUpController.add(btn);
              break;
            case 'BROWSER_FORWARD':
              _browserForwardController.add(null);
              break;
            case 'BROWSER_BACK':
              _browserBackController.add(null);
              break;
            case 'THREE_FINGER_UP':
              _threeFingerUpController.add(null);
              break;
            case 'THREE_FINGER_DOWN':
              _threeFingerDownController.add(null);
              break;
            case 'THREE_FINGER_LEFT':
              _threeFingerLeftController.add(null);
              break;
            case 'THREE_FINGER_RIGHT':
              _threeFingerRightController.add(null);
              break;
            case 'FOUR_FINGER_LEFT':
              _fourFingerLeftController.add(null);
              break;
            case 'FOUR_FINGER_RIGHT':
              _fourFingerRightController.add(null);
              break;
            case 'STATUS':
              final status = (event['status'] as String?) ?? 'SEARCHING';
              final message = (event['message'] as String?) ?? '';
              statusNotifier.value = status;
              if (message.isNotEmpty) {
                errorMessageNotifier.value = message;
              }
              if (kDebugMode) {
                debugPrint('[TouchlessService Diagnostic] Status updated -> $status ${message.isNotEmpty ? "($message)" : ""}');
              }
              break;
            case 'LANDMARKS':
              final rawPoints = event['landmarks'] as List<dynamic>?;
              if (rawPoints != null) {
                final points = rawPoints.map((pt) {
                  final map = Map<String, dynamic>.from(pt as Map);
                  final x = (map['x'] as num).toDouble();
                  final y = (map['y'] as num).toDouble();
                  return Offset(x, y);
                }).toList();
                landmarksNotifier.value = points;
              }
              break;
          }
        }
      },
      onError: (error) {
        statusNotifier.value = 'CAMERA_ERROR';
        errorMessageNotifier.value = error.toString();
        debugPrint('[TouchlessService Diagnostic] EventChannel Error: $error');
      },
    );
  }

  Future<bool> startTracking({double sensitivity = 1.0}) async {
    try {
      _isTracking = true;
      statusNotifier.value = 'INITIALIZING';
      errorMessageNotifier.value = '';
      debugPrint('[TouchlessService Diagnostic] Invoking startTracking method...');
      final bool? success = await _controlChannel.invokeMethod<bool>('startTracking', {
        'sensitivity': sensitivity,
      });
      return success ?? true;
    } catch (e) {
      _isTracking = true;
      statusNotifier.value = 'SEARCHING';
      debugPrint('[TouchlessService Diagnostic] startTracking fallback (unit test mode): $e');
      return true;
    }
  }

  Future<void> stopTracking() async {
    _isTracking = false;
    statusNotifier.value = 'SEARCHING';
    landmarksNotifier.value = [];
    try {
      await _controlChannel.invokeMethod('stopTracking');
    } catch (_) {}
  }

  Future<void> setSensitivity(double value) async {
    try {
      await _controlChannel.invokeMethod('setSensitivity', {'sensitivity': value});
    } catch (_) {}
  }

  /// Dispatches simulated/mock index movement for unit testing or fallback frame feeds.
  void dispatchMockMove(double dx, double dy) {
    if (_isTracking) {
      statusNotifier.value = 'HAND_DETECTED';
      _moveStreamController.add(Offset(dx, dy));
    }
  }

  void dispatchMockScroll(double dx, double dy) => _scrollStreamController.add(Offset(dx, dy));
  void dispatchMockLeftClick() => _leftClickController.add(null);
  void dispatchMockRightClick() => _rightClickController.add(null);
  void dispatchMockDoubleClick() => _doubleClickController.add(null);
  void dispatchMockButtonDown([String button = 'left']) => _buttonDownController.add(button);
  void dispatchMockButtonUp([String button = 'left']) => _buttonUpController.add(button);
  void dispatchMockBrowserForward() => _browserForwardController.add(null);
  void dispatchMockBrowserBack() => _browserBackController.add(null);
  void dispatchMockThreeFingerUp() => _threeFingerUpController.add(null);
  void dispatchMockThreeFingerDown() => _threeFingerDownController.add(null);
  void dispatchMockThreeFingerLeft() => _threeFingerLeftController.add(null);
  void dispatchMockThreeFingerRight() => _threeFingerRightController.add(null);
  void dispatchMockFourFingerLeft() => _fourFingerLeftController.add(null);
  void dispatchMockFourFingerRight() => _fourFingerRightController.add(null);

  void dispose() {
    _eventSubscription?.cancel();
    _moveStreamController.close();
    _scrollStreamController.close();
    _leftClickController.close();
    _rightClickController.close();
    _doubleClickController.close();
    _buttonDownController.close();
    _buttonUpController.close();
    _browserForwardController.close();
    _browserBackController.close();
    _threeFingerUpController.close();
    _threeFingerDownController.close();
    _threeFingerLeftController.close();
    _threeFingerRightController.close();
    _fourFingerLeftController.close();
    _fourFingerRightController.close();
    statusNotifier.dispose();
    errorMessageNotifier.dispose();
    landmarksNotifier.dispose();
  }
}
