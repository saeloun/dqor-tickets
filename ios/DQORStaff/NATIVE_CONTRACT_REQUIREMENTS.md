# Native staff integration requirements

Status: integration acceptance requirements for the backend/native owners. The native app remains mock-only. This document is confined to the iOS change; it does not edit or authorize backend work.

## Latest backend handoff received

The backend owner published `docs/NATIVE_STAFF_API.md` during this review. Native v1 is implemented for integration testing, disabled by default, not deployed/enabled for production, and scoped to the existing single `dqor-2026` event. It now provides:

- `POST /api/staff/session`: existing admin/desk credentials; a 256-bit opaque Bearer token (digest-only server storage), 8-hour expiry, no refresh token, event/date scope, `tickets:read` and `checkins:write`, and a 50-ticket maximum. No web-cookie fallback.
- `GET /api/staff/session`: current scope/expiry. `DELETE /api/staff/session`: revoke the current native session. Password/role/account/session changes revoke replay; web logout does not revoke native sessions.
- `POST /api/staff/checkins/resolve`: secret/date body; `state: resolved`, canonical date, minimal ticket fields, `eligible`, and `checked_in_at`; no attendance or attendance audit writes. `GET /api/staff/checkins` provides bounded search.
- `POST /api/staff/checkins/confirm`: explicit IDs/date/confirmation; locks and rechecks eligibility; per-ticket results; one transaction rolls back unexpected errors; safe attendance retries with duplicate outcomes.

These routes resolve the earlier absence of native session/preview operations. They do **not** establish approved live integration. Remaining decisions/evidence include the authorized staging origin and fixtures, Keychain accessibility/backup policy, end-to-end expiry/revocation/logout and timeout recovery tests, precise nested outcome classification (avoid parsing message prose), physical-device checks, and release authorization. The local mock role matrix is not production policy. A future universal-event adapter must retain `dqor-2026` as the canonical single-event mapping until multi-event authorization exists.

## Nonmutating QR resolution — required for continuous batch scanning

The proposed `POST /checkin` is a mutation and must never implement `StaffAPI.resolveQR`. A scan in DQOR Staff adds a ticket to a review list; only **Confirm check-in** submits attendance.

Verify the new read-only resolution operation against these guarantees before connecting the native adapter:

- An authenticated staff session and the same scoped authorization as attendee lookup are required. Anonymous or attendee sessions cannot enumerate staff records.
- The opaque secret is supplied only in an HTTPS JSON request body, never a URL/query string, response, analytics, or log. Redact both parameter values and error dumps. Apply input-size limits and rate limits.
- The request includes the selected event/date context. Universal-event support needs a stable event identifier or an explicit documented single-event mapping; display the canonical returned event/date, never silently keep a rejected client date.
- A successful response includes stable ticket ID, minimum attendee display fields, canonical event/date, eligibility, and current check-in status for that date. It does not echo the secret or claim token. It must distinguish “resolved for review” from “checked in.”
- Resolution creates **zero attendance, check-in, redemption, or attendance-counter changes**, including duplicate scans and concurrent resolutions. A security lookup log, if needed, must be documented and secret-free; do not record a successful attendance audit.
- Unknown/malformed secrets, wrong event/day, ineligible/canceled/refunded/pending tickets, duplicate/already-checked-in tickets, expired/revoked sessions, and forbidden capabilities have documented status codes and stable machine-readable outcome codes. Supply sample JSON for each case; human message text is not a parser contract.
- Repeated resolution is safe. Ticket revocation between resolve and confirm is still enforced by the existing batch mutation. Resolution never reserves entry or promises eligibility at submission time.
- Regression evidence should assert unchanged attendance count/timestamp and unchanged success-audit count after repeated/concurrent lookups, plus staff auth, CSRF, eligibility, unknown-ticket, and log-redaction behavior.

The app has no network route configured. The proposed `/api/staff/checkins/resolve` response can map to `Attendee` after the above verification without changing the scanner/review semantics.

## Native authentication — proposed first-party flow requires integration verification

The proposed native flow is now first-party JSON session creation, separate from web CSRF/cookies. Preserve that isolation. The native app now contains a disabled HTTP adapter and token-only Keychain store, tested through injected fakes. Its entry point still uses only the demo, and no live calls or credential UI are enabled; do not scrape attendee cookies or create credentials. Hosted-handoff-specific requirements below apply only if the approved approach later changes.

Verify the concrete auth specification and authorized test environment against:

1. Authorized HTTPS host(s), staff issuer/audience, native bundle/callback target if applicable, and CSRF/PKCE/state/nonce rules for the selected mechanism. Credentials and secrets must never appear in URLs or source.
2. Success/error payloads, staff identity and server-issued capabilities, authorized event catalog, canonical date/timezone, and max batch size. Admin/desk are the existing backend roles. Owner/admin/organizer/team-lead/volunteer/finance/AV in this app are future fixture labels only; server-issued capabilities govern access.
3. Expiry, renewal, revocation and forced logout semantics, including 401 versus 403, role/capability changes during a session, and the behavior of in-flight check-in requests. A transport error after submission must remain “not confirmed.”
4. Secure storage policy: approve the proposed token-only Keychain store using WhenUnlockedThisDeviceOnly, no synchronization/access group, and origin-bound service identity before enabling staging. No passwords or web cookies are retained. Validate logout cleanup/revocation and locked-device behavior.
5. Authorized synthetic staging staff identity and event fixtures supplied through an approved secret channel, not committed to Git. Session bootstrap, refresh, revocation, logout, forbidden-role and lost-network tests must pass before a production adapter is enabled.

## Lookup and submission adapter acceptance

- Preserve `GET /checkin.json`'s returned `date`, `event_dates`, `max_batch_size`, and `more_results`. The current native catalog is configurable fixtures, not proof of multi-event backend support. No hidden all-results selection; load/selection limits are explicit.
- Submit only reviewed ticket IDs and canonical event/date with `confirmed: true`. Cap at 50 or the lower server-issued limit.
- Validate every batch result against the selected stable IDs. Mixed success/warning/error results remain independent. HTTP 200 alone is not success. Unknown/missing/unexpected results leave the batch unconfirmed.
- Clarify whether every nested result includes a stable outcome code/status; HTTP status only applies to the outer batch. Map duplicate versus ineligible versus unknown without parsing prose.
- The local UUID is a client request seam, not an assumed Rails idempotency header. The reviewed server safely retries the same IDs/date with duplicate outcomes. Preserve that behavior, server counts, and operator attribution; never increment attendance optimistically.
- Reconcile partial commits after timeout/offline/5xx. Do not automatically retry or queue attendance while offline. Explicitly describe whether a duplicate response provides enough canonical timestamp/context to show “already checked in.”

Signing/team/App Store Connect provisioning and distribution are outside these requirements and remain separately approval-gated.

The disabled adapter implements these seams in `NativeStaffAPI.swift`; see [NATIVE_ADAPTER.md](NATIVE_ADAPTER.md) for structural DTO mapping and the remaining stable-outcome-code request. No provider access, live credentials, or production mutations were authorized by implementing this adapter.
