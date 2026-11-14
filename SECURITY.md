# Security

The package estimates UTC from network sources. NTP is unauthenticated. HTTPS authenticates the transport peer. The peer supplies the Date header. Version 0.1.0-dev.1 provides no authenticated time protocol.

Never disable certificate verification, substitute wall-clock time, or use private boot APIs. Provider diversity and uncertainty do not establish cryptographic authenticity. Use server-authoritative decisions for transactions or licensing.

Persistence is opt-in. Restore only with matching proven boot epoch, installation scope, clock domain, trust policy, evidence, and freshness. Android's installation marker must remain excluded from backup. Apple/Windows default to no cross-process restoration; web requires fresh synchronization after restart. Secure storage alone does not prove continuity. Separate processes must not share a writable anchor namespace; serialization is in-process.

Keep credentials, key material, and logs containing installation or boot identifiers private. To report a security issue, ask the maintainer for a private contact before sharing details. Verification of a private reporting channel remains an open qualification item.
