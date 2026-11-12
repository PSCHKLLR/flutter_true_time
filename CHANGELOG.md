# Changelog

## 0.1.0-dev.1 (unpublished)

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
- Qualification remains incomplete; NTS and OS background workers are deferred. Publication is disabled.
