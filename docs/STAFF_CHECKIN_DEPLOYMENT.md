# Staff check-in rollout

Status: local/CI validation only. Production migration and deployment are blocked
until the actual Render workspace/service/database and current release are verified.

The migration `20261002150100` adds only `checkin_audits`, foreign keys and indexes;
it does not rewrite historic ticket attendance. Native staff sessions use additive migration `20261002150200`; the separate invoice
safety branch reserves `20261002160000`. Reconcile schema.rb on integration.

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

## Phone browser checks

The web route is `/checkin`; native API enablement is not needed. Production HTTPS
is required for camera access. Permission prompts remain user initiated, and the
camera selector lets staff choose the back/rear camera after permission. The
bundled software QR decoder runs without BarcodeDetector, including image-file
fallback. Permission denial leaves manual attendee search available. Hidden pages
and orientation changes pause admission callbacks; Restart camera resets the
scanner and requires the permission/start interaction again. Continuous scans are
serialized and repeated frames suppressed. No camera permission is requested by
batch/manual check-in.

Automated Chromium tests cover software-decoded QR images, simulated permission
denial/manual fallback, mobile layout, orientation restart and repeated frames.
Actual iPhone Safari/Android Chrome camera focus, rear lens selection, background
return and HTTPS permissions must still be exercised on those devices before
claiming verified hardware support.
