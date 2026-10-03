# Attendee account and pass-status API draft

The reviewed PR189 read-only facade was deployed on 2026-10-03 at main `6842a5b0b6224f24f78332593aff3b9b56d62be8`; its feature switch remains absent, so it is disabled. It uses the existing email-verified attendee web session. A separately implemented, undeployed, default-off bearer bridge is documented in [NATIVE_ATTENDEE_PKCE_DRAFT.md](NATIVE_ATTENDEE_PKCE_DRAFT.md). Existing staff authentication stays separate.

## Bounded implementation

1. Add default-off GET routes for account and assigned pass status; no migration or auth issuer.
2. Reuse the existing User web session and require its verified_attendee_email to equal the current normalized User.email, as Account::RedemptionsController already does. Reject Authorization headers instead of interpreting staff/native bearer tokens.
3. Query only the singleton DQOR legacy ticket, order and ticket-type scopes. Match the assigned attendee email; a buyer who assigned a pass to another person does not acquire that person's status through this API.
4. Read current payment/cancellation/assignment state on every request. Preserve stored ticket-type admission dates and recorded attendance. Return no QR secret, claim token, wallet URL, order code, other attendee identity, payment or special-purpose entitlement data.
5. Verify with synthetic local request journeys, then independent security/testing/Rails/quality/performance review. Leave draft and feature switch off pending contract agreement and action-time production approval.

The API does not enroll an attendee, send email, assign tickets, admit anyone, redeem food/party benefits, grant roles or mutate orders. User creation and verified login continue through existing web flows.

## Proposed contract for native owner

Fixed first-party HTTPS origin: https://deccanqueenonrails.com.
Feature switch: NATIVE_ATTENDEE_READ_API_ENABLED must equal true; absent/false returns404.

GET /api/attendee/v1/account returns schema_version1, event dqor-2026, checked_at(serverISO8601), account{id,name,email}. GET /api/attendee/v1/passes returns schema_version1,event,checked_at, passes,more_results,next_cursor. Page size20, positive canonical ticket-ID cursor and stable ID-ascending order. Invalid cursor422. IDs are strings; timestamps are server observations, not permission leases.

Pass fields are limited to ID, ticket type ID/name, current status, stored admission-date bounds and existing daily entry status. Status vocabulary confirmed,canceled,expired,pending. A paid order remains paid after its old checkout-hold expires_at; an elapsed unpaid checkout hold is expired without writing the order. Cancellation overrides eligibility. Daily eligibility follows paid/noncanceled state and existing TicketType#valid_on? within Ticket::EVENT_DATES. A timestamp is recorded attendance, not permission to admit again. Reassignment removes the pass on the next request. No food/party entitlement or purpose is inferred from the conference title/date.

401 means attendee web session required;403 means verified attendee email required or unsupported Authorization header/production insecure request;422 malformed cursor;404 disabled. All success/error responses private,no-store and Referrer-Policy:no-referrer; no cached304 private snapshots. Do not log bodies or copy any session cookie into telemetry/diagnostics. The client must clear private snapshots on logout, identity change or authentication failure and must not show cached eligibility as live.

The draft DTO has string account/pass/type IDs. Success responses include `schema_version`, `event`, and ISO8601 `checked_at`. Account responses add `account: {id, name, email}`. Pass responses add `passes`, boolean `more_results`, and nullable string `next_cursor`. Each pass is exactly `{id, type: {id, name}, status, admission: {starts_on, ends_on}, entry: [{date, eligible, checked_in_at}]}`. Nullable admission bounds preserve stored nulls. Entry dates come only from existing `Ticket::EVENT_DATES`; recorded check-in timestamps may be null.

Error responses are `{schema_version: 1, error: {code}}`. Exact codes are `not_found` (404, disabled), `unauthenticated` (401, no current User), `https_required` (403, production HTTP), `authorization_not_supported` (403, any Authorization header), `email_verification_required` (403, missing/mismatched email-link proof), and `invalid_cursor` (422). Authentication gates run before cursor validation. Page size is fixed at20; an optional cursor must be a positive canonical decimal string within signed64-bit ID bounds. Arbitrary requested limits cannot increase the page size. This reviewed contract is deployed but remains disabled.

