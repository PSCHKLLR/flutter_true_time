# Compatibility targets and evidence

Version 2.0.0 renames the facade, engine, configuration, and exception types to `TrueTime`, `TrueTimeEngine`, `TrueTimeConfig`, and `TrueTimeException`. Versions through 1.0.0 use the `TrustedTime` names. Existing platform qualification evidence predates this breaking rename; local regression tests do not qualify unexecuted platform lanes.

The shared Dart readiness path returns the same reading it validated as ready on every platform, including at age and uncertainty boundaries. This correction does not change platform support or establish physical-device qualification; see the [readiness contract](SPECIFICATION.md#state-and-synchronization).

Persisted sequences use the same bounded exact integer range on native and JavaScript targets. The sequence regressions run in the core SDK/OS lanes and in Chrome on both pinned SDKs. Older version-2 records above `AnchorRecord.maxSequence` are rejected and require fresh synchronization; see the [persistence contract](SPECIFICATION.md#persistence-and-restart-policy).

Native NTP cleanup tests assert socket closure and listener cancellation through injected DNS/bind transports, including late setup results and queued receive events. A negative fixture retains a real OS socket to verify that the ownership assertions detect a leak. Loopback protocol/cancellation tests remain separate and do not depend on immediate ephemeral-port reuse. The full suites run on Windows, Linux, and macOS on both pinned SDKs; macOS additionally repeats the focused ownership/loopback suites five times per lane. These host checks do not establish physical-device qualification.

Android and iOS jobs block the compatibility workflow on failure. Hosted iOS jobs build for the simulator and for devices without signing on both pinned Flutter SDKs. The manual Xcode 27.2 workflow provides additional iOS qualification, with its macOS build reported as advisory. Shared core, desktop, Web, and published package smoke checks are advisory in CI.

Standalone compatibility runs cover PRs (including forks), pushes to `main`, and manual requests. Feature-branch pushes and release tags do not start standalone matrices. Release tags use the publishing workflow's strict reusable matrix, where every job is required before upload. Only superseded standalone PR runs are cancelled. See the [event coverage and concurrency policy](PUBLISHING.md#compatibility-event-coverage).

The first public prerelease is `0.1.0-dev.1`. The matrix below describes the available platform test evidence. [Published package](https://pub.dev/packages/flutter_true_time/versions/0.1.0-dev.1)

The [release manifest](release_gates.json) records the status for the current source digest. See [validation](VALIDATION.md) for results and [device qualification](DEVICE_QUALIFICATION.md) for physical and live-network procedures.

The matrix records platform results before the release checker gained the physical lifecycle waiver. Consult the release manifest for gate status on the regenerated digest.

| Lane | Pinned target | Current evidence |
| --- | --- | --- |
| Minimum SDK | Flutter 3.41.0 / Dart 3.11.0 | Formatting, analysis, core and facade tests, and example tests passed on Windows, Linux, and macOS. |
| Current SDK | Flutter 3.47.9 / Dart 3.13.7 | Formatting, analysis, core and facade tests, and example tests passed on Windows, Linux, and macOS. |
| Android baseline | AGP 8.11.1 / Gradle 8.14 / Kotlin 2.2.20 / JDK 17 | APK and AAB build qualification. See the current gate for evidence. |
| Android current | AGP 9.1.0 / Gradle 9.3.1 / Kotlin 2.4.0 / JDK 17 | APK and AAB build qualification. See the current gate for evidence. |
| Android built-in Kotlin | AGP 9.1.0 / Gradle 9.3.1 / Kotlin compiler 2.4.0 / JDK 17; no legacy plugin | APK/AAB passed; compiler alignment is in settings classpath |
| Apple | Xcode 27.2 / Apple silicon, both SDKs; iOS 15+, macOS 12+ | Blocked; no Mac or archive/device evidence |
| Windows | x64 / QPC, both SDKs | Both hosted release builds passed. Native suspend and storage qualification remain open. |
| Linux | x64 / BOOTTIME, both SDKs | Both hosted release builds passed. Native suspend, keyring, and epoch qualification remain open. |
| Web | JS/WASM on both SDKs | All four release builds passed live HTTPS/CORS and offline reload in Chrome on the current digest. |
| Read performance | Representative release-build latency and allocations | Windows AOT and browser latency and allocation measurements are recorded. Representative mobile measurements remain open. |

Android API 24 remains the floor. The package bridge uses Java 17; Kotlin versions describe example hosts. Modern typed AGP extension configuration and compilerOptions replace deprecated DSL accessors. Built-in Kotlin alignment upgrades the AGP runtime compiler without applying the legacy Android Kotlin plugin; no dependency-validation bypass was used. [Android runtime KGP guidance](https://developer.android.com/build/releases/agp-9-0-0-release-notes#runtime-dependency-on-kotlin-gradle-plugin)

| Platform | Restore after app restart by default |
| --- | --- |
| Android | Only matching verified boot and installation |
| Linux | Only matching verified kernel boot UUID and application scope |
| iOS/macOS and Windows | Unavailable without a separately qualified epoch provider |
| Web | Never across page/browser restart |

Physical lifecycle testing is waived for `0.1.0-dev.1`. The native persistence gate can use simulator, emulator, or VM evidence for the scenarios those environments support.
