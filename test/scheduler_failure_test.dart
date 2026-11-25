import 'dart:async';
import 'package:flutter_true_time/core.dart';
import 'package:test/test.dart';
import 'helpers.dart';

class FailingScheduler implements TimeScheduler {
  bool fail = true;
  int calls = 0;
  final tasks = <Duration>[];
  @override
  ScheduledTask schedule(Duration delay, void Function() callback) {
    calls++;
    if (fail) throw StateError('scheduler unavailable');
    tasks.add(delay);
    return FakeTask(() => tasks.remove(delay));
  }
}

class TestWall implements WallClockReader {
  @override
  WallClockSample read() =>
      WallClockSample(DateTime.utc(2026), Duration.zero, 'UTC');
}

void main() {
  for (final success in [false, true]) {
    test(
      'scheduler failure preserves network success=$success and settles callers',
      () async {
        final errors = await captureAsyncErrors(() async {
          final scheduler = FailingScheduler();
          final sources = [FakeSource('a', 'a'), FakeSource('b', 'b')];
          if (!success) {
            for (final source in sources) {
              source.error = StateError('offline');
            }
          }
          final engine = TrueTimeEngine(
            sources: sources,
            clock: FakeClock(),
            scheduler: scheduler,
          );
          final events = <TimeEvent>[];
          final subscription = engine.events.listen(events.add);
          try {
            final first = engine.sync();
            final coalesced = engine.sync();
            expect(identical(first, coalesced), isTrue);
            final outcome = await first.timeout(
              const Duration(milliseconds: 500),
            );
            expect(outcome.success, success);
            expect((await coalesced).success, success);
            expect(engine.status.syncInProgress, isFalse);
            expect(engine.isTrusted, success);
            expect(engine.status.lastError, same(outcome.error));
            await Future<void>.delayed(Duration.zero);
            expect(
              events
                  .where(
                    (e) =>
                        e.kind == TimeEventKind.schedulingFailed &&
                        e.detail!.contains('Automatic refresh'),
                  )
                  .single
                  .detail,
              contains('Automatic refresh'),
            );
            expect(scheduler.calls, greaterThanOrEqualTo(1));
            scheduler.fail = false;
            expect((await engine.forceResync()).success, success);
            expect(scheduler.tasks, hasLength(success ? 2 : 1));
          } finally {
            await engine.dispose();
            await subscription.cancel();
          }
          expect(scheduler.tasks, isEmpty);
        });
        expect(errors, isEmpty);
      },
    );
  }

  test(
    'diagnostic scheduling failures do not abort initialize or resume',
    () async {
      final errors = await captureAsyncErrors(() async {
        final scheduler = FailingScheduler();
        final engine = TrueTimeEngine(
          sources: [FakeSource('a', 'a'), FakeSource('b', 'b')],
          clock: FakeClock(),
          scheduler: scheduler,
          wallClock: TestWall(),
        );
        final events = <TimeEvent>[];
        final subscription = engine.events.listen(events.add);
        try {
          await engine.initialize();
          expect((await engine.forceResync()).success, isTrue);
          engine.suspend();
          engine.resume();
          expect((await engine.forceResync()).success, isTrue);
          await Future<void>.delayed(Duration.zero);
          expect(
            events.where(
              (e) =>
                  e.kind == TimeEventKind.schedulingFailed &&
                  e.detail!.contains('Diagnostic poll'),
            ),
            hasLength(2),
          );
          scheduler.fail = false;
          engine.suspend();
          engine.resume();
          expect((await engine.forceResync()).success, isTrue);
          expect(scheduler.tasks, hasLength(3));
        } finally {
          await engine.dispose();
          await subscription.cancel();
        }
        expect(scheduler.tasks, isEmpty);
      });
      expect(errors, isEmpty);
    },
  );

  test('replacement cycle settles when refresh registration fails', () async {
    final errors = await captureAsyncErrors(() async {
      final gate = Completer<void>();
      final sources = [FakeSource('a', 'a'), FakeSource('b', 'b')];
      for (final source in sources) {
        source.gate = gate;
      }
      final engine = TrueTimeEngine(
        sources: sources,
        clock: FakeClock(),
        scheduler: FailingScheduler(),
      );
      try {
        final original = engine.sync();
        await Future<void>.delayed(Duration.zero);
        engine.invalidateContinuity();
        final replacement = engine.forceResync();
        gate.complete();
        expect(
          (await original.timeout(const Duration(milliseconds: 500))).success,
          isFalse,
        );
        expect(
          (await replacement.timeout(
            const Duration(milliseconds: 500),
          )).success,
          isTrue,
        );
        expect(engine.isTrusted, isTrue);
      } finally {
        await engine.dispose();
      }
    });
    expect(errors, isEmpty);
  });
}
