import 'dart:ffi';
import 'dart:io';
import 'dart:math';
import 'package:ffi/ffi.dart';
import 'clock.dart';

final class _Timespec extends Struct {
  @Long()
  external int seconds;
  @Long()
  external int nanos;
}

final class _Timebase extends Struct {
  @Uint32()
  external int numer;
  @Uint32()
  external int denom;
}

MonotonicClock createClock() {
  try {
    if (Platform.isWindows) {
      final kernel = DynamicLibrary.open('kernel32.dll');
      final counter = kernel
          .lookupFunction<
            Int32 Function(Pointer<Int64>),
            int Function(Pointer<Int64>)
          >('QueryPerformanceCounter');
      final frequency = kernel
          .lookupFunction<
            Int32 Function(Pointer<Int64>),
            int Function(Pointer<Int64>)
          >('QueryPerformanceFrequency');
      final value = calloc<Int64>();
      late int hz;
      try {
        if (frequency(value) == 0 || value.value <= 0) {
          throw StateError('QPC unavailable');
        }
        hz = value.value;
      } finally {
        calloc.free(value);
      }
      return _NativeClock(
        () {
          final tick = calloc<Int64>();
          try {
            if (counter(tick) == 0) throw StateError('QPC failed');
            final count = tick.value;
            // Avoid overflowing signed 64-bit arithmetic on long-running machines.
            return (count ~/ hz) * 1000000 + (count % hz) * 1000000 ~/ hz;
          } finally {
            calloc.free(tick);
          }
        },
        ClockCapabilities(
          domain: 'windows.qpc.us.v1',
          resolution: Duration(microseconds: (1000000 / hz).ceil()),
          includesSleep: true,
        ),
      );
    }
    if (Platform.isLinux || Platform.isAndroid) {
      final libc = DynamicLibrary.open(
        Platform.isAndroid ? 'libc.so' : 'libc.so.6',
      );
      final gettime = libc
          .lookupFunction<
            Int32 Function(Int32, Pointer<_Timespec>),
            int Function(int, Pointer<_Timespec>)
          >('clock_gettime');
      final getres = libc
          .lookupFunction<
            Int32 Function(Int32, Pointer<_Timespec>),
            int Function(int, Pointer<_Timespec>)
          >('clock_getres');
      final value = calloc<_Timespec>();
      late Duration resolution;
      try {
        if (getres(7, value) != 0) {
          throw StateError('Clock resolution unavailable');
        }
        resolution = Duration(
          microseconds:
              value.ref.seconds * 1000000 + (value.ref.nanos / 1000).ceil(),
        );
      } finally {
        calloc.free(value);
      }
      final os = Platform.isAndroid ? 'android' : 'linux';
      return _NativeClock(
        () {
          final t = calloc<_Timespec>();
          try {
            if (gettime(7, t) != 0) {
              throw StateError('CLOCK_BOOTTIME unavailable');
            }
            return t.ref.seconds * 1000000 + t.ref.nanos ~/ 1000;
          } finally {
            calloc.free(t);
          }
        },
        ClockCapabilities(
          domain: '$os.clock_boottime.us.v1',
          resolution: resolution,
          includesSleep: true,
          supportsBootEpoch: true,
        ),
      );
    }
    if (Platform.isIOS || Platform.isMacOS) {
      final lib = DynamicLibrary.process();
      final ticks = lib.lookupFunction<Uint64 Function(), int Function()>(
        'mach_continuous_time',
      );
      final info = lib
          .lookupFunction<
            Int32 Function(Pointer<_Timebase>),
            int Function(Pointer<_Timebase>)
          >('mach_timebase_info');
      final base = calloc<_Timebase>();
      late int numer, denom;
      try {
        if (info(base) != 0 || base.ref.denom == 0) {
          throw StateError('Invalid timebase');
        }
        numer = base.ref.numer;
        denom = base.ref.denom;
      } finally {
        calloc.free(base);
      }
      return _NativeClock(
        () {
          final count = ticks();
          return ((count ~/ denom) * numer +
                  (count % denom) * numer ~/ denom) ~/
              1000;
        },
        ClockCapabilities(
          domain: 'darwin.mach_continuous.us.v1',
          resolution: Duration(microseconds: (numer / denom / 1000).ceil()),
          includesSleep: true,
        ),
      );
    }
  } catch (_) {
    /* Unknown native capability must not authorize restoration. */
  }
  return StopwatchClock();
}

class _NativeClock implements MonotonicClock {
  _NativeClock(this._micros, this.capabilities) {
    _micros();
  }
  final int Function() _micros;
  @override
  final ClockCapabilities capabilities;
  final String _id =
      Random.secure().nextInt(0x7fffffff).toString() +
      identityHashCode(Object()).toString();
  @override
  bool get includesSleep => capabilities.includesSleep;
  @override
  ClockSnapshot snapshot() {
    final watch = Stopwatch()..start();
    final value = _micros();
    watch.stop();
    return ClockSnapshot(
      Duration(microseconds: value),
      _id,
      uncertainty: capabilities.resolution + watch.elapsed,
    );
  }
}
