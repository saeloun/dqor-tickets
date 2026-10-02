# Disabled native adapter and integration gates

`nativeapi/NativeStaffClient.kt` now implements the proposed **native v1** DTOs
from the backend branch's `docs/NATIVE_STAFF_API.md`. It is separate from
`CheckInService`: the demo scanner's immediate mutation interface must never be
used as a production preview. MainActivity still exclusively uses mocks.

## Three independent gates

- `NativeConfig` defaults to disabled and has no default origin.
- `NativeIntegrationGate.ENABLED` is a compiled `false`; even an enabled config
  cannot instantiate `ApprovedNativeTransport` in this build.
- The Android application has **no INTERNET permission**.

Opening these gates requires reviewed staging approval and an explicit, fixed
HTTPS origin. No remote config or UI switch can turn them on. No credentials,
staff grants, live requests or attendance were created during implementation.

## Exact native wire DTOs

- POST `/api/staff/session`: `{email,password}` → 201 `{access_token,
  token_type: "Bearer", expires_at, event, event_dates, capabilities,
  max_batch_size}`. GET returns the scope without the token; DELETE returns 204.
- POST `/api/staff/checkins/resolve`: `{secret,date}` →
  `{state:"resolved",date,ticket}`. Resolution is read-only, never admission.
- GET `/api/staff/checkins?date=...&q=...` → `{date,more_results,tickets}`.
- Ticket: positive `id`, `attendee_name`, `attendee_email`, `ticket_type`,
  `order_code`, boolean `eligible`, nullable `checked_in_at` timestamp.
- POST `/api/staff/checkins/confirm`: `{ticket_ids,date,confirmed:true}` →
  `{date,results}`. Results contain `ticket_id`, optional `attendee`,
  `state: success|warning|error`, `message`, timestamp on success.
  Rails currently serializes confirmation IDs as strings; the adapter validates
  and accepts positive integer IDs or decimal strings, rejecting fractional IDs.

**Native endpoints provide no attendance counts/stats.** Do not infer totals from
successful results or reuse the legacy web lookup DTO. Confirmation preserves
ordered per-ticket states and validates returned IDs against the explicit request.
Malformed 2xx, unexpected dates, missing success timestamps or missing results
are not admissions. Resolve does not call the legacy POST `/checkin`.

## Session lifecycle and storage

Sign-in clears any prior local session and wipes the supplied password character
array after the attempt; no password is persisted. JSON/HTTP libraries necessarily
create short-lived immutable strings in process memory. Never log request bodies.
The token and expiry are encrypted with AES-256-GCM under a per-app, non-exportable
Android Keystore key and written atomically inside `noBackupFilesDir`. Fresh IVs
are generated for every write; AAD binds the storage format. No plaintext fallback.
Keystore hardware backing depends on the device and is not claimed from tests.

Restoration calls GET session before any ticket action to obtain current scope.
Local expiry/origin mismatch and server 401 clear the session. Capability/event/
date scope is checked locally and must still be enforced server-side on every
request. No refresh token exists. Logout clears local data/key first, then requests
revocation; transport failure returns `LOCAL_ONLY`, never a claim of server logout.
Operations are serialized to avoid local logout/sign-in races.

The real transport uses platform TLS validation, a fixed validated HTTPS origin,
no cookies/cache/redirects/automatic retries, bounded timeouts and a 1 MiB response
limit. Credentials are only in Authorization or sign-in JSON; QR is only in the
resolve JSON body. Diagnostic string forms redact sensitive request contents.

## Tests and release gates

JVM tests use injected fake transport/storage and synthetic values to test scope,
expiry, restore, revocation, logout uncertainty, duplicate/mixed outcomes, strict
schema validation, explicit confirmation and disabled transport. Device tests
exercise actual Android Keystore encryption, store recreation, deletion, fresh
nonces and corrupted storage. They do not authenticate against any server.

Before staging: review final backend fixtures and target origin; approve the gate
changes; wire a separate resolve-preview-confirm UI; verify device session expiry,
role/password revocation, TLS and logout against the approved staging server.
Before release: physical camera, TalkBack, process-death/rotation during a real
request and stale eligibility between preview/confirm. There is no offline queue.
Multi-event discovery/branding remains a separate contract; this API is scoped
to the single DQOR event. Never send staff credentials to event-supplied URLs.
