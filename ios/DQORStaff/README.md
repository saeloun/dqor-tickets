# DQOR iOS — public programme and scanner rehearsal

The default app connects anonymously to the deployed official DQOR public programme. It presents real event dates, venue and published sessions, local saved-session preferences, search/day filters, details, retry and clearly marked cached/offline states. The original bundled Deccan artwork and warm/plum presentation remain. Public reads do not authenticate, download private tickets or alter attendance.

The separate labeled staff/design demo uses synthetic data only. The disabled native staff adapter remains disconnected. Draft backend PR #189 contains disabled, undeployed account/pass cookie JSON; an approved native authentication handoff and scannable-pass API are absent; the app opens the existing official ticket route in the system browser instead of inventing a private integration or presenting sample passes as live.

## Run and test

Open `DQORStaff.xcodeproj`, select the shared scheme and an available iOS 17+ simulator. No third-party dependencies or signing team is required for simulator tests.

```sh
xcodebuild -project ios/DQORStaff/DQORStaff.xcodeproj -scheme DQORStaff \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -derivedDataPath /tmp/dqor-public-ios-build CODE_SIGNING_ALLOWED=NO test
```

`python3 ios/DQORStaff/generate_project.py` reproducibly regenerates the project with Python's standard library.

Demo launch arguments include `--demo`, with optional `--offline`, `--fail-checkin`, `--finance` and `--duplicate-names`. The first explicitly opens the demo; the others affect synthetic fixtures only. Debug `--public-fixture` provides labeled public-feed fixtures and scenario controls; `--public-offline` makes the initial fixture read fail. Release uses the official public feed. There is no staff API activation flag or credential-entry UI.

Live XCTest reads are explicitly opt-in with `DQOR_RUN_LIVE_PUBLIC_SMOKE=1` in the test runner environment. Without it, those tests skip instead of substituting fixtures or claiming live results. They only GET the approved public programme; they never log in, retrieve private tickets, send email or submit attendance.

See [PUBLIC_PROGRAMME_CLIENT.md](PUBLIC_PROGRAMME_CLIENT.md) for the exact network, cache, bookmark, withdrawal and privacy-clearing behavior.

## Scanner rehearsal

Open the labeled demo, choose an event/day, then scan or search. Resolution adds an attendee to an explicit review batch. Only confirmation produces per-attendee synthetic admission results. The purpose is event entrance attendance; there are no invented meal, party or session redemption operations. Review shows the selected event/day, names and count. Cancel preserves the batch; leaving a nonempty batch asks before discarding. No offline mutation queue or optimistic admission exists. Invalid, duplicate, ineligible, canceled, unconfirmed and uncertain results remain distinct, with server-coded results enforced by the disabled adapter's mocked tests.

Camera capture explicitly selects the rear wide-angle camera. Permission is requested only on opening the scanner. Denial provides Settings, retry and manual lookup. Capture stops on dismissal/background, queued starts are invalidated, foregrounding retries permission, partially failed configuration is cleaned up, and preview rotation uses the platform rotation coordinator. Raw QR payloads are never logged or persisted. Continuous frames go through `ScanGate`, with size/cooldown limits and stable attendee deduplication.

Simulator camera capture is unavailable. Debug `--demo --scanner-rehearsal` exposes clearly labeled synthetic code buttons through the same camera callback to test preview, repeat suppression, explicit confirmation and outcomes. `--scanner-camera-denied` rehearses denial/retry/manual fallback. These buttons are absent from Release and real-device camera builds. No camera permission or system setting is changed by tests.

## Required approvals for private live integration

The public feed needs no new authentication or activation. Staff API production reads currently fail closed while activation is disabled. Any activation requires a separately approved exact host, existing named admin/desk identity, authorized subset of October 8–11, session creation/read/write scope and backend release owner. Do not provision staff accounts, widen roles, copy browser credentials, issue tokens or turn on production flags implicitly.

Before staff login: verify the approved secure credential-entry flow, event/date capabilities, eight-hour expiry, origin-bound token-only Keychain policy, logout/revocation, 401/403 clearing and lost-network recovery against approved synthetic staging fixtures. Before any real confirmation: explicitly authorize the named event/day, test attendees and attendance mutation; verify read-only QR resolution writes nothing, and require explicit review/confirmation. Legacy web `POST /checkin` must never implement native preview.

Before native attendee tickets/wallet: review draft PR #189 (`ae97aa1cd3c54c15cf094947b9a99d4a9fe94e8d`), which supplies a disabled, undeployed cookie-authenticated JSON surface. Obtain an approved native attendee authentication/token handoff separate from staff identity, minimal authenticated ticket/entitlement DTOs, expiry/revocation/logout semantics and secure QR storage/display policy. Existing browser ticket-access links do not supply that native contract. Payments, email and redemption remain separately scoped; this implementation enables none of them.

[NATIVE_CONTRACT_REQUIREMENTS.md](NATIVE_CONTRACT_REQUIREMENTS.md) and [NATIVE_ADAPTER.md](NATIVE_ADAPTER.md) describe the existing disabled adapter and acceptance requirements.

## Device and distribution gates

Read-only inspection on 2026-10-03 found an Apple Development signing identity, but no connected physical iPhone. The app project has no selected development team; its bundle identifier, provisioning profile, device authorization and distribution target have not been approved or verified. No signing assets, profiles, permissions, registrations or uploads were created.

Physical rear-camera capture, real QR focus/rotation/interruption, permission behavior on a real phone, locked-device token storage and actual staff auth/revocation still require an approved device build and test scope. Simulator fixtures cannot prove those behaviors. TestFlight/App Store distribution requires an approved team, App ID, provisioning/distribution target and explicit release authorization; no upload has occurred.

## Evidence

The final 2026-10-03 live-enabled unit run passed all 67 tests with zero skips/failures, including an actual simulator URLSession 200 followed by exact weak-ETag 304. The observed publication had 34 sessions and 14 speakers. The controlled full UI replay passed all 20 tests with zero skips/failures, including real programme content, local saving/cold restart, foreground/privacy clear and labeled scanner rehearsal. After a test-only settled-landscape/whole-screen capture refinement, the focused scanner journey passed its one test; the runtime app binary remained unchanged. Actual screenshot pixels were inspected.

One preceding full UI run retained an automated contrast finding on the existing Demo environment row. The same unchanged audit passed in a focused run and the controlled full replay; the cause remains unconfirmed, and no audit assertion was removed. Earlier recovery failures, an interrupted SpringBoard preflight run and an intermediate screenshot-API compile failure are retained with exact provenance in the accompanying review handoff. These results do not establish physical-camera, live staff-authentication or distribution readiness.
