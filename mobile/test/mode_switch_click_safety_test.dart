import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/src/mouse_mode_manager.dart';
import 'package:mobile/src/sources/motion_source.dart';
import 'package:mobile/src/sources/touchpad_source.dart';
import 'package:mobile/src/sources/touchless_source.dart';
import 'package:mobile/src/transports/pouse_transport.dart';
import 'package:mobile/src/websocket_service.dart';
import 'package:sensors_plus/sensors_plus.dart';

class MockSafetyTransport implements PouseTransport {
  final List<String> eventLog = [];

  @override
  TransportType get type => TransportType.wifi;

  @override
  bool get isConnected => true;

  @override
  final ValueNotifier<ConnectionStatus> statusNotifier =
      ValueNotifier<ConnectionStatus>(ConnectionStatus.connected);

  @override
  ConnectionStatus get status => ConnectionStatus.connected;

  @override
  void sendMove(double dx, double dy) => eventLog.add('MOVE');

  @override
  void sendLeftClick() => eventLog.add('LEFT_CLICK');

  @override
  void sendRightClick() => eventLog.add('RIGHT_CLICK');

  @override
  void sendDoubleClick() => eventLog.add('DOUBLE_CLICK');

  @override
  void sendButtonDown([String button = 'left']) => eventLog.add('BUTTON_DOWN_$button');

  @override
  void sendButtonUp([String button = 'left']) => eventLog.add('BUTTON_UP_$button');

  @override
  void sendScroll(double dx, double dy) => eventLog.add('SCROLL');

  @override
  void sendTextInput(String text) {}

  @override
  void sendKeyPress(String key) {}

  @override
  void sendKeyDown(String key) {}

  @override
  void sendKeyUp(String key) {}

  @override
  void sendTwoFingerBrowserBack() {}

  @override
  void sendTwoFingerBrowserForward() {}

  @override
  void sendThreeFingerUp() {}

  @override
  void sendThreeFingerDown() {}

  @override
  void sendThreeFingerLeft() {}

  @override
  void sendThreeFingerRight() {}

  @override
  void sendFourFingerLeft() {}

  @override
  void sendFourFingerRight() {}

  @override
  void releaseAll() {
    eventLog.add('RELEASE_ALL');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Mode Switch Click Safety Tests (Bug 2 Regression Guard)', () {
    late MouseModeManager manager;
    late MockSafetyTransport transport;
    late TouchpadSource touchpadSource;
    late MotionSource motionSource;
    late TouchlessSource touchlessSource;

    setUp(() {
      transport = MockSafetyTransport();
      touchpadSource = TouchpadSource(transport);
      motionSource = MotionSource(
        transport,
        accelStream: const Stream<AccelerometerEvent>.empty(),
        gyroStream: const Stream<GyroscopeEvent>.empty(),
      );
      touchlessSource = TouchlessSource(transport);

      manager = MouseModeManager();
      manager.registerSource(touchpadSource);
      manager.registerSource(motionSource);
      manager.registerSource(touchlessSource);
    });

    test('Switching Touchless -> Touchpad emits NO automatic clicks or button releases', () {
      manager.selectMode(MouseMode.touchless);
      transport.eventLog.clear();

      manager.selectMode(MouseMode.touchpad);

      expect(transport.eventLog.contains('LEFT_CLICK'), isFalse);
      expect(transport.eventLog.contains('RIGHT_CLICK'), isFalse);
      expect(transport.eventLog.contains('BUTTON_UP_left'), isFalse);
      expect(transport.eventLog.contains('BUTTON_UP_right'), isFalse);
    });

    test('Switching Touchless -> Motion emits NO automatic clicks or button releases', () {
      manager.selectMode(MouseMode.touchless);
      transport.eventLog.clear();

      manager.selectMode(MouseMode.motion);

      expect(transport.eventLog.contains('LEFT_CLICK'), isFalse);
      expect(transport.eventLog.contains('RIGHT_CLICK'), isFalse);
      expect(transport.eventLog.contains('BUTTON_UP_left'), isFalse);
      expect(transport.eventLog.contains('BUTTON_UP_right'), isFalse);
    });

    test('Switching Touchpad -> Touchless emits NO automatic clicks or button releases', () {
      manager.selectMode(MouseMode.touchpad);
      transport.eventLog.clear();

      manager.selectMode(MouseMode.touchless);

      expect(transport.eventLog.contains('LEFT_CLICK'), isFalse);
      expect(transport.eventLog.contains('RIGHT_CLICK'), isFalse);
      expect(transport.eventLog.contains('BUTTON_UP_left'), isFalse);
      expect(transport.eventLog.contains('BUTTON_UP_right'), isFalse);
    });

    test('Switching Motion -> Touchless emits NO automatic clicks or button releases', () {
      manager.selectMode(MouseMode.motion);
      transport.eventLog.clear();

      manager.selectMode(MouseMode.touchless);

      expect(transport.eventLog.contains('LEFT_CLICK'), isFalse);
      expect(transport.eventLog.contains('RIGHT_CLICK'), isFalse);
      expect(transport.eventLog.contains('BUTTON_UP_left'), isFalse);
      expect(transport.eventLog.contains('BUTTON_UP_right'), isFalse);
    });
  });
}
