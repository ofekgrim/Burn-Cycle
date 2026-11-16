import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../test/support/playthrough.dart';

/// Runs the real app on a device or simulator and plays a whole year.
///
///   flutter test integration_test/full_run_test.dart -d DEVICE_ID
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('a whole year plays through on the device', (tester) async {
    await playFullYear(tester);
  });
}
