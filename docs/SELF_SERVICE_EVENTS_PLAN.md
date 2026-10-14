# Self-service events product and discovery release plan

Goal: earn recurring revenue from a usable self-service events product before December 31, 2026. A bounded external paid pilot by mid-December is a planning target, not a launch guarantee. Organization is the tenant and future billing boundary; a meetup group is a community/calendar; an event is a dated occurrence. Organizer membership, following a group and reserving a place are distinct relationships.

## Current verified baseline

Main `62703646410842531e2a892f8a8ea580bec34004` contains organization owner/admin/editor/viewer roles, verified-email self-service organization creation, private event drafts and publication, event-scoped free inventory, capacity/duplicate locks, account-bound tickets, owner/admin attendee desk/export/check-in, immutable questions and timezone-aware registration windows. These routes have explicit default-off organizer/free-pilot gates. Owned commerce remains free-only and isolated from legacy DQOR checkout, refunds, invoice, scanner and announcement services. No generic cancellation, waitlist, recurring group or scoped delivery ledger is currently present.

PR169 is merged; 177/180 content is already present in current main despite their historical stacked PRs remaining open. PR225 is an open, conflicting website-editor candidate and is not a dependency of discovery. PR17 is a broad historical platform branch, not a safe merge unit. Theme, native, Campfire and commerce branches are not bundled into this work.

## First: an attributed discovery catalog

- External listing records stay separate from locally owned organizations, groups, events and attendee data. Public factual event titles, dates, location/topic metadata and canonical source/registration links only; no copied descriptions, images, videos, logos or attendee lists.
- Reviewed JSON snapshots are parsed as data with a bounded size/schema. Source identity, revision, fetch timestamp, explicit date/time precision and explicit cancellation status are retained. Canonical URL deduplication and stable source record IDs make imports repeatable. Import failures preserve the last good snapshot; missing records do not imply cancellation.
- Search and Ruby/React, India/Pune/global, upcoming/past/date-uncertain filters. Counts are unique event listings, not talks or padded calendar dates. A dated record with unknown timezone is labelled accordingly; uncertain dates are not presented as definite upcoming events.
- Responsive, accessible public directory and listing pages with original graphic motifs, keyboard-visible controls and reduced-motion-safe animation. Registration opens the original external service; no local ownership or local RSVP claim is made.
- `EVENT_DISCOVERY_ENABLED` is a new default-off application product gate. No production import or activation is implicit in merge. Verify exact-head CI, browser journeys, source counts and import recovery before asking for deployment/activation approval.

RubyEvents data is factual discovery input. Official versioned YAML contains series/event metadata and recurring top-level meetup occurrences; child talks are not separate event listings. Pune Ruby currently has a historical February 1, 2025 occurrence, not a complete upcoming calendar. Use canonical source/registration links. Content/media reuse terms remain unresolved. Incoming reviewed RubyEvents and React/India snapshots will be validated before import; no upstream code is executed.

## October: the first owned Pune Ruby community

Reuse the pilot: add tenant-owned recurring groups, a supported organizer dashboard and attractive group/event pages. Create the real Pune Ruby group through supported UI only after the exact account/organization and activation are verified. Do not invent an upcoming occurrence. Add explicit group following/preferences, group-scoped organizer invitations with last-owner protection, event duplication without attendees/delivery history, local-time event entry, stable occurrence calendars and RSVP cancel/rejoin/waitlist under the existing capacity lock. Preserve immutable answer history. Fresh memberships and server-side association scopes are mandatory; global AdminUser is never a group permission.

The user requested attendee invitations. First verify the precise DQOR attendee cohort and consent/suppression, prepare invitation content, and report the eligible count. Existing authenticated Avo currently reports one eligible legacy announcement recipient and delivery paused. That is not proof that every attendee has consented to a new group or permission to enroll them. No copy of private Luma lists, automatic following, opt-out override or invitation send occurs here. Exact organizer accounts and proposed group-only roles need action-time approval before grants.

## November: operational pilot reliability

Add a tenant/event-specific confirmation/reminder ledger, content approval, preference/suppression rechecks and uncertain-outcome reconciliation before real delivery. Legacy DQOR announcement/calendar jobs remain isolated. Cover interrupted sign-in, repeated submissions, Back, cancellation/rejoin/waitlist races, DST/date precision, revoked roles, exports and cross-tenant jobs. Rehearse PostgreSQL backup/restore, production migration locks, recovery and retained-data application rollback. Existing README SQLite/hourly-backup claims are not production recovery evidence.

## December: bounded paid onboarding

Organization subscriptions and explicit server-side feature entitlements can precede third-party paid-ticket commerce. Price, provider, currency, terms, tax handling and account ownership must be settled before billing integration or live charging. Validate sandbox checkout, subscription state changes, idempotent webhooks, entitlement downgrade behavior and cancellation. Do not bypass staged commerce free-only guards or enable marketplace payouts without separately reviewed onboarding/compliance and credentials.

## Release and machines

Main MacBook-Pro-2.local (M5 Max, 128GB) is the sole writer/integrator. The existing approved SSH configuration for Vipuls-MacBook-Pro-2.local returned `Permission denied (publickey,password,keyboard-interactive)` on October 11; no credentials, host checks or remote access were changed. Independent execution there remains blocked. All local tests/build/browser workloads run serially and at reduced priority; paused Miru and unrelated worktrees are preserved.

Five independent expert approvals are required before each code commit. Push only the checked-out feature branch, create draft PRs and record exact-head CI. Ask before every merge and production release. Production flag changes that broaden access, real group provisioning, invitation sends, administrator grants and paid activation are separate actions. The DQOR thank-you email remains separate and unsent while format approval is pending.

## Infrastructure and execution readiness, without activation

The actual runtime uses PostgreSQL and R2; the README's SQLite/hourly-backup language is not restore evidence. Docker serves port 3000 and Render currently references an image tagged `latest`. A future cutover needs immutable image revisions, a restore rehearsal, one controlled migration, an explicit rollback and no competing mail/job consumers. `SOLID_QUEUE_IN_PUMA` currently checks environment-variable presence; values `false` or `0` still start the supervisor. Separate web/worker deployment needs a separately reviewed boolean fix. Entrypoint database preparation and conditional seeds also need a single controlled migration when multiple hosts start. No Hetzner/Kamal, DNS, database access or security setting changes are part of this branch.

Evaluate Cloudflare Email Sending Beta HTTPS REST through existing approved capability before choosing delivery infrastructure; its Workers Paid/verified-domain requirements are not yet established here. Evaluate marclou/mailcheap only: its Next.js/MongoDB/SES architecture is not a Rails transactional drop-in. No installation, imported mailing list, provider account, purchase or live delivery is authorized by this readiness note. Existing VAPID push belongs to the gated legacy web flow and is not native APNs/FCM.

This executor supports foreground work and resumable local command sessions while connected. No durable runner through disconnect, overnight supervisor, new launch agent, scheduled automation or unattended restart has been established. Checkpoint files and draft branches are the recovery mechanism. Local Ollama is usable. Configured Kimi is blocked for private source export by automatic approval review until the exact payload/destination approval arrives. Claude is logged out, Muse reports missing credentials, Exa is unavailable, and second-Mac SSH is denied. Do not repair or bypass those gates.
