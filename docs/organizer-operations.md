# Sponsor and vendor operations (staged)

Base: foundation PR #151, commit 12efd3b. No dependency on commerce PR #153.
Migration 20261002210000 was checked against the foundation and current main;
no reservation collision was found.

Both ORGANIZER_PLATFORM_ENABLED and ORGANIZER_OPERATIONS_ENABLED must be
explicitly true. Both default off. Keep off until the parent integration and
tenant review are complete. No organization provisioning or membership grants
are included. Existing attendee User authentication is required. Only a fresh
owner/admin Membership may read, export, draft or write commercial data.
Editors and viewers receive 403; global AdminUser sessions grant no bypass.

Entry point: the event detail page links to operations for owner/admin when
its flag is on. Every resource has an event FK; organization ownership is
inherited through that event. Every request first resolves organization via
membership, then event via organization, then related IDs within that event.
No fields or behavior on public Sponsor, invoices, checkout, payment webhooks,
or Refund are changed.

## Manual workflow

1. Add an event-owned business contact. Optional local-template approval
   authorizes using that contact name and event title; it does not send email.
2. Record a cash or in-kind sponsor pledge, then explicitly commit it.
3. Record positive integer-paise installments against committed cash deals.
   In-kind estimates and pledges never count as received cash.
4. Create deliverables/giveaway tasks and mark them complete.
5. Record vendor commitments, partial expenses, and returned vendor cash.

INR only. Refunds are positive reversal records, not negative payments.
A parent row lock serializes amount checks: cash cannot exceed commitment;
refunds cannot exceed net recorded cash. Manual entries and audits are
append-only through the application, with no edit/delete endpoints. Each
write and its actor/event audit record commit in the same transaction.
Database operators retain their ordinary privileged access; this is not a
tamper-proof ledger or an accounting/tax-compliance system. References are
manual and are not evidence that a provider transfer occurred. No provider
reconciliation, payment execution, tax calculation, or automated outreach.

CSV exports only id, kind, amount_paise, occurred_on, sponsor_deal_id and
vendor_engagement_id. It excludes all user-authored text and contact data,
preventing spreadsheet formula content from entering the export. Responses
are marked no-store. Local outreach is an escaped deterministic template,
explicitly labeled with AI generation disabled. No AI API or secrets.

## Validation

Request/model tests cover two organizations, sibling events, foreign related
IDs, role changes/revocation, both flags, partial receipts/expenses/refunds,
amount limits, atomic audit rollback, read-only records, safe CSV and draft
approval. A 390px browser workflow checks the contact → pledge → commitment →
installment → completed giveaway flow and horizontal overflow.

Use a dedicated test database; do not point these commands at any real data.

    RAILS_ENV=test DATABASE_URL=postgresql:///dqor_operations_task15_test bin/rails db:prepare
    RAILS_ENV=test DATABASE_URL=postgresql:///dqor_operations_task15_test bundle exec rspec

Migration rollback removes only the six new operations tables. Integrators
must reconcile db/schema.rb with any sibling migration before enabling flags.
