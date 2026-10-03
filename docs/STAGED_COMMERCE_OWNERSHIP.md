# Staged commerce ownership — internal service only

Depends on the organization/event foundation (PR151). This increment adds nullable event ownership for TicketType, Order, and Ticket, plus a namespaced authorization/query/draft-management service. **No routes call it. No generic checkout or issuance is implemented. Do not populate real event-owned orders/tickets or enable this in production yet.**

## Compatibility and ownership

The legacy DQOR checkout continues to create `event_id = NULL` records. No backfill, environment activation, grants, provider credentials, or production migration is part of this work. Existing global model methods and finance/check-in endpoints are unchanged. Coordination with their owners precedes the change: preserve PR148 payment/refund/document boundaries, the finance-readiness billing-details token and issuance lock, and the check-in owner's Ticket/check-in methods. This change does not authorize members to visit global finance/admin pages.

`20261002200000` adds nullable event foreign keys and an internal stored generated `ownership_key = COALESCE(event_id, 0)`. Composite foreign keys enforce that each ticket has the same ownership as its order and ticket type, including NULL-owned legacy records. A normal nullable composite foreign key alone would silently skip the NULL case. IDs must be positive when present. Slugs retain existing global uniqueness; draft creation generates an opaque event-prefixed unique slug.

The generated column/index/constraint creation can rewrite or lock existing tables. This is a proposed migration, locally validated only. Review production row counts, lock budget, backups, staging rehearsal, and deployment window before application. Down migration removes ownership columns/constraints and therefore discards ownership metadata: rollback is acceptable only while no real owned records exist; otherwise export and approve a recovery plan first. No automatic rollback of populated ownership is proposed.

## Internal API and privileges

`Platform::Commerce::Workspace.new(user:, organization_id:, event_id:)` requires both `ORGANIZER_PLATFORM_ENABLED=true` and `STAGED_COMMERCE_ENABLED=true` for **every call**. Both default off. Test examples stub flags locally; no environment is enabled by this branch.

| Operation | owner/admin | editor | viewer |
| --- | --- | --- | --- |
| List/read ticket-type drafts | yes | yes | yes |
| Create/edit ticket-type drafts | yes | yes | no |
| Order/ticket lists and lookups | yes | no | no |
| Order/attendee CSV exports | yes | no | no |
| Paid or complimentary order issuance | denied | denied | denied |

Fresh membership is checked for each call under a transaction/lock, so revocation/demotion affects existing workspace instances. Event must belong to the explicitly selected organization. All record IDs and order-code lookups are event scoped; there is no global admin bypass. Results are frozen allowlisted attribute snapshots, never live Order/Ticket instances, lazy relations, payment methods, claim tokens, order codes, or ticket secrets. CSV exports use the same scopes, omit billing addresses/snapshots, GST data, review notes, metadata, provider IDs, and private links, and escape spreadsheet formulas. They do not invoke legacy invoice/tax exporters.

Inventory writes permit only name, description, price, capacity, and per-order quantity bounds. Ownership/slug/active/hidden mass assignment is rejected. Both application and database enforce **hidden + inactive** for all event-owned ticket types; publishing an Event does not change that. Legacy checkout therefore cannot display or sell these drafts. There is no deletion, public sale activation, coupon management, ticket mutation, check-in, or refund API here.

`create_order!` always raises `ProviderOnboardingRequired` after authorization, including for zero-value/complementary orders. No call reaches global Razorpay, invoice, PDF, mail, or refund behavior. There is deliberately no configurable bypass for this gate.

## Actual completion versus pending commerce

Completed: persisted ownership metadata and constraints; strict internal policy; draft inventory management; scoped reads/lookups/exports; provider/issuance refusal; two-organization + same-organization different-event + legacy-null regression matrix.

Pending before **any** live owned order/ticket or commerce route: explicit organization seller/legal identity and provider onboarding; tenant-specific payment/webhook/refund routing; invoice policy, counters, billing snapshots and fulfillment branding; all legacy public order/claim/access, wallet/PDF/email, attendee account queries, background jobs, Avo/global admin, check-in/batch/native and slot paths either scoped or explicitly denied for owned records; capacity and coupon policy; complete end-to-end and cross-tenant threat tests. Existing global routes are still legacy and may resolve manually inserted event-owned records, so these records must not be provisioned as a workaround. This PR does not claim those routes are tenant ready.

Review exact Vipul identity and Saeloun roster independently before grants. Never infer employees from Slack or email domain. A later backfill requires explicit event mapping, a dry run, reviewed counts, and a rollback plan.
