# flutter_true_time specification — revision 0.3

Status: implementation specification for 0.1.0-dev.1. Date: 12 November 2026.

## Purpose and limits

Provide reliable UTC app timestamps independent of subsequent device wall-clock changes. Required behavior includes bounded multi-source synchronization, conservative uncertainty, offline projection, explicit availability, lifecycle handling, and safe optional persistence. This is not a tamper-proof authority, licensing mechanism, unique-ID generator, or globally ordered clock.

All DateTime reads are UTC. A strict read requires a continuous anchor whose age and estimated uncertainty satisfy the configured policy. Explicit estimates may expose stale anchors but never substitute DateTime.now(). Correcting a clock may move UTC backward.

## Anchor and uncertainty

An anchor consists of UTC, a paired monotonic instant, uncertainty, accepted sources/groups, and clock-domain/session evidence. Projection is anchorUtc + currentMonotonic - anchorMonotonic. Reads have no network/storage/asynchronous work; native sampling can perform synchronous FFI calls.

Include network precision, round-trip bounds, local sample/reference quantization, sampling overhead, and drift. The offline drift increment is elapsed microseconds multiplied by driftPpm / 1,000,000, rounded upward. Local clock capabilities expose domain, resolution, sleep continuity, and whether a boot-epoch provider can be used.

Windows uses QPC/frequency with overflow-safe tick conversion; Android/Linux use CLOCK_BOOTTIME; Apple uses mach_continuous_time. Unknown native capabilities fall back conservatively to a session-only Stopwatch, with a documented portable uncertainty allowance. Physical sleep/resume qualification is mandatory before support claims.

## State and synchronization

Availability is unavailable, ready, or stale, independently from synchronization activity. A failed refresh preserves a valid anchor. Informational wall-clock/timezone changes must not invalidate it. Epoch change, monotonic regression, and suspension of a noncontinuous clock invalidate continuity.

waitUntilReady samples one candidate per check and completes normally only with that same candidate when its availability is ready. This applies to the already-ready fast path, events, and initialization completion. Stale or unavailable candidates continue waiting within the original timeout. Readiness describes the returned reading's sampled instant; callers must take another reading for later decisions because the anchor may expire after sampling.

If a readiness check fails while sampling the monotonic clock, waitUntilReady completes with that original error and stack trace, including checks triggered by events or initialization completion. The wait subscription is cancelled on success, failure, disposal, or timeout.

Sources return intervals paired to a monotonic reference. Query in bounded concurrency, deduplicate configured and resolved endpoints, require named provider diversity, and select deterministic maximum-support interval consensus. Equally supported disjoint results fail. A provider label is an application assertion, not proof of independence.

One cycle runs per engine. Calls normally coalesce; invalidating an active cycle queues a replacement for a foreground resume. Cancellation propagates to built-in sockets/clients on deadline, disposal, or continuity loss. Permits belong to actual query futures, so noncooperative external implementations cannot inflate concurrency after timeout.

Cancellation wrappers observe supplied operation futures even if their signal is already cancelled. They retain synchronous cancellation in that case, without registering a listener or creating a deadline timer; opaque underlying work is not stopped by the wrapper alone.

NTP validates header, originate nonce, packet endpoint, server timestamp order, precision/dispersion, and eras within 2020–2100. HTTPS Date is a coarse fallback requiring valid TLS, fresh no-store responses, usable headers, and browser CORS access. No response receives an authenticated/NTS label.

Defaults: refresh 30 minutes; source timeout 3 seconds; cycle deadline 5 seconds; minimum two sources/two known provider groups; maximum anchor age 24 hours; maximum uncertainty 5 seconds; drift budget 100 ppm. Retry uses capped exponential backoff and jitter.

## Lifecycle and diagnostics

Track foreground state separately from clock validity. Native continuous anchors can remain readable while backgrounded; automatic refresh and informational diagnostic polling stop. Portable clocks invalidate on suspension. Initialize from the current Flutter lifecycle state and resume with a fresh cycle if a previous one was invalidated.

An injected foreground wall-clock reader can detect jumps and timezone changes. It is used only for diagnostics, never as a trusted time source. The default diagnostic interval is 30 seconds and jump threshold 2 seconds plus sampling allowances.

If the optional wall-clock reader throws, skip that diagnostic poll without emitting a change event and clear the diagnostic baseline. Initialization and resume continue; scheduled polling retries at the next interval. Recovery establishes a new baseline so gaps cannot produce misleading wall-clock jump events. Monotonic sampling errors retain their existing failure behavior.

## Persistence and restart policy

