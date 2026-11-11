> Historical revision 0.1. Superseded by [SPECIFICATION.md](SPECIFICATION.md).

# trusted_time rebuild specification

Status: Draft 0.1 — proposed behavior, ready for review  
Date: 10 November 2026  
Fork: https://github.com/PSCHKLLR/trusted_time  
Confirmed primary use case: reliable app timestamps

## 1. Purpose

Provide Flutter applications with a dependable UTC clock derived from network time and elapsed monotonic time. Applications should keep producing useful timestamps when the user changes the device clock or connectivity disappears, while understanding when accuracy can no longer be trusted.

The first release prioritizes correctness, predictable lifecycle behavior, and a small API. It must not advertise absolute tamper resistance, zero drift, or guaranteed accuracy on every network.

## 2. Evidence and scope

The published package describes multi-source synchronization, monotonic anchoring, offline estimates, persistence, integrity events, background scheduling, and six Flutter platforms. Its public API includes initialize(), now(), forceResync(), trust/confidence accessors, and testing overrides. This is a documentation baseline, not a verified inventory of the fork. [Published package](https://pub.dev/packages/trusted_time)

The published README describes advisory NTS while its changelog describes later native NTS changes. The rebuild must verify actual source and dependency behavior before promising authenticated time. [README](https://pub.dev/packages/trusted_time) · [Changelog](https://pub.dev/packages/trusted_time/changelog)

Fork HEAD was reachable as b6173c0eb54ce5946e10115b26b2b40296d37862. Its files have not been audited because local checkout was blocked by workspace access. No implementation defect is asserted by this specification.

All requirements below are proposals unless explicitly marked confirmed. Compatibility, supported OS versions, and numerical defaults require a source audit before implementation.

## 3. Release scope

Required:
- UTC reads independent of subsequent device wall-clock changes.
- Bounded network synchronization with multiple configurable sources.
- Offline projection with an increasing uncertainty estimate.
- Explicit ready, stale, and unavailable states.
- Correct handling of sleep, resume, process restart, and reboot.
- Deterministic testing without real network or wall-clock dependencies.
- A documented capability matrix and migration guidance.

Optional after the core is stable: verified NTS, OS-managed background refresh, timezone formatting helpers, and a separately published pure-Dart core.

Excluded: setting the system clock, global event ordering, unique timestamp IDs, server-authoritative transaction timestamps, licensing enforcement, and protection against a compromised OS or modified application.

## 4. Clock contract

R1. Every returned DateTime is UTC. Timezone conversion belongs at presentation boundaries.

R2. A successful sync creates an immutable anchor: UTC instant, paired monotonic instant, uncertainty, accepted source evidence, and clock-session identity.

R3. Project time using anchorUtc + (currentMonotonic - anchorMonotonic). Never use DateTime.now() to advance a trusted anchor.

R4. Elapsed time must include device sleep. If an adapter cannot demonstrate continuity through suspension, downgrade availability on resume and resynchronize. Android elapsedRealtime explicitly includes deep sleep; adapters must be tested against equivalent semantics. [Android SystemClock](https://developer.android.com/reference/android/os/SystemClock)

R5. A device wall-clock or timezone change emits an informational event and may trigger a refresh. It does not invalidate an otherwise continuous monotonic anchor. A monotonic reset or unprovable continuity invalidates the anchor.

R6. UTC estimates may move backward when a new sync corrects an earlier estimate. Document this explicitly. Consumers needing elapsed durations must use a monotonic timer. Do not silently clamp UTC or invent precision to guarantee ordering.

R7. Ordinary reads perform no network, storage, or asynchronous work. If native monotonic sampling requires a synchronous call, disclose its cost. Do not promise a channel-free path until the implementation proves it.

## 5. State and accuracy

Keep availability separate from synchronization activity:

| Availability | Meaning | Strict read |
| --- | --- | --- |
| unavailable | No valid continuous anchor | Fails |
| ready | Anchor satisfies configured age and uncertainty limits | Succeeds |
| stale | Continuous anchor exceeds either limit | Fails; explicit estimate remains available |

A separate syncInProgress flag allows refresh while reads continue. A failed refresh retains the previous anchor and records the failure. It does not make a still-valid clock unavailable.

Each reading includes utc, uncertainty, anchorAge, availability, sourceCount, providerGroupCount, and provenance. Uncertainty is a conservative engineering estimate conditional on source and oscillator assumptions, not a cryptographic guarantee or statistical confidence interval.

Use uncertaintyNow = uncertaintyAtSync + elapsed × driftBudget. The drift budget is configurable and expressed in ppm. Account separately for timestamp resolution and local sampling error. A confidence badge may summarize this information but must not replace it.

Provisional defaults for ordinary timestamps: refresh every 30 minutes while active; source timeout 3 seconds; total sync deadline 5 seconds; minimum 2 accepted sources from 2 provider groups; maximum anchor age 24 hours; maximum estimated uncertainty 5 seconds; drift budget 100 ppm. These are starting policies, not accuracy promises. Validate against device measurements before release.

## 6. Synchronization

- Query eligible sources concurrently, subject to a bounded concurrency limit and overall deadline.
- Represent samples as UTC intervals at a common monotonic reference instant. Include transport delay, protocol precision, and source dispersion where available.
- Select a sufficiently supported overlapping interval using a documented deterministic consensus algorithm. Enforce quorum and configured provider diversity.
- Duplicate addresses and multiple endpoints operated by the same provider must not inflate independence. Unknown grouping cannot satisfy an independence claim automatically.
- Reject malformed, mismatched, implausible, excessively delayed, or unusable samples with structured reasons. Handle NTP era conversion explicitly.
- Define tie handling and conflicting clusters. An unresolved tie fails synchronization rather than selecting arbitrarily.
- Publish the new anchor atomically only after validation. Late responses from an older cycle cannot overwrite a newer result.
- Coalesce concurrent sync requests into one in-flight operation. Apply capped exponential backoff with jitter after failures.
- HTTPS Date is a coarse fallback requiring valid TLS, fresh responses, acceptable cache/Age handling, usable Date headers, and browser CORS access. Missing evidence excludes the sample. It never receives an NTS label.
- Provider disagreement is a diagnostic, not proof that the user changed the clock.

## 7. Proposed API shape

Keep a familiar TrustedTime facade where compatible, backed by an injectable instance for tests and multiple consumers. Exact signatures follow the source audit.

| Operation | Contract |
| --- | --- |
| initialize(config) | Validates config, restores only eligible state, starts initial sync; completion does not imply ready |
| waitUntilReady(timeout) | Waits for a policy-compliant reading or returns a typed failure within the deadline |
| read() | Returns one immutable reading and its metadata; fails if unavailable |
| now() | Returns UTC only when the default policy passes; otherwise throws a typed availability error |
| estimate() | Returns a labeled stale/ready estimate, or null with no usable anchor; never substitutes system time |
| sync() / forceResync() | Awaits the shared sync cycle and returns a structured outcome |
| status / events | Reports availability, sync activity, lifecycle events, and source failures |
| dispose() | Cancels owned work and releases resources; safe to repeat |

Initialization is idempotent for equivalent configuration. Conflicting reconfiguration fails explicitly. Document disposal and reinitialization behavior. No hidden global testing state may leak between tests.

## 8. Persistence and lifecycle

Persist a versioned anchor record atomically. Restore it only when its monotonic epoch and clock continuity are demonstrably valid. Current uptime being larger than stored uptime is insufficient proof that no reboot occurred.

If reliable continuity evidence is unavailable after process restart, treat stored UTC as diagnostic information and establish a fresh anchor before strict reads. Web anchors are session-scoped by default and must not be restored across page sessions.

Corrupt, unsupported, or inaccessible storage must not crash startup or fabricate trust. A valid in-memory anchor may continue if persistence fails; emit a diagnostic. Secure storage does not by itself prove freshness or prevent rollback.

Refresh on foreground resume when stale or continuity is uncertain. Background scheduling is best effort and must report whether it performs a real sync or merely schedules a foreground refresh. Initial release correctness must not depend on background execution.

## 9. Platform qualification

| Platform | Qualification required |
| --- | --- |
| Android | Sleep-inclusive elapsed clock, lifecycle handling, restart/reboot validation |
| iOS/macOS | Continuous clock behavior through sleep, safe lifecycle integration, documented restore limits |
| Windows/Linux | Suspend/resume behavior, clock epoch identity, native resource cleanup |
| Web/WASM | Session-scoped projection, suspension checks, HTTPS/CORS fallback, no socket-only imports |

The target is all six existing platform families. A platform is supported only after its capability and acceptance tests pass. Publish unsupported capabilities explicitly; minimum Flutter, Dart, and OS versions remain open pending the audit.

## 10. Security and privacy

Describe the core as resistant to ordinary device clock changes under an uncompromised runtime. Unauthenticated NTP consensus cannot guarantee protection from an attacker controlling network responses. Source diversity mitigates some failures but does not prove truth.

If authenticated mode is added, acceptance requires validated NTS key establishment and authenticated NTP packets. A successful TLS handshake alone is insufficient. Authentication metadata must describe the evidence actually used to create the selected anchor. Strict authenticated requests fail on unsupported platforms or verification failure and never silently downgrade. [RFC 8915](https://www.rfc-editor.org/rfc/rfc8915.html)

Do not disable TLS certificate validation to work around incorrect device time. Return a structured bootstrap failure instead. Default telemetry is off. Document contacted endpoints and allow applications to configure providers. Logs must exclude key material and unnecessary identifiers.

## 11. Acceptance criteria

1. Moving the device wall clock forward or backward by one day does not change projected UTC from an existing continuous anchor.
2. A simulated one-hour offline interval advances projected UTC by one hour and increases uncertainty according to the configured budget.
3. Sleep-inclusive platform tests preserve elapsed time; adapters that cannot do so downgrade before strict reads resume.
4. A reboot cannot reuse an old anchor solely because the new uptime exceeds the previously recorded uptime.
5. A failed refresh preserves a valid anchor. Crossing age or uncertainty limits makes strict reads fail and explicit estimates report stale.
6. A rogue outlier cannot satisfy quorum alone. Duplicate/provider-correlated sources do not count as independent groups. Conflicting clusters fail deterministically.
7. Synchronization terminates within its deadline; concurrent callers share a cycle; late callbacks cannot overwrite newer state.
8. Storage failures, missing HTTPS headers, blocked UDP, DNS failures, and TLS errors produce typed outcomes without system-time fallback.
9. Each qualified platform passes foreground/resume tests. Web/WASM builds without unsupported socket imports.
10. Tests use injected monotonic clocks, source transports, storage, and schedulers. Live network checks are a separate integration suite.
11. Benchmark synchronous read latency and allocations in release builds on representative devices; publish measured results and conditions before setting a performance claim.

## 12. Delivery and remaining decisions

Milestone A: audit the fork at a pinned commit; inventory API, dependencies, licenses, adapters, and tests; map each requirement to an existing implementation or a change.

Milestone B: implement and test the clock model, explicit states, sync policy, and familiar API facade.

Milestone C: qualify native adapters and Web/WASM; add migration examples, diagnostics, and measured performance documentation.

Milestone D: consider authenticated NTS and genuine background synchronization only after the timestamp core is reliable.

Open decisions: preserve API compatibility versus a breaking major release; initial platform release priority; acceptable offline age/uncertainty for the consuming app; package name and publishing ownership; final provider list and SDK constraints. Recommended starting approach: preserve useful public entry points, require a major version for changed failure semantics, and keep advanced security optional.
