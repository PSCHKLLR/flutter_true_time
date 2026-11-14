/// Network-derived UTC for Flutter apps, with freshness and uncertainty.
///
/// Initialize [TrueTime], wait for a usable anchor, and call
/// [TrueTime.read] to read the projected UTC time and its uncertainty.
/// Use [TrueTimeEngine] to manage independent clocks.
library;

export 'src/models.dart';
export 'src/clock.dart';
export 'src/engine.dart';
export 'src/sources.dart';
export 'src/facade.dart';

export 'src/cancellation.dart';
export 'src/persistence.dart';
export 'src/diagnostics.dart';

export 'src/secure_store.dart';

export 'src/epoch_platform.dart' show createPlatformEpochProvider;
