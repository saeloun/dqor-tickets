# Android emulator review

Synthetic Compose test activity on the existing Pixel 3a API 32 ARM emulator.
The production launcher keeps `FLAG_SECURE`. No real attendee/account is shown.
Screenshots are unedited captures of the same composables used by the launcher;
the staff test fixture uses the shortened event title “DQOR”.

| Journey | Screenshot |
| --- | --- |
| Event catalogue | [01-events](screenshots/01-events.png) |
| Event overview | [02-overview](screenshots/02-overview.png) |
| Programme and date filters | [03-schedule](screenshots/03-schedule.png) |
| Sample pass wallet | [04-wallet](screenshots/04-wallet.png) |
| Clearly invalid demo QR and admission by day | [05-sample-pass](screenshots/05-sample-pass.png) |
| Admission, meal and party states remain separate | [06-independent-redemptions](screenshots/06-independent-redemptions.png) |
| Different event / empty wallet | [07-empty-wallet](screenshots/07-empty-wallet.png) |
| Programme at 200% text | [08-schedule-large-text](screenshots/08-schedule-large-text.png) |
| Pass at 200% text | [09-pass-large-text](screenshots/09-pass-large-text.png) |
| Manual lookup with selected guest | [10-staff-lookup](screenshots/10-staff-lookup.png) |
| Explicit staff confirmation outcome | [11-staff-confirmed](screenshots/11-staff-confirmed.png) |
| Preview-only local history | [12-staff-history](screenshots/12-staff-history.png) |
| Reachable staff review action at 200% text | [13-staff-large-text](screenshots/13-staff-large-text.png) |
| Event metadata and single ticket action | [14-event-ticket-action](screenshots/14-event-ticket-action.png) |
| Original sample event artwork | [15-original-studio-art](screenshots/15-original-studio-art.png) |

## Local checks

- Debug app and Android test APK assembled successfully with existing JDK 21 and SDK 35.
- 52 JVM tests passed: 23 typed client, 18 desk workflow, 5 event/wallet, 6 legacy mock.
- Lint passed with no errors; inherited target/dependency update warnings remain.
- 14 emulator tests passed: 3 attendee journeys, 1 bundled-cover decoding check, 5 staff journeys, 1 staff large-text
  journey and 4 Android Keystore tests. Exact instrumentation result: `OK (14 tests)`.
- Actual protected launcher cold-started successfully and its UI hierarchy showed
  the event catalogue and Staff workspace. No new SDK/license/security grants.
- Camera decoding on a physical device, TalkBack audio and live integration were
  not tested. “Preview sample QR” exercises the same resolve workflow without
  granting emulator camera permission. No production attendance occurred.

The final attendee direction was revised after the user's Luma feedback: event
artwork now leads, chrome uses warm off-white/aubergine instead of operational
forest, metadata is compact, programme cards form a timeline, and passes inherit
art above a white credential area. No Luma artwork/branding was copied. Forest
remains in the staff workspace. The images cover normal and 200% font-scale
layouts, empty states, separate benefit statuses and confirmation outcomes.
See [EVENT_EXPERIENCE.md](../EVENT_EXPERIENCE.md) for provenance and API needs.

The shared generated cover from design PR #175 is bundled directly in the APK as
`deccan_cover.png`. Event and pass captures verify actual rendering; an emulator
resource decoding assertion guards against the blank/missing image regression.
