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
class TrustedTime {
  TrustedTime._();
  static TrustedTimeEngine? _engine;
  static _ClockLifecycle? _lifecycle;
  static PersistenceConfig? _persistence;
  static MonotonicClock? _clockArgument;
  static AnchorStore? _storeArgument;
  static BootEpochProvider? _epochArgument;
  static WallClockReader? _wallArgument;
  static TrustedTimeEngine get _current =>
      _engine ??
      (throw const TrustedTimeException(
        'uninitialized',
        'Call TrustedTime.initialize first',
      ));

  /// Omitted options retain an existing initialization; supplied incompatible
  /// options require disposal. Persistence is opt-in with an application namespace.
  static Future<void> initialize({
    TrustedTimeConfig? config,
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
        throw const TrustedTimeException(
          'configurationConflict',
          'Dispose before reconfiguring',
        );
      }
      return existing.initialize();
    }
    if (kIsWeb && sources == null) {
      throw const TrustedTimeException(
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
    final engine = TrustedTimeEngine(
      config: config ?? const TrustedTimeConfig(),
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

  static DateTime now() => _current.now();
  static int nowUnixMs() => now().millisecondsSinceEpoch;
  static String nowIso() => now().toIso8601String();
  static TimeReading read() => _current.read();
  static TimeReading? estimate() => _current.estimate();
  static bool get isTrusted => _engine?.isTrusted ?? false;
  static TimeStatus get status => _current.status;
  static Stream<TimeEvent> get events => _current.events;
  static Future<SyncOutcome> forceResync() => _current.sync();
  static Future<TimeReading> waitUntilReady({
    Duration timeout = const Duration(seconds: 5),
  }) => _current.waitUntilReady(timeout: timeout);
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
  final TrustedTimeEngine engine;
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      engine.resume();
    } else {
      engine.suspend();
    }
  }
}
