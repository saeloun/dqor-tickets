# Attendee event-first redesign

Review increment stacked on PR #168. Attendee chrome uses warm off-white and aubergine, square original event artwork, editorial system typography, compact date/venue metadata and one prominent sample-pass action. Staff scanning remains a separate operational workflow. Explore sample event is available before staff demo entry; event/schedule/pass navigation also remains available from a selected staff day without discarding the batch.

The design owner's public Luma review informed artwork hierarchy and restrained navigation, not copied assets or branding. Event geometry is drawn locally in SwiftUI. A separately generated original icon is a proposal only and is not installed in the app or a signing configuration. A final icon and attendee visual approval remain release gates.

All event, schedule, attendee and pass content remains explicitly synthetic. Passes have independent admission/meal/party labels with icons; no admission QR, booking, redemption, credentials or live endpoint was added. Backend PR #171 supplies the proposed published programme contract; native consumption awaits merged-contract and deployed-target approval. Staff search/offline/cancel/duplicate behavior is unchanged.

## Verification

- 46 unit tests passed during the full redesign run.
- Full 13-test UI run: 12 passed; existing companion search/back regression failed because default search presentation hid navigation. Explicit navigation-bar search placement corrected it; targeted companion search/cancel/back/confirmation/history test then passed.
- Final event/pass/schedule journey and largest-Dynamic-Type navigation both passed on a fresh iPhone 17 Pro iOS 26.2 simulator. Pixel review confirmed actual dark appearance after adding the standard DEBUG compilation condition and a Debug-only appearance launch argument.
- The DEBUG appearance override is absent from Release. No production enablement flags or credentials were introduced.
- Pixel review removed a truncated artwork headline from the compact pass strip and rejected a first-run simulator notification overlay before final export.
- Palette contrast: light main/canvas 14.21:1, light secondary/canvas 6.25:1, dark main/canvas 15.93:1, dark secondary/card 8.12:1. These are palette checks, not a complete accessibility certification. Existing staff accessibility audit passed; physical-device VoiceOver/camera, iPad and final attendee audit remain release checks.
- Infrastructure interruptions: the original simulator reported a Busy runner and an unexpected runner exit. A dedicated fresh simulator completed both final journeys. A transient Mac execution disconnect recovered. No runtime was removed.

Final screenshot Library identities:
- Event: `libfile_63aa0380ab2481919990c30d825c21fb`
- Schedule: `libfile_a38c03f5441c8191894eaa9d213e0d41`
- Pass: `libfile_fb068c5975108191a6f4ca88d69c054a`

Final UI evidence: `/tmp/dqor-ios-design-approved-pixels.xcresult`, with exported images and log under the workspace `ios-review/attendee-redesign` folder. Earlier complete-unit/UI and corrected companion evidence: `/tmp/dqor-ios-design-2.xcresult` and `/tmp/dqor-ios-design-final.xcresult`.

TestFlight remains blocked by an unconfirmed team/app/bundle, unavailable local signing assets, recipient email, final visual/icon approval and release privacy/export metadata. No signing assets, grants, uploads or invitations were created by this increment. The parent is already handling account/team and recipient questions.
