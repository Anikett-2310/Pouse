import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../websocket_service.dart';
import 'pouse_transport.dart';

/// Production Bluetooth Classic RFCOMM Transport implementation.
///
/// Implements [PouseTransport] over an isolated RFCOMM server channel on Android,
/// connecting directly to the Pouse.exe RFCOMM client on Windows without Wi-Fi.
class BluetoothRfcommService implements PouseTransport {
  static const MethodChannel _controlChannel = MethodChannel('pouse/rfcomm_control');
  static const EventChannel _statusChannel = EventChannel('pouse/rfcomm_status');

  @override
  TransportType get type => TransportType.bluetooth;

  ConnectionStatus _status = ConnectionStatus.disconnected;
  StreamSubscription? _statusSubscription;

  // Button & Key tracking for safety release
  bool _isLeftButtonDown = false;
  bool _isRightButtonDown = false;
  final Set<String> _heldKeys = {};

  @override
  final ValueNotifier<ConnectionStatus> statusNotifier =
      ValueNotifier<ConnectionStatus>(ConnectionStatus.disconnected);

  final ValueNotifier<String?> errorNotifier = ValueNotifier<String?>(null);
  final ValueNotifier<String> userMessageNotifier =
      ValueNotifier<String>('Pair phone in Windows Bluetooth Settings to connect');

  BluetoothRfcommService() {
    _subscribeToStatusStream();
  }

  void _subscribeToStatusStream() {
    try {
      _statusSubscription = _statusChannel.receiveBroadcastStream().listen(
        (dynamic rawStatus) {
          final statusStr = rawStatus.toString();
          _handleNativeStatus(statusStr);
        },
        onError: (dynamic error) {
          debugPrint('[RFCOMM] Status channel error: $error');
          _setStatus(ConnectionStatus.error);
          userMessageNotifier.value = 'Bluetooth error: $error';
        },
      );
    } catch (e) {
      debugPrint('[RFCOMM] Failed to subscribe to status stream: $e');
    }
  }

  void _handleNativeStatus(String statusStr) {
    if (statusStr == 'connected') {
      _setStatus(ConnectionStatus.connected);
      userMessageNotifier.value = 'Connected';
      errorNotifier.value = null;
    } else if (statusStr == 'listening') {
      _setStatus(ConnectionStatus.connecting);
      userMessageNotifier.value = 'Searching for Pouse PC...';
    } else if (statusStr == 'stopped') {
      _setStatus(ConnectionStatus.disconnected);
      userMessageNotifier.value = 'Disconnected';
    } else if (statusStr.startsWith('error:')) {
      _setStatus(ConnectionStatus.error);
      final msg = statusStr.replaceFirst('error:', '').trim();
      errorNotifier.value = msg;
      userMessageNotifier.value = 'Bluetooth error: $msg';
    }
  }

  @override
  ConnectionStatus get status => _status;

  @override
  bool get isConnected => _status == ConnectionStatus.connected;

  Future<bool> startServer() async {
    try {
      _setStatus(ConnectionStatus.connecting);
      userMessageNotifier.value = 'Starting Bluetooth server...';
      final bool? result = await _controlChannel.invokeMethod<bool>('startServer');
      if (result == true) {
        return true;
      } else {
        _setStatus(ConnectionStatus.error);
        userMessageNotifier.value = 'Failed to start Bluetooth server';
        return false;
      }
    } on PlatformException catch (e) {
      _setStatus(ConnectionStatus.error);
      errorNotifier.value = e.message;
      userMessageNotifier.value = 'Bluetooth error: ${e.message}';
      return false;
    } catch (e) {
      _setStatus(ConnectionStatus.error);
      errorNotifier.value = e.toString();
      return false;
    }
  }

  Future<void> disconnect() async {
    releaseAll();
    try {
      await _controlChannel.invokeMethod<bool>('stopServer');
    } catch (e) {
      debugPrint('[RFCOMM] Error stopping server: $e');
    }
    _setStatus(ConnectionStatus.disconnected);
    userMessageNotifier.value = 'Disconnected';
  }

  void sendEvent(Map<String, dynamic> event) {
    if (_status == ConnectionStatus.connected) {
      try {
        final jsonString = jsonEncode(event);
        _controlChannel.invokeMethod<bool>('sendEvent', {'message': jsonString});
      } catch (e) {
        debugPrint('[RFCOMM] Failed to send event: $e');
      }
    }
  }

