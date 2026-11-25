import 'dart:async';
import 'dart:convert';
import 'package:flutter_true_time/core.dart';
import 'package:test/test.dart';
import 'helpers.dart';

class ControlledWrite {
  ControlledWrite(this.record);
  final Map<String, Object?> record;
  final done = Completer<void>();
}

class ControlledStore extends FakeStore {
  final writes = <ControlledWrite>[];
  int active = 0, maximum = 0, loads = 0;

  @override
  Future<void> save(Map<String, Object?> value) async {
    active++;
    if (active > maximum) maximum = active;
    final write = ControlledWrite(value);
    writes.add(write);
    try {
      await write.done.future;
      record = value;
    } finally {
      active--;
    }
  }

  @override
  Future<Map<String, Object?>?> load() async {
    loads++;
    return record;
  }
}

class ReentrantStore extends FakeStore {
  late SerializingAnchorStore writer;
  late Future<void> nested;
  final release = Completer<void>();
  final starts = <int>[];

  @override
  Future<void> save(Map<String, Object?> value) {
    starts.add(value['sequence'] as int);
    if (starts.length == 1) {
      nested = writer.save({'sequence': 2});
      return release.future;
    }
    throw StateError('synchronous backend failure');
  }
}

Future<void> turn() => Future<void>.delayed(Duration.zero);

final superseded = isA<TrueTimeException>().having(
  (error) => error.code,
  'code',
  'storageSuperseded',
);

