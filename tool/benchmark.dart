// ignore_for_file: avoid_print
import 'package:flutter_true_time/core.dart';

class _FixedSource implements TimeSource {
  const _FixedSource(this.id, this.providerGroup);
  @override
  final String id;
  @override
  final String providerGroup;
  @override
  String get endpoint => id;
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
    uncertainty: const Duration(milliseconds: 10),
  );
}

Future<void> main() async {
  final engine = TrustedTimeEngine(
    sources: const [_FixedSource('a', 'a'), _FixedSource('b', 'b')],
    autoRefresh: false,
  );
  await engine.sync();
  for (var i = 0; i < 10000; i++) {
    engine.now();
  }
  const count = 100000;
  final watch = Stopwatch()..start();
  var checksum = 0;
  for (var i = 0; i < count; i++) {
    checksum ^= engine.now().microsecondsSinceEpoch;
  }
  watch.stop();
  print(
    'Average read microseconds: ${(watch.elapsedMicroseconds / count).toStringAsFixed(3)}',
  );
  print('Checksum: $checksum');
  await engine.dispose();
}
