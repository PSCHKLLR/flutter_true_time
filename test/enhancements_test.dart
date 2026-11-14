import 'dart:async';
import 'package:test/test.dart';
import 'package:flutter_true_time/core.dart';
import 'helpers.dart';

class Probe {
  int active = 0, maximum = 0, calls = 0, cancelled = 0;
}

class ResourceSource implements TimeSource {
  ResourceSource(this.id, this.probe, this.gate, {this.cooperative = true});
  @override
  final String id;
  final Probe probe;
  final Completer<void> gate;
  final bool cooperative;
  @override
  String get endpoint => id;
  @override
  String get providerGroup => id;
  @override
  String get configurationKey => id;
  @override
  Future<TimeSample> query(
    MonotonicClock clock,
    Duration timeout, {
    CancellationSignal? cancellation,
  }) async {
    probe.calls++;
    probe.active++;
    if (probe.active > probe.maximum) probe.maximum = probe.active;
    try {
      if (cooperative && cancellation != null) {
        await cancellation.race(gate.future);
      } else {
        await gate.future;
      }
      final at = clock.snapshot();
      return TimeSample(
        utc: DateTime.utc(2026, 11, 11).add(at.elapsed),
        at: at,
        uncertainty: const Duration(milliseconds: 10),
      );
    } catch (_) {
      if (cancellation?.isCancelled ?? false) probe.cancelled++;
      rethrow;
    } finally {
      probe.active--;
    }
  }
}

class SlowStore implements AnchorStore {
  final firstStarted = Completer<void>(), releaseFirst = Completer<void>();
  final List<int> writes = [];
  Map<String, Object?>? record;
  @override
  Future<Map<String, Object?>?> load() async => record;
  @override
  Future<void> save(Map<String, Object?> value) async {
    if (writes.isEmpty) {
      writes.add(value['sequence'] as int);
      firstStarted.complete();
      await releaseFirst.future;
    } else {
      writes.add(value['sequence'] as int);
    }
    record = value;
  }
}

class FakeWall implements WallClockReader {
  DateTime utc = DateTime.utc(2026, 11, 11);
  Duration offset = Duration.zero;
  String zone = 'UTC';
  @override
  WallClockSample read() => WallClockSample(utc, offset, zone);
}

