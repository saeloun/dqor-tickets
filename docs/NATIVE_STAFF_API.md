# Native staff API v1 (disabled by default)

Implemented for integration testing; not enabled or exercised in production.
Use HTTPS and the existing AdminUser staff credentials. Attendee User accounts
are not staff identities. No new users, live grants or secrets are provisioned.
This is scoped to the existing single DQOR 2026 event, not a multi-tenant API.

## Configuration and session

Both `NATIVE_STAFF_API_ENABLED=true` and `NATIVE_STAFF_EVENT_DATES` are required.
The latter is a comma-separated subset of 2026-10-08 through 2026-10-11. Absent or
invalid dates fail closed (503); disabled API returns 404. Dates are checked on
every request, so reducing configured days immediately restricts existing tokens.
Leave disabled until target, migration, native secure storage and device tests pass.
No separate signing secret is needed; opaque 256-bit tokens are stored only as SHA256
digests. Never put passwords, tokens or QR secrets in URLs, logs or analytics.

POST `/api/staff/session` with JSON `{ "email": "...", "password": "..." }`.
Existing admin/desk accounts can authenticate; 10 attempts per IP per 3 minutes.
Response 201: `{ access_token, token_type: "Bearer", expires_at, event: "dqor-2026",
event_dates: [...], capabilities: ["tickets:read", "checkins:write"], max_batch_size: 50 }`.
There is no refresh token. Session expires after 8 hours; reauthenticate afterward.
Store the token only in iOS Keychain/Android Keystore-backed storage; never retain
the password. API returns Cache-Control: no-store and does not establish web cookies.

Send `Authorization: Bearer <access_token>` on every subsequent request. GET
`/api/staff/session` returns scope/expiry without repeating the token. DELETE the
same URL revokes that database session and returns 204; clear device storage even
if transport fails and require server-confirmed logout before claiming revocation.
Password changes, role changes, account deletion, expiry and session deletion deny
replay. Web logout revokes its web session only. To revoke all native devices for
an account, delete its NativeStaffSession records through authorized operations.
Tokens cannot authenticate Avo/web routes; web cookies cannot authenticate native routes.
401 means sign in again, 403 means missing capability/event day, 422 malformed input.

## Read-only preview

POST `/api/staff/checkins/resolve` with JSON `{ "secret": "<QR value>", "date": "2026-10-08" }`.
Requires `tickets:read` for that event day. 200 response:
`{ state: "resolved", date, ticket: { id, attendee_name, attendee_email, ticket_type,
order_code, eligible, checked_in_at } }`. A resolved QR is NOT an admission.
Unknown QR returns 404; ineligible tickets resolve with `eligible: false`.
Neither attendance nor an attendance audit is written by this endpoint. No raw
QR secret or claim token is returned. A preview can become stale; confirmation
always reevaluates eligibility under database locks.

GET `/api/staff/checkins?date=2026-10-08&q=Grace` requires the same capability and
returns `{ date, more_results, tickets: [...] }` with at most 20 records. Ticket
shape matches resolution. Search includes confirmed, non-canceled tickets.

## Explicit confirmation

After showing the attendee names/count/date and obtaining confirmation, POST
`/api/staff/checkins/confirm` with JSON `{ "ticket_ids": [123,124],
"date": "2026-10-08", "confirmed": true }`. Requires `checkins:write` for that day.
Accepts at most 50 distinct positive IDs; repeated IDs are coalesced. No implicit
all-pages selection, wildcard, client-supplied capability or scope override.

Response 200 is `{ date, results: [...] }` using the existing per-ticket result
shape: `ticket_id`, `attendee` when known, `state` success/warning/error, `message`,
and `checked_in_at` on success. Inspect EVERY result; some attendees can be ineligible.
Database locks recheck payment, cancellation, ticket-type dates and duplicates.
The native confirmation transaction commits accepted attendance and audits together;
an unexpected exception rolls back that request. Expected individual rejections
remain per-ticket outcomes, so 200 does not mean every attendee was admitted.

### Additive v1 outcome codes

Each confirmation result now includes `code`, matching its audit outcome:

| code | state | Meaning |
| --- | --- | --- |
| `success` | `success` | Admission recorded; `checked_in_at` is returned. |
| `duplicate` | `warning` | Previously admitted on this date; attendance is unchanged. |
| `not_found` | `error` | Requested ticket does not exist. |
| `unconfirmed` | `error` | Order is not confirmed/paid. |
| `wrong_date` | `error` | Ticket is invalid on the requested event date. |
| `canceled` | `error` | Ticket or order is canceled. |

This is an additive v1 response change: existing `state`, `message`, identity fields,
and success timestamp retain their meaning. Older clients may ignore `code`.
New clients must use the exact code/state pairs above, never parse display messages,
and fail closed for missing codes (including older servers), unknown future codes,
or mismatched code/state pairs: show an unsupported/unverified outcome and require
staff resolution, without displaying a new admission success. Only `success` records
a new admission; `duplicate` must be shown as already admitted. HTTP 200 alone is
not admission authorization. Codes apply to individual confirmation results, not
request-level authentication/validation errors or read-only QR previews. Client-side
enforcement belongs in the mobile adapters and must be tested there before live use.
The native feature remains disabled by default; this addition does not enable it.

Repeated confirmation is idempotent for attendance: same ticket/day retains its
original timestamp, returns a duplicate warning and never adds another success.
Duplicate attempts may add duplicate audit rows. A timeout can follow a commit:
retry the same IDs/day to resolve uncertainty, and never admit optimistically.
No offline mutation queue is provided. A scan-to-preview must NEVER call the
legacy POST `/checkin`, which is an immediate web scanner action.

## Verification before native live use

Local requests test disabled/configured gates, credential rate limit, token digest
storage, no cookie fallback, read-only QR resolution, bounded search, explicit
confirmation, capability/day denial, changed eligibility, duplicates, transaction
rollback and logout/expiry/password/role/session revocation. Native real-device
login, TLS origin validation, camera input, secure storage and logout integration
remain separate release gates. Do not claim live native integration from mock tests.
