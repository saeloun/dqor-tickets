# Complete free-event pilot candidate

This isolated candidate combines current main `5028de5` (including Campfire handoff PR164) with reviewed foundation PR151 and ownership PR153. It adds a bounded usable free-event flow, not paid multimerchant ticketing. No production migration, flag activation, roster grant, real-user provisioning, provider call, or live email was performed. Current live DQOR remains unchanged until an independently approved deployment.

## Try the synthetic journey

Use a separate PostgreSQL test database and Rails test mail adapter. Run `bundle exec rspec spec/system/free_event_pilot_spec.rb` with `RAILS_ENV=test` and a dedicated `DATABASE_URL`. The test supplies synthetic users and signed test-only email-verification links, stubs flags in-process, and drives actual browser forms through organization creation → event draft → publication → free ticket publication → attendee registration → account-bound retrieval → organizer check-in. The responsive screens use the design owner’s shared warm canvas, forest green, serif headings, and 48px controls. Invalid inventory submissions preserve entered values; email verification returns attendees to the event for explicit registration. Screenshots land in `tmp/free-pilot-ticket.png`, `tmp/free-pilot-ticket-mobile.png`, and `tmp/free-pilot-organizer.png`, plus mobile creation and check-in captures. Nothing emails real users or changes environment flags.

For an independently reviewed local demo, the gates are `ORGANIZER_PLATFORM_ENABLED=true` and `FREE_EVENT_PILOT_ENABLED=true`; both default off. `STAGED_COMMERCE_ENABLED` is not needed. Start at `/free` after signing in with a verified email link. Google-only and global AdminUser sessions are insufficient for pilot mutations. Pilot-origin Google callbacks are rejected server-side before account creation; failed/retried sign-in retains the email-link context. Pilot-origin email signup makes newly created accounts private before first persistence; test delivery only has been exercised. Production auth/email operations need explicit release review.

## Delivered behavior

- Verified users explicitly create a new organization and become its owner. No existing organization, employee roster, or role is inferred or granted. Existing event draft form handles title, UTC start/end and IANA display timezone, with required dates at publication.
- Organization owners/admins publish one named, capacity-limited free ticket type per event. All owned inventory stays hidden/inactive to legacy checkout; a separate free publication timestamp controls the free page. Price is zero, one ticket per user per event, and capacity is serialized under an event lock. Retries return the existing registration; independent-connection tests cover capacity races and duplicates.
- Attendees register using their verified session identity. Forged email/user/price parameters are ignored. Confirmation and ticket retrieval are in-app and account-bound; no provider, legacy comp, invoice, PDF, wallet, email, or background delivery method runs. No bearer order/claim/ticket secret is displayed.
- Owners/admins see only that event’s attendees, export a minimal formula-safe CSV, and check attendees in during the event window. Check-in is idempotent and records event, ticket, operator and time. Editors/viewers cannot access attendee PII or perform this workflow. Revoked memberships stop working on the next request.

## Legacy isolation audit

Explicit `legacy` scopes (not default scopes) are applied to live DQOR store/home/SEO/preview/checkout, order/claim/assignment, account ticket recovery/dashboard/referrals, Apple/Google wallet, admin list/search/detail/edit/actions/export/dashboard, check-in search/resolve/batch/counts, native staff APIs, and slot lookup/eligibility. Ticket broadcast and reminder queries exclude owned records.

`LegacyCommerce.assert!` fails closed before legacy Order payment/comp/reconcile/refund/document/delivery methods; Ticket assignment/PDF/check-in/reminder methods; Invoice issue/snapshot/PDF; provider event recording; refund initiation/processing; direct mail, PDF and wallet services. These guards preserve original null-owned behavior and order → refund → ticket lock ordering. No finance152, hiring162, email163, scanner159 or programme160 branch is rewritten or folded into this candidate. Future integration must carry these guards forward to any newly added legacy endpoint.

Avo has explicit index/detail/bulk query scopes and legacy-only association picker scopes; direct attachment/detachment and autocomplete regressions cover the separate Avo association controller. Invoice/refund/payment/coupon and slot-redemption model validation rejects owned commerce. Tests attempt forged IDs, secrets, order codes, admin direct URLs, exports, native resolve/batch and direct service calls even with the pilot disabled. Database ownership keys prevent cross-event and legacy-null/owned ticket relationships.

