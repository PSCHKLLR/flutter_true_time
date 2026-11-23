# Changelog

## 2.0.4

- Share pending boot-epoch lookups between initialization and synchronization, retaining bounded waits and rejecting stale continuity-generation results (#4).

## 2.0.3

- Propagate clock sampling failures from readiness callbacks to the waiting caller with their original stack trace, and clean up the wait subscription (#5).

## 2.0.2

- Keep initialization, resume, and diagnostic polling working when an optional wall-clock reader fails; skip failed polls and reset their diagnostic baseline (#3).

## 2.0.1

- Fix unhandled operation errors from already-cancelled `CancellationSignal.race` and `withTimeout` calls while preserving synchronous cancellation and deadline cleanup (#2).

## 2.0.0

- **Breaking:** Rename `TrustedTime`, `TrustedTimeEngine`, `TrustedTimeConfig`, and `TrustedTimeException` to `TrueTime`, `TrueTimeEngine`, `TrueTimeConfig`, and `TrueTimeException`. Update type references and facade calls; imports and the version-2 persistence format stay the same.

## 1.0.0

- First stable release of the public Dart API and version-2 persistence format.

## 0.1.0-dev.1

First public prerelease on pub.dev, published 14 November 2026.

- Restore valid anchors during pending queries without replacing fresh network time.
- Preserve accepted quorum evidence at cycle deadlines while cancelling remaining work.
- Queue persistence for anchors accepted at the deadline and keep writes ordered after the sync returns.
- Verify saved native anchors across restart and bind release approval to the exact pub-selected files.
- Prevent unobserved NTP errors on pre-cancellation/send failure and normalize unknown provider evidence consistently.
- Add canonical tracked-source fingerprints, digest-bound release evidence, generated-file exclusions, and native restart qualification harnesses.

- Rename the new package and primary import to flutter_true_time; retain TrustedTime and the Flutter-independent core entry point.
- Include native clock precision and sampling overhead in uncertainty; use Windows QPC.
- Cancel built-in transports at deadlines/disposal and retain concurrency permits until underlying queries settle.
- Replace invalidated cycles on resume and pause automatic refresh while backgrounded.
- Add secure-storage opt-in, Android/Linux epoch providers, strict version-2 record validation, serialized writes, and restored readiness/origin.
- Compare source configuration by value and add informational foreground clock/timezone diagnostics.
- Add runnable six-platform hosts, regression tests, compatibility workflows, provenance notices, and fail-closed release checks.
- Platform qualification continues. NTS and OS background workers are deferred.
