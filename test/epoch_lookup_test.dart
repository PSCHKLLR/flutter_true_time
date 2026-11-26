import 'dart:async';
import 'package:flutter_true_time/core.dart';
import 'package:test/test.dart';
import 'helpers.dart';

class PendingEpochProvider implements BootEpochProvider {
  final calls = <Completer<BootEpoch?>>[];
  void Function()? onLookup;
  @override
  Future<BootEpoch?> currentEpoch(ClockCapabilities clock) {
    final result = Completer<BootEpoch?>();
    calls.add(result);
    onLookup?.call();
    return result.future;
  }
}

class RecordingStore extends FakeStore {
  final writes = <Map<String, Object?>>[];
  @override
  Future<void> save(Map<String, Object?> value) async {
    writes.add(value);
    await super.save(value);
  }
}

Future<void> flush() => Future<void>.delayed(Duration.zero);

void main() {
  late FakeClock clock;
  late FakeSource a, b;
  late PendingEpochProvider epochs;
  late RecordingStore store;
  late TrueTimeEngine engine;
  BootEpoch epoch(String id) => BootEpoch(
    id: id,
    installationScope: 'installation',
    clockDomain: clock.domain,
  );
  setUp(() {
    clock = FakeClock();
    a = FakeSource('a', 'a');
    b = FakeSource('b', 'b');
    epochs = PendingEpochProvider();
    store = RecordingStore();
    engine = TrueTimeEngine(
      sources: [a, b],
      clock: clock,
      store: store,
      epochProvider: epochs,
      autoRefresh: false,
    );
  });
  tearDown(() => engine.dispose());

  test('provider reentrancy joins the already-published lookup', () async {
    Future<SyncOutcome>? work;
    epochs.onLookup = () => work = engine.sync();
    final initialization = engine.initialize();
    await flush();
    expect(epochs.calls, hasLength(1));
    expect(store.writes, isEmpty);
    final accepted = epoch('boot-current');
    epochs.calls.single.complete(accepted);
    expect((await work!).success, isTrue);
    await initialization;
    expect(store.writes.first['epoch'], accepted.toMap());
  });

  test('lookup timeout is shared and late errors remain observed', () async {
    await engine.dispose();
    engine = TrueTimeEngine(
      sources: [a, b],
      clock: clock,
      store: store,
      epochProvider: epochs,
      autoRefresh: false,
      config: const TrueTimeConfig(
        sourceTimeout: Duration(milliseconds: 100),
        syncDeadline: Duration(seconds: 2),
      ),
    );
    final events = <TimeEventKind>[];
    final subscription = engine.events.listen(
      (event) => events.add(event.kind),
    );
    addTearDown(subscription.cancel);
    final initialization = engine.initialize();
    final work = engine.sync();
    expect((await work.timeout(const Duration(seconds: 1))).success, isTrue);
    await initialization;
    expect(epochs.calls, hasLength(1));
    expect(store.writes.first['epoch'], isNull);
    await flush();
    expect(
      events.where((kind) => kind == TimeEventKind.persistenceUnavailable),
      hasLength(1),
    );
    epochs.calls.single.completeError(StateError('late failure'));
    await flush();
    expect((await engine.sync()).success, isTrue);
    expect(epochs.calls, hasLength(1));
  });

  test(
    'cycle deadline leaves initialization lookup available for reuse',
    () async {
      await engine.dispose();
      engine = TrueTimeEngine(
        sources: [a, b],
        clock: clock,
        store: store,
        epochProvider: epochs,
        autoRefresh: false,
        config: const TrueTimeConfig(
          sourceTimeout: Duration(seconds: 2),
          syncDeadline: Duration(milliseconds: 100),
        ),
      );
      final initialization = engine.initialize();
      final outcome = await engine.sync().timeout(const Duration(seconds: 1));
      expect(outcome.success, isTrue);
      expect(a.calls + b.calls, 2);
      expect(store.writes.first['epoch'], isNull);
      final accepted = epoch('boot-current');
      epochs.calls.single.complete(accepted);
      await initialization;
      expect((await engine.sync()).success, isTrue);
      expect(epochs.calls, hasLength(1));
      expect(store.writes.last['epoch'], accepted.toMap());
    },
  );

  test(
    'initialize and sync share pending evidence before the first write',
    () async {
      final initialization = engine.initialize();
      final work = engine.forceResync();
      var finished = false;
      unawaited(work.then((_) => finished = true));
      await flush();
      expect(epochs.calls, hasLength(1));
      expect(finished, isFalse);
      expect(a.calls + b.calls, 2);
      expect(store.writes, isEmpty);

      final accepted = epoch('boot-current');
      epochs.calls.single.complete(accepted);
      expect((await work).success, isTrue);
      await initialization;
      expect(store.writes, isNotEmpty);
      expect(store.writes.first['epoch'], accepted.toMap());
      expect(epochs.calls, hasLength(1));
    },
  );

  for (final oldFirst in [true, false]) {
    test(
      'continuity replacement rejects old lookup (old first: $oldFirst)',
      () async {
        final initialization = engine.initialize();
        final oldWork = engine.sync();
        await flush();
        engine.invalidateContinuity();
        final newWork = engine.forceResync();
        expect((await oldWork).success, isFalse);
        await flush();
        expect(epochs.calls, hasLength(2));
        final old = epoch('boot-old'), current = epoch('boot-new');
        var finished = false;
        unawaited(newWork.then((_) => finished = true));
        if (oldFirst) {
          epochs.calls.first.complete(old);
          await flush();
          expect(finished, isFalse);
          expect(store.writes, isEmpty);
        }
        epochs.calls.last.complete(current);
        expect((await newWork).success, isTrue);
        if (!oldFirst) epochs.calls.first.complete(old);
        await initialization;
        expect((await engine.forceResync()).success, isTrue);
        expect(store.writes, isNotEmpty);
        expect(
          store.writes.every(
            (write) => (write['epoch'] as Map?)?['id'] == 'boot-new',
          ),
          isTrue,
        );
        expect(epochs.calls, hasLength(2));
      },
    );
  }

  test(
    'disposal releases shared waiters and observes late provider failure',
    () async {
      final initialization = engine.initialize();
      final work = engine.sync();
      await flush();
      await engine.dispose();
      await initialization.timeout(const Duration(seconds: 1));
      final outcome = await work.timeout(const Duration(seconds: 1));
      expect(outcome.success, isFalse);
      expect(outcome.error?.code, 'disposed');
      expect(store.writes, isEmpty);
      expect(a.calls + b.calls, 2);
      epochs.calls.single.completeError(StateError('late provider error'));
      await flush();
    },
  );
}
