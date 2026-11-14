# First-release implementation status

The engine now queues persistence for deadline-accepted anchors. The native harness checks the seed and boot evidence, and the full candidate checker binds approval to exact Pub-selected bytes. Public APIs, persistence v2, and freshness, quorum, and drift defaults are unchanged.

| Area | Status |
| --- | --- |
| Runtime and release checks | Deadline persistence, native restart assertions, exact candidate selection, and digest-bound approval are implemented |
| Builds and tests | The SDK matrices, Windows and Linux release builds, three Android lanes, and Web gate passed before the release checker gained the physical lifecycle waiver. The manifest requires evidence for the regenerated digest. |
| Native and performance qualification | Physical lifecycle is waived for `0.1.0-dev.1`. Native restart and storage, Apple archive inspection, and representative read measurements remain open. Windows and browser measurements are recorded in VALIDATION.md. |
| Rights and publication | Notice hashes verified. Human and native dependency review, private reporting, uploader access, and candidate review remain open |

See VALIDATION.md, DEVICE_QUALIFICATION.md, APPLE_PRIVACY_AUDIT.md and PUBLISHING.md. The development checkout retains `publish_to: none`.
