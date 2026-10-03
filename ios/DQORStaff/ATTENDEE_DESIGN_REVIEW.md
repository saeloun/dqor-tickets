# Attendee event-first redesign

Review increment stacked on PR #168. Attendee chrome uses warm off-white and aubergine, square original event artwork, editorial system typography, compact date/venue metadata and one prominent sample-pass action. Staff scanning remains a separate operational workflow. Explore sample event is available before staff demo entry; event/schedule/pass navigation also remains available from a selected staff day without discarding the batch.

The shared reference is PR #175, commit c0847da820766957c9f63db64c1a7a928461ce8f, documented in docs/theme-studio/ATTENDEE_DIRECTION.md. Its original Deccan cover is bundled unchanged in Resources/deccan-cover.png. The design owner's public Luma review informed artwork hierarchy and restrained navigation; no Luma assets or branding were copied. The pass uses a cropped art strip and a separate white sample credential field. A separately generated original icon remains a proposal only and is not installed in the app or signing configuration.

All event, schedule, attendee and pass content remains explicitly synthetic. The Deccan After Hours preview is isolated from selectable staff API days. Passes have independent admission/meal/party labels with icons; no admission QR, booking, redemption, credentials or live endpoint was added. Backend PR #171 supplies the proposed published programme contract; native consumption awaits merged-contract and deployed-target approval. Staff search/offline/cancel/duplicate behavior is unchanged.

## Verification

- Final shared-art run: 47 unit tests and both attendee UI journeys passed on a fresh iPhone 17 Pro iOS 26.2 simulator, using Xcode 27 and signing disabled.
- The unit suite verifies bundled artwork decodes and the fictional attendee preview cannot become a staff event day. UI coverage includes event/pass/schedule navigation and largest-Dynamic-Type dark navigation.
- Initial shared-art captures showed blank image regions despite resource inclusion. Explicit UIImage loading from the app bundle with the PNG filename fixed loading. Regenerated event and pass pixels were inspected before replacing Library evidence; blank captures are not accepted evidence.
- Earlier redesign regression run: 12 of 13 UI tests passed; the companion search/back test exposed hidden navigation from default search presentation. Explicit navigation-bar search placement corrected it, and the targeted search/cancel/back/confirmation/history test passed afterward. The full 13 were not rerun for this artwork-only followup.
- The DEBUG appearance override is absent from Release. No production enablement flags or credentials were introduced.
- Physical-device VoiceOver/camera, iPad and final attendee accessibility review remain release checks. Simulator pixel inspection is not a complete accessibility certification.
- The original simulator had Busy runner and unexpected exit interruptions. A dedicated fresh simulator completed final verification; no runtime was removed.

Final screenshot Library identities, all version 1:
- Event: `libfile_63aa0380ab2481919990c30d825c21fb`
- Schedule: `libfile_a38c03f5441c8191894eaa9d213e0d41`
- Pass: `libfile_fb068c5975108191a6f4ca88d69c054a`

Final evidence: `/tmp/dqor-ios-shared-art-final.xcresult`, with exported images and log under the workspace `ios-review/attendee-redesign` folder. Review copies are `/tmp/dqor-native-design-library/DQOR-Event-Redesign.png`, `DQOR-Schedule-Redesign.png` and `DQOR-Pass-Redesign.png`. Earlier regression evidence remains in `/tmp/dqor-ios-design-2.xcresult` and `/tmp/dqor-ios-design-final.xcresult`.

TestFlight remains blocked by an unconfirmed team/app/bundle, unavailable local signing assets, recipient email, final visual/icon approval and release privacy/export metadata. No signing assets, grants, uploads or invitations were created by this increment. The parent is already handling account/team and recipient questions.
