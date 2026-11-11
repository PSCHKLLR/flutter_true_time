# Architecture

The core transforms source intervals into an immutable UTC/monotonic anchor, with explicit ready/stale/unavailable state. Source samples and the common reference include local clock error; read uncertainty grows with drift and current sampling error. No wall clock advances an anchor.

The engine owns one cancellable cycle and a bounded permit pool. Concurrent callers share work. Continuity loss cancels the old cycle; resume queues a replacement. Permits remain attached to actual source futures, so timed-out external code cannot silently create unbounded overlapping operations. Built-in UDP/HTTPS sources release owned resources on cancellation.

The Flutter facade observes lifecycle state. Foreground scheduling is independent from clock continuity: native continuous anchors remain readable in the background, while session-only clocks invalidate. Injected wall-clock observations produce informational events only.

Optional persistence uses a typed version-2 complete record and a serialized backend. Matching clock domain, public boot evidence, installation scope, trust-policy fingerprint, accepted source/provider mapping, freshness, and uncertainty are required for restoration. A caller timeout never releases the actual writer queue. One namespace has one writer per isolate; share the backend object when multiple engines intentionally share state.

Android's small Java bootstrap plugin reads BOOT_COUNT and an AtomicFile installation marker in noBackupFilesDir. Linux reads the kernel boot UUID. Other platforms use Dart-only registrations and deliberately report no verified restart epoch. Public hot-path clock sampling uses conditional FFI adapters; web imports neither sockets nor native FFI.

SwiftPM/native Apple resources are supplied by the storage dependency; this package has no custom Swift binary or private sysctl. Final Apple privacy/resource behavior is an archive-level qualification gate.
