# flutter_true_time specification — revision 0.3

Status: implementation specification for 0.1.0-dev.1. Date: 12 November 2026.

## Purpose and limits

Provide reliable UTC app timestamps independent of subsequent device wall-clock changes. Required behavior includes bounded multi-source synchronization, conservative uncertainty, offline projection, explicit availability, lifecycle handling, and safe optional persistence. This is not a tamper-proof authority, licensing mechanism, unique-ID generator, or globally ordered clock.

All DateTime reads are UTC. A strict read requires a continuous anchor whose age and estimated uncertainty satisfy the configured policy. Explicit estimates may expose stale anchors but never substitute DateTime.now(). Correcting a clock may move UTC backward.

## Anchor and uncertainty

An anchor consists of UTC, a paired monotonic instant, uncertainty, accepted sources/groups, and clock-domain/session evidence. Projection is anchorUtc + currentMonotonic - anchorMonotonic. Reads have no network/storage/asynchronous work; native sampling can perform synchronous FFI calls.

Include network precision, round-trip bounds, local sample/reference quantization, sampling overhead, and drift. The offline drift increment is elapsed microseconds multiplied by driftPpm / 1,000,000, rounded upward. Local clock capabilities expose domain, resolution, sleep continuity, and whether a boot-epoch provider can be used.

Uncertainty is supported from zero through 9007199254740991 microseconds (`TrueTimeConfig.maximumUncertainty`), inclusive. Engine construction rejects a higher configured maximum. Check contributions and sums before addition; reject nonfinite or unsupported drift before integer conversion. Read/estimate/now fail with `TrueTimeException` code `uncertain` if the computed bound exceeds this range, rather than wrapping, rounding away integer bits, or reporting ready. Representable uncertainty above the configured policy still yields a stale estimate. Consensus uses exact integer endpoints, spans, and midpoints on native and JavaScript targets. Record construction/decoding rejects unsupported uncertainty, and restore rejects a base uncertainty above the current policy before projection; rejected records do not advance write sequences.

Windows uses QPC/frequency with overflow-safe tick conversion; Android/Linux use CLOCK_BOOTTIME; Apple uses mach_continuous_time. Unknown native capabilities fall back conservatively to a session-only Stopwatch, with a documented portable uncertainty allowance. Physical sleep/resume qualification is mandatory before support claims.

Native sampling returns a new immutable snapshot and bounds local error by clock resolution plus the measured synchronous sampling duration. Internal scratch buffers and the overhead Stopwatch may be reused within one clock. Reentrant reads require separate scratch/watch state, and native pointer owners must not cross isolates. An engine does not free an injected clock when disposed; clock-owned native storage is finalized when unreachable. Buffer reuse must not change clock domains, continuity, tick conversion, or fallback behavior.

## State and synchronization

Availability is unavailable, ready, or stale, independently from synchronization activity. A failed refresh preserves a valid anchor. Informational wall-clock/timezone changes must not invalidate it. Epoch change, monotonic regression, and suspension of a noncontinuous clock invalidate continuity.

waitUntilReady samples one candidate per check and completes normally only with that same candidate when its availability is ready. This applies to the already-ready fast path, events, and initialization completion. Stale or unavailable candidates continue waiting within the original timeout. Readiness describes the returned reading's sampled instant; callers must take another reading for later decisions because the anchor may expire after sampling.

If a readiness check fails while sampling the monotonic clock, waitUntilReady completes with that original error and stack trace, including checks triggered by events or initialization completion. The wait subscription is cancelled on success, failure, disposal, or timeout.

Sources return intervals paired to a monotonic reference. Query in bounded concurrency, deduplicate configured and resolved endpoints, require named provider diversity, and select deterministic maximum-support interval consensus. Equally supported disjoint results fail. A provider label is an application assertion, not proof of independence.

