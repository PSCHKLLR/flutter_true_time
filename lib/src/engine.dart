import 'dart:async';
import 'dart:collection';
import 'dart:math';
import 'cancellation.dart';
import 'clock.dart';
import 'diagnostics.dart';
import 'models.dart';
import 'persistence.dart';
import 'sources.dart';
import 'provider_group.dart';

abstract interface class ScheduledTask {
  void cancel();
}

abstract interface class TimeScheduler {
  ScheduledTask schedule(Duration delay, void Function() callback);
}

class TimerScheduler implements TimeScheduler {
  @override
  ScheduledTask schedule(Duration delay, void Function() callback) =>
      _TimerTask(Timer(delay, callback));
}

class _TimerTask implements ScheduledTask {
  _TimerTask(this.timer);
  final Timer timer;
  @override
  void cancel() => timer.cancel();
}

class _Anchor {
  _Anchor(
    this.utc,
    this.at,
    this.uncertainty,
    this.sources,
    this.groups, {
    this.restored = false,
  });
  final DateTime utc;
  final ClockSnapshot at;
  final Duration uncertainty;
  final List<String> sources, groups;
  final bool restored;
}

class _Cycle {
  _Cycle(this.generation);
  final int generation;
  final CancellationSignal signal = CancellationSignal();
}

/// Permits belong to the real source Future, not its timeout wrapper. Even a
/// non-cooperative custom source cannot inflate concurrency across cycles.
class _QueryPool {
  _QueryPool(this.limit);
  final int limit;
  int _used = 0;
  final Set<Completer<void>> _waiters = {};
  Future<void> acquire(CancellationSignal signal) async {
    signal.throwIfCancelled();
    while (_used >= limit) {
      final waiter = Completer<void>();
      _waiters.add(waiter);
      try {
        await signal.race(waiter.future);
      } finally {
        _waiters.remove(waiter);
      }
      signal.throwIfCancelled();
    }
    signal.throwIfCancelled();
    _used++;
  }

  void release() {
    _used--;
    for (final waiter in List<Completer<void>>.of(_waiters)) {
      if (!waiter.isCompleted) waiter.complete();
    }
  }
}

class TrueTimeEngine {
  /// Bounds collection and post-deadline consensus finalization work.
  static const maximumSources = 1024;

  TrueTimeEngine({
    required List<TimeSource> sources,
    MonotonicClock? clock,
    this.config = const TrueTimeConfig(),
    AnchorStore? store,
    this.epochProvider = const UnknownBootEpochProvider(),
    TimeScheduler? scheduler,
    Random? random,
    this.autoRefresh = true,
    this.wallClock,
    this.diagnosticInterval = const Duration(seconds: 30),
    this.wallClockJumpThreshold = const Duration(seconds: 2),
    bool foreground = true,
  }) : sources = List.unmodifiable(sources),
       clock = clock ?? createPlatformClock(),
       store = store == null ? null : SerializingAnchorStore.wrap(store),
       _scheduler = scheduler ?? TimerScheduler(),
       _random = random ?? Random(),
       _foreground = foreground,
       _pool = _QueryPool(config.maxConcurrentSources) {
    config.validate();
    if (sources.length > maximumSources) {
      throw ArgumentError.value(
        sources.length,
        'sources',
        'At most $maximumSources sources are supported',
      );
    }
    if (diagnosticInterval <= Duration.zero ||
        wallClockJumpThreshold <= Duration.zero) {
      throw ArgumentError('Diagnostic durations must be positive');
    }
    final ids = <String>{}, endpoints = <String>{};
    for (final source in sources) {
      if (source.id.isEmpty ||
          source.endpoint.isEmpty ||
          source.configurationKey.isEmpty ||
          !ids.add(source.id) ||
          !endpoints.add(source.endpoint.toLowerCase())) {
        throw ArgumentError(
          'Source ids, endpoints, and configuration identities must be valid and unique',
        );
      }
    }
  }
  final List<TimeSource> sources;
  final MonotonicClock clock;
  final TrueTimeConfig config;
  final AnchorStore? store;
  final BootEpochProvider epochProvider;
  final bool autoRefresh;
  final WallClockReader? wallClock;
  final Duration diagnosticInterval, wallClockJumpThreshold;
  final TimeScheduler _scheduler;
  final Random _random;
  final _QueryPool _pool;
  final _events = StreamController<TimeEvent>.broadcast();
  final _lifetime = CancellationSignal();
  Stream<TimeEvent> get events => _events.stream;
  _Anchor? _anchor;
  ClockSnapshot? _lastSnapshot;
  BootEpoch? _epoch;
  Future<void>? _epochLookup;
  Future<void>? _initialization;
  Future<SyncOutcome>? _inFlight;
  Completer<SyncOutcome>? _replacement;
  _Cycle? _active;
  ScheduledTask? _refresh, _diagnostic;
  WallClockSample? _previousWall;
  ClockSnapshot? _previousWallMono;
  bool _disposed = false, _foreground;
  int _generation = 0, _failureCount = 0, _sequence = 0;
  TimeAvailability _reportedAvailability = TimeAvailability.unavailable;
  TrueTimeException? _lastError;
  late final String _fingerprint =
      trustPolicyFingerprint(sources.map((s) => s.configurationKey).toList(), [
        clock.capabilities.domain,
        config.minimumSources,
        config.minimumProviderGroups,
        config.driftPpm,
        config.maxAnchorAge.inMicroseconds,
        config.maxUncertainty.inMicroseconds,
      ]);

