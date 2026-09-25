import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/main.dart';
import 'package:mobile/src/views/motion_view.dart';
import 'package:mobile/src/views/touchpad_view.dart';
import 'package:mobile/src/views/touchless_view.dart';

void main() {
  testWidgets('MainScreen renders persistent Connection Bar and Mode Selector Header', (WidgetTester tester) async {
    await tester.pumpWidget(const PouseApp());

    // Verify Title & AppBar
    expect(find.textContaining('Pouse — Touchpad'), findsOneWidget);

    // Verify all mouse modes are rendered in Mode Selector Header
    expect(find.text('Touchpad'), findsOneWidget);
    expect(find.text('Motion'), findsOneWidget);
    expect(find.text('Touchless'), findsOneWidget);

    // Verify active TouchpadView is rendered by default
    expect(find.byType(TouchpadView), findsOneWidget);
  });

  testWidgets('Switching between Touchpad, Motion, and Touchless modes updates view and title', (WidgetTester tester) async {
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
}
