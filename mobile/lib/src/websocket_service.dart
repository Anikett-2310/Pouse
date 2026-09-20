import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

enum ConnectionStatus {
  disconnected,
  connecting,
  connected,
  error,
}

class WebSocketService {
  WebSocketChannel? _channel;
  ConnectionStatus _status = ConnectionStatus.disconnected;
  String? _currentIp;
  int _port = 8081;

  final ValueNotifier<ConnectionStatus> statusNotifier =
      ValueNotifier<ConnectionStatus>(ConnectionStatus.disconnected);
  final ValueNotifier<String?> errorNotifier = ValueNotifier<String?>(null);

  ConnectionStatus get status => _status;

  Future<void> connect(String ip, {int port = 8081}) async {
    if (_channel != null) {
      disconnect();
    }

    _currentIp = ip.trim();
    _port = port;
    _setStatus(ConnectionStatus.connecting);
    errorNotifier.value = null;

    final uri = Uri.parse('ws://$_currentIp:$_port');
    try {
      _channel = WebSocketChannel.connect(uri);
      await _channel!.ready.timeout(const Duration(seconds: 5));
      _setStatus(ConnectionStatus.connected);

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
      errorNotifier.value = 'Connection timed out while reaching ws://$_currentIp:$_port';
    } catch (e) {
      _channel?.sink.close();
      _channel = null;
      _setStatus(ConnectionStatus.error);
      errorNotifier.value = 'Failed to connect to ws://$_currentIp:$_port ($e)';
    }
  }

  void disconnect() {
    _channel?.sink.close();
    _channel = null;
    _setStatus(ConnectionStatus.disconnected);
  }

  void sendEvent(Map<String, dynamic> event) {
    if (_status == ConnectionStatus.connected && _channel != null) {
      try {
        final jsonString = jsonEncode(event);
        _channel!.sink.add(jsonString);
      } catch (e) {
        debugPrint('Failed to send WebSocket event: $e');
      }
    }
  }

  void sendMove(double dx, double dy) {
    debugPrint('[MOVE SENT] dx: $dx, dy: $dy');
    sendEvent({
      'event': 'MOVE',
      'dx': dx,
      'dy': dy,
    });
  }

  void sendLeftClick() {
    sendEvent({'event': 'LEFT_CLICK'});
  }

  void sendRightClick() {
    sendEvent({'event': 'RIGHT_CLICK'});
  }

  void sendDoubleClick() {
    sendEvent({'event': 'DOUBLE_CLICK'});
  }

  void sendButtonDown([String button = 'left']) {
    sendEvent({
      'event': 'BUTTON_DOWN',
      'button': button,
    });
  }

  void sendButtonUp([String button = 'left']) {
    sendEvent({
      'event': 'BUTTON_UP',
      'button': button,
    });
  }

  void sendScroll(double dx, double dy) {
    sendEvent({
      'event': 'SCROLL',
      'dx': dx,
      'dy': dy,
    });
  }

  void sendTextInput(String text) {
    sendEvent({
      'event': 'TEXT_INPUT',
      'text': text,
    });
  }

  void sendKeyPress(String key) {
    sendEvent({
      'event': 'KEY_PRESS',
      'key': key,
    });
  }

  void _handleIncomingMessage(dynamic message) {
    try {
      final data = jsonDecode(message as String);
      if (data['event'] == 'PONG') {
        debugPrint('Received PONG from PC client');
      }
    } catch (e) {
      debugPrint('Error parsing message: $e');
    }
  }

  void _setStatus(ConnectionStatus newStatus) {
    _status = newStatus;
    statusNotifier.value = newStatus;
  }
}
