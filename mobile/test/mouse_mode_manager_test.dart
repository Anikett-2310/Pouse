import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/src/input_source.dart';
import 'package:mobile/src/mouse_mode_manager.dart';

class MockInputSource implements InputSource {
  @override
  final MouseMode mode;
  @override
  final String displayName;
  bool _isActive = false;

  MockInputSource(this.mode, this.displayName);

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
}

void main() {
  group('MouseModeManager Unit Tests', () {
    test('initial mode defaults to touchpad', () {
      final manager = MouseModeManager();
      expect(manager.currentMode, MouseMode.touchpad);
      expect(manager.activeSource, isNull);
    });

    test('registering source for current mode activates it', () {
      final manager = MouseModeManager();
      final touchpadSource = MockInputSource(MouseMode.touchpad, 'Touchpad');

      manager.registerSource(touchpadSource);

      expect(manager.activeSource, touchpadSource);
      expect(touchpadSource.isActive, isTrue);
    });

    test('switching mode deactivates old source and activates new source', () {
      final manager = MouseModeManager();
      final touchpadSource = MockInputSource(MouseMode.touchpad, 'Touchpad');
      final motionSource = MockInputSource(MouseMode.motion, 'Motion');

      manager.registerSource(touchpadSource);
      manager.registerSource(motionSource);

      expect(manager.currentMode, MouseMode.touchpad);
      expect(touchpadSource.isActive, isTrue);
      expect(motionSource.isActive, isFalse);

      manager.selectMode(MouseMode.motion);

      expect(manager.currentMode, MouseMode.motion);
      expect(touchpadSource.isActive, isFalse);
      expect(motionSource.isActive, isTrue);
    });
  });
}
