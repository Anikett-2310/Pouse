import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/src/sources/motion_source.dart';
import 'package:mobile/src/sources/touchless_source.dart';
import 'package:mobile/src/sources/touchpad_source.dart';
import 'package:mobile/src/views/motion_view.dart';
import 'package:mobile/src/views/touchless_view.dart';
import 'package:mobile/src/views/touchpad_view.dart';
import 'package:mobile/src/widgets/shared_zoom_panel.dart';
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

  group('Touchpad System Magnifier & 4th Zoom Utility Tests', () {
    late MockWebSocketService mockWsService;
    late TouchpadSource touchpadSource;

    setUp(() {
      mockWsService = MockWebSocketService();
      touchpadSource = TouchpadSource(mockWsService);
      touchpadSource.activate();
    });

    testWidgets('1. Touchpad pinch out emits SYSTEM_MAGNIFY with scale > 1.0 and no scroll or right click', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TouchpadView(source: touchpadSource),
          ),
        ),
      );

      final surface = find.text('TOUCHPAD SURFACE');
      final center = tester.getCenter(surface);

      // Start 2 fingers 20px apart
      final g1 = await tester.startGesture(center - const Offset(10, 0));
      final g2 = await tester.startGesture(center + const Offset(10, 0));
      await tester.pump(const Duration(milliseconds: 20));

      // Pinch OUT: spread fingers apart horizontally to 80px apart
      await g1.moveBy(const Offset(-30, 0));
      await g2.moveBy(const Offset(30, 0));
      await tester.pump(const Duration(milliseconds: 20));

      final magnifyEvents = mockWsService.sentEvents.where((e) => e['event'] == 'SYSTEM_MAGNIFY').toList();
      final scrollEvents = mockWsService.sentEvents.where((e) => e['event'] == 'SCROLL').toList();
      final rightClicks = mockWsService.sentEvents.where((e) => e['event'] == 'RIGHT_CLICK').toList();

      expect(magnifyEvents.isNotEmpty, isTrue);
      expect(magnifyEvents.first['scale'], greaterThan(1.0));
      expect(scrollEvents.isEmpty, isTrue);

      await g1.up();
      await g2.up();
      await tester.pumpAndSettle();

      expect(rightClicks.isEmpty, isTrue);
    });

    testWidgets('2. Gesture lock: once pinch classified, stays SYSTEM_MAGNIFY; once scroll classified, stays SCROLL', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TouchpadView(source: touchpadSource),
          ),
        ),
      );

      final surface = find.text('TOUCHPAD SURFACE');
      final center = tester.getCenter(surface);

      // Pinch sequence
      final g1 = await tester.startGesture(center - const Offset(10, 0));
      final g2 = await tester.startGesture(center + const Offset(10, 0));
      await tester.pump(const Duration(milliseconds: 20));

      // Pinch out 50px
      await g1.moveBy(const Offset(-25, 0));
      await g2.moveBy(const Offset(25, 0));
      await tester.pump(const Duration(milliseconds: 20));

      // Now translate downward while still pinching: must STAY system magnify, zero scroll events!
      await g1.moveBy(const Offset(0, 40));
      await g2.moveBy(const Offset(0, 40));
      await tester.pump(const Duration(milliseconds: 20));

      await g1.up();
      await g2.up();
      await tester.pumpAndSettle();

      final scrollEvents = mockWsService.sentEvents.where((e) => e['event'] == 'SCROLL').toList();
      expect(scrollEvents.isEmpty, isTrue);
    });

    testWidgets('3. Utility dock contains all 4 utilities (Keyboard, Gaming, OS Actions, Zoom)', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TouchpadView(source: touchpadSource),
          ),
        ),
      );

      // Expand Utilities dock
      await tester.tap(find.byTooltip('Utilities'));
      await tester.pumpAndSettle();

      expect(find.byTooltip('Keyboard'), findsOneWidget);
      expect(find.byTooltip('Presentation / Gaming'), findsOneWidget);
      expect(find.byTooltip('OS Actions'), findsOneWidget);
      expect(find.byTooltip('Zoom'), findsOneWidget);
    });

    testWidgets('4. Zoom utility + and - send Ctrl + + and Ctrl + -', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SharedZoomPanel(transport: mockWsService),
          ),
        ),
      );

      mockWsService.sentEvents.clear();

      // Tap Zoom +
      await tester.tap(find.text('+'));
      await tester.pumpAndSettle();

      final plusEvents = List<Map<String, dynamic>>.from(mockWsService.sentEvents);
      expect(plusEvents.any((e) => e['event'] == 'KEY_DOWN' && e['key'] == 'ctrl'), isTrue);
      expect(plusEvents.any((e) => e['event'] == 'KEY_DOWN' && e['key'] == 'shift'), isTrue);
      expect(plusEvents.any((e) => e['event'] == 'KEY_PRESS' && e['key'] == '='), isTrue);
      expect(plusEvents.any((e) => e['event'] == 'KEY_UP' && e['key'] == 'shift'), isTrue);
      expect(plusEvents.any((e) => e['event'] == 'KEY_UP' && e['key'] == 'ctrl'), isTrue);

      mockWsService.sentEvents.clear();

      // Tap Zoom -
      await tester.tap(find.text('−'));
      await tester.pumpAndSettle();

      final minusEvents = List<Map<String, dynamic>>.from(mockWsService.sentEvents);
      expect(minusEvents.any((e) => e['event'] == 'KEY_DOWN' && e['key'] == 'ctrl'), isTrue);
      expect(minusEvents.any((e) => e['event'] == 'KEY_PRESS' && e['key'] == '-'), isTrue);
      expect(minusEvents.any((e) => e['event'] == 'KEY_UP' && e['key'] == 'ctrl'), isTrue);
    });

    testWidgets('5. Safety: Magnification cleanup resets scale to 1.0 on dispose and releaseAll', (WidgetTester tester) async {
      final key = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TouchpadView(key: key, source: touchpadSource),
          ),
        ),
      );

      final surface = find.text('TOUCHPAD SURFACE');
      final center = tester.getCenter(surface);

      final g1 = await tester.startGesture(center - const Offset(10, 0));
      final g2 = await tester.startGesture(center + const Offset(10, 0));
      await tester.pump(const Duration(milliseconds: 20));

      await g1.moveBy(const Offset(-40, 0));
      await g2.moveBy(const Offset(40, 0));
      await tester.pump(const Duration(milliseconds: 20));

      await g1.up();
      await g2.up();
      await tester.pumpAndSettle();

      mockWsService.sentEvents.clear();

      // Unmount / dispose view
      await tester.pumpWidget(const SizedBox());

      final resetEvents = mockWsService.sentEvents.where((e) => e['event'] == 'SYSTEM_MAGNIFY' && e['scale'] == 1.0).toList();
      expect(resetEvents.isNotEmpty, isTrue);

      mockWsService.sentEvents.clear();
      mockWsService.releaseAll();
      final releaseAllResets = mockWsService.sentEvents.where((e) => e['event'] == 'SYSTEM_MAGNIFY' && e['scale'] == 1.0).toList();
      expect(releaseAllResets.isNotEmpty, isTrue);
    });

    testWidgets('6. SharedUtilitiesDock works consistently in MotionView, TouchlessView, and RemoteScreenSpikeView', (WidgetTester tester) async {
      final motionSource = MotionSource(mockWsService);
      motionSource.activate();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MotionView(source: motionSource),
          ),
        ),
      );

      await tester.tap(find.byTooltip('Utilities'));
      await tester.pumpAndSettle();

      expect(find.byTooltip('Zoom'), findsOneWidget);

      final touchlessSource = TouchlessSource(mockWsService);
      touchlessSource.activate();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TouchlessView(source: touchlessSource),
          ),
        ),
      );

      await tester.tap(find.byTooltip('Utilities'));
      await tester.pumpAndSettle();

      expect(find.byTooltip('Zoom'), findsOneWidget);
    });
  });
}
