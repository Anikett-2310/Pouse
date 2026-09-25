import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mobile/src/sources/touchpad_source.dart';
import 'package:mobile/src/views/touchpad_view.dart';
import 'package:mobile/src/views/motion_view.dart';
import 'package:mobile/src/sources/motion_source.dart';
import 'package:mobile/src/widgets/shared_gaming_panel.dart';
import 'package:mobile/src/widgets/shared_keyboard_panel.dart';
import 'package:mobile/src/widgets/shared_os_actions_panel.dart';
import 'package:mobile/src/websocket_service.dart';

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
  SharedPreferences.setMockInitialValues({});

  group('Feature 1 — Touchpad Sensitivity Expansion (0.2x to 6.0x)', () {
    late MockWebSocketService mockWs;
    late TouchpadSource source;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      mockWs = MockWebSocketService();
      source = TouchpadSource(mockWs);
      source.activate();
    });

    testWidgets('Touchpad sensitivity slider min 0.2x and max 6.0x', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TouchpadView(source: source),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final sliders = tester.widgetList<Slider>(find.byType(Slider));
      final pointerSlider = sliders.first;

      expect(pointerSlider.min, equals(0.2));
      expect(pointerSlider.max, equals(6.0));
      expect(find.text('1.2x'), findsOneWidget); // Default pointer sensitivity is 1.2x
    });

    testWidgets('Touchpad sensitivity persistence loads saved value', (WidgetTester tester) async {
      SharedPreferences.setMockInitialValues({
        'pouse_pointer_sensitivity': 4.5,
      });

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TouchpadView(source: source),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('4.5x'), findsWidgets);
    });
  });

  group('Feature 2, 3, 4 — Windows 3/4-Finger Gestures & Architecture', () {
    late MockWebSocketService mockWs;
    late TouchpadSource source;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      mockWs = MockWebSocketService();
      source = TouchpadSource(mockWs);
      source.activate();
    });

    testWidgets('3-finger swipe UP sends THREE_FINGER_UP and no clicks on release', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TouchpadView(source: source),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final center = tester.getCenter(find.text('TOUCHPAD SURFACE'));

      final g1 = await tester.startGesture(center);
      final g2 = await tester.startGesture(center + const Offset(20, 0));
      final g3 = await tester.startGesture(center + const Offset(40, 0));
      await tester.pump(const Duration(milliseconds: 20));

      // Swipe UP 40px
      await g1.moveBy(const Offset(0, -40));
      await g2.moveBy(const Offset(0, -40));
      await g3.moveBy(const Offset(0, -40));
      await tester.pump(const Duration(milliseconds: 20));

      // Release all fingers
      await g1.up();
      await tester.pump(const Duration(milliseconds: 10));
      await g2.up();
      await tester.pump(const Duration(milliseconds: 10));
      await g3.up();
      await tester.pump(const Duration(milliseconds: 300));

      final gestureEvents = mockWs.sentEvents.where((e) => e['event'] == 'THREE_FINGER_UP').toList();
      final leftClicks = mockWs.sentEvents.where((e) => e['event'] == 'LEFT_CLICK').toList();
      final rightClicks = mockWs.sentEvents.where((e) => e['event'] == 'RIGHT_CLICK').toList();

      expect(gestureEvents.length, equals(1));
      expect(leftClicks.isEmpty, isTrue);
      expect(rightClicks.isEmpty, isTrue);
    });

    testWidgets('3-finger swipe DOWN sends THREE_FINGER_DOWN', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TouchpadView(source: source),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final center = tester.getCenter(find.text('TOUCHPAD SURFACE'));

      final g1 = await tester.startGesture(center);
      final g2 = await tester.startGesture(center + const Offset(20, 0));
      final g3 = await tester.startGesture(center + const Offset(40, 0));
      await tester.pump(const Duration(milliseconds: 20));

      await g1.moveBy(const Offset(0, 40));
      await g2.moveBy(const Offset(0, 40));
      await g3.moveBy(const Offset(0, 40));
      await tester.pump(const Duration(milliseconds: 20));

      await g1.up();
      await g2.up();
      await g3.up();
      await tester.pump(const Duration(milliseconds: 300));

      final gestureEvents = mockWs.sentEvents.where((e) => e['event'] == 'THREE_FINGER_DOWN').toList();
      expect(gestureEvents.length, equals(1));
    });

    testWidgets('3-finger swipe LEFT sends THREE_FINGER_LEFT', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TouchpadView(source: source),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final center = tester.getCenter(find.text('TOUCHPAD SURFACE'));

      final g1 = await tester.startGesture(center);
      final g2 = await tester.startGesture(center + const Offset(20, 0));
      final g3 = await tester.startGesture(center + const Offset(40, 0));
      await tester.pump(const Duration(milliseconds: 20));

      await g1.moveBy(const Offset(-40, 0));
      await g2.moveBy(const Offset(-40, 0));
      await g3.moveBy(const Offset(-40, 0));
      await tester.pump(const Duration(milliseconds: 20));

      await g1.up();
      await g2.up();
      await g3.up();
      await tester.pump(const Duration(milliseconds: 300));

      final gestureEvents = mockWs.sentEvents.where((e) => e['event'] == 'THREE_FINGER_LEFT').toList();
      expect(gestureEvents.length, equals(1));
    });

    testWidgets('3-finger swipe RIGHT sends THREE_FINGER_RIGHT', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TouchpadView(source: source),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final center = tester.getCenter(find.text('TOUCHPAD SURFACE'));

      final g1 = await tester.startGesture(center);
      final g2 = await tester.startGesture(center + const Offset(20, 0));
      final g3 = await tester.startGesture(center + const Offset(40, 0));
      await tester.pump(const Duration(milliseconds: 20));

      await g1.moveBy(const Offset(40, 0));
      await g2.moveBy(const Offset(40, 0));
      await g3.moveBy(const Offset(40, 0));
      await tester.pump(const Duration(milliseconds: 20));

      await g1.up();
      await g2.up();
      await g3.up();
      await tester.pump(const Duration(milliseconds: 300));

      final gestureEvents = mockWs.sentEvents.where((e) => e['event'] == 'THREE_FINGER_RIGHT').toList();
      expect(gestureEvents.length, equals(1));
    });

    testWidgets('4-finger swipe LEFT sends FOUR_FINGER_LEFT', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TouchpadView(source: source),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final center = tester.getCenter(find.text('TOUCHPAD SURFACE'));

      final g1 = await tester.startGesture(center);
      final g2 = await tester.startGesture(center + const Offset(20, 0));
      final g3 = await tester.startGesture(center + const Offset(40, 0));
      final g4 = await tester.startGesture(center + const Offset(60, 0));
      await tester.pump(const Duration(milliseconds: 20));

      await g1.moveBy(const Offset(-40, 0));
      await g2.moveBy(const Offset(-40, 0));
      await g3.moveBy(const Offset(-40, 0));
      await g4.moveBy(const Offset(-40, 0));
      await tester.pump(const Duration(milliseconds: 20));

      await g1.up();
      await g2.up();
      await g3.up();
      await g4.up();
      await tester.pump(const Duration(milliseconds: 300));

      final gestureEvents = mockWs.sentEvents.where((e) => e['event'] == 'FOUR_FINGER_LEFT').toList();
      expect(gestureEvents.length, equals(1));
    });

    testWidgets('4-finger swipe RIGHT sends FOUR_FINGER_RIGHT', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TouchpadView(source: source),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final center = tester.getCenter(find.text('TOUCHPAD SURFACE'));

      final g1 = await tester.startGesture(center);
      final g2 = await tester.startGesture(center + const Offset(20, 0));
      final g3 = await tester.startGesture(center + const Offset(40, 0));
      final g4 = await tester.startGesture(center + const Offset(60, 0));
      await tester.pump(const Duration(milliseconds: 20));

      await g1.moveBy(const Offset(40, 0));
      await g2.moveBy(const Offset(40, 0));
      await g3.moveBy(const Offset(40, 0));
      await g4.moveBy(const Offset(40, 0));
      await tester.pump(const Duration(milliseconds: 20));

      await g1.up();
      await g2.up();
      await g3.up();
      await g4.up();
      await tester.pump(const Duration(milliseconds: 300));

      final gestureEvents = mockWs.sentEvents.where((e) => e['event'] == 'FOUR_FINGER_RIGHT').toList();
      expect(gestureEvents.length, equals(1));
    });

    testWidgets('Partial finger-up does NOT prematurely trigger 2-finger right click or 1-finger click', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TouchpadView(source: source),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final center = tester.getCenter(find.text('TOUCHPAD SURFACE'));

      // Place 3 fingers down
      final g1 = await tester.startGesture(center);
      final g2 = await tester.startGesture(center + const Offset(20, 0));
      final g3 = await tester.startGesture(center + const Offset(40, 0));
      await tester.pump(const Duration(milliseconds: 20));

      // Lift finger 1 first (leaving 2 fingers down)
      await g1.up();
      await tester.pump(const Duration(milliseconds: 50));

      // Lift finger 2 (leaving 1 finger down)
      await g2.up();
      await tester.pump(const Duration(milliseconds: 50));

      // Lift finger 3
      await g3.up();
      await tester.pump(const Duration(milliseconds: 300));

      final rightClicks = mockWs.sentEvents.where((e) => e['event'] == 'RIGHT_CLICK').toList();
      final leftClicks = mockWs.sentEvents.where((e) => e['event'] == 'LEFT_CLICK').toList();

      expect(rightClicks.isEmpty, isTrue);
      expect(leftClicks.isEmpty, isTrue);
    });
  });

  group('Feature 7 — Unified Utilities Menu & OS Actions Panel', () {
    late MockWebSocketService mockWs;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      mockWs = MockWebSocketService();
    });

    testWidgets('Unified Utilities three-dot button exists in TouchpadView and opens secondary toolbar', (WidgetTester tester) async {
      final touchpadSource = TouchpadSource(mockWs)..activate();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TouchpadView(source: touchpadSource),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final utilBtn = find.byTooltip('Utilities');
      expect(utilBtn, findsOneWidget);

      await tester.tap(utilBtn);
      await tester.pumpAndSettle();

      expect(find.byTooltip('Keyboard'), findsOneWidget);
      expect(find.byTooltip('Presentation / Gaming'), findsOneWidget);
      expect(find.byTooltip('OS Actions'), findsOneWidget);
    });

    testWidgets('Unified Utilities three-dot button exists in MotionView and opens secondary toolbar', (WidgetTester tester) async {
      final motionSource = MotionSource(mockWs);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MotionView(source: motionSource),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final utilBtn = find.byTooltip('Utilities');
      expect(utilBtn, findsOneWidget);

      await tester.tap(utilBtn);
      await tester.pumpAndSettle();

      expect(find.byTooltip('Keyboard'), findsOneWidget);
      expect(find.byTooltip('Presentation / Gaming'), findsOneWidget);
      expect(find.byTooltip('OS Actions'), findsOneWidget);
    });

    testWidgets('Tapping Keyboard icon opens SharedKeyboardPanel', (WidgetTester tester) async {
      final touchpadSource = TouchpadSource(mockWs)..activate();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TouchpadView(source: touchpadSource),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Utilities'));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Keyboard'));
      await tester.pumpAndSettle();

      expect(find.byType(SharedKeyboardPanel), findsOneWidget);
    });

    testWidgets('Tapping Gaming icon opens SharedGamingPanel', (WidgetTester tester) async {
      final touchpadSource = TouchpadSource(mockWs)..activate();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TouchpadView(source: touchpadSource),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Utilities'));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Presentation / Gaming'));
      await tester.pumpAndSettle();

      expect(find.byType(SharedGamingPanel), findsOneWidget);
    });

    testWidgets('Tapping OS Actions icon opens SharedOsActionsPanel and triggers OS actions', (WidgetTester tester) async {
      final touchpadSource = TouchpadSource(mockWs)..activate();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TouchpadView(source: touchpadSource),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Utilities'));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('OS Actions'));
      await tester.pumpAndSettle();

      expect(find.byType(SharedOsActionsPanel), findsOneWidget);

      // Tap Task View button
      await tester.tap(find.text('Task View'));
      await tester.pumpAndSettle();

      // Tap Show Desktop button
      await tester.tap(find.text('Show Desktop'));
      await tester.pumpAndSettle();

      final taskViewEvents = mockWs.sentEvents.where((e) => e['event'] == 'THREE_FINGER_UP').toList();
      final desktopEvents = mockWs.sentEvents.where((e) => e['event'] == 'THREE_FINGER_DOWN').toList();

      expect(taskViewEvents.length, equals(1));
      expect(desktopEvents.length, equals(1));
    });
  });

  group('Milestone Refinements — 2-Finger Gestures, Keyboard & Motion UI', () {
    late MockWebSocketService mockWs;
    late TouchpadSource touchpadSource;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      mockWs = MockWebSocketService();
      touchpadSource = TouchpadSource(mockWs)..activate();
    });

    testWidgets('2-finger tap sends RIGHT_CLICK only after both fingers are released', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TouchpadView(source: touchpadSource),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final center = tester.getCenter(find.text('TOUCHPAD SURFACE'));

      final g1 = await tester.startGesture(center);
      final g2 = await tester.startGesture(center + const Offset(50, 0));
      await tester.pump(const Duration(milliseconds: 20));

      // Lift finger 1 first
      await g1.up();
      await tester.pump(const Duration(milliseconds: 20));
      expect(mockWs.sentEvents.where((e) => e['event'] == 'RIGHT_CLICK').isEmpty, isTrue);

      // Lift finger 2
      await g2.up();
      await tester.pump(const Duration(milliseconds: 100));

      final rightClicks = mockWs.sentEvents.where((e) => e['event'] == 'RIGHT_CLICK').toList();
      expect(rightClicks.length, equals(1));
    });

    testWidgets('2-finger vertical swipe sends SCROLL and NO RIGHT_CLICK', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TouchpadView(source: touchpadSource),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final center = tester.getCenter(find.text('TOUCHPAD SURFACE'));

      final g1 = await tester.startGesture(center);
      final g2 = await tester.startGesture(center + const Offset(50, 0));
      await tester.pump(const Duration(milliseconds: 20));

      await g1.moveBy(const Offset(0, 30));
      await g2.moveBy(const Offset(0, 30));
      await tester.pump(const Duration(milliseconds: 20));

      await g1.up();
      await g2.up();
      await tester.pump(const Duration(milliseconds: 100));

      final scrollEvents = mockWs.sentEvents.where((e) => e['event'] == 'SCROLL').toList();
      final rightClicks = mockWs.sentEvents.where((e) => e['event'] == 'RIGHT_CLICK').toList();

      expect(scrollEvents.isNotEmpty, isTrue);
      expect(rightClicks.isEmpty, isTrue);
    });

    testWidgets('2-finger horizontal swipe LEFT sends TWO_FINGER_BROWSER_FORWARD and NO RIGHT_CLICK', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TouchpadView(source: touchpadSource),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final center = tester.getCenter(find.text('TOUCHPAD SURFACE'));

      final g1 = await tester.startGesture(center);
      final g2 = await tester.startGesture(center + const Offset(50, 0));
      await tester.pump(const Duration(milliseconds: 20));

      // Swipe Left (-40px)
      await g1.moveBy(const Offset(-40, 0));
      await g2.moveBy(const Offset(-40, 0));
      await tester.pump(const Duration(milliseconds: 20));

      await g1.up();
      await g2.up();
      await tester.pump(const Duration(milliseconds: 100));

      final forwardEvents = mockWs.sentEvents.where((e) => e['event'] == 'TWO_FINGER_BROWSER_FORWARD').toList();
      final rightClicks = mockWs.sentEvents.where((e) => e['event'] == 'RIGHT_CLICK').toList();

      expect(forwardEvents.length, equals(1));
      expect(rightClicks.isEmpty, isTrue);
    });

    testWidgets('2-finger horizontal swipe RIGHT sends TWO_FINGER_BROWSER_BACK and NO RIGHT_CLICK', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TouchpadView(source: touchpadSource),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final center = tester.getCenter(find.text('TOUCHPAD SURFACE'));

      final g1 = await tester.startGesture(center);
      final g2 = await tester.startGesture(center + const Offset(50, 0));
      await tester.pump(const Duration(milliseconds: 20));

      // Swipe Right (+40px)
      await g1.moveBy(const Offset(40, 0));
      await g2.moveBy(const Offset(40, 0));
      await tester.pump(const Duration(milliseconds: 20));

      await g1.up();
      await g2.up();
      await tester.pump(const Duration(milliseconds: 100));

      final backEvents = mockWs.sentEvents.where((e) => e['event'] == 'TWO_FINGER_BROWSER_BACK').toList();
      final rightClicks = mockWs.sentEvents.where((e) => e['event'] == 'RIGHT_CLICK').toList();

      expect(backEvents.length, equals(1));
      expect(rightClicks.isEmpty, isTrue);
    });

    testWidgets('SharedKeyboardPanel sends TEXT_INPUT without duplicate backspaces on single character input', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SharedKeyboardPanel(transport: mockWs),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'Hello World');
      await tester.pumpAndSettle();

      final textInputs = mockWs.sentEvents.where((e) => e['event'] == 'TEXT_INPUT').toList();
      final backspaces = mockWs.sentEvents.where((e) => e['event'] == 'KEY_PRESS' && e['key'] == 'backspace').toList();

      expect(textInputs.isNotEmpty, isTrue);
      expect(backspaces.isEmpty, isTrue);
      expect(textInputs.last['text'], equals('Hello World'));
    });

    testWidgets('MotionView collapses Motion Sensitivity slider when Utility panel opens', (WidgetTester tester) async {
      final motionSource = MotionSource(mockWs);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MotionView(source: motionSource),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Motion Sensitivity slider initially visible
      expect(find.text('Motion Sensitivity'), findsOneWidget);

      // Open Utilities toolbar
      await tester.tap(find.byTooltip('Utilities'));
      await tester.pumpAndSettle();

      // Open Keyboard utility panel
      await tester.tap(find.byTooltip('Keyboard'));
      await tester.pumpAndSettle();

      // Motion Sensitivity slider should now be collapsed/hidden
      expect(find.text('Motion Sensitivity'), findsNothing);

      // Close Utility panel
      await tester.tap(find.byTooltip('Utilities'));
      await tester.pumpAndSettle();

      // Motion Sensitivity slider restored
      expect(find.text('Motion Sensitivity'), findsOneWidget);
    });
  });
}
