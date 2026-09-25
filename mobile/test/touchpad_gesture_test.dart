import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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

  group('Touchpad Gesture State Machine & Keyboard Tests', () {
    late MockWebSocketService mockWsService;
    late TouchpadSource source;

    setUp(() {
      mockWsService = MockWebSocketService();
      source = TouchpadSource(mockWsService);
      source.activate();
    });

    testWidgets('Single-finger move > 8px emits MOVE only and NO left click on release', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TouchpadView(source: source),
          ),
        ),
      );

      final surface = find.text('TOUCHPAD SURFACE');
      final center = tester.getCenter(surface);

      final g = await tester.startGesture(center);
      await tester.pump(const Duration(milliseconds: 20));

      // Move finger 20px (exceeds 8px threshold)
      await g.moveBy(const Offset(20, 0));
      await tester.pump(const Duration(milliseconds: 20));

      await g.up();
      // Wait past the 250ms tap timer duration
      await tester.pump(const Duration(milliseconds: 300));

      final moveEvents = mockWsService.sentEvents.where((e) => e['event'] == 'MOVE').toList();
      final clickEvents = mockWsService.sentEvents.where((e) => e['event'] == 'LEFT_CLICK').toList();

      expect(moveEvents.isNotEmpty, isTrue);
      expect(clickEvents.isEmpty, isTrue); // Zero LEFT_CLICK on move release
    });

    testWidgets('Stationary two-finger tap emits RIGHT_CLICK when both pointers release', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TouchpadView(source: source),
          ),
        ),
      );

      final surface = find.text('TOUCHPAD SURFACE');
      final center = tester.getCenter(surface);

      final g1 = await tester.startGesture(center);
      final g2 = await tester.startGesture(center + const Offset(30, 0));
      await tester.pump(const Duration(milliseconds: 50));

      // Release finger 1 first, then finger 2
      await g1.up();
      await tester.pump(const Duration(milliseconds: 20));
      await g2.up();
      await tester.pumpAndSettle();

      final rightClicks = mockWsService.sentEvents.where((e) => e['event'] == 'RIGHT_CLICK').toList();
      final leftClicks = mockWsService.sentEvents.where((e) => e['event'] == 'LEFT_CLICK').toList();

      expect(rightClicks.length, equals(1));
      expect(leftClicks.isEmpty, isTrue);
    });

    testWidgets('Two-finger scroll > 8px emits SCROLL only and NO clicks on release', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TouchpadView(source: source),
          ),
        ),
      );

      final surface = find.text('TOUCHPAD SURFACE');
      final center = tester.getCenter(surface);

      final g1 = await tester.startGesture(center);
      final g2 = await tester.startGesture(center + const Offset(30, 0));
      await tester.pump(const Duration(milliseconds: 20));

      // Scroll 30px down (exceeds 8px touch-slop)
      await g1.moveBy(const Offset(0, 30));
      await g2.moveBy(const Offset(0, 30));
      await tester.pump(const Duration(milliseconds: 20));

      // Release finger 1 then finger 2
      await g1.up();
      await tester.pump(const Duration(milliseconds: 20));
      await g2.up();
      await tester.pump(const Duration(milliseconds: 300));

      final scrollEvents = mockWsService.sentEvents.where((e) => e['event'] == 'SCROLL').toList();
      final rightClicks = mockWsService.sentEvents.where((e) => e['event'] == 'RIGHT_CLICK').toList();
      final leftClicks = mockWsService.sentEvents.where((e) => e['event'] == 'LEFT_CLICK').toList();
      final doubleClicks = mockWsService.sentEvents.where((e) => e['event'] == 'DOUBLE_CLICK').toList();

      expect(scrollEvents.isNotEmpty, isTrue);
      expect(rightClicks.isEmpty, isTrue);
      expect(leftClicks.isEmpty, isTrue);
      expect(doubleClicks.isEmpty, isTrue);
    });

    testWidgets('Double-tap-and-drag emits BUTTON_DOWN(left), MOVE, BUTTON_UP(left) and no double click', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TouchpadView(source: source),
          ),
        ),
      );

      final surface = find.text('TOUCHPAD SURFACE');
      final center = tester.getCenter(surface);

      // Tap 1
      await tester.tapAt(center);
      await tester.pump(const Duration(milliseconds: 50));

      // Tap 2 & Hold & Drag 40px
      final g = await tester.startGesture(center);
      await tester.pump(const Duration(milliseconds: 50));
      await g.moveBy(const Offset(40, 0));
      await tester.pump(const Duration(milliseconds: 50));
      await g.up();
      await tester.pumpAndSettle();

      final buttonDowns = mockWsService.sentEvents.where((e) => e['event'] == 'BUTTON_DOWN').toList();
      final buttonUps = mockWsService.sentEvents.where((e) => e['event'] == 'BUTTON_UP').toList();
      final doubleClicks = mockWsService.sentEvents.where((e) => e['event'] == 'DOUBLE_CLICK').toList();

      expect(buttonDowns.isNotEmpty, isTrue);
      expect(buttonUps.isNotEmpty, isTrue);
      expect(doubleClicks.isEmpty, isTrue);
    });

    testWidgets('Soft keyboard Backspace emits KEY_PRESS backspace', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TouchpadView(source: source),
          ),
        ),
      );

      // Open soft keyboard UI via Utilities button
      await tester.tap(find.byTooltip('Utilities'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Keyboard'));
      await tester.pumpAndSettle();

      // Enter text and then delete a character
      await tester.enterText(find.byType(TextField), 'ab');
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'a');
      await tester.pumpAndSettle();

      final backspaceEvents = mockWsService.sentEvents
          .where((e) => e['event'] == 'KEY_PRESS' && e['key'] == 'backspace')
          .toList();

      expect(backspaceEvents.isNotEmpty, isTrue);
    });

    testWidgets('Soft keyboard blue action key inserts newline via TEXT_INPUT and does NOT generate KEY_PRESS ENTER', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TouchpadView(source: source),
          ),
        ),
      );

      // Open soft keyboard UI via Utilities button
      await tester.tap(find.byTooltip('Utilities'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Keyboard'));
      await tester.pumpAndSettle();

      mockWsService.sentEvents.clear();

      // Enter newline text in TextField (simulating phone blue action key)
      final textFieldFinder = find.byType(TextField);
      expect(textFieldFinder, findsOneWidget);

      await tester.enterText(textFieldFinder, '\n');
      await tester.pumpAndSettle();

      final textEvents = mockWsService.sentEvents.where((e) => e['event'] == 'TEXT_INPUT').toList();
      final enterKeyPresses = mockWsService.sentEvents
          .where((e) => e['event'] == 'KEY_PRESS' && e['key'] == 'enter')
          .toList();

      expect(textEvents.isNotEmpty, isTrue);
      expect(textEvents.first['text'], equals('\n'));
      expect(enterKeyPresses.isEmpty, isTrue); // NO KEY_PRESS enter generated by blue action key
      expect(find.byType(TextField), findsOneWidget); // Keyboard panel remains open
    });
  });
}
