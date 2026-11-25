# flutter_true_time

[![pub.dev version](https://img.shields.io/pub/v/flutter_true_time)](https://pub.dev/packages/flutter_true_time)
[![GitHub release](https://img.shields.io/github/v/release/PSCHKLLR/flutter_true_time)](https://github.com/PSCHKLLR/flutter_true_time/releases/latest)

Network-derived UTC timestamps for Flutter, anchored to a monotonic clock with explicit freshness and uncertainty. See [pub.dev](https://pub.dev/packages/flutter_true_time) for published versions.

This is an independently maintained rebuild of the trusted_time design/API baseline. It is not a drop-in replacement or an official upstream release. Historical license and NOTICE attribution is preserved in THIRD_PARTY_NOTICES.md.

## Use in a Flutter app

Version 2.0.0 uses the `TrueTime` API. Versions through 1.0.0 use `TrustedTime`, `TrustedTimeEngine`, `TrustedTimeConfig`, and `TrustedTimeException`. See the [migration guide](https://github.com/PSCHKLLR/flutter_true_time/blob/main/docs/MIGRATION.md) for the breaking rename.

Add the package to your Flutter app:

```yaml
dependencies:
  flutter_true_time: ^2.0.0
```

```dart
import 'package:flutter/widgets.dart';
import 'package:flutter_true_time/flutter_true_time.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await TrueTime.initialize(
    persistence: PersistenceConfig(namespace: 'com.example.my_app'),
  );
  // Initialization starts a sync; it does not imply readiness.
  try {
    await TrueTime.waitUntilReady();
    final reading = TrueTime.read();
    debugPrint(reading.utc.toIso8601String());
    debugPrint('Estimated uncertainty: ' + reading.uncertainty.toString());
  } on TrueTimeException catch (error) {
    debugPrint(error.code); // Retry/show unavailable; never substitute system time.
  }
}
```

Omit persistence for an in-memory clock. Use an application-specific namespace and one writer per namespace/isolate; share an AnchorStore object when multiple engines intentionally share state. The Android bridge declares INTERNET permission through its library manifest. Sandboxed macOS applications need the network client entitlement.

Native defaults query time.cloudflare.com and ntp.netnod.se (distinct configured provider labels). Network/server policies may prevent consensus. These servers are external services, and the labels do not cryptographically prove operational independence. See [Cloudflare](https://developers.cloudflare.com/time-services/ntp/usage/) and [Netnod](https://www.netnod.se/ntp/connect-to-ntp-servers).

## Read contract

| API | Result |
| --- | --- |
| now(), nowUnixMs(), nowIso() | Strict UTC; throws when unavailable or stale |
| read() | UTC, uncertainty, anchor age, source/provider evidence, and restored origin; throws when unavailable |
| estimate() | Labeled ready/stale reading, or null without a continuous anchor |
| waitUntilReady() | Bounded wait returning the same reading sampled as ready, including restored anchors |
| forceResync() | One shared bounded cycle; a replacement is queued after invalidation |
| status / events | Availability, sync state, failures, restoration, and clock diagnostics |
| dispose() | Releases timers/observation and cancels owned transport work |

UTC may move backward after a correction. Use a monotonic timer for durations; these timestamps do not provide unique IDs or globally ordered events.

Defaults remain: 30-minute foreground refresh, 3-second source timeout, 5-second cycle deadline, two sources from two named providers, 24-hour anchor-age limit, 5-second uncertainty limit, and 100-ppm drift budget. Uncertainty grows by 360 ms per offline hour at that budget, in addition to sampling and source error. This is an engineering estimate under stated assumptions, not an accuracy or security guarantee.

`TrueTimeConfig.maximumUncertainty` is the portable arithmetic limit (9007199254740991 microseconds). Values or projected bounds beyond it fail explicitly with `uncertain`; representable bounds above your configured policy remain stale estimates. A `schedulingFailed` event means automatic refresh/retry or diagnostic registration failed. The completed network result and anchor are retained; a later sync retries refresh registration and resume retries diagnostic registration.

Up to 1,024 sources (`TrueTimeEngine.maximumSources`) are supported; larger lists fail at construction. The sync deadline stops collection, including immediate-source chains. Previously accepted evidence may finish bounded consensus and queue persistence afterward; synchronous custom callbacks cannot be preempted. See the [deadline contract](docs/SPECIFICATION.md#state-and-synchronization) and [scaling measurements](docs/CONSENSUS_PERFORMANCE.md).

## Persistence capability

| Platform | Clock | Offline restore after app restart |
| --- | --- | --- |
| Android API 24+ | CLOCK_BOOTTIME | Only with matching boot count, no-backup installation marker, clock domain, and trust policy |
| Linux | CLOCK_BOOTTIME | Only with a matching kernel boot UUID and application scope |
| iOS/macOS | mach_continuous_time | Fresh online sync required by the default provider |
| Windows | QueryPerformanceCounter | Fresh online sync required by the default provider |
| Web | Session-only portable clock | Fresh online sync after page/browser restart |

A reboot never authorizes reuse by comparing uptime alone. Missing epoch evidence, changed policy, expired/corrupt records, inaccessible storage, and restored backup mismatches fail closed. Apple removed app access to the iOS boot-session UUID; secure storage does not supply that proof.

Storage writes are serialized until the actual backend operation settles. A caller timeout does not release that writer. An unresponsive backend can delay persistence; an otherwise valid in-memory clock continues. Opaque third-party sources that ignore cancellation retain their concurrency permit until their real Future settles.

## Browser setup

Supply at least two independently operated HttpsDateSource endpoints. Each must support HEAD, normal TLS verification, a Date header, Cache-Control: no-store, absent/zero Age, and CORS-exposed Date/Cache-Control/Age headers. Redirects, cached replies, and missing evidence are excluded.

The demo accepts TRUE_TIME_HTTPS_A, TRUE_TIME_HTTPS_B, TRUE_TIME_PROVIDER_A, and TRUE_TIME_PROVIDER_B dart-defines. Missing browser configuration reports sourcesRequired instead of inventing trusted time.

## Development and compatibility

The minimum declared SDK is Flutter 3.41.0 / Dart 3.11.0. The qualification lanes pin Flutter 3.41.0 and 3.47.9. See the [compatibility matrix](https://github.com/PSCHKLLR/flutter_true_time/blob/main/docs/COMPATIBILITY.md) and [validation record](https://github.com/PSCHKLLR/flutter_true_time/blob/main/docs/VALIDATION.md) for platform evidence.

```sh
flutter pub get
flutter analyze
flutter test test test_flutter --coverage
dart test test
cd example
flutter run -d windows
```

The Flutter-independent engine is exported from core.dart. Inject MonotonicClock, TimeSource, BootEpochProvider, AnchorStore, TimeScheduler, and WallClockReader for deterministic tests. Custom sources must expose an immutable configurationKey and honor CancellationSignal to release resources promptly.

No NTS authentication, TLS bypass, system-clock modification, untrusted wall-clock fallback, or OS-managed background worker is included. See the [specification, migration guidance, and release procedures](https://github.com/PSCHKLLR/flutter_true_time/tree/main/docs).

Release tooling lives in the repository. `dart run tool/release.dart patch` previews a version bump. Create a release branch and add `--write` to prepare the four release files, then review, commit, push the branch, and open a PR to main. Pass the required checks, resolve conversations, and merge. After explicit publication authorization, run `dart run tool/release.dart current --publish` from clean, updated main to tag the merged version. See the [release procedure](https://github.com/PSCHKLLR/flutter_true_time/blob/main/docs/PUBLISHING.md).

`dart run tool/update_release_manifest.dart` records the tracked source digest, and `dart run tool/release_check.dart` checks the matching qualification evidence. The full candidate check also runs the pinned Pub dry run in the isolated candidate. See the [device and browser procedures](https://github.com/PSCHKLLR/flutter_true_time/blob/main/docs/DEVICE_QUALIFICATION.md).
