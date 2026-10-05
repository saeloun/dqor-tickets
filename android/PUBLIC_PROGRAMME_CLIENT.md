# Official public programme

The default launcher reads only `GET https://deccanqueenonrails.com/api/public/v1/dqor/programme`.
The deployed v1 schema is defined in `docs/PUBLIC_PROGRAMME_API.md` and
`docs/contracts/public_programme_v1.schema.json`. Published sessions and speakers
replace the entire snapshot on a valid 200, including authoritative empty arrays.
This is anonymous public information, not an attendee account or ticket wallet.

## Transport and freshness

`OfficialProgrammeTransport` fixes the HTTPS origin and route, uses platform TLS,
no cookies, authorization, redirects, disk cache or automatic retries, bounds the
body to 1 MiB and connect/read/call timeouts to 10/15/20 seconds. The normal
INTERNET permission is necessary for this read. `NativeIntegrationGate.ENABLED`
remains false; the staff rehearsal has a socket-free mock transport.

`PublishedProgrammeStore` keeps the snapshot and exact ETag only in memory.
Foreground and explicit refresh revalidate; matching 304 retains that snapshot,
while orphan/mismatched 304 gets one unconditional read. Invalid schemas/origins,
503 and connection errors retain any previously verified snapshot with an explicit
stale warning. Cold offline start never invents a programme. Background cancels
in-flight reading and marks retained content unverified until foreground succeeds.
No polling, background jobs or offline writes are added.

Privacy clearing discards snapshot, validator, query, expanded details and local
bookmarks. A generation guard rejects older responses even if their transport
ignores cancellation; an explicit new read can proceed without waiting for that
old response. Clear suppresses automatic reload until the user requests it.
Only opaque published-session IDs persist in the separate `dqor.published.bookmarks`
private preferences. They are pruned against each authoritative valid snapshot.
No programme body, QR, identity, ticket, token or account credential is stored there.

## Programme journey

The live overview uses feed event title, venue, October dates and Asia/Kolkata
schedule times. Programme supports day, speaker/title/room search, Saved and
nullable unannounced details. Saved means a local bookmark, not a reservation.
Actual Android Back collapses the most recently expanded visible or offscreen
session before returning to overview. Filtering, unsaving, withdrawal and privacy
clear remove hidden expanded state. Large text stacks card controls; motion uses
the existing system reduced-animation setting and original DQOR artwork.

**Demo preview** is optional, clearly labeled synthetic, and holds the existing
sample events/passes and scanner rehearsal. No sample wallet appears in the live
programme. **Your tickets** opens the verified official `/tickets/mine` URL in the
system browser; the existing website may redirect to its ticket lookup/magic-link
flow. The app never submits an email, copies browser cookies, or authenticates a
private native wallet.

A native attendee wallet still needs a separately approved authenticated read
contract: attendee identity/session lifecycle, server-enforced ticket ownership,
authorised event/pass fields, admission status and protected QR credential
expiry/revocation rules. Meals and parties would need independent entitlement and
redemption contracts; the native staff endpoint authorises entrance attendance only.

## Verification boundaries

`PublishedLauncherSmokeTest` is explicitly opted in with `-e livePublic true`.
It launches the actual protected MainActivity, actual model and HTTP transport,
then checks public programme navigation, background/resume and manual refresh.
`OfficialProgrammeSmokeTest` independently checks the built transport's 200/304
and renders the real returned feed in a synthetic Compose screenshot activity.
Those pixels preserve launcher FLAG_SECURE and are not screenshots of a private
account. Network counts are observations, not hardcoded expectations.

Synthetic JVM/device tests cover cache replacement, ETag, delayed reads, clearing,
old-response rejection, cold offline state, bookmarks, OS Back, filters, repeated
taps, 200% text and reduced motion. Camera rehearsal uses the emulator rear camera
and real permission UI, with denial/retry and lifecycle pause/resume. The camera
permission journey requires a fresh synthetic test-app install: repeated ADB revokes
on API32 retain USER_SET and change the denial to a permanent-denial button.
The fixture reset never grants permission; actual user-facing denial/allow clicks
and visible-node assertions remain required. Synthetic
QR guard and staff workflow tests cover read-only preview, explicit confirmation,
duplicates, stale/ineligible outcomes, uncertainty, lookup, expiry and logout.
No emulator result claims physical QR focus/lighting, TalkBack audio, phone signing,
store distribution or enabled staff integration. These remain release gates.
