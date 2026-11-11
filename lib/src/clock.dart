import 'dart:math';
import 'clock_portable.dart'
    if (dart.library.io) 'clock_native.dart'
    as platform;

class ClockCapabilities {
  const ClockCapabilities({
    required this.domain,
    required this.resolution,
    required this.includesSleep,
    this.supportsBootEpoch = false,
  });
  final String domain;
  final Duration resolution;
  final bool includesSleep, supportsBootEpoch;
}

class ClockSnapshot {
  const ClockSnapshot(
    this.elapsed,
    this.sessionId, {
    this.uncertainty = Duration.zero,
  });
  final Duration elapsed;
  final String sessionId;

  /// Bound for local quantization and sampling overhead; not network error.
  final Duration uncertainty;
}

abstract interface class MonotonicClock {
  ClockSnapshot snapshot();
  ClockCapabilities get capabilities;
  bool get includesSleep;
}

/// Conservative portable fallback; session scoped and invalidated on suspension.
class StopwatchClock implements MonotonicClock {
  StopwatchClock({this.resolution = const Duration(milliseconds: 100)});
  final Duration resolution;
  final Stopwatch _watch = Stopwatch()..start();
  final String _id =
      Random.secure().nextInt(0x7fffffff).toString() +
      identityHashCode(Object()).toString();
  @override
  ClockCapabilities get capabilities => ClockCapabilities(
    domain: 'portable.stopwatch.v1',
    resolution: resolution,
    includesSleep: false,
  );
  @override
  bool get includesSleep => capabilities.includesSleep;
  @override
  ClockSnapshot snapshot() =>
      ClockSnapshot(_watch.elapsed, _id, uncertainty: resolution);
}

MonotonicClock createPlatformClock() => platform.createClock();
