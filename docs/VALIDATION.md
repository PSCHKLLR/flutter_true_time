# Validation record

12 November 2026; Windows x64. Commands were executed locally, not inferred from workflow definitions.

| Check | Result |
| --- | --- |
| Flutter 3.41.0 / Dart 3.11.0, independently resolved graph | Analysis clean; all 76 core/facade tests passed |
| Flutter 3.47.9 / Dart 3.13.7, independently resolved graph | Analysis clean; all 76 core/facade tests passed |
| Installed Flutter 3.41.8 / Dart 3.11.5 | 76 tests passed with coverage; example widget test passed |
| Complete Flutter web JavaScript application | Release build passed (3.41.8) |
| Complete Flutter web WebAssembly application | Release build passed (3.41.8); nonfatal missing Cupertino font-family warning emitted |
| Native Windows clock / local transports | Exercised by VM tests; local NTP cancellation releases the UDP port, HTTPS cancellation closes its client |
| Windows release host | Blocked: suitable Visual Studio toolchain unavailable |
| Android release APK / AAB | Passed on Flutter 3.41.8, AGP 8.11.1 / Gradle 8.14 / KGP 2.2.20, JDK 21; API 24 floor. Required JDK 17 lanes and AGP 9 remain pending |
| Android device qualification | No connected device; some SDK licenses remain unaccepted. No physical lifecycle/restoration qualification |
| Apple Xcode 27.2 / iOS / macOS | Blocked: no Mac/Xcode runner available here |
| Linux native host/keyring | Not executed on this Windows host |
| Physical lifecycle, same-boot app restart, backup restore, unavailable keyrings | Pending device/native integration qualification |
| Chrome core source tests / Dart 3.11.0 | 8 HTTPS validation/cancellation tests passed with mocked HTTP transport |
| Flutter-rendered Chrome test attempt | Stalled during test loading; stopped without executing tests. Not a pass |
| Remote CI | Not executed; workflows supplied for qualification |

Tests use injected clocks, sources, epochs and storage, plus loopback UDP; they do not prove public providers' availability or independence. Web builds without configured endpoints exercise compilation, not CORS or live synchronization. Secure-storage namespace behavior is mocked in facade tests; native keychain/keyring behavior remains unqualified.

Regressions cover all nine review findings, outstanding transport cancellation, noncooperative query permits, timed-out writes, background cycles, restored readiness, malformed/expired/policy-mismatched records, boot/install mismatch, equivalent sources, and pending timeout cleanup on disposal. No numeric coverage promise is made.

The gate file remains fail-closed. Do not advertise all six platforms or Xcode compatibility until platform builds, browser execution, physical lifecycle, privacy and archive checks have evidence. Re-run the exact SDK lanes after changing dependency constraints or runtime code.

Workflow YAML files were parsed successfully, Android lane configuration round-tripped through current/built-in/baseline in an isolated copy, and final Dart formatting/static analysis were clean. The release checker exits 1 for pending gates as intended.

The first Android attempts failed because --no-pub skipped release plugin regeneration and retained a dev-only integration-test registration. Normal flutter build regenerated the registrant and the APK and AAB passed. Host-build workflows now omit --no-pub. The built-in Kotlin configuration also removes the legacy kotlinOptions DSL and inherits Java 17 target compatibility; its AGP 9 build remains pending.

The example release artifacts use the generated debug signing configuration for compilation checks; they are not store-ready uploads. No signing credentials were added.
