# DQOR Android staff demo

Native Kotlin / Jetpack Compose entrance check-in slice. **Demo only:** no live
login, server requests or real attendance. A typed native adapter and encrypted
session store exist behind disabled integration gates; the UI still uses mocks. Application ID `in.dqor.staff.demo`.
Only files under `android/` are owned by this project; Rails and iOS are unchanged.

## Build and verification

Requires ARM-compatible JDK 17, Android SDK platform 35 / build tools 35 and an
existing accepted SDK license. No tooling bootstrap or license acceptance runs.

```sh
cd android
export JAVA_HOME=/path/to/jdk17
export ANDROID_HOME=/path/to/android/sdk
./gradlew :app:assembleDebug :app:testDebugUnitTest :app:lintDebug
```

APK: `app/build/outputs/apk/debug/app-debug.apk`. This is a debug APK, not a
store-ready build. Gradle wrapper is pinned to 8.14.3. Unit tests exercise duplicate
handling, date/event isolation, partial outcomes, malformed batches, confirmation,
role denial, expired sessions, offline failures and lookup eligibility.

## Explore

1. Enter the explicitly labelled demo as Desk, Admin or Viewer.
2. Pick an event and date. Search by name, email or ticket ID.
3. Select visible attendees, review their names/count/date, then confirm.
4. Scan QR text `demo-101`, `demo-102`, `demo-103`; `demo-104` is ineligible.
   Any other QR returns unknown. Camera permission is requested on demand;
   search remains available if denied. The camera pauses with the activity.
5. Scan multiple different QRs continuously. Consecutive identical frames are
   suppressed; restart the scanner to retry the same QR after an uncertain result.
6. Toggle offline to see explicit unconfirmed outcomes. Nothing is queued.

Attendance stays in memory, survives rotation through a ViewModel and is lost on
process death. Event/date/query survive recreation, but unsubmitted selections
clear. An interrupted mutation restores a not-confirmed notice; no request is
automatically replayed. Back stops scanning first, and leaving selected tickets
requires confirmation. Backgrounding stops the scanner.
Only returned counts are displayed; a transport error cannot imply admission.
Names/emails are synthetic. Raw scan values are never logged or persisted.
Screenshots/recents capture and backup are disabled. No INTERNET permission exists.

## Configuration and service boundary

`app/src/main/assets/events.json` is the configurable local event catalog. Each
entry supplies an ID, title, subtitle, location, explicit ISO event dates and theme
(`heritage` or `midnight`). Both themes are Android-local Material 3 palettes.
The second event is clearly identified as a sample. This is not remote universal
event discovery; the existing backend is single-event and supplies no catalog API.

`StaffApp(events, service, demo)` accepts an injectable `CheckInService`; the
launcher uses `MockCheckInService`. The demo role picker is not authorization.
Desk and Admin may check in; Viewer is read-only. Real authorization must come
from a verified staff session and be enforced server-side.

The proposed contract in `docs/STAFF_CHECKIN_API.md` on the separate backend
check-in branch is the integration target. It requires native auth approval
before live integration can be enabled. The separate `nativeapi` adapter implements
the proposed bearer-only `docs/NATIVE_STAFF_API.md` contract behind a compiled
false gate, disabled configuration and absent INTERNET permission. Production
scanning preview must use its read-only resolve endpoint, then require explicit
confirmation before the confirm endpoint. The
current scanner directly performs demo-only mutations and is not a preview flow.
Do not invent bearer tokens or reuse
attendee cookies. Production integration must validate the payload schema,
use the canonical date and every per-ticket result. Native responses contain no
counts; the web DTO is not interchangeable. The adapter must
handle 401/403/404/422/429 and ambiguous transport errors, enforce secure session
storage/expiry/revocation/logout, and preserve explicit IDs + `confirmed: true`
for batches of at most 50. Never infer success from HTTP 200 alone.

## Release gates

Approved staging authentication/UI integration, remote event configuration,
device camera/accessibility/rotation testing, signing and store
review remain required. The separate `.github/workflows/android.yml` runs APK build, unit tests and lint
for Android/workflow changes and publishes the debug APK plus reports for 14 days.
It uses read-only repository permission and the runner's preinstalled SDK, without
a license-acceptance command. Existing Rails CI is unchanged. See
[INTEGRATION.md](INTEGRATION.md) for exact DTO needs and pending staging/UI integration gates.

## Accessibility review

Ticket selection labels include name, email and ticket ID to distinguish duplicate
names. Confirmation lists the same identity fields; results include ticket ID.
Status text uses a polite accessibility live region for scan/response updates.
Entry and confirmation content scroll at large font sizes. Camera permission
denial leaves search available. TalkBack audio and physical-camera testing remain
release gates; semantic labels alone are not proof of a full accessibility audit.

Run Android Keystore tests on an existing emulator/device with
`./gradlew :app:connectedDebugAndroidTest`. These tests only use synthetic
credentials. Staging access is not enabled by running them.
