# Native attendee client foundation

The disabled native attendee backend and client foundations are integrated in main `f13697e60364f26dca28ecb9684964b187fc86af` through PR192 and PR196, alongside the public programme and synthetic scanner. The wire contract originated in PR192 head `2839e33961e9c6a9b95ea78c8b477265471e8bca`, `docs/NATIVE_ATTENDEE_PKCE_DRAFT.md` SHA256 `2831d9944e29277eefaca0ee3ac77bbc5378432ccedd61185a773770b56683c6`.

## Runtime boundary

`AttendeeIntegration.ENABLED` is false. The production `AttendeeModel` constructs an unavailable controller. The account page offers the official account and ticket websites through the system browser; it has no enabled native sign-in action. No Intent extra, query parameter or remote response can select a synthetic controller or turn the gate on. Synthetic bridges/screens exist only in unit or instrumentation tests, with an explicit persistent fixture label. This foundation issues no real credential, sends no email, reads no production attendee API, changes no staff transport and performs no admission write.

The existing app ID remains `in.dqor.staff.demo`, minimum API26. Public anonymous programme transport, staff rehearsal transport and attendee bearer transport remain separate. The protected launcher keeps FLAG_SECURE. Original QR/scanner semantics are unchanged.

## Browser return

The public client ID is `dqor-android`. The owner-approved exact callback is `https://deccanqueenonrails.com/native/attendee/android/callback`. A static HTTPS autoVerify VIEW/DEFAULT/BROWSABLE filter restricts the exact host/path. MainActivity uses singleTask so an external browser return reuses the memory-held pending transaction. Initial and subsequent intents share one handler, immediately clearing data from the Activity's current Intent. Android's system ActivityManager/task record is outside application memory; callback values are single-use codes/state rather than reusable bearer credentials.

Only one attempt is allowed. State and verifier use independent cryptographic32-byte randomness, base64url without padding; challenge is S256. State/verifier never enter saved state or preferences. HTTPS origin, authority, exact raw path, fragment absence, exactly one code/state pair, strict code format and constant-time expected state comparison are checked independently of browser cookies. Invalid callbacks preserve the legitimate pending attempt; Cancel/Back invalidates it. Cold launch without the verifier fails closed. Attempts expire after ten minutes. A callback is consumed once before exchange, with no automatic exchange retry.

The client/callback mapping is owner-approved; the production registry and association are still unprovisioned. Claimed-link signing/domain ownership is not proved by manual intent delivery. The owner must provision/validate assetlinks for this existing package and the actual approved signing certificate, then prove physical browser-to-app routing before activation. No assetlinks/signing provisioning or custom production scheme is included here.

## Wire and privacy

The fixed first-party HTTPS adapter accepts only token POST, account/pass/session GET and session DELETE in `/api/native/attendee/v1`. Token exchange has exactly code/code_verifier/client_id/redirect_uri JSON, no Authorization or query. Read/session requests use exactly `Authorization: Bearer na1_<43-url-safe-characters>`. Header construction cannot attach attendee credentials to public, cookie-attendee, staff or browser requests.

CookieJar.NO_COOKIES, no cache, no redirects, no implicit connection retry, ten-second connect/fifteen-second read/twenty-second call limits and a one-MiB decoded response limit apply. Actual async OkHttp calls cancel when their coroutine is canceled. JSON parsing runs off the main dispatcher and rejects duplicate keys, non-JSON syntax, unexpected success/error fields, scope/client/event/type mismatches and over-limit pages. Token/session responses follow the backend's actual shape: token success has no schema_version; session has no account identity or token echo. Account/pass envelopes preserve server checked_at, nullable admission bounds and nullable entry timestamps.

Credentials and snapshots remain memory only, with no refresh or persisted bearer. A generation-bound deadline clears private state even with the account page closed. Android elapsedRealtime includes deep sleep; local clock rollback cannot extend the monotonic thirty-minute cap. Server session checked_at/expires_at can shorten the deadline and must demonstrate at most thirty minutes remaining. Backgrounding hides private snapshots and invalidates old reads, then foregrounding revalidates. Identity change, authentication denial, expiry and failed verification clear private state. Every awaited stage checks generation/expiry before starting another request. Up to two hundred status rows may be held; additional rows use the official website.

Logout clears locally immediately. DELETE204 means explicit server revocation; canonical401 unauthenticated means the credential is already invalid. Offline/timeout logout says revocation could not be confirmed. There is no retry queue. A canceled exchange that eventually returns a token receives one bounded best-effort revoke; an ambiguous exchange/termination has only absolute server expiry as backstop. Old results cannot restore a newer session.

Pass cards report server-observed status/eligibility and recorded entry only. They contain no QR, claim, wallet token, food/party capability, scanner confirmation or fresh admission permission. Actual ticket credentials remain on the official ticket website.

## Verification and remaining gates

Synthetic JVM tests cover the RFC7636 vector, randomness, origin/path/query/state mismatches, callback replay, Cancel/repeated taps, expiry/clock rollback/idle expiry, identity change, revocation, offline/logout and late-response races. A real owned loopback HTTP fixture verifies incoming S256 verifier, single-use code, exact request bytes/header isolation, no cookie/cache reuse, DELETE/replay and redirect rejection. It rewrites canonical requests only inside test code and never calls the canonical private API. Instrumentation checks synthetic sign-in/read-only/empty/expiry/offline logout with large text, real Android JSON behavior, actual warm task reuse and disabled protected launcher behavior. Manually forced cold callback is not domain-association proof.

Backend and client source integration is complete and access remains disabled. Approved activation and runtime callback configuration, signing/domain association and physical-phone browser/TLS/privacy/logout proof remain pending. Production deployment is not established by this audit. Changes to this integrated foundation require five-expert review and coordinator PR/CI handoff; the release integrator alone owns landing.

## Rate-limit recovery

Canonical native HTTP429 carries schema_version1, error.code rate_limited and one exact Retry-After:180 header. The client preserves that header and validates the published value; missing, duplicate, malformed or out-of-contract header/body values fail closed while retaining a conservative180-second local wait. No caller-selected duration or date format can extend the wait. Exchange, read and logout429 clear private state; logout still reports unconfirmed server revocation.

The existing ViewModel-owned controller keeps the cooldown deadline only in memory using elapsedRealtime, including deep sleep. Cancel, ordinary background/resume and account navigation do not bypass it; activity recreation retains the existing ViewModel. Process death loses this local wait along with all private credentials; server rate limits remain authoritative. A small counter runs only during the bounded wait, ends on expiry or ViewModel disposal, and never queues a request or opens a browser automatically. Sign-in is disabled during the wait, a readable remaining time is shown, and official website account/ticket actions remain available. At expiry the user must explicitly start again.