  void _checkOpen() {
    if (_disposed) {
      throw const TrueTimeException('disposed', 'Clock has been disposed');
    }
  }

  void _emit(TimeEventKind kind, [String? detail]) {
    if (!_disposed) _events.add(TimeEvent(kind, detail));
  }

  void _availability(TimeAvailability value) {
    if (value == _reportedAvailability) return;
    _reportedAvailability = value;
    _emit(TimeEventKind.availabilityChanged, value.name);
  }

  ClockSnapshot _snapshot() {
    final next = clock.snapshot(), previous = _lastSnapshot;
    if (next.elapsed < Duration.zero || next.uncertainty < Duration.zero) {
      throw const TrueTimeException(
        'invalidClock',
        'Negative monotonic reading or error',
      );
    }
    if (previous != null &&
        (previous.sessionId != next.sessionId ||
            next.elapsed < previous.elapsed)) {
      _loseContinuity('Monotonic epoch changed or regressed');
    }
    _lastSnapshot = next;
    return next;
  }

  void _loseContinuity(String reason) {
    _anchor = null;
    _epoch = null;
    _epochLookup = null;
    _generation++;
    _active?.signal.cancel('continuityLost');
    _availability(TimeAvailability.unavailable);
    _emit(TimeEventKind.continuityLost, reason);
    if (autoRefresh && _foreground && _initialization != null) {
      _schedule(const Duration(milliseconds: 1));
    }
  }

  Future<void> _ensureEpoch() {
    if (store == null || _disposed) return Future<void>.value();
    final existing = _epochLookup;
    if (existing != null) return existing;
    // Publish the shared future before invoking injected provider code.
    final completion = Completer<void>();
    _epochLookup = completion.future;
    unawaited(
      _lookupEpoch(_generation).then<void>(
        (_) => completion.complete(),
        onError: (Object error, StackTrace stack) =>
            completion.completeError(error, stack),
      ),
    );
    return completion.future;
  }