Persistence is opt-in with an application-specific namespace. Use a single writer per namespace/isolate, or share the same AnchorStore object across engines. The secure backend stores a complete version-2 record. It contains UTC/monotonic anchor, uncertainty, source/provider evidence, clock domain, verified epoch/installation scope, trust-policy fingerprint, and write sequence.

The version-2 sequence is a local counter in 1..9007199254740991 (`AnchorRecord.maxSequence`), the portable exact integer range for native and JavaScript consumers. Record construction and decoding reject values outside this range. Adopt a saved sequence only after all restore checks accept the anchor; rejected records cannot change the counter. The first fresh save without an accepted restore uses 1. After an accepted restore, saves increment the counter and wrap from the maximum to 1; a later restart can restore that wrapped record normally. Sequence values are neither globally unique nor an anti-rollback mechanism. The serialized writer queue determines write order across rollover and between engines sharing a backend.

Initialization and synchronization share one bounded boot-epoch lookup per continuity generation, including its pending and unavailable outcomes. Continuity loss starts a separate lookup; results and diagnostics from earlier generations are ignored. Disposal releases waiting callers, and a cycle deadline can end that cycle's wait without releasing another caller's shared lookup.

Restore only after validating the schema, supported UTC range, evidence/source mapping, uniqueness, quorum, policy fingerprint, clock domain, verified epoch, nonregressing monotonic time, age, and uncertainty. A process-local random session identity is never a boot identity. Caller timeouts must not release the underlying serialized writer; old writes cannot overtake new writes.

Android uses public BOOT_COUNT and a persistent installation UUID stored in noBackupFilesDir. Linux uses the kernel boot UUID plus the application namespace. Their offline restoration is limited to the same proven boot/installation. Default Apple/Windows providers report unknown continuity and require fresh network time after restart. Web always requires fresh time after page/browser restart. A reboot, restored backup mismatch, unknown epoch, or inaccessible storage never fabricates trust.

Storage failures leave a valid in-memory anchor usable and emit diagnostics. Restoring a usable anchor immediately completes readiness, without waiting for the network. Disposal cancels owned deadline timers while preserving ordering of already-running opaque backend writes.

Successful consensus queues a version-2 record even when sample collection runs to its deadline. Sync waits for persistence only within the cycle budget. Storage observation remains bounded by the source timeout and can report a failure after sync returns. The writer keeps its position until the backend settles.

## API and platform qualification

Version 2.0.0 exposes TrueTime initialize/now/read/estimate/waitUntilReady/forceResync/status/events/dispose, TrueTimeEngine in core.dart, TrueTimeConfig, and TrueTimeException. These names replace the TrustedTime-prefixed types from versions through 1.0.0 without compatibility aliases. Equivalent built-in source configurations initialize idempotently; conflicting supplied options require disposal. Reading metadata distinguishes restored origin and unauthenticated provenance.

The initial target is all six Flutter platforms. Minimum declared SDK is Flutter 3.41.0/Dart 3.11.0; current qualification is pinned to Flutter 3.47.9. Android API 24, iOS 15, and macOS 12 are deployment floors. Android AGP/KGP/Gradle host combinations and Xcode 27.2 builds require recorded evidence. A passing core compiler check does not qualify an app build or device behavior.

NTS, timezone formatting helpers, OS background workers, private boot-identity APIs, and approximate wall-clock restart estimates are deferred. Publishing remains disabled until the all-platform, provenance, privacy, namespace, repository, and owner-approval gates pass.

## First-release corrections

Valid restored state may complete readiness while a query is pending; it cannot replace a fresh network anchor or survive invalidated restoration continuity. The cycle deadline closes sample collection and cancels pending work, then consensus evaluates samples already accepted before that cutoff. Disposal/continuity cancellation still discards the cycle. Named provider evidence is trimmed and excludes unknown case-insensitively throughout live and stored state; real names retain case sensitivity. NTP validates arguments/cancellation before transport setup and observes every response future on send failure and cleanup.

Release verification uses schema-2 repository metadata, canonical LF UTF-8 text and binary hashes, a tracked-input inventory, and evidence tied to the source digest. Generated wrappers and registrants are excluded. The runtime fingerprint ignores the exact development guard line when present. Candidate approval binds to the actual bytes selected by Pub. The published package workflow separately verifies that a clean consumer resolves the public version and passes the example tests on both pinned SDKs.

Full candidate verification reruns the pinned pub dry run and fingerprints the exact selected paths and bytes. Both candidate consumer evidence and owner approval must contain that digest. Representative release-build read latency and allocation measurements are required qualification evidence.
