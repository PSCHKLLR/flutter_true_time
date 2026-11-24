import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'clock.dart';
import 'diagnostics.dart';
import 'engine.dart';
import 'epoch_platform.dart';
import 'models.dart';
import 'persistence.dart';
import 'secure_store.dart';
import 'sources.dart';

/// Flutter convenience facade. Core consumers inject independent engines.
class TrueTime {
  TrueTime._();
  static TrueTimeEngine? _engine;
  static _ClockLifecycle? _lifecycle;
  static PersistenceConfig? _persistence;
  static MonotonicClock? _clockArgument;
  static AnchorStore? _storeArgument;
  static BootEpochProvider? _epochArgument;
  static WallClockReader? _wallArgument;
  static TrueTimeEngine get _current =>
      _engine ??
      (throw const TrueTimeException(
        'uninitialized',
        'Call TrueTime.initialize first',
      ));

  /// Omitted options retain an existing initialization; supplied incompatible
  /// options require disposal. Persistence is opt-in with an application namespace.
  static Future<void> initialize({
    TrueTimeConfig? config,
    List<TimeSource>? sources,
    PersistenceConfig? persistence,
    MonotonicClock? clock,
    AnchorStore? store,
    BootEpochProvider? epochProvider,
    WallClockReader? wallClock,
  }) async {
    WidgetsFlutterBinding.ensureInitialized();
    final existing = _engine;
    if (existing != null) {
      final incompatibleSources =
          sources != null &&
          (sources.length != existing.sources.length ||
              sources.asMap().entries.any(
                (e) =>
                    e.value.configurationKey !=
                    existing.sources[e.key].configurationKey,
              ));
      if ((config != null && config != existing.config) ||
          incompatibleSources ||
          (persistence != null && persistence != _persistence) ||
          (clock != null && !identical(clock, _clockArgument)) ||
          (store != null && !identical(store, _storeArgument)) ||
          (epochProvider != null &&
              !identical(epochProvider, _epochArgument)) ||
          (wallClock != null && !identical(wallClock, _wallArgument))) {
        throw const TrueTimeException(
          'configurationConflict',
          'Dispose before reconfiguring',
        );
      }
      return existing.initialize();
    }
    if (kIsWeb && sources == null) {
      throw const TrueTimeException(
        'sourcesRequired',
        'Configure independent, CORS-ready HTTPS Date sources for web',
      );
    }
    final effectiveStore =
        store ??
        (persistence == null ? null : SecureAnchorStore.open(persistence));
    final effectiveEpoch =
        epochProvider ??
        (persistence == null
            ? const UnknownBootEpochProvider()
            : createPlatformEpochProvider(persistence));
    final state = WidgetsBinding.instance.lifecycleState;
    final foreground =
        state == null ||
        state == AppLifecycleState.resumed ||
        state == AppLifecycleState.detached;
    final engine = TrueTimeEngine(
      config: config ?? const TrueTimeConfig(),
      clock: clock,
      sources:
          sources ??
          const [
            NtpSource('time.cloudflare.com', providerGroup: 'cloudflare'),
            NtpSource('ntp.netnod.se', providerGroup: 'netnod'),
          ],
      store: effectiveStore,
      epochProvider: effectiveEpoch,
      wallClock: wallClock ?? SystemWallClockReader(),
      foreground: foreground,
    );
    _engine = engine;
    _persistence = persistence;
    _clockArgument = clock;
    _storeArgument = store;
    _epochArgument = epochProvider;
    _wallArgument = wallClock;
    _lifecycle = _ClockLifecycle(engine);
    WidgetsBinding.instance.addObserver(_lifecycle!);
    await engine.initialize();
  }

  /// Returns the current projected UTC time.
  ///
  /// Throws [TrueTimeException] if the clock is unavailable or stale.
  static DateTime now() => _current.now();

  /// Returns [now] as milliseconds since the Unix epoch.
  static int nowUnixMs() => now().millisecondsSinceEpoch;

  /// Returns [now] formatted as an ISO 8601 UTC string.
  static String nowIso() => now().toIso8601String();

  /// Returns UTC, uncertainty, and source evidence for a usable anchor.
  ///
  /// The result can be stale. Throws [TrueTimeException] if no continuous
  /// anchor exists.
  static TimeReading read() => _current.read();

  /// Returns the current reading, including stale readings, or null when
  /// there is no continuous anchor.
  static TimeReading? estimate() => _current.estimate();

  /// Whether the current reading meets the freshness and uncertainty limits.
  static bool get isTrusted => _engine?.isTrusted ?? false;

  /// Returns the current availability, sync state, and last error.
  static TimeStatus get status => _current.status;

  /// Streams synchronization, persistence, and clock diagnostic events.
  static Stream<TimeEvent> get events => _current.events;

  /// Starts synchronization or joins the cycle already in progress.
  static Future<SyncOutcome> forceResync() => _current.sync();

  /// Waits up to [timeout] for a reading within the configured policy limits.
  /// Returns the same reading sampled as ready; later work needs a new reading.
  static Future<TimeReading> waitUntilReady({
    Duration timeout = const Duration(seconds: 5),
  }) => _current.waitUntilReady(timeout: timeout);

  /// Releases the current engine and removes its Flutter lifecycle observer.
  ///
  /// Call [initialize] again before reading from the facade.
  static Future<void> dispose() async {
    if (_lifecycle != null) WidgetsBinding.instance.removeObserver(_lifecycle!);
    final engine = _engine;
    _engine = null;
    _lifecycle = null;
    _persistence = null;
    _clockArgument = null;
    _storeArgument = null;
    _epochArgument = null;
    _wallArgument = null;
    await engine?.dispose();
  }
}

class _ClockLifecycle extends WidgetsBindingObserver {
  _ClockLifecycle(this.engine);
  final TrueTimeEngine engine;
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      engine.resume();
    } else {
      engine.suspend();
    }
  }
}
