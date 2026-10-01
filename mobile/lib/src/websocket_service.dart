import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'transports/pouse_transport.dart';

enum ConnectionStatus {
  disconnected,
  connecting,
  connected,
  error,
}

class WebSocketService implements PouseTransport {
  static const MethodChannel _wifiControlChannel = MethodChannel('pouse/wifi_control');

  @override
  TransportType get type => TransportType.wifi;

  WebSocketChannel? _channel;
  ConnectionStatus _status = ConnectionStatus.disconnected;
  String? _currentIp;
  int _port = 8081;
  String? _pairToken;

  // Button state tracking for safety
  bool _isLeftButtonDown = false;
  bool _isRightButtonDown = false;

  @override
  final ValueNotifier<ConnectionStatus> statusNotifier =
      ValueNotifier<ConnectionStatus>(ConnectionStatus.disconnected);
  final ValueNotifier<String?> errorNotifier = ValueNotifier<String?>(null);

  @override
  ConnectionStatus get status => _status;

  @override
  bool get isConnected => _status == ConnectionStatus.connected;

  String? get currentIp => _currentIp;
  String? get pairToken => _pairToken;

  void setPairToken(String? token) {
    _pairToken = token?.trim();
    if (isConnected && _pairToken != null && _pairToken!.isNotEmpty) {
      sendEvent({
        'event': 'AUTH',
        'token': _pairToken,
      });
    }
  }

  Future<void> connect(String ip, {int port = 8081, String? pairToken}) async {
    if (_channel != null) {
      await disconnect();
    }

    _currentIp = ip.trim();
    _port = port;
    if (pairToken != null && pairToken.trim().isNotEmpty) {
      _pairToken = pairToken.trim();
    }
    _setStatus(ConnectionStatus.connecting);
    errorNotifier.value = null;

    // Explicitly bind Android process socket routing to physical Wi-Fi interface
    if (defaultTargetPlatform == TargetPlatform.android) {
      try {
        await _wifiControlChannel.invokeMethod<bool>('bindWifiNetwork');
      } catch (e) {
        debugPrint('[WIFI_SERVICE] Wi-Fi network binding failed: $e');
      }
    }

    final uri = Uri.parse('ws://$_currentIp:$_port');
    try {
      _channel = WebSocketChannel.connect(uri);
      await _channel!.ready.timeout(const Duration(seconds: 5));

      _setStatus(ConnectionStatus.connected);

      // Authenticate over existing control connection if pairToken is present
      if (_pairToken != null && _pairToken!.isNotEmpty) {
        sendEvent({
          'event': 'AUTH',
          'token': _pairToken,
        });
      }

      _channel!.stream.listen(
        (message) {
          _handleIncomingMessage(message);
        },
        onError: (error) {
          _channel?.sink.close();
          _channel = null;
          _setStatus(ConnectionStatus.error);
          errorNotifier.value = 'Connection error: $error';
        },
        onDone: () {
          _channel?.sink.close();
          _channel = null;
          _setStatus(ConnectionStatus.disconnected);
        },
      );
    } on TimeoutException {
      _channel?.sink.close();
      _channel = null;
      _setStatus(ConnectionStatus.error);
      await _checkWifiAndSetError('Connection timed out while reaching ws://$_currentIp:$_port');
    } catch (e) {
      _channel?.sink.close();
      _channel = null;
      _setStatus(ConnectionStatus.error);
      await _checkWifiAndSetError('Failed to connect to ws://$_currentIp:$_port ($e)');
    }
  }

  Future<void> _checkWifiAndSetError(String defaultError) async {
    if (defaultTargetPlatform == TargetPlatform.android) {
      try {
        final bool? isWifiConnected = await _wifiControlChannel.invokeMethod<bool>('isWifiConnected');
        if (isWifiConnected != true) {
          errorNotifier.value = 'Wi-Fi connection unavailable';
          return;
        }
      } catch (_) {}
    }
    errorNotifier.value = defaultError;
  }

  Future<void> disconnect() async {
    _isLeftButtonDown = false;
    _isRightButtonDown = false;
    _channel?.sink.close();
    _channel = null;
    _setStatus(ConnectionStatus.disconnected);

    if (defaultTargetPlatform == TargetPlatform.android) {
      try {
        await _wifiControlChannel.invokeMethod<bool>('unbindWifiNetwork');
      } catch (_) {}
    }
  }

  void sendEvent(Map<String, dynamic> event) {
    if (_status == ConnectionStatus.connected && _channel != null) {
      if (event['event'] != 'MOVE' && (_pendingMoveDx != 0 || _pendingMoveDy != 0)) {
        _flushMove();
      }
      try {
        final jsonString = jsonEncode(event);
        _channel!.sink.add(jsonString);
      } catch (e) {
        debugPrint('Failed to send WebSocket event: $e');
      }
    }
  }

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

