import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/src/sources/motion_source.dart';
import 'package:mobile/src/views/motion_view.dart';
import 'package:mobile/src/websocket_service.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MockWebSocketService extends WebSocketService {
  final List<Map<String, dynamic>> sentEvents = [];

  @override
  ConnectionStatus get status => ConnectionStatus.connected;

  @override
  void sendEvent(Map<String, dynamic> event) {
    sentEvents.add(event);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('MotionView Widget & Relative Swipe Tests', () {
    late MockWebSocketService mockWsService;
    late MotionSource source;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      mockWsService = MockWebSocketService();
      source = MotionSource(
        mockWsService,
        accelStream: const Stream<AccelerometerEvent>.empty(),
        gyroStream: const Stream<GyroscopeEvent>.empty(),
      );
      source.activate();
      await Future<void>.delayed(Duration.zero);
    });

    testWidgets('renders MotionView UI elements correctly with right-side Scroll Zone, shared scroll settings, Keyboard button and NO 2x button', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MotionView(source: source),
          ),
        ),
      );

      // Verify header status indicator
      expect(find.textContaining('INACTIVE'), findsOneWidget);

      // Verify touch activation surface guidance
      expect(find.text('HOLD TO MOVE POINTER'), findsOneWidget);

      // Verify sensitivity label
      expect(find.textContaining('px/°'), findsOneWidget);

      // Verify dedicated vertical right-side Scroll Zone exists
      expect(find.textContaining('SCROLL ZONE'), findsOneWidget);

      // Verify shared scroll settings (Scroll label & Natural toggle)
      expect(find.text('Scroll'), findsOneWidget);
      expect(find.text('Natural'), findsOneWidget);

      // Verify action buttons: Left Click, Utilities Button (⋯), Right Click (and NO 2x)
      expect(find.text('Left Click'), findsOneWidget);
      expect(find.text('Right Click'), findsOneWidget);
      expect(find.byTooltip('Utilities'), findsOneWidget);
      expect(find.text('2x'), findsNothing); // Dedicated 2x button is removed
    });

    testWidgets('tapping Utilities and Keyboard toggle button opens SharedKeyboardPanel', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MotionView(source: source),
          ),
        ),
      );

      // Initially Esc and Enter quick buttons are hidden
      expect(find.text('Esc'), findsNothing);
      expect(find.text('Enter'), findsNothing);

      // Tap Utilities toggle icon button
      await tester.tap(find.byTooltip('Utilities'));
      await tester.pumpAndSettle();

      // Tap Keyboard icon button in secondary toolbar
      await tester.tap(find.byTooltip('Keyboard'));
      await tester.pumpAndSettle();

      // Verify Esc and Enter quick buttons are visible inside SharedKeyboardPanel
      expect(find.text('Esc'), findsOneWidget);
      expect(find.text('Enter'), findsOneWidget);
    });

    testWidgets('relative gesture swipes from TOP, MIDDLE, and BOTTOM emit SCROLL events and zero click events on release', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MotionView(source: source),
          ),
        ),
      );

      final scrollZoneFinder = find.textContaining('SCROLL ZONE');
      expect(scrollZoneFinder, findsOneWidget);

      final rect = tester.getRect(scrollZoneFinder);

      // Test 1: Touch near TOP, swipe DOWN
      mockWsService.sentEvents.clear();
      final topPos = Offset(rect.center.dx, rect.top + 10);
      var gesture = await tester.startGesture(topPos);
      await tester.pump(const Duration(milliseconds: 20));
      await gesture.moveBy(const Offset(0, 30));
      await tester.pump(const Duration(milliseconds: 20));
      await gesture.up();
      await tester.pumpAndSettle();

      var scrollEvents = mockWsService.sentEvents.where((e) => e['event'] == 'SCROLL').toList();
      expect(scrollEvents.isNotEmpty, isTrue);
      expect(scrollEvents.first['dy'], greaterThan(0));

      // Test 2: Touch near BOTTOM, swipe UP
      mockWsService.sentEvents.clear();
      final bottomPos = Offset(rect.center.dx, rect.bottom - 10);
      gesture = await tester.startGesture(bottomPos);
      await tester.pump(const Duration(milliseconds: 20));
      await gesture.moveBy(const Offset(0, -30));
      await tester.pump(const Duration(milliseconds: 20));
      await gesture.up();
      await tester.pumpAndSettle();

      scrollEvents = mockWsService.sentEvents.where((e) => e['event'] == 'SCROLL').toList();
      expect(scrollEvents.isNotEmpty, isTrue);
      expect(scrollEvents.first['dy'], lessThan(0));

      // Test 3: Touch in MIDDLE, swipe DOWN
      mockWsService.sentEvents.clear();
      final middlePos = rect.center;
      gesture = await tester.startGesture(middlePos);
      await tester.pump(const Duration(milliseconds: 20));
      await gesture.moveBy(const Offset(0, 30));
      await tester.pump(const Duration(milliseconds: 20));
      await gesture.up();
      await tester.pumpAndSettle();

      scrollEvents = mockWsService.sentEvents.where((e) => e['event'] == 'SCROLL').toList();
      expect(scrollEvents.isNotEmpty, isTrue);
      expect(scrollEvents.first['dy'], greaterThan(0));

      // Verify no click events emitted at all across all scroll gestures
      final buttonEvents = mockWsService.sentEvents.where((e) =>
          e['event'] == 'LEFT_CLICK' ||
          e['event'] == 'RIGHT_CLICK' ||
          e['event'] == 'DOUBLE_CLICK' ||
          e['event'] == 'BUTTON_DOWN' ||
          e['event'] == 'BUTTON_UP').toList();
      expect(buttonEvents.isEmpty, isTrue);
    });

    testWidgets('toggling Natural/Reverse in MotionView inverts scroll direction and persists preference', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MotionView(source: source),
          ),
        ),
      );

      // Tap Natural toggle button to change to Reverse
      await tester.tap(find.text('Natural'));
      await tester.pumpAndSettle();
      expect(find.text('Reverse'), findsOneWidget);

      final scrollZoneFinder = find.textContaining('SCROLL ZONE');
      final center = tester.getCenter(scrollZoneFinder);

      mockWsService.sentEvents.clear();
      final gesture = await tester.startGesture(center);
      await tester.pump(const Duration(milliseconds: 20));
      await gesture.moveBy(const Offset(0, 30));
      await tester.pump(const Duration(milliseconds: 20));
      await gesture.up();
      await tester.pumpAndSettle();

      final scrollEvents = mockWsService.sentEvents.where((e) => e['event'] == 'SCROLL').toList();
      expect(scrollEvents.isNotEmpty, isTrue);
      // In Reverse mode, downward swipe (dy = +30) produces negative scroll dy
      expect(scrollEvents.first['dy'], lessThan(0));

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('pouse_scroll_natural'), isFalse);
    });
  });
}
