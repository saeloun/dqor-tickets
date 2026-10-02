# Staged hiring slice

Stacked on foundation PR 151. Both ORGANIZER_PLATFORM_ENABLED=true and HIRING_ENABLED=true are required; defaults remain off. No production settings, invitations, staff grants, providers, sponsorship records, AI ranking or automatic rejection are involved.

Migration reservation: 20261002230000. Adjacent open PR migrations checked: commerce 20261002200000 and operations 20261002210000; programme 20261002220000 remains reserved by the coordinating task.

## Implemented

Authenticated all-events/global and event-filtered job boards. Event jobs only appear while their event is published. Any company can request approval in a host organization, independent of sponsorship. Owner/admin memberships permit claim review only; editors/viewers cannot approve, and self-approval is forbidden. Company evidence must be independently checked by the reviewing human. Approval permits the claimant to create roles; each job explicitly names its creator as recruiter. No foundation membership is created or modified.

Applicant snapshots include manually entered name, summary, optional LinkedIn URL and server-owned account email. Explicit consent is required. Applicants can withdraw their own application, erasing its snapshot and PDF; recruiters cannot withdraw candidates. Only the explicitly named job recruiter with a currently approved company claim can review active applications. Organization membership alone grants no candidate access, including other events in the same organization. Self-reported affiliation is stored separately and is never read by any policy.

Optional PDFs are stored in a private database bytea column on the applicant's application, not Active Storage. Uploads require authentication, application consent, declared PDF type, a PDF header and a bounded read of 5 MB plus one byte. This is preliminary type validation, not malware scanning. Every upload is quarantined; there are no download, preview, bearer or release routes, including for the uploader. Withdrawal deletes bytes. No file is described as scanned. Do not enable file review until a fail-closed scanner, authenticated per-request scoped download, audit trail and retention policy are implemented. Database operators/backups remain infrastructure-level access.

## Pending

Recruiting QR sharing is absent: recipient-bound, separate-purpose, revocable consent-confirmed sharing must be implemented before offering it. Entry-ticket QR codes are not reused. LinkedIn import is absent; partner access is unavailable and no scraping occurs. Resume release/scanning, claim revocation UI, job editing/closing UI, public affiliation display, multiple recruiters, identity deduplication, retention automation and moderation audit UI are follow-up work. This draft is a staged first slice, not deployment authorization.

## Verification

Focused run: `bundle exec rspec spec/requests/hiring/board_spec.rb spec/requests/organizer_events_spec.rb spec/system/hiring_spec.rb` — 20 examples, zero failures. Includes two organizations, sibling events in one organization, owner membership without recruiter access, revocation, self-approval denial, applicant-only withdrawal/affiliation removal, PDF spoof/oversize/quarantine, disabled feature gates, and a real browser application/withdrawal flow at 390×844 with no horizontal overflow. Scoped RuboCop: 11 files, no offenses. Zeitwerk eager-load check passed. Brakeman 8.1.0: zero warnings. Tests used a temporary synthetic PostgreSQL database on port 55439; no production data or credentials.