Construction rejects source lists above `TrueTimeEngine.maximumSources` (1,024) with `ArgumentError`; no source is silently dropped. Consensus uses O(n log n) endpoint processing and O(n) retained state, with exact closed-interval boundary and provider-diversity semantics. Collection uses a separate monotonic Stopwatch budget, checked before transport invocation and after a query returns. Results observed at or after the budget expire are rejected even if the deadline Timer has not run. Each worker yields after 32 attempts so queued lifecycle/timer callbacks can run. Already accepted evidence may finalize and queue persistence after expiry; this bounded finalization and at most one synchronous injected callback/check step are deadline overhead. Synchronous application code and platform scheduling cannot be preempted, so the deadline is not a hard real-time return guarantee. No additional storage wait begins after the budget expires.

One cycle runs per engine. Calls normally coalesce; invalidating an active cycle queues a replacement for a foreground resume. Cancellation propagates to built-in sockets/clients on deadline, disposal, or continuity loss. Permits belong to actual query futures, so noncooperative external implementations cannot inflate concurrency after timeout.

Cancellation wrappers observe supplied operation futures even if their signal is already cancelled. They retain synchronous cancellation in that case, without registering a listener or creating a deadline timer; opaque underlying work is not stopped by the wrapper alone.

NTP validates header, originate nonce, packet endpoint, server timestamp order, precision/dispersion, and eras within 2020–2100. HTTPS Date is a coarse fallback requiring valid TLS, fresh no-store responses, usable headers, and browser CORS access. No response receives an authenticated/NTS label.

Synchronous receive and packet-validation failures settle the NTP query with the original error and stack, then release its owned listener and socket. Queued callbacks cannot complete a response twice if cancellation has already settled it; failures do not escape into the callback zone or wait for the source deadline.

Defaults: refresh 30 minutes; source timeout 3 seconds; cycle deadline 5 seconds; minimum two sources/two known provider groups; maximum anchor age 24 hours; maximum uncertainty 5 seconds; drift budget 100 ppm. Retry uses capped exponential backoff and jitter.

## Lifecycle and diagnostics

Track foreground state separately from clock validity. Native continuous anchors can remain readable while backgrounded; automatic refresh and informational diagnostic polling stop. Portable clocks invalidate on suspension. Initialize from the current Flutter lifecycle state and resume with a fresh cycle if a previous one was invalidated.

An injected foreground wall-clock reader can detect jumps and timezone changes. It is used only for diagnostics, never as a trusted time source. The default diagnostic interval is 30 seconds and jump threshold 2 seconds plus sampling allowances.

If the optional wall-clock reader throws, skip that diagnostic poll without emitting a change event and clear the diagnostic baseline. Initialization and resume continue; scheduled polling retries at the next interval. Recovery establishes a new baseline so gaps cannot produce misleading wall-clock jump events. Monotonic sampling errors retain their existing failure behavior.

If an injected scheduler throws while registering refresh/retry or diagnostic polling, emit `TimeEventKind.schedulingFailed` with the task purpose and retain the network sync outcome, last network error, and anchor. Complete all coalesced cycle callers normally; initialization and resume continue. No task is registered for that failed attempt and there is no immediate retry loop. A later manual sync retries refresh/retry registration; resume retries diagnostic registration. Applications can observe this event to detect loss of automatic work.

## Foreground availability expiry

For a live or restored ready anchor, a separate task on the injected `TimeScheduler` publishes `availabilityChanged` when deterministic anchor-age or drift uncertainty exceeds policy, even with `autoRefresh: false` and no external reads. Equality remains ready: the scheduled crossing is the first invalid integer microsecond, using the same ceil-rounded drift and latest sampled clock-error bound as reads. Early callbacks rearm; delayed callbacks resample current monotonic time and emit only changed availability. Delays longer than one day use one-day checkpoints to stay within browser/native timer limits. Refresh and diagnostic tasks remain independent.

