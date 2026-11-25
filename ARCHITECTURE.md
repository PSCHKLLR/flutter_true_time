# Architecture

The core transforms source intervals into an immutable UTC/monotonic anchor, with explicit ready/stale/unavailable state. Source samples and the common reference include local clock error; read uncertainty grows with drift and current sampling error. No wall clock advances an anchor.

Uncertainty sums are checked before arithmetic against the portable exact microsecond limit (2^53 - 1); unsupported projection fails explicitly. Consensus interval endpoints and midpoints use BigInt so wide intervals cannot wrap on native Dart or lose bits in JavaScript. Stored uncertainty must pass both codec range checks and restore policy checks before projection.

The engine owns one cancellable cycle and a bounded permit pool. Concurrent callers share work. Continuity loss cancels the old cycle; resume queues a replacement. Permits remain attached to actual source futures, so timed-out external code cannot silently create unbounded overlapping operations. Built-in UDP/HTTPS sources release owned resources on cancellation.

At most 1,024 configured sources are supported. Collection checks an independent Stopwatch budget before starting a query and after receiving a result, so an immediate-future chain cannot accept late evidence while starving the deadline Timer. Workers yield after 32 attempts. Accepted evidence finalizes using a sorted closed-endpoint sweep with incremental provider counts and ordered boundary multisets: O(n log n) work and O(n) retained state. Starts are applied before ends at a shared endpoint; unknown groups never supply diversity. Only the first maximum-support quorum is materialized, and equally supported disjoint intersections remain ambiguous. Finalization checks elapsed time but may finish a previously accepted quorum after collection expires.

The Flutter facade observes lifecycle state. Foreground scheduling is independent from clock continuity: native continuous anchors remain readable in the background, while session-only clocks invalidate. Injected wall-clock observations produce informational events only.

Scheduler registration is optional maintenance: failures emit `schedulingFailed`, preserve network results and accepted anchors, and never strand cycle completers. Later sync/resume calls can register maintenance again. NTP receive callbacks contain synchronous transport failures, preserve their stacks, and check completion after injected code to tolerate cancellation races.

Optional persistence uses a typed version-2 complete record and a serialized backend. Matching clock domain, public boot evidence, installation scope, trust-policy fingerprint, accepted source/provider mapping, freshness, and uncertainty are required for restoration. A caller timeout never releases the actual writer queue. One namespace has one writer per isolate; share the backend object when multiple engines intentionally share state.

Only fully accepted restores advance the local write-sequence counter. Sequences are exact integers in 1..9007199254740991 across native and JavaScript consumers, wrapping to 1 at the limit. The writer queue preserves order across rollover; sequence values do not provide global ordering or rollback protection.

Initialization and synchronization join a shared, bounded epoch lookup within each continuity generation. Continuity loss replaces that lookup; late results from an older generation cannot populate the current epoch. A cycle deadline stops only that cycle's wait, while disposal releases all lifetime-bound lookup waiters.

Android's small Java bootstrap plugin reads BOOT_COUNT and an AtomicFile installation marker in noBackupFilesDir. Linux reads the kernel boot UUID. Other platforms use Dart-only registrations and deliberately report no verified restart epoch. Public hot-path clock sampling uses conditional FFI adapters; web imports neither sockets nor native FFI.

SwiftPM/native Apple resources are supplied by the storage dependency; this package has no custom Swift binary or private sysctl. Final Apple privacy/resource behavior is an archive-level qualification gate.

A deadline closes sample collection. Valid collected evidence can still produce an anchor and queue its storage write. The cycle stops waiting at the deadline, and the serialized writer retains its position until the backend settles. Restoration can run alongside network work but never replaces a fresh anchor. Provider-group normalization is shared by live consensus and record validation. The tracked-source fingerprint normalizes text inputs. The candidate fingerprint uses exact bytes from the fresh Pub file list and binds the clean-consumer results and owner approval.