void main() {
  test(
    'ten thousand saves retain only the active and newest pending work',
    () async {
      final backend = ControlledStore();
      final writer = SerializingAnchorStore.wrap(backend);
      final first = writer.save({'sequence': 0});
      var rejected = 0, saved = 0;
      Future<void>? latest;
      for (var i = 1; i <= 10000; i++) {
        latest = writer
            .save({'sequence': i})
            .then<void>(
              (_) => saved++,
              onError: (Object error) {
                expect(error, superseded);
                rejected++;
              },
            );
      }
      await turn();
      expect(rejected, 9999);
      expect(saved, 0);
      expect(backend.writes.map((w) => w.record['sequence']), [0]);
      expect(backend.active, 1);
      backend.writes.first.done.complete();
      await first;
      await turn();
      expect(backend.writes.map((w) => w.record['sequence']), [0, 10000]);
      expect(
        saved,
        0,
        reason: 'Starting the newest write is not durable success',
      );
      backend.writes.last.done.complete();
      await latest;
      expect(saved, 1);
      expect(backend.record!['sequence'], 10000);
      expect(backend.maximum, 1);
    },
  );

  test('pending snapshots include independent nested lists and maps', () async {
    final backend = ControlledStore();
    final writer = SerializingAnchorStore.wrap(backend);
    final first = writer.save({'sequence': 1});
    final value = <String, Object?>{
      'sequence': 2,
      'groups': ['a', 'b'],
      'epoch': {'id': 'original'},
    };
    final pending = writer.save(value);
    value['sequence'] = 99;
    (value['groups'] as List).clear();
    (value['epoch'] as Map)['id'] = 'mutated';
    backend.writes.first.done.complete();
    await first;
    await turn();
    expect(backend.writes.last.record, {
      'sequence': 2,
      'groups': ['a', 'b'],
      'epoch': {'id': 'original'},
    });
    backend.writes.last.done.complete();
    await pending;
  });

  test(
    'load waits for a superseded pending record replacement, not later saves',
    () async {
      final backend = ControlledStore();
      final writer = SerializingAnchorStore.wrap(backend);
      final first = writer.save({'sequence': 1});
      final replaced = expectLater(
        writer.save({'sequence': 2}),
        throwsA(superseded),
      );
      final read = writer.load();
      final third = writer.save({'sequence': 3});
      await replaced;
      expect(backend.loads, 0);
      backend.writes.first.done.complete();
      await first;
      await turn();
      expect(backend.loads, 0);
      final fourth = writer.save({'sequence': 4});
      backend.writes.last.done.complete();
      await third;
      expect((await read)!['sequence'], 3);
      expect(backend.writes.map((w) => w.record['sequence']), [1, 3, 4]);
      backend.writes.last.done.complete();
      await fourth;
      expect(backend.maximum, 1);
    },
  );

  test(
    'backend failures preserve stacks, release the permit, and unblock loads',
    () async {
      final backend = ControlledStore();
      final writer = SerializingAnchorStore.wrap(backend);
      final error = StateError('late storage failure');
      final stack = StackTrace.current;
      final first = writer
          .save({'sequence': 1})
          .then<void>(
            (_) => fail('failed write must not succeed'),
            onError: (Object failure, StackTrace trace) {
              expect(failure, same(error));
              expect(trace, same(stack));
            },
          );
      final second = expectLater(
        writer.save({'sequence': 2}),
        throwsA(same(error)),
      );
      final read = writer.load();
      backend.writes.first.done.completeError(error, stack);
      await first;
      await turn();
      expect(backend.writes.length, 2);
      backend.writes.last.done.completeError(error, stack);
      await second;
      expect(await read, isNull);
      final recovery = writer.save({'sequence': 3});
      backend.writes.last.done.complete();
      await recovery;
      expect((await writer.load())!['sequence'], 3);
      expect(backend.maximum, 1);
    },
  );

  test(
    'shared backends order whole policies; different backends stay independent',
    () async {
      final backend = ControlledStore(), other = FakeStore();
      final a = SerializingAnchorStore.wrap(backend);
      final b = SerializingAnchorStore.wrap(backend);
      expect(b, same(a));
      expect(SerializingAnchorStore.wrap(a), same(a));
      final first = a.save({
        'policy': 'a',
        'sequence': AnchorRecord.maxSequence,
      });
      final replaced = expectLater(
        b.save({'policy': 'b', 'sequence': 1}),
        throwsA(superseded),
      );
      final newest = a.save({'policy': 'c', 'sequence': 1});
      await SerializingAnchorStore.wrap(
        other,
      ).save({'policy': 'other', 'sequence': 10});
      expect(other.record!['policy'], 'other');
      await replaced;
      backend.writes.first.done.complete();
      await first;
      await turn();
      expect(backend.writes.last.record, {'policy': 'c', 'sequence': 1});
      backend.writes.last.done.complete();
      await newest;
      expect(backend.maximum, 1);
    },
  );

  test('invalid snapshots do not displace an already pending save', () async {
    final backend = ControlledStore();
    final writer = SerializingAnchorStore.wrap(backend);
    final first = writer.save({'sequence': 1});
    final pending = writer.save({'sequence': 2});
    expect(
      () => writer.save({'invalid': Object()}),
      throwsA(isA<JsonUnsupportedObjectError>()),
    );
    backend.writes.first.done.complete();
    await first;
    await turn();
    expect(backend.writes.last.record['sequence'], 2);
    backend.writes.last.done.complete();
    await pending;
  });

  test(
    'synchronous reentrancy and throws retain one active backend write',
    () async {
      final backend = ReentrantStore();
      final writer = SerializingAnchorStore.wrap(backend);
      backend.writer = writer;
      final first = writer.save({'sequence': 1});
      final failure = expectLater(backend.nested, throwsStateError);
      expect(backend.starts, [1]);
      backend.release.complete();
      await first;
      await failure;
      expect(backend.starts, [1, 2]);
      expect(await writer.load(), isNull);
    },
  );

  test(
    'cancelled observers and late failures never release a stalled writer early',
    () async {
      final errors = await captureAsyncErrors(() async {
        final backend = ControlledStore();
        final writer = SerializingAnchorStore.wrap(backend);
        final signal = CancellationSignal();
        final cancelled = expectLater(
          signal.race(writer.save({'sequence': 1})),
          throwsA(isA<TrueTimeException>()),
        );
        signal.cancel();
        await cancelled;
        unawaited(writer.save({'sequence': 2}));
        final newest = writer.save({'sequence': 3});
        await turn();
        expect(backend.writes.length, 1);
        backend.writes.first.done.completeError(StateError('late failure'));
        await turn();
        expect(backend.writes.map((w) => w.record['sequence']), [1, 3]);
        backend.writes.last.done.complete();
        await newest;
        expect(backend.maximum, 1);
      });
      expect(errors, isEmpty);
    },
  );

  test(
    'many shared-engine syncs coalesce and survive disposal until recovery',
    () async {
      final backend = ControlledStore(), clock = FakeClock();
      TrueTimeEngine engine() => TrueTimeEngine(
        sources: [FakeSource('a', 'a'), FakeSource('b', 'b')],
        clock: clock,
        epochProvider: FakeEpochProvider(),
        store: backend,
        autoRefresh: false,
      );
      final owner = engine(), a = engine(), b = engine();
      addTearDown(owner.dispose);
      addTearDown(a.dispose);
      addTearDown(b.dispose);
      final first = owner.sync();
      await turn();
      expect(backend.writes.length, 1);
      await owner.dispose();
      expect((await first).error?.code, 'disposed');
      var storageFailures = 0;
      final subscriptions = [a, b]
          .map(
            (e) => e.events.listen((event) {
              if (event.kind == TimeEventKind.storageFailed) storageFailures++;
            }),
          )
          .toList();
      Future<SyncOutcome>? pending;
      for (var i = 0; i < 100; i++) {
        clock.advance(const Duration(milliseconds: 1));
        final next = (i.isEven ? a : b).sync();
        await turn();
        if (pending != null) expect((await pending).success, isTrue);
        pending = next;
      }
      expect(backend.writes.length, 1);
      expect(storageFailures, 99);
      expect(a.isTrusted, isTrue);
      expect(b.isTrusted, isTrue);
      final newestUtc = b.now();
      await a.dispose();
      await b.dispose();
      expect((await pending!).error?.code, 'disposed');
      backend.writes.first.done.complete();
      await turn();
      expect(backend.writes.length, 2);
      backend.writes.last.done.complete();
      await SerializingAnchorStore.wrap(backend).load();
      expect(AnchorRecord.fromMap(backend.record!).utc, newestUtc);
      expect(backend.maximum, 1);
      for (final subscription in subscriptions) {
        await subscription.cancel();
      }
    },
  );
}
