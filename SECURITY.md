# Security

This development package estimates UTC; it is not a tamper-proof authority. NTP is unauthenticated. HTTPS authenticates a transport peer, not the accuracy of its Date header. Authenticated time is not implemented in 0.1.0-dev.1.

Never disable certificate verification, substitute wall-clock time, or use private boot APIs. Provider diversity and uncertainty do not establish cryptographic authenticity. Use server-authoritative decisions for transactions or licensing.

Persistence is opt-in. Restore only with matching proven boot epoch, installation scope, clock domain, trust policy, evidence, and freshness. Android's installation marker must remain excluded from backup. Apple/Windows default to no cross-process restoration; web requires fresh synchronization after restart. Secure storage alone does not prove continuity. Separate processes must not share a writable anchor namespace; serialization is in-process.

Do not commit credentials, key material, or logs containing installation/boot identifiers. Before publication, configure and verify a private security reporting channel on the owned repository. Until then, request a private contact from the maintainer without posting exploit details publicly. The public repository exists; private vulnerability reporting was disabled when checked on 12 November 2026. Keep the security gate blocked until a private reporting channel is verified.
