# First-release validation

The revised CI workflows resolve Dart dependencies without preparing native example hosts in core jobs. They compare the source fingerprint before and after analysis and tests. Apple build jobs capture both the input fingerprint and the prepared-host fingerprint. Android jobs install the NDK required by both pinned Flutter versions before invoking Gradle, with up to three install attempts.

On Windows, both pinned SDKs passed analysis, 110 core and facade tests, and two example tests with the revised workflow sequence. Both copies preserved the new source fingerprint. A mock `sdkmanager` verified the retry behavior. Hosted validation remains open. The results below apply to `22507ec` and earlier source fingerprints. [Workflow validation](evidence/first-release-ci-workflow-validation.json)

On `3849c56`, all three local Android lanes rebuilt an APK and an AAB against the revised fingerprint. The toolchains and six artifact hashes were verified. Windows Dart AOT and optimized browser JS/WASM read latency were also measured. Chrome recorded sampled JS allocations. Mobile release builds and native and WASM allocation measurements remain open. [Android rebuilds](evidence/first-release-android-workflow-rebuilds.json) · [Read performance](evidence/first-release-read-performance.json)

The Web gate passed on `3849c56`. Chrome ran the JS and WASM release builds from both pinned Flutter SDKs with the live `httpbin.org` and `httpbingo.org` HTTPS fixtures. All four runs reached ready with two provider groups, rejected hidden Date, CORS, nonzero Age and redirect controls, and aborted a delayed Fetch. On reload with both time origins blocked, the encrypted anchor remained in browser storage and the clock reported unavailable. [Live Web evidence](evidence/first-release-web-live.json)

The Android provenance audit resolved 59 distinct Maven runtime modules across the three build lanes. Cached POMs declared licenses for 51 modules. The other eight were Flutter engine and embedding coordinates. All six APKs and AABs contained native binaries and readable Flutter notice bundles with the expected engine component headings. Hosted Dart packages in all ten local lockfiles matched the license catalog. The provenance gate remains partial pending human review and the remaining native artifacts. [Provenance evidence](evidence/first-release-android-provenance.json)

On Windows x64, the Dart 3.13.7 AOT fixture recorded about 431 bytes of observed young-generation growth per `now()` or `read()` call across three two-million-call runs each. Rounding contributes up to about 22 bytes per call to that estimate. The interval excludes the first and last partial GC spans. Direct native allocation profiling remains open. [Performance evidence](evidence/first-release-read-performance.json)

The optimized Dart WASM fixture measured 678.1–678.4 bytes of aggregate V8 managed-heap growth per read in six standalone Node runs. Chrome's V8 heap sampler estimated 384.7–398.4 bytes per call for the same compiled fixture across three fresh browser profiles. Both methods used a no-read baseline and retained-object control. The two measurements use different V8 builds and accounting methods. Direct native profiling and representative mobile measurements remain open. [Performance evidence](evidence/first-release-read-performance.json)

The first public release remains blocked. The guarded Pub preview succeeded with zero warnings and selected 165 files. The payload includes the top-level license and complete upstream and Flutter template notices. [Release gates](release_gates.json) · [Current qualification evidence](evidence/first-release-qualification.json)

Both pinned SDKs passed Windows formatting and analysis, 110 core and facade tests, two example tests, and eight mocked Chrome source tests. The local Windows release builds require a suitable Visual Studio C++ toolchain. All four Web release builds rendered in Chrome with their intended JS or WASM entrypoint and no uncaught runtime errors. Live HTTPS/CORS and offline reload after a successful sync remain open. [Browser startup evidence](evidence/first-release-browser-startup.json)

GitHub Actions passed all six SDK core jobs and all four Windows and Linux release build jobs on `22507ec`. The archive hashes matched GitHub's published digests. Nine artifacts recorded the release fingerprint. The Flutter 3.41.0 macOS artifact recorded two new Podfiles and four changed xcconfig files, so the minimum-SDK gate remains partial. [CI artifact review](evidence/first-release-ci-compatibility.json)

The overall compatibility run failed on the Android current lane. The Linux runner's `sdkmanager` rejected the downloaded NDK 28.2.13676358 ZIP during project configuration. This lane built both artifacts in the recorded Windows qualification. [Failed GitHub job](https://github.com/PSCHKLLR/flutter_true_time/actions/runs/43212797316/job/131164401671)

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
