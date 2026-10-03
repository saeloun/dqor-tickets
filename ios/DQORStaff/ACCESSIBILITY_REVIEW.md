# Native accessibility review — 2026-10-02

Scope: synthetic demo on iPhone 17 Pro / iOS 26.2, Xcode 27. No production credentials, attendance, camera permissions, or device settings were granted. The configurable event/day adapter and three semantic themes remain intact.

## Changes from the initial preview

- Attendee selection now exposes name plus the staff-visible email, a separate selected value/trait, and a selection hint. Review, removal, and result rows also retain email so two identical names remain distinguishable. A dedicated synthetic duplicate-name fixture and UI regression cover both lookup and confirmation. No extra identity fields were introduced.
- Primary text and section headings use strong semantic foreground colors. Result text is neutral and has explicit wording/icons rather than depending on green/orange. Forest/ember button tints use darker light-mode colors.
- Search has a persistent label and an accessible name, not only a long placeholder. Multiline content can grow, and removal controls have a minimum 44-point target.
- Scanner content scrolls and its camera region scales with Dynamic Type. Simulator builds show a truthful camera-unavailable fallback without requesting permission.
- Status changes and completed batches announce when VoiceOver is active. Actual spoken output and focus traversal still require hands-on VoiceOver validation.

## Evidence and limits

`testReadOnlyAccessibilityAudit` uses Apple's installed XCTest audit APIs on welcome, event catalog, lookup, and review. It preserves every finding as a text attachment. Contrast, hit regions, sufficient descriptions, clipping, and traits are asserted; Dynamic Type findings are retained in the report and assessed separately with a real largest-category navigation test. The review is not a blanket accessibility compliance claim.

The initial audit found contrast and potential clipping issues. After the UI changes, no contrast/clipping findings remained in the four inspected screens. The audit still flags partial Dynamic Type support in native navigation controls and a review-row element; the largest accessibility category test validates that staff can reach demo entry, event selection, scanner fallback, keyboard search, attendee selection, and confirmation without submitting. Toolbar text has platform-managed scaling limits.

The screenshot set covers welcome, catalog, lookup, selected batch, explicit review, confirmed result, mixed eligibility results, scanner fallback, role restriction, offline lookup, unconfirmed submission, duplicate-name review, and largest-text welcome/scanner/lookup/review. These are simulator screenshots of synthetic data, not designed mockups or proof of live integration.

Remaining validation: hands-on VoiceOver speech/focus and hardware keyboard navigation; physical camera focus/orientation/interruption and real scan throughput; iPad/landscape and dark/high-contrast presentation; native authentication/session expiry and staging server responses. Signing and TestFlight remain separately gated.