  // Microtask Coalescing for MOVE events
  double _pendingMoveDx = 0.0;
  double _pendingMoveDy = 0.0;
  bool _isMoveScheduled = false;

  @override
  void sendMove(double dx, double dy) {
    _pendingMoveDx += dx;
    _pendingMoveDy += dy;

    if (!_isMoveScheduled) {
      _isMoveScheduled = true;
      scheduleMicrotask(_flushMove);
    }
  }

  @override
  void sendAbsMove(double x, double y) {}

  void _flushMove() {
    _isMoveScheduled = false;
    final dx = _pendingMoveDx;
    final dy = _pendingMoveDy;
    _pendingMoveDx = 0.0;
    _pendingMoveDy = 0.0;

    if (dx != 0 || dy != 0) {
      sendEvent({
        'event': 'MOVE',
        'dx': dx,
        'dy': dy,
        't': DateTime.now().millisecondsSinceEpoch,
      });
    }
  }

  @override
  void sendLeftClick() {
    sendEvent({'event': 'LEFT_CLICK'});
  }

  @override
  void sendRightClick() {
    sendEvent({'event': 'RIGHT_CLICK'});
  }

  @override
  void sendDoubleClick() {
    sendEvent({'event': 'DOUBLE_CLICK'});
  }

  @override
  void sendButtonDown([String button = 'left']) {
    if (button == 'right') {
      _isRightButtonDown = true;
    } else {
      _isLeftButtonDown = true;
    }
    sendEvent({
      'event': 'BUTTON_DOWN',
      'button': button,
    });
  }

  @override
  void sendButtonUp([String button = 'left']) {
    if (button == 'right') {
      _isRightButtonDown = false;
    } else {
      _isLeftButtonDown = false;
    }
    sendEvent({
      'event': 'BUTTON_UP',
      'button': button,
    });
  }

  @override
  void sendScroll(double dx, double dy) {
    sendEvent({
      'event': 'SCROLL',
      'dx': dx,
      'dy': dy,
    });
  }

  @override
  void sendTextInput(String text) {
    sendEvent({
      'event': 'TEXT_INPUT',
      'text': text,
    });
  }

  @override
  void sendKeyPress(String key) {
    sendEvent({
      'event': 'KEY_PRESS',
      'key': key,
    });
  }

  @override
  void sendKeyDown(String key) {
    _heldKeys.add(key);
    sendEvent({
      'event': 'KEY_DOWN',
      'key': key,
    });
  }

  @override
  void sendKeyUp(String key) {
    _heldKeys.remove(key);
    sendEvent({
      'event': 'KEY_UP',
      'key': key,
    });
  }

  @override
  void sendTwoFingerBrowserBack() {
    sendEvent({'event': 'TWO_FINGER_BROWSER_BACK'});
  }

  @override
  void sendTwoFingerBrowserForward() {
    sendEvent({'event': 'TWO_FINGER_BROWSER_FORWARD'});
  }

  @override
  void sendThreeFingerUp() {
    sendEvent({'event': 'THREE_FINGER_UP'});
  }

  @override
  void sendThreeFingerDown() {
    sendEvent({'event': 'THREE_FINGER_DOWN'});
  }

  @override
  void sendThreeFingerLeft() {
    sendEvent({'event': 'THREE_FINGER_LEFT'});
  }

  @override
  void sendThreeFingerRight() {
    sendEvent({'event': 'THREE_FINGER_RIGHT'});
  }

  @override
  void sendFourFingerLeft() {
    sendEvent({'event': 'FOUR_FINGER_LEFT'});
  }

  @override
  void sendFourFingerRight() {
    sendEvent({'event': 'FOUR_FINGER_RIGHT'});
  }

  @override
  void sendSystemMagnify(double scale) {
    if (_status != ConnectionStatus.connected) return;
    sendEvent({
      'event': 'SYSTEM_MAGNIFY',
      'scale': scale,
    });
  }

  @override
  void releaseAll() {

    if (_isLeftButtonDown) {
      sendButtonUp('left');
    }
    if (_isRightButtonDown) {
      sendButtonUp('right');
    }
    for (final key in _heldKeys.toList()) {
      sendKeyUp(key);
    }
    _heldKeys.clear();
  }

  void _setStatus(ConnectionStatus newStatus) {
    _status = newStatus;
    statusNotifier.value = newStatus;
  }

  void dispose() {
    _statusSubscription?.cancel();
    statusNotifier.dispose();
    errorNotifier.dispose();
    userMessageNotifier.dispose();
  }
}
