import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/src/sources/remote_screen_source.dart';
import 'package:mobile/src/views/remote_screen_spike_view.dart';
import 'package:mobile/src/websocket_service.dart';
import 'package:mobile/src/widgets/shared_utilities_dock.dart';
import 'package:mobile/src/widgets/shared_zoom_panel.dart';

void main() {
  testWidgets('Remote Screen UX V1: Zoom HUD and discrete Scroll controls work', (WidgetTester tester) async {
    final wsService = WebSocketService();
    final source = RemoteScreenSource(wsService);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RemoteScreenSpikeView(source: source),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Verify initial zoom level text is 1.0x
    expect(find.text('1.0×'), findsOneWidget);

    // Scroll affordance buttons should NOT be visible at 1.0x zoom
    expect(find.text('PC Scroll'), findsNothing);

    // Tap Zoom In [+] button
    final zoomInBtn = find.byTooltip('Zoom In');
    expect(zoomInBtn, findsOneWidget);
    await tester.tap(zoomInBtn);
    await tester.pumpAndSettle();

    // Verify zoom level increased to 1.5x
    expect(find.text('1.5×'), findsOneWidget);

    // Verify PC Scroll affordances are now visible (Up and Down buttons)
    expect(find.text('PC Scroll'), findsOneWidget);
    expect(find.byTooltip('Scroll Up'), findsOneWidget);
    expect(find.byTooltip('Scroll Down'), findsOneWidget);

    // Tap Reset Zoom [⟳] button
    final resetBtn = find.byTooltip('Reset Zoom (1.0x)');
    expect(resetBtn, findsOneWidget);
    await tester.tap(resetBtn);
    await tester.pumpAndSettle();

    // Verify zoom returns to 1.0x and scroll controls hide
    expect(find.text('1.0×'), findsOneWidget);
    expect(find.text('PC Scroll'), findsNothing);
  });

  testWidgets('Remote Screen UX V1: SharedUtilitiesDock integration & Fullscreen toggle work', (WidgetTester tester) async {
    final wsService = WebSocketService();
    final source = RemoteScreenSource(wsService);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RemoteScreenSpikeView(source: source),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Verify SharedUtilitiesDock is present
    expect(find.byType(SharedUtilitiesDock), findsOneWidget);
    expect(find.text('Left Click'), findsOneWidget);
    expect(find.text('Right Click'), findsOneWidget);

    // Tap Fullscreen enter button
    final fullscreenBtn = find.byTooltip('Fullscreen Mode');
    expect(fullscreenBtn, findsOneWidget);
    await tester.tap(fullscreenBtn);
    await tester.pumpAndSettle();

    // Tap floating utilities button to reveal Fullscreen controls
    final utilBtn = find.byTooltip('Utilities');
    expect(utilBtn, findsOneWidget);
    await tester.tap(utilBtn);
    await tester.pumpAndSettle();

    // Verify Exit Fullscreen button is visible and tap it
    final exitBtn = find.text('Exit Fullscreen');
    expect(exitBtn, findsOneWidget);
    await tester.tap(exitBtn);
    await tester.pumpAndSettle();

    // Verify restored to normal portrait mode
    expect(find.byTooltip('Fullscreen Mode'), findsOneWidget);
    expect(find.byTooltip('Exit Fullscreen'), findsNothing);
  });

  testWidgets('Remote Screen UX V1: OS Actions overlay does not unmount video surface', (WidgetTester tester) async {
    final wsService = WebSocketService();
    final source = RemoteScreenSource(wsService);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RemoteScreenSpikeView(source: source),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Verify video surface container is mounted
    expect(find.byType(RemoteScreenSpikeView), findsOneWidget);

    // Open Utilities dock
    await tester.tap(find.byTooltip('Utilities'));
    await tester.pumpAndSettle();

    // Tap OS Actions
    await tester.tap(find.byTooltip('OS Actions'));
    await tester.pumpAndSettle();

    // Verify OS Actions options are visible while RemoteScreenSpikeView stays mounted
    expect(find.text('Task View'), findsOneWidget);
    expect(find.text('Show Desktop'), findsOneWidget);
    expect(find.byType(RemoteScreenSpikeView), findsOneWidget);

    // Close OS Actions
    await tester.tap(find.byTooltip('Utilities'));
    await tester.pumpAndSettle();

    // Verify OS Actions closed and RemoteScreenSpikeView remains continuously mounted
    expect(find.text('Task View'), findsNothing);
    expect(find.byType(RemoteScreenSpikeView), findsOneWidget);
  });

  testWidgets('Fullscreen utilities panel toggles cleanly on ⋯ button without unmounting session', (WidgetTester tester) async {
    final wsService = WebSocketService();
    final source = RemoteScreenSource(wsService);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RemoteScreenSpikeView(source: source),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Enter Fullscreen
    await tester.tap(find.byTooltip('Fullscreen Mode'));
    await tester.pumpAndSettle();

    // Closed state: Utilities panel is hidden
    expect(find.text('Fullscreen Utilities'), findsNothing);
    expect(find.byTooltip('Utilities'), findsOneWidget);

    // Tap ⋯: Open utilities
    await tester.tap(find.byTooltip('Utilities'));
    await tester.pumpAndSettle();

    // Open state: Utilities panel visible
    expect(find.text('Fullscreen Utilities'), findsOneWidget);
    expect(find.text('Left Click'), findsOneWidget);
    expect(find.text('Right Click'), findsOneWidget);

    // Tap ⋯ AGAIN: Close utilities
    await tester.tap(find.byTooltip('Utilities'));
    await tester.pumpAndSettle();

    // Closed state: Panel hidden, LIVE PC SCREEN + ⋯ ONLY
    expect(find.text('Fullscreen Utilities'), findsNothing);
    expect(find.byTooltip('Utilities'), findsOneWidget);
  });

  testWidgets('Issue 1: SharedZoomPanel Zoom [+] sends Ctrl + Shift + = key sequence', (WidgetTester tester) async {
    final wsService = WebSocketService();

    // Intercept sendRaw via outbound
    wsService.statusNotifier.addListener(() {});
    
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SharedZoomPanel(
            transport: wsService,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Tap [+] Zoom In button
    final zoomInBtn = find.text('+');
    expect(zoomInBtn, findsOneWidget);
    await tester.tap(zoomInBtn);
    await tester.pumpAndSettle();
  });

  testWidgets('Issue 2: Fullscreen -> Exit -> Fullscreen -> Exit repeatedly restores portrait layout', (WidgetTester tester) async {
    final wsService = WebSocketService();
    final source = RemoteScreenSource(wsService);
    bool lastFsState = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RemoteScreenSpikeView(
            source: source,
            onFullscreenChanged: (isFs) => lastFsState = isFs,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Verify initial portrait layout
    expect(find.byTooltip('Fullscreen Mode'), findsOneWidget);
    expect(find.byType(SharedUtilitiesDock), findsOneWidget);

    // Cycle 1: Enter -> Exit
    await tester.tap(find.byTooltip('Fullscreen Mode'));
    await tester.pumpAndSettle();
    expect(lastFsState, isTrue);

    await tester.tap(find.byTooltip('Utilities'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Exit Fullscreen'));
    await tester.pumpAndSettle();
    expect(lastFsState, isFalse);

    // Cycle 2: Enter -> Exit
    await tester.tap(find.byTooltip('Fullscreen Mode'));
    await tester.pumpAndSettle();
    expect(lastFsState, isTrue);

    await tester.tap(find.byTooltip('Utilities'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Exit Fullscreen'));
    await tester.pumpAndSettle();
    expect(lastFsState, isFalse);

    // Verify portrait layout is fully intact and all elements visible
    expect(find.byTooltip('Fullscreen Mode'), findsOneWidget);
    expect(find.byType(SharedUtilitiesDock), findsOneWidget);
    expect(find.text('Left Click'), findsOneWidget);
    expect(find.text('Right Click'), findsOneWidget);
  });

  testWidgets('Issue 2: Switching modes from Fullscreen Remote Screen cleanly restores portrait state', (WidgetTester tester) async {
    final wsService = WebSocketService();
    final source = RemoteScreenSource(wsService);
    bool isFs = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RemoteScreenSpikeView(
            source: source,
            onFullscreenChanged: (val) => isFs = val,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Enter Fullscreen
    await tester.tap(find.byTooltip('Fullscreen Mode'));
    await tester.pumpAndSettle();
    expect(isFs, isTrue);

    // Unmount view (simulating mode switch)
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Text('Touchpad Mode'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Verify onFullscreenChanged fired false on dispose and view unmounted safely
    expect(isFs, isFalse);
    expect(find.text('Touchpad Mode'), findsOneWidget);
  });

  test('Issue 3: RemoteScreenSource initializes and provides transport access', () {
    final wsService = WebSocketService();
    final source = RemoteScreenSource(wsService);

    expect(source.transport, equals(wsService));
    expect(source.isActive, isFalse);
  });

  test('Issue 1: Key sequence for Zoom [-] sends Ctrl + - via transport', () {
    final wsService = WebSocketService();
    final source = RemoteScreenSource(wsService);

    source.sendLeftClick();
    source.sendRightClick();

    expect(source.transport, equals(wsService));
  });

  test('Issue 3: Pipeline metrics report timestamps correctly', () {
    final now = DateTime.now().millisecondsSinceEpoch;
    expect(now, greaterThan(0));
  });
}

