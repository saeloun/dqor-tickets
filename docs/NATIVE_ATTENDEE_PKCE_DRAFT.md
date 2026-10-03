# Native attendee PKCE bridge draft

This isolated draft is off by default. It adds a separate, read-only attendee bearer namespace; it does not activate production, provision Users, change ordinary web/staff authentication, or grant admission, purchase, food, party, refund, or wallet rights. Existing cookie API DTOs are preserved through the same private snapshot service.

## Activation and client configuration

Disabled new-flow paths stop in the outer privacy middleware before request-body parsing, authorization database/cache work or job enqueueing. Both an explicit gate and valid callback configuration are required:

- `NATIVE_ATTENDEE_SESSION_API_ENABLED=true`
- `NATIVE_ATTENDEE_CLIENT_CALLBACKS` is a JSON object mapping only `dqor-ios` and/or `dqor-android` to unique exact HTTPS callback URLs on `deccanqueenonrails.com`, port 443, under `/native/attendee/`.

There are no default callbacks. Missing, malformed, duplicate-key, unknown-client, wildcard, userinfo, query, fragment, noncanonical host, percent-encoded path, traversal, and duplicate-target configurations fail closed. An individual request must match its configured URL byte for byte. The following entries are synthetic test fixtures only, not production callback decisions:

```json
{"dqor-ios":"https://deccanqueenonrails.com/native/attendee/synthetic-ios/callback","dqor-android":"https://deccanqueenonrails.com/native/attendee/synthetic-android/callback"}
```

Signing identities, final client callback paths, association files and physical app handoff remain owner decisions. This draft adds no wildcard or association files. Production requires HTTPS; local synthetic test transport is HTTP only to the local test server.

## Browser authorization

1. The client keeps a cryptographically random state and an RFC 7636 verifier in memory only for one active attempt. It does not persist either value; process death cancels the client attempt and requires a fresh start. Open `GET /account/native/authorize` with `client_id`, `redirect_uri`, `state`, `code_challenge`, and `code_challenge_method=S256`. State accepts 32–128 URL-safe characters. Challenge accepts exactly 43 URL-safe characters. No plain PKCE is supported.
2. `POST /account/native/email` requires the form's valid Rails CSRF token and browser attempt cookie. It accepts an email and returns the same 202 HTML response for existing and absent Users. It never provisions a User. A native-specific job looks up the existing identity and generates the credential inside the job, with only authorization ID/email in queued arguments. Raw verification credentials are never queued. The job rechecks gate, callback, pending state, expiry and current email immediately before synchronous delivery.
3. The delivered verification link uses the explicit canonical HTTPS origin. `GET /account/native/verify?token=...` verifies its native-specific purpose and immutable attempt binding, resets the browser session and establishes only the consent context. An ordinary account magic link cannot substitute for this proof. GET never creates a code or bearer session.
4. `GET /account/native/consent` displays the verified identity, app and thirty-minute read capabilities. `POST /account/native/consent` requires the valid CSRF token and consent proof. It issues one code and redirects with 303 to the exact configured callback, containing `code` and the original `state`. The app must independently match state before exchange.
5. `POST /account/native/cancel` requires valid CSRF and attempt proof. It cancels only an unfinished attempt. It cannot revoke a consumed bearer session.

Browser pages are asset/script/analytics free, frame denied, and private/no-store with no ETag or Last-Modified. Their `strict-origin` referrer policy strips all paths and query credentials while allowing normal Rails origin and masked-token CSRF validation. There is no custom null-origin exception. The CSP permits forms only to self and the exact displayed configured callback. JSON and callback fallback responses use `no-referrer`. Physical supported browsers still require proof of this complete flow.

A callback opened without app interception returns constant 410 text while enabled (404 while disabled), no credential echoes, scripts or telemetry. In local Chromium evidence the canonical callback is intercepted before any network request to production; only the email's origin is replaced in the test driver to visit the local verification route.

## Token exchange and bearer API

`POST /api/native/attendee/v1/token` accepts exactly this JSON body, no query parameters or Authorization header:

```json
{"code":"nac1_<43 URL-safe characters>","code_verifier":"<43–128 RFC 7636 verifier characters>","client_id":"dqor-ios","redirect_uri":"<exact configured callback>"}
```

Success contains exactly `access_token`, `token_type: "Bearer"`, `expires_at` (ISO 8601), `event: "dqor-2026"`, and `capabilities: ["account:read", "passes:read"]`. The token is `na1_` plus 43 URL-safe characters. Only SHA-256 code/token digests are stored. There is no refresh token, sliding expiry, or token in a URL.

All bearer requests require exactly `Authorization: Bearer <token>`; ordinary login cookies, admin cookies, staff tokens and noncanonical bearer forms cannot substitute. JSON and errors are private/no-store/no-referrer and cannot become cached 304 responses.

