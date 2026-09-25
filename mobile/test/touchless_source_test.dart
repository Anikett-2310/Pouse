import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/src/mouse_mode_manager.dart';
import 'package:mobile/src/sources/touchless_source.dart';
import 'package:mobile/src/transports/pouse_transport.dart';
import 'package:mobile/src/transports/touchless_camera_service.dart';
import 'package:mobile/src/websocket_service.dart';

class MockPouseTransport implements PouseTransport {
  final List<String> log = [];

  @override
  TransportType get type => TransportType.wifi;

  @override
  ConnectionStatus get status => ConnectionStatus.connected;

  @override
  bool get isConnected => true;

  @override
  get statusNotifier => throw UnimplementedError();

  @override
  void sendMove(double dx, double dy) => log.add('move:$dx,$dy');

  @override
  void sendLeftClick() => log.add('leftClick');

  @override
  void sendRightClick() => log.add('rightClick');

  @override
  void sendDoubleClick() => log.add('doubleClick');

  @override
  void sendButtonDown([String button = 'left']) => log.add('buttonDown:$button');

  @override
  void sendButtonUp([String button = 'left']) => log.add('buttonUp:$button');

  @override
  void sendScroll(double dx, double dy) => log.add('scroll:$dx,$dy');

  @override
  void sendTextInput(String text) => log.add('text:$text');

  @override
  void sendKeyPress(String key) => log.add('keyPress:$key');

  @override
  void sendKeyDown(String key) => log.add('keyDown:$key');

  @override
  void sendKeyUp(String key) => log.add('keyUp:$key');

  @override
  void sendTwoFingerBrowserBack() => log.add('browserBack');

  @override
  void sendTwoFingerBrowserForward() => log.add('browserForward');

  @override
  void sendThreeFingerUp() => log.add('taskView');

  @override
  void sendThreeFingerDown() => log.add('showDesktop');

  @override
  void sendThreeFingerLeft() => log.add('prevApp');

  @override
  void sendThreeFingerRight() => log.add('nextApp');

  @override
  void sendFourFingerLeft() => log.add('prevDesktop');

  @override
  void sendFourFingerRight() => log.add('nextDesktop');

  @override
  void releaseAll() => log.add('releaseAll');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('TouchlessSource Phase 1 Tests', () {
    late MockPouseTransport mockTransport;
    late TouchlessCameraService mockService;
    late TouchlessSource source;

    setUp(() {
      mockTransport = MockPouseTransport();
      mockService = TouchlessCameraService();
      source = TouchlessSource(mockTransport, service: mockService);
    });

    test('initial state and properties', () {
      expect(source.mode, equals(MouseMode.touchless));
      expect(source.displayName, equals('Touchless'));
      expect(source.isActive, isFalse);
      expect(source.transport, equals(mockTransport));
    });

    test('activation lifecycle toggles tracking and emits releaseAll on deactivation', () {
      source.activate();
      expect(source.isActive, isTrue);

      source.deactivate();
      expect(source.isActive, isFalse);
      expect(mockTransport.log, contains('releaseAll'));
    });

    test('pointer movement delta is routed to PouseTransport.sendMove', () async {
      source.activate();
      mockService.dispatchMockMove(15.0, 25.0);
      await pumpEventQueue();

      expect(mockTransport.log, contains('move:15.0,25.0'));
    });

    test('sensitivity settings update correctly', () {
      source.setSensitivity(2.5);
      expect(source.sensitivity, equals(2.5));
    });
  });
}
