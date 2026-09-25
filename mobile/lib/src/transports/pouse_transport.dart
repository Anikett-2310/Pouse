import 'package:flutter/foundation.dart';

import '../websocket_service.dart';

enum TransportType { wifi, bluetooth }

/// Abstract Pouse Input Transport interface.
///
/// Serves as the Strategy Pattern base for input-producing features (Touchpad,
/// Motion, Keyboard, Gaming, OS Actions, Gestures, Browser Navigation).
abstract class PouseTransport {
  TransportType get type;
  ConnectionStatus get status;
  ValueNotifier<ConnectionStatus> get statusNotifier;
  bool get isConnected;

  void sendMove(double dx, double dy);
  void sendLeftClick();
  void sendRightClick();
  void sendDoubleClick();
  void sendButtonDown([String button = 'left']);
  void sendButtonUp([String button = 'left']);
  void sendScroll(double dx, double dy);

  void sendTextInput(String text);
  void sendKeyPress(String key);
  void sendKeyDown(String key);
  void sendKeyUp(String key);

  void sendTwoFingerBrowserBack();
  void sendTwoFingerBrowserForward();

  void sendThreeFingerUp();
  void sendThreeFingerDown();
  void sendThreeFingerLeft();
  void sendThreeFingerRight();

  void sendFourFingerLeft();
  void sendFourFingerRight();

  void releaseAll();
}