| Endpoint | Success |
| --- | --- |
| `GET /api/native/attendee/v1/account` | `schema_version: 1`, `event`, `checked_at`, `account: {id, name, email}` |
| `GET /api/native/attendee/v1/passes` | `schema_version: 1`, `event`, `checked_at`, `passes`, `more_results`, `next_cursor` |
| `GET /api/native/attendee/v1/session` | `schema_version: 1`, `event`, `client_id`, `capabilities`, `expires_at`, `checked_at`; no token echo |
| `DELETE /api/native/attendee/v1/session` | 204 after current session revocation; subsequent reads return 401 |

Account/pass/type IDs and pagination cursors are strings. `cursor` is an optional positive canonical decimal signed-64-bit ID; pages contain at most twenty passes in ascending ID order. A pass contains exactly `id`, `type: {id, name}`, `status`, `admission: {starts_on, ends_on}`, and `entry: [{date, eligible, checked_in_at}]`. Admission bounds are the stored nullable TicketType dates. Daily eligibility uses existing `Ticket::EVENT_DATES` and `TicketType#valid_on?`. No food/party or other entitlement dates are invented.

Ownership requires legacy Ticket, legacy Order and legacy TicketType, normalized assigned attendee email equal to the verified User email, and a nonblank assigned attendee name. Buyer-only, other-user, unassigned and cross-tenant combinations are excluded. Every read rechecks assignment, cancellation and payment/expiry state. A paid order's old hold deadline cannot make its pass expired. Pass states are `confirmed`, `canceled`, `expired` or `pending`. No order code, money, raw ticket/claim/QR secret, wallet URL, refund details, other contact, or bearer URL is returned.

Errors have `{"schema_version":1,"error":{"code":"..."}}`:

| HTTP | Code |
| --- | --- |
| 400 | `invalid_request` for wrong exchange transport/body |
| 401 | `invalid_grant` for denied exchange; `unauthenticated` for bearer denial |
| 403 | `https_required`; `invalid_consent` for Rails CSRF/origin denial |
| 404 | `not_found` while gate is absent/off |
| 409 | `invalid_attempt` for terminal, expired or mismatched browser attempts |
| 422 | `invalid_cursor` |
| 429 | `rate_limited`, `Retry-After: 180` |
| 503 | `configuration_unavailable`; `temporarily_unavailable` for counter/cache failure |

## Lifecycle, limits and privacy

The two new authorization/session tables have cascading User foreign keys and a unique authorization-to-session index. Attempts last ten minutes; one code lasts at most sixty seconds and never past the attempt deadline; one bearer session lasts thirty minutes. Terminal transitions persist on denial. Consumed/canceled/expired attempts cannot restart, replace their code or issue a second session. User → authorization → session lock order avoids inverse deletion locks. Concurrent consent/exchange tests use separate database connections.

Verification binds the current email and a nil-safe password-digest fingerprint. Consent, exchange and each bearer read recheck the current identity. An observed email/password mismatch persistently revokes the session; deletion cascades authorization/session rows. No ordinary web logout or cookie transport is used to authorize or revoke this separate bearer namespace. Secure storage, app state validation, clearing credentials after 401/expiry, and client logout calling DELETE belong to the native owners.

Shared hashed counters limit starts to 20/IP/3min; sends to 10/IP/3min and 3/email/15min; exchanges to 20/IP/3min and 5/attempt/3min. Production requires Solid Cache. Cold increments are serialized on its actual PostgreSQL connection; a one-second local advisory-lock timeout, nil counts and database/store errors fail closed. Cache infrastructure is unchanged. Counter TTL controls logical visibility; the existing 256MB cache eviction and default two-week maximum age are not a physical deletion guarantee for the three/fifteen-minute windows. Expired auth/session rows are retained; an approved retention/cleanup decision is an activation gate, and this draft activates no deletion job.

New-flow parameter, redirect and model filters suppress new credentials without changing unrelated public filtering. Native request/job Sentry scopes suppress events and secret breadcrumbs; existing public callbacks remain chained. Native mail instrumentation hides its credential-bearing body/recipient payload from the global ActionMailer debug subscriber. A native-path-only request logger filters the framework malformed-JSON raw-body debug message; the boot-installed logger is covered by a synthetic sentinel. Local tests use synthetic logger sentinels and Sentry's local dummy transport, not a remote telemetry service. Upstream proxy/access-log suppression evidence remains an activation gate; application tests cannot prove upstream behavior.

## Local evidence and remaining gates

Focused request/model/system tests exercise real local mail delivery, Rails CSRF, current identity checks, replay/expiry, separate-connection code/session races, User deletion races, cold Solid Cache counters/TTL, bounded lock contention, private DTO ownership, no-ETag conditional requests, logger/telemetry sentinels and actual Chrome form/callback/referrer behavior. Local Chrome completes email → verification → explicit consent → intercepted callback, followed by actual HTTP S256 exchange, own pass reads, DELETE 204 and replay 401. The consent screenshot contains only the synthetic attendee.

This is a backend transport draft. It does not prove iOS/Android secure storage, registered callback/signing identities, association behavior, physical app handoff, supported device browser compatibility, upstream logging, live configuration, operational cleanup, or production readiness. All require independent owner approval and evidence before activation.
