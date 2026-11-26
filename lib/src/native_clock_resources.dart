import 'dart:ffi';
import 'dart:math';
import 'package:ffi/ffi.dart';
import 'clock.dart';

/// Internal isolate-local scratch owner. Pointers must not escape [read].
/// Finalizable keeps this owner alive during native calls and prevents copying
/// its native pointer to another isolate. Engines never close injected clocks.
class NativeClockScratch implements Finalizable {
  NativeClockScratch(this.byteLength)
    : _pointer = calloc.allocate<Uint8>(byteLength) {
    try {
      _finalizer.attach(
        this,
        _pointer.cast(),
        detach: this,
        externalSize: byteLength,
      );
    } catch (_) {
      calloc.free(_pointer);
      rethrow;
    }
  }
  static final _finalizer = NativeFinalizer(calloc.nativeFree);
  final int byteLength;
  final Pointer<Uint8> _pointer;
  bool _busy = false, _closed = false;

  int read(int Function(Pointer<Void>) action) {
    if (_closed) throw StateError('Native scratch is closed');
    if (_busy) {
      final temporary = calloc.allocate<Uint8>(byteLength);
      try {
        return action(temporary.cast());
      } finally {
        calloc.free(temporary);
      }
    }
    _busy = true;
    try {
      return action(_pointer.cast());
    } finally {
      _busy = false;
    }
  }

  /// Used for construction failures/tests, not by engine disposal.
  void close() {
    if (_closed) return;
    if (_busy) throw StateError('Cannot close scratch during a read');
    _closed = true;
    _finalizer.detach(this);
    calloc.free(_pointer);
  }
}

/// Internal native sampler. Reuses its overhead watch only on nonnested reads.
/// Every returned snapshot stays immutable; nested calls own a separate watch.
class NativeSamplingClock implements MonotonicClock {
  NativeSamplingClock(this._micros, this.capabilities) {
    _micros();
  }
  final int Function() _micros;
  @override
  final ClockCapabilities capabilities;
  final _watch = Stopwatch();
  bool _sampling = false;
  final String _id =
      Random.secure().nextInt(0x7fffffff).toString() +
      identityHashCode(Object()).toString();
  @override
  bool get includesSleep => capabilities.includesSleep;
  @override
  ClockSnapshot snapshot() {
    final nested = _sampling;
    final watch = nested ? Stopwatch() : _watch;
    _sampling = true;
    try {
      watch
        ..reset()
        ..start();
      final value = _micros();
      watch.stop();
      return ClockSnapshot(
        Duration(microseconds: value),
        _id,
        uncertainty: capabilities.resolution + watch.elapsed,
      );
    } finally {
      watch.stop();
      _sampling = nested;
    }
  }
}
