import 'dart:async';
import 'models.dart';

/// Cooperative cancellation. Register resource cleanup before starting I/O.
class CancellationSignal {
  bool _cancelled = false;
  String _reason = 'cancelled';
  final Set<void Function()> _listeners = {};
  bool get isCancelled => _cancelled;
  String get reason => _reason;
  void throwIfCancelled() {
    if (_cancelled) throw TrueTimeException('cancelled', _reason);
  }

  void Function() onCancel(void Function() listener) {
    if (_cancelled) {
      listener();
      return () {};
    }
    _listeners.add(listener);
    return () {
      _listeners.remove(listener);
    };
  }

  void cancel([String reason = 'cancelled']) {
    if (_cancelled) return;
    _cancelled = true;
    _reason = reason;
    final callbacks = List<void Function()>.of(_listeners);
    _listeners.clear();
    for (final callback in callbacks) {
      try {
        callback();
      } catch (_) {
        /* Continue releasing other resources. */
      }
    }
  }

  void _checkOperation<T>(Future<T> operation) {
    if (!_cancelled) return;
    // The caller has already started this future. Observe it even though the
    // wrapper rejects synchronously, without adding a timer or cancel listener.
    unawaited(
      operation.then<void>((_) {}, onError: (Object _, StackTrace _) {}),
    );
    throwIfCancelled();
  }

  /// Observes [operation] even if cancellation already occurred. In that case,
  /// throws synchronously; the underlying operation is not stopped.
  Future<T> race<T>(Future<T> operation) {
    _checkOperation(operation);
    final result = Completer<T>();
    final detach = onCancel(() {
      if (!result.isCompleted) {
        result.completeError(TrueTimeException('cancelled', _reason));
      }
    });
    operation
        .then(
          (value) {
            if (!result.isCompleted) result.complete(value);
          },
          onError: (Object error, StackTrace stack) {
            if (!result.isCompleted) result.completeError(error, stack);
          },
        )
        .whenComplete(detach);
    return result.future;
  }

  /// Deadline wrapper whose timer is released on cancellation as well as result.
  /// It deliberately does not cancel an opaque storage backend operation.
  /// An already-cancelled signal throws synchronously while still observing
  /// the supplied operation, without creating a deadline timer.
  Future<T> withTimeout<T>(Future<T> operation, Duration timeout) {
    _checkOperation(operation);
    final result = Completer<T>();
    final timer = Timer(timeout, () {
      if (!result.isCompleted) {
        result.completeError(
          const TrueTimeException('timeout', 'Operation exceeded its deadline'),
        );
      }
    });
    final detach = onCancel(() {
      timer.cancel();
      if (!result.isCompleted) {
        result.completeError(TrueTimeException('cancelled', _reason));
      }
    });
    operation.then(
      (value) {
        if (!result.isCompleted) result.complete(value);
      },
      onError: (Object error, StackTrace stack) {
        if (!result.isCompleted) result.completeError(error, stack);
      },
    );
    return result.future.whenComplete(() {
      timer.cancel();
      detach();
    });
  }
}
