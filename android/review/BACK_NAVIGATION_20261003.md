# Android Back navigation correction · 3 October 2026

Expanding a programme session, scrolling it out of the lazy list, then pressing OS Back previously left Schedule for Overview. Back now collapses the most recently expanded session while preserving the current schedule and scroll position. A following Back returns to Overview. A public programme preview closes before expanded sessions; pass detail still returns to the wallet before event navigation.

One stable event-level Back handler owns the decision. Expansion and preview state are keyed to the selected event; cards receive expansion state instead of registering item-scoped handlers. Date, search and saved filters clear hidden detail steps. Unsaving an expanded card in Saved-only mode also removes its invisible Back step. Programme filter state stays remembered while the public preview is open.

## Baseline and preserved experiment

The branch starts at current main `6efec600242e79d72b0470c2d2de3a7a0d2cc9bb`. The exact Library handoff `libfile_0a55d131627481919af99fd4d4be8dbc` was materialized in this executor and inspected before reproduction: 10,308 bytes, SHA256 `e0f39bd3ab94c06a9e5bf3930ea3732e1c8239c7c79f9df8ae3aae42cba84cf5`.

That bundle preserves an unmerged experiment which moved card expansion into ScheduleScreen but still registered child Back handlers. Its API35 run failed two Back assertions even after bounded waits. The experiment is not the implementation in this change. Only its long-list test reproduction was initially ported, with production source unchanged.

On a separate owned API35 emulator, baseline reproduces the offscreen-card failure: four focused tests, one failure, plus a screenshot replay with the same failure. Visible-card Back passes there. The old experiment's device-specific no-op symptom was not reproduced and is not attributed to an invented platform cause. New source uses a single root handler, and tests continue injecting actual `KEYCODE_BACK` through Instrumentation; they never call an app dispatcher directly, send a second Back to make an assertion pass, or remove the collapse assertion.

## Actual validation

| Check | Result |
| --- | --- |
| Debug app / instrumentation APK / lint | Pass |
| JVM suite | 67 tests, zero failures |
| Final API35 focused replay | 9 tests pass in 26.168 seconds |
| Final API35 full suite | 24 tests pass in 92.39 seconds |
| Final API32 full suite | 24 tests pass in 103.06 seconds |
| Independent review council | Security, testing, architecture, quality and performance approve |
| Patch hygiene | `git diff --check` passes |

Device journeys cover offscreen expansion in a 23-session fixture; latest-first handling of multiple expansions; preview priority; repeated save/unsave; pass/wallet/overview/catalogue Back; date and Saved-only removal; actual OS Back with system animations disabled; loading with repeated refresh; and synthetic offline/stale/304/error/empty recovery. Existing 200% text, staff confirmation/cancel/retry and Keystore cases pass in both full suites. The JVM suite also verifies role gating.

The first extended API35 full run exposed two existing search-test viewport/focus failures (23 tests, two failures). Untouched main reproduced the standalone public-search assertion failure in its full run (20 tests, one failure), while focused baseline search tests passed. Test helpers now re-scroll and reacquire visible fields with a five-second bound, retaining all visibility and exact search-value assertions. They use no sleeps, skipped assertions or exception suppression. Failed runs remain in the evidence alongside final passing runs.

Installed APK hashes match the final locally built artifacts on both owned emulators. App SHA256: `39dbb072ddd60b5ab6a1aeeb22883678308d4201dd0dd43793a5031695e65be9`; test APK SHA256: `e104965bdea8769a0a5974ab391389472b3d7ec17e700a1bc86ebc79f715ee92`. APKs are local test artifacts and are not distributed with the review evidence.

## Evidence and boundaries

Before/after screenshots are unedited captures from the real composables in the synthetic test activity. Before OS Back shows the unexpected Overview; after OS Back remains in Schedule; returning to the original card shows collapsed Session details. The coordinator inspected those pixels. The evidence bundle includes raw baseline/final logs, original handoff, source patch, APK checksums and a short synthetic emulator replay. Exact Library IDs accompany the draft PR handoff.

Only Android attendee state/navigation, instrumentation tests and this review note change. Web, iOS, CI, production flags, transport, credentials, permissions, auth, payment, scanner/QR and staff mutation semantics remain unchanged. No live feed, wallet or account capability is activated. The launcher keeps FLAG_SECURE. Emulator fixtures do not establish live native integration, physical camera/TalkBack or distribution readiness. Landing remains with the release owner.
