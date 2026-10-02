# DQOR announcement email ledger

This feature is for the existing DQOR administrator role. It is not a generic multi-tenant campaign product. It does not change ticket receipts, password resets, invoice/refund jobs, provider accounts, or commercial plan limits.

## Organizer flow

From Avo announcements choose **Preview and approve email** for one announcement. Review the audience count and escaped body; download the branded `.eml` test draft, addressed only to the current administrator, without sending it. Approval requires the reviewed content and audience digest to still match, then atomically snapshots title/body, approving administrator, approval time and normalized recipient rows. Editing the source announcement later does not modify the approved version. Each announcement has at most one approved campaign. Legacy `emailed_at` records cannot be approved again, and old broadcast jobs carrying an announcement cannot authorize delivery.

The review page lists state counts and the first 100 recipient states. Empty audiences cannot be approved. Larger audiences are bounded to 5,000 per campaign and 10,000 outstanding recipient rows globally. These limits apply only to announcements. Approval never queues an individual email per recipient. Public announcement publishing and push jobs remain separate from email approval.

## Consent and suppression

There is no automatic enrollment or live audience backfill. Attendees opt in explicitly from their authenticated account settings. Preferences record consent time/source; suppression overrides consent. Recipient addresses are lowercased and trimmed even for legacy ticket rows, deduplicated across paid, non-canceled tickets, and intersected with opted-in preferences. Both consent and active-ticket eligibility are checked again before submission. An unsubscribe link carries a signed purpose-bound token; GET displays a confirmation and POST suppresses. Settings updates always use the authenticated user's email, never a submitted email address. Ticket and account emails are unaffected.

## Worker, rate cap, and retries

Production delivery is **paused by default**. `ANNOUNCEMENT_DELIVERY_ENABLED=true` is an explicit operational switch; do not enable it until the account/provider setup and audience are approved. In tests dispatch only runs when Action Mailer uses `:test`. No provider credentials are added by this feature.

The production recurring dispatcher runs every minute on `announcements`. Queue ordering checks `default` first and retains the wildcard for existing queues. Existing transactional jobs and retries are unchanged. A PostgreSQL row lock serializes claims and a persisted window caps dispatch attempts to 25 per minute across concurrent jobs/processes. Solid Queue additionally limits dispatcher concurrency to one. This is a bounded burst, not a claim of provider-specific throughput guarantees.

States: `pending` → `preparing` → `submitting` → `submitted`; ineligible recipients become `suppressed`. Preparation failures become `failed`. Administrators can retry these only, up to three attempts. No automatic network/provider retry is inherited. After 15 minutes an abandoned preparation is failed and an abandoned submission becomes `unknown`. Attempt fencing prevents an old renderer from submitting after recovery. The next recurring tick recovers/continues persisted pending rows if enqueueing or a worker fails. This relies on the recurring scheduler being enabled.

The `submitting` marker commits before calling the mail transport. A timeout or crash from that point may mean the provider accepted the email. Such outcomes become `unknown` and are never resent automatically or via the retry button. `submitted` means the transport call succeeded, not confirmed inbox delivery. There is deliberately no claim of exactly-once SMTP delivery or provider idempotency. Reconcile unknowns against provider records before any separate operational remedy. Error classes, not provider exception payloads or credentials, are stored.

## Provider integration remains disabled

No Miru credentials, live audiences, provider setup, email/SMS submission, Postmark server/stream creation or MSG91 configuration is part of this change. Future approved Postmark setup should isolate broadcast and transactional traffic in separate servers/streams and ingest verified bounce/complaint suppressions before enabling campaigns. Existing SMTP is not assumed to provide idempotency. MSG91 DLT templates, consent and provider integration remain disabled until separately approved account setup. Preserve the transactional queue and receipt guarantees when that integration is designed.

## Validation

Focused specs cover overlapping approvals and claims using independent PostgreSQL connections, stale-renderer fencing, unknown outcomes, suppression, address deduplication, immutable versions, stale previews, bounded attempts/rate/backlog, role authorization, signed unsubscribe and escaped previews. The browser spec exercises review/approval at 390×844 and checks horizontal overflow. All delivery specs use local Action Mailer test transport. Run with an isolated test database; never copy production credentials or audiences.
