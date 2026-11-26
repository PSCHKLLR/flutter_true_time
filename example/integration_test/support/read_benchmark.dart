import 'package:flutter_true_time/core.dart';

/// Shared offline fixture for host AOT and mobile release/profile measurements.
/// Quantiles are batch-average latencies, not individual-call tail latencies.
Future<Map<String, Object?>> benchmarkReads({
  required String mode,
  int warmup = 10000,
  int count = 10000,
  int batches = 25,
  bool foreground = true,
}) async {
  if (!['baseline', 'snapshot', 'read', 'now'].contains(mode) ||
      warmup < 0 ||
      count < 1 ||
      batches < 2) {
    throw ArgumentError(
      'Require a known mode, nonnegative warmup, positive count and >=2 batches',
    );
  }
  final clock = createPlatformClock();
  final engine = TrueTimeEngine(
    clock: clock,
    sources: const [_BenchmarkSource('a'), _BenchmarkSource('b')],
    autoRefresh: false,
    foreground: foreground,
  );
  try {
    if (!(await engine.sync()).success) {
      throw StateError('Offline benchmark sync failed');
    }
    var baseline = 0;
    final int Function() sample = switch (mode) {
      'baseline' => () => ++baseline,
      'snapshot' => () {
        final value = clock.snapshot();
        return value.elapsed.inMicroseconds ^ value.uncertainty.inMicroseconds;
      },
      'read' => () {
        final value = engine.read();
        return value.utc.microsecondsSinceEpoch ^
            value.uncertainty.inMicroseconds;
      },
      'now' => () => engine.now().microsecondsSinceEpoch,
      _ => throw StateError('Validated mode'),
    };
    var checksum = 0;
    for (var i = 0; i < warmup; i++) {
      checksum ^= sample();
    }
    final watch = Stopwatch(), timings = <double>[];
    var ticks = 0;
    for (var batch = 0; batch < batches; batch++) {
      watch.reset();
      watch.start();
      for (var i = 0; i < count; i++) {
        checksum ^= sample();
      }
      watch.stop();
      ticks += watch.elapsedTicks;
      timings.add(watch.elapsedTicks * 1000000 / (watch.frequency * count));
    }
    timings.sort();
    double quantile(double p) => timings[(batches * p).ceil() - 1];
    return {
      'mode': mode,
      'foreground': foreground,
      'clockDomain': clock.capabilities.domain,
      'clockResolutionUs': clock.capabilities.resolution.inMicroseconds,
      'warmup': warmup,
      'callsPerBatch': count,
      'batches': batches,
      'measuredCalls': count * batches,
      'checksum': checksum,
      'quantileUnit': 'microseconds per call, batch means',
      'minimumUs': timings.first,
      'medianUs': quantile(.5),
      'p95Us': quantile(.95),
      'p99Us': quantile(.99),
      'maximumUs': timings.last,
      'callsPerSecond': ticks == 0
          ? null
          : count * batches * watch.frequency / ticks,
      'batchMeansUs': timings,
      'allocationMeasurement': 'not collected by this latency fixture',
    };
  } finally {
    await engine.dispose();
  }
}

class _BenchmarkSource implements TimeSource {
  const _BenchmarkSource(this.id);
  @override
  final String id;
  @override
  String get endpoint => id;
  @override
  String get configurationKey => 'benchmark:$id';
  @override
  String get providerGroup => id;
  @override
  Future<TimeSample> query(
    MonotonicClock clock,
    Duration timeout, {
    CancellationSignal? cancellation,
  }) async {
    cancellation?.throwIfCancelled();
    final at = clock.snapshot();
    return TimeSample(
      utc: DateTime.utc(2026, 11, 11).add(at.elapsed),
      at: at,
      uncertainty: const Duration(milliseconds: 10),
    );
  }
}
