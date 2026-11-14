# Apple privacy audit: blocked pending Mac qualification

Static source inventory, 12 November 2026:

- The Dart clock adapter dynamically calls mach_continuous_time and mach_timebase_info. No private sysctl or boot-session UUID is used.
- The optional secure-storage adapter uses flutter_secure_storage_darwin 0.4.3 in the resolved graphs. Its packaged Resources/PrivacyInfo.xcprivacy declares no tracking, collected-data types, or accessed-API entries.
- That dependency manifest does not establish coverage for this package's clock calls or the consuming app's use of derived timestamps.

Apple documents `mach_continuous_time` as a sleep-inclusive monotonic clock and `mach_timebase_info` as its tick conversion. Apple separately documents an explicit required-reason obligation for `mach_absolute_time` and `ProcessInfo.systemUptime`. The source scan of `lib/` found neither of those two entry points. Archive review must check the compiled Flutter application and embedded frameworks for their own API use before deciding whether a consuming app needs a declaration. [Mach continuous clock](https://developer.apple.com/documentation/kernel/1646199-mach_continuous_time) · [Mach absolute clock](https://developer.apple.com/documentation/driverkit/mach_absolute_time) · [System uptime](https://developer.apple.com/documentation/foundation/processinfo/systemuptime)

Required before release: classify actual API use against the Apple/Xcode 27.2 required-reason list, select only reasons justified by application behavior, verify resource packaging in simulator/unsigned-release/macOS artifacts, and inspect the resulting manifests/archive contents. Do not infer a privacy reason from the package name or reuse a dependency declaration without checking it. No custom privacy manifest has been invented in this implementation.

The Apple privacy/archive gate remains blocked until the Mac inspection and owner review have evidence. [Apple required-reason API documentation](https://developer.apple.com/documentation/bundleresources/describing-use-of-required-reason-api)
