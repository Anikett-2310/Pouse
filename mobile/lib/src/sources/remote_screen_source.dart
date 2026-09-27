import '../input_source.dart';
import '../mouse_mode_manager.dart';
import '../transports/pouse_transport.dart';

/// Remote Screen input source implementation.
///
/// Manages activation lifecycle for Remote Screen mode and delegates
/// event dispatching to the active [PouseTransport].
class RemoteScreenSource implements InputSource {
  PouseTransport _transport;
  bool _isActive = false;

  RemoteScreenSource(this._transport);

  void setTransport(PouseTransport transport) {
    _transport = transport;
  }

  @override
  MouseMode get mode => MouseMode.remoteScreen;

  @override
  String get displayName => 'Remote Screen';

  @override
  bool get isActive => _isActive;

  @override
  void activate() {
    _isActive = true;
  }

  @override
  void deactivate() {
    _isActive = false;
    _transport.releaseAll();
  }

  PouseTransport get transport => _transport;

  void sendAbsMove(double x, double y) => _transport.sendAbsMove(x, y);
  void sendLeftClick() => _transport.sendLeftClick();
  void sendRightClick() => _transport.sendRightClick();
  void sendDoubleClick() => _transport.sendDoubleClick();
  void sendButtonDown([String button = 'left']) => _transport.sendButtonDown(button);
  void sendButtonUp([String button = 'left']) => _transport.sendButtonUp(button);
  void sendScroll(double dx, double dy) => _transport.sendScroll(dx, dy);
  void sendKeyDown(String key) => _transport.sendKeyDown(key);
  void sendKeyUp(String key) => _transport.sendKeyUp(key);
}

