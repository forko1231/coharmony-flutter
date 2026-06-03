import 'package:flutter_test/flutter_test.dart';

import 'package:coharmony/main.dart';

void main() {
  testWidgets('App boots and shows the CoHarmony title', (WidgetTester tester) async {
    await tester.pumpWidget(const CoHarmonyApp());
    expect(find.text('CoHarmony'), findsOneWidget);
  });
}
