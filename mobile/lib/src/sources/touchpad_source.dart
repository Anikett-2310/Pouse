import '../input_source.dart';
import '../mouse_mode_manager.dart';
import '../websocket_service.dart';

/// Touchpad input source implementation for V1.1 Unified Architecture.
///
/// Manages the activation lifecycle and state for Touchpad mode.
/// Delegates event dispatching to the shared [WebSocketService].
class TouchpadSource implements InputSource {
  final WebSocketService _wsService;
  bool _isActive = false;

  TouchpadSource(this._wsService);

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

  WebSocketService get wsService => _wsService;
}
