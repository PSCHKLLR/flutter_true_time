import 'dart:io';
import 'package:flutter_true_time/core.dart';

/// Separate instrumented AOT workload. Run with dartaotruntime --verbose-gc.
/// GC heap growth is not total allocation or native allocator traffic.
Future<void> main(List<String> args) async {
  if (args.length != 2 ||
      !['baseline', 'snapshot', 'read', 'now'].contains(args[0]) ||
      !['true', 'false'].contains(args[1])) {
    throw ArgumentError('Expected baseline|snapshot|read|now true|false');
  }
  final mode = args[0], foreground = args[1] == 'true';
  final clock = createPlatformClock();
  final engine = TrueTimeEngine(
    clock: clock,
    sources: const [_Source('a'), _Source('b')],
    autoRefresh: false,
    foreground: foreground,
  );
  try {
    if (!(await engine.sync()).success) throw StateError('Fixture sync failed');
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
    const warmup = 100000, calls = 2000000;
    var checksum = 0;
    for (var i = 0; i < warmup; i++) {
      checksum ^= sample();
    }
    stderr.writeln(
      'NATIVE_GC_BEGIN $mode $foreground $calls ${clock.capabilities.domain}',
    );
    for (var i = 0; i < calls; i++) {
      checksum ^= sample();
    }
    stderr.writeln('NATIVE_GC_END $checksum');
  } finally {
    await engine.dispose();
  }
}

class _Source implements TimeSource {
  const _Source(this.id);
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
