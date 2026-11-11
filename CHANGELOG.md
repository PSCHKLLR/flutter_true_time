# Changelog

## 0.1.0-dev.1 (unpublished)

- Rename the new package and primary import to flutter_true_time; retain TrustedTime and the Flutter-independent core entry point.
- Include native clock precision and sampling overhead in uncertainty; use Windows QPC.
- Cancel built-in transports at deadlines/disposal and retain concurrency permits until underlying queries settle.
- Replace invalidated cycles on resume and pause automatic refresh while backgrounded.
- Add secure-storage opt-in, Android/Linux epoch providers, strict version-2 record validation, serialized writes, and restored readiness/origin.
- Compare source configuration by value and add informational foreground clock/timezone diagnostics.
- Add runnable six-platform hosts, regression tests, compatibility workflows, provenance notices, and fail-closed release checks.
- Qualification remains incomplete; NTS and OS background workers are deferred. Publication is disabled.