  Future<void> _lookupEpoch(int lookupGeneration) async {
    if (!clock.capabilities.supportsBootEpoch || !clock.includesSleep) {
      _emit(
        TimeEventKind.persistenceUnavailable,
        'Clock has no verified cross-process epoch',
      );
      return;
    }
    try {
      final epoch = await _lifetime.withTimeout(
        epochProvider.currentEpoch(clock.capabilities),
        config.sourceTimeout,
      );
      if (_disposed || lookupGeneration != _generation) return;
      if (epoch != null &&
          epoch.isValid &&
          epoch.clockDomain == clock.capabilities.domain) {
        _epoch = epoch;
      } else {
        _emit(
          TimeEventKind.persistenceUnavailable,
          'Verified epoch unavailable; fresh synchronization required after restart',
        );
      }
    } catch (_) {
      if (_disposed || lookupGeneration != _generation) return;
      _emit(
        TimeEventKind.persistenceUnavailable,
        'Epoch lookup failed; fresh synchronization required',
      );
    }
  }

  Future<void> initialize() {
    _checkOpen();
    return _initialization ??= _initialize();
  }

  Future<void> _initialize() async {
    final restorationGeneration = _generation;
    await _ensureEpoch();
    if (store != null && !_disposed) {
      try {
        final value = await _lifetime.withTimeout(
          store!.load(),
          config.sourceTimeout,
        );
        if (!_disposed &&
            value != null &&
            _anchor == null &&
            restorationGeneration == _generation) {
          final record = AnchorRecord.fromMap(value), current = _snapshot();
          final acceptedIds = sources.map((s) => s.id).toSet();
          final acceptedGroups = sources
              .map((s) => knownProviderGroup(s.providerGroup))
              .whereType<String>()
              .toSet();
          if (_epoch != null &&
              record.epoch == _epoch &&
              record.clockDomain == clock.capabilities.domain &&
              record.policyFingerprint == _fingerprint &&
              record.sourceIds.length >= config.minimumSources &&
              record.providerGroups.length >= config.minimumProviderGroups &&
              record.sourceIds.every(acceptedIds.contains) &&
              record.providerGroups.every(acceptedGroups.contains) &&
              _sameSelectedGroups(record) &&
              current.elapsed >= record.monotonic &&
              record.uncertainty <= config.maxUncertainty) {
            final age = current.elapsed - record.monotonic;
            final error = _uncertainty([
              record.uncertainty,
              current.uncertainty,
              _drift(age),
            ]);
            if (age <= config.maxAnchorAge && error <= config.maxUncertainty) {
              _sequence = max(_sequence, record.sequence);
              _anchor = _Anchor(
                record.utc,
                ClockSnapshot(record.monotonic, current.sessionId),
                record.uncertainty,
                record.sourceIds,
                record.providerGroups,
                restored: true,
              );
              _emit(TimeEventKind.restored);
              estimate();
            }
          }
        }
      } catch (_) {
        _emit(
          TimeEventKind.storageFailed,
          'Stored anchor unavailable, invalid, or incompatible',
        );
      }
    }
    if (!_disposed && _foreground) {
      unawaited(sync());
      _startDiagnostics();
    }
  }

  bool _sameSelectedGroups(AnchorRecord record) {
    final byId = {for (final source in sources) source.id: source};
    final selected = record.sourceIds
        .map((id) => knownProviderGroup(byId[id]!.providerGroup))
        .whereType<String>()
        .toSet();
    return selected.length == record.providerGroups.length &&
        record.providerGroups.every(selected.contains);
  }

  Duration _uncertainty(List<Duration> terms) {
    final limit = TrueTimeConfig.maximumUncertainty.inMicroseconds;
    var total = 0;
    for (final term in terms) {
      final value = term.inMicroseconds;
      // Check before adding: native integers can wrap and JS can lose bits.
      if (value < 0 || value > limit - total) {
        throw const TrueTimeException(
          'uncertain',
          'Uncertainty exceeds supported range',
        );
      }
      total += value;
    }
    return Duration(microseconds: total);
  }

