# DQOR premium attendee pass · 3 October 2026

This pass refines the selected warm/plum, artwork-led direction across the existing Rails web app and native previews. Web actions continue to use the existing registration, bookmark, account and ticket flows. Native attendee data and passes remain explicitly synthetic; this change does not activate live native registration, payment or wallet access.

## Visual and interaction changes

- Web: original Deccan cover in a lighter split hero, readable event dates and primary actions, mobile schedule navigation, programme timeline, visible save progress, account saved-schedule empty state, accessible audience-question input, clearer ticket identity and a cohesive free-event attendee layout.
- iOS: artwork-led welcome, scalable staff shortcut, local All/Saved schedule, recoverable saved-empty state, 48pt controls and brief press/save transitions. Welcome metadata is outside the composite card so it remains readable at larger text sizes.
- Android: restrained reveal/press/expansion motion, day/result/save counts, clear-search recovery, saved-card feedback, original native arch/sunset empty-state illustration and header actions that stack at 200% text. Native Back first collapses an expanded session.
- Web motion uses 140/220/480ms tokens, focus and submit feedback. CSS reduced-motion settings and the native system settings suppress decorative transitions. Native agenda saves are local preview state, not account persistence or reservations.
- Operational organizer/scanner surfaces retain their forest status colors and task-first layouts. Ticket QR, role gates, scanner confirmation and retry behavior are unchanged.

## Artwork and reference

The cover is the existing original DQOR Deccan artwork committed with `docs/theme-studio/ATTENDEE_DIRECTION.md` and `public/theme-studio/attendee/deccan-cover.png`. The new web assets are optimized derivatives: 1254 × 1254, WebP 271,926 bytes and JPEG fallback 611,440 bytes. Android empty-state art is original Compose vector drawing. Luma's public home and event page were inspected for spacing and interaction quality; no Luma artwork was copied.

The coordinator owned a separate gstack Chromium session, with dedicated public-reference and localhost tabs, and imported no personal browser session. The localhost Rails test server and database were isolated from production. Screenshots include the real public baseline and synthetic local browser/simulator fixtures; native sample labels remain visible. Captured pixels were inspected before visual acceptance.

## Actual validation

| Area | Result |
| --- | --- |
| Integrated Rails suite | 907 examples, 0 failures, 2 existing pending ClamAV cases; seed 19525 |
| New Rails browser journeys | 320px/reduced-motion layout, loaded artwork, navigation Back, 300ms network latency, repeated save taps, offline navigation and saved-state recovery |
| Web existing journey coverage | Pilot registration/ticket/check-in, question submission/errors, registration windows, account, payment, auth and privacy covered by the full suite |
| Android | Debug and instrumentation builds, lint and 67 JVM tests pass |
| Android device suite | Direct adb instrumentation: 20/20 pass in 113.204s; final attendee replay 7/7 pass in 34.117s |
| iOS | 54 unit tests and Release build pass |
| iOS regression and corrections | Initial 13/14 UI run exposed clipping/contrast; corrected accessibility audit 1/1 passes; final four attendee/staff/saved/large-text-dark journeys pass in 70.370s |
| Independent council | Security, testing, Rails architecture, code quality and performance all approve before commit |
| Patch hygiene | `git diff --check` passes |

Android final device evidence is retained direct-command stdout with session/chunk provenance, not newly generated Gradle XML. The existing iOS audit excludes baseline partial Dynamic Type support on some staff system controls; that exclusion was not expanded. The repaired welcome report has no automated findings. No physical screen-reader or frame-rate benchmark claim is made.

## Remaining release gates

Approved live native identity, attendee registration/payment, authorized wallet and QR lifecycle, native public feed activation, real-device camera/interruptions and spoken VoiceOver/TalkBack checks remain required. Two existing real-engine ClamAV tests are pending unless their integration environment is enabled. CI status is evaluated on the draft PR. Deployment, activation, signing and store submissions remain with the release integrator.

No workflow, production flag, permission, credential, email or production-data change is part of this pass. The optional external mentor lookup was rejected by automatic approval review because its repository-context destination was unspecified; the five independent local council reviews completed instead.

## Evidence

Early Library checkpoint: baseline `libfile_49b4c3db277481919c6e8b48e915e43d`, desktop `libfile_86c76a1be0ec81918995316bfb894570`, mobile `libfile_92a5c3e0f5d08191a0ea41c51bcd037a`. The final Library evidence bundle contains curated before/after screenshots, the Android journey video, actual Rails/iOS logs and Android execution provenance. Its exact IDs are provided with the draft PR handoff.
