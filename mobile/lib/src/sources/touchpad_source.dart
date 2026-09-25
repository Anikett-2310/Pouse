import '../input_source.dart';
import '../mouse_mode_manager.dart';
import '../transports/pouse_transport.dart';

/// Touchpad input source implementation for V1.1 Unified Architecture.
///
/// Manages the activation lifecycle and state for Touchpad mode.
/// Delegates event dispatching to the active [PouseTransport].
class TouchpadSource implements InputSource {
  PouseTransport _transport;
  bool _isActive = false;

  TouchpadSource(this._transport);

  void setTransport(PouseTransport transport) {
    _transport = transport;
  }

  @override
  MouseMode get mode => MouseMode.touchpad;

  @override
  String get displayName => 'Touchpad';

  @override
  bool get isActive => _isActive;

  @override
  void activate() {
    _isActive = true;
  }

  @override
  void deactivate() {
    _isActive = false;
  }

  PouseTransport get transport => _transport;
}
