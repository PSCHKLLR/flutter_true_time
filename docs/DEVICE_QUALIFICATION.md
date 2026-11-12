# Native and browser qualification

These are required manual gates, not results. Record device/OS/build versions, commands, elapsed-time observations, source digest, and logs; hash evidence before changing a gate to passed. Generated debug-signed examples are not store uploads.

## Native persistence harness

From example/, use the same installed application and device for successive phases:

```sh
flutter test integration_test/restart_test.dart -d <device-id> --dart-define=TRUE_TIME_RESTART_PHASE=seed
flutter test integration_test/restart_test.dart -d <device-id> --dart-define=TRUE_TIME_RESTART_PHASE=same-boot
# Reboot the device/host without uninstalling the app, then:
flutter test integration_test/restart_test.dart -d <device-id> --dart-define=TRUE_TIME_RESTART_PHASE=changed-boot
```

The harness uses deterministic, explicitly unauthenticated test sources and a separate qualification namespace. Seed verifies actual backend readback. Android/Linux require real epoch proof and same-boot restoration; Apple/Windows/web must not restore through the default provider. If the runner reinstalls by clearing application data, it cannot qualify a same-installation restart: record that run blocked and use an installation-preserving driver.

For backup testing, seed, create an OS-supported backup, restore into a fresh Android installation, and run changed-boot (the phase also asserts unavailable for an installation mismatch). The no-backup installation marker must not transfer. Record whether encrypted state was readable or rejected; neither path may produce ready time from the old installation. Do not use private boot identifiers.

For unavailable storage/keyrings, seed while storage works, stop the app, deny access/stop the test keyring in a disposable test environment, and run unavailable-storage. Expect no restored anchor or uncaught error. Restore the test environment afterward. Validate storage diagnostic events separately; core mocks do not qualify native keyrings.

## Physical lifecycle

Run the normal demo, obtain time, then disconnect networking. Record UTC/uncertainty, lock or suspend the device for a measured external interval, and resume. Native continuous clocks must include sleep in elapsed UTC within reported uncertainty; portable clocks must become unavailable until fresh synchronization. Automatic refresh must pause while backgrounded. Test Android and iOS physical devices; a simulated lifecycle callback is insufficient.

## Browser

Use two caller-operated HTTPS endpoints and distinct provider labels with the example dart-defines. Verify HEAD, TLS, no-store, exposed Date/Cache-Control/Age headers, CORS failure, redirects, cancellation, and offline behavior. Run both JavaScript and WebAssembly builds in Chrome, record the browser version, and reload the page offline: a previous anchor must not restore. Missing endpoints block this gate; compiled empty configuration and mocked HTTP tests do not pass it.

## Apple archives

Run the trusted Xcode 27.2 workflow on Apple silicon. Inspect iOS simulator/unsigned-release and macOS outputs, dependency privacy manifests, and actual required-reason API use. Record justified declarations and archive contents; do not invent a privacy reason. Inspect UIScene lifecycle behavior on a physical iOS device.
