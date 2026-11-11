# Implementation status

Updated 12 November 2026. This is a new package; compatibility with the upstream API is not promised. See SPECIFICATION.md for the current contract and REVIEW_REPORT.md for the nine original findings.

| Area | Implemented | Remaining qualification |
| --- | --- | --- |
| Clock | QPC, BOOTTIME, continuous Apple clock; capability and sampling-error metadata | Physical sleep/resume and release-device precision |
| Synchronization | Cooperative cancellation, owned transport cleanup, cross-cycle permits, queued resume replacement | Live network and device stress |
| Lifecycle | Independent foreground scheduling and anchor continuity | Android/iOS physical lifecycle |
| Persistence | Optional secure storage, typed v2 records, policy/evidence validation, serialized real writes | Native keyrings, backup/restore, storage failures |
| Epoch proof | Android public boot count plus no-backup installation marker; Linux boot UUID | Native integration; Apple/Windows intentionally unavailable by default |
| API | Value configuration identity, restored readiness/origin, injectable diagnostics | Consumer API feedback |
| Hosts | Generated Android/iOS/macOS/Windows/Linux/web example projects | Native release builds and archive privacy review |
| Toolchains | Exact minimum/current dependency resolution, analysis and 76 tests on Windows | CI platform/toolchain matrix |
| Provenance | Pinned upstream LICENSE/NOTICE retained; selected dependency license inventory | Full release dependency/provenance review |

The supplied workflows define qualification jobs; they have not been executed remotely. Publishing remains disabled. NTS, system-clock fallback, and OS background workers are excluded.
