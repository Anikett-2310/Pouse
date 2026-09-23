import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/main.dart';
import 'package:mobile/src/views/motion_view.dart';
import 'package:mobile/src/views/touchpad_view.dart';

void main() {
  testWidgets('MainScreen renders persistent Connection Bar and Mode Selector Header', (WidgetTester tester) async {
    await tester.pumpWidget(const PouseApp());

    // Verify Title & AppBar
    expect(find.textContaining('Pouse — Touchpad'), findsOneWidget);

    // Verify all four mouse modes are rendered in Mode Selector Header
    expect(find.text('Touchpad'), findsOneWidget);
    expect(find.text('Motion'), findsOneWidget);
    expect(find.text('Optical'), findsOneWidget);
    expect(find.text('Touchless'), findsOneWidget);

    // Verify disabled version badges for V3 & V4
    expect(find.text('V3'), findsOneWidget);
    expect(find.text('V4'), findsOneWidget);

    // Verify active TouchpadView is rendered by default
    expect(find.byType(TouchpadView), findsOneWidget);
  });

  testWidgets('Switching between Touchpad and Motion modes updates view and title', (WidgetTester tester) async {
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

    // Tap Touchpad mode chip
    await tester.tap(find.text('Touchpad'));
    await tester.pumpAndSettle();

    // Verify view switches back to TouchpadView
    expect(find.byType(TouchpadView), findsOneWidget);
    expect(find.byType(MotionView), findsNothing);
    expect(find.textContaining('Pouse — Touchpad'), findsOneWidget);
  });

  testWidgets('Tapping disabled future mode chips displays coming soon feedback', (WidgetTester tester) async {
    await tester.pumpWidget(const PouseApp());

    // Tap Optical mode (V3)
    await tester.tap(find.text('Optical'));
    await tester.pumpAndSettle();

    // Verify SnackBar feedback
    expect(find.text('Optical mode is coming in V3'), findsOneWidget);
    expect(find.byType(TouchpadView), findsOneWidget);

    // Tap Touchless mode (V4)
    await tester.tap(find.text('Touchless'));
    await tester.pumpAndSettle();

    // Verify SnackBar feedback
    expect(find.text('Touchless mode is coming in V4'), findsOneWidget);
  });
}
