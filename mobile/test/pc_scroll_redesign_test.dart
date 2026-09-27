import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/src/mouse_mode_manager.dart';
import 'package:mobile/src/sources/remote_screen_source.dart';
import 'package:mobile/src/sources/touchpad_source.dart';
import 'package:mobile/src/transports/pouse_transport.dart';
import 'package:mobile/src/views/remote_screen_spike_view.dart';
import 'package:mobile/src/websocket_service.dart';

class MockTransport implements PouseTransport {
  final List<String> events = [];
  final List<String> keyEvents = [];
  final Set<String> heldKeys = {};

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
  void sendMove(double dx, double dy) {}

  @override
  void sendAbsMove(double x, double y) {}

  @override
  void sendLeftClick() {}

  @override
  void sendRightClick() {}

  @override
  void sendDoubleClick() {}

  @override
  void sendButtonDown([String button = 'left']) {}

  @override
  void sendButtonUp([String button = 'left']) {}

  @override
  void sendScroll(double dx, double dy) {
    events.add('SCROLL:$dx,$dy');
  }

  @override
  void sendTextInput(String text) {}

  @override
  void sendKeyPress(String key) {
    keyEvents.add('PRESS:$key');
  }

  @override
  void sendKeyDown(String key) {
    keyEvents.add('DOWN:$key');
    heldKeys.add(key);
  }

  @override
  void sendKeyUp(String key) {
    keyEvents.add('UP:$key');
    heldKeys.remove(key);
  }

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
  void sendSystemMagnify(double scale) {}

  @override
  void releaseAll() {
    for (final k in heldKeys.toList()) {
      keyEvents.add('UP:$k');
    }
    heldKeys.clear();
  }
}

void main() {
  group('PART A & F — Zoomed PC Scroll & Safety Release Tests', () {
    testWidgets('Short tap ArrowUp sends KEY_DOWN and KEY_UP for ArrowUp', (WidgetTester tester) async {
      final mockTransport = MockTransport();
      final source = RemoteScreenSource(mockTransport);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RemoteScreenSpikeView(source: source),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Zoom in to reveal PC Scroll arrow buttons
      await tester.tap(find.byTooltip('Zoom In'));
      await tester.pumpAndSettle();

      final scrollUpBtn = find.byTooltip('Scroll Up');
      expect(scrollUpBtn, findsOneWidget);

      // Perform a tap on Scroll Up
      await tester.tap(scrollUpBtn);
      await tester.pumpAndSettle();

      expect(mockTransport.keyEvents, contains('DOWN:ArrowUp'));
      expect(mockTransport.keyEvents, contains('UP:ArrowUp'));
      expect(mockTransport.events.where((e) => e.startsWith('SCROLL')), isEmpty);
    });

    testWidgets('Short tap ArrowDown sends KEY_DOWN and KEY_UP for ArrowDown', (WidgetTester tester) async {
      final mockTransport = MockTransport();
      final source = RemoteScreenSource(mockTransport);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RemoteScreenSpikeView(source: source),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Zoom in to reveal PC Scroll arrow buttons
      await tester.tap(find.byTooltip('Zoom In'));
      await tester.pumpAndSettle();

      final scrollDownBtn = find.byTooltip('Scroll Down');
      expect(scrollDownBtn, findsOneWidget);

      // Perform a tap on Scroll Down
      await tester.tap(scrollDownBtn);
      await tester.pumpAndSettle();

      expect(mockTransport.keyEvents, contains('DOWN:ArrowDown'));
      expect(mockTransport.keyEvents, contains('UP:ArrowDown'));
      expect(mockTransport.events.where((e) => e.startsWith('SCROLL')), isEmpty);
    });

    testWidgets('Hold ArrowUp sends KEY_DOWN on press and KEY_UP on release without scroll deltas', (WidgetTester tester) async {
      final mockTransport = MockTransport();
      final source = RemoteScreenSource(mockTransport);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RemoteScreenSpikeView(source: source),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Zoom In'));
      await tester.pumpAndSettle();

      final scrollUpBtn = find.byTooltip('Scroll Up');

      // Press and hold for 1 second
      final gesture = await tester.startGesture(tester.getCenter(scrollUpBtn));
      await tester.pump(const Duration(milliseconds: 500));

      expect(mockTransport.keyEvents, contains('DOWN:ArrowUp'));
      expect(mockTransport.keyEvents.contains('UP:ArrowUp'), isFalse);
      expect(mockTransport.events.where((e) => e.startsWith('SCROLL')), isEmpty);

      // Release finger
      await gesture.up();
      await tester.pumpAndSettle();

      expect(mockTransport.keyEvents, contains('UP:ArrowUp'));
    });

    testWidgets('Mode switch safely releases held arrow key', (WidgetTester tester) async {
      final mockTransport = MockTransport();
      final remoteSource = RemoteScreenSource(mockTransport);
      final touchpadSource = TouchpadSource(mockTransport);
      final manager = MouseModeManager();

      manager.registerSource(remoteSource);
      manager.registerSource(touchpadSource);
      manager.selectMode(MouseMode.remoteScreen);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RemoteScreenSpikeView(source: remoteSource),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Zoom In'));
      await tester.pumpAndSettle();

      final scrollUpBtn = find.byTooltip('Scroll Up');
      await tester.startGesture(tester.getCenter(scrollUpBtn));
      await tester.pump(const Duration(milliseconds: 200));

      expect(mockTransport.keyEvents, contains('DOWN:ArrowUp'));

      // Deactivate Remote Screen source (simulates mode switch)
      manager.selectMode(MouseMode.touchpad);
      await tester.pumpAndSettle();

      expect(mockTransport.keyEvents, contains('UP:ArrowUp'));
      expect(mockTransport.heldKeys, isEmpty);
    });

    testWidgets('Fullscreen transition safely releases held arrow key', (WidgetTester tester) async {
      final mockTransport = MockTransport();
      final source = RemoteScreenSource(mockTransport);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RemoteScreenSpikeView(source: source),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Zoom In'));
      await tester.pumpAndSettle();

      final scrollUpBtn = find.byTooltip('Scroll Up');
      await tester.startGesture(tester.getCenter(scrollUpBtn));
      await tester.pump(const Duration(milliseconds: 200));

      expect(mockTransport.keyEvents, contains('DOWN:ArrowUp'));

      // Enter fullscreen while key held
      await tester.tap(find.byTooltip('Fullscreen Mode'));
      await tester.pumpAndSettle();

      expect(mockTransport.keyEvents, contains('UP:ArrowUp'));
    });

    testWidgets('Widget disposal safely releases held arrow key', (WidgetTester tester) async {
      final mockTransport = MockTransport();
      final source = RemoteScreenSource(mockTransport);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RemoteScreenSpikeView(source: source),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Zoom In'));
      await tester.pumpAndSettle();

      final scrollUpBtn = find.byTooltip('Scroll Up');
      await tester.startGesture(tester.getCenter(scrollUpBtn));
      await tester.pump(const Duration(milliseconds: 200));

      expect(mockTransport.keyEvents, contains('DOWN:ArrowUp'));

      // Replace widget subtree to trigger dispose
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Text('Unmounted'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(mockTransport.keyEvents, contains('UP:ArrowUp'));
    });
  });
}
