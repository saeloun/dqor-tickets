# DQOR Staff — native iOS preview

A focused SwiftUI iPhone/iPad staff check-in app. This is a **mock-only, synthetic-data preview**, not a production attendance client. All changes are contained in `ios/DQORStaff`. No Rails or dashboard code is included.

## Run and test

Open `DQORStaff.xcodeproj`, select the shared DQORStaff scheme and an iOS 17+ simulator, then Run. No third-party dependencies, real credentials, or signing team are required for the simulator.

```sh
xcodebuild -project ios/DQORStaff/DQORStaff.xcodeproj -scheme DQORStaff \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.2' \
  -derivedDataPath /tmp/dqor-staff-build CODE_SIGNING_ALLOWED=NO test
```

`python3 ios/DQORStaff/generate_project.py` reproducibly regenerates the checked-in project using Python's standard library. No XcodeGen or runtime replacement is needed.

Demo launch arguments: `--offline` makes lookup/scanning/submission fail; `--fail-checkin` permits search but rejects submission; `--finance` demonstrates a role without attendance capabilities. These flags only select synthetic fixtures. The app still constructs DemoStaffAPI exclusively. A separate disabled NativeStaffAPI adapter is covered by mocked transport tests; no production origin or runtime activation switch is configured.

## Staff flow

Enter demo → choose event/day → scan tickets continuously or search by name/email/ticket ID → select multiple attendees → review the explicit event, day, and names → confirm → inspect per-attendee results. Cancel preserves the batch; clear/back discard unsubmitted selections. Leaving a nonempty batch asks for confirmation. Search supports keyboard submission; native controls expose VoiceOver labels and semantic status text. Layout uses Dynamic Type and system colors.

Synthetic QR payloads: `dqor-demo:demo-001`, `dqor-demo:demo-002`, `dqor-demo:demo-003`. The third fixture is ineligible for Day 1. Repeating a successful check-in reports “Already checked in”; another day has independent attendance. Unknown codes produce an actionable lookup error. Repeated camera frames are throttled and selected attendees are deduplicated. The batch limit is 50, aligned with the proposed Rails contract. Each event/day carries a configurable lower limit and a semantic presentation theme (indigo, forest, ember). The catalog includes three synthetic event fixtures; production event discovery and richer branded experiences remain future integration work.

Camera permission is requested only when the user opens scanning. `NSCameraUsageDescription` is generated into the app Info.plist. Capture stops on dismissal/background. Denied/restricted/no-camera states provide attendee-search fallback. Simulator tests do not grant camera permission, create credentials, or change live attendance. Physical camera focus/orientation, interrupted capture, and real QR performance still need device validation.

## Rails integration seam — pending verified contract

`StaffAPI` is injectable and asynchronous. It separates sign-in/session, authorized event days, bounded attendee search, opaque QR resolution, and confirmed batch submission. NativeStaffAPI implements the proposed v1 wire contract behind a disabled configuration, with an ephemeral transport and injectable Keychain storage. `DemoStaffAPI` is an actor with synthetic fixtures. `StaffStore` owns selection, request lifecycle, errors, and confirmation; camera input goes through a separately testable `ScanGate`.

The backend owner's current `docs/NATIVE_STAFF_API.md` was reviewed on 2026-10-02. It proposes disabled-by-default, bearer-only native sessions and separate read-only QR resolution, search, and explicit confirmation endpoints. Tokens expire after 8 hours without refresh; current-session logout revokes the token. The API is scoped to the single `dqor-2026` event with server-authorized dates and admin/desk accounts. It is not enabled or exercised in production.

`POST /api/staff/checkins/resolve` now resolves a QR without attendance/audit mutation, addressing the original batch-preview mismatch. Never use legacy `POST /checkin` for preview because it mutates attendance immediately. The app remains demo-only; the disabled native adapter and token-only Keychain implementation are present but never instantiated by the app entry point. Before enabling integration, verify the authorized staging origin/fixtures, Keychain policy, session expiry/revocation/logout, canonical event/date mapping, secure transport, per-ticket outcome classification, and physical-device behavior. See [NATIVE_CONTRACT_REQUIREMENTS.md](NATIVE_CONTRACT_REQUIREMENTS.md) for exact acceptance requirements and the received contract snapshot.

