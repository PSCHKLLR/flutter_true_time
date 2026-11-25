import 'dart:async';
import 'dart:math';
import 'package:flutter_true_time/core.dart';
import 'package:test/test.dart';
import 'helpers.dart';

// Deliberately performs synchronous work so the deadline Timer cannot run.
class BudgetBurningSource extends FakeSource {
  BudgetBurningSource() : super('slow', 'slow');
  @override
  Future<TimeSample> query(
    MonotonicClock clock,
    Duration timeout, {
    CancellationSignal? cancellation,
  }) {
    final watch = Stopwatch()..start();
    while (watch.elapsed < const Duration(milliseconds: 150)) {}
    return super.query(clock, timeout, cancellation: cancellation);
  }
}

void main() {
  test('source-count limit is explicit and inclusive', () async {
    final sources = List.generate(
      TrueTimeEngine.maximumSources + 1,
      (i) => FakeSource('s$i', i.isEven ? 'a' : 'b'),
    );
    expect(() => TrueTimeEngine(sources: sources), throwsArgumentError);
    final engine = TrueTimeEngine(
      sources: sources.take(TrueTimeEngine.maximumSources).toList(),
      clock: FakeClock(),
      autoRefresh: false,
    );
    addTearDown(engine.dispose);
    expect((await engine.sync()).success, isTrue);
    expect(engine.read().sourceCount, TrueTimeEngine.maximumSources);
  });

  for (final retainQuorum in [false, true]) {
    test(
      'elapsed budget rejects late immediate samples; retain quorum=$retainQuorum',
      () async {
        final pending = List.generate(
          100,
          (i) => FakeSource('later$i', 'later'),
        );
        final sources = <FakeSource>[
          if (retainQuorum) ...[FakeSource('a', 'a'), FakeSource('b', 'b')],
          BudgetBurningSource(),
          ...pending,
        ];
        final engine = TrueTimeEngine(
          sources: sources,
          clock: FakeClock(),
          autoRefresh: false,
          config: const TrueTimeConfig(
            maxConcurrentSources: 1,
            syncDeadline: Duration(milliseconds: 100),
          ),
        );
        addTearDown(engine.dispose);
        final outcome = await engine.sync();
        expect(outcome.success, retainQuorum);
        expect(sources.whereType<BudgetBurningSource>().single.calls, 1);
        expect(pending.every((source) => source.calls == 0), isTrue);
        if (retainQuorum) {
          expect(engine.read().sourceIds, ['a', 'b']);
        } else {
          expect(engine.estimate(), isNull);
        }
      },
    );
  }

  test('large immediate collection yields to lifecycle callbacks', () async {
    final sources = List.generate(
      TrueTimeEngine.maximumSources,
      (i) => FakeSource('s$i', i.isEven ? 'a' : 'b'),
    );
    final engine = TrueTimeEngine(
      sources: sources,
      clock: FakeClock(),
      autoRefresh: false,
      config: const TrueTimeConfig(maxConcurrentSources: 1),
    );
    addTearDown(engine.dispose);
    final sync = engine.sync();
    final interrupted = Completer<void>();
    Timer.run(() {
      engine.invalidateContinuity();
      interrupted.complete();
    });
    expect((await sync).success, isFalse);
    await interrupted.future;
    expect(
      sources.fold<int>(0, (sum, source) => sum + source.calls),
      lessThan(sources.length),
    );
    expect(engine.estimate(), isNull);
  });

  test('endpoint sweep matches exhaustive endpoint/span consensus', () async {
    final random = Random(20);
    for (var run = 0; run < 120; run++) {
      final sources = List.generate(
        2 + random.nextInt(11),
        (i) => FakeSource(
          's$i',
          ['a', 'b', 'unknown', ''][random.nextInt(4)],
          offset: Duration(microseconds: random.nextInt(25)),
          width: Duration(microseconds: random.nextInt(6)),
        ),
      );
      final intervals = sources
          .map(
            (s) => (
              source: s,
              low: s.offset.inMicroseconds - s.width.inMicroseconds,
              high: s.offset.inMicroseconds + s.width.inMicroseconds,
            ),
          )
          .toList();
      final endpoints =
          intervals.expand((i) => [i.low, i.high]).toSet().toList()..sort();
      final points = <int>[];
      for (var i = 0; i < endpoints.length; i++) {
        points.add(endpoints[i]);
        if (i + 1 < endpoints.length && endpoints[i + 1] - endpoints[i] > 1) {
          points.add((endpoints[i] + endpoints[i + 1]) ~/ 2);
        }
      }
      var best = 0;
      final winners = <List<({FakeSource source, int low, int high})>>[];
      for (final point in points) {
        final active = intervals
            .where((i) => i.low <= point && point <= i.high)
            .toList();
        final groups = active
            .map((i) => i.source.providerGroup)
            .where((g) => g.isNotEmpty && g != 'unknown')
            .toSet();
        if (active.length < 2 || groups.length < 2) continue;
        if (active.length > best) {
          best = active.length;
          winners.clear();
        }
        if (active.length == best) winners.add(active);
      }
      final engine = TrueTimeEngine(
        sources: sources,
        clock: FakeClock(),
        autoRefresh: false,
        config: const TrueTimeConfig(driftPpm: 0),
      );
      try {
        final outcome = await engine.sync();
        if (winners.isEmpty) {
          expect(outcome.error?.code, 'noConsensus', reason: 'fixture $run');
          continue;
        }
        final low = winners.first.map((i) => i.low).reduce(max);
        final high = winners.first.map((i) => i.high).reduce(min);
        final ambiguous = winners.any(
          (w) =>
              w.map((i) => i.low).reduce(max) > high ||
              w.map((i) => i.high).reduce(min) < low,
        );
        if (ambiguous) {
          expect(
            outcome.error?.code,
            'ambiguousConsensus',
            reason: 'fixture $run',
          );
        } else {
          expect(outcome.success, isTrue, reason: 'fixture $run');
          final reading = engine.read();
          expect(
            reading.sourceIds,
            winners.first.map((i) => i.source.id).toList()..sort(),
          );
          expect(
            reading.utc,
            DateTime.utc(
              2026,
              11,
              11,
            ).add(Duration(microseconds: (low + high) ~/ 2)),
          );
          expect(reading.uncertainty.inMicroseconds, (high - low + 1) ~/ 2);
        }
      } finally {
        await engine.dispose();
      }
    }
  });
}
