import 'dart:async';
import 'package:flutter_true_time/core.dart';
import 'package:test/test.dart';
import 'helpers.dart';

class FailingClock extends FakeClock {
  final failure = StateError('native clock failed');
  bool fail = false;
  int reads = 0;
  @override
  ClockSnapshot snapshot() {
    reads++;
    if (fail) throw failure;
    return super.snapshot();
  }
}

class PendingLoadStore extends FakeStore {
  final loaded = Completer<Map<String, Object?>?>();
  @override
  Future<Map<String, Object?>?> load() => loaded.future;
}

class AdvancingClock extends FakeClock {
  Duration advanceAfterSample = Duration.zero;
  Duration errorAfterSample = Duration.zero;
  int reads = 0;

  @override
  ClockSnapshot snapshot() {
    reads++;
    final sampled = super.snapshot();
    advance(advanceAfterSample);
    samplingError += errorAfterSample;
    return sampled;
  }
}

Future<List<Object>> captureErrors(Future<void> Function() action) async {
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
  }, (error, _) => errors.add(error));
  await done.future;
  return errors;
}

Future<void> expectSamplingFailure(
  Future<TimeReading> waiting,
  FailingClock clock,
) async {
  try {
    await waiting;
    fail('Expected the original sampling error');
  } catch (error, stack) {
    expect(error, same(clock.failure));
    expect(stack.toString(), contains('FailingClock.snapshot'));
  }
}

