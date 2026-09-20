import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/main.dart';

void main() {
  testWidgets('PouseApp builds successfully', (WidgetTester tester) async {
    await tester.pumpWidget(const PouseApp());
    expect(find.text('Pouse Touchpad'), findsOneWidget);
  });
}