void main() {
  late FakeClock clock;
  late FakeSource a, b;
  setUp(() {
    clock = FakeClock();
    a = FakeSource('a', 'a');
    b = FakeSource('b', 'b');
  });
  TrueTimeEngine engine({
    AnchorStore? store,
    BootEpochProvider? epoch,
    TrueTimeConfig config = const TrueTimeConfig(),
    TimeScheduler? scheduler,
    WallClockReader? wall,
    bool refresh = false,
  }) => TrueTimeEngine(
    sources: [a, b],
    clock: clock,
    store: store,
    epochProvider: epoch ?? FakeEpochProvider(),
    config: config,
    autoRefresh: refresh,
    scheduler: scheduler,
    wallClock: wall,
  );
  test('clock quantization and sampling overhead bound uncertainty', () async {
    clock.resolution = const Duration(milliseconds: 16);
    clock.samplingError = const Duration(milliseconds: 2);
    final e = engine();
    addTearDown(e.dispose);
    await e.sync();
    expect(
      e.read().uncertainty,
      greaterThanOrEqualTo(const Duration(milliseconds: 18)),
    );
  });
  test(
    'resume replaces an invalidated cycle even without automatic refresh',
    () async {
      clock.includesSleep = false;
      final e = engine();
      addTearDown(e.dispose);
      await e.sync();
      final gate = Completer<void>();
      a.gate = gate;
      final old = e.sync();
      await Future<void>.delayed(Duration.zero);
      e.suspend();
      a.gate = null;
      e.resume();
      expect((await old).success, isFalse);
      expect((await e.sync()).success, isTrue);
      expect(e.isTrusted, isTrue);
      gate.complete();
    },
  );
  test(
    'native anchor remains readable but no refresh schedules in background',
    () async {
      final scheduler = FakeScheduler();
      final e = engine(scheduler: scheduler, refresh: true);
      addTearDown(e.dispose);
      await e.sync();
      a.gate = Completer<void>();
      final work = e.sync();
      await Future<void>.delayed(Duration.zero);
      e.suspend();
      a.gate!.complete();
      expect((await work).success, isTrue);
      expect(e.isTrusted, isTrue);
      expect(scheduler.callback, isNull);
    },
  );
  test('cycle deadline closes cooperative source resources', () async {
    final probe = Probe(), gate = Completer<void>();
    final e = TrueTimeEngine(
      sources: [
        ResourceSource('a', probe, gate),
        ResourceSource('b', probe, gate),
      ],
      clock: clock,
      autoRefresh: false,
      config: const TrueTimeConfig(
        syncDeadline: Duration(milliseconds: 25),
        sourceTimeout: Duration(seconds: 1),
        maxConcurrentSources: 2,
      ),
    );
    addTearDown(e.dispose);
    expect((await e.sync()).success, isFalse);
    await Future<void>.delayed(Duration.zero);
    expect(probe.active, 0);
    expect(probe.cancelled, 2);
    gate.complete();
  });
  test(
    'noncooperative futures retain permits across repeated cycle deadlines',
    () async {
      final probe = Probe(), gate = Completer<void>();
      final e = TrueTimeEngine(
        sources: [
          ResourceSource('a', probe, gate, cooperative: false),
          ResourceSource('b', probe, gate, cooperative: false),
        ],
        clock: clock,
        autoRefresh: false,
        config: const TrueTimeConfig(
          syncDeadline: Duration(milliseconds: 20),
          sourceTimeout: Duration(seconds: 1),
          maxConcurrentSources: 2,
        ),
      );
      addTearDown(e.dispose);
      for (var i = 0; i < 3; i++) {
        expect((await e.sync()).success, isFalse);
      }
      expect(probe.maximum, 2);
      expect(probe.calls, 2);
      gate.complete();
      await Future<void>.delayed(Duration.zero);
    },
  );
  test('disposal cancels cooperative transport resources', () async {
    final probe = Probe(), gate = Completer<void>();
    final e = TrueTimeEngine(
      sources: [
        ResourceSource('a', probe, gate),
        ResourceSource('b', probe, gate),
      ],
      clock: clock,
      autoRefresh: false,
    );
    final work = e.sync();
    await Future<void>.delayed(Duration.zero);
    await e.dispose();
    expect((await work).error?.code, 'disposed');
    await Future<void>.delayed(Duration.zero);
    expect(probe.active, 0);
    gate.complete();
  });
  test(
    'valid restored anchor completes readiness before the network responds',
    () async {
      final store = FakeStore(), epoch = FakeEpochProvider();
      final seed = engine(store: store, epoch: epoch);
      await seed.sync();
      await seed.dispose();
      clock.session = 'another-process';
      final gate = Completer<void>();
      a.gate = b.gate = gate;
      final e = engine(store: store, epoch: epoch);
      addTearDown(e.dispose);
      final reading = await e.waitUntilReady(
        timeout: const Duration(milliseconds: 100),
      );
      expect(reading.restoredFromStorage, isTrue);
      expect(reading.availability, TimeAvailability.ready);
      gate.complete();
    },
  );
  test(
    'matching boot supports another process session; changed boot rejects it',
    () async {
      final store = FakeStore(), epoch = FakeEpochProvider();
      final seed = engine(store: store, epoch: epoch);
      await seed.sync();
      await seed.dispose();
      clock.session = 'new-process';
      clock.advance(const Duration(hours: 1));
      a.error = b.error = StateError('offline');
      final same = engine(store: store, epoch: epoch);
      await same.initialize();
      await same.sync();
      expect(same.isTrusted, isTrue);
      await same.dispose();
      epoch.boot = 'boot-2';
      final reboot = engine(store: store, epoch: epoch);
      addTearDown(reboot.dispose);
      await reboot.initialize();
      await reboot.sync();
      expect(reboot.estimate(), isNull);
    },
  );
  test(
    'restored backup with a new installation scope cannot restore trust',
    () async {
      final store = FakeStore(), epoch = FakeEpochProvider();
      final seed = engine(store: store, epoch: epoch);
      await seed.sync();
      await seed.dispose();
      epoch.installation = 'new-installation';
      a.error = b.error = StateError('offline');
      final e = engine(store: store, epoch: epoch);
      addTearDown(e.dispose);
      await e.initialize();
      await e.sync();
      expect(e.estimate(), isNull);
    },
  );
  test('unavailable epoch capability fails closed after restart', () async {
    final store = FakeStore();
    final seed = engine(store: store);
    await seed.sync();
    await seed.dispose();
    a.error = b.error = StateError('offline');
    final e = engine(
      store: store,
      epoch: FakeEpochProvider()..available = false,
    );
    addTearDown(e.dispose);
    await e.initialize();
    await e.sync();
    expect(e.estimate(), isNull);
  });
  final mutations = <String, void Function(Map<String, Object?>)>{
    'out-of-range UTC': (r) =>
        r['utcUs'] = DateTime.utc(1970).microsecondsSinceEpoch,
    'negative monotonic': (r) => r['monoUs'] = -1,
    'negative uncertainty': (r) => r['uncertaintyUs'] = -1,
    'unsupported schema': (r) => r['version'] = 1,
    'unknown provider': (r) => r['groups'] = ['a', 'unknown'],
    'duplicate providers': (r) => r['groups'] = ['a', 'a'],
    'unconfigured source': (r) => r['sources'] = ['a', 'not-configured'],
    'wrong clock domain': (r) => r['clockDomain'] = 'other.clock',
    'changed policy': (r) => r['policy'] = 'different-policy',
  };
  for (final entry in mutations.entries) {
    test('restore rejects ${entry.key}', () async {
      final store = FakeStore();
      final seed = engine(store: store);
      await seed.sync();
      await seed.dispose();
      entry.value(store.record!);
      a.error = b.error = StateError('offline');
      final e = engine(store: store);
      addTearDown(e.dispose);
      await e.initialize();
      await e.sync();
      expect(e.estimate(), isNull);
    });
  }
  test('expired stored state is not restored as an offline estimate', () async {
    final store = FakeStore();
    final seed = engine(store: store);
    await seed.sync();
    await seed.dispose();
    clock.advance(const Duration(days: 2));
    a.error = b.error = StateError('offline');
    final e = engine(store: store);
    addTearDown(e.dispose);
    await e.initialize();
    await e.sync();
    expect(e.estimate(), isNull);
  });
  test('caller timeout does not release the real persistent writer', () async {
    final store = SlowStore();
    final e = engine(
      store: store,
      config: const TrueTimeConfig(
        sourceTimeout: Duration(milliseconds: 20),
        syncDeadline: Duration(milliseconds: 200),
      ),
    );
    addTearDown(e.dispose);
    expect((await e.sync()).success, isTrue);
    a.offset = b.offset = const Duration(seconds: 1);
    expect((await e.sync()).success, isTrue);
    expect(store.writes, [1]);
    store.releaseFirst.complete();
    await Future<void>.delayed(Duration.zero);
    expect(store.writes, [1, 2]);
    expect(
      store.record!['utcUs'],
      DateTime.utc(2026, 11, 11, 0, 0, 1).microsecondsSinceEpoch,
    );
  });
  test(
    'disposal completes a cycle awaiting persistence without releasing writer ordering',
    () async {
      final store = SlowStore();
      final e = engine(store: store);
      final work = e.sync();
      await store.firstStarted.future;
      await e.dispose();
      expect((await work).error?.code, 'disposed');
      store.releaseFirst.complete();
    },
  );
  test('wall-clock and timezone events do not change monotonic UTC', () async {
    final wall = FakeWall(), e = engine(wall: FakeWall());
    await e.dispose();
    final clockEngine = engine(wall: wall);
    addTearDown(clockEngine.dispose);
    await clockEngine.sync();
    final before = clockEngine.now();
    final events = <TimeEventKind>[];
    final subscription = clockEngine.events.listen((e) => events.add(e.kind));
    clockEngine.pollDiagnostics();
    wall.utc = wall.utc.add(const Duration(days: 1));
    wall.zone = 'Changed';
    wall.offset = const Duration(hours: 8);
    clockEngine.pollDiagnostics();
    await Future<void>.delayed(Duration.zero);
    expect(events, contains(TimeEventKind.wallClockChanged));
    expect(events, contains(TimeEventKind.timezoneChanged));
    expect(clockEngine.now(), before);
    await subscription.cancel();
  });
  test('built-in source configurations have stable value identities', () {
    expect(
      NtpSource('TIME.EXAMPLE', providerGroup: 'operator').configurationKey,
      NtpSource('time.example', providerGroup: 'operator').configurationKey,
    );
    expect(
      HttpsDateSource(
        Uri.parse('https://time.example'),
        providerGroup: 'operator',
      ).configurationKey,
      HttpsDateSource(
        Uri.parse('https://time.example'),
        providerGroup: 'operator',
      ).configurationKey,
    );
    expect(
      NtpSource('time.example', providerGroup: 'different').configurationKey,
      isNot(
        NtpSource('time.example', providerGroup: 'operator').configurationKey,
      ),
    );
  });
  test('paused external events cannot hang disposal', () async {
    final e = engine();
    final subscription = e.events.listen((_) {});
    subscription.pause();
    await e.dispose().timeout(const Duration(milliseconds: 100));
    await subscription.cancel();
  });

  test(
    'persisted provider evidence must belong to the selected source ids',
    () async {
      final aa = FakeSource('aa', 'operator-a'),
          ab = FakeSource('ab', 'operator-a'),
          c = FakeSource('c', 'operator-c');
      final store = FakeStore();
      final seed = TrueTimeEngine(
        sources: [aa, ab, c],
        clock: clock,
        store: store,
        epochProvider: FakeEpochProvider(),
        autoRefresh: false,
      );
      await seed.sync();
      await seed.dispose();
      store.record!['sources'] = ['aa', 'ab'];
      aa.error = ab.error = c.error = StateError('offline');
      final restored = TrueTimeEngine(
        sources: [aa, ab, c],
        clock: clock,
        store: store,
        epochProvider: FakeEpochProvider(),
        autoRefresh: false,
      );
      addTearDown(restored.dispose);
      await restored.initialize();
      await restored.sync();
      expect(restored.estimate(), isNull);
    },
  );
}