## Identity, expiry and revocation boundaries

Existing attendee User identity is distinct from AdminUser admin/desk identity. Magic-link verification expires after30minutes and sets verified_attendee_email only after validation. Google sign-in currently does not set that marker; this API denies it until the existing email-link verification flow is completed. No Google verification rule is changed in this draft.

The web account uses a Rails cookie session. Web logout resets that browser's cookie session, and a changed/deleted User or mismatched verified email cannot read. The existing cookie-session design does not supply a server-stored attendee session record, an explicit bearer lease or server-side revocation of a copied cookie after logout. This draft must not claim those properties. No session lifetime, password semantics or magic-link behavior is silently changed.

A system-browser cookie is not automatically shared with an iOS/Android native HTTP client. Therefore this draft cannot honestly be called direct native authenticated integration. A same-origin first-party WebView/Hotwire session transport would require the native owner's explicit design, secure cookie isolation, TLS and logout tests. The separately authorized [native attendee PKCE bridge draft](NATIVE_ATTENDEE_PKCE_DRAFT.md) adds its own fresh email proof, bounded bearer expiry and server revocation. It remains undeployed and disabled; it does not change these existing cookie-session boundaries or prove physical native integration.

Short-term ready path: open https://deccanqueenonrails.com/account in the system browser. Existing login, purchaser ticket dashboard and https://deccanqueenonrails.com/account/redemptions serve their current semantics. The browser owns its cookies; the native app does not read email-link tokens or copy cookies. This is existing web access, not a completed native wallet/QR integration.

## Production action-time gates

The parent must agree the exact attendee transport/auth contract with the native owner before activation. The current request authorizes this isolated draft and synthetic local tests, not production credential/session issuance or feature enablement. A reviewed exact combined head, real-device first-party TLS/cookie/privacy/logout behavior, selected verified attendee test identity and approved bounded data reads are required before an action-time request to set NATIVE_ATTENDEE_READ_API_ENABLED=true and deploy. The separate bearer bridge contract and its activation/device/proxy/retention gates are documented in [NATIVE_ATTENDEE_PKCE_DRAFT.md](NATIVE_ATTENDEE_PKCE_DRAFT.md); its local implementation does not authorize activation. No privileged grant is needed for an attendee.

Staff scanning uses a separate existing surface: NATIVE_STAFF_API_ENABLED plus NATIVE_STAFF_EVENT_DATES. Normal existing admin/desk login issues eight-hour tokens with BOTH tickets:read and checkins:write. The proposed least-scope test date remains2026-10-08 only; backend permits nonempty subsets of2026-10-08 through2026-10-11, but those public dates alone are not operator authorization.

Phone camera input must POST the opaque QR value in JSON to /api/staff/checkins/resolve, which is read-only. Never use legacy POST/checkin for preview. GET/api/staff/checkins gives at most20 results; confirmation requires explicit selected IDs/date/confirmed:true and max50 distinct IDs. A phone app must display every strict code/state pair: success/success,duplicate/warning,not_found|unconfirmed|wrong_date|canceled/error. A200 alone is not admission. Do not parse messages or synthesize counts. No offline queue or optimistic admission.

The staff native contract supports regular admission only. It does not provide native EventSlot food/party redemption or purpose selection. Do not label these as connected or route them through regular entry confirmation. Parent must select a named existing admin/desk operator before the final production activation/test question; no account/grant is created to unblock testing. Physical camera, permission-denial fallback, secure storage, expiry/role/password/session revocation and ambiguous-confirmation recovery still need native-owner evidence. No real attendance/payment/email test write is authorized here.

Disabling the staff API blocks requests but does not erase existing tokens. Test logout must be server-confirmed; re-enabling before eight-hour expiry can revive otherwise valid outstanding sessions. Web logout is separate. Production revocation/deletion beyond the chosen session needs its own approval. No pending Wallet/CodeQL hardening or Campfire work is included.
