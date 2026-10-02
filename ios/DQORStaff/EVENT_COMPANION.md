# Event companion increment

This stacked draft extends the native iOS preview after PR #144. All edits are under `ios/DQORStaff`.

From a selected event/day, Explore opens Schedule, Sample passes, or Activity history. Returning preserves an unsubmitted batch. Schedule search supports an empty result state. Passes show admission, meal, and party status independently; they cannot redeem anything, encode an admission QR, or export an Apple Wallet pass. Content is explicitly synthetic and scoped to the existing demo event days, never substituted for an unknown live event.

Activity history records successful QR resolution as **not confirmed**, failed scans without their raw payload, and individually verified submission outcomes. Entries are memory-only, capped at 100 for the session, filtered by day, and cleared on sign-out or authorization loss. Lookup returns to the existing server-backed search abstraction without selecting or checking in an attendee. This is local activity, not a server audit log. It does not claim a canceled batch was checked in.

## Backend contracts still needed

Coordinate these with the existing backend owner before any integration:

- Authorized event catalog with stable event/day identifiers, venue and timezone.
- Published schedule version, stable session identifiers, start/end timestamps, rooms, cancellation/change semantics and authorized cache policy.
- Attendee authentication/ownership separate from staff access; ticket/pass entitlement schema, independent admission and meal/party status, server timestamps and revocation rules.
- Redemption commands with resource-specific permissions, duplicate/replay behavior and explicit confirmation requirements. No endpoint is assumed or implemented here.
- Optional authorized, paginated staff audit history with retention and privacy rules. Local history is not a substitute.

The shipped entry point still injects DemoStaffAPI. The native adapter remains disabled by default. No shared backend, web, branding, signing or account settings were changed.

## Design coordination

Operations retain semantic iOS system colors for accessible light/dark contrast and Dynamic Type rather than hard-coded light-only canvas tokens. Existing event accent themes remain intact. Views use native grouped lists, clear labels, icon-plus-text states, and large controls. The proposed shared 8-point spacing rhythm is compatible; any fixed forest/canvas palette needs reviewed dark-mode variants before adoption. Physical-device VoiceOver focus/speech, camera checks, live contract verification, signing and distribution remain release gates.

## Verification

Xcode 27, iPhone 17 Pro simulator, iOS 26.2, signing disabled. All 46 unit tests pass. The nine existing UI regressions pass, including accessibility audit, largest text, scanner fallback, cancel/back/discard, mixed results, duplicate names and offline failures. The two new complete UI journeys cover schedule search/empty state, independent entitlement states, preserved batch, confirmation/history/manual lookup, largest Dynamic Type, empty history and event switching. Screenshot review prompted explicit attendee references in history, a history demo label and redundant entitlement icons.

A test initially tapped the search Close button instead of Back. It now dismisses active search before tapping the identified navigation Back button. No product workaround was necessary.
