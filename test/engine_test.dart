import 'dart:async';
import 'package:test/test.dart';
import 'package:flutter_true_time/core.dart';
import 'helpers.dart';

void main() {
  late FakeClock clock;
  late FakeSource a, b;
  late TrueTimeEngine engine;
  setUp(() {
    clock = FakeClock();
    a = FakeSource('a', 'provider-a');
    b = FakeSource('b', 'provider-b');
    engine = TrueTimeEngine(sources: [a, b], clock: clock, autoRefresh: false);
  });
  tearDown(() => engine.dispose());
  test('unavailable clock never falls back to system time', () {
    expect(engine.estimate(), isNull);
    expect(engine.now, throwsA(isA<TrueTimeException>()));
  });
  test(
    'offline hour advances UTC and increases uncertainty by 100 ppm',
    () async {
      expect((await engine.sync()).success, isTrue);
      final initial = engine.read();
      clock.advance(const Duration(hours: 1));
      final next = engine.read();
      expect(next.utc.difference(initial.utc), const Duration(hours: 1));
      expect(
        next.uncertainty - initial.uncertainty,
        const Duration(milliseconds: 360),
      );
      expect(next.utc.isUtc, isTrue);
      expect(next.sourceCount, 2);
      expect(next.providerGroupCount, 2);
    },
  );
  test('failed refresh retains a ready anchor', () async {
    await engine.sync();
    final before = engine.now();
    a.error = b.error = StateError('offline');
    expect((await engine.sync()).success, isFalse);
    expect(engine.now(), before);
    expect(engine.status.lastError, isNotNull);
  });
  test(
    'stale accuracy blocks strict reads but retains labeled estimates',
    () async {
      await engine.sync();
      clock.advance(const Duration(hours: 15));
      expect(engine.read().availability, TimeAvailability.stale);
      expect(engine.now, throwsA(isA<TrueTimeException>()));
    },
  );
  test('age policy independently expires an anchor', () async {
    final ageEngine = TrueTimeEngine(
      sources: [a, b],
      clock: clock,
      autoRefresh: false,
      config: const TrueTimeConfig(driftPpm: 0),
    );
    addTearDown(ageEngine.dispose);
    await ageEngine.sync();
    clock.advance(const Duration(hours: 25));
    expect(ageEngine.read().availability, TimeAvailability.stale);
  });
  test('epoch change invalidates even when new uptime is larger', () async {
    await engine.sync();
    clock.session = 'reboot';
    clock.advance(const Duration(days: 10));
    expect(engine.estimate(), isNull);
  });
  test(
    'regression after a read invalidates even above original anchor',
    () async {
      await engine.sync();
      clock.advance(const Duration(hours: 2));
      engine.read();
      clock.elapsed = const Duration(hours: 1);
      expect(engine.estimate(), isNull);
    },
  );
  test('suspend-safe native clock preserves elapsed time', () async {
    await engine.sync();
    engine.suspend();
    clock.advance(const Duration(hours: 1));
    expect(engine.now(), DateTime.utc(2026, 11, 11, 1));
  });
  test('session-only clock is unavailable through suspension', () async {
    clock.includesSleep = false;
    await engine.sync();
    engine.suspend();
    expect(engine.estimate(), isNull);
    engine.resume();
    await engine.sync();
    expect(engine.isTrusted, isTrue);
  });
  test('rogue outlier does not shift accepted consensus', () async {
    final outlier = FakeSource(
      'rogue',
      'rogue',
      offset: const Duration(days: 2),
    );
    final e = TrueTimeEngine(
      sources: [a, b, outlier],
      clock: clock,
      autoRefresh: false,
    );
    addTearDown(e.dispose);
    expect((await e.sync()).success, isTrue);
    expect(e.now(), DateTime.utc(2026, 11, 11));
    expect(e.read().sourceIds, ['a', 'b']);
  });
  test('same-provider sources fail diversity', () async {
    final e = TrueTimeEngine(
      sources: [a, FakeSource('c', 'provider-a')],
      clock: clock,
      autoRefresh: false,
    );
    addTearDown(e.dispose);
    expect((await e.sync()).success, isFalse);
  });
  test('empty and unknown provider groups do not satisfy diversity', () async {
    final e = TrueTimeEngine(
      sources: [FakeSource('x', ''), FakeSource('y', 'unknown')],
      clock: clock,
      autoRefresh: false,
    );
    addTearDown(e.dispose);
    expect((await e.sync()).success, isFalse);
  });
  test('duplicate endpoints are rejected before querying', () {
    expect(
      () => TrueTimeEngine(sources: [a, a], clock: clock),
      throwsArgumentError,
    );
  });
  test('equally supported disjoint clusters fail', () async {
    final e = TrueTimeEngine(
      sources: [
        a,
        b,
        FakeSource('c', 'c', offset: const Duration(seconds: 10)),
        FakeSource('d', 'd', offset: const Duration(seconds: 10)),
      ],
      clock: clock,
      autoRefresh: false,
    );
    addTearDown(e.dispose);
    final result = await e.sync();
    expect(result.error?.code, 'ambiguousConsensus');
    expect(e.estimate(), isNull);
  });
  test('concurrent callers share one query cycle', () async {
    a.gate = Completer<void>();
    final first = engine.sync(), second = engine.sync();
    expect(identical(first, second), isTrue);
    a.gate!.complete();
    await first;
    expect(a.calls, 1);
    expect(b.calls, 1);
  });
  test(
    'deadline bounds synchronization and late samples cannot overwrite state',
    () async {
      final gate = Completer<void>();
      a.gate = gate;
      final e = TrueTimeEngine(
        sources: [a, b],
        clock: clock,
        autoRefresh: false,
        config: const TrueTimeConfig(
          syncDeadline: Duration(milliseconds: 20),
          sourceTimeout: Duration(seconds: 1),
        ),
      );
      addTearDown(e.dispose);
      expect((await e.sync()).success, isFalse);
      a.gate = null;
      await e.sync();
      final before = e.now();
      gate.complete();
      await Future<void>.delayed(Duration.zero);
      expect(e.now(), before);
    },
  );
  test('invalidation rejects an in-flight cycle', () async {
    a.gate = Completer<void>();
    final work = engine.sync();
    engine.invalidateContinuity();
    a.gate!.complete();
    expect((await work).success, isFalse);
    expect(engine.estimate(), isNull);
  });
  test('new synchronization can correct UTC backward', () async {
    a.offset = b.offset = const Duration(seconds: 10);
    await engine.sync();
    final before = engine.now();
    a.offset = b.offset = Duration.zero;
    await engine.sync();
    expect(engine.now().isBefore(before), isTrue);
  });
  test('storage failure does not discard an in-memory anchor', () async {
    final e = TrueTimeEngine(
      sources: [a, b],
      clock: clock,
      store: FakeStore()..fail = true,
      autoRefresh: false,
    );
    addTearDown(e.dispose);
    await e.initialize();
    await e.sync();
    expect(e.isTrusted, isTrue);
  });
  test(
    'changed boot epoch rejects a stored anchor despite process restart',
    () async {
      final store = FakeStore();
      final first = TrueTimeEngine(
        sources: [a, b],
        clock: clock,
        store: store,
        epochProvider: FakeEpochProvider(),
        autoRefresh: false,
      );
      await first.sync();
      await first.dispose();
      clock.session = 'new-process';
      a.error = b.error = StateError('offline');
      final second = TrueTimeEngine(
        sources: [a, b],
        clock: clock,
        store: store,
        epochProvider: FakeEpochProvider()..boot = 'boot-2',
        autoRefresh: false,
      );
      addTearDown(second.dispose);
      await second.initialize();
      await second.sync();
      expect(second.estimate(), isNull);
    },
  );
  test(
    'readiness has a typed timeout and cleans up its subscription',
    () async {
      a.error = b.error = StateError('offline');
      await expectLater(
        engine.waitUntilReady(timeout: const Duration(milliseconds: 20)),
        throwsA(
          isA<TrueTimeException>().having((e) => e.code, 'code', 'notReady'),
        ),
      );
    },
  );
  test(
    'disposed engine releases a pending sync and rejects further operations',
    () async {
      a.gate = Completer<void>();
      final work = engine.sync();
      await engine.dispose();
      expect((await work).error?.code, 'disposed');
      expect(engine.now, throwsA(isA<TrueTimeException>()));
      a.gate!.complete();
      await engine.dispose();
    },
  );
  test('configuration rejects nonfinite drift and invalid quorum', () {
    expect(
      () => const TrueTimeConfig(driftPpm: double.infinity).validate(),
      throwsArgumentError,
    );
    expect(
      () => const TrueTimeConfig(
        minimumSources: 1,
        minimumProviderGroups: 2,
      ).validate(),
      throwsArgumentError,
    );
  });
  test('refresh is scheduled and cancelled on disposal', () async {
    final scheduler = FakeScheduler();
    final e = TrueTimeEngine(
      sources: [a, b],
      clock: clock,
      scheduler: scheduler,
    );
    await e.sync();
    expect(scheduler.delay, const Duration(minutes: 30));
    await e.dispose();
    expect(scheduler.callback, isNull);
  });

  test('resolved DNS aliases cannot inflate a quorum', () async {
    a.resolvedIdentity = b.resolvedIdentity = 'udp:192.0.2.1:123';
    final outcome = await engine.sync();
    expect(outcome.success, isFalse);
    expect(
      outcome.failures.values.any((s) => s.contains('duplicateEndpoint')),
      isTrue,
    );
  });
  test(
    'corrupt persisted records cannot prevent fresh synchronization',
    () async {
      final store = FakeStore()
        ..record = {'version': 1, 'session': 'test-epoch', 'monoUs': 'invalid'};
      final e = TrueTimeEngine(
        sources: [a, b],
        clock: clock,
        store: store,
        epochProvider: FakeEpochProvider(),
        autoRefresh: false,
      );
      addTearDown(e.dispose);
      await e.initialize();
      await e.sync();
      expect(e.isTrusted, isTrue);
    },
  );
  test(
    'valid persisted state restores only in the same injected epoch',
    () async {
      final store = FakeStore();
      final first = TrueTimeEngine(
        sources: [a, b],
        clock: clock,
        store: store,
        epochProvider: FakeEpochProvider(),
        autoRefresh: false,
      );
      await first.sync();
      await first.dispose();
      a.error = b.error = StateError('offline');
      clock.advance(const Duration(minutes: 1));
      final second = TrueTimeEngine(
        sources: [a, b],
        clock: clock,
        store: store,
        epochProvider: FakeEpochProvider(),
        autoRefresh: false,
      );
      addTearDown(second.dispose);
      await second.initialize();
      await second.sync();
      expect(second.now(), DateTime.utc(2026, 11, 11, 0, 1));
    },
  );
  test('source concurrency never exceeds the configured bound', () async {
    final gate = Completer<void>();
    final pool = List.generate(
      6,
      (i) => FakeSource('source$i', 'provider$i')..gate = gate,
    );
    final e = TrueTimeEngine(
      sources: pool,
      clock: clock,
      autoRefresh: false,
      config: const TrueTimeConfig(maxConcurrentSources: 2),
    );
    addTearDown(e.dispose);
    final work = e.sync();
    await Future<void>.delayed(Duration.zero);
    expect(pool.where((s) => s.calls > 0).length, 2);
    gate.complete();
    expect((await work).success, isTrue);
    expect(pool.every((s) => s.calls == 1), isTrue);
  });
}
