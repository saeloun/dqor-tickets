# Native integration gate and exact DTO needs

No production authentication or network adapter is implemented. The types in
`CheckIn.kt` are demo domain models, **not wire DTOs**. Backend implementation and
native authentication both need approval before integration.

## Confirmed proposed wire fields

- Lookup response: `date: ISO-date`, `event_dates: [ISO-date]`,
  `max_batch_size: integer`, `more_results: boolean`, `stats`, `tickets`.
- Ticket: `id: positive integer`, `attendee_name: string`,
  `attendee_email: string`, `ticket_type: string`, `order_code: string`,
  `order_status: string`, `event_starts_on/event_ends_on: ISO-date or null`,
  `canceled: boolean`, `checked_in_at: ISO timestamp or null`.
- Stats: `total`, `checked_in`, `by_type: [{name, total, checked_in}]`.
- Single result: `ticket_id` and `attendee` when found, `state` with values
  `success|warning|error`, `message`, `checked_in_at` on success,
  `checked_in_count`, `stats`. Missing-ticket fields must be nullable.
- Batch result: ordered `results` plus `checked_in_count`; every result is
  independently inspected. Request is `ticket_ids`, `date`, `confirmed: true`.

Android's `DUPLICATE` enum must map from documented warning/HTTP 409, never be
serialized as a wire value. Use the returned lookup date and server counts.
Keep bounded integer validation and reject malformed/missing required fields;
HTTP 200 alone cannot prove success. Confirm exact field nullability/types with
backend fixtures, especially attendee shape and errors without ticket fields.

## Pending read-only resolve DTO

Backend owner is adding a **separate read-only QR resolve** operation. Its route,
method and schema were not in the API document available during this revision.
Do not invent them. We need fixtures specifying:

- Input location for QR secret (HTTPS body only), event/day scope and validation.
- Resolved ticket identity/display fields, eligibility status and reason,
  existing attendance timestamp, canonical date and any count/stats fields.
- Whether confirmation submits a ticket ID or a short-lived resolve handle;
  mutation still rechecks eligibility and authorization server-side.
- Status/schema for unknown, wrong-event, expired/ineligible and duplicate QRs,
  401/403, rate limit, malformed input, timeout and 5xx.
- Proof that resolve never changes attendance/audit success counts.

The current mock scanner directly performs a labelled demo check-in. It is not a
production preview implementation. Production must resolve, display identity,
then explicitly confirm before mutation. Clear raw QR memory after resolve and
never store it in saved state, logs, analytics or URLs.

## Other missing contracts

Authentication needs approved session establishment, staff role/capabilities,
CSRF handling (if cookie-based), expiry, revocation, logout and secure-storage
rules. Multi-event discovery needs stable event IDs, authorized endpoints,
canonical time zone/dates and approved branding schema; the current backend is
single-event. Do not trust an arbitrary catalog URL with staff credentials.

Required integration tests: two same-name attendees; stale eligibility between
resolve and mutation; expired session; partial batch response; timeout after
commit; malformed 2xx; response date differs; concurrent scanners; process death
while awaiting response. Every uncertain mutation remains “not confirmed”; no
offline queue or optimistic attendance count.
