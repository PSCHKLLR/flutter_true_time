import 'dart:async';
import 'package:flutter_true_time/core.dart';
import 'package:test/test.dart';

Future<List<Object>> captureUnhandled(Future<void> Function() body) async {
  final errors = <Object>[];
  final completed = Completer<void>();
  runZonedGuarded(() async {
    try {
      await body();
      // Flush errors from futures whose result the cancelled caller discarded.
      await Future<void>.delayed(Duration.zero);
      completed.complete();
    } catch (error, stack) {
      completed.completeError(error, stack);
    }
  }, (error, _) => errors.add(error));
  await completed.future;
  return errors;
}

void main() {
  final cancelled = isA<TrueTimeException>()
      .having((e) => e.code, 'code', 'cancelled')
      .having((e) => e.message, 'reason', 'caller stopped');
  for (final timed in [false, true]) {
    final name = timed ? 'withTimeout' : 'race';
    Future<int> wrap(CancellationSignal signal, Future<int> operation) => timed
        ? signal.withTimeout(operation, const Duration(days: 1))
        : signal.race(operation);

    test('$name observes an immediate error when already cancelled', () async {
      final errors = await captureUnhandled(() async {
        final signal = CancellationSignal()..cancel('caller stopped');
        final operation = Future<int>.error(StateError('operation failed'));
        expect(() => wrap(signal, operation), throwsA(cancelled));
      });
      expect(errors, isEmpty);
    });

    test('$name observes a late error when already cancelled', () async {
      final errors = await captureUnhandled(() async {
        final signal = CancellationSignal()..cancel('caller stopped');
        final operation = Completer<int>();
        expect(() => wrap(signal, operation.future), throwsA(cancelled));
        operation.completeError(StateError('late operation failure'));
      });
      expect(errors, isEmpty);
    });

    test('$name discards success when already cancelled', () async {
      final errors = await captureUnhandled(() async {
        final signal = CancellationSignal()..cancel('caller stopped');
        expect(() => wrap(signal, Future.value(42)), throwsA(cancelled));
      });
      expect(errors, isEmpty);
    });

    test('$name observes a late error after active cancellation', () async {
      final errors = await captureUnhandled(() async {
        final signal = CancellationSignal();
        final operation = Completer<int>();
        final result = wrap(signal, operation.future);
        final assertion = expectLater(result, throwsA(cancelled));
        signal.cancel('caller stopped');
        await assertion;
        operation.completeError(StateError('late operation failure'));
      });
      expect(errors, isEmpty);
    });

    test('$name preserves ordinary operation results and errors', () async {
      final signal = CancellationSignal();
      expect(await wrap(signal, Future.value(42)), 42);
      final failure = StateError('operation failure');
      await expectLater(
        wrap(signal, Future<int>.error(failure)),
        throwsA(same(failure)),
      );
      signal.cancel();
    });
  }

  test('pre-cancelled withTimeout creates no deadline timer', () {
    var timers = 0;
    runZoned(
      () {
        final signal = CancellationSignal()..cancel('caller stopped');
        expect(
          () => signal.withTimeout(Future.value(42), const Duration(days: 1)),
          throwsA(cancelled),
        );
      },
      zoneSpecification: ZoneSpecification(
        createTimer: (self, parent, zone, duration, callback) {
          timers++;
          return parent.createTimer(zone, duration, callback);
        },
      ),
    );
    expect(timers, 0);
  });

  for (final outcome in ['success', 'failure', 'cancellation']) {
    test('withTimeout releases its timer after $outcome', () async {
      final timers = <Timer>[];
      await runZoned(
        () async {
          final signal = CancellationSignal();
          final operation = Completer<int>();
          final result = signal.withTimeout(
            operation.future,
            const Duration(days: 1),
          );
          if (outcome == 'success') {
            operation.complete(42);
            expect(await result, 42);
          } else if (outcome == 'failure') {
            final error = StateError('operation failure');
            final assertion = expectLater(result, throwsA(same(error)));
            operation.completeError(error);
            await assertion;
          } else {
            final assertion = expectLater(result, throwsA(cancelled));
            signal.cancel('caller stopped');
            await assertion;
            operation.complete(42);
          }
        },
        zoneSpecification: ZoneSpecification(
          createTimer: (self, parent, zone, duration, callback) {
            final timer = parent.createTimer(zone, duration, callback);
            timers.add(timer);
            return timer;
          },
        ),
      );
      expect(timers, hasLength(1));
      expect(timers.single.isActive, isFalse);
    });
  }
}