## Social privacy

`users.free_pilot_identity` is a persistent privacy marker, not an access role. New pilot-origin signups are private before verification. An existing non-DQOR user entering the pilot is enrolled privately per-user; no bulk backfill occurs. Existing DQOR attendees keep their explicit visibility settings. A pilot identity that later attends DQOR remains private until the user explicitly changes visibility settings.

Pilot-only identities cannot be listed/read by legacy community search or guessed profile IDs, connect, access chats/history, send/receive DMs or push subscriptions, or appear through referral lookups. Queued message and push delivery rechecks eligibility, and direct model calls are guarded. Campfire handoff issuance and redemption both recheck the freshly verified email’s eligibility, including grants issued before pilot enrollment and when flags are off. These protections remain active when the pilot flag is off. Hidden profiles now reject guessed-ID access rather than exposing profile details. Public legacy users retain existing connection semantics; a full mutual-consent redesign for legacy messaging is outside this pilot. No cross-event networking feature is enabled for free events.

Shared users’ DQOR participation remains usable, but free-event orders, attendees and organization memberships never surface as DQOR participation. Tests cover two free events, pilot-only identities, shared DQOR users, forced visibility flags, private profiles, existing one-way chats, direct model calls and stale queued push jobs.

## Browser cache privacy

The service worker no longer caches navigation HTML. It caches only static assets under `/assets` or `/dqor` plus explicit shell assets, rejects private/no-store/no-cache responses and redirects, and excludes private Active Storage images. Its next activation invalidates prior DQOR cache versions while preserving unrelated caches. Browser-executed worker-handler regression covers private navigation/image exclusion, header handling, stale-entry removal, offline fallback and version invalidation. This candidate has not been deployed: already installed production workers need the release/update lifecycle before this protection takes effect.

## Schema and release gates

Reserved migration `20261003020000` adds a free publication timestamp, account ownership and a unique event/user registration key, free-only monetary/provider constraints, an event-scoped check-in audit, and the privacy marker. No ownership backfill or production grants occur. Migration rollback/reapply and schema loading are tested only on disposable local data. Rolling down destroys pilot ownership/audit/privacy metadata; do not do that after real enrollment without an approved preservation plan.

Review migration locks/row counts, integrated head, all legacy/social denial tests, current scanner/refund behavior, email test configuration, deployment target and rollback before activation. Paid payments, generic merchant onboarding, taxes/invoices, free ticket transfers/cancellation/waitlists, external delivery, tenant-specific QR scanner/mobile apps, public attendee directories and organization invitations remain unsupported. There is no bypass into global Razorpay or global invoice behavior. Complete means this documented free demo workflow and its tested boundaries, not every feature of a commercial event platform.

## Extension contracts for separate increments

- `FreeEvents::Access.with_manager` rechecks and locks owner/admin membership plus the organization-owned event. Keep all attendee/operations reads and mutations behind it; never grant global AdminUser or finance access from membership.
- `FreeEvents::Register.call` serializes inventory using the event lock and the database unique `(event_id, user_id)` key. Multiple ticket categories/windows require a deliberate new registration contract and compatible unique-key migration, not bypassing the current one-ticket rule.
- Owned `TicketType` stays hidden/inactive to legacy commerce; `free_published_at` is independent of legacy availability. Any future price or provider integration must replace the explicit free-only database constraints through a separately reviewed design.
- Custom fields should belong to event/category, with immutable registration answer snapshots; never store them on shared User or expose them in the allowlisted attendee CSV by default.
- Check-in uses `FreeCheckin` with operator/time and an event-ticket composite FK. Future QR credentials must be separate from legacy ticket secrets and resolved within the authorized event.
- Cancellation needs an audited state transition and concurrency tests under the same capacity lock; there is no supported cancellation endpoint here. Do not call legacy refund or comp methods.
- Social privacy is independent of feature flags. Future networking must explicitly scope event participation and consent; do not reuse global connection/chat relations for free events.
