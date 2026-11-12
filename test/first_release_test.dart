import 'dart:async';
import 'package:test/test.dart';
import 'package:flutter_true_time/core.dart';
import 'helpers.dart';

class DelayedLoadStore implements AnchorStore {
  final started = Completer<void>();
  final loaded = Completer<Map<String, Object?>?>();
  Map<String, Object?>? saved;
  @override
  Future<Map<String, Object?>?> load() {
    started.complete();
    return loaded.future;
  }

  @override
  Future<void> save(Map<String, Object?> value) async {
    saved = value;
  }
}

class LateSource extends FakeSource {
  LateSource() : super('late', 'late');
  final release = Completer<void>();
  bool cancelled = false;
  @override
  Future<TimeSample> query(
    MonotonicClock clock,
    Duration timeout, {
    CancellationSignal? cancellation,
  }) async {
    final detach = cancellation?.onCancel(() => cancelled = true);
    try {
      await release.future;
      final at = clock.snapshot();
      return TimeSample(
        utc: DateTime.utc(2090),
        at: at,
        uncertainty: const Duration(milliseconds: 10),
      );
    } finally {
      detach?.call();
    }
  }
}

class SlowFirstSaveStore extends FakeStore {
  final release = Completer<void>();
  final saved = <AnchorRecord>[];
  int writes = 0;

  @override
  Future<void> save(Map<String, Object?> value) async {
    if (++writes == 1) await release.future;
    await super.save(value);
    saved.add(AnchorRecord.fromMap(value));
  }
}