  Duration _drift(Duration elapsed) {
    final value = elapsed.inMicroseconds * config.driftPpm / 1000000;
    if (!value.isFinite ||
        value < 0 ||
        value > TrueTimeConfig.maximumUncertainty.inMicroseconds) {
      throw const TrueTimeException(
        'uncertain',
        'Drift exceeds supported range',
      );
    }
    return Duration(microseconds: value.ceil());
  }

  TimeReading? estimate() {
    _checkOpen();
    final snapshot = _snapshot(), anchor = _anchor;
    if (anchor == null ||
        (!clock.includesSleep && !_foreground) ||
        anchor.at.sessionId != snapshot.sessionId ||
        snapshot.elapsed < anchor.at.elapsed) {
      _availability(TimeAvailability.unavailable);
      return null;
    }
    final age = snapshot.elapsed - anchor.at.elapsed;
    final error = _uncertainty([
      anchor.uncertainty,
      snapshot.uncertainty,
      _drift(age),
    ]);
    final availability =
        age > config.maxAnchorAge || error > config.maxUncertainty
        ? TimeAvailability.stale
        : TimeAvailability.ready;
    _availability(availability);
    return TimeReading(
      utc: anchor.utc.add(age),
      uncertainty: error,
      anchorAge: age,
      availability: availability,
      sourceIds: anchor.sources,
      providerGroups: anchor.groups,
      restoredFromStorage: anchor.restored,
    );
  }

  TimeReading read() =>
      estimate() ??
      (throw const TrueTimeException(
        'unavailable',
        'No continuous UTC anchor',
      ));
  DateTime now() {
    final r = read();
    if (r.availability != TimeAvailability.ready) {
      throw const TrueTimeException(
        'stale',
        'UTC anchor exceeds accuracy or freshness policy',
      );
    }
    return r.utc;
  }

  TimeStatus get status => TimeStatus(
    estimate()?.availability ?? TimeAvailability.unavailable,
    _inFlight != null || _replacement != null,
    _lastError,
  );
  bool get isTrusted => status.availability == TimeAvailability.ready;

  /// Waits for a reading that satisfies the policy at its sampled instant.
  /// Each check validates and returns the same reading; the anchor can expire
  /// after sampling, so callers must obtain another reading for later work.
  Future<TimeReading> waitUntilReady({
    Duration timeout = const Duration(seconds: 5),
  }) async {
    _checkOpen();
    if (timeout <= Duration.zero) throw ArgumentError.value(timeout, 'timeout');
    final candidate = estimate();
    if (candidate?.availability == TimeAvailability.ready) return candidate!;
    final ready = Completer<TimeReading>();
    void check() {
      if (ready.isCompleted || _disposed) return;
      try {
        final candidate = estimate();
        if (candidate?.availability == TimeAvailability.ready) {
          ready.complete(candidate!);
        }
      } catch (error, stack) {
        // Event/initialization callbacks must deliver sampling failures to the
        // waiting caller rather than leaking them into the callback's zone.
        ready.completeError(error, stack);
      }
    }

    final subscription = events.listen(
      (_) => check(),
      onDone: () {
        if (!ready.isCompleted) {
          ready.completeError(
            const TrueTimeException('disposed', 'Clock disposed while waiting'),
          );
        }
      },
    );
    unawaited(
      initialize().then(
        (_) => check(),
        onError: (Object e, StackTrace s) {
          if (!ready.isCompleted) ready.completeError(e, s);
        },
      ),
    );
    try {
      return await ready.future.timeout(
        timeout,
        onTimeout: () => throw const TrueTimeException(
          'notReady',
          'Timed out waiting for a usable anchor',
        ),
      );
    } finally {
      await subscription.cancel();
    }
  }

  Future<SyncOutcome> forceResync() => sync();
  Future<SyncOutcome> sync() {
    _checkOpen();
    if (_inFlight != null) {
      if (_active!.signal.isCancelled && _foreground) {
        return (_replacement ??= Completer<SyncOutcome>()).future;
      }
      return _inFlight!;
    }
    return _launch();
  }

