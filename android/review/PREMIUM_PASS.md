# Android premium attendee pass · 3 October 2026

The native preview retains the original Deccan cover, warm canvas and plum accents. It now provides short screen reveals, restrained event/pass press feedback, smooth session expansion and a visible saved-card treatment. The system animator setting disables these effects when reduced motion is selected. No infinite decorative animation or delayed navigation is added.

The schedule shows per-day bookmark counts and result counts, a clear-search action, and a recoverable empty state. The empty wallet and saved-session view use an original native arch-and-sunset drawing. System Back closes an expanded session before leaving the schedule. Header actions stack at large text settings; pass detail respects the space below the header.

Bookmarks remain preview state that survives navigation and rotation. They are not durable account storage or seat reservations. Programme, wallet and attendee content is explicitly synthetic. Admission and benefit redemption remain separate read-only states, and sample QR payloads are invalid for entry.

## Verified

- Debug app and instrumentation APK builds, all 67 JVM tests, and Android lint pass.
- The full emulator instrumentation suite passes 20 tests on the existing Pixel 3a API 32 ARM emulator.
- Attendee tests exercise discovery, overview, schedule search/reset, saving, wallet/detail navigation, independent redemption labels and 200% text.
- The new premium regression suite exercises repeated save/unsave taps, empty saved state, native Back through expanded session/schedule/pass/wallet/catalogue, system animator scale zero, and stalled programme loading with repeated refresh taps.
- Existing programme tests cover offline/stale responses, 304 recovery, service errors, authoritative empty replacement and large text refresh controls.
- Existing staff and Keystore unit/device tests still pass, including preview/cancel/confirm, stale preview rejection, ambiguous commit retry, read-only roles, credential restoration/corruption/deletion and large text.

Baseline and updated pixels were captured from the real composables in the existing synthetic test activity and inspected. The launcher retains FLAG_SECURE. A short emulator recording documents the attendee test journey. Evidence is supplied separately through Library rather than adding generated binary screenshots to this source change.

## Remaining gates

No live attendee authentication, registration, payment, wallet authorization, QR credential lifecycle, redemption mutation or live public feed is connected. Those require approved APIs and activation. The app still has no INTERNET permission and the native production transport gate remains disabled. No credentials, permissions, workflow configuration, production data, store submissions or release settings are changed.

Physical-camera handling, real-device interruptions, TalkBack audio and approved live integration remain release gates. Visual finish and local emulator tests do not establish production readiness for those capabilities.
