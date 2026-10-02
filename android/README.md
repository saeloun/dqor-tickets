# DQOR Android staff workflow

Native Kotlin / Compose staff app, application ID `in.dqor.staff.demo`.
**In-process mock transport only.** The app collects no real credentials, makes
no live requests and changes no real attendance. Rails and iOS are unchanged.

## Build and tests

Requires JDK 17 (or compatible 21), installed Android platform/build tools 35 and
an existing accepted SDK license. No SDK bootstrap/license acceptance runs.

```sh
cd android
export JAVA_HOME=/path/to/jdk
export ANDROID_HOME=/path/to/android/sdk
./gradlew :app:assembleDebug :app:testDebugUnitTest :app:lintDebug
# Existing emulator/device; synthetic credentials only:
./gradlew :app:connectedDebugAndroidTest
```

Debug APK: `app/build/outputs/apk/debug/app-debug.apk`. No production signing or
store release. Path-scoped `.github/workflows/android.yml` builds, unit-tests,
lints and retains APK/reports for 14 days; existing Rails CI is unchanged.
Device tests run locally, not in hosted CI. Gradle is pinned to 8.14.3.

## Usable preview → review → confirm flow

1. Sign in with the synthetic demo Desk or read-only identity. No password field
   accepts real credentials. Sign-in uses the typed adapter and mock session API.
2. Choose the authorized DQOR event/date. The configurable catalog also shows a
   clearly marked sample event without access; backend v1 is single-event.
3. Scan QR text `demo-101`, `demo-102`, `demo-103` or `demo-105`; `demo-104` is
   ineligible. “Preview sample QR” exercises the same resolve path as the camera.
4. Scanning is **read-only**. Eligible identities are added to a bounded preview
   selection. A preview is never admission. Search adds only explicit tickets;
   names, email and ticket ID distinguish duplicate names.
5. Review the selected names/IDs and date, then tap **Confirm check-in**.
   Only that action calls `/api/staff/checkins/confirm`. Cancel does not submit.
   Read every per-ticket result; a mixed batch is not all-success.
6. Use demo controls to expire the session, invalidate a selected preview, go
   offline, or simulate a timeout after the mock server committed. An uncertain
   response retains the exact reviewed IDs/date for explicit retry; duplicate
   outcomes do not add attendance. Nothing is queued or automatically retried.
7. Sign out revokes the mock session and clears encrypted local storage. Offline
   logout explicitly says server revocation was not confirmed.

Native API responses provide **no attendance totals**. The UI does not invent a
counter. In-memory mock attendance resets on process death; the restarted mock
server rejects the old stored demo token, prompting sign-in. Rotation retains
workflow state and in-flight operations in the ViewModel. Backgrounding stops
the camera; returning revalidates the session. Unsubmitted selection discard is
confirmed. Uncertain results require explicit retry or dismissal without admitting.

## Configuration and integration boundary

`app/src/main/assets/events.json` configures event IDs, titles, subtitle, location,
ISO dates and Android-local `heritage`/`midnight` palettes. No shared theme files
are changed. Server session event/date/capabilities restrict available controls.

`NativeDeskWorkflow` owns the UI state machine. It calls `NativeStaffClient` for
session, lookup, resolve and confirm. `NativeDemoModel` injects
`MockNativeTransport` and `KeystoreCredentialStore`; the `.invalid` mock origin
cannot make network requests because the transport has no socket implementation.
The original `MockCheckInService` is retained only as a legacy test fixture;
its immediate scanner is not connected to the launcher.

Real transport remains blocked by a compiled false gate and absent INTERNET
permission. `NativeConfig` defaults to disabled; only the in-process mock client
is explicitly enabled. Staging needs approved origin/accounts, reviewed gate
changes and real session/TLS verification; see [INTEGRATION.md](INTEGRATION.md).

## Verification and release gates

JVM tests cover the typed adapter and UI state transitions: login/restore/logout,
local/server expiry, read-only roles, scan-without-confirmation, canceled reviews,
explicit snapshot confirmation, date changes, stale eligibility, duplicates and
retry after ambiguous commit. Compose device tests exercise actual sign-in,
preview/cancel/confirm/logout, expiry, stale-preview rejection and retry buttons.
Separate device tests exercise Android Keystore ciphertext, restoration, fresh
nonces, deletion and corruption handling with synthetic credentials.

Status uses a polite accessibility live region. Identity labels include email/ID;
entry and confirmation scroll at large text sizes. Camera permission is requested
on demand, and search works without it. Screenshots/recents capture and backup are
disabled. Physical camera, TalkBack audio, approved staging integration and full
real-device interruption testing remain release gates. No live integration is
claimed from in-process mocks or emulator tests.
