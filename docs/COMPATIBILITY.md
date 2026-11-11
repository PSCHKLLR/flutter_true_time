# Compatibility targets

Targets are pinned for qualification, not claims of completed platform support. See VALIDATION.md for executed checks.

| Lane | Target | Current evidence |
| --- | --- | --- |
| Minimum SDK | Flutter 3.41.0 / Dart 3.11.0 | Windows resolution, analysis, 76 tests passed |
| Current SDK | Flutter 3.47.9 / Dart 3.13.7 | Windows resolution, analysis, 76 tests passed |
| Android baseline | AGP 8.11.1 / Gradle 8.14 / KGP 2.2.20 / JDK 17 | APK/AAB passed on JDK 21 / Flutter 3.41.8; specified JDK 17 lane pending |
| Android current | AGP 9.1.0 / Gradle 9.3.1 / KGP 2.4.0 / JDK 17 | Host configuration provided; build pending |
| Android built-in Kotlin | AGP 9.1.0 / Gradle 9.3.1 / no legacy Kotlin plugin | Host configuration provided; build pending |
| Apple | Xcode 27.2 / Apple silicon; iOS 15+, macOS 12+ | UIScene hosts supplied; Mac builds/device checks blocked here |
| Windows | x64 / QPC | Unit/native clock tests pass; release host pending |
| Linux | x64 / BOOTTIME | Host supplied; release and keyring checks pending |
| Web | JavaScript and WebAssembly | See build evidence; browser/network qualification pending |

Android API 24 is the minimum. Kotlin versions describe the host: the package bridge uses Java 17. Secure-storage native dependencies must pass every applicable lane. Apple's privacy manifest and final archive inspection remain release gates.

| Platform | UTC after successful sync | Restore after app restart by default |
| --- | --- | --- |
| Android | Planned | Same verified boot and installation only |
| Linux | Planned | Same verified kernel boot UUID only |
| iOS / macOS | Planned | Unavailable without a separately qualified epoch provider |
| Windows | QPC exercised on this machine | Unavailable without a separately qualified epoch provider |
| Web | Explicit HTTPS sources required | Never across page/browser restart |

All six platforms must pass the release gates before broad support is advertised. CI files are recipes, not test evidence.
