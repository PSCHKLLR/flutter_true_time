/// Whether the current anchor satisfies the configured read policy.
enum TimeAvailability { unavailable, ready, stale }

enum TimeEventKind {
  synchronized,
  restored,
  availabilityChanged,
  syncFailed,
  continuityLost,
  storageFailed,
  persistenceUnavailable,
  wallClockChanged,
  timezoneChanged,
}

class TrustedTimeException implements Exception {
  const TrustedTimeException(this.code, this.message);
  final String code;
  final String message;
  @override
  String toString() => 'TrustedTimeException($code): $message';
}

class TimeReading {
  const TimeReading({
    required this.utc,
    required this.uncertainty,
    required this.anchorAge,
    required this.availability,
    required this.sourceIds,
    required this.providerGroups,
    this.restoredFromStorage = false,
  });
  final bool restoredFromStorage;
  final DateTime utc;
  final Duration uncertainty;
  final Duration anchorAge;
  final TimeAvailability availability;
  final List<String> sourceIds;
  final List<String> providerGroups;
  int get sourceCount => sourceIds.length;
  int get providerGroupCount => providerGroups.length;

  /// Authentication is not implemented in this release.
  bool get isAuthenticated => false;
}

class TimeStatus {
  const TimeStatus(this.availability, this.syncInProgress, this.lastError);
  final TimeAvailability availability;
  final bool syncInProgress;
  final TrustedTimeException? lastError;
}

class TimeEvent {
  const TimeEvent(this.kind, [this.detail]);
  final TimeEventKind kind;
  final String? detail;
}

class SyncOutcome {
  SyncOutcome({
    required this.success,
    required Map<String, String> failures,
    this.error,
  }) : failures = Map.unmodifiable(failures);
  final bool success;
  final Map<String, String> failures;
  final TrustedTimeException? error;
}

class TrustedTimeConfig {
  const TrustedTimeConfig({
    this.refreshInterval = const Duration(minutes: 30),
    this.sourceTimeout = const Duration(seconds: 3),
    this.syncDeadline = const Duration(seconds: 5),
    this.minimumSources = 2,
    this.minimumProviderGroups = 2,
    this.maxAnchorAge = const Duration(hours: 24),
    this.maxUncertainty = const Duration(seconds: 5),
    this.driftPpm = 100,
    this.maxConcurrentSources = 4,
    this.maxRetryDelay = const Duration(minutes: 5),
  });
  final Duration refreshInterval,
      sourceTimeout,
      syncDeadline,
      maxAnchorAge,
      maxUncertainty,
      maxRetryDelay;
  final int minimumSources, minimumProviderGroups, maxConcurrentSources;
  final double driftPpm;
  void validate() {
    if ([
          refreshInterval,
          sourceTimeout,
          syncDeadline,
          maxAnchorAge,
          maxUncertainty,
          maxRetryDelay,
        ].any((d) => d <= Duration.zero) ||
        minimumSources < 1 ||
        minimumProviderGroups < 1 ||
        minimumProviderGroups > minimumSources ||
        maxConcurrentSources < 1 ||
        !driftPpm.isFinite ||
        driftPpm < 0) {
      throw ArgumentError('Invalid trusted time policy');
    }
  }

  @override
  bool operator ==(Object other) =>
      other is TrustedTimeConfig &&
      refreshInterval == other.refreshInterval &&
      sourceTimeout == other.sourceTimeout &&
      syncDeadline == other.syncDeadline &&
      minimumSources == other.minimumSources &&
      minimumProviderGroups == other.minimumProviderGroups &&
      maxAnchorAge == other.maxAnchorAge &&
      maxUncertainty == other.maxUncertainty &&
      driftPpm == other.driftPpm &&
      maxConcurrentSources == other.maxConcurrentSources &&
      maxRetryDelay == other.maxRetryDelay;
  @override
  int get hashCode => Object.hash(
    refreshInterval,
    sourceTimeout,
    syncDeadline,
    minimumSources,
    minimumProviderGroups,
    maxAnchorAge,
    maxUncertainty,
    driftPpm,
    maxConcurrentSources,
    maxRetryDelay,
  );
}
