import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';
import 'clock.dart';
import 'native_clock_resources.dart';

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
      final scratch = NativeClockScratch(sizeOf<Int64>());
      try {
        final hz = scratch.read((pointer) {
          final value = pointer.cast<Int64>();
          if (frequency(value) == 0 || value.value <= 0) {
            throw StateError('QPC unavailable');
          }
          return value.value;
        });
        int sample(Pointer<Void> pointer) {
          final tick = pointer.cast<Int64>();
          if (counter(tick) == 0) throw StateError('QPC failed');
          final count = tick.value;
          // Preserve quotient/remainder conversion for long-running hosts.
          return (count ~/ hz) * 1000000 + (count % hz) * 1000000 ~/ hz;
        }

        return NativeSamplingClock(
          () => scratch.read(sample),
          ClockCapabilities(
            domain: 'windows.qpc.us.v1',
            resolution: Duration(microseconds: (1000000 / hz).ceil()),
            includesSleep: true,
          ),
        );
      } catch (_) {
        scratch.close();
        rethrow;
      }
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
      final scratch = NativeClockScratch(sizeOf<_Timespec>());
      try {
        final resolution = Duration(
          microseconds: scratch.read((pointer) {
            final value = pointer.cast<_Timespec>();
            if (getres(7, value) != 0) {
              throw StateError('Clock resolution unavailable');
            }
            return value.ref.seconds * 1000000 +
                (value.ref.nanos / 1000).ceil();
          }),
        );
        int sample(Pointer<Void> pointer) {
          final t = pointer.cast<_Timespec>();
          if (gettime(7, t) != 0) {
            throw StateError('CLOCK_BOOTTIME unavailable');
          }
          return t.ref.seconds * 1000000 + t.ref.nanos ~/ 1000;
        }

        final os = Platform.isAndroid ? 'android' : 'linux';
        return NativeSamplingClock(
          () => scratch.read(sample),
          ClockCapabilities(
            domain: '$os.clock_boottime.us.v1',
            resolution: resolution,
            includesSleep: true,
            supportsBootEpoch: true,
          ),
        );
      } catch (_) {
        scratch.close();
        rethrow;
      }
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
      return NativeSamplingClock(
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
