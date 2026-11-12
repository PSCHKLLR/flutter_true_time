# Implementation review and resolution report

Baseline: the generated trusted_time 0.1.0 project; reviewed as a complete initial addition without a Git merge base. Review locations below refer to that baseline, not current line numbers.

| Finding | Baseline location | Resolution and regression |
| --- | --- | --- |
| P2: SDK/dependency mismatch | pubspec.yaml:14 | Declared Flutter 3.41/Dart 3.11 floor; exact minimum/current independently resolved lanes |
| P2: missing local clock error | clock_native.dart:25 | QPC/frequency, clock capabilities, sample resolution/overhead, uncertainty regression |
| P2: queries outlive cycle limits | engine.dart:294 | Cooperative signals, owned socket/client closure, actual-future concurrency permits; native/HTTPS tests |
| P2: resumed calls join invalidated cycle | engine.dart:452 | Queued replacement and generation isolation; refresh-disabled resume regression |
| P2: foreground conflated with continuity | engine.dart:443 | Independent foreground state and automatic scheduling suppression; native-background regression |
| P2: timed-out saves overtake new state | engine.dart:329 | Shared serialized backend queue survives timeout; delayed write and disposal regressions |
| P2: restored readiness waits for network | engine.dart:228 | Restore/availability events plus initialization recheck; blocked-network readiness regression |
| P2: weak record validation | engine.dart:142 | Typed schema, epoch/policy/domain, range/age/error/evidence validation; corruption and backup tests |
| P2: initialization uses object identity | facade.dart:24 | Source configurationKey comparison; equivalent-value and conflict facade tests |

Additional verification found an owned timeout timer surviving widget disposal. Scoped timeout wrappers now release those timers; a Flutter fake-time regression covers pending storage initialization. Restored provider labels are checked against the selected source IDs, not only against the configured pool.

## Specification decisions implemented

New identity: flutter_true_time. New attribution: PSCHKLLR, with upstream notices preserved. Target: all six platforms; SDK lanes 3.41.0 and 3.47.9. Secure persistence is optional and uses only proven continuity; Apple/Windows/web restart reads remain unavailable until synchronization. NTS and OS background workers are deferred.

## Qualification and publication

See VALIDATION.md for actual executed checks, COMPATIBILITY.md for targets and limitations, and PUBLISHING.md for the release procedure. CI configuration is not evidence that a lane passed. No publication is authorized by this report. Remaining external device, Apple, repository ownership, and final archive gates stay blocked until evidence exists.

## Host qualification corrections

Android release compilation exposed a stale integration_test registration when --no-pub bypassed platform regeneration. Normal release commands passed APK compilation; workflows now regenerate tooling. The built-in Kotlin host removes the legacy kotlinOptions block and inherits the Java 17 compilation target. These fixes do not establish JDK 17 or AGP 9 qualification. See VALIDATION.md for executed results.

## First-release enhancement review (12 November 2026)

The five additional P2 findings have implementation and regression coverage:

| Finding | Correction | Regression coverage |
| --- | --- | --- |
| Restore skipped while syncing | Restore alongside pending queries, preserve a fresh anchor, guard continuity generation | Resume/explicit sync during delayed load; network wins; disposal/invalidation |
| Deadline discarded accepted quorum | Cancel remaining work and evaluate accepted evidence | Quorum before deadline, late response isolation, existing no-quorum/concurrency tests |
| Unobserved NTP errors | Early cancellation/argument checks, immediate response-future observation | Pre-cancel, invalid arguments, thrown/zero-byte send and resource cleanup |
| Mixed-case unknown provider evidence | Shared canonical named-group filter | Unknown casing/whitespace, source count, persisted restore, real-name case sensitivity |
| Nonportable release fingerprints | Tracked canonical inputs, generated-file exclusion, digest-bound evidence | LF/CRLF, binary changes, untracked inputs, stale/corrupt evidence, read-only checker |

The complete suite has 106 tests. Executed SDK/build results and remaining blockers are recorded in VALIDATION.md; this report does not certify unexecuted native/device gates.

Android qualification also exposed deprecated AGP/Kotlin DSL accessors and an insufficient built-in compiler default. Typed extensions, compilerOptions and settings-level KGP alignment resolved these without bypassing Flutter checks. Exact baseline/current/built-in APK and AAB builds passed on JDK 17.
