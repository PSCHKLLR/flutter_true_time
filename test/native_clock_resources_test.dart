import 'dart:ffi';
import 'dart:isolate';
import 'package:flutter_true_time/core.dart';
import 'package:flutter_true_time/src/native_clock_resources.dart';
import 'package:test/test.dart';
import 'helpers.dart';

const capabilities = ClockCapabilities(
  domain: 'test.native',
  resolution: Duration(microseconds: 7),
  includesSleep: true,
);

void main() {
  test(
    'scratch is reused, nested reads are isolated, failures release ownership',
    () {
      final scratch = NativeClockScratch(sizeOf<Int64>());
      addTearDown(scratch.close);
      var address = 0;
      scratch.read((outer) {
        address = outer.address;
        outer.cast<Int64>().value = 123;
        scratch.read((inner) {
          expect(inner.address, isNot(address));
          inner.cast<Int64>().value = 456;
          expect(scratch.close, throwsStateError);
          return 456;
        });
        expect(outer.cast<Int64>().value, 123);
        return 123;
      });
      expect(
        () => scratch.read((_) => throw StateError('native failure')),
        throwsStateError,
      );
      scratch.read((value) {
        expect(value.address, address);
        return 0;
      });
      scratch.close();
      scratch.close();
      expect(
        () => scratch.read((_) => fail('must not use freed memory')),
        throwsStateError,
      );
    },
  );

  test(
    'native scratch and capturing clock cannot be copied across isolates',
    () {
      final scratch = NativeClockScratch(sizeOf<Int64>());
      addTearDown(scratch.close);
      final port = ReceivePort();
      addTearDown(port.close);
      final clock = NativeSamplingClock(
        () => scratch.read((_) => 1),
        capabilities,
      );
      expect(() => port.sendPort.send(scratch), throwsArgumentError);
      expect(() => port.sendPort.send(clock), throwsArgumentError);
    },
  );

  test(
    'nested sampling and failure preserve immutable snapshots and error floor',
    () {
      var count = 0, recurse = false, shouldFail = false;
      late NativeSamplingClock clock;
      ClockSnapshot? nested;
      clock = NativeSamplingClock(() {
        if (shouldFail) throw StateError('sampling failure');
        if (recurse) {
          recurse = false;
          nested = clock.snapshot();
        }
        return ++count;
      }, capabilities);
      final first = clock.snapshot();
      recurse = true;
      final outer = clock.snapshot();
      expect(outer.elapsed, greaterThan(nested!.elapsed));
      expect(outer.sessionId, nested!.sessionId);
      expect(outer.uncertainty, greaterThanOrEqualTo(capabilities.resolution));
      expect(
        nested!.uncertainty,
        greaterThanOrEqualTo(capabilities.resolution),
      );
      expect(first.elapsed, const Duration(microseconds: 2));
      shouldFail = true;
      expect(clock.snapshot, throwsStateError);
      shouldFail = false;
      expect(clock.snapshot().elapsed, greaterThan(outer.elapsed));
    },
  );

  test('long-uptime samples retain exact elapsed microseconds', () {
    final uptime = (1 << 60) + 123;
    final clock = NativeSamplingClock(() => uptime, capabilities);
    expect(clock.snapshot().elapsed.inMicroseconds, uptime);
  });

  test(
    'disposing one engine never releases a clock shared with another',
    () async {
      final scratch = NativeClockScratch(sizeOf<Int64>());
      addTearDown(scratch.close);
      final clock = NativeSamplingClock(
        () => scratch.read((p) {
          final value = p.cast<Int64>();
          return ++value.value;
        }),
        capabilities,
      );
      TrueTimeEngine engine() => TrueTimeEngine(
        clock: clock,
        sources: [FakeSource('a', 'a'), FakeSource('b', 'b')],
        autoRefresh: false,
        foreground: false,
      );
      final a = engine(), b = engine();
      addTearDown(a.dispose);
      addTearDown(b.dispose);
      expect((await a.sync()).success, isTrue);
      expect((await b.sync()).success, isTrue);
      await a.dispose();
      final before = b.now();
      expect(b.now().isBefore(before), isFalse);
      expect((await b.sync()).success, isTrue);
    },
  );
}
