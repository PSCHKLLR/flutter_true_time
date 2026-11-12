# Repository Guidelines

## Project Structure & Module Organization

flutter_true_time exposes its Flutter facade from lib/flutter_true_time.dart and its injectable engine from lib/core.dart. Clock, source, cancellation, persistence, and diagnostic implementations live in lib/src/. Android's Java bootstrap bridge lives in android/; other platforms use conditional Dart/FFI implementations and Dart-only registrations.

Core tests are in test/, Flutter-specific tests in test_flutter/, device checks in example/integration_test/, and runnable host projects in example/. Specifications, review results, notices, and compatibility evidence live in docs/. Read ARCHITECTURE.md and SECURITY.md before changing time or trust behavior.

## Build, Test, and Development Commands

- flutter pub get: resolve package and example dependencies.
- dart format lib test test_flutter example/integration_test tool example/lib example/test: format maintained Dart code.
- flutter analyze: enforce flutter_lints checks.
- flutter test test test_flutter --coverage: run core and facade regressions.
- dart test test: run only Flutter-independent core tests.
- flutter run -d windows inside example/: run the demo.
- dart run tool/configure_android.dart baseline: select the approved Android host lane.
- dart run tool/update_release_manifest.dart: regenerate canonical tracked inputs and invalidate stale evidence. Use --development for an untracked implementation snapshot.
- dart run tool/release_check.dart: verify publication gates; pending gates intentionally fail.

## Coding Style & Naming Conventions

Use standard Dart formatting, snake_case.dart filenames, UpperCamelCase types, and lowerCamelCase members. Keep socket/FFI dependencies behind conditional imports. Android bootstrap code uses Java 17, not a package-owned Kotlin plugin. Document units, UTC semantics, uncertainty assumptions, resource ownership, and failure behavior.

## Testing Guidelines

Keep unit tests offline and deterministic through injected clocks, sources, epochs, storage, and schedulers. Test cancellation cleanup, concurrency across deadlines, restore validation, write ordering, and lifecycle transitions. Maintain separate Flutter tests so the VM suite does not import dart:ui. No numeric coverage threshold is imposed. Physical device qualification requires recorded evidence.

## Commit & Pull Request Guidelines

Use concise imperative subjects; fix:, feat:, and docs: prefixes are recommended. Explain resulting behavior, linked issues, affected platforms, and validation. Update the specification, compatibility matrix, and changelog for public contract changes. Never mark an unexecuted CI lane passed.

## Security & Publication

Never substitute system time, weaken TLS validation, use private boot APIs, or claim NTS authentication. Preserve upstream notices. Keep publish_to: none until qualification and owner approval; publication requires an explicit instruction.
