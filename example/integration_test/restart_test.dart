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

AnchorRecord requireQualificationSeed(Map<String, Object?>? stored) {
  if (stored == null) {
    throw StateError('Missing seed for this qualification run');
  }
  return AnchorRecord.fromMap(stored);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('native restart qualification phase', (tester) async {
    const phase = String.fromEnvironment(
      'TRUE_TIME_RESTART_PHASE',
      defaultValue: 'seed',
    );
    const runId = String.fromEnvironment('TRUE_TIME_RESTART_RUN_ID');
    const unreadableBackup = bool.fromEnvironment(
      'TRUE_TIME_BACKUP_UNREADABLE',
    );
    expect(
      RegExp(r'^[a-zA-Z0-9_-]{8,64}$').hasMatch(runId),
      isTrue,
      reason: 'Use one fresh run ID for all phases of a qualification run',
    );
    expect([
      'seed',
      'same-boot',
      'changed-boot',
      'backup-restore',
      'unavailable-storage',
    ], contains(phase));
    final config = PersistenceConfig(
      namespace: 'dev.pschkllr.flutter_true_time.qualification.$runId',
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
    final engine = TrueTimeEngine(
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
      final proof = await epoch.currentEpoch(clock.capabilities);
      expect(proof?.isValid ?? false, expectsBootProof);
      if (phase == 'seed') {
        expect(await store.load(), isNull, reason: 'Run ID already has a seed');
        final start = clock.snapshot().elapsed;
        expect((await engine.sync()).success, isTrue);
        final stored = await store.load();
        expect(
          stored,
          isNotNull,
          reason: 'Seed must persist, not merely synchronize in memory',
        );
        final record = requireQualificationSeed(stored);
        expect(record.epoch == proof, isTrue);
        expect(record.monotonic, greaterThanOrEqualTo(start));
        expect(record.monotonic, lessThanOrEqualTo(clock.snapshot().elapsed));
        debugPrint(
          'Seed elapsed microseconds: ${record.monotonic.inMicroseconds}',
        );
        return;
      }

      if (phase == 'changed-boot') expect(expectsBootProof, isTrue);
      if (phase == 'backup-restore') {
        expect(
          !kIsWeb && defaultTargetPlatform == TargetPlatform.android,
          isTrue,
        );
      }
      Object? storageError;
      Map<String, Object?>? stored;
      try {
        stored = await store.load().timeout(const Duration(seconds: 3));
      } catch (error) {
        storageError = error;
      }
      if (phase == 'unavailable-storage') {
        expect(
          storageError != null,
          isTrue,
          reason: 'Storage must actually fail',
        );
      } else if (phase == 'backup-restore' && unreadableBackup) {
        expect(
          stored,
          isNull,
          reason: 'Expected the backup seed to be unreadable',
        );
      } else {
        final saved = requireQualificationSeed(stored);
        if (phase == 'same-boot') {
          expect(saved.epoch == proof, isTrue);
        } else {
          final previous = saved.epoch;
          expect(previous?.isValid, isTrue);
          if (phase == 'changed-boot') {
            expect(
              previous!.installationScope == proof!.installationScope,
              isTrue,
            );
            expect(previous.id != proof.id, isTrue);
            final elapsed = clock.snapshot().elapsed;
            expect(elapsed, greaterThan(saved.monotonic));
            debugPrint(
              'Reboot proof differs; elapsed microseconds: ${elapsed.inMicroseconds}',
            );
          } else {
            expect(
              previous!.installationScope != proof!.installationScope,
              isTrue,
            );
          }
        }
      }
      final events = <TimeEventKind>[];
      final subscription = engine.events.listen(
        (event) => events.add(event.kind),
      );
      try {
        await engine.initialize();
        expect((await engine.sync()).success, isFalse);
        final shouldRestore = phase == 'same-boot' && expectsBootProof;
        if (shouldRestore) {
          expect(engine.read().restoredFromStorage, isTrue);
          expect(engine.now().isUtc, isTrue);
        } else {
          expect(engine.estimate(), isNull);
          expect(engine.now, throwsA(isA<TrueTimeException>()));
        }
        if (phase == 'unavailable-storage') {
          expect(events, contains(TimeEventKind.storageFailed));
        }
      } finally {
        await subscription.cancel();
      }
    });
  });
}
