import 'dart:async';
import 'dart:convert';
import 'package:flutter_true_time/core.dart';
import 'package:test/test.dart';
import 'helpers.dart';

const maxSequence = 9007199254740991;
const config = TrueTimeConfig(
  maxAnchorAge: Duration(seconds: 1),
  driftPpm: 0,
  sourceTimeout: Duration(milliseconds: 100),
);

class SequenceStore extends FakeStore {
  final writes = <Map<String, Object?>>[];
  final started = Completer<void>(), release = Completer<void>();
  bool blockNext = false;
  int active = 0, maximum = 0;

  @override
  Future<void> save(Map<String, Object?> value) async {
    active++;
    if (active > maximum) maximum = active;
    try {
      if (blockNext) {
        blockNext = false;
        started.complete();
        await release.future;
      }
      await super.save(value);
      writes.add(Map<String, Object?>.from(value));
    } finally {
      active--;
    }
  }
}

void main() {
  late FakeClock clock;
  late Map<String, Object?> seed;

  TrueTimeEngine engine(AnchorStore store) => TrueTimeEngine(
    sources: [FakeSource('a', 'a'), FakeSource('b', 'b')],
    clock: clock,
    store: store,
    epochProvider: FakeEpochProvider(),
    config: config,
    foreground: false,
    autoRefresh: false,
  );

  setUp(() async {
    clock = FakeClock();
    final store = FakeStore();
    final first = engine(store);
    try {
      expect((await first.sync()).success, isTrue);
      seed = Map<String, Object?>.from(store.record!);
    } finally {
      await first.dispose();
    }
    clock.session = 'restarted-process';
  });

  for (final reason in [
    'policy',
    'epoch',
    'stale',
    'uncertainty',
    'providers',
  ]) {
    for (final sequence in [maxSequence, int.parse('9223372036854775807')]) {
      test(
        'rejected $reason record with sequence $sequence cannot affect saves',
        () async {
          final value = Map<String, Object?>.from(seed)
            ..['sequence'] = sequence;
          switch (reason) {
            case 'policy':
              value['policy'] = 'incompatible';
            case 'epoch':
              value['epoch'] = {
                ...Map<String, Object?>.from(value['epoch'] as Map),
                'id': 'another-boot',
              };
            case 'stale':
              clock.advance(const Duration(seconds: 2));
            case 'uncertainty':
              value['uncertaintyUs'] = const Duration(
                seconds: 6,
              ).inMicroseconds;
            case 'providers':
              value['groups'] = ['other-provider'];
          }
          final store = SequenceStore()..record = value;
          final current = engine(store);
          addTearDown(current.dispose);
          await current.initialize();
          expect(current.estimate(), isNull);
          for (final expected in [1, 2]) {
            expect((await current.forceResync()).success, isTrue);
            expect(AnchorRecord.fromMap(store.record!).sequence, expected);
          }
          expect(store.writes, hasLength(2));
        },
      );
    }
  }

  for (final sequence in [1, maxSequence - 1, maxSequence]) {
    test(
      'accepted sequence $sequence advances and rolls over exactly',
      () async {
        final store = SequenceStore()
          ..record = (Map<String, Object?>.from(seed)..['sequence'] = sequence);
        final current = engine(store);
        addTearDown(current.dispose);
        await current.initialize();
        expect(current.read().restoredFromStorage, isTrue);
        var expected = sequence;
        for (var i = 0; i < 3; i++) {
          expected = expected == maxSequence ? 1 : expected + 1;
          expect((await current.forceResync()).success, isTrue);
          // Exercise the JSON representation used by secure storage and browser
          // consumers, in addition to decoding the in-memory record.
          final roundTrip = Map<String, Object?>.from(
            jsonDecode(jsonEncode(store.record)) as Map,
          );
          expect(AnchorRecord.fromMap(roundTrip).sequence, expected);
        }
      },
    );
  }

  test('decoder rejects sequences outside the portable positive range', () {
    for (final sequence in [
      0,
      -1,
      maxSequence + 1,
      int.parse('9223372036854775807'),
    ]) {
      expect(
        () => AnchorRecord.fromMap({...seed, 'sequence': sequence}),
        throwsFormatException,
      );
    }
    expect(
      AnchorRecord.fromMap({...seed, 'sequence': maxSequence}).sequence,
      maxSequence,
    );
  });

  test('record constructor enforces the portable sequence range', () {
    final original = AnchorRecord.fromMap(seed);
    AnchorRecord record(int sequence) => AnchorRecord(
      utc: original.utc,
      monotonic: original.monotonic,
      uncertainty: original.uncertainty,
      clockDomain: original.clockDomain,
      policyFingerprint: original.policyFingerprint,
      sequence: sequence,
      sourceIds: original.sourceIds,
      providerGroups: original.providerGroups,
      epoch: original.epoch,
    );
    expect(AnchorRecord.maxSequence, maxSequence);
    for (final sequence in [0, -1, maxSequence + 1]) {
      expect(() => record(sequence), throwsArgumentError);
    }
    expect(
      AnchorRecord.fromMap(record(maxSequence).toMap()).sequence,
      maxSequence,
    );
  });

  test(
    'a record saved after rollover restores and advances after restart',
    () async {
      final store = SequenceStore()
        ..record = (Map<String, Object?>.from(seed)
          ..['sequence'] = maxSequence);
      final first = engine(store);
      try {
        await first.initialize();
        expect((await first.forceResync()).success, isTrue);
        expect(AnchorRecord.fromMap(store.record!).sequence, 1);
      } finally {
        await first.dispose();
      }
      clock.session = 'another-restart';
      final restarted = engine(store);
      addTearDown(restarted.dispose);
      await restarted.initialize();
      expect(restarted.read().restoredFromStorage, isTrue);
      expect((await restarted.forceResync()).success, isTrue);
      expect(AnchorRecord.fromMap(store.record!).sequence, 2);
    },
  );

  test('rollover preserves ownership and order of a stalled writer', () async {
    final store = SequenceStore()
      ..record = (Map<String, Object?>.from(seed)
        ..['sequence'] = maxSequence - 1)
      ..blockNext = true;
    final current = engine(store);
    addTearDown(current.dispose);
    addTearDown(() {
      if (!store.release.isCompleted) store.release.complete();
    });
    await current.initialize();
    final first = current.forceResync();
    await store.started.future;
    expect((await first).success, isTrue);
    expect((await current.forceResync()).success, isTrue);
    expect(store.active, 1);
    expect(store.writes, isEmpty);
    store.release.complete();
    await SerializingAnchorStore.wrap(store).load();
    expect(store.maximum, 1);
    expect(store.writes.map((value) => AnchorRecord.fromMap(value).sequence), [
      maxSequence,
      1,
    ]);
    expect(AnchorRecord.fromMap(store.record!).sequence, 1);
  });
}
