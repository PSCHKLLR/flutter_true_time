# Compatibility targets and evidence

The [release manifest](release_gates.json) records the status for the current source digest. See [validation](VALIDATION.md) for results and [device qualification](DEVICE_QUALIFICATION.md) for physical and live-network procedures.

The matrix identifies current results and historical runs. The revised workflows need fresh hosted evidence against the current source fingerprint.

| Lane | Pinned target | Current evidence |
| --- | --- | --- |
| Minimum SDK | Flutter 3.41.0 / Dart 3.11.0 | Local Windows tests passed on the current digest. In the earlier hosted run, macOS tests passed with a different fingerprint after Flutter changed the Apple example hosts. |
| Current SDK | Flutter 3.47.9 / Dart 3.13.7 | Local Windows tests passed on the current digest. The earlier hosted run passed analysis and tests on Windows, Linux, and macOS. |
| Android baseline | AGP 8.11.1 / Gradle 8.14 / Kotlin 2.2.20 / JDK 17 | APK and AAB build qualification. See the current gate for evidence. |
| Android current | AGP 9.1.0 / Gradle 9.3.1 / Kotlin 2.4.0 / JDK 17 | APK and AAB build qualification. See the current gate for evidence. |
| Android built-in Kotlin | AGP 9.1.0 / Gradle 9.3.1 / Kotlin compiler 2.4.0 / JDK 17; no legacy plugin | APK/AAB passed; compiler alignment is in settings classpath |
| Apple | Xcode 27.2 / Apple silicon, both SDKs; iOS 15+, macOS 12+ | Blocked; no Mac or archive/device evidence |
| Windows | x64 / QPC, both SDKs | Both CI release builds passed on the earlier digest. Current-digest release builds, native suspend, and storage qualification remain open. |
| Linux | x64 / BOOTTIME, both SDKs | Both CI release builds passed on the earlier digest. Current-digest release builds, native suspend, keyring, and epoch qualification remain open. |
| Web | JS/WASM on both SDKs | All four release builds passed live HTTPS/CORS and offline reload in Chrome on the current digest. |
| Read performance | Representative release-build latency and allocations | Windows AOT and browser latency and allocation measurements are recorded. Representative mobile measurements remain open. |

Android API 24 remains the floor. The package bridge uses Java 17; Kotlin versions describe example hosts. Modern typed AGP extension configuration and compilerOptions replace deprecated DSL accessors. Built-in Kotlin alignment upgrades the AGP runtime compiler without applying the legacy Android Kotlin plugin; no dependency-validation bypass was used. [Android runtime KGP guidance](https://developer.android.com/build/releases/agp-9-0-0-release-notes#runtime-dependency-on-kotlin-gradle-plugin)

| Platform | Restore after app restart by default |
| --- | --- |
| Android | Only matching verified boot and installation |
| Linux | Only matching verified kernel boot UUID and application scope |
| iOS/macOS and Windows | Unavailable without a separately qualified epoch provider |
| Web | Never across page/browser restart |

All six-platform and native persistence gates remain required before release. Build success does not qualify physical behavior.
