# Staff check-in: web and native contract

Status: proposed native contract implemented for check-in/lookup on the isolated
staff-checkin branch; not deployed. Native clients must use mocks until this
branch and staff authentication are approved and verified. No new credentials,
SSO grants, staff users or live attendance records are provisioned.

## Authentication

Existing web staff sign-in is GET `/session/new` then POST `/session` with email,
password, CSRF token and a cookie jar. It redirects and sets a signed HttpOnly
staff session cookie. Existing roles are `admin` and `desk`; attendee User login
is not sufficient. DELETE `/session` signs out. Login is rate-limited.

Native JSON sign-in/session bootstrap is NOT implemented here. Decide whether
the native app uses an approved hosted authentication handoff or a dedicated
first-party JSON session flow before implementing real sign-in. Do not scrape or
share the ticketing attendee cookies, invent bearer credentials, put passwords
in URLs, or store raw QR secrets in logs/analytics. Preserve CSRF/session rules.
For now, the native client can mock the payloads below. Production integration
requires explicit session-expiry/revocation/logout and secure-storage tests.

## Endpoints (staff session required)

- GET `/checkin.json?date=2026-10-08&q=Grace`: returns `date`, `event_dates`,
  `max_batch_size` (50), `more_results`, `stats` and `tickets`. Search is capped
  at 20 visible records; there is no implicit selection across pages. Returns
  confirmed, non-canceled tickets only. Invalid read dates use the established
  default event date, so display the returned date rather than the request.
- Ticket fields: `id`, `attendee_name`, `attendee_email`, `ticket_type`,
  `order_code`, `order_status`, `event_starts_on`, `event_ends_on`, `canceled`,
  and `checked_in_at` for the returned date. No QR secret or claim token.
- POST `/checkin`: JSON `{ "secret": "<scanned value>", "date": "2026-10-08" }`
  for camera input, or `{ "ticket_id": 123, "date": "2026-10-08" }` for a
  manual action. The raw QR goes only in this HTTPS request body. Never log it.
- POST `/checkin/batch`: JSON `{ "ticket_ids": [123, 124], "date": "2026-10-08",
  "confirmed": true }`. Confirm the explicit names/count/date before submitting.
  Maximum 50 unique positive IDs. No `all`, pagination token or wildcard.
  Duplicate IDs are coalesced; retries return duplicate outcomes rather than
  incrementing attendance. Missing confirmation, malformed IDs or an invalid
  date rejects the whole request without attendance mutations.

Single results have `ticket_id` and `attendee` when found, `state`
(`success`, `warning`, `error`), `message`, and `checked_in_at` on success.
They also include `checked_in_count`, the server's current count for the day,
and `stats: { total, checked_in, by_type: [{ name, total, checked_in }] }`.
HTTP 200 means success, 409 duplicate, 404 unknown, 422 ineligible/invalid input,
and 401 expired/missing staff session. Batch HTTP 200 contains `results` in
selection order and `checked_in_count`; it is NOT all-or-nothing and does NOT
mean every attendee succeeded. Inspect every result's state. Missing tickets
retain the requested `ticket_id` in batch results. Never infer success from a
2xx without the expected response schema, or increment counters optimistically.

Timeouts/offline/5xx may follow a committed individual result. Say "not confirmed"
and retry the same IDs/date safely; never tell staff the attendee is admitted
without confirmation. A batch may have partially committed before a transport
failure. Disable repeat submit while awaiting a response. Do not queue invisible
offline attendance mutations.

## Eligibility and audit

Only paid/confirmed orders and non-canceled tickets qualify. Completed free and
complimentary orders use the existing `complete_comp!` → paid path and need no
captured Razorpay payment. Zero price alone is not eligibility. Pending, expired,
canceled, or refunded/canceled tickets are rejected. Enforce each ticket type's
configured event date bounds within the October 8–11 event dates. Legacy ticket
types with no date bounds keep the global event window; audit data before launch.

Order then ticket row locks serialize concurrent scanners and batch requests.
Successful attendance and its operator audit commit atomically. Duplicate and
ineligible attempts record their outcome too, without raw secrets. Historical
pre-audit check-ins are preserved; no operator is fabricated for them. This is
entrance attendance, not meal, giveaway or session redemption.
