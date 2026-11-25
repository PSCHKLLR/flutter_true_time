import 'package:flutter_true_time/core.dart';
import 'package:test/test.dart';
import 'helpers.dart';

const maximumErrorUs = 9007199254740991;
final uncertain = throwsA(
  isA<TrueTimeException>().having((error) => error.code, 'code', 'uncertain'),
);

void main() {
  late FakeClock clock;
  setUp(() => clock = FakeClock());
  TrueTimeEngine engine({
    AnchorStore? store,
    TrueTimeConfig config = const TrueTimeConfig(),
  }) => TrueTimeEngine(
    sources: [FakeSource('a', 'a'), FakeSource('b', 'b')],
    clock: clock,
    store: store,
    epochProvider: FakeEpochProvider(),
    config: config,
    autoRefresh: false,
    foreground: false,
  );

  for (final error in [
    maximumErrorUs,
    maximumErrorUs + 1,
    int.parse('9223372036854775807'),
  ]) {
    test('oversized stored uncertainty $error is never restored', () async {
      clock.resolution = const Duration(microseconds: 1);
      final store = FakeStore();
      final original = engine(store: store);
      expect((await original.sync()).success, isTrue);
      await original.dispose();
      store.record = {...store.record!, 'uncertaintyUs': error};
      clock.session = 'restarted';
      final restored = engine(store: store);
      addTearDown(restored.dispose);
      await restored.initialize();
      expect(restored.estimate(), isNull);
      expect((await restored.forceResync()).success, isTrue);
      expect(
        AnchorRecord.fromMap(store.record!).uncertainty,
        lessThan(const Duration(seconds: 5)),
      );
    });
  }

  for (final error in [
    maximumErrorUs,
    maximumErrorUs + 1,
    int.parse('9223372036854775807'),
  ]) {
    test(
      'sampling uncertainty $error cannot wrap a fresh reading ready',
      () async {
        final current = engine();
        addTearDown(current.dispose);
        expect((await current.sync()).success, isTrue);
        clock.samplingError = Duration(microseconds: error);
        expect(current.read, uncertain);
        expect(current.now, uncertain);
      },
    );
  }

  test(
    'representable over-policy uncertainty remains a stale estimate',
    () async {
      final current = engine();
      addTearDown(current.dispose);
      await current.sync();
      clock.samplingError = const Duration(seconds: 10);
      expect(current.read().availability, TimeAvailability.stale);
      expect(current.read().uncertainty, const Duration(milliseconds: 10010));
    },
  );

  test(
    'the exact sum limit is supported; its successor fails closed',
    () async {
      final current = engine(
        config: const TrueTimeConfig(
          maxUncertainty: Duration(microseconds: maximumErrorUs),
          driftPpm: 0,
        ),
      );
      addTearDown(current.dispose);
      await current.sync();
      final anchorError = current.read().uncertainty.inMicroseconds;
      clock.samplingError = Duration(
        microseconds: maximumErrorUs - anchorError,
      );
      expect(current.read().uncertainty.inMicroseconds, maximumErrorUs);
      expect(current.read().availability, TimeAvailability.ready);
      clock.samplingError += const Duration(microseconds: 1);
      expect(current.read, uncertain);
    },
  );

  test(
    'huge finite drift fails with a typed error rather than wrapping',
    () async {
      final current = engine(config: const TrueTimeConfig(driftPpm: 1e308));
      addTearDown(current.dispose);
      expect((await current.sync()).success, isTrue);
      clock.advance(const Duration(seconds: 1));
      expect(current.read, uncertain);
    },
  );

  test('maximum-width consensus keeps exact endpoints and midpoint', () async {
    final sources = [FakeSource('a', 'a'), FakeSource('b', 'b')];
    for (final source in sources) {
      source.width = const Duration(microseconds: maximumErrorUs);
      source.offset = const Duration(microseconds: 1);
    }
    final current = TrueTimeEngine(
      sources: sources,
      clock: clock,
      config: const TrueTimeConfig(
        maxUncertainty: Duration(microseconds: maximumErrorUs),
        driftPpm: 0,
      ),
      autoRefresh: false,
      foreground: false,
    );
    addTearDown(current.dispose);
    expect((await current.sync()).success, isTrue);
    final reading = current.read();
    expect(reading.uncertainty.inMicroseconds, maximumErrorUs);
    expect(
      reading.utc,
      DateTime.utc(2026, 11, 11).add(const Duration(microseconds: 1)),
    );
  });

  test('oversized local uncertainty cannot create a live anchor', () async {
    clock.samplingError = const Duration(microseconds: maximumErrorUs);
    final current = engine();
    addTearDown(current.dispose);
    final outcome = await current.sync();
    expect(outcome.success, isFalse);
    expect(outcome.error?.code, 'uncertain');
    expect(current.estimate(), isNull);
  });

  test(
    'out-of-range uncertainty configuration is rejected at construction',
    () {
      expect(
        () => engine(
          config: const TrueTimeConfig(
            maxUncertainty: Duration(microseconds: maximumErrorUs + 1),
          ),
        ),
        throwsArgumentError,
      );
    },
  );
}
