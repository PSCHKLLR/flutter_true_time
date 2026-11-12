# First publication procedure

Target flutter_true_time 0.1.0-dev.1; new contributions PSCHKLLR. Development remains publish_to: none. This procedure does not authorize uploading, tagging, or pushing.

## Canonical inputs and evidence

1. Finish fixes and stage the intended source changes using normal contributor review. Run dart run tool/update_release_manifest.dart. Before staging, --development can capture new files for implementation checks, but the release checker always rejects development mode. No command stages files automatically.
2. Inputs come from tracked runtime, host, tests, workflow and release-tool sources. UTF-8 text uses LF; binary bytes remain exact. Generated wrappers/registrants are excluded. Every passed gate must reference the same sourceDigest and a hashed file under docs/evidence/. Changing an input requires manifest regeneration and fresh affected qualification evidence. Historical records do not constitute current passes.
3. Run dart run tool/release_check.dart --technical. This checks all prerequisites except archive-consumer and final-owner approval. Pending/partial/blocked results are failures. Complete the exact SDK/platform/device matrix in COMPATIBILITY.md and DEVICE_QUALIFICATION.md; manually review CI artifacts before recording passes.

## Rights, metadata and accounts

4. Review the pinned upstream provenance, preserved LICENSE/NOTICE texts, and DEPENDENCY_LICENSES.json. All resolved Dart/Flutter package licenses are collected; native Maven/CocoaPods/binary obligations and substantial-similarity/redistribution rights still need human review. Automated collection is not legal clearance.
5. The public repository PSCHKLLR/flutter_true_time now exists. Confirm maintainer/admin control, issue/security reporting, and authorized pub.dev uploader access. Private vulnerability reporting returned disabled on 12 November 2026. Public existence alone does not establish maintainer or uploader permissions. Recheck name availability immediately before publishing; a current 404 is not a reservation.

## Candidate and approval

6. Only after prerequisites pass, prepare a clean isolated Git candidate from the reviewed source and remove the exact `publish_to: none` line there. The runtime fingerprint excludes that line. Run `dart run tool/release_check.dart --technical --candidate` before generating the candidate manifest.
7. With Flutter 3.47.9 / Dart 3.13.7, run `dart run tool/release_check.dart --candidate-manifest` and save its JSON output outside the package root. It uses a successful `dart pub publish --dry-run` and hashes every selected file byte-for-byte. Inspect the file list, top-level notices, platform sources and privacy resources. The package excludes `docs/`, `tool/` and the repository-only release tests. Keep the candidate frozen during selection, testing, and review.
8. Test clean consumers using the selected contents on both SDK lanes and every advertised platform. Record archive-consumer and owner-approval evidence as separate JSON files under `docs/evidence/`, each containing the manifest's `candidateDigest` plus the test results or approval details. Record each evidence file's hash and the runtime `sourceDigest` in its gate. Run `dart run tool/release_check.dart --candidate` using Dart 3.13.7. It reruns the pub dry run and checks the fresh digest against both evidence records. Any change to selected paths or bytes requires fresh validation and approval.
9. Actual publication requires a separate explicit owner instruction and credentials. After publication, verify installation from pub.dev on both SDK lanes. Promote to 0.1.0 only after all six-platform gates pass; do not automate the first upload.

The checker verifies source/evidence integrity and recorded statuses; a human must verify the evidence's meaning. References: [Dart publishing](https://dart.dev/tools/pub/publishing), [pub.dev policy](https://pub.dev/policy).
