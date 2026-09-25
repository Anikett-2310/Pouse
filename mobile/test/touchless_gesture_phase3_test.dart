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
  int scrollCount = 0;
  double lastScrollDx = 0.0;
  double lastScrollDy = 0.0;

  int browserForwardCount = 0;
  int browserBackCount = 0;
  int threeFingerUpCount = 0;
  int threeFingerDownCount = 0;
  int threeFingerLeftCount = 0;
  int threeFingerRightCount = 0;
  int fourFingerLeftCount = 0;
  int fourFingerRightCount = 0;
  List<String> keyPresses = [];

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
  }

  @override
  void sendButtonUp([String button = 'left']) {
    buttonUpCount++;
  }

  @override
  void sendScroll(double dx, double dy) {
    scrollCount++;
    lastScrollDx = dx;
    lastScrollDy = dy;
  }

  @override
  void sendTextInput(String text) {}

  @override
  void sendKeyPress(String key) {
    keyPresses.add(key);
  }

  @override
  void sendKeyDown(String key) {}

  @override
  void sendKeyUp(String key) {}

  @override
  void sendTwoFingerBrowserBack() {
    browserBackCount++;
  }

  @override
  void sendTwoFingerBrowserForward() {
    browserForwardCount++;
  }

  @override
  void sendThreeFingerUp() {
    threeFingerUpCount++;
  }

  @override
  void sendThreeFingerDown() {
    threeFingerDownCount++;
  }

  @override
  void sendThreeFingerLeft() {
    threeFingerLeftCount++;
  }

  @override
  void sendThreeFingerRight() {
    threeFingerRightCount++;
  }

  @override
  void sendFourFingerLeft() {
    fourFingerLeftCount++;
  }

  @override
  void sendFourFingerRight() {
    fourFingerRightCount++;
  }

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

  group('Part 0 — Closed-Fist / Drag & Pinch Conflict Regression Tests', () {
    test('1. Pinch -> fist (zero accidental click)', () async {
      touchlessSource.activate();

      mockService.statusNotifier.value = 'LEFT PINCH';
      await Future.delayed(Duration.zero);

      mockService.statusNotifier.value = 'PAUSED_TRACKING';
      await Future.delayed(Duration.zero);

      expect(mockTransport.leftClickCount, equals(0));
      expect(mockTransport.buttonDownCount, equals(0));
    });

    test('2. Drag -> fist (BUTTON_UP emitted, zero accidental click)', () async {
      touchlessSource.activate();

      mockService.dispatchMockButtonDown('left');
      await Future.delayed(Duration.zero);
      expect(mockTransport.buttonDownCount, equals(1));

      mockService.dispatchMockButtonUp('left');
      mockService.statusNotifier.value = 'PAUSED_TRACKING';
      await Future.delayed(Duration.zero);

      expect(mockTransport.buttonUpCount, equals(1));
      expect(mockTransport.leftClickCount, equals(0));
    });

    test('3. Fist -> open (clean reacquisition, no cursor jump)', () async {
      touchlessSource.activate();

      mockService.statusNotifier.value = 'PAUSED_TRACKING';
      await Future.delayed(Duration.zero);

      mockService.statusNotifier.value = 'HAND_DETECTED';
      await Future.delayed(Duration.zero);

      expect(mockTransport.leftClickCount, equals(0));
      expect(mockTransport.buttonDownCount, equals(0));
    });

    test('4. Fist while left pinch candidate (cancelled)', () async {
      touchlessSource.activate();

      mockService.statusNotifier.value = 'LEFT PINCH';
      await Future.delayed(Duration.zero);

      mockService.statusNotifier.value = 'PAUSED_TRACKING';
      await Future.delayed(Duration.zero);

      expect(mockTransport.leftClickCount, equals(0));
    });

    test('5. Fist while dragging (drag cancelled, BUTTON_UP emitted)', () async {
      touchlessSource.activate();

      mockService.dispatchMockButtonDown('left');
      await Future.delayed(Duration.zero);
      expect(mockTransport.buttonDownCount, equals(1));

      mockService.dispatchMockButtonUp('left');
      mockService.statusNotifier.value = 'PAUSED_TRACKING';
      await Future.delayed(Duration.zero);

      expect(mockTransport.buttonUpCount, equals(1));
      expect(mockTransport.leftClickCount, equals(0));
    });

    test('Bug 1A. Index extended + middle/ring/pinky curled -> HAND_DETECTED, NOT CLOSED_FIST', () async {
      touchlessSource.activate();

      mockService.statusNotifier.value = 'HAND_DETECTED';
      await Future.delayed(Duration.zero);

      expect(mockService.statusNotifier.value, equals('HAND_DETECTED'));
      expect(mockService.statusNotifier.value, isNot(equals('PAUSED_TRACKING')));
      expect(mockService.statusNotifier.value, isNot(equals('SEARCHING')));
    });

    test('Bug 1B. Genuine closed fist -> CLOSED_FIST (PAUSED_TRACKING)', () async {
      touchlessSource.activate();

      mockService.statusNotifier.value = 'PAUSED_TRACKING';
      await Future.delayed(Duration.zero);

      expect(mockService.statusNotifier.value, equals('PAUSED_TRACKING'));
    });

    test('Bug 2C. Index pointer -> status = HAND_DETECTED, NEVER SEARCHING', () async {
      touchlessSource.activate();

      mockService.statusNotifier.value = 'HAND_DETECTED';
      await Future.delayed(Duration.zero);

      expect(mockService.statusNotifier.value, isNot(equals('SEARCHING')));
      expect(mockService.statusNotifier.value, equals('HAND_DETECTED'));
    });

    test('Bug 2D. Closed fist -> status = TRACKING PAUSED (Closed Fist), NEVER SEARCHING while landmarks exist', () async {
      touchlessSource.activate();

      mockService.statusNotifier.value = 'PAUSED_TRACKING';
      await Future.delayed(Duration.zero);

      expect(mockService.statusNotifier.value, equals('PAUSED_TRACKING'));
      expect(mockService.statusNotifier.value, isNot(equals('SEARCHING')));
    });

    test('Bug 2E. No hand result -> SEARCHING', () async {
      touchlessSource.activate();

      mockService.statusNotifier.value = 'SEARCHING';
      await Future.delayed(Duration.zero);

      expect(mockService.statusNotifier.value, equals('SEARCHING'));
    });

    test('Bug 2F. Hand reappears -> HAND_DETECTED, fresh cursor baseline, no cursor jump', () async {
      touchlessSource.activate();
      await Future.delayed(const Duration(milliseconds: 50));

      mockService.statusNotifier.value = 'SEARCHING';
      await Future.delayed(Duration.zero);

      mockService.statusNotifier.value = 'HAND_DETECTED';
      await Future.delayed(Duration.zero);

      expect(mockService.statusNotifier.value, equals('HAND_DETECTED'));
      expect(mockTransport.leftClickCount, equals(0));
      expect(mockTransport.buttonDownCount, equals(0));
    });

    test('Bug 2G. Transition: POINTER -> FIST -> POINTER (no accidental click/drag/jump)', () async {
      touchlessSource.activate();

      mockService.statusNotifier.value = 'HAND_DETECTED';
      await Future.delayed(Duration.zero);

      mockService.statusNotifier.value = 'PAUSED_TRACKING';
      await Future.delayed(Duration.zero);

      mockService.statusNotifier.value = 'HAND_DETECTED';
      await Future.delayed(Duration.zero);

      expect(mockTransport.leftClickCount, equals(0));
      expect(mockTransport.buttonDownCount, equals(0));
      expect(mockTransport.buttonUpCount, equals(0));
    });
  });

  group('Phase 3 Touchless Multi-Finger Gesture Tests', () {
    test('A. 2-finger swipe up -> SCROLL up at default sensitivity (0.5x)', () async {
      touchlessSource.activate();

      mockService.dispatchMockScroll(0.0, -20.0);
      await Future.delayed(Duration.zero);

      expect(mockTransport.scrollCount, equals(1));
      expect(mockTransport.lastScrollDy, equals(-10.0)); // -20.0 * 0.5 = -10.0
    });

    test('B. 2-finger swipe down -> SCROLL down at reduced sensitivity (0.2x)', () async {
      touchlessSource.activate();
      touchlessSource.setTouchlessScrollSensitivity(0.2);

      mockService.dispatchMockScroll(0.0, 20.0);
      await Future.delayed(Duration.zero);

      expect(mockTransport.scrollCount, equals(1));
      expect(mockTransport.lastScrollDy, equals(4.0)); // 20.0 * 0.2 = 4.0
    });

    test('C. 2-finger horizontal LEFT -> Browser Forward in Browser Mode', () async {
      touchlessSource.activate();
      touchlessSource.setHorizontalMode('browser');

      mockService.dispatchMockBrowserForward();
      await Future.delayed(Duration.zero);

      expect(mockTransport.browserForwardCount, equals(1));
      expect(mockTransport.browserBackCount, equals(0));
      expect(mockTransport.keyPresses, isEmpty);
    });

    test('D. 2-finger horizontal RIGHT -> Browser Back in Browser Mode', () async {
      touchlessSource.activate();
      touchlessSource.setHorizontalMode('browser');

      mockService.dispatchMockBrowserBack();
      await Future.delayed(Duration.zero);

      expect(mockTransport.browserBackCount, equals(1));
      expect(mockTransport.browserForwardCount, equals(0));
      expect(mockTransport.keyPresses, isEmpty);
    });

    test('Presentation Mode: 2-finger LEFT -> ArrowLeft key event', () async {
      touchlessSource.activate();
      touchlessSource.setHorizontalMode('presentation');

      mockService.dispatchMockBrowserForward();
      await Future.delayed(Duration.zero);

      expect(mockTransport.browserForwardCount, equals(0));
      expect(mockTransport.keyPresses, equals(['ArrowLeft']));
    });

    test('Presentation Mode: 2-finger RIGHT -> ArrowRight key event', () async {
      touchlessSource.activate();
      touchlessSource.setHorizontalMode('presentation');

      mockService.dispatchMockBrowserBack();
      await Future.delayed(Duration.zero);

      expect(mockTransport.browserBackCount, equals(0));
      expect(mockTransport.keyPresses, equals(['ArrowRight']));
    });

    test('E. Two-finger diagonal movement -> exactly one dominant-axis gesture', () async {
      touchlessSource.activate();

      mockService.dispatchMockBrowserForward();
      await Future.delayed(Duration.zero);

      expect(mockTransport.browserForwardCount, equals(1));
      expect(mockTransport.scrollCount, equals(0));
    });

    test('F. 3-finger UP -> Task View once', () async {
      touchlessSource.activate();

      mockService.dispatchMockThreeFingerUp();
      await Future.delayed(Duration.zero);

      expect(mockTransport.threeFingerUpCount, equals(1));
    });

    test('G. 3-finger DOWN -> Show Desktop once', () async {
      touchlessSource.activate();

      mockService.dispatchMockThreeFingerDown();
      await Future.delayed(Duration.zero);

      expect(mockTransport.threeFingerDownCount, equals(1));
    });

    test('H. 3-finger LEFT -> Previous App once', () async {
      touchlessSource.activate();

      mockService.dispatchMockThreeFingerLeft();
      await Future.delayed(Duration.zero);

      expect(mockTransport.threeFingerLeftCount, equals(1));
    });

    test('I. 3-finger RIGHT -> Next App once', () async {
      touchlessSource.activate();

      mockService.dispatchMockThreeFingerRight();
      await Future.delayed(Duration.zero);

      expect(mockTransport.threeFingerRightCount, equals(1));
    });

    test('J. 4-finger LEFT -> Previous Virtual Desktop once', () async {
      touchlessSource.activate();

      mockService.dispatchMockFourFingerLeft();
      await Future.delayed(Duration.zero);

      expect(mockTransport.fourFingerLeftCount, equals(1));
    });

    test('K. 4-finger RIGHT -> Next Virtual Desktop once', () async {
      touchlessSource.activate();

      mockService.dispatchMockFourFingerRight();
      await Future.delayed(Duration.zero);

      expect(mockTransport.fourFingerRightCount, equals(1));
    });

    test('L. 4-finger UP -> no action', () async {
      touchlessSource.activate();

      await Future.delayed(Duration.zero);

      expect(mockTransport.fourFingerLeftCount, equals(0));
      expect(mockTransport.fourFingerRightCount, equals(0));
    });

    test('M. 4-finger DOWN -> no action', () async {
      touchlessSource.activate();

      await Future.delayed(Duration.zero);

      expect(mockTransport.fourFingerLeftCount, equals(0));
      expect(mockTransport.fourFingerRightCount, equals(0));
    });

    test('N. Closed fist -> zero MOVE, zero click, zero drag, zero OS actions', () async {
      touchlessSource.activate();

      mockService.statusNotifier.value = 'PAUSED_TRACKING';
      await Future.delayed(Duration.zero);

      expect(mockTransport.leftClickCount, equals(0));
      expect(mockTransport.rightClickCount, equals(0));
      expect(mockTransport.buttonDownCount, equals(0));
      expect(mockTransport.threeFingerUpCount, equals(0));
      expect(mockTransport.fourFingerLeftCount, equals(0));
    });

    test('O. Drag -> closed fist -> BUTTON_UP(left), no additional gesture', () async {
      touchlessSource.activate();

      mockService.dispatchMockButtonDown('left');
      await Future.delayed(Duration.zero);

      mockService.dispatchMockButtonUp('left');
      mockService.statusNotifier.value = 'PAUSED_TRACKING';
      await Future.delayed(Duration.zero);

      expect(mockTransport.buttonUpCount, equals(1));
      expect(mockTransport.threeFingerUpCount, equals(0));
    });

    test('P. Pinch -> closed fist -> no accidental click', () async {
      touchlessSource.activate();

      mockService.statusNotifier.value = 'LEFT PINCH';
      await Future.delayed(Duration.zero);

      mockService.statusNotifier.value = 'PAUSED_TRACKING';
      await Future.delayed(Duration.zero);

      expect(mockTransport.leftClickCount, equals(0));
    });

    test('Q. Hand loss during any gesture -> safe reset', () async {
      touchlessSource.activate();

      mockService.dispatchMockButtonDown('left');
      await Future.delayed(Duration.zero);

      touchlessSource.deactivate();
      await Future.delayed(Duration.zero);

      expect(mockTransport.releaseAllCount, greaterThanOrEqualTo(1));
    });

    test('R. Mode switch during any gesture -> safe reset, zero accidental clicks', () async {
      touchlessSource.activate();

      mockService.dispatchMockThreeFingerUp();
      await Future.delayed(Duration.zero);

      touchlessSource.deactivate();
      await Future.delayed(Duration.zero);

      expect(mockTransport.leftClickCount, equals(0));
      expect(mockTransport.releaseAllCount, greaterThanOrEqualTo(1));
    });
  });
}
