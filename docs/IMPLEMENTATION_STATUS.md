# Implementation and release status

The first public prerelease, `0.1.0-dev.1`, was published on 14 November 2026. [Published package](https://pub.dev/packages/flutter_true_time/versions/0.1.0-dev.1)

The engine now queues persistence for deadline-accepted anchors. The native harness checks the seed and boot evidence, and the full candidate checker binds approval to exact Pub-selected bytes. Public APIs, persistence v2, and freshness, quorum, and drift defaults are unchanged.

| Area | Status |
| --- | --- |
| Runtime and release checks | Deadline persistence, native restart assertions, exact candidate selection, and digest-bound approval are implemented |
| Builds and tests | The SDK matrices, Windows and Linux release builds, three Android lanes, and Web gate passed before the release checker gained the physical lifecycle waiver. The manifest requires evidence for the regenerated digest. |
| Native and performance qualification | Physical lifecycle is waived for `0.1.0-dev.1`. Native restart and storage, Apple archive inspection, and representative read measurements remain open. Windows and browser measurements are recorded in VALIDATION.md. |
| Rights and qualification | Notice hashes verified. Human and native dependency review and private reporting verification remain open. |

See [validation](VALIDATION.md), [device qualification](DEVICE_QUALIFICATION.md), [Apple privacy audit](APPLE_PRIVACY_AUDIT.md), and [publishing](PUBLISHING.md).
