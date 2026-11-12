import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:flutter_true_time/flutter_true_time.dart';

// This deterministic fixture tests native persistence/epoch proof, not providers.
class FixtureSource implements TimeSource {
  FixtureSource(this.id, this.offline);
  @override
  final String id;
  final bool offline;
  @override
  String get endpoint => id;
  @override
  String get providerGroup => id;
  @override
  String get configurationKey => 'native-restart-fixture:$id:v1';
  @override
  Future<TimeSample> query(
    MonotonicClock clock,
    Duration timeout, {
    CancellationSignal? cancellation,
  }) async {
    cancellation?.throwIfCancelled();
    if (offline) throw StateError('Deliberate offline qualification phase');
    final at = clock.snapshot();
    return TimeSample(
      utc: DateTime.utc(2026, 11, 12),
      at: at,
      uncertainty: const Duration(milliseconds: 10),
    );
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('native restart qualification phase', (tester) async {
    const phase = String.fromEnvironment(
      'TRUE_TIME_RESTART_PHASE',
      defaultValue: 'seed',
    );
    expect([
      'seed',
      'same-boot',
      'changed-boot',
      'unavailable-storage',
    ], contains(phase));
    final config = PersistenceConfig(
      namespace: 'dev.pschkllr.flutter_true_time.qualification',
    );
    final clock = createPlatformClock(),
        epoch = createPlatformEpochProvider(config);
    final store = SecureAnchorStore.open(config);
    final expectsBootProof =
        !kIsWeb &&
        [
          TargetPlatform.android,
          TargetPlatform.linux,
        ].contains(defaultTargetPlatform);
    final engine = TrustedTimeEngine(
      sources: [
        FixtureSource('fixture-a', phase != 'seed'),
        FixtureSource('fixture-b', phase != 'seed'),
      ],
      clock: clock,
      store: store,
      epochProvider: epoch,
      autoRefresh: false,
    );
    addTearDown(engine.dispose);
    await tester.runAsync(() async {
      if (phase == 'seed') {
        expect((await engine.sync()).success, isTrue);
        final stored = await store.load();
        expect(
          stored,
          isNotNull,
          reason: 'Seed must persist, not merely synchronize in memory',
        );
        final proof = await epoch.currentEpoch(clock.capabilities);
        if (expectsBootProof) {
          expect(proof, isNotNull);
        } else {
          expect(proof, isNull);
        }
        expect(AnchorRecord.fromMap(stored!).epoch, proof);
      } else {
        await engine.initialize();
        // Await the deliberately offline cycle so all source wrappers settle.
        await engine.sync();
        final proof = await epoch.currentEpoch(clock.capabilities);
        if (phase == 'same-boot' && expectsBootProof) {
          expect(
            proof,
            isNotNull,
            reason: 'Native restart support needs actual epoch proof',
          );
        }
        final shouldRestore = phase == 'same-boot' && expectsBootProof;
        if (!expectsBootProof) expect(proof, isNull);
        expect(engine.estimate()?.restoredFromStorage ?? false, shouldRestore);
        if (!shouldRestore) expect(engine.estimate(), isNull);
      }
    });
  });
}
