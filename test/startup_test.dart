import 'dart:async';
import 'package:flutter_true_time/core.dart';
import 'package:test/test.dart';
import 'helpers.dart';

class StartupStore extends FakeStore {
  final started = Completer<void>();
  final loaded = Completer<Map<String, Object?>?>();
  @override
  Future<Map<String, Object?>?> load() {
    started.complete();
    return loaded.future;
  }
}

class StartupEpoch implements BootEpochProvider {
  final result = Completer<BootEpoch?>();
  int calls = 0;
  @override
  Future<BootEpoch?> currentEpoch(ClockCapabilities clock) {
    calls++;
    return result.future;
  }
}

void main() {
  test(
    'load timeout completes initialization while fresh time stays ready',
    () async {
      final store = StartupStore();
      final e = TrueTimeEngine(
        clock: FakeClock(),
        sources: [FakeSource('a', 'a'), FakeSource('b', 'b')],
        store: store,
        epochProvider: FakeEpochProvider(),
        autoRefresh: false,
        config: const TrueTimeConfig(sourceTimeout: Duration(milliseconds: 40)),
      );
      addTearDown(e.dispose);
      final initialization = e.initialize();
      await store.started.future;
      expect((await e.waitUntilReady()).restoredFromStorage, isFalse);
      await initialization;
      expect(e.isTrusted, isTrue);
      store.loaded.completeError(StateError('late failed load'));
      await Future<void>.delayed(Duration.zero);
      expect(e.isTrusted, isTrue);
    },
  );

  test(
    'fresh readiness precedes epoch I/O while persistence joins it',
    () async {
      final clock = FakeClock(), epochs = StartupEpoch(), store = FakeStore();
      final a = FakeSource('a', 'a'), b = FakeSource('b', 'b');
      final e = TrueTimeEngine(
        clock: clock,
        sources: [a, b],
        store: store,
        epochProvider: epochs,
        autoRefresh: false,
      );
      addTearDown(e.dispose);
      final initialization = e.initialize();
      final work = e.sync();
      final ready = await e.waitUntilReady();
      expect(ready.restoredFromStorage, isFalse);
      expect(a.calls + b.calls, 2);
      expect(epochs.calls, 1);
      expect(store.record, isNull);
      epochs.result.complete(
        BootEpoch(
          id: 'boot',
          installationScope: 'installation',
          clockDomain: clock.domain,
        ),
      );
      expect((await work).success, isTrue);
      await initialization;
      expect((store.record!['epoch'] as Map)['id'], 'boot');
    },
  );
  for (final invalidate in [false, true]) {
    test('fresh startup wins blocked load (invalidate: $invalidate)', () async {
      final clock = FakeClock();
      final a = FakeSource('a', 'a'), b = FakeSource('b', 'b');
      final store = StartupStore();
      final engine = TrueTimeEngine(
        clock: clock,
        sources: [a, b],
        store: store,
        epochProvider: FakeEpochProvider(),
        autoRefresh: false,
      );
      addTearDown(engine.dispose);
      var initialized = false;
      final initialization = engine.initialize().then(
        (_) => initialized = true,
      );
      await store.started.future;
      expect((await engine.sync()).success, isTrue);
      expect(a.calls, 1);
      expect(b.calls, 1);
      expect(initialized, isFalse);
      final saved = Map<String, Object?>.from(store.record!);
      saved['utcUs'] = DateTime.utc(2030).microsecondsSinceEpoch;
      if (invalidate) engine.invalidateContinuity();
      store.loaded.complete(saved);
      await initialization;
      if (invalidate) {
        expect(engine.estimate(), isNull);
      } else {
        final ready = await engine.waitUntilReady();
        expect(ready.restoredFromStorage, isFalse);
        expect(ready.utc.year, 2026);
      }
    });
  }

  test(
    'disposal ends blocked restoration and observes its late failure',
    () async {
      final errors = await captureAsyncErrors(() async {
        final store = StartupStore();
        final e = TrueTimeEngine(
          clock: FakeClock(),
          sources: [FakeSource('a', 'a'), FakeSource('b', 'b')],
          store: store,
          epochProvider: FakeEpochProvider(),
          autoRefresh: false,
        );
        final initialization = e.initialize();
        await store.started.future;
        await e.sync();
        await e.dispose();
        await initialization;
        store.loaded.completeError(StateError('late storage failure'));
      });
      expect(errors, isEmpty);
    },
  );
}
