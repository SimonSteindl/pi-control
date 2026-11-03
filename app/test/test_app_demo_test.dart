import 'package:flutter_test/flutter_test.dart';

import '../lib/test_app_demo.dart';

void main() {
  testWidgets('shows the title, initial value, and working controls',
      (tester) async {
    await tester.pumpWidget(const TestAppDemo());

    expect(find.text('Test App'), findsOneWidget);
    expect(find.text('Zählerstand'), findsOneWidget);
    expect(find.text('0'), findsOneWidget);
    expect(find.byTooltip('Erhöhen'), findsOneWidget);
    expect(find.byTooltip('Verringern'), findsOneWidget);

    await tester.tap(find.byTooltip('Erhöhen'));
    await tester.pump();
    expect(find.text('1'), findsOneWidget);

    await tester.tap(find.byTooltip('Verringern'));
    await tester.pump();
    expect(find.text('0'), findsOneWidget);

    await tester.tap(find.byTooltip('Verringern'));
    await tester.pump();
    expect(find.text('0'), findsOneWidget);
  });
}
