import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_true_time/flutter_true_time.dart';
import 'package:flutter_true_time_example/main.dart';

import '../integration_test/restart_test.dart' show requireQualificationSeed;

class DemoSource implements TimeSource {
  const DemoSource(this.id);
  @override
  final String id;
  @override
  String get endpoint => id;
  @override
  String get providerGroup => id;
  @override
  String get configurationKey => id;
  @override
  Future<TimeSample> query(
    MonotonicClock clock,
    Duration timeout, {
    CancellationSignal? cancellation,
  }) async => TimeSample(
    utc: DateTime.utc(2026, 11, 11),
    at: clock.snapshot(),
    uncertainty: const Duration(milliseconds: 50),
  );
}

void main() {
  test('restart qualification requires a readable seed', () {
    expect(() => requireQualificationSeed(null), throwsStateError);
  });
  testWidgets('demo renders UTC without public network requests', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: ClockDemo(
          enablePersistence: false,
          sources: [DemoSource('a'), DemoSource('b')],
        ),
      ),
    );
    // Flush initialization, including the optional unavailable storage channel.
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 1));
    }
    expect(find.text('Trusted UTC clock'), findsOneWidget);
    expect(
      find.text(
        'Network-derived estimate. Not cryptographically authenticated.',
      ),
      findsOneWidget,
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
}
