import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_true_time/flutter_true_time.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../test/helpers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    WidgetsBinding.instance.handleAppLifecycleStateChanged(
      AppLifecycleState.resumed,
    );
  });
  tearDown(() => TrueTime.dispose());
  test(
    'equivalent newly constructed custom source configurations are idempotent',
    () async {
      final clock = FakeClock();
      await TrueTime.initialize(
        clock: clock,
        sources: [FakeSource('a', 'a'), FakeSource('b', 'b')],
      );
      await TrueTime.waitUntilReady();
      await TrueTime.initialize(
        sources: [FakeSource('a', 'a'), FakeSource('b', 'b')],
      );
      expect(TrueTime.isTrusted, isTrue);
      await expectLater(
        TrueTime.initialize(
          sources: [FakeSource('a', 'a'), FakeSource('c', 'c')],
        ),
        throwsA(isA<TrueTimeException>()),
      );
    },
  );
  test(
    'Flutter pause/resume invalidates and replaces a portable anchor',
    () async {
      final clock = FakeClock()..includesSleep = false;
      await TrueTime.initialize(
        clock: clock,
        sources: [FakeSource('a', 'a'), FakeSource('b', 'b')],
      );
      await TrueTime.waitUntilReady();
      WidgetsBinding.instance.handleAppLifecycleStateChanged(
        AppLifecycleState.paused,
      );
      expect(TrueTime.isTrusted, isFalse);
      WidgetsBinding.instance.handleAppLifecycleStateChanged(
        AppLifecycleState.resumed,
      );
      await TrueTime.forceResync();
      expect(TrueTime.isTrusted, isTrue);
    },
  );
  test('initial background state defers network work until resume', () async {
    WidgetsBinding.instance.handleAppLifecycleStateChanged(
      AppLifecycleState.paused,
    );
    final a = FakeSource('a', 'a'), b = FakeSource('b', 'b');
    await TrueTime.initialize(clock: FakeClock(), sources: [a, b]);
    expect(a.calls, 0);
    expect(b.calls, 0);
    WidgetsBinding.instance.handleAppLifecycleStateChanged(
      AppLifecycleState.resumed,
    );
    await TrueTime.forceResync();
    expect(TrueTime.isTrusted, isTrue);
  });
  test('secure store isolates JSON records by application namespace', () async {
    // Dedicated Flutter test directory keeps the VM-only suite independent.
    // ignore: invalid_use_of_visible_for_testing_member
    FlutterSecureStorage.setMockInitialValues({});
    final a = SecureAnchorStore.open(
      PersistenceConfig(namespace: 'test.application.a'),
    );
    final b = SecureAnchorStore.open(
      PersistenceConfig(namespace: 'test.application.b'),
    );
    await a.save({'version': 2, 'sequence': 1});
    await b.save({'version': 2, 'sequence': 2});
    expect((await a.load())!['sequence'], 1);
    expect((await b.load())!['sequence'], 2);
  });

  testWidgets('disposing while storage is pending releases deadline timers', (
    tester,
  ) async {
    final store = HangingLoadStore();
    final engine = TrueTimeEngine(
      sources: [FakeSource('a', 'a'), FakeSource('b', 'b')],
      clock: FakeClock(),
      store: store,
      epochProvider: FakeEpochProvider(),
      autoRefresh: false,
    );
    final initialization = engine.initialize();
    await tester.pump();
    await engine.dispose();
    await initialization;
    await tester.pump();
    store.pending.complete(null);
  });
}

class HangingLoadStore implements AnchorStore {
  final pending = Completer<Map<String, Object?>?>();
  @override
  Future<Map<String, Object?>?> load() => pending.future;
  @override
  Future<void> save(Map<String, Object?> record) async {}
}
