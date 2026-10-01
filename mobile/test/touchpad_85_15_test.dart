import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/src/sources/touchpad_source.dart';
import 'package:mobile/src/transports/pouse_transport.dart';
import 'package:mobile/src/views/touchpad_view.dart';
import 'package:mobile/src/websocket_service.dart';
import 'package:mobile/src/widgets/shared_os_actions_panel.dart';

class MockPouseTransport implements PouseTransport {
  final List<String> events = [];

  @override
  TransportType get type => TransportType.wifi;

  @override
  ConnectionStatus get status => ConnectionStatus.connected;

  @override
  final ValueNotifier<ConnectionStatus> statusNotifier =
      ValueNotifier<ConnectionStatus>(ConnectionStatus.connected);

  @override
  bool get isConnected => true;

  @override
  void sendMove(double dx, double dy) {
    events.add('MOVE:$dx,$dy');
  }

  @override
  void sendAbsMove(double x, double y) {}

  @override
  void sendLeftClick() {
    events.add('LEFT_CLICK');
  }

  @override
  void sendRightClick() {
    events.add('RIGHT_CLICK');
  }

  @override
  void sendDoubleClick() {
    events.add('DOUBLE_CLICK');
  }

  @override
  void sendButtonDown([String button = 'left']) {
    events.add('BUTTON_DOWN:$button');
  }

  @override
  void sendButtonUp([String button = 'left']) {
    events.add('BUTTON_UP:$button');
  }

  @override
  void sendScroll(double dx, double dy) {
    events.add('SCROLL:$dx,$dy');
  }

  @override
  void sendTextInput(String text) {}

  @override
  void sendKeyPress(String key) {}

  @override
  void sendKeyDown(String key) {}

  @override
  void sendKeyUp(String key) {}

  @override
  void sendTwoFingerBrowserBack() {
    events.add('TWO_FINGER_BROWSER_BACK');
  }

  @override
  void sendTwoFingerBrowserForward() {
    events.add('TWO_FINGER_BROWSER_FORWARD');
  }

  @override
  void sendThreeFingerUp() {
    events.add('THREE_FINGER_UP');
  }

  @override
  void sendThreeFingerDown() {
    events.add('THREE_FINGER_DOWN');
  }

  @override
  void sendThreeFingerLeft() {
    events.add('THREE_FINGER_LEFT');
  }

  @override
  void sendThreeFingerRight() {
    events.add('THREE_FINGER_RIGHT');
  }

  @override
  void sendFourFingerLeft() {
    events.add('FOUR_FINGER_LEFT');
  }

  @override
  void sendFourFingerRight() {
    events.add('FOUR_FINGER_RIGHT');
  }

  @override
  void sendSystemMagnify(double scale) {}

  @override
  void sendVolumeUp() {}

  @override
  void sendVolumeDown() {}

  @override
  void sendVolumeMute() {}

  @override
  void sendBrightnessUp() {}

  @override
  void sendBrightnessDown() {}

  @override
  void sendWindowsSearch() {}

  @override
  void sendTaskbarApps() {
    events.add('TASKBAR_APPS');
  }

