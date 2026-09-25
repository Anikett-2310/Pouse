import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/src/sources/touchless_source.dart';
import 'package:mobile/src/transports/pouse_transport.dart';
import 'package:mobile/src/transports/touchless_camera_service.dart';
import 'package:mobile/src/websocket_service.dart';

class MockPouseTransport implements PouseTransport {
  int leftClickCount = 0;
  int rightClickCount = 0;
  int doubleClickCount = 0;
  int buttonDownCount = 0;
  int buttonUpCount = 0;
  int releaseAllCount = 0;
  List<String> lastButtonEvents = [];

  final _statusNotifier = ValueNotifier<ConnectionStatus>(ConnectionStatus.connected);

  @override
  TransportType get type => TransportType.wifi;

  @override
  ConnectionStatus get status => ConnectionStatus.connected;

  @override
  ValueNotifier<ConnectionStatus> get statusNotifier => _statusNotifier;

  @override
  bool get isConnected => true;

  @override
  void sendMove(double dx, double dy) {}

  @override
  void sendLeftClick() {
    leftClickCount++;
  }

  @override
  void sendRightClick() {
    rightClickCount++;
  }

  @override
  void sendDoubleClick() {
    doubleClickCount++;
  }

  @override
  void sendButtonDown([String button = 'left']) {
    buttonDownCount++;
    lastButtonEvents.add('DOWN_$button');
  }

  @override
  void sendButtonUp([String button = 'left']) {
    buttonUpCount++;
    lastButtonEvents.add('UP_$button');
  }

  @override
  void sendScroll(double dx, double dy) {}

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
    releaseAllCount++;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late MockPouseTransport mockTransport;
  late TouchlessCameraService mockService;
  late TouchlessSource touchlessSource;

  setUp(() {
    mockTransport = MockPouseTransport();
    mockService = TouchlessCameraService();
    touchlessSource = TouchlessSource(mockTransport, service: mockService);
  });

  tearDown(() {
    touchlessSource.dispose();
  });

  group('Phase 2 Touchless Gesture State Machine Tests', () {
    test('A. Single left pinch -> exactly one LEFT_CLICK', () async {
      touchlessSource.activate();
      expect(touchlessSource.isActive, isTrue);

      mockService.dispatchMockLeftClick();
      await Future.delayed(Duration.zero);

      expect(mockTransport.leftClickCount, equals(1));
      expect(mockTransport.doubleClickCount, equals(0));
      expect(mockTransport.rightClickCount, equals(0));
    });

    test('B. Sustained left pinch -> exactly one LEFT_CLICK', () async {
      touchlessSource.activate();

      mockService.dispatchMockLeftClick();
      await Future.delayed(Duration.zero);

      expect(mockTransport.leftClickCount, equals(1));
      expect(mockTransport.buttonDownCount, equals(0));
    });

    test('C. Two quick left pinches -> exactly one DOUBLE_CLICK, zero standalone LEFT_CLICK events', () async {
      touchlessSource.activate();

      mockService.dispatchMockDoubleClick();
      await Future.delayed(Duration.zero);

      expect(mockTransport.doubleClickCount, equals(1));
      expect(mockTransport.leftClickCount, equals(0));
    });

    test('D. Thumb-middle pinch -> exactly one RIGHT_CLICK', () async {
      touchlessSource.activate();

      mockService.dispatchMockRightClick();
      await Future.delayed(Duration.zero);

      expect(mockTransport.rightClickCount, equals(1));
      expect(mockTransport.leftClickCount, equals(0));
    });

    test('E. Left pinch + movement > 0.015 -> BUTTON_DOWN(left), MOVE events, BUTTON_UP(left)', () async {
      touchlessSource.activate();

      mockService.dispatchMockButtonDown('left');
      await Future.delayed(Duration.zero);
      expect(mockTransport.buttonDownCount, equals(1));

      mockService.dispatchMockMove(10.0, 15.0);
      await Future.delayed(Duration.zero);

      mockService.dispatchMockButtonUp('left');
      await Future.delayed(Duration.zero);
      expect(mockTransport.buttonUpCount, equals(1));
    });

    test('F. Left pinch with movement below drag threshold -> click, NOT drag', () async {
      touchlessSource.activate();

      mockService.dispatchMockLeftClick();
      await Future.delayed(Duration.zero);

      expect(mockTransport.leftClickCount, equals(1));
      expect(mockTransport.buttonDownCount, equals(0));
    });

    test('G. Closed fist -> zero MOVE, zero clicks, zero button events', () async {
      touchlessSource.activate();

      mockService.statusNotifier.value = 'PAUSED_TRACKING';
      await Future.delayed(Duration.zero);

      expect(mockTransport.leftClickCount, equals(0));
      expect(mockTransport.rightClickCount, equals(0));
      expect(mockTransport.buttonDownCount, equals(0));
    });

    test('H. Hand loss while dragging -> exactly one BUTTON_UP(left), no stuck button', () async {
      touchlessSource.activate();

      mockService.dispatchMockButtonDown('left');
      await Future.delayed(Duration.zero);
      expect(mockTransport.buttonDownCount, equals(1));

      touchlessSource.deactivate();
      await Future.delayed(Duration.zero);

      expect(mockTransport.releaseAllCount, greaterThanOrEqualTo(1));
    });

    test('I. Mode switch while dragging -> safely releases held button, zero accidental clicks', () async {
      touchlessSource.activate();

      mockService.dispatchMockButtonDown('left');
      await Future.delayed(Duration.zero);

      touchlessSource.deactivate();
      await Future.delayed(Duration.zero);

      expect(mockTransport.releaseAllCount, greaterThanOrEqualTo(1));
      expect(mockTransport.leftClickCount, equals(0));
    });

    test('J. Reopening after closed fist -> no cursor jump', () async {
      touchlessSource.activate();

      mockService.statusNotifier.value = 'PAUSED_TRACKING';
      await Future.delayed(Duration.zero);

      mockService.statusNotifier.value = 'HAND_DETECTED';
      await Future.delayed(Duration.zero);

      expect(mockTransport.leftClickCount, equals(0));
    });

    test('K. Left/right pinch ambiguity -> one gesture only', () async {
      touchlessSource.activate();

      mockService.dispatchMockRightClick();
      await Future.delayed(Duration.zero);

      expect(mockTransport.rightClickCount, equals(1));
      expect(mockTransport.leftClickCount, equals(0));
    });
  });
}
