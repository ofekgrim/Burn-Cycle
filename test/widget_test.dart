import 'package:burn_cycle/main.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('app opens on the first morning', (tester) async {
    await tester.pumpWidget(const BurnCycleApp());
    expect(find.textContaining('יום 1'), findsOneWidget);
    expect(find.text('לסיים את הבוקר'), findsOneWidget);
  });
}