  @override
  void releaseAll() {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Touchpad 85/15 Zone Tests', () {
    late MockPouseTransport transport;
    late TouchpadSource source;

    setUp(() {
      transport = MockPouseTransport();
      source = TouchpadSource(transport);
    });

    testWidgets('Touchpad renders 85% Touchpad Surface and 15% Scroll Zone', (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TouchpadView(source: source),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify Touchpad Surface text is present
      expect(find.text('TOUCHPAD SURFACE'), findsOneWidget);

      // Verify SCROLL ZONE text is present
      expect(find.text('SCROLL ZONE'), findsOneWidget);

      // Verify Expanded flex values (85 and 15)
      final expandedWidgets = tester.widgetList<Expanded>(find.byType(Expanded)).toList();
      final flex85 = expandedWidgets.where((e) => e.flex == 85);
      final flex15 = expandedWidgets.where((e) => e.flex == 15);
      expect(flex85, isNotEmpty);
      expect(flex15, isNotEmpty);

      // 1. 15% Scroll Zone: single-finger vertical scrolling
      final scrollZoneFinder = find.text('SCROLL ZONE');
      expect(scrollZoneFinder, findsOneWidget);

      final scrollZoneCenter = tester.getCenter(scrollZoneFinder);
      final scrollGesture = await tester.startGesture(scrollZoneCenter);
      await scrollGesture.moveBy(const Offset(0, 50));
      await scrollGesture.up();
      await tester.pumpAndSettle();

      expect(transport.events.any((e) => e.startsWith('SCROLL:')), isTrue);
      transport.events.clear();

      // 2. 85% Touchpad Surface: cursor movement
      final surfaceCenter = tester.getCenter(find.text('TOUCHPAD SURFACE'));
      final moveGesture = await tester.startGesture(surfaceCenter);
      await tester.pump(const Duration(milliseconds: 20));
      await moveGesture.moveBy(const Offset(30, 20));
      await tester.pump(const Duration(milliseconds: 20));
      await moveGesture.up();
      await tester.pump(const Duration(milliseconds: 300));

      expect(transport.events.any((e) => e.startsWith('MOVE:')), isTrue);
      expect(transport.events.contains('LEFT_CLICK'), isFalse);
      transport.events.clear();

      // 3. 85% Touchpad Surface: tap -> left click
      await tester.tap(find.text('TOUCHPAD SURFACE'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(transport.events, contains('LEFT_CLICK'));
      transport.events.clear();

      // 4. 85% Touchpad Surface: double tap
      await tester.tap(find.text('TOUCHPAD SURFACE'));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(find.text('TOUCHPAD SURFACE'));
      await tester.pumpAndSettle();
      expect(transport.events, contains('DOUBLE_CLICK'));
      transport.events.clear();

      // 5. 85% Touchpad Surface: two-finger tap -> right click
      final g1 = await tester.startGesture(surfaceCenter);
      final g2 = await tester.startGesture(surfaceCenter + const Offset(40, 0));
      await tester.pump(const Duration(milliseconds: 50));
      await g1.up();
      await tester.pump(const Duration(milliseconds: 20));
      await g2.up();
      await tester.pumpAndSettle();
      expect(transport.events, contains('RIGHT_CLICK'));
      transport.events.clear();

      // 6. 85% Touchpad Surface: two-finger vertical scrolling
      final s1 = await tester.startGesture(surfaceCenter);
      final s2 = await tester.startGesture(surfaceCenter + const Offset(40, 0));
      await tester.pump(const Duration(milliseconds: 20));
      await s1.moveBy(const Offset(0, 40));
      await s2.moveBy(const Offset(0, 40));
      await tester.pump(const Duration(milliseconds: 20));
      await s1.up();
      await tester.pump(const Duration(milliseconds: 20));
      await s2.up();
      await tester.pump(const Duration(milliseconds: 300));
      expect(transport.events.any((e) => e.startsWith('SCROLL:')), isTrue);
      transport.events.clear();

      // 7. 85% Touchpad Surface: two-finger horizontal swipe
      final h1 = await tester.startGesture(surfaceCenter);
      final h2 = await tester.startGesture(surfaceCenter + const Offset(40, 0));
      await tester.pump(const Duration(milliseconds: 20));
      await h1.moveBy(const Offset(-50, 0));
      await h2.moveBy(const Offset(-50, 0));
      await tester.pump(const Duration(milliseconds: 20));
      await h1.up();
      await tester.pump(const Duration(milliseconds: 20));
      await h2.up();
      await tester.pump(const Duration(milliseconds: 300));
      expect(transport.events.contains('TWO_FINGER_BROWSER_FORWARD') ||
             transport.events.contains('TWO_FINGER_BROWSER_BACK'), isTrue);
      transport.events.clear();

      // 8. 85% Touchpad Surface: tap-hold drag and drag release
      await tester.tapAt(surfaceCenter);
      await tester.pump(const Duration(milliseconds: 50));
      final dragGesture = await tester.startGesture(surfaceCenter);
      await tester.pump(const Duration(milliseconds: 50));
      await dragGesture.moveBy(const Offset(50, 0));
      await tester.pump(const Duration(milliseconds: 50));
      expect(transport.events, contains('BUTTON_DOWN:left'));
      expect(transport.events.any((e) => e.startsWith('MOVE:')), isTrue);

      // Drag release
      await dragGesture.up();
      await tester.pumpAndSettle();
      expect(transport.events, contains('BUTTON_UP:left'));
    });
  });

  group('OS Actions Panel Strict Separation Tests', () {
    late MockPouseTransport transport;

    setUp(() {
      transport = MockPouseTransport();
    });

    testWidgets('OS Actions has Taskbar Apps and NO Volume/Brightness/Search duplicates', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SharedOsActionsPanel(transport: transport),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Must have Taskbar Apps
      expect(find.text('Taskbar Apps'), findsOneWidget);
      expect(find.text('Task View'), findsOneWidget);
      expect(find.text('Show Desktop'), findsOneWidget);
      expect(find.text('Previous App'), findsOneWidget);
      expect(find.text('Next App'), findsOneWidget);

      // MUST NOT have PC Controls
      expect(find.text('Vol -'), findsNothing);
      expect(find.text('Mute'), findsNothing);
      expect(find.text('Vol +'), findsNothing);
      expect(find.text('Bright -'), findsNothing);
      expect(find.text('Bright +'), findsNothing);
      expect(find.text('Search (Win+S)'), findsNothing);

      // Tapping Taskbar Apps triggers transport.sendTaskbarApps()
      await tester.tap(find.text('Taskbar Apps'));
      await tester.pumpAndSettle();

      expect(transport.events, contains('TASKBAR_APPS'));
    });
  });
}
