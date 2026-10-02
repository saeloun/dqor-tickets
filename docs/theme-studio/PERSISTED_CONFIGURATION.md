# Persisted DQOR branding configuration

This follow-up turns the branding controls into a real Rails workflow at **`/organizer/branding`**. Existing `AdminUser.admin?` sessions can save a draft to PostgreSQL, preview saved state, publish a separate configuration, and restore the previous publication. No account, membership or role is created or granted. Desk staff and attendee accounts cannot read or mutate settings or images.

**Public activation is deliberately OFF.** Publishing here records a configuration; it does not rebrand or deploy the storefront, tickets, invoices, email or public favicon. The UI states this beside the controls, in the preview, and after publication. `EventBrandingSetting::PUBLIC_RENDERING_ENABLED` is false, the public-rendering accessor returns nil, and no public controller consumes these settings. Activation needs its own consistency/rollback review and code change.

## Scope and integration ownership

- Singleton **existing DQOR** only. The `event_key = 'dqor'` database check and unique index enforce this.
- This controller inherits existing staff-session authentication and then explicitly requires the existing admin role. It is **not** a base controller, global admin bypass, or membership policy for future organization-scoped features.
- Independent from the Organization/Event/Membership foundation and `DQOR_PLATFORM_EVENT_ID` adapter. No commerce foreign keys, grants, backfills or tenancy claims.
- Reserved migration **20261002161000** creates only `event_branding_settings` and `event_branding_assets`. Invoice migration 160000 and foundation migration 180000 remain untouched.
- `config/routes.rb` adds one namespaced `organizer/branding` block. Integrate this block alongside other workers' blocks, and regenerate schema after all approved migrations; do not replace another branch's schema wholesale.
- The follow-up builds on PR147's static theme CSS. The browser-only studio stays separately labeled and has no bridge to server settings.

## Supported configuration

The versioned server allowlist accepts theme (`conference`, `marathon`, `campus`), six-digit accent/background colors, heading font preset (`editorial`, `modern`, `humanist`), and a permutation of `about`, `programme`, `visit`. The hero stays first. Foreground color is derived for contrast. No arbitrary CSS, JS, HTML, URLs, or font names are accepted.

Managed logo/cover/favicon IDs are assigned by the upload path, checked against the singleton's owned assets, and never accepted as arbitrary IDs from the editor. Event name, dates, venue, schedule, ticketing and invoice policy are not editable here. The authenticated preview uses DQOR's actual `Conference` dates/venue and links to the existing schedule; it does not present fictional race dates or example programme data as live facts.

## Draft, publication and concurrency

- **Save draft:** commits only the draft and its actor. Unsaved form edits never appear in the saved preview. Validation errors do not partially write images or settings; the enhanced editor retains entered values and selected files after validation, stale-write or connection errors. The no-JavaScript HTML fallback explicitly shows the latest saved draft after an error.
- **Publish saved configuration:** requires explicit confirmation and the current revision. It copies the saved draft to `published`, moves the prior publication to `previous_published`, and records the existing admin actor and UTC timestamp.
- **Restore previous publication:** requires confirmation/current revision, restores the previous published snapshot, and keeps the draft. One previous snapshot is retained; this is not a complete audit-history archive. Restoring swaps the previous/current snapshots, so that action can also be reversed.
- Row locks and optimistic `lock_version` reject a second writer's stale draft/publish/rollback instead of silently losing changes. Two independent database connections are tested.
- The first publication has no previous configuration, so rollback is unavailable until a second publication exists. Public appearance is unchanged regardless because activation is off.

## Private image handling

Images are stored as bounded database bytes rather than Active Storage attachments. This avoids creating default signed/public blob endpoints for branding drafts.

