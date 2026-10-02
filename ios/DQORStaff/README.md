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

Demo launch arguments: `--offline` makes lookup/scanning/submission fail; `--fail-checkin` permits search but rejects submission; `--finance` demonstrates a role without attendance capabilities. These flags only select synthetic fixtures. There is no production URL or network adapter to accidentally enable.

## Staff flow

Enter demo → choose event/day → scan tickets continuously or search by name/email/ticket ID → select multiple attendees → review the explicit event, day, and names → confirm → inspect per-attendee results. Cancel preserves the batch; clear/back discard unsubmitted selections. Leaving a nonempty batch asks for confirmation. Search supports keyboard submission; native controls expose VoiceOver labels and semantic status text. Layout uses Dynamic Type and system colors.

Synthetic QR payloads: `dqor-demo:demo-001`, `dqor-demo:demo-002`, `dqor-demo:demo-003`. The third fixture is ineligible for Day 1. Repeating a successful check-in reports “Already checked in”; another day has independent attendance. Unknown codes produce an actionable lookup error. Repeated camera frames are throttled and selected attendees are deduplicated. The batch limit is 50, aligned with the proposed Rails contract. Each event/day carries a configurable lower limit and a semantic presentation theme (indigo, forest, ember). The catalog includes three synthetic event fixtures; production event discovery and richer branded experiences remain future integration work.

Camera permission is requested only when the user opens scanning. `NSCameraUsageDescription` is generated into the app Info.plist. Capture stops on dismissal/background. Denied/restricted/no-camera states provide attendee-search fallback. Simulator tests do not grant camera permission, create credentials, or change live attendance. Physical camera focus/orientation, interrupted capture, and real QR performance still need device validation.

## Rails integration seam — pending verified contract

`StaffAPI` is injectable and asynchronous. It separates sign-in/session, authorized event days, attendee search, opaque QR resolution, and confirmed batch submission. `DemoStaffAPI` is an actor with synthetic fixtures. `StaffStore` owns selection, request lifecycle, errors, and confirmation; camera input goes through a separately testable `ScanGate`.

The proposed `docs/STAFF_CHECKIN_API.md` from the separate backend checkout was reviewed on 2026-10-02. It specifies staff-cookie/CSRF authentication, `GET /checkin.json`, `POST /checkin`, and `POST /checkin/batch`, a 50-ticket limit, 20 visible search results, returned-date authority, and per-result success/warning/error outcomes. Native JSON sign-in is explicitly unimplemented. Existing backend roles are admin/desk; the expanded mock role matrix below is not the backend policy.

**Blocking QR contract mismatch:** `POST /checkin` with a scanned secret mutates attendance immediately. This app's `resolveQR` deliberately does not check in; it builds a batch for later confirmation. Do not map that method to the mutating endpoint. A security-approved nonmutating QR-resolution endpoint (or an explicitly revised user flow) is needed for real continuous batch scanning.

The local request UUID is an API seam, not a claim that Rails accepts an idempotency header. The proposed server safely retries the same ticket IDs/date by returning duplicates; a live adapter must preserve that behavior and validate all per-ticket outcomes.

Before a live adapter is enabled, the backend owner must supply or verify:

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
