import 'dart:async';
import 'package:flutter_true_time/core.dart';

/// Captures detached callback errors without letting a regression escape tests.
Future<List<Object>> captureAsyncErrors(Future<void> Function() action) async {
  final errors = <Object>[];
  final done = Completer<void>();
  runZonedGuarded(() async {
    try {
      await action();
      await Future<void>.delayed(Duration.zero);
      done.complete();
    } catch (error, stack) {
      done.completeError(error, stack);
    }
  }, (error, stack) => errors.add(error));
  await done.future;
  return errors;
}

class FakeClock implements MonotonicClock {
  Duration elapsed = Duration.zero;
  Duration resolution = Duration.zero;
  Duration samplingError = Duration.zero;
  String domain = 'test.boottime.v1';
  @override
  ClockCapabilities get capabilities => ClockCapabilities(
    domain: domain,
    resolution: resolution,
    includesSleep: includesSleep,
    supportsBootEpoch: true,
  );
  String session = 'test-epoch';
  @override
  bool includesSleep = true;
  @override
  ClockSnapshot snapshot() =>
      ClockSnapshot(elapsed, session, uncertainty: resolution + samplingError);
  void advance(Duration delta) => elapsed += delta;
}

class FakeSource implements TimeSource {
  FakeSource(
    this.id,
    this.providerGroup, {
    this.offset = Duration.zero,
    this.width = const Duration(milliseconds: 10),
  });
  @override
  final String id;
  @override
  String get endpoint => id;
  @override
  String get configurationKey => '$id|$providerGroup';
  @override
  final String providerGroup;
  Duration offset, width;
  String? resolvedIdentity;
  Object? error;
  Completer<void>? gate;
  int calls = 0;
  @override
  Future<TimeSample> query(
    MonotonicClock clock,
    Duration timeout, {
    CancellationSignal? cancellation,
  }) async {
    calls++;
    if (gate != null) {
      await (cancellation == null
          ? gate!.future
          : cancellation.race(gate!.future));
    }
    cancellation?.throwIfCancelled();
    if (error != null) throw error!;
    final at = clock.snapshot();
    return TimeSample(
      utc: DateTime.utc(2026, 11, 11).add(at.elapsed).add(offset),
      at: at,
      uncertainty: width,
      endpointIdentity: resolvedIdentity,
    );
  }
}

class FakeStore implements AnchorStore {
  Map<String, Object?>? record;
  bool fail = false;
  @override
  Future<Map<String, Object?>?> load() async {
    if (fail) throw StateError('storage unavailable');
    return record;
  }

  @override
  Future<void> save(Map<String, Object?> value) async {
    if (fail) throw StateError('storage unavailable');
    record = value;
  }
}

class FakeScheduler implements TimeScheduler {
  Duration? delay;
  void Function()? callback;
  @override
  ScheduledTask schedule(Duration value, void Function() action) {
    delay = value;
    callback = action;
    return FakeTask(() => callback = null);
  }
}

class FakeTask implements ScheduledTask {
  FakeTask(this.action);
  final void Function() action;
  @override
  void cancel() => action();
}

class FakeEpochProvider implements BootEpochProvider {
  String boot = 'boot-1', installation = 'installation-1';
  bool available = true;
  @override
  Future<BootEpoch?> currentEpoch(ClockCapabilities clock) async => available
      ? BootEpoch(
          id: boot,
          installationScope: installation,
          clockDomain: clock.domain,
        )
      : null;
}
