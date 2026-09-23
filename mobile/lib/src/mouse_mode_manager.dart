import 'package:flutter/foundation.dart';
import 'input_source.dart';

/// Enum representing the available user-facing Mouse Modes in Pouse.
enum MouseMode {
  touchpad,
  motion,
  optical,
  touchless,
}

/// Manages the registered [InputSource] instances and enforces that
/// **exactly one active InputSource** is active at any given time.
class MouseModeManager extends ChangeNotifier {
  final Map<MouseMode, InputSource> _sources = {};
  MouseMode _currentMode = MouseMode.touchpad;

  MouseModeManager();

  /// The currently selected [MouseMode].
  MouseMode get currentMode => _currentMode;

  /// The currently active [InputSource], or null if no source registered for [currentMode].
  InputSource? get activeSource => _sources[_currentMode];

  /// Register an [InputSource] with the manager.
  void registerSource(InputSource source) {
    _sources[source.mode] = source;
    if (source.mode == _currentMode && !source.isActive) {
      source.activate();
    }
  }

  /// Switch the active mouse mode to [mode].
  ///
  /// Deactivates the previously active source and activates the newly selected source.
  void selectMode(MouseMode mode) {
    if (_currentMode == mode && activeSource?.isActive == true) {
      return;
    }

    final previousSource = activeSource;
    previousSource?.deactivate();

    _currentMode = mode;
    final nextSource = activeSource;
    nextSource?.activate();

    notifyListeners();
  }
}
