# Android event and wallet preview

This increment is stacked on the Android staff foundation (PR #145). It owns only
`android/` files. The launcher now opens a configurable event catalogue, followed
by an event overview, programme and attendee pass wallet. Staff operations remain
a separate workspace using the established typed native staff client.

## Boundaries

All programme, attendee and entitlement data in `assets/experience.json` is
explicitly synthetic (`demo_only: true`). Dates and timezone are validated, event
IDs scope both programme and wallet, and saved sessions are local bookmarks, not
seat reservations. Programme dates are illustrative, not an announced schedule.
Bookmarks and filters survive navigation/rotation but are not an account sync or
a durable cross-device store.

Wallet admission is per day. Meal and party redemption use separate enums and
records; no admission operation changes either. Passes are read-only, include
“not valid for entry” labels, and encode a `DEMO-ONLY:WALLET:…:NOT-VALID-FOR-ENTRY`
QR payload which the staff mock rejects. The wallet fixtures are intentionally
independent of staff mock attendance, not a synchronized account.

There is no attendee login, checkout, booking, payment or redemption mutation.
No INTERNET permission, credentials, native transport gate, signing configuration,
production attendance or distribution policy is changed. The existing production
transport gate remains compiled false; only an in-process synthetic transport is
injected into the staff workflow.

## Staff UX

Scan, Lookup and History separate the desk tasks. The review/scan/search action
stays at the bottom, with 48dp+ touch targets. Search accepts name, email or order
code per the established native contract. Selected identities remain across tabs;
leaving an unsubmitted or uncertain selection requires explicit discard. Review
still captures an immutable batch and only its explicit confirmation can submit.

History contains at most 100 in-memory session activities, filtered by event/day.
It distinguishes lookup, read-only preview, confirmed admission, existing
admission, rejection and unverified response. It is **not a server audit log**.
It stores no QR secret or lookup query and clears on logout or session expiry.
Timeout-after-commit remains unverified until the explicit retry gets an outcome;
a duplicate retry is reported as already admitted, never a new success.

## Visual system

Operations use warm canvas `#F6F5EF`, ink `#243024`, forest `#334B28`, 12dp cards,
16sp body and 48–56dp primary controls. Attendee chrome is separate: warm off-white `#F8F5F2`, aubergine `#332631` and plum accent `#642F47`,
white cards, restrained dividers and artwork-led event identity. The 56dp header,
square 16dp-radius art, 46/50sp title with native serif italic accents, compact metadata and one ticket action follow
the design owner's fresh public Luma reference review. No Luma assets or branding
are used. DQOR art bundles the original generated `deccan-cover.png` from design PR #175
(`c0847da`) unchanged as Android resource `deccan_cover.png`;
the second event uses an original Compose geometric motif. Cropped art carries into
the pass above its white credential area. Poster typography is decorative, while
all real labels and actions scale with the system font setting.
Large text uses scrollable section tabs and stacked card actions.
Results carry a symbol and text, never only color. No shared web/iOS theme file
is edited. Camera scanning stops on background, navigation and review.

## API needs to coordinate through the parent

The existing backend staff session/lookup/resolve/confirm contract is unchanged.
These local presentation models are **not proposed wire DTOs**. Before replacing
fixtures, coordinate and approve:

- Published event/programme read endpoints: event scope, stable session IDs,
  timezone, publication/version semantics, cancellation and cache freshness.
- Attendee authentication and wallet authorization distinct from staff session
  capabilities. Ownership must be enforced by the server, not event selection.
- Pass identity and per-day admission reads, with a deliberate protected QR
  credential lifecycle. Do not expose a real claim secret through sample QR code.
- Separate meal/party entitlement and redemption contracts: eligibility, status,
  date, capacity/revocation rules and explicit idempotent redemption outcomes.
  Do not reuse admission confirmation to redeem benefits.
- If durable staff history is required, a server audit endpoint with scope,
  retention, pagination and authority semantics. Local history cannot prove
  attendance or replace audit records.

The feed owner has proposed PR #171 (`675f4f1`) at
`GET /api/public/v1/dqor/programme`, with checked-in JSON Schema and synthetic
example. Android has no blocking shape objection. A future adapter must handle
string IDs, nullable timestamps/local dates/rooms/speaker fields, explicit timezone,
ETag/304, authoritative empty arrays and `programme_unavailable` on 503. Track is
omitted from that public contract; the demo's local track categories must not be
assumed to exist on the wire. This increment does not consume that undeployed API
or claim that the local fixture parser implements its schema.

No backend writes are part of this increment. Live/staging validation, attendee
identity, real QR security and physical-camera testing remain release gates.

## Review evidence

JVM and Compose tests cover event/date scoping, malformed fixtures, separate
admission/redemption states, unsafe wallet QR rejection, history semantics and
retention, programme search/recovery/bookmarks, wallet empty state, large text,
manual lookup, preview/review/cancel/confirm, session expiry, stale eligibility and
ambiguous-response retry. Existing Keystore tests remain part of device checks.

`review/screenshots/` contains real Compose renders captured on the existing
Pixel 3a API 32 ARM emulator in a synthetic test activity. The launcher retains
FLAG_SECURE; test captures do not weaken its protection. These images are review
fixtures, not screenshots of a live event/account or a published app. Instrumentation
screenshot helpers store only synthetic content inside the debug app's private
files. Device tests and screenshot inspection run locally; hosted CI runs build,
JVM tests and lint.


The subsequent rendered attendee handoff (`docs/theme-studio/attendee/event-mobile.png`
and `pass-mobile.png` in the design owner's checkout) was inspected before aligning
the final palette and display hierarchy. Android bundles the supplied original generated cover and retains the configured
event identity. The imaginary courtyard artwork is not a venue photograph.
Pass codes remain clearly invalid synthetic fixtures because no approved attendee
credential contract is connected; QR pixels stay on white with an untouched quiet zone.
