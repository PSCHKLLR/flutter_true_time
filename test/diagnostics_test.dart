import 'dart:async';
import 'package:flutter_true_time/core.dart';
import 'package:test/test.dart';
import 'helpers.dart';

class SwitchableWall implements WallClockReader {
  bool fail = false;
  int calls = 0;
  DateTime utc = DateTime.utc(2026, 11, 11);
  @override
  WallClockSample read() {
    calls++;
    if (fail) throw StateError('optional diagnostic reader unavailable');
    return WallClockSample(utc, Duration.zero, 'UTC');
  }
}

void main() {
  late FakeClock clock;
  late SwitchableWall wall;
  late FakeScheduler scheduler;
  late TrueTimeEngine engine;
  setUp(() {
    clock = FakeClock();
    wall = SwitchableWall();
    scheduler = FakeScheduler();
    engine = TrueTimeEngine(
      sources: [FakeSource('a', 'a'), FakeSource('b', 'b')],
      clock: clock,
      wallClock: wall,
      scheduler: scheduler,
      autoRefresh: false,
    );
  });
  tearDown(() => engine.dispose());

  test('failed initial diagnostic does not poison initialization', () async {
    wall.fail = true;
    await engine.initialize();
    await engine.initialize();
    expect((await engine.forceResync()).success, isTrue);
    expect(engine.isTrusted, isTrue);
    expect(wall.calls, 1);
    expect(scheduler.callback, isNotNull);
  });

  test('failed resume diagnostic preserves anchor and starts sync', () async {
    await engine.initialize();
    await engine.forceResync();
    final before = engine.now();
    engine.suspend();
    wall.fail = true;
    engine.resume();
    expect(engine.status.syncInProgress, isTrue);
    expect((await engine.forceResync()).success, isTrue);
    expect(engine.now(), before);
    expect(scheduler.callback, isNotNull);
  });

  test(
    'scheduled diagnostics retry after failure with a fresh baseline',
    () async {
      final events = <TimeEventKind>[];
      final subscription = engine.events.listen(
        (event) => events.add(event.kind),
      );
      addTearDown(subscription.cancel);
      await engine.initialize();
      await engine.forceResync();
      final before = engine.now();

      wall.fail = true;
      scheduler.callback!();
      expect(scheduler.delay, engine.diagnosticInterval);
      expect(engine.now(), before);
      expect(wall.calls, 2);

      // A failed read creates a gap; recovery starts a new diagnostic baseline.
      wall.fail = false;
      wall.utc = wall.utc.add(const Duration(days: 1));
      scheduler.callback!();
      await Future<void>.delayed(Duration.zero);
      expect(events, isNot(contains(TimeEventKind.wallClockChanged)));
      expect(wall.calls, 3);
      expect(scheduler.callback, isNotNull);

      wall.utc = wall.utc.add(const Duration(days: 1));
      scheduler.callback!();
      await Future<void>.delayed(Duration.zero);
      expect(events, contains(TimeEventKind.wallClockChanged));
      expect(engine.now(), before);

      engine.suspend();
      expect(scheduler.callback, isNull);
      engine.resume();
      await engine.forceResync();
      expect(scheduler.callback, isNotNull);
      await engine.dispose();
      expect(scheduler.callback, isNull);
    },
  );

  test('explicit failed poll does not throw or change trusted time', () async {
    await engine.sync();
    final before = engine.read();
    wall.fail = true;
    engine.pollDiagnostics();
    expect(engine.now(), before.utc);
    expect(engine.read().uncertainty, before.uncertainty);
  });

  test('polling after disposal still rejects misuse', () async {
    await engine.dispose();
    expect(
      engine.pollDiagnostics,
      throwsA(
        isA<TrueTimeException>().having((e) => e.code, 'code', 'disposed'),
      ),
    );
  });
}
