import 'dart:async';
import 'package:flutter_true_time/core.dart';
import 'package:test/test.dart';
import 'helpers.dart';

class ExpiryTask implements ScheduledTask {
  ExpiryTask(this.at, this.callback);
  final Duration at;
  final void Function() callback;
  bool cancelled = false;
  @override
  void cancel() => cancelled = true;
}

class ExpiryScheduler implements TimeScheduler {
  ExpiryScheduler(this.clock);
  final FakeClock clock;
  final tasks = <ExpiryTask>[];
  @override
  ScheduledTask schedule(Duration delay, void Function() callback) {
    final task = ExpiryTask(clock.elapsed + delay, callback);
    tasks.add(task);
    return task;
  }

  void advance(Duration amount) {
    clock.advance(amount);
    for (final task in List<ExpiryTask>.of(tasks)) {
      if (!task.cancelled && task.at <= clock.elapsed) {
        task.cancel();
        task.callback();
      }
    }
  }

  List<ExpiryTask> get pending => tasks.where((t) => !t.cancelled).toList();
}

class SwitchableExpiryClock extends FakeClock {
  bool fail = false;
  @override
  ClockSnapshot snapshot() {
    if (fail) throw StateError('sampling unavailable');
    return super.snapshot();
  }
}

void main() {
  late FakeClock clock;
  late ExpiryScheduler scheduler;
  late TrueTimeEngine engine;
  late List<String?> events;
  late StreamSubscription<TimeEvent> subscription;
  Future<void> start(TrueTimeConfig config) async {
    clock = FakeClock();
    scheduler = ExpiryScheduler(clock);
    engine = TrueTimeEngine(
      clock: clock,
      scheduler: scheduler,
      config: config,
      sources: [FakeSource('a', 'a'), FakeSource('b', 'b')],
      autoRefresh: false,
    );
    events = [];
    subscription = engine.events.listen((event) {
      if (event.kind == TimeEventKind.availabilityChanged) {
        events.add(event.detail);
      }
    });
    addTearDown(engine.dispose);
    addTearDown(() => subscription.cancel());
    expect((await engine.sync()).success, isTrue);
    await Future<void>.delayed(Duration.zero);
    events.clear();
  }

  const ageConfig = TrueTimeConfig(
    maxAnchorAge: Duration(seconds: 1),
    driftPpm: 0,
  );

  test('strict age crossing pushes stale without a read', () async {
    await start(ageConfig);
    scheduler.advance(const Duration(seconds: 1));
    await Future<void>.delayed(Duration.zero);
    expect(events, isEmpty);
    expect(scheduler.pending.single.at, const Duration(microseconds: 1000001));
    scheduler.advance(const Duration(microseconds: 1));
    await Future<void>.delayed(Duration.zero);
    expect(events, ['stale']);
    expect(scheduler.pending, isEmpty);
    engine.read();
    await Future<void>.delayed(Duration.zero);
    expect(events, ['stale']);
  });

  test(
    'rounded drift crossing pushes stale at the first invalid microsecond',
    () async {
      await start(
        const TrueTimeConfig(
          driftPpm: 1000000,
          maxUncertainty: Duration(milliseconds: 11),
        ),
      );
      // Source intervals start with 10 ms of uncertainty.
      expect(scheduler.pending.single.at, const Duration(microseconds: 1001));
      scheduler.advance(const Duration(microseconds: 1000));
      expect(events, isEmpty);
      scheduler.advance(const Duration(microseconds: 1));
      await Future<void>.delayed(Duration.zero);
      expect(events, ['stale']);
    },
  );

  test(
    'resync cancels old expiry and stale anchors recover to ready',
    () async {
      await start(ageConfig);
      final old = scheduler.pending.single;
      scheduler.advance(const Duration(milliseconds: 500));
      await engine.sync();
      expect(old.cancelled, isTrue);
      old.callback();
      scheduler.advance(const Duration(microseconds: 500001));
      await Future<void>.delayed(Duration.zero);
      expect(events, isEmpty);
      scheduler.advance(const Duration(milliseconds: 500));
      await Future<void>.delayed(Duration.zero);
      expect(events, ['stale']);
      await engine.sync();
      await Future<void>.delayed(Duration.zero);
      expect(events, ['stale', 'ready']);
    },
  );

  test(
    'suspend cancels, resume resamples, disposal ignores stale callbacks',
    () async {
      await start(ageConfig);
      final task = scheduler.pending.single;
      engine.suspend();
      expect(task.cancelled, isTrue);
      scheduler.advance(const Duration(seconds: 2));
      task.callback();
      await Future<void>.delayed(Duration.zero);
      expect(events, isEmpty);
      engine.resume();
      await Future<void>.delayed(Duration.zero);
      expect(events.first, 'stale');
      await engine.sync();
      final last = scheduler.pending.single;
      await engine.dispose();
      expect(last.cancelled, isTrue);
      last.callback();
    },
  );

  test(
    'continuity loss cancels expiry and repeated reads reuse one task',
    () async {
      await start(ageConfig);
      final task = scheduler.pending.single;
      for (var i = 0; i < 100; i++) {
        engine.read();
      }
      expect(scheduler.tasks.length, 1);
      engine.invalidateContinuity();
      expect(task.cancelled, isTrue);
      task.callback();
      await Future<void>.delayed(Duration.zero);
      expect(events, ['unavailable']);
    },
  );

  test('sampling error changes recompute drift expiry', () async {
    await start(
      const TrueTimeConfig(
        driftPpm: 1000000,
        maxUncertainty: Duration(milliseconds: 12),
      ),
    );
    final previous = scheduler.pending.single;
    clock.samplingError = const Duration(milliseconds: 1);
    engine.read();
    expect(previous.cancelled, isTrue);
    expect(scheduler.pending.single.at, const Duration(microseconds: 1001));
    scheduler.advance(const Duration(microseconds: 1001));
    await Future<void>.delayed(Duration.zero);
    expect(events, ['stale']);
  });

  test(
    'restored anchors expire without waiting for network or reads',
    () async {
      final store = FakeStore();
      final clock = FakeClock();
      final sources = [FakeSource('a', 'a'), FakeSource('b', 'b')];
      TrueTimeEngine make(TimeScheduler scheduler) => TrueTimeEngine(
        sources: sources,
        clock: clock,
        scheduler: scheduler,
        config: ageConfig,
        store: store,
        epochProvider: FakeEpochProvider(),
        autoRefresh: false,
        foreground: false,
      );
      final seed = make(ExpiryScheduler(clock));
      await seed.sync();
      await seed.dispose();
      clock.session = 'restarted';
      for (final source in sources) {
        source.error = StateError('offline');
      }
      final scheduler = ExpiryScheduler(clock);
      final restored = make(scheduler);
      addTearDown(restored.dispose);
      await restored.initialize();
      final changes = <String?>[];
      final sub = restored.events.listen((e) {
        if (e.kind == TimeEventKind.availabilityChanged) changes.add(e.detail);
      });
      addTearDown(sub.cancel);
      restored.resume();
      await restored.sync();
      expect(restored.read().restoredFromStorage, isTrue);
      scheduler.advance(const Duration(microseconds: 1000001));
      await Future<void>.delayed(Duration.zero);
      expect(changes, contains('stale'));
    },
  );

  test(
    'early callbacks and long delays rearm without premature expiry',
    () async {
      await start(
        const TrueTimeConfig(maxAnchorAge: Duration(days: 100), driftPpm: 0),
      );
      final task = scheduler.pending.single;
      expect(task.at, const Duration(days: 1));
      task.cancel();
      task.callback();
      expect(scheduler.pending.single.at, const Duration(days: 1));
      scheduler.advance(const Duration(days: 1));
      await Future<void>.delayed(Duration.zero);
      expect(events, isEmpty);
      expect(scheduler.pending.single.at, const Duration(days: 2));
    },
  );

  test(
    'callback sampling failures are contained and a later read retries',
    () async {
      final clock = SwitchableExpiryClock();
      final scheduler = ExpiryScheduler(clock);
      final e = TrueTimeEngine(
        clock: clock,
        scheduler: scheduler,
        sources: [FakeSource('a', 'a'), FakeSource('b', 'b')],
        autoRefresh: false,
        config: ageConfig,
      );
      addTearDown(e.dispose);
      await e.sync();
      final errors = await captureAsyncErrors(() async {
        clock.fail = true;
        scheduler.advance(const Duration(microseconds: 1000001));
      });
      expect(errors, isEmpty);
      clock.fail = false;
      expect(e.read().availability, TimeAvailability.stale);
      await e.sync();
      expect(scheduler.pending, hasLength(1));
    },
  );
}