  Future<SyncOutcome> _launch() {
    _refresh?.cancel();
    final cycle = _Cycle(_generation), completion = Completer<SyncOutcome>();
    _active = cycle;
    _inFlight = completion.future;
    unawaited(_drive(cycle, completion));
    return completion.future;
  }

  Future<void> _drive(_Cycle cycle, Completer<SyncOutcome> completion) async {
    SyncOutcome outcome;
    try {
      outcome = await _runSync(cycle);
    } catch (e) {
      outcome = SyncOutcome(
        success: false,
        failures: const {},
        error: e is TrueTimeException
            ? e
            : TrueTimeException('syncFailed', e.toString()),
      );
    }
    _active = null;
    _inFlight = null;
    final replacement = _replacement;
    _replacement = null;
    try {
      if (replacement != null) {
        if (!_disposed && _foreground) {
          _launch().then(
            replacement.complete,
            onError: replacement.completeError,
          );
        } else {
          replacement.complete(
            SyncOutcome(
              success: false,
              failures: const {},
              error: const TrueTimeException(
                'cancelled',
                'Clock is disposed or backgrounded',
              ),
            ),
          );
        }
      } else if (!_disposed && _foreground) {
        if (outcome.success) {
          _failureCount = 0;
          _schedule(config.refreshInterval);
        } else {
          _failureCount++;
          final cap = min(
            config.maxRetryDelay.inMilliseconds,
            1000 * pow(2, min(_failureCount - 1, 20)),
          ).toInt();
          _schedule(
            Duration(
              milliseconds: max(1, (_random.nextDouble() * cap).round()),
            ),
          );
        }
      }
    } catch (_) {
      _emit(TimeEventKind.schedulingFailed, 'Post-sync scheduling failed');
      if (replacement != null && !replacement.isCompleted) {
        replacement.complete(
          SyncOutcome(
            success: false,
            failures: const {},
            error: const TrueTimeException(
              'schedulingFailed',
              'Replacement cycle could not start',
            ),
          ),
        );
      }
    } finally {
      // Optional scheduling must never strand a completed network cycle.
      completion.complete(outcome);
    }
  }

  Future<TimeSample> _query(
    TimeSource source,
    _Cycle cycle,
    void Function() checkDeadline,
  ) async {
    await _pool.acquire(cycle.signal);
    final signal = CancellationSignal();
    final detach = cycle.signal.onCancel(
      () => signal.cancel(cycle.signal.reason),
    );
    final actual = Future<TimeSample>.sync(() {
      checkDeadline();
      signal.throwIfCancelled();
      return source.query(clock, config.sourceTimeout, cancellation: signal);
    });
    void settled() {
      detach();
      _pool.release();
    }

    unawaited(
      actual.then<void>(
        (_) => settled(),
        onError: (Object _, StackTrace _) => settled(),
      ),
    );
    try {
      return await signal
          .race(actual)
          .timeout(
            config.sourceTimeout,
            onTimeout: () {
              signal.cancel('sourceTimeout');
              throw const TrueTimeException(
                'sourceTimeout',
                'Source query timed out',
              );
            },
          );
    } finally {
      /* The REAL operation retains its permit until it settles. */
    }
  }

