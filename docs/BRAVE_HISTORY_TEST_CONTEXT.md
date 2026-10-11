# Brave history test context compatibility

The existing desktop and mobile ticket-choice Back regressions fail on the selected Mac's Brave with Cuprite 0.17/Ferrum 0.17.2. Both failures reproduce on unchanged main `62703646410842531e2a892f8a8ea580bec34004`, before a discovery or community change.

An actual CDP trace identifies `Page.frameNavigated` with `type=BackForwardCacheRestore`. The restored default JavaScript context contains the Cuprite helper, the heading `Choose your pass`, the Rails Girls quantity of 1 and the cart total of ₹350. Ferrum instead selects an isolated context where the helper is undefined. Its context-created callback accepts any context for the frame, and the frame's MVar retains the first restored context; the isolated context arrives first on this restore.

`spec/support/cuprite_default_execution_context.rb` replaces Cuprite's inherited context-created subscription with the same frame initialization behavior filtered to contexts explicitly marked `auxData.isDefault=true`. It applies only in test support to `Capybara::Cuprite::Page`. It does not modify application scripts, browser flags, installed gems, production behavior, or ticket assertions. The original native Back journey and all existing quantity, total, order, keyboard and mobile assertions remain intact. BFCache remains enabled in the default driver.

A before/after trace in an owned headless Brave session shows the selection moving from isolated context 3 (`_cuprite` undefined) to default context 2 (`_cuprite` object), while actual BFCache restoration, cart quantity and total remain unchanged. All six existing ticket-choice examples pass after correction. Full-suite results and exact-head CI must also be recorded before integration.

This small test-only adapter depends on Ferrum's installed private frame lifecycle. Reevaluate it when upgrading Cuprite/Ferrum; remove it once upstream selects default execution contexts correctly and the actual Brave Back regressions pass without the adapter. No compatibility claim is made for mobile clients or a signed native release.
