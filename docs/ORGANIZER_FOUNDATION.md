# Organization and event foundation

This opt-in slice supports explicitly provisioned organizations and memberships, organizer event drafts, and publication of a title/date information page. It is not a complete multitenant ticketing product. Existing DQOR checkout, admin permissions, payment credentials, and URLs are unchanged. No paid services are activated.

## Enable and use

Apply the additive schema migration, review the exact identity and roster, then provision organizations/memberships separately under an approved operational plan. No provisioning writes are included here. Set `ORGANIZER_PLATFORM_ENABLED=true` to enable the new routes (default disabled). Sign in using the existing attendee account and visit `/organizer/organizations/:organization_id/events`. A global AdminUser login does not grant organization access.

Owners, admins, and editors may create/edit/publish events. Viewers may read their organization's drafts. Every event lookup is scoped through the requested organization and a fresh membership lookup. No membership management endpoint or implicit email-domain grant exists. Drafts require title, slug, and a real IANA timezone; publication also requires start/end, with end strictly after start. The initial form explicitly accepts UTC dates and displays them in the event timezone.

Published pages live at `/events/:organization_slug/:event_slug`; drafts return 404, including to organizers through that public endpoint. Existing published events may be edited by event managers; validated edits take effect immediately. This slice has no unpublish/archive/delete workflow, ticket sales, checkout routing, or guest registration for new events.

## Saeloun / Vipul dry run

`PLATFORM_OWNER_EMAIL=<reviewed-exact-account-email> bin/rails platform:seed_dry_run`

This prints a proposal for Saeloun and the supplied existing account, requested owner name Vipul, and blockers. It performs **zero writes**. A matching email is evidence of an existing account, not proof it is Vipul. Confirm identity, intended role, roster, recovery/last-owner plan, and event mapping before separately approving provisioning. Do not derive employee membership from Slack or email domain. No production migration/backfill or grants have been executed as part of this work.

## Staged DQOR adapter

`ExistingDqorEvent.resolve` returns a published Event only when the platform is enabled and `DQOR_PLATFORM_EVENT_ID` is explicitly set. It returns nil for missing, malformed, stale, or draft IDs. Nothing in the legacy application calls it. It does not scope commerce records or provide authorization. Future integration must review org/event mapping, ownership of every commerce/content record, cross-resource constraints, staged nullable references, dry-run counts, rollback, and cross-tenant tests before backfill. Never infer a default tenant from the first Event.

Branding remains the separately owned singleton draft/publish implementation. Billing/invoices, check-in, native APIs, Campfire, and ticket slots are separate work; this change supplies no claim of tenant readiness for those resources.

## PR 17 salvage assessment

Inspected unmerged `platform-foundation` before implementation. Retained concepts of normalized per-tenant slugs, explicit roles and ordered dates. Copied no code wholesale. Its replacement sessions/auth, broad commerce associations, and DQOR backfill are incompatible with the current attendee/admin boundaries and deliberately excluded. In particular, organization authorization must never accept an arbitrary resumed admin session as attendee identity.
