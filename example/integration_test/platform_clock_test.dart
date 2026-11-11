import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:flutter_true_time/flutter_true_time.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('native or browser clock and lifecycle bootstrap', (
    tester,
  ) async {
    final clock = createPlatformClock();
    final first = clock.snapshot();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 50));
    final second = clock.snapshot();
    expect(second.sessionId, first.sessionId);
    expect(second.elapsed >= first.elapsed, isTrue);
    expect(clock.capabilities.resolution >= Duration.zero, isTrue);
  });
}
