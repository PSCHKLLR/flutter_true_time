# First-release validation

The first public release remains blocked. The guarded Pub preview succeeded with zero warnings and selected 165 files. The payload includes the top-level license and complete upstream and Flutter template notices. [Release gates](release_gates.json) · [Current qualification evidence](evidence/first-release-qualification.json)

Both pinned SDKs passed Windows formatting and analysis, 110 core and facade tests, two example tests, and eight mocked Chrome source tests. Windows release builds require a suitable Visual Studio C++ toolchain. Web JS and WASM compilation ran on both SDKs. The live endpoint and offline reload checks remain open.

The baseline, current, and built-in Kotlin Android lanes each produced a release APK and AAB on JDK 17. The current evidence records each artifact hash and the Gradle, AGP, and Kotlin versions reported by the build.

The Windows Dart AOT smoke run measured `now()` and `read()` using the QPC adapter. Representative release-build timing and allocation evidence remains open. Public checks returned HTTP 404 for the package name and showed that private vulnerability reporting is disabled on the repository. Upstream and collected dependency notice hashes were verified. Human and native redistribution review remains open.

## Earlier qualification snapshot

12 November 2026, Windows x64. Source digest `bc95cb148d87d09a324da954e86e6cd99fae11efcbffc52d3714674a0ae1d8b4`.

| Check | Result |
| --- | --- |
| Flutter 3.41.0 / Dart 3.11.0 | Independent resolution; analysis clean; 106 tests and example widget test passed |
| Flutter 3.47.9 / Dart 3.13.7 | Independent resolution; analysis clean; 106 tests and example widget test passed |
| Android baseline | APK and AAB passed; AGP 8.11.1, Gradle 8.14, Kotlin 2.2.20, JDK 17.0.21+9 |
| Android current | APK and AAB passed; AGP 9.1.0, Gradle 9.3.1, Kotlin 2.4.0, JDK 17.0.21+9 |
| Android built-in Kotlin | APK and AAB passed; same current versions, built-in enabled, legacy Android Kotlin plugin absent |
| Web JS/WASM | Both release variants built on both pinned SDKs; all four rendered in Chrome 157.0.8103.40 with intended entrypoints and no uncaught page errors |
| Chrome source regression | 8 mocked HTTPS/cancellation tests passed per SDK; live HTTPS/CORS blocked because caller-operated endpoints were unavailable |
| Source portability | Fresh LF and Windows-autocrlf clones produced identical canonical digests; Linux checkout execution still pending |
| Windows release | Both exact SDK attempts blocked by missing suitable Visual Studio toolchain |
| Linux / Apple | Blocked: no Linux environment or Apple silicon Xcode 27.2 runner available here |
| Physical lifecycle, native storage, reboot/backup | Blocked: devices/keyrings unavailable; executable restart harness supplied |
| GitHub qualification workflows | Updated and syntax checked locally; enhanced revision not pushed or run remotely |

The five review corrections have regression coverage, including delayed restoration, quorum retention at deadline, NTP error cleanup, unknown provider labels, and source/evidence tampering. The Android configuration round-trip test also checks AGP settings classpath alignment and modern Kotlin compiler options. Android artifacts use the generated debug signing configuration for compilation checks only.

Exact commands, exit codes, resolved dependency locks, runtime Maven graphs, artifact hashes, and toolchains are in evidence/enhancement-minimum.json, evidence/enhancement-current.json, and evidence/enhancement-builtin.json. Browser and checkout records are in evidence/enhancement-browser-startup.json and evidence/enhancement-checkout-portability.json. Older evidence files are historical.

The three Android build gates passed on this earlier snapshot. Evidence for a different source digest is historical.
