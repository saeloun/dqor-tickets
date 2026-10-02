# DQOR theme studio — integration review

Provisional branding, three original event directions, and a browser-only no-code editor. This is an isolated design prototype, not a connected event-management feature. No domain choice is assumed.

## Review locally

From the repository root:

```sh
python3 -m http.server 8766 --directory public
```

Open `http://localhost:8766/theme-studio/index.html`. Rails can also serve the explicit `/theme-studio/index.html` static path when public file serving is enabled. No routes, navigation, authentication, models, migrations, native projects, or Campfire code are changed.

Direct samples:

- `/theme-studio/preview.html?theme=conference` — **The Gathering**: warm paper, editorial type, original architectural artwork.
- `/theme-studio/preview.html?theme=marathon` — **The Movement**: forest/lime, bold sans, original track artwork.
- `/theme-studio/preview.html?theme=campus` — **The Commons**: parchment/copper, literary type, original book artwork; applicable to campus festivals, literature events, and conventions.

All sample dates, programme descriptions, race distances and venues are illustrative. Conference identity/date/venue are seeded from existing DQOR content, but the programme is still illustrative. There is no registration/payment CTA; all links navigate real sections.

## What actually persists

| Control | Behavior | Live application impact |
| --- | --- | --- |
| Name, headline, date/location labels | Preview text, safe text nodes | None |
| Accent/background, font | Namespaced CSS tokens and allowlisted font stacks | None |
| Logo/cover/favicon | Locally decoded PNG/JPEG/WebP, maximum 1 MB each; favicon shown in studio browser chrome | No upload or live favicon update |
| Section arrows | Accessible reordering with retained keyboard focus | None |
| Save browser draft | Versioned localStorage key, separate per theme, assets included | None; never published |
| Restore saved draft | Restores that theme's local draft | None |
| Reset working preview | Restores theme defaults; saved draft remains available | None |
| Full preview | Same-tab navigation, sessionStorage carries working state | None |

Working previews survive same-tab navigation/reload using sessionStorage. Switching themes retains in-progress edits in memory. A saved draft is restored explicitly, not automatically. Browser storage is origin-specific, can be cleared, and is not an account backup. Storage failures are caught; saving reports failure. If sessionStorage is unavailable, the embedded live preview works but the full-page preview falls back to defaults. Drafts do not sync across devices or accounts.

The existing app has **no persisted event-branding settings**. Date/venue are currently constants in `app/models/conference.rb`; identity and artwork are rendered from existing application views/assets. The prototype deliberately does not claim otherwise. Ticket tiers, capacity, schedule and other existing records are outside this change.

## Integration boundary

- `public/theme-studio/themes.js`: version 1 draft schema, presets, strict normalization, allowlisted fonts/sections, safe color validation and contrast selection.
- `preview.js`: renderer that only assigns text nodes, safe raster data URLs and CSS custom properties. `postMessage` is accepted only from the same-origin parent frame.
- Reusable tokens: `--dq-accent`, `--dq-accent-ink`, `--dq-surface`, `--dq-ink`, `--dq-display-font`.
- The standalone CSS lives only on these static prototype pages, so it cannot alter existing Rails screens.
- Future server integration needs authenticated event-scoped settings, server validation, managed asset uploads, content mapping, and a separately reviewed publish path. Client validation is not an authorization boundary.
- Keep this PR draft until integration review. It intentionally makes no production root-route or navigation change.

## Assets and licensing

All default artwork is original CSS geometry/typesetting, added under the repository's MIT license. Fonts are operating-system stacks; there are no external font, tracking, image or library requests. No private Billetto or Methodology code/data was accessed. Existing `public/dqor` images were used only as local QA inputs, not copied into the theme defaults.

## Validation

`node script/theme-studio/check.mjs` (Node 22+) checks invalid/prototype theme keys, rejected CSS/remote/SVG inputs, schema/section validation, draft round-trip, and 4,096 colors with at least 4.5:1 foreground contrast. JavaScript module syntax and `git diff --check` pass.

Chromium/Playwright manual checks:

- Rendered and visually inspected all three themes at 1440×1100 and 390×844; full-page phone captures below.
- Editor at desktop and phone sizes; no page or preview horizontal overflow at 320px.
- Save → change → restore, reset preserving saved draft, and reload with custom assets.
- Logo, cover and favicon decode/display, local saved-asset restore; oversized 4.5 MB cover rejected with an actionable message.
- Font changes and section reordering update the preview; arrows preserve focus and announce changes.
- Skip link receives visible keyboard focus; labeled fields, semantic headings/nav, real anchor targets, reduced-motion support, adaptive text contrast.
- No browser console errors in the exercised flows. No automated screen-reader audit was performed.

Local Rails suite could not start: host default Ruby 2.6.10 lacks locked Bundler 4.0.10 (project requires Ruby 4.0.6). Repository PR CI is the Rails verification source; inspect the exact PR-head check results.

## Screenshots

| Direction | Desktop | Phone |
| --- | --- | --- |
| Studio | [Desktop](screenshots/studio-desktop.png) | [Phone](screenshots/studio-mobile.png) |
| The Gathering | [Desktop](screenshots/conference-desktop.png) | [Phone](screenshots/conference-mobile.png) |
| The Movement | [Desktop](screenshots/marathon-desktop.png) | [Phone](screenshots/marathon-mobile.png) |
| The Commons | [Desktop](screenshots/campus-desktop.png) | [Phone](screenshots/campus-mobile.png) |
