import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/main.dart';
import 'package:mobile/src/views/motion_view.dart';
import 'package:mobile/src/views/remote_screen_spike_view.dart';
import 'package:mobile/src/views/touchpad_view.dart';
import 'package:mobile/src/views/touchless_view.dart';

void main() {
  testWidgets('MainScreen renders persistent Connection Bar and Mode Selector Header', (WidgetTester tester) async {
    await tester.pumpWidget(const PouseApp());

    // Verify Title & AppBar
    expect(find.textContaining('Pouse — Touchpad'), findsOneWidget);

    // Verify all 4 mouse modes are rendered in Mode Selector Header
    expect(find.text('Touchpad'), findsOneWidget);
    expect(find.text('Motion'), findsOneWidget);
    expect(find.text('Remote Screen'), findsOneWidget);
    expect(find.text('Touchless'), findsOneWidget);

    // Verify active TouchpadView is rendered by default
    expect(find.byType(TouchpadView), findsOneWidget);
  });

  testWidgets('Four mode buttons fit cleanly on narrow portrait screen without overflow', (WidgetTester tester) async {
    // Set typical narrow portrait phone physical size (360 x 800)
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(const PouseApp());
    await tester.pumpAndSettle();

    // Verify no overflow errors occurred
    expect(tester.takeException(), isNull);
    expect(find.text('Touchpad'), findsOneWidget);
    expect(find.text('Motion'), findsOneWidget);
    expect(find.text('Remote Screen'), findsOneWidget);
    expect(find.text('Touchless'), findsOneWidget);
  });

  testWidgets('Switching between Touchpad, Motion, Remote Screen, and Touchless modes updates view and title', (WidgetTester tester) async {
    await tester.pumpWidget(const PouseApp());

    // Initially in Touchpad mode
    expect(find.byType(TouchpadView), findsOneWidget);

    // Tap Motion mode chip
    await tester.tap(find.text('Motion'));
    await tester.pumpAndSettle();

    // Verify view switches to MotionView and app bar updates
    expect(find.byType(MotionView), findsOneWidget);
    expect(find.byType(TouchpadView), findsNothing);
    expect(find.textContaining('Pouse — Motion'), findsOneWidget);

    // Tap Remote Screen mode chip
    await tester.tap(find.text('Remote Screen'));
    await tester.pumpAndSettle();

    // Verify view switches to RemoteScreenSpikeView and app bar updates
    expect(find.byType(RemoteScreenSpikeView), findsOneWidget);
    expect(find.textContaining('Pouse — Remote Screen'), findsOneWidget);

    // Tap Touchless mode chip
    await tester.tap(find.text('Touchless'));
    await tester.pumpAndSettle();

    // Verify view switches to TouchlessView and app bar updates
    expect(find.byType(TouchlessView), findsOneWidget);
    expect(find.textContaining('Pouse — Touchless'), findsOneWidget);

    // Tap Touchpad mode chip
    await tester.tap(find.text('Touchpad'));
    await tester.pumpAndSettle();

    // Verify view switches back to TouchpadView
    expect(find.byType(TouchpadView), findsOneWidget);
    expect(find.textContaining('Pouse — Touchpad'), findsOneWidget);
  });

  testWidgets('Remote Screen renders production UI and contains NO legacy spike/debug controls', (WidgetTester tester) async {
    await tester.pumpWidget(const PouseApp());

    // Switch to Remote Screen
    await tester.tap(find.text('Remote Screen'));
    await tester.pumpAndSettle();

    // Verify Production Remote Screen View is rendered
    expect(find.byType(RemoteScreenSpikeView), findsOneWidget);
    expect(find.textContaining('Remote Screen'), findsWidgets);

    // Verify NO debug / spike controls exist in production UI
    expect(find.textContaining('Spike 3'), findsNothing);
    expect(find.text('PC Host IP'), findsNothing);
    expect(find.text('Connect Video & Control'), findsNothing);
    expect(find.text('Force IDR'), findsNothing);
    expect(find.text('Reset Decoder'), findsNothing);
    expect(find.textContaining('WS RX FPS'), findsNothing);
    expect(find.textContaining('ABS_MOVE Target'), findsNothing);
  });
}