  Future<SyncOutcome> _runSync(_Cycle cycle) async {
    final budget = Stopwatch()..start();
    void checkDeadline() {
      if (budget.elapsed >= config.syncDeadline) {
        cycle.signal.cancel('deadline');
      }
    }

    final deadline = Timer(
      config.syncDeadline,
      () => cycle.signal.cancel('deadline'),
    );
    final failures = <String, String>{};
    final samples = <({TimeSource source, TimeSample sample})>[];
    final endpoints = <String>{};
    try {
      await cycle.signal.race(_ensureEpoch());
      final initial = _snapshot();
      if (cycle.generation != _generation) {
        cycle.signal.cancel('continuityLost');
      }
      cycle.signal.throwIfCancelled();
      var cursor = 0;
      Future<void> worker() async {
        var sinceYield = 0;
        while (!cycle.signal.isCancelled &&
            !_disposed &&
            cursor < sources.length) {
          checkDeadline();
          if (cycle.signal.isCancelled) break;
          final source = sources[cursor++];
          try {
            final sample = await _query(source, cycle, checkDeadline);
            checkDeadline();
            cycle.signal.throwIfCancelled();
            if (!sample.utc.isUtc ||
                sample.utc.year < 2020 ||
                sample.utc.year > 2100 ||
                sample.uncertainty < Duration.zero ||
                sample.at.uncertainty < Duration.zero ||
                sample.uncertainty > config.maxUncertainty ||
                sample.at.sessionId != initial.sessionId ||
                sample.at.elapsed < initial.elapsed) {
              throw const TrueTimeException(
                'invalidSample',
                'Sample violates clock or uncertainty policy',
              );
            }
            if (!endpoints.add(
              (sample.endpointIdentity ?? source.endpoint).toLowerCase(),
            )) {
              throw const TrueTimeException(
                'duplicateEndpoint',
                'Resolved endpoint already contributed',
              );
            }
            samples.add((source: source, sample: sample));
          } catch (e) {
            failures[source.id] = e.toString();
          }
          // Give timers/lifecycle callbacks a turn even for immediate sources.
          if (++sinceYield == 32) {
            sinceYield = 0;
            await Future<void>.delayed(Duration.zero);
          }
        }
      }

      await Future.wait(
        List.generate(
          min(sources.length, config.maxConcurrentSources),
          (_) => worker(),
        ),
      );
      // A deadline closes collection, but already accepted evidence remains usable.
      if (cycle.signal.isCancelled && cycle.signal.reason != 'deadline') {
        cycle.signal.throwIfCancelled();
      }
      final reference = _snapshot();
      if (cycle.generation != _generation ||
          reference.sessionId != initial.sessionId ||
          (!clock.includesSleep && !_foreground)) {
        throw const TrueTimeException(
          'continuityLost',
          'Clock continuity changed during synchronization',
        );
      }
      final anchor = _consensus(samples, reference, checkDeadline);
      _anchor = anchor;
      _lastError = null;
      estimate();
      _emit(TimeEventKind.synchronized);
      if (store != null) {
        _sequence = _sequence == AnchorRecord.maxSequence ? 1 : _sequence + 1;
        final record = AnchorRecord(
          utc: anchor.utc,
          monotonic: anchor.at.elapsed,
          uncertainty: anchor.uncertainty,
          clockDomain: clock.capabilities.domain,
          policyFingerprint: _fingerprint,
          sequence: _sequence,
          sourceIds: anchor.sources,
          providerGroups: anchor.groups,
          epoch: _epoch,
        );
        final observation = _observeSave(record);
        if (budget.elapsed < config.syncDeadline && !cycle.signal.isCancelled) {
          try {
            await cycle.signal.race(observation);
          } on TrueTimeException {
            // The cycle ended, but the serialized write remains observed.
          }
        }
      }
      if (_disposed ||
          cycle.generation != _generation ||
          cycle.signal.isCancelled && cycle.signal.reason != 'deadline') {
        throw const TrueTimeException(
          'cancelled',
          'Cycle invalidated before completion',
        );
      }
      return SyncOutcome(success: true, failures: failures);
    } catch (e) {
      final error = _disposed
          ? const TrueTimeException(
              'disposed',
              'Clock disposed during synchronization',
            )
          : e is TrueTimeException
          ? e
          : TrueTimeException('syncFailed', e.toString());
      if (!_disposed) {
        _lastError = error;
        _emit(TimeEventKind.syncFailed, error.toString());
      }
      return SyncOutcome(success: false, failures: failures, error: error);
    } finally {
      deadline.cancel();
      cycle.signal.cancel('completed');
    }
  }

