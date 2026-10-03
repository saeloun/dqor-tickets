# Disabled native adapter

`NativeStaffAPI` now implements the reviewed native v1 routes behind an explicit configuration gate and injectable transport/storage. **DQORStaffApp still constructs DemoStaffAPI exclusively.** There is no live origin, credential-entry UI, runtime activation flag, provider grant, or production token in this change. Do not instantiate an enabled real transport until staging is approved.

## Wire behavior

- First-party credentials are transient JSON request-body inputs to `authenticate(email:password:)`; no password is stored. An existing valid local session must be signed out before another sign-in.
- `signIn()` restores only after `GET /api/staff/session` validates scope/expiry. Persisted token bytes never grant capabilities by themselves. Dates, expected event, canonical IDs, batch/search limits, response origin, HTTP status, and DTO fields are checked.
- `tickets:read` maps to lookup/scan and `checkins:write` to confirmation. Unknown capabilities grant nothing. The configured event presentation remains separate from the canonical server event/date; native v1 remains single-event.
- Search preserves `more_results` and displays a refinement notice without implicit selection. Numeric and string ticket IDs are accepted only as positive canonical integers. The server searches name/email/order code; a future live UI must use that wording instead of the demo's ticket-ID hint.
- QR lookup uses only `/api/staff/checkins/resolve`. It preserves eligibility/current check-in metadata and never calls legacy `/checkin` or native confirmation while resolving.
- Confirmation submits only explicit IDs/date/`confirmed: true`, never a fabricated idempotency header. Exact expected IDs/results are required. Success needs a valid timestamp; missing, malformed, unknown, or partial responses remain unconfirmed. There is no optimistic count, automatic retry, or offline queue.
- The adapter requires exact per-ticket `code`/`state` pairs from backend revision `26d5a1eddfb64960b29abd58412da5965b50bb45`: success/success, duplicate/warning, and not_found, unconfirmed, wrong_date, canceled paired with error. Missing (including older servers), unknown, non-string, or mismatched codes reject the response as unverified; no success is published, even when another result in the same batch was valid. Human message text and attendee-field presence never classify outcomes. Unconfirmed/canceled have explicit do-not-admit labels. The response's `attendee` remains a display string; displayed identity stays tied to the selected stable ticket ID.

## Session and transport boundaries

An ephemeral URLSession has no shared credential storage, cookies, or cache. Redirects are rejected. Only an explicitly supplied HTTPS origin without user info, query, fragment, or non-root path is accepted; normal platform TLS certificate validation is preserved. Errors exposed to the UI are sanitized and never include request bodies/tokens. Response data is schema-validated and capped at 1 MiB after receipt; transport timeouts are bounded.

The Keychain store uses a generic-password record, `WhenUnlockedThisDeviceOnly`, no synchronization/access group, and a service chosen for the approved origin. It stores only opaque token, expiry and origin. The exact device-protection policy remains subject to staging/security review. No real Keychain item is written in automated tests: the Security client is injected.

401/403 and known expiry clear local credentials/capabilities and attendee state. Logout clears local storage before waiting for remote revocation. Failure to confirm remote logout is reported distinctly; failure to erase Keychain data is also surfaced. Signing out while a request is pending invalidates that operation, so a late login/read response cannot restore access. A login already committed on the server but interrupted before receipt may still need authorized server revocation; the client does not claim otherwise. Keychain persistence failure attempts best-effort revocation of the newly issued token, then rejects sign-in.

## Verification and gates

Tests use a synthetic 43-character fixture token and `https://staff.example.test` behind a mocked transport; **no requests are sent to that host**. No actual token issuance, credentials, camera grant, provider grant, or production attendance is exercised. Tests cover disabled/invalid configuration, session bootstrap/restore, expiry, 401/403, scope/day denial, secure-storage policy/errors, redirect/response-origin rejection, bounded search, read-only QR resolution, mixed results, malformed/partial replies, offline behavior, logout failures and late-response races.

Before enabling real integration: approve the staging origin and synthetic staff/event fixtures, complete migration/backend review, approve Keychain policy, validate device TLS and auth/revocation/logout, verify camera and VoiceOver behavior, obtain the target Apple team/signing/App Store Connect approval, and explicitly authorize distribution. The original head `049f2baf34358d6b40757496a1fd59f7ff9c9c62` completed remote CI successfully; later adapter commits have their own check status.