New anchors and changed sampled error bounds recompute expiry; repeated reads with the same anchor/error reuse one task. Continuity loss, suspension, and disposal cancel expiry and make old callbacks inert. Continuous anchors can remain readable while suspended, but background event delivery is not guaranteed; resume immediately resamples before starting fresh synchronization. Session-only suspension still invalidates continuity. OS timer suspension can delay delivery until the event loop resumes.

Changes in sampling error or clock continuity can only be discovered by a new snapshot. Expiry callbacks contain sampling failures and report `schedulingFailed`; a later read, sync, or resume can retry. Registration failures similarly preserve the accepted anchor and emit `schedulingFailed`. If drift arithmetic becomes unsupported at expiry, availability becomes stale while reads retain their existing explicit `uncertain` failure. No wall-clock timestamps or busy polling are used for UTC projection.

## Persistence and restart policy

Persistence is opt-in with an application-specific namespace. Use a single writer per namespace/isolate, or share the same AnchorStore object across engines. The secure backend stores a complete version-2 record. It contains UTC/monotonic anchor, uncertainty, source/provider evidence, clock domain, verified epoch/installation scope, trust-policy fingerprint, and write sequence.

The version-2 sequence is a local counter in 1..9007199254740991 (`AnchorRecord.maxSequence`), the portable exact integer range for native and JavaScript consumers. Record construction and decoding reject values outside this range. Adopt a saved sequence only after all restore checks accept the anchor; rejected records cannot change the counter. The first fresh save without an accepted restore uses 1. After an accepted restore, saves increment the counter and wrap from the maximum to 1; a later restart can restore that wrapped record normally. Sequence values are neither globally unique nor an anti-rollback mechanism. The serialized writer queue determines write order across rollover and between engines sharing a backend.

Initialization and synchronization share one bounded boot-epoch lookup per continuity generation, including its pending and unavailable outcomes. Continuity loss starts a separate lookup; results and diagnostics from earlier generations are ignored. Disposal releases waiting callers, and a cycle deadline can end that cycle's wait without releasing another caller's shared lookup.

Foreground initialization starts restoration and fresh synchronization concurrently. Queries and fresh readiness do not wait for epoch or storage I/O. A valid restore can satisfy readiness first; late restoration cannot replace fresh time or cross continuity generations. `initialize()` completes after the restoration attempt, not after network completion, and does not imply readiness. With `foreground: false`, initialization attempts restoration without automatic network work.

Restoration shares one `sourceTimeout` budget across epoch lookup and load: if epoch lookup consumes it, load is skipped; otherwise load receives the remaining budget. Fresh persistence joins epoch lookup only after publishing the live anchor, within the cycle's remaining deadline. A deadline during this join preserves accepted network evidence and may save without restart evidence; such a record cannot authorize restart restoration. A later cycle can persist newly available matching epoch evidence. `waitUntilReady()` keeps its independent caller timeout and can return before initialization or persistence finishes. Disposal releases waits and late failures remain observed; actual backend write ownership is unchanged.

Restore only after validating the schema, supported UTC range, evidence/source mapping, uniqueness, quorum, policy fingerprint, clock domain, verified epoch, nonregressing monotonic time, age, and uncertainty. A process-local random session identity is never a boot identity. Caller timeouts must not release the underlying serialized writer; old writes cannot overtake new writes.

`SerializingAnchorStore` retains at most one active complete-record snapshot and one pending snapshot per backend object/isolate. Save arguments are deep-snapshotted before queue selection. A newer save replaces a not-yet-started record and promptly fails that record's future with `TrueTimeException` code `storageSuperseded`; it does not wait for the active backend or imply that the superseded record was written. A successful save means the backend completed that specific snapshot. A failed backend write propagates its error/stack and releases ownership only after it settles, allowing the newest pending record to proceed. Late failures remain observed after caller timeout or disposal.