  Future<void> _observeSave(AnchorRecord record) async {
    try {
      await _lifetime.withTimeout(
        store!.save(record.toMap()),
        config.sourceTimeout,
      );
    } catch (_) {
      _emit(
        TimeEventKind.storageFailed,
        'Anchor retained in memory; persistence failed, timed out, or was superseded',
      );
    }
  }

  _Anchor _consensus(
    List<({TimeSource source, TimeSample sample})> samples,
    ClockSnapshot reference,
    void Function() checkDeadline,
  ) {
    final intervals = <({BigInt low, BigInt high, TimeSource source})>[];
    for (final item in samples) {
      checkDeadline();
      final elapsed = reference.elapsed - item.sample.at.elapsed;
      if (elapsed < Duration.zero) continue;
      final center =
          BigInt.from(item.sample.utc.microsecondsSinceEpoch) +
          BigInt.from(elapsed.inMicroseconds);
      final width = BigInt.from(
        _uncertainty([
          item.sample.uncertainty,
          item.sample.at.uncertainty,
          reference.uncertainty,
          _drift(elapsed),
        ]).inMicroseconds,
      );
      intervals.add((
        low: center - width,
        high: center + width,
        source: item.source,
      ));
    }
    // Add starts before considering a point, then remove ends: closed intervals
    // that touch count together. Every open-span active set is a subset of an
    // endpoint set, so a maximum-support quorum always occurs at an endpoint.
    final events = <BigInt, ({List<int> starts, List<int> ends})>{};
    for (var i = 0; i < intervals.length; i++) {
      (events[intervals[i].low] ??= (starts: [], ends: [])).starts.add(i);
      (events[intervals[i].high] ??= (starts: [], ends: [])).ends.add(i);
    }
    final points = events.keys.toList()..sort();
    final lows = SplayTreeMap<BigInt, int>(),
        highs = SplayTreeMap<BigInt, int>();
    final groups = <String, int>{};
    final providerGroups = intervals
        .map((i) => knownProviderGroup(i.source.providerGroup))
        .toList();
    var activeCount = 0, bestCount = 0, ambiguous = false;
    BigInt? winner, low, high;
    void adjust<K>(Map<K, int> counts, K key, int delta) {
      final count = (counts[key] ?? 0) + delta;
      if (count == 0) {
        counts.remove(key);
      } else {
        counts[key] = count;
      }
    }

    void change(int index, int delta) {
      final interval = intervals[index];
      activeCount += delta;
      adjust(lows, interval.low, delta);
      adjust(highs, interval.high, delta);
      final group = providerGroups[index];
      if (group != null) adjust(groups, group, delta);
    }

    for (final point in points) {
      checkDeadline();
      final event = events[point]!;
      for (final index in event.starts) {
        change(index, 1);
      }
      if (activeCount >= config.minimumSources &&
          groups.length >= config.minimumProviderGroups) {
        final a = lows.lastKey()!, b = highs.firstKey()!;
        if (activeCount > bestCount) {
          bestCount = activeCount;
          winner = point;
          low = a;
          high = b;
          ambiguous = false;
        } else if (activeCount == bestCount && (a > high! || b < low!)) {
          ambiguous = true;
        }
      }
      for (final index in event.ends) {
        change(index, -1);
      }
    }
    if (winner == null) {
      throw const TrueTimeException('noConsensus', 'No group-diverse quorum');
    }
    if (ambiguous) {
      throw const TrueTimeException(
        'ambiguousConsensus',
        'Equally supported disjoint intervals',
      );
    }
    // Materialize evidence once, only for the first winning endpoint.
    final first = intervals
        .where((i) => i.low <= winner! && winner <= i.high)
        .toList();
    BigInt larger(BigInt a, BigInt b) => a > b ? a : b;
    final width = larger(
      (high! - low! + BigInt.one) ~/ BigInt.two,
      BigInt.from(
        _uncertainty([
          reference.uncertainty,
          clock.capabilities.resolution,
        ]).inMicroseconds,
      ),
    );
    final center = (low + high) ~/ BigInt.two;
    if (width > BigInt.from(config.maxUncertainty.inMicroseconds) ||
        center.abs() >
            BigInt.from(TrueTimeConfig.maximumUncertainty.inMicroseconds)) {
      throw const TrueTimeException(
        'uncertain',
        'Consensus exceeds uncertainty policy',
      );
    }
    return _Anchor(
      DateTime.fromMicrosecondsSinceEpoch(center.toInt(), isUtc: true),
      reference,
      Duration(microseconds: width.toInt()),
      List.unmodifiable(first.map((i) => i.source.id).toList()..sort()),
      List.unmodifiable(
        first
            .map((i) => knownProviderGroup(i.source.providerGroup))
            .whereType<String>()
            .toSet()
            .toList()
          ..sort(),
      ),
    );
  }