void main() {
  for (final boundary in ['age', 'uncertainty']) {
    final config = TrueTimeConfig(
      maxAnchorAge: const Duration(seconds: 1),
      maxUncertainty: const Duration(milliseconds: 11),
      driftPpm: 0,
    );

    void approachBoundary(AdvancingClock clock) {
      if (boundary == 'age') {
        clock.advance(const Duration(milliseconds: 999));
        clock.advanceAfterSample = const Duration(milliseconds: 2);
      } else {
        clock.samplingError = const Duration(microseconds: 999);
        clock.errorAfterSample = const Duration(microseconds: 2);
      }
    }

    void expectReadyCandidate(TimeReading reading) {
      expect(reading.availability, TimeAvailability.ready);
      expect(
        boundary == 'age' ? reading.anchorAge : reading.uncertainty,
        boundary == 'age'
            ? const Duration(milliseconds: 999)
            : const Duration(microseconds: 10999),
      );
    }

    test(
      'already-ready wait uses one sample at the $boundary boundary',
      () async {
        final clock = AdvancingClock();
        final engine = TrueTimeEngine(
          sources: [FakeSource('a', 'a'), FakeSource('b', 'b')],
          clock: clock,
          config: config,
          autoRefresh: false,
          foreground: false,
        );
        addTearDown(engine.dispose);
        expect((await engine.sync()).success, isTrue);
        approachBoundary(clock);
        final reads = clock.reads;
        expectReadyCandidate(await engine.waitUntilReady());
        expect(clock.reads, reads + 1);
        // The following sample is stale; it must not replace the ready candidate.
        expect(engine.read().availability, TimeAvailability.stale);
      },
    );

    test('event-driven wait returns its ready $boundary candidate', () async {
      final clock = AdvancingClock();
      final gate = Completer<void>();
      final engine = TrueTimeEngine(
        sources: [
          FakeSource('a', 'a')..gate = gate,
          FakeSource('b', 'b')..gate = gate,
        ],
        clock: clock,
        config: config,
        autoRefresh: false,
      );
      addTearDown(engine.dispose);
      // Position the clock before the wait's listener receives the first ready
      // event, after consensus has finished sampling its new anchor.
      var positioned = false;
      final position = engine.events.listen((event) {
        if (!positioned &&
            event.kind == TimeEventKind.availabilityChanged &&
            event.detail == 'ready') {
          positioned = true;
          approachBoundary(clock);
        }
      });
      addTearDown(position.cancel);
      final waiting = engine.waitUntilReady();
      await Future<void>.delayed(Duration.zero);
      gate.complete();
      expectReadyCandidate(await waiting);
      expect(positioned, isTrue);
      expect(engine.read().availability, TimeAvailability.stale);
    });

    test('stale $boundary candidate waits for fresh synchronization', () async {
      final clock = AdvancingClock();
      final engine = TrueTimeEngine(
        sources: [FakeSource('a', 'a'), FakeSource('b', 'b')],
        clock: clock,
        config: config,
        autoRefresh: false,
        foreground: false,
      );
      addTearDown(engine.dispose);
      await engine.initialize();
      expect((await engine.sync()).success, isTrue);
      if (boundary == 'age') {
        clock.advance(const Duration(milliseconds: 1001));
      } else {
        clock.samplingError = const Duration(microseconds: 1001);
      }
      var completed = false;
      final waiting = engine.waitUntilReady().then((reading) {
        completed = true;
        return reading;
      });
      await Future<void>.delayed(Duration.zero);
      expect(completed, isFalse);
      clock.samplingError = Duration.zero;
      expect((await engine.forceResync()).success, isTrue);
      final reading = await waiting;
      expect(reading.availability, TimeAvailability.ready);
      expect(reading.anchorAge, Duration.zero);
    });
  }

  for (final boundary in ['age', 'uncertainty']) {
    test(
      'initialization check returns the same ready $boundary sample',
      () async {
        final clock = AdvancingClock();
        final store = PendingLoadStore();
        final engine = TrueTimeEngine(
          sources: [FakeSource('a', 'a'), FakeSource('b', 'b')],
          clock: clock,
          store: store,
          epochProvider: FakeEpochProvider(),
          config: const TrueTimeConfig(
            maxAnchorAge: Duration(seconds: 1),
            maxUncertainty: Duration(milliseconds: 11),
            driftPpm: 0,
          ),
          autoRefresh: false,
          foreground: false,
        );
        addTearDown(engine.dispose);
        expect((await engine.sync()).success, isTrue);
        clock.samplingError = const Duration(milliseconds: 2);
        final waiting = engine.waitUntilReady();
        // Drain stale availability events while restoration remains pending. Only
        // initialization completion can initiate the next readiness check.
        await Future<void>.delayed(Duration.zero);
        if (boundary == 'age') {
          clock.samplingError = Duration.zero;
          clock.advance(const Duration(milliseconds: 999));
          clock.advanceAfterSample = const Duration(milliseconds: 2);
        } else {
          clock.samplingError = const Duration(microseconds: 999);
          clock.errorAfterSample = const Duration(microseconds: 2);
        }
        store.loaded.complete(null);
        final reading = await waiting;
        expect(reading.availability, TimeAvailability.ready);
        expect(
          boundary == 'age' ? reading.anchorAge : reading.uncertainty,
          boundary == 'age'
              ? const Duration(milliseconds: 999)
              : const Duration(microseconds: 10999),
        );
        expect(engine.read().availability, TimeAvailability.stale);
      },
    );
  }

  for (final dispose in [false, true]) {
    test(
      'stale wait cleans up after ${dispose ? 'disposal' : 'timeout'}',
      () async {
        final clock = AdvancingClock();
        final engine = TrueTimeEngine(
          sources: [FakeSource('a', 'a'), FakeSource('b', 'b')],
          clock: clock,
          config: const TrueTimeConfig(maxAnchorAge: Duration(seconds: 1)),
          autoRefresh: false,
          foreground: false,
        );
        addTearDown(engine.dispose);
        await engine.initialize();
        expect((await engine.sync()).success, isTrue);
        clock.advance(const Duration(seconds: 2));
        final assertion = expectLater(
          engine.waitUntilReady(timeout: const Duration(milliseconds: 50)),
          throwsA(
            isA<TrueTimeException>().having(
              (error) => error.code,
              'code',
              dispose ? 'disposed' : 'notReady',
            ),
          ),
        );
        if (dispose) await engine.dispose();
        await assertion;
        final reads = clock.reads;
        if (!dispose) engine.invalidateContinuity();
        await Future<void>.delayed(Duration.zero);
        expect(clock.reads, reads);
      },
    );
  }

  test(
    'event-driven readiness reports sampling failure without zone errors',
    () async {
      final errors = await captureErrors(() async {
        final clock = FailingClock();
        final a = FakeSource('a', 'a')..gate = Completer<void>();
        final b = FakeSource('b', 'b')..gate = Completer<void>();
        final engine = TrueTimeEngine(
          sources: [a, b],
          clock: clock,
          autoRefresh: false,
        );
        try {
          final waiting = engine.waitUntilReady(
            timeout: const Duration(seconds: 1),
          );
          final assertion = expectSamplingFailure(waiting, clock);
          await Future<void>.delayed(Duration.zero);
          clock.fail = true;
          engine.invalidateContinuity();
          // This bound distinguishes prompt error propagation from the API timeout.
          await assertion.timeout(const Duration(milliseconds: 500));
          await Future<void>.delayed(Duration.zero);
          final reads = clock.reads;
          engine.invalidateContinuity();
          await Future<void>.delayed(Duration.zero);
          expect(clock.reads, reads);
          // A failed wait must not poison later synchronization/readiness.
          clock.fail = false;
          a.gate!.complete();
          b.gate!.complete();
          expect((await engine.forceResync()).success, isTrue);
          expect((await engine.waitUntilReady()).utc, engine.now());
        } finally {
          await engine.dispose();
        }
      });
      expect(errors, isEmpty);
    },
  );

  test('initialization completion check reports sampling failure', () async {
    final errors = await captureErrors(() async {
      final clock = FailingClock();
      final store = PendingLoadStore();
      final engine = TrueTimeEngine(
        sources: [FakeSource('a', 'a'), FakeSource('b', 'b')],
        clock: clock,
        store: store,
        autoRefresh: false,
        foreground: false,
      );
      try {
        final waiting = engine.waitUntilReady(
          timeout: const Duration(seconds: 1),
        );
        final assertion = expectSamplingFailure(waiting, clock);
        await Future<void>.delayed(Duration.zero);
        clock.fail = true;
        store.loaded.complete(null);
        await assertion.timeout(const Duration(milliseconds: 500));
      } finally {
        await engine.dispose();
      }
    });
    expect(errors, isEmpty);
  });

  test('initial readiness sampling errors still reach the caller', () async {
    final clock = FailingClock()..fail = true;
    final engine = TrueTimeEngine(
      sources: [],
      clock: clock,
      autoRefresh: false,
    );
    addTearDown(engine.dispose);
    await expectLater(engine.waitUntilReady(), throwsA(same(clock.failure)));
  });
}
