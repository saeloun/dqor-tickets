# Staff check-in rollout

Status: local/CI validation only. Production migration and deployment are blocked
until the actual Render workspace/service/database and current release are verified.

The migration `20261002150100` adds only `checkin_audits`, foreign keys and indexes;
it does not rewrite historic ticket attendance. The earlier timestamp `20261002150000`
is reserved for the separate invoice safety branch. Reconcile schema.rb on integration.

Before release, verify the target PostgreSQL database, a restorable recent backup,
and the release entrypoint's `db:prepare` behavior. Run the additive migration before
serving the new code. Existing code can run while the audit table exists. Roll back
application code if needed and retain the audit table/data; do not drop the table as
an operational rollback. There is no live data backfill or change to ticket secrets.

Use authorized staff accounts and a designated synthetic staging ticket to verify
login, lookup, desktop/mobile selection, cancel, explicit confirmation, duplicate
retry, per-day eligibility and logout. Confirm no attendance changes on lookup or
cancel. Inspect logs for filtered secrets. Test an actual camera/device separately;
local automated decoder callbacks do not prove hardware compatibility.

Review legacy ticket types without date bounds before launch; their compatibility
fallback remains the global October 8–11 window. Production counts exclude unpaid,
canceled and out-of-day tickets. This change does not provision users or grants.