  void _schedule(Duration delay) {
    _refresh?.cancel();
    if (autoRefresh && !_disposed && _foreground) {
      _refresh = _registerTask(delay, () {
        if (!_disposed && _foreground) unawaited(sync());
      }, 'Automatic refresh');
    }
  }

  ScheduledTask? _registerTask(
    Duration delay,
    void Function() callback,
    String purpose,
  ) {
    try {
      return _scheduler.schedule(delay, callback);
    } catch (_) {
      _emit(TimeEventKind.schedulingFailed, '$purpose registration failed');
      return null;
    }
  }

  /// Informational diagnostics never advance or invalidate a UTC anchor.
  /// Failed wall-clock reads skip the poll and reset its diagnostic baseline.
  /// Scheduled polling retries at the next interval without emitting a change.
  void pollDiagnostics() {
    _checkOpen();
    if (!_foreground || wallClock == null) return;
    final WallClockSample wall;
    try {
      wall = wallClock!.read();
    } catch (_) {
      // Optional diagnostics must not block initialization, resume, or polling.
      _previousWall = null;
      _previousWallMono = null;
      return;
    }
    final mono = _snapshot();
    final previous = _previousWall, previousMono = _previousWallMono;
    if (previous != null &&
        previousMono != null &&
        mono.sessionId == previousMono.sessionId &&
        mono.elapsed >= previousMono.elapsed) {
      final deviation =
          wall.utc.difference(previous.utc) -
          (mono.elapsed - previousMono.elapsed);
      if (deviation.abs() >
          wallClockJumpThreshold +
              mono.uncertainty +
              previousMono.uncertainty) {
        _emit(TimeEventKind.wallClockChanged);
      }
      if (wall.offset != previous.offset || wall.zone != previous.zone) {
        _emit(TimeEventKind.timezoneChanged);
      }
    }
    _previousWall = wall;
    _previousWallMono = mono;
  }

  void _startDiagnostics() {
    _diagnostic?.cancel();
    if (_disposed || !_foreground || wallClock == null) return;
    pollDiagnostics();
    _diagnostic = _registerTask(
      diagnosticInterval,
      _startDiagnostics,
      'Diagnostic poll',
    );
  }

  void suspend() {
    _checkOpen();
    _foreground = false;
    _refresh?.cancel();
    _diagnostic?.cancel();
    _previousWall = null;
    _previousWallMono = null;
    if (!clock.includesSleep) _loseContinuity('Session-only clock suspended');
  }

  void resume() {
    _checkOpen();
    _foreground = true;
    _startDiagnostics();
    unawaited(sync());
  }

  void invalidateContinuity() {
    _checkOpen();
    _loseContinuity('Caller invalidated clock continuity');
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _generation++;
    _anchor = null;
    _refresh?.cancel();
    _diagnostic?.cancel();
    _lifetime.cancel('disposed');
    _active?.signal.cancel('disposed');
    // A paused external subscriber must not block releasing engine resources.
    unawaited(_events.close());
  }
}
