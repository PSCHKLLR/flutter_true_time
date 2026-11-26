# Native and browser qualification

For `0.1.0-dev.1`, the owner directed us to skip testing on physical hardware. Record simulator, emulator, and VM results with the OS and build versions, commands, observations, source digest, and logs. Identify the test environment in each result.

## Native persistence harness

From `example/`, choose a fresh run ID (8–64 ASCII letters, digits, underscores, or hyphens). Use the same ID, installed application, and device for successive phases:

```sh
flutter test integration_test/restart_test.dart -d <device-id> --dart-define=TRUE_TIME_RESTART_RUN_ID=<run-id> --dart-define=TRUE_TIME_RESTART_PHASE=seed
flutter test integration_test/restart_test.dart -d <device-id> --dart-define=TRUE_TIME_RESTART_RUN_ID=<run-id> --dart-define=TRUE_TIME_RESTART_PHASE=same-boot
# Android/Linux only. Reboot without uninstalling, then wait until uptime exceeds seed uptime.
flutter test integration_test/restart_test.dart -d <device-id> --dart-define=TRUE_TIME_RESTART_RUN_ID=<run-id> --dart-define=TRUE_TIME_RESTART_PHASE=changed-boot
```

Seed verifies the namespace was empty and checks the persisted record against the current boot proof and monotonic sample bounds. Android and Linux require the record to remain readable through restart. The reboot phase verifies the installation is unchanged, the epoch changed, and current uptime exceeds the saved anchor's uptime. On iOS, macOS and Windows, the offline restart must remain unavailable even with a readable record. Run the Web restart in the browser procedure below. If the runner clears application data, use an installation-preserving driver. Record durations and match results without logging raw epoch or installation identifiers.

For backup testing, seed, create an OS-supported backup, restore into a fresh Android installation, and run `backup-restore` with the same run ID. If the platform rejects or omits the encrypted value, record evidence that the backup and restore ran and pass `--dart-define=TRUE_TIME_BACKUP_UNREADABLE=true`. If the value is readable, the harness requires the saved installation scope to differ from the current scope. The no-backup installation marker must stay local to the original installation.

For unavailable storage/keyrings, seed while storage works, stop the app, deny access or stop the test keyring in a disposable environment, and run `unavailable-storage` with the same run ID. The harness requires an actual storage error or timeout, a diagnostic event, and no restored anchor. Restore access afterward and repeat `same-boot` to confirm the original record is still present.

## Physical lifecycle deferred

Physical sleep and resume testing is deferred for this release. For any lifecycle checks run in a virtual environment, record the UTC and uncertainty before and after the transition and identify the transition exercised.

## Read performance

Issue #10 adds a shared offline fixture, a standalone release app with JSON export, a profile integration driver, and separate host GC telemetry. Follow the [native measurement procedure](NATIVE_READ_PERFORMANCE.md) for paired before/after runs. Representative Android and iOS release-build latency, allocation/GC, and native resource observations remain pending until executed on physical targets.

Measure synchronous `now()` and `read()` on representative release builds. Record the hardware, OS, SDK, clock adapter, build mode, warmup, iteration count, latency distribution and allocations per read. Use an allocation profiler appropriate to the target and distinguish sampled results from exact counts. `tool/benchmark.dart` provides a Windows/Linux/macOS AOT latency smoke measurement when compiled with `dart compile exe`. Record representative mobile and browser results separately. Attach the methodology and raw results to the `read_performance` gate.

## Browser

Use two independently operated HTTPS endpoints and distinct provider labels with the example dart-defines. Verify HEAD, TLS, no-store, exposed Date/Cache-Control/Age headers, CORS failure, redirects, cancellation, and offline behavior. Run both JavaScript and WebAssembly builds in Chrome and record the browser version. Reload offline and verify the previous anchor is unavailable.

## Apple archives

Run the trusted Xcode 27.2 workflow on Apple silicon. Inspect iOS simulator/unsigned-release and macOS outputs, dependency privacy manifests, and actual required-reason API use. Record justified declarations and archive contents; do not invent a privacy reason. Inspect UIScene lifecycle behavior on a physical iOS device.