  double? _pendingAbsX;
  double? _pendingAbsY;
  bool _isAbsMoveScheduled = false;

  @override
  void sendAbsMove(double x, double y) {
    _pendingAbsX = x;
    _pendingAbsY = y;

    if (!_isAbsMoveScheduled) {
      _isAbsMoveScheduled = true;
      scheduleMicrotask(_flushAbsMove);
    }
  }

  void _flushAbsMove() {
    _isAbsMoveScheduled = false;
    final x = _pendingAbsX;
    final y = _pendingAbsY;
    _pendingAbsX = null;
    _pendingAbsY = null;

    if (x != null && y != null) {
      sendEvent({
        'event': 'ABS_MOVE',
        'x': x,
        'y': y,
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

  final Set<String> _heldKeys = {};

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
    sendEvent({
      'event': 'SYSTEM_MAGNIFY',
      'scale': scale,
    });
  }

  @override
  void sendVolumeUp() => sendEvent({'event': 'VOLUME_UP'});

  @override
  void sendVolumeDown() => sendEvent({'event': 'VOLUME_DOWN'});

  @override
  void sendVolumeMute() => sendEvent({'event': 'VOLUME_MUTE'});

  @override
  void sendBrightnessUp() => sendEvent({'event': 'BRIGHTNESS_UP'});

  @override
  void sendBrightnessDown() => sendEvent({'event': 'BRIGHTNESS_DOWN'});

  @override
  void sendWindowsSearch() => sendEvent({'event': 'WINDOWS_SEARCH'});

  @override
  void sendTaskbarApps() => sendEvent({'event': 'TASKBAR_APPS'});

  static const MethodChannel _remoteScreenMethodChannel = MethodChannel('pouse/remote_screen/method');

  WebSocketService() {
    _initRemoteScreenControlChannel();
  }

  void _initRemoteScreenControlChannel() {
    try {
      _remoteScreenMethodChannel.setMethodCallHandler((call) async {
        if (call.method == 'sendControlMessage') {
          final Map<dynamic, dynamic>? args = call.arguments as Map<dynamic, dynamic>?;
          final String? jsonStr = args?['json'] as String?;
          if (jsonStr != null && jsonStr.isNotEmpty) {
            sendRawJson(jsonStr);
          }
        }
      });
    } catch (e) {
      debugPrint('[WEBSOCKET_SERVICE] Could not initialize remote screen MethodChannel handler: $e');
    }
  }

  void sendRawJson(String jsonStr) {
    if (_status == ConnectionStatus.connected && _channel != null) {
      try {
        _channel!.sink.add(jsonStr);
      } catch (e) {
        debugPrint('Failed to send raw WebSocket text: $e');
      }
    }
  }

  void _handleIncomingMessage(dynamic message) {
    try {
      final text = message as String;
      final data = jsonDecode(text);
      if (data is Map<String, dynamic>) {
        final event = data['event'];
        if (event == 'PONG') {
          debugPrint('Received PONG from PC client');
        } else if (event == 'AUTH_OK' ||
            event == 'SCREEN_METADATA' ||
            event == 'RESUME_OK' ||
            event == 'STOP_SCREEN_OK' ||
            event == 'INPUT_BLOCKED' ||
            event == 'SESSION_BUSY' ||
            event == 'SESSION_EXPIRED' ||
            event == 'ERROR') {
          _forwardToNativeRemoteScreen(text);
        }
      }
    } catch (e) {
      debugPrint('Error parsing message: $e');
    }
  }

  void _forwardToNativeRemoteScreen(String jsonStr) {
    try {
      _remoteScreenMethodChannel.invokeMethod('onControlMessage', {'json': jsonStr});
    } catch (e) {
      debugPrint('Failed to forward control message to native: $e');
    }
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
    sendSystemMagnify(1.0);
  }


  void _setStatus(ConnectionStatus newStatus) {
    if (_status != newStatus) {
      final now = DateTime.now().toIso8601String();
      if (newStatus == ConnectionStatus.connected) {
        debugPrint('[DIAGNOSTIC] [CONTROL_CONNECTED] timestamp=$now');
      } else if (newStatus == ConnectionStatus.disconnected) {
        debugPrint('[DIAGNOSTIC] [CONTROL_DISCONNECTED] timestamp=$now');
      }
    }
    _status = newStatus;
    statusNotifier.value = newStatus;
  }

  void dispose() {
    statusNotifier.dispose();
    errorNotifier.dispose();
  }
}
