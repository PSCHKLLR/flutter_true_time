# Changelog

## Unreleased

- Publish foreground age/drift availability expiry without requiring reads, with independent cancellable scheduling for live/restored anchors and immediate resume resampling (#8).
- Bound persistence to one active and one newest pending complete record per shared backend; fail superseded saves explicitly while preserving backend ownership, load barriers, snapshots, and in-memory time (#9).
- Make release-branch preparation, PR checks, merge, and authorized publication from updated main the standard release flow; explain recovery of retained version commits after a rejected main push (#33).
- Test the latest stable published package on both pinned Flutter SDKs, with validated manual version overrides and separate advisory 2.0.0 coverage; keep publication consumers pinned to their exact release (#24).

## 2.0.6

- Use an O(n log n) endpoint sweep for consensus, enforce elapsed collection budgets even for immediate sources, yield during long collections, and reject more than 1,024 configured sources (#20).
- Reject unsupported uncertainty values and checked-sum/drift overflow; compute consensus endpoints exactly on native and web targets (#30).
- Deliver synchronous UDP receive failures with their original stack and release the owned socket/listener, including cancellation races (#31).
- Keep sync futures and lifecycle calls usable when scheduler registration throws; report `schedulingFailed` diagnostics and retry registration on later sync/resume (#32).
- Replace the UDP cancellation test's immediate ephemeral-port rebind with deterministic socket/listener ownership checks, a real leaking-socket negative fixture, and repeated macOS coverage (#22).
- Wait for both pub.dev version metadata and package indexing, and retry only exact-version visibility failures in clean consumers within bounded propagation budgets (#21).
- Keep rejected restore records from changing fresh-write sequences; validate the portable positive sequence range and wrap safely at its maximum while preserving writer ordering (#19).
- Return the same ready reading validated by `waitUntilReady()`, avoiding stale results across age or uncertainty expiry boundaries (#18).
- Avoid duplicate compatibility matrices on feature-branch pushes and release tags; cancel superseded standalone PR checks while preserving strict release validation (#23).
- Add a release command to preview or prepare version bumps and publish by pushing main before its annotated release tag.

## 2.0.5

- Derive release-tool versions from pubspec, reject mismatched manifests and Pub dry-run headers, and retain qualification requirements for stable and prerelease candidates (#6).
- Add tag-triggered pub.dev publishing with OIDC, strict compatibility checks, clean-consumer verification, and matching GitHub Releases. Display published version badges in the README.

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
