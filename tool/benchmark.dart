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
  final engine = TrueTimeEngine(
    sources: const [_FixedSource('a', 'a'), _FixedSource('b', 'b')],
    autoRefresh: false,
  );
  try {
    if (!(await engine.sync()).success) {
      throw StateError('Benchmark sync failed');
    }
    print('Clock adapter: ${engine.clock.capabilities.domain}');
    measure('now', () => engine.now().microsecondsSinceEpoch);
    measure('read', () => engine.read().utc.microsecondsSinceEpoch);
  } finally {
    await engine.dispose();
  }
}

void measure(String name, int Function() read) {
  const warmup = 10000, count = 10000, batches = 25;
  var checksum = 0;
  for (var i = 0; i < warmup; i++) {
    checksum ^= read();
  }
  final timings = <double>[];
  final watch = Stopwatch();
  for (var batch = 0; batch < batches; batch++) {
    watch.reset();
    watch.start();
    for (var i = 0; i < count; i++) {
      checksum ^= read();
    }
    watch.stop();
    timings.add(watch.elapsedTicks * 1000000 / (watch.frequency * count));
  }
  timings.sort();
  final median = timings[batches ~/ 2],
      p95 = timings[(batches * .95).ceil() - 1];
  print(
    '$name: $warmup warmup reads, $batches batches of $count reads, '
    'median ${median.toStringAsFixed(3)} µs/read, '
    'p95 ${p95.toStringAsFixed(3)} µs/read across batches, checksum $checksum',
  );
}