The local request UUID is an API seam, not a claim that Rails accepts an idempotency header. The proposed server safely retries the same ticket IDs/date by returning duplicates. The integration team must supply or verify:

- Authentication/session creation, refresh, revocation, and secure token-storage requirements.
- Authorized event/day IDs and timezone/eligibility semantics.
- Search pagination, minimal attendee fields, and opaque QR resolution format.
- Server-authoritative capabilities, check-in eligibility, duplicate/conflict outcomes, and audit rules.
- Batch request/response schema and idempotency behavior, including uncertain response recovery.
- Authorized staging host and synthetic test credentials; no production credentials in source.

The native session carries capability values; the mock role matrix includes owner/admin/organizer/team lead/volunteer with attendance capabilities and finance/AV without them. This is a **fixture policy only**, not an assertion about production permissions. The live server must enforce authorization for every action.

Unchanged failed batches retain their request UUID for retry. Editing a batch creates a new request ID. Incomplete responses and transport failures never become success. No offline queue exists. After an uncertain live response, reconcile server attendance before retrying according to the verified backend contract. Ticket payloads are neither logged nor persisted. Attendee/session state is cleared on sign-out, and event context changes clear the batch.

## Release gates

Local inspection on 2026-10-02 found Xcode 27.0 (27A266a), iOS 26.1/26.2/27.0 simulators, and **zero valid local code-signing identities**. `DEVELOPMENT_TEAM` is unset; `org.dqor.staff` is a provisional local bundle identifier, not a registered App ID. Apple team membership and App Store Connect permissions have not been verified.

Before device/TestFlight distribution: integrate and test the verified Rails contract; obtain the approved Apple team/account, bundle ID, signing assets and App Store Connect target; approve branding/app icon and privacy disclosures; perform physical-camera and accessibility validation; then obtain exact distribution approval. No certificates, profiles, App IDs, account grants, agreements, or uploads were created.

## Verification checkpoint

On 2026-10-02, the iPhone 17 Pro / iOS 26.2 simulator suite passed **13 unit tests and 5 UI tests** (18 total), covering mixed/duplicate/day eligibility results, repeated/invalid QR input, cooldown/length limits, cancellation, offline and failed submissions, incomplete server responses, stable retry IDs, stable attendee identity, event configuration limits, capability denial, sign-out cleanup, empty search, review cancellation/confirmation, and back/discard behavior. XCTest screenshots captured the welcome, event catalog, lookup, review, and result screens. Small subsequent UI text/color edits were compiler-validated. VoiceOver behavior, largest accessibility sizes, physical camera capture, and production authentication require additional validation before release.

## Accessibility follow-up

The follow-up suite passes **13 unit tests and 9 UI tests** (22 total), including read-only accessibility audits, largest accessibility text size, keyboard search, simulator camera fallback, and duplicate-name confirmation. See [ACCESSIBILITY_REVIEW.md](ACCESSIBILITY_REVIEW.md) for findings and limits, and [NATIVE_CONTRACT_REQUIREMENTS.md](NATIVE_CONTRACT_REQUIREMENTS.md) for the precise backend handoff. `--duplicate-names` adds a synthetic second Alex Morgan to validate identity disambiguation. The app remains mock-only.

## Disabled adapter checkpoint

[Native adapter details](NATIVE_ADAPTER.md) describe the implemented HTTP/DTO and Keychain boundaries. The native unit suite now passes **40 tests**; the full regression run also passed all **9 UI tests** before the final native-only lifecycle tightening, followed by the 40-unit rerun. No live server was called and the Keychain tests use an injected client. The original requested head `049f2baf34358d6b40757496a1fd59f7ff9c9c62` completed remote CI successfully.

## Pinned outcome-code update

Backend contract revision `26d5a1eddfb64960b29abd58412da5965b50bb45` adds per-ticket result codes. The native adapter now requires the exact documented code/state pairs and rejects missing/unknown/mismatched values, including older-server responses, without publishing admission success. Errors direct staff to an event administrator for verification. **43 focused unit tests pass**, including all six valid codes, all mismatched combinations, malformed/missing codes, and a mixed-batch unverified-result regression. Demo launch and native-disabled configuration remain unchanged.