- PNG/JPEG/WebP byte signatures only; maximum input 1 MB. MIME or filename alone is not trusted.
- libvips decodes the image, rejects animation and dimensions above 4096 per side or 12 megapixels, strips metadata and re-encodes WebP. Optimized output is also capped at 1 MB.
- HTML/SVG, malformed raster bytes, remote URLs and oversized images are rejected.
- Only authenticated existing admins can GET `/organizer/branding/assets/:id`. Responses are `private, no-store`, `nosniff`, and `image/webp`; no raw upload filename is served.
- Replaced images are pruned only when unreferenced by the draft, current publication and previous publication. Rollback images are retained. At most nine referenced image slots remain after a successful mutation.
- These private assets are not ready for public rendering. Future activation must implement a published-only asset delivery policy without exposing drafts, and review cache invalidation.

## Running and migration

Use the project's Ruby 4.0.6/Bundler environment, PostgreSQL and existing libvips dependency. Run `bin/rails db:migrate`, then sign in through the existing `/session/new` flow with an authorized admin and visit `/organizer/branding`. Do not create or promote production users as part of rollout. No environment secrets or domain changes are required.

Migration adds tables only and performs no role grants or data backfill. The singleton is initialized with default branding when an authorized admin first opens the editor. Schema rollback would delete saved branding/images: back those up first if rollback is ever required. For application rollback, leave additive tables in place and remove the route/code; public rendering remains unchanged.

## Verification

- Full local suite: **608 examples, 0 failures** on isolated `dqor_branding_task6_test` with real Chromium system tests.
- Focused service/model/request/system coverage: **30 examples**, including authentication, desk/attendee denial, CSRF, validation, upload privacy and decoding, atomic failure, stale writes, concurrent writers, saved preview, publish and rollback.
- RuboCop: **331 files, no offenses**. Brakeman: **0 warnings**.
- Real development-mode Rails browser checks use synthetic data in a separate local database: desktop 1440×1100, phone 390×844, saving and confirmed publication. No horizontal overflow in the page/iframe and no browser console errors.
- No deployment, public activation, shared-database mutation or live-account grant was performed.

Screenshots: [desktop editor](screenshots/persisted-editor-desktop.png), [phone editor](screenshots/persisted-editor-mobile.png), [phone publication state](screenshots/persisted-published-mobile.png).

## Mobile interaction follow-up

Sticky Edit / Saved preview / Save draft actions make the saved preview reachable before the long form. A full-screen native dialog preserves unsaved form values and files; Back to editing, Escape, and browser Back return focus to the opener. Section links scroll inside the preview. Links to the live event/schedule open separately. Without JavaScript, saved-preview links open in a new tab.

Editable six-digit hex fields accompany color pickers. Private-image cards show selected local thumbnails and filenames with Cancel selection; server decoding and validation remain authoritative. The picker is disabled without JavaScript; editable hex fields still submit normally.

Enhanced submissions use the same authenticated, CSRF-protected endpoints with JSON responses. Validation and connection failures leave the form intact. Pending requests disable editing and repeat submissions; publication/rollback are blocked while edits are unsaved. Leaving the editor with unsaved values triggers the browser's standard warning. No automatic retry occurs after an uncertain result.

The separately labeled static prototype now exposes Previous / Next and “1 of 3” feedback. Touch scrolling and arrow keys synchronize the selected card, editor and preview. Its drafts remain browser-only.

Real Chromium checks: 390×844 phone and 1440×1100 desktop, keyboard focus/section navigation, actual emulated touch swipe, all three gallery directions, no horizontal overflow or console errors. System coverage includes Back/Escape, image cancel, validation retention, failed connection, and repeated save/publish (one revision each).

Updated screenshots: [phone editor](screenshots/persisted-editor-mobile-polish.png), [desktop editor](screenshots/persisted-editor-desktop-polish.png), [full saved preview](screenshots/persisted-full-preview-mobile.png), [gallery first](screenshots/studio-mobile-gallery-first.png), [gallery third](screenshots/studio-mobile-gallery-third.png).
