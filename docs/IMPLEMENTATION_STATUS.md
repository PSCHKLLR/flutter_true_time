# First-release implementation status

The five first-release review findings are fixed. Public APIs, persistence v2, and freshness/quorum/drift defaults are unchanged.

| Area | Status |
| --- | --- |
| Runtime correctness | Delayed restoration, deadline quorum, NTP error ownership, and provider normalization implemented and regression tested |
| Release reproducibility | Schema-2 canonical tracked-source digest, separate manifest generator, digest-bound evidence and read-only gate checker; fresh LF/autocrlf clones agree |
| SDK and example checks | 106 tests per pinned SDK, clean analysis, and example test on Windows |
| Android | All three exact JDK 17 build lanes passed APK/AAB |
| Browser | Both SDKs built and rendered JS/WASM; real endpoint/CORS gate remains open |
| Native/device coverage | Apple/Linux/Windows release, physical lifecycle, native restart/storage and privacy archive qualification blocked here |
| Rights and publication | Resolved license texts collected; human/native audit, private security reporting, uploader access and exact-candidate review remain open |

See REVIEW_REPORT.md, VALIDATION.md, DEVICE_QUALIFICATION.md, APPLE_PRIVACY_AUDIT.md and PUBLISHING.md. Publish_to remains none. No release candidate, upload, tag, or push was performed.
