// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:io';
import 'package:flutter_true_time/core.dart';

class _Clock implements MonotonicClock {
  @override
  bool get includesSleep => true;
  @override
  ClockCapabilities get capabilities => const ClockCapabilities(
    domain: 'benchmark',
    resolution: Duration.zero,
    includesSleep: true,
    supportsBootEpoch: false,
  );
  @override
  ClockSnapshot snapshot() => const ClockSnapshot(Duration.zero, 'benchmark');
}

class _Source implements TimeSource {
  _Source(this.index);
  final int index;
  int groupReads = 0;
  @override
  String get id => 's$index';
  @override
  String get endpoint => id;
  @override
  String get configurationKey => id;
  @override
  String get providerGroup {
    groupReads++;
    return index.isEven ? 'a' : 'b';
  }

  @override
  Future<TimeSample> query(
    MonotonicClock clock,
    Duration timeout, {
    CancellationSignal? cancellation,
  }) async => TimeSample(
    utc: DateTime.utc(2026, 11, 11).add(Duration(microseconds: index)),
    at: clock.snapshot(),
    uncertainty: const Duration(milliseconds: 10),
  );
}

Future<void> main(List<String> args) async {
  const warmup = 5, repetitions = 15;
  final results = <Object>[];
  for (final count in [64, 128, 256, 512, 1024]) {
    final sources = List.generate(count, _Source.new);
    final engine = TrueTimeEngine(
      sources: sources,
      clock: _Clock(),
      autoRefresh: false,
      config: const TrueTimeConfig(
        syncDeadline: Duration(seconds: 30),
        driftPpm: 0,
      ),
    );
    final times = <int>[];
    try {
      for (var i = 0; i < warmup + repetitions; i++) {
        for (final source in sources) {
          source.groupReads = 0;
        }
        final watch = Stopwatch()..start();
        final result = await engine.sync();
        watch.stop();
        if (!result.success) throw StateError('Sync failed: ${result.error}');
        if (i >= warmup) times.add(watch.elapsedMicroseconds);
      }
      times.sort();
      results.add({
        'sources': count,
        'medianUs': times[times.length ~/ 2],
        'p95Us': times[(times.length * .95).ceil() - 1],
        'providerReads': sources.fold<int>(
          0,
          (sum, source) => sum + source.groupReads,
        ),
      });
    } finally {
      await engine.dispose();
    }
  }
  print(
    jsonEncode({
      'label': args.isEmpty ? 'working' : args.first,
      'runtime': Platform.version,
      'os': Platform.operatingSystem,
      'warmup': warmup,
      'repetitions': repetitions,
      'results': results,
    }),
  );
}
