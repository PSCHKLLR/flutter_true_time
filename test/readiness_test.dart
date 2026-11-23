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
