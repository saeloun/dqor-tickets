# Disconnected public programme client

Implements the read-only DTO and snapshot semantics proposed by backend PR #171, contract commit 675f4f1. `PublicProgrammeClient` requires an injected `ProgrammeTransport`; there is no production transport, origin, app wiring or network call. The existing app continues to show explicitly synthetic fixtures. A verified merged contract and approved deployment are required before connecting it.

A successful v1 response replaces the entire in-memory snapshot, including authoritative empty session/speaker arrays. Nullable times and speaker fields remain nullable, without invented scheduling or private identity. Exact ETags, including weak markers and quotes, are retained for conditional requests. A 304 requires a prior snapshot and validator; otherwise the client retries once unconditionally. Unsupported versions, malformed data, repeated cacheless 304, connectivity failures and server failures do not replace valid content and mark it stale. Consumers must expose that stale state when UI integration is approved. Cancellation is checked before publishing responses; overlapping refresh requests are rejected.

The client has no credentials, cookies, persistence, logs, attendee fields, ticket secrets or mutation API. A future HTTP adapter must omit authorization/cookies, enforce the approved HTTPS origin and redirect policy, and preserve response ETags.

Validation: Xcode 27, iPhone 17 Pro simulator / iOS 26.2, signing disabled. All 53 unit tests passed, including six synthetic public-feed transport tests. Evidence: /tmp/dqor-programme-client.xcresult and /tmp/dqor-programme-client.log. No UI behavior changed; UI tests were not repeated for this isolated client addition.
