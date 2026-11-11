# Example application

The six host projects are checked in; do not regenerate them during normal development.

From the package root run flutter pub get, then:

```sh
cd example
flutter devices
flutter run -d <device-id>
flutter test
```

Native targets use two independent NTP providers. The demo enables optional secure persistence under dev.pschkllr.flutter_true_time_example. Android/Linux may restore within a proven boot epoch; other targets synchronize again after restart. A reboot requires network time. Android INTERNET permission and macOS network entitlements are included.

For web, supply two independent, caller-operated HTTPS Date endpoints and provider identities:

```sh
flutter run -d chrome --dart-define=TRUE_TIME_HTTPS_A=https://a.example/time --dart-define=TRUE_TIME_PROVIDER_A=provider-a --dart-define=TRUE_TIME_HTTPS_B=https://b.example/time --dart-define=TRUE_TIME_PROVIDER_B=provider-b
```

Endpoints must meet README freshness and CORS requirements. Missing configuration displays unavailable time. Compilation without endpoints is supported but does not demonstrate network synchronization.

Run dart run tool/configure_android.dart baseline (or current/builtin) from the package root to select a qualification lane. Android API 24, iOS 15, and macOS 12 are the deployment floors. Apple qualification requires the specified Mac/Xcode runner; generated hosts alone do not establish compatibility.

Run flutter test integration_test/platform_clock_test.dart -d <device-id> inside example/ for the host clock smoke test. Physical suspend/resume and offline restart still require the manual qualification scenarios.

Use normal flutter build commands for release hosts. Flutter 3.41 skips platform registrant regeneration with --no-pub, which can leave dev-only integration-test registrations in an Android release build. CI intentionally allows the build preparation step.
