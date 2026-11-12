# First-release implementation status

The engine now queues persistence for deadline-accepted anchors. The native harness checks the seed and boot evidence, and the full candidate checker binds approval to exact Pub-selected bytes. Public APIs, persistence v2, and freshness, quorum, and drift defaults are unchanged.

| Area | Status |
| --- | --- |
| Runtime and release checks | Deadline persistence, native restart assertions, exact candidate selection, and digest-bound approval are implemented |
| Builds and tests | Current SDK, Android, and Web evidence is tracked in VALIDATION.md and release_gates.json |
| Native, browser, and performance qualification | Physical lifecycle, native restart/storage, live HTTPS/CORS, Apple archive inspection, and representative allocation measurements remain open |
| Rights and publication | Notice hashes verified. Human and native dependency review, private reporting, uploader access, and candidate review remain open |

See VALIDATION.md, DEVICE_QUALIFICATION.md, APPLE_PRIVACY_AUDIT.md and PUBLISHING.md. The development checkout retains `publish_to: none`.
