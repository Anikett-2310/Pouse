import 'mouse_mode_manager.dart';

/// Abstract base class for all Pouse mouse input sources.
///
/// An [InputSource] manages the input behavior, internal state, and lifecycle
/// for a specific input mode (e.g. Touchpad, Motion, Optical, Touchless).
///
/// It is decoupled from Flutter UI rendering, allowing the UI layer (MainScreen)
/// to decide how to render views for the active input mode.
abstract class InputSource {
  /// The [MouseMode] associated with this input source.
  MouseMode get mode;

  /// User-facing display name of the input source mode.
  String get displayName;

  /// Whether this input source is currently active.
  bool get isActive;

  /// Called when this input source is activated by the [MouseModeManager].
  void activate();

  /// Called when this input source is deactivated by the [MouseModeManager].
  void deactivate();
}
