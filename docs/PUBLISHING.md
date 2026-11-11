# Publication procedure

Package: flutter_true_time. Proposed first public prerelease: 0.1.0-dev.1. New contributions: PSCHKLLR. Publishing is disabled; this delivery does not authorize an upload.

1. Complete docs/release_gates.json with evidence for every platform and native persistence scenario. Run dart run tool/release_check.dart. A pending gate must fail; do not edit status solely to make the checker green. Runtime/host changes invalidate source fingerprints and their qualification evidence.
2. Audit the pinned upstream commit and retained notices in PROVENANCE.json, licenses/, and THIRD_PARTY_NOTICES.md. No identical complete Dart files were found; this does not prove absence of substantial similarity or settle legal ownership. Review all resolved dependency licenses and binary/native notices for the actual release graph.
3. Establish an owned repository at the declared metadata URLs, enable/verify private security reporting, and configure uploader credentials. A public API lookup returned 404 for the proposed repository on 12 November 2026; ownership is unverified. Do not publish inaccurate metadata.
4. Recheck pub.dev name availability immediately before release. The API returned 404 on 12 November 2026; this is a point-in-time observation, not a reservation or guarantee.
5. In an isolated reviewed release candidate, remove publish_to: none, run dart pub publish --dry-run, inspect the complete manifest, licenses, notices, privacy resources, platform sources and generated files. Restore the development guard if the candidate is rejected. Exclude local paths, caches, build outputs, credentials and diagnostic identifiers. Save the exact archive hash and manifest.
6. Install a clean consumer from the candidate archive contents and test both SDK lanes and supported hosts. Present exact version, archive hash/manifest, all evidence, and limitations for owner approval. Any subsequent archive change requires fresh review.
7. Actual publication requires an explicit publishing instruction and credentials. Do not automate a first upload. Publication is generally permanent; promote to 0.1.0 only after all six-platform qualification gates pass. Verify installation from pub.dev on both SDK lanes after publication.

The source ZIP supplied with this project is a review artifact, not a pub-generated upload archive and not release qualification. The release checker verifies recorded hashes/statuses, not the truth of manually supplied evidence; a human must review it.

Publishing references: [Dart publishing](https://dart.dev/tools/pub/publishing), [pub.dev policy](https://pub.dev/policy). Redistribution rights, required notices, a license, a unique name and authorized credentials are prerequisites. Resolve provenance uncertainty before uploading.
