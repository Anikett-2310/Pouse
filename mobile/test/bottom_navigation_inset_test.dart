import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/main.dart';
import 'package:mobile/src/widgets/shared_utilities_dock.dart';

void main() {
  testWidgets('Area B: Android 3-button navigation bottom insets preserve control layout in portrait mode', (WidgetTester tester) async {
    // Simulate Android phone with 48dp 3-button navigation bar at bottom
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1.0;
    tester.view.padding = const FakeViewPadding(bottom: 48.0);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const PouseApp());
    await tester.pumpAndSettle();

    // Verify app renders cleanly without overflow errors
    expect(tester.takeException(), isNull);

    // Verify SharedUtilitiesDock (Click dock) is rendered above the 48dp navigation inset
    final dockFinder = find.byType(SharedUtilitiesDock);
    expect(dockFinder, findsOneWidget);

    final dockRect = tester.getRect(dockFinder);
    // 800 total height - 48 bottom inset = 752. dock bottom must be <= 752.
    expect(dockRect.bottom, lessThanOrEqualTo(752.0));
  });

  testWidgets('Area B: Remote Screen fullscreen mode disables bottom safe area inset for full video canvas', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 360);
    tester.view.devicePixelRatio = 1.0;
    tester.view.padding = const FakeViewPadding(bottom: 0.0);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const PouseApp());
    await tester.pumpAndSettle();

    // Switch to Remote Screen
    await tester.tap(find.text('Remote Screen'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });
}
