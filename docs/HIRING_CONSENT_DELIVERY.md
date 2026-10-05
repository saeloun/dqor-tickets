# Gated resume delivery and recruiting consent

This slice is stacked on PR 162; its green commit df58c95106b73bb11920ea1e8e42aa9ad7cb411f is unchanged. Migration 20261003010000 follows PR 163's verified 20261003000000 announcement ledger reservation.

## Resume delivery

`clamscan` and `clamdscan` were not found on the execution host's checked PATH, and no existing repository antivirus adapter was found. Nothing was installed. No real malware scans ran, and no real resumes or external document services were used.

The default `Hiring::ResumeScanner` returns `unavailable`. `Hiring::ScanResumeJob` runs on the dedicated `hiring_scans` queue and preserves quarantine unless a supported future adapter returns `clean` plus the SHA-256 digest of the exact bytes supplied. It checks the current bytes again under row lock before recording the verdict. Changed uploads reset digest/verdict metadata; exceptions quarantine and re-raise. No scanner or heavyweight AV runs inside the HTTP upload action.

`HIRING_RESUME_DOWNLOADS_ENABLED` defaults off, independently of the existing hiring/foundation gates. Even if enabled, the default adapter cannot produce clean files. Tests explicitly inject scanner doubles; their clean results are synthetic authorization tests, not evidence of antivirus operation.

`GET /hiring/applications/:id/resume` requires the attendee account session and rechecks applicant ownership or the current named recruiter with approved company claim. Active consent and a nonwithdrawn application are required, including QR expiry/revocation when applicable. Stored digest, verdict digest, and freshly computed byte digest must agree, with a clean verdict and scan timestamp. Files remain private database bytes with no Active Storage/public/bearer route. Responses are attachments with fixed filename, no-store, nosniff and restrictive CSP; successful access is audited without document content. Applicant withdrawal deletes the bytes and invalidates verdict metadata. The authorization check occurs before any bytes are sent; bytes already downloaded cannot be recalled.

Before operational enablement: select a supported local scanner and engine/version policy, deploy it in an isolated worker environment with resource/time limits, add integration tests with standard benign test fixtures, define stale-verdict rescanning and retention/deletion policies, and review operational access to database backups. Do not replace the unavailable adapter with an always-clean stub outside tests. No production settings were changed.

## Recruiting QR

An authorized recruiter creates a request from their job's applicant page. The generated QR encodes only an opaque recruiting URL. The database stores its token digest; it carries no entry-ticket secret, profile data, or file access capability. It is bound to the issuing recruiter and job, with a 24-hour deadline for both acceptance and subsequent recipient access. No job/recruiter identity is accepted from consent form parameters.

Opening the request requires attendee sign-in and shows the recipient's name/email, company, job/event, shared fields, deadline and revocation terms. GET shares no profile. Explicit checked consent plus manual profile entry creates the application and consumes the request atomically under a row lock. QR submissions contain name, summary, optional manual LinkedIn URL and server-owned account email; **no PDF is shared via QR**. A duplicate application is rejected rather than replaced. Replays and expired requests fail; consumed links do not reveal applicant data to other users. All hiring responses suppress referrers and caching.

The applicant can revoke from their applications list; revocation erases the snapshot through withdrawal, records an audit event and removes recruiter access. Ordinary withdrawal also removes access and cannot make the token reusable. Expiry removes recruiter review/download access but does not itself erase the stored snapshot: automated retention deletion remains pending. The QR is separate from entry admission and grants no staff, organization or company administration permission. Recruiter changes or claim revocation invalidate access.

## Verification

Focused request/foundation/mobile suite: 30 examples, zero failures. Includes unavailable/error/mismatched/stale scanner results; exact-byte gated downloads; anonymous, other-org and sibling-event recruiter denial; withdrawal; named recipient binding; no-consent denial; expiry; replay; wrong-user revocation denial; entry-token rejection; and browser consent/revocation at 390×844 without horizontal overflow. Brakeman: zero warnings. Scanner success is simulated only in tests.

Remaining scope: actual antivirus integration and operations, resume upload through QR (deliberately excluded), automated retention, broader company identity lifecycle, additional recruiter grants and partner-only LinkedIn import. No hiring decisions, live invitations, real users, provider imports or production activation occurred. The broader hiring request is not complete.

## Follow-up: optional local scanner adapter

The subsequent local-scanner slice adds a bounded, opt-in `Hiring::ClamavScanner`; see `HIRING_CLAMAV.md`. The unavailable adapter remains the default. Homebrew installation failed on this host's unsupported macOS version, so real-engine/signature validation is still blocked and no actual scan success is claimed. Process-protocol tests and opt-in real-engine tests are kept distinct.
