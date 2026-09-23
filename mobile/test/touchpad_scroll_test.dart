import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mobile/src/sources/touchpad_source.dart';
import 'package:mobile/src/views/touchpad_view.dart';
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

  group('Touchpad Scroll & Persistence Tests', () {
    late MockWebSocketService mockWsService;
    late TouchpadSource source;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      mockWsService = MockWebSocketService();
      source = TouchpadSource(mockWsService);
      source.activate();
    });

    testWidgets('Scroll controls load defaults and update scroll events correctly', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TouchpadView(source: source),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify default controls visible: Scroll label, 1.0x for scroll, Natural toggle
      expect(find.text('Scroll'), findsOneWidget);
      expect(find.text('1.0x'), findsOneWidget); // Scroll sensitivity 1.0x
      expect(find.text('Natural'), findsOneWidget);

      final surface = find.text('TOUCHPAD SURFACE');
      final center = tester.getCenter(surface);

      // Perform 2-finger scroll gesture (downwards dy = +40, dx = +20)
      final g1 = await tester.startGesture(center);
      final g2 = await tester.startGesture(center + const Offset(20, 0));
      await tester.pump(const Duration(milliseconds: 20));

      await g1.moveBy(const Offset(20, 40));
      await g2.moveBy(const Offset(20, 40));
      await tester.pump(const Duration(milliseconds: 20));

      await g1.up();
      await g2.up();
      await tester.pumpAndSettle();

      final scrollEvents = mockWsService.sentEvents.where((e) => e['event'] == 'SCROLL').toList();
      expect(scrollEvents.isNotEmpty, isTrue);

      final firstScroll = scrollEvents.first;
      // Default: Natural (1.0 dir), Sensitivity 1.0, Base 0.5
      // dy = 40 * 0.5 * 1.0 * 1.0 = 20.0
      // dx = 20 * 0.5 * 1.0 * 1.0 = 10.0
      expect(firstScroll['dx'], equals(10.0));
      expect(firstScroll['dy'], equals(20.0));
    });

    testWidgets('Toggling Natural to Reverse inverts scroll direction and persists setting', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TouchpadView(source: source),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Tap Natural toggle button to change to Reverse
      await tester.tap(find.text('Natural'));
      await tester.pumpAndSettle();

      expect(find.text('Reverse'), findsOneWidget);

      final surface = find.text('TOUCHPAD SURFACE');
      final center = tester.getCenter(surface);

      mockWsService.sentEvents.clear();

      // Perform 2-finger scroll gesture (dy = +40, dx = +20)
      final g1 = await tester.startGesture(center);
      final g2 = await tester.startGesture(center + const Offset(20, 0));
      await tester.pump(const Duration(milliseconds: 20));

      await g1.moveBy(const Offset(20, 40));
      await g2.moveBy(const Offset(20, 40));
      await tester.pump(const Duration(milliseconds: 20));

      await g1.up();
      await g2.up();
      await tester.pumpAndSettle();

      final scrollEvents = mockWsService.sentEvents.where((e) => e['event'] == 'SCROLL').toList();
      expect(scrollEvents.isNotEmpty, isTrue);

      final firstScroll = scrollEvents.first;
      // Reverse (-1.0 dir), Sensitivity 1.0, Base 0.5
      // dy = 40 * 0.5 * 1.0 * (-1.0) = -20.0
      // dx = 20 * 0.5 * 1.0 * (-1.0) = -10.0
      expect(firstScroll['dx'], equals(-10.0));
      expect(firstScroll['dy'], equals(-20.0));

      // Verify persistence in SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('pouse_scroll_natural'), isFalse);
    });
  });
}
