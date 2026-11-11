# Migration to flutter_true_time 0.1.0-dev.1

This is a new package identity, not a compatible update to the existing pub.dev trusted_time package.

- Change the dependency name and import to flutter_true_time and package:flutter_true_time/flutter_true_time.dart. Use core.dart for the injectable engine without the Flutter facade.
- Require Flutter >=3.41.0 and Dart >=3.11.0. Resolve dependencies with the SDK actually being tested; do not reuse a newer SDK's lockfile as minimum-version evidence.
- Strict now() throws for unavailable or stale time. read() includes metadata, estimate() returns null without continuity, and no API silently uses system time.
- Opt into secure persistence with PersistenceConfig(namespace: 'your.unique.application'). Android/Linux restore only within a verified boot; Apple/Windows/web restart behavior is intentionally fail-closed by default.
- Custom TimeSource implementations must add an immutable configurationKey and accept CancellationSignal? cancellation in query(). Register transport cleanup before I/O and honor the provided timeout/cancellation.
- Custom MonotonicClock implementations must expose ClockCapabilities and sample uncertainty. Set supportsBootEpoch only when the paired BootEpochProvider is qualified for that exact clock domain.
- Injected stores still read/write maps, but records must use AnchorRecord's version-2 schema. Version-1 records are discarded. SerializingAnchorStore preserves ordering across engines sharing the same backend object.
- The Flutter facade keeps omitted initialization options. Newly supplied equivalent source values are accepted; explicit conflicting options require dispose() first.
- UTC corrections can go backward. Use a monotonic timer for elapsed durations and a separate identifier/order mechanism for events.

No NTS authLevel, timezone helper, legacy testing override, or OS background-sync API is emulated. isAuthenticated remains false. Use independent injected engines in tests, and dispose every facade instance in tearDown.