Engines sharing one backend share this single pending slot, including when their policy fingerprints or sequences differ: newest invocation wins, records are replaced whole, and no evidence is combined. Different backend objects/namespaces have independent queues. Restore still requires the caller's matching policy and continuity checks. A shared backend represents one record slot; separate processes or distinct backend objects must not write the same namespace concurrently.

`load()` waits for writes preceding the call (or the replacement of a preceding pending record) to settle before invoking the backend read. Superseding a pending save cannot prematurely release that read barrier. Errors do not prevent a subsequent load of the last saved record. Later saves may already be active when the read occurs, so an atomic backend read may return a later complete record. Loads do not pin superseded snapshots or stop coalescing. The writer bounds retained pending snapshots, not record byte size or work/futures retained by external callers or backend implementations.

Android uses public BOOT_COUNT and a persistent installation UUID stored in noBackupFilesDir. Linux uses the kernel boot UUID plus the application namespace. Their offline restoration is limited to the same proven boot/installation. Default Apple/Windows providers report unknown continuity and require fresh network time after restart. Web always requires fresh time after page/browser restart. A reboot, restored backup mismatch, unknown epoch, or inaccessible storage never fabricates trust.

Storage failures, timeouts, and superseded saves leave a valid in-memory anchor usable and emit `storageFailed` diagnostics. Restoring a usable anchor immediately completes readiness, without waiting for the network. Disposal cancels owned deadline timers while preserving ownership of already-running opaque backend writes and the newest queued snapshot.

Successful consensus queues a version-2 record even when sample collection runs to its deadline. Sync waits for persistence only within the cycle budget. Storage observation remains bounded by the source timeout and can report a failure after sync returns. The writer keeps its position until the backend settles.

## API and platform qualification

Version 2.0.0 exposes TrueTime initialize/now/read/estimate/waitUntilReady/forceResync/status/events/dispose, TrueTimeEngine in core.dart, TrueTimeConfig, and TrueTimeException. These names replace the TrustedTime-prefixed types from versions through 1.0.0 without compatibility aliases. Equivalent built-in source configurations initialize idempotently; conflicting supplied options require disposal. Reading metadata distinguishes restored origin and unauthenticated provenance.

The initial target is all six Flutter platforms. Minimum declared SDK is Flutter 3.41.0/Dart 3.11.0; current qualification is pinned to Flutter 3.47.9. Android API 24, iOS 15, and macOS 12 are deployment floors. Android AGP/KGP/Gradle host combinations and Xcode 27.2 builds require recorded evidence. A passing core compiler check does not qualify an app build or device behavior.

NTS, timezone formatting helpers, OS background workers, private boot-identity APIs, and approximate wall-clock restart estimates are deferred. Publishing remains disabled until the all-platform, provenance, privacy, namespace, repository, and owner-approval gates pass.

## First-release corrections

Valid restored state may complete readiness while a query is pending; it cannot replace a fresh network anchor or survive invalidated restoration continuity. The cycle deadline closes sample collection and cancels pending work, then consensus evaluates samples already accepted before that cutoff. Disposal/continuity cancellation still discards the cycle. Named provider evidence is trimmed and excludes unknown case-insensitively throughout live and stored state; real names retain case sensitivity. NTP validates arguments/cancellation before transport setup and observes every response future on send failure and cleanup.

Release verification uses schema-2 repository metadata, canonical LF UTF-8 text and binary hashes, a tracked-input inventory, and evidence tied to the source digest. Generated wrappers and registrants are excluded. The runtime fingerprint ignores the exact development guard line when present. Candidate approval binds to the actual bytes selected by Pub. The published package workflow separately verifies that a clean consumer resolves the public version and passes the example tests on both pinned SDKs.

Full candidate verification reruns the pinned pub dry run and fingerprints the exact selected paths and bytes. Both candidate consumer evidence and owner approval must contain that digest. Representative release-build read latency and allocation measurements are required qualification evidence.
