import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/main.dart';

void main() {
  testWidgets('ControlHubApp smoke test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const ControlHubApp());

    // Verify that the title "Control Hub" is rendered.
    expect(find.text('Control Hub'), findsOneWidget);
  });
}
