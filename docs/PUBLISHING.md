# Publishing and release verification

## Automated releases

Version bumps prepare source changes; they do not publish. The README's pub.dev badge shows the latest published package, and the GitHub Release badge links to the latest completed GitHub Release.

One-time uploader setup: open [the package Admin tab](https://pub.dev/packages/flutter_true_time/admin), enable publishing from GitHub Actions, set repository `PSCHKLLR/flutter_true_time`, and use tag pattern `v{{version}}`. The workflow uses short-lived OIDC credentials rather than a stored publisher secret. It does not currently require a GitHub deployment environment. See [Dart's automated publishing instructions](https://dart.dev/tools/pub/automated-publishing).

To publish an approved version:

1. Merge its version, changelog entry, and source changes to main.
2. Create and push a tag matching pubspec exactly, for example `git tag -a v2.0.4 -m "Release 2.0.4"` and `git push origin v2.0.4`.
3. Watch [Publish package and GitHub Release](../.github/workflows/publish.yml). It verifies package/tag/changelog identity and main ancestry, runs a Pub dry run, and requires all compatibility jobs (including normally advisory jobs) to succeed.
4. The workflow publishes to pub.dev, waits for registry confirmation, and tests clean consumers on both pinned Flutter SDKs. Only then does it create the matching GitHub Release using changelog notes. Stable releases are marked Latest only when they match the registry's latest version; prereleases never replace Latest.

Manual Run workflow performs validation only, even when a tag ref is selected. Only a pushed release tag can start an upload. There is no automatic upload on every merge or version bump.

If publication succeeds but consumer verification or GitHub Release creation fails, rerun failed jobs after fixing the cause. Do not rerun a successful upload or move an existing release tag. A registry upload is not rolled back by a later failed job.

The workflow verifies builds/tests and publication identity. It does not claim that historical device, provenance, or privacy qualification gaps are resolved. The release checker reads the current pubspec version and still requires current qualification evidence; this workflow does not manufacture passed gate records.

## Historical qualification procedure

The 2.0.0 release renames the public API to `TrueTime`, `TrueTimeEngine`, `TrueTimeConfig`, and `TrueTimeException`. Its release review and remaining qualification limits are recorded in [REVIEW_REPORT.md](REVIEW_REPORT.md). The standalone published-package smoke workflow targets 2.0.0; release runs supply the exact version being published. Historical qualification records do not establish qualification for later versions.

`flutter_true_time 0.1.0-dev.1` was published on 14 November 2026. [Published package](https://pub.dev/packages/flutter_true_time/versions/0.1.0-dev.1) · [Smoke test workflow](../.github/workflows/published-package.yml)

## Canonical inputs and evidence

The owner waived the physical lifecycle gate for `0.1.0-dev.1` only. Simulator, emulator, and VM runs can provide evidence for the behaviors they exercise. Use those environments for outstanding persistence and performance checks. The checker and manifest writer derive the package version from pubspec, accept stable and prerelease versions, and require the manifest and Pub dry-run header to match that version. Regeneration invalidates evidence when the version or inputs change; the original physical lifecycle waiver cannot carry forward to another version. Use `--technical --candidate` to review technical evidence on a checkout with publication enabled. Candidate archive selection still requires the pinned Dart SDK.

1. Finish fixes and stage the intended source changes using normal contributor review. Run dart run tool/update_release_manifest.dart. Before staging, --development can capture new files for implementation checks, but the release checker always rejects development mode. No command stages files automatically.
2. Inputs come from tracked runtime, host, tests, workflow and release-tool sources. UTF-8 text uses LF; binary bytes remain exact. Generated wrappers/registrants are excluded. Every passed gate must reference the same sourceDigest and a hashed file under docs/evidence/. Changing an input requires manifest regeneration and fresh affected qualification evidence. Historical records do not constitute current passes.
3. Run dart run tool/release_check.dart --technical. This checks all prerequisites except archive-consumer and final-owner approval. Pending/partial/blocked results are failures. Complete the exact SDK/platform/device matrix in COMPATIBILITY.md and DEVICE_QUALIFICATION.md; manually review CI artifacts before recording passes.

## Rights, metadata and accounts

4. Review the pinned upstream provenance, preserved LICENSE/NOTICE texts, and DEPENDENCY_LICENSES.json. All resolved Dart/Flutter package licenses are collected; native Maven/CocoaPods/binary obligations and substantial-similarity/redistribution rights still need human review. Automated collection is not legal clearance.
5. Verify repository control, a private security reporting channel, and authorized uploader access before the next upload. Check that the registry is associated with the intended package and that the planned version is available.

## Candidate and approval

6. Once prerequisites pass, prepare a clean isolated Git checkout with the intended version and publication enabled. Run `dart run tool/release_check.dart --technical --candidate` before generating the candidate manifest.
7. With Flutter 3.47.9 / Dart 3.13.7, run `dart run tool/release_check.dart --candidate-manifest` and save its JSON output outside the package root. It uses a successful `dart pub publish --dry-run` and hashes every selected file byte-for-byte. Inspect the file list, top-level notices, platform sources and privacy resources. The package excludes `docs/`, `tool/` and the repository-only release tests. Keep the candidate frozen during selection, testing, and review. A clean Git status and matching runtime digest can still coexist with different line endings in selected files. Use the same frozen checkout to select and stage consumer inputs, and verify the staged bytes against its candidate manifest.
8. Test clean consumers using the selected contents on both SDK lanes and every advertised platform. Record archive-consumer and owner-approval evidence as separate JSON files under `docs/evidence/`, each containing the manifest's `candidateDigest` plus the test results or approval details. Record each evidence file's hash and the runtime `sourceDigest` in its gate. Run `dart run tool/release_check.dart --candidate` using Dart 3.13.7. It reruns the pub dry run and checks the fresh digest against both evidence records. Any change to selected paths or bytes requires fresh validation and approval.
9. Publish with explicit owner authorization and authorized credentials. Update the smoke workflow version after publication and verify installation from pub.dev on both SDK lanes. Close all six-platform gates before promoting to `0.1.0`.

The checker verifies source/evidence integrity and recorded statuses; a human must verify the evidence's meaning. References: [Dart publishing](https://dart.dev/tools/pub/publishing), [pub.dev policy](https://pub.dev/policy).
