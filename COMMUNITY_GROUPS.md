# Tenant-owned community foundation

This default-off foundation gives an existing organization a private community draft and an explicitly published public home. It is independent of the external discovery catalog. No external listing becomes an owned event, organization or community.

Enablement requires all three flags: `ORGANIZER_PLATFORM_ENABLED=true`, `FREE_EVENT_PILOT_ENABLED=true` and `MEETUP_GROUPS_ENABLED=true`. Missing flags return 404 for public HTML, API and organizer group routes. No production enablement is part of this branch.

Verified existing organization owners and admins can create, edit, publish, make private and attach an existing event from their organization. Editors and viewers can read their private workspace but cannot manage communities. Every request reads current membership; every mutation locks and rechecks a current owner/admin membership inside its transaction. Group and event IDs always resolve within that organization. A composite foreign key enforces the same organization even outside model validation. No deletion or implicit reassignment is exposed.

A publication needs a name, slug, description, city, two-letter country code and valid IANA timezone. Description and titles render as escaped plain text. Bounded unbroken names, introductions and descriptions wrap on mobile. A failed publication retains the private draft and validation errors. Publishing a community does not publish its events. Making a community private hides its public home without changing existing event publication or registration settings.

Public HTML is `/communities` and `/communities/:organization_slug/:group_slug`. The existing `/community` attendee directory and its route helper remain unchanged. Community pages display only their organization's published events, divided by actual end time into upcoming/ongoing and past events. Each event retains its dates and timezone. Each section paginates independently in groups of 24 with a bounded page number.

The separate anonymous, read-only JSON contract is `/api/public/v1/communities` and `/api/public/v1/communities/:organization_slug/:group_slug`. It provides schema version 1, prefixed community/event IDs, explicit ownership and allowlisted public facts. Detail responses include independent upcoming/past pagination totals. It exposes no memberships, attendees, orders, tickets, passes or native authorization scopes. Existing native legacy contracts remain separate; no mobile client integration, release signing or device verification is claimed.

No real Pune Ruby community has been provisioned. Browser rehearsal creates transaction-scoped synthetic local data. This branch does not follow, enroll, invite, notify, grant roles, bill or send mail/push to a community's users. Existing free-pilot verified authentication and privacy behavior are reused.

## Validation and release gates

Meaningful regressions cover all three flag gates, verified sign-in, global administrator separation, owner/admin versus editor/viewer access, forged IDs in both-tenant memberships, fresh role change/revocation, idempotent association, rejection of implicit reassignment, failed publication recovery, escaped facts, draft exclusion, separate pagination, preserved legacy routes and the database foreign key. Isolated Brave rehearses private draft creation, publication, association, public event navigation, Back, keyboard skip navigation, four-width overflow checks, bounded unbroken facts at 320/390px and 44px organizer title links and the same signed-in session after membership revocation.

Backend legacy/native compatibility tests are executed separately from mobile validation. The mobile engineering playbook's actual device, auth-refresh, deep-link, push, offline and signed-release gates remain unverified by this web branch.

Before merge, require the exact reviewed head's CI and independent approval. Before deployment or enablement, review the combined release tree, obtain release approval, verify the actual production commit and existing rows, capture a restorable production database backup, rehearse the additive migration against representative data and verify the live migration/commit and browser smoke tests. These production actions are not performed here.

Migration `20261011030000` creates `community_groups`, adds a nullable event association and a supporting index, and enforces the same-organization composite foreign key. Existing event associations stay null. The event table/index/foreign-key operations can take locks and must be assessed against actual production size before release.

For runtime rollback, disable `MEETUP_GROUPS_ENABLED` and retain the additive schema and community data. A migration down removes community records and event associations: never run it on populated production data without explicit irreversible-deletion approval and a verified backup. The local down/up rehearsal runs only after confirming the owned test database has zero community rows and zero event rows.