void main() {
  late FakeClock clock;
  late FakeSource a, b;
  setUp(() {
    clock = FakeClock();
    a = FakeSource('a', 'a');
    b = FakeSource('b', 'b');
  });
  Future<Map<String, Object?>> seed() async {
    final store = FakeStore();
    final e = TrustedTimeEngine(
      sources: [a, b],
      clock: clock,
      store: store,
      epochProvider: FakeEpochProvider(),
      autoRefresh: false,
    );
    await e.sync();
    await e.dispose();
    clock.session = 'restarted-process';
    return Map<String, Object?>.from(store.record!);
  }

  for (final resume in [false, true]) {
    test(
      'restore during pending ${resume ? 'resume' : 'explicit synchronization'}',
      () async {
        final record = await seed();
        final store = DelayedLoadStore();
        final gate = Completer<void>();
        a.gate = b.gate = gate;
        final e = TrustedTimeEngine(
          sources: [a, b],
          clock: clock,
          store: store,
          epochProvider: FakeEpochProvider(),
          autoRefresh: false,
        );
        addTearDown(e.dispose);
        final initialization = e.initialize();
        await store.started.future;
        if (resume) e.resume();
        final network = e.sync();
        await Future<void>.delayed(Duration.zero);
        store.loaded.complete(record);
        await initialization;
        final reading = await e.waitUntilReady(
          timeout: const Duration(milliseconds: 200),
        );
        expect(reading.restoredFromStorage, isTrue);
        expect(e.status.syncInProgress, isTrue);
        await e.dispose();
        await network;
        gate.complete();
      },
    );
  }
  test(
    'a successful network anchor wins over a delayed stored record',
    () async {
      final record = await seed();
      final store = DelayedLoadStore();
      a.offset = b.offset = const Duration(seconds: 5);
      final e = TrustedTimeEngine(
        sources: [a, b],
        clock: clock,
        store: store,
        epochProvider: FakeEpochProvider(),
        autoRefresh: false,
      );
      addTearDown(e.dispose);
      final initialization = e.initialize();
      await store.started.future;
      expect((await e.sync()).success, isTrue);
      store.loaded.complete(record);
      await initialization;
      expect(e.read().restoredFromStorage, isFalse);
      expect(e.now(), DateTime.utc(2026, 11, 11, 0, 0, 5));
    },
  );
  for (final dispose in [false, true]) {
    test(
      'delayed restoration is rejected after ${dispose ? 'disposal' : 'continuity loss'}',
      () async {
        final record = await seed();
        final store = DelayedLoadStore();
        final gate = Completer<void>();
        a.gate = b.gate = gate;
        final e = TrustedTimeEngine(
          sources: [a, b],
          clock: clock,
          store: store,
          epochProvider: FakeEpochProvider(),
          autoRefresh: false,
        );
        addTearDown(e.dispose);
        final initialization = e.initialize();
        await store.started.future;
        if (dispose) {
          await e.dispose();
        } else {
          e.invalidateContinuity();
        }
        store.loaded.complete(record);
        await initialization;
        if (!dispose) expect(e.estimate(), isNull);
        await e.dispose();
        gate.complete();
      },
    );
  }
  test(
    'deadline retains a quorum and ignores a late noncooperative response',
    () async {
      final late = LateSource();
      final store = FakeStore();
      final e = TrustedTimeEngine(
        sources: [a, b, late],
        clock: clock,
        store: store,
        epochProvider: FakeEpochProvider(),
        autoRefresh: false,
        config: const TrustedTimeConfig(
          syncDeadline: Duration(milliseconds: 60),
          sourceTimeout: Duration(seconds: 2),
        ),
      );
      addTearDown(e.dispose);
      expect((await e.sync()).success, isTrue);
      expect(e.read().sourceIds, ['a', 'b']);
      expect(late.cancelled, isTrue);
      final before = e.now();
      late.release.complete();
      await Future<void>.delayed(Duration.zero);
      expect(e.now(), before);
      expect(e.read().sourceIds, ['a', 'b']);
      expect(store.record, isNotNull);
      await e.dispose();
      clock.session = 'restarted-process';
      a.error = b.error = StateError('offline');
      final restarted = TrustedTimeEngine(
        sources: [a, b, late],
        clock: clock,
        store: store,
        epochProvider: FakeEpochProvider(),
        autoRefresh: false,
      );
      addTearDown(restarted.dispose);
      await restarted.initialize();
      expect(restarted.read().restoredFromStorage, isTrue);
      expect(restarted.now(), before);
    },
  );
  test('deadline save stays ordered when its observation times out', () async {
    final late = LateSource(), store = SlowFirstSaveStore();
    final e = TrustedTimeEngine(
      sources: [a, b, late],
      clock: clock,
      store: store,
      epochProvider: FakeEpochProvider(),
      autoRefresh: false,
      config: const TrustedTimeConfig(
        syncDeadline: Duration(milliseconds: 40),
        sourceTimeout: Duration(milliseconds: 200),
      ),
    );
    addTearDown(e.dispose);
    final storageFailed = e.events.firstWhere(
      (event) => event.kind == TimeEventKind.storageFailed,
    );
    expect((await e.sync()).success, isTrue);
    expect(store.writes, 1);
    expect(store.saved, isEmpty);
    await storageFailed.timeout(const Duration(seconds: 2));
    late.release.complete();
    a.offset = b.offset = const Duration(seconds: 1);
    expect((await e.sync()).success, isTrue);
    expect(store.writes, 1);
    store.release.complete();
    await SerializingAnchorStore.wrap(store).load();
    expect(store.saved.map((record) => record.sequence), [1, 2]);
    expect(store.saved.last.utc, e.now());
  });
  test('deadline save failure emits a diagnostic and retains time', () async {
    final late = LateSource(), store = FakeStore()..fail = true;
    final e = TrustedTimeEngine(
      sources: [a, b, late],
      clock: clock,
      store: store,
      autoRefresh: false,
      config: const TrustedTimeConfig(
        syncDeadline: Duration(milliseconds: 40),
        sourceTimeout: Duration(milliseconds: 200),
      ),
    );
    addTearDown(e.dispose);
    final storageFailed = e.events.firstWhere(
      (event) => event.kind == TimeEventKind.storageFailed,
    );
    expect((await e.sync()).success, isTrue);
    await storageFailed.timeout(const Duration(seconds: 2));
    expect(e.now().isUtc, isTrue);
    expect(store.record, isNull);
    late.release.complete();
  });
  test('continuity loss discards even a collected quorum', () async {
    final gate = Completer<void>();
    final late = FakeSource('late', 'late')..gate = gate;
    final store = FakeStore();
    final e = TrustedTimeEngine(
      sources: [a, b, late],
      clock: clock,
      store: store,
      autoRefresh: false,
    );
    addTearDown(e.dispose);
    final work = e.sync();
    await Future<void>.delayed(Duration.zero);
    e.invalidateContinuity();
    expect((await work).success, isFalse);
    expect(e.estimate(), isNull);
    expect(store.record, isNull);
    gate.complete();
  });
  for (final label in ['UNKNOWN', 'Unknown', ' unknown ', '', '   ']) {
    test(
      'unknown provider label "$label" is excluded from live and restored evidence',
      () async {
        final c = FakeSource('c', label);
        final store = FakeStore();
        final e = TrustedTimeEngine(
          sources: [a, b, c],
          clock: clock,
          store: store,
          epochProvider: FakeEpochProvider(),
          autoRefresh: false,
        );
        expect((await e.sync()).success, isTrue);
        expect(e.read().providerGroups, ['a', 'b']);
        expect(e.read().sourceCount, 3);
        await e.dispose();
        clock.session = 'another-process';
        a.error = b.error = c.error = StateError('offline');
        final restored = TrustedTimeEngine(
          sources: [a, b, c],
          clock: clock,
          store: store,
          epochProvider: FakeEpochProvider(),
          autoRefresh: false,
        );
        addTearDown(restored.dispose);
        await restored.initialize();
        expect(restored.read().restoredFromStorage, isTrue);
        expect(restored.read().providerGroups, ['a', 'b']);
      },
    );
  }
  test('known labels are trimmed but remain case sensitive', () async {
    final e = TrustedTimeEngine(
      sources: [FakeSource('a', ' Operator '), FakeSource('b', 'operator')],
      clock: clock,
      autoRefresh: false,
    );
    addTearDown(e.dispose);
    expect((await e.sync()).success, isTrue);
    expect(e.read().providerGroups, ['Operator', 'operator']);
  });
}
