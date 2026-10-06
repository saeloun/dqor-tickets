# Launch foundation and operating guide

This guide describes source baseline `3d10fd8a1e58d0fce34d9fd5c16ce218b2858ea4` and the event-website implementation candidate included in this change. It is not a live deployment receipt. **ConfOSS is a working name**; this work changes neither repository visibility nor its MIT license.

## Capability status

“Implemented” means present in the baseline source. “Gated” means an additional default-off switch prevents use. “Preview” means changes do not update the live DQOR site. “Candidate” means implementation is present in this change but review, merge, deployment, and activation remain separate milestones. “Planned” has no delivered workflow in this slice.

| Capability | Status and boundary |
| --- | --- |
| Existing DQOR root, paid checkout, documents, attendee accounts, web scanner | Implemented single-conference behavior. Provider configuration, release evidence, and authorized staff access remain operational prerequisites. |
| Organization event drafts/public pages | Implemented, gated by `ORGANIZER_PLATFORM_ENABLED=true`. Fresh organization membership scopes access; public drafts return 404. |
| Free organization creation, one free category, registration, retrieval, attendee CSV/check-in | Implemented, gated by both `ORGANIZER_PLATFORM_ENABLED` and `FREE_EVENT_PILOT_ENABLED`. Email-verified attendee identity required. |
| Registration questions | Implemented; also needs `FREE_EVENT_QUESTIONS_ENABLED`. Published form versions and answer snapshots are category/event-owned. |
| Registration windows | Implemented; also needs `FREE_REGISTRATION_WINDOWS_ENABLED`. Saved draft and published wall-time window remain separate. |
| `/theme-studio/index.html` | Static browser-only preview. Browser storage is not server publication or an account backup. |
| `/organizer/branding` | Implemented private DQOR singleton draft/preview/publish/rollback for existing staff admins. Public rendering is disabled by code, independently of organizer flags. |
| Event-owned website editor and public snapshot | Candidate present in this change; absent from the baseline deployment. Existing organizer flag remains off; no automatic DQOR enrollment or new authorization is included. |
| Organizer commercial operations | Implemented, gated by `ORGANIZER_OPERATIONS_ENABLED` plus organizer access. Drafting records is separate from sending messages or granting access. |
| Owned paid commerce | Staged source behind `STAGED_COMMERCE_ENABLED`; not validated or activated as a paid multimerchant launch here. |
| Hiring/resume delivery | Gated by `ORGANIZER_PLATFORM_ENABLED` and `HIRING_ENABLED`; resume downloads have a separate `HIRING_RESUME_DOWNLOADS_ENABLED` gate and scanner prerequisites. See [hiring](HIRING.md) and [ClamAV](HIRING_CLAMAV.md). Not activated by this website slice. |
| Announcement delivery | Implemented explicit approval/consent ledger; sending defaults off via `ANNOUNCEMENT_DELIVERY_ENABLED`. See [delivery contract](ANNOUNCEMENT_DELIVERY.md). |
| Generic event-native catalog, merchant onboarding, custom domains, organization invitations | Planned/outside this slice. No new route, entitlement, provisioning, or delivery is promised. |

The guide does not instruct production flag activation. For an approved isolated demo, review the relevant gates and use synthetic identities/data. An environment variable equal to `true` enables its switch; missing values leave it off. Free-event questions/windows configured while their infrastructure is disabled fail closed for new registration rather than silently bypassing required questions or closing times.

## Local quickstart

Follow [README setup](../README.md#stack-and-local-setup) with PostgreSQL 16, Ruby 4.0.6, Chromium/Chrome, and libvips. Choose dedicated local development/test databases. DQOR sample seeds do not create organization memberships or activate platform routes.

The Rails application uses importmap/Propshaft; its production asset command is:

```sh
RAILS_ENV=production SECRET_KEY_BASE_DUMMY=1 bin/rails assets:precompile
```

This builds assets only. It does not validate production credentials, migrate a production database, deploy, or activate any feature. The static theme checker separately requires Node 22+:

```sh
node script/theme-studio/check.mjs
```

For browser-only theme exploration, serve `public` locally:

```sh
python3 -m http.server 8766 --directory public
```

Open `http://localhost:8766/theme-studio/index.html`. Use synthetic labels/images: prototype drafts live in browser storage and do not change a server event.

## Current organizer and free-event workflow

1. With an approved local platform/pilot demo, sign in using the attendee email-verification link and open `/free`. Google-only sign-in and staff AdminUser sessions do not authorize pilot mutations.
2. Explicitly create a new organization and become its owner, or use an organization to which your existing attendee account already has an approved membership. No email-domain, employee, or global staff membership is inferred.
3. Open `/organizer/organizations/:organization_id/events`. Owners/admins/editors may create/edit/publish event metadata; viewers may read. Set title, slug, UTC start/end inputs, and a real IANA display timezone. Publication requires ordered dates. Current metadata edits to an already published event take effect directly; they are not website snapshot drafts.
4. Owners/admins publish one named, capacity-limited free ticket category from the event's inventory workflow. Editors/viewers cannot access attendee PII or manage free inventory. Owned tickets remain hidden/inactive to legacy DQOR checkout and never enter global Razorpay/document flows.
5. If approved for the demo, configure Registration questions and Registration window from that category. Save/review the private draft, then explicitly publish the saved version. Questions support bounded text, integers, choices, and yes/no; they are not resume/file-upload or sensitive-data collection forms. Window inputs use the event timezone; ambiguous/nonexistent DST wall times are rejected.
6. Attendees open `/events/:organization_slug/:event_slug`, verify email, and register explicitly. There is one registration per user/event; retries return the original ticket. Retrieval at `/free/tickets` remains account-bound. The pilot does not send a PDF, wallet pass, invoice, or registration email.
7. Owners/admins use the event's attendees workflow for the limited CSV and event-window check-in. Fresh membership is checked on requests; revoked members lose access. There is no pilot cancellation/transfer/waitlist or tenant-native QR workflow in this slice.

Detailed contracts: [organization foundation](ORGANIZER_FOUNDATION.md), [free pilot](FREE_EVENT_PILOT.md), [questions](FREE_EVENT_QUESTIONS.md), [windows](FREE_REGISTRATION_WINDOWS.md). Their historical validation counts are not current combined-head test receipts.

## Existing DQOR branding previews

The persisted editor at `/organizer/branding` uses the existing **staff admin** identity and the singleton `event_key = dqor`. Desk staff and attendee/organization membership alone cannot use it. Save draft, preview saved state, explicitly publish, or restore the previous publication with the current revision. Publishing records private configuration but leaves the public DQOR root, tickets, invoices, and favicon unchanged: `EventBrandingSetting::PUBLIC_RENDERING_ENABLED` is false.

The three existing theme directions are `conference`, `marathon`, and `campus`. Colors and preset fonts are allowlisted. PNG/JPEG/WebP inputs are signature-checked, bounded to 1 MB and decoded limits, normalized to metadata-stripped WebP; SVG/animation/remote URLs are not accepted. Existing singleton assets are separate from candidate tenant website assets. See [persisted branding](theme-studio/PERSISTED_CONFIGURATION.md).

## Candidate: event-owned website workflow

**Candidate only.** The following implementation is present in this change, not deployed in baseline `3d10fd8`. Local validation and PR review do not establish production availability. The existing organizer gate remains off; deployment and activation require their own approval and evidence.

Private editor prefix: `/organizer/organizations/:organization_id/events/:event_id/website`, with save, saved-draft preview, explicit publish, restore, and event-owned asset actions. Public event pages retain `/events/:organization_slug/:event_slug`.

1. A freshly authorized event manager opens the editor: owner/admin/editor may write; a viewer may read the permitted saved draft/preview. Global staff credentials grant no tenant access. Every read/write/asset lookup rechecks membership and the exact organization/event.
2. Save a draft using `conference`, `marathon`, or `campus`; six-digit colors; preset heading fonts; bounded summary/about/venue and manually entered programme/sponsor text; bounded section order/visibility and internal navigation. Event title, dates, and timezone remain canonical Event fields. Global DQOR Talk/Sponsor records are not tenant content.
3. Upload bounded logo/cover/favicon raster images using the existing normalization limits. Draft images are private/no-store and require membership. Preview renders only the saved draft; editing does not change the public snapshot.
4. Explicitly publish the reviewed saved draft using the current revision and confirmation. A configured published event then renders that event's published snapshot; an unconfigured event retains its existing page. Publishing website configuration does not publish the Event or register attendees.
5. Explicitly restore the one retained prior publication using the current revision. Row locks/optimistic version checks reject stale writes; failed validation/upload must leave saved/public state unchanged.

Public image access is limited to assets referenced by the **current** published snapshot of the same published event. Draft, prior-only, cross-event, and unpublished assets must return 404 publicly. No public signed Active Storage draft URLs are part of the contract.

Migration `20261007000000_create_event_websites.rb` adds event-owned setting and private asset tables with no backfill or automatic enrollment. It introduces no flag activation, new login persistence, payment/native contract, staff grant, or root-site rewrite. Its first slice retains superseded private images rather than pruning them: repeated uploads can accumulate PostgreSQL storage. Retention/deletion needs a separate reviewed procedure; this guide authorizes none. Do not run a destructive schema rollback to restore a website publication.

## API and native scope

| Contract | Source status and limits |
| --- | --- |
| `GET /api/public/v1/dqor/programme` | Implemented read-only DQOR-specific JSON feed; published talks and published/announced speakers only. No tenant selector, attendee data, QR secrets, writes, or admission rights. ETag revalidation and 503/no-store failure semantics are documented in [programme API](PUBLIC_PROGRAMME_API.md). |
| `/api/staff/session`, `/api/staff/checkins` | Implemented default-off native staff API. Requires `NATIVE_STAFF_API_ENABLED` and a valid `NATIVE_STAFF_EVENT_DATES` subset. Existing admin/desk credentials, opaque scoped tokens, separate from web cookies/attendee identity. See [native staff contract](NATIVE_STAFF_API.md). |
| `/api/attendee/v1/account`, `/api/attendee/v1/passes` | Implemented default-off web-session read facade via `NATIVE_ATTENDEE_READ_API_ENABLED`; requires the verified attendee email. No bearer staff tokens or QR/claim/order secrets. See [read facade](NATIVE_ATTENDEE_READ_API_DRAFT.md). |
| `/api/native/attendee/v1/*` and account-native authorization | Implemented source bridge, default off via `NATIVE_ATTENDEE_SESSION_API_ENABLED`, with an explicit callback allowlist. Not generic organization/event-native login or remembered Safari authentication. See [PKCE contract](NATIVE_ATTENDEE_PKCE_DRAFT.md). |

These contracts remain unchanged by the candidate website workflow. iOS/Android directories contain separate clients and validation instructions, not a distribution receipt. Signing/team/tester setup, TestFlight or Android release delivery, device-camera rehearsal, and live API integration require their own evidence; merging Rails code cannot establish them.

## Deployment and recovery

Repository sources are [database.yml](../config/database.yml), [Dockerfile](../Dockerfile), [entrypoint](../bin/docker-entrypoint), [Render blueprint](../render.yaml), [Puma](../config/puma.rb), [storage configuration](../config/storage.yml), and [Docker workflow](../.github/workflows/docker-build.yml).

The blueprint declares a Singapore web service, Docker runtime, and `/up`, with no disk or database provisioning. Provide a reviewed PostgreSQL `DATABASE_URL` separately. All app/Solid Queue/Cache/Cable data uses the configured PostgreSQL database. Attachments select R2 when `R2_BUCKET` is present; otherwise production falls back to ephemeral local storage. The image includes Chromium/libvips and sets `SOLID_QUEUE_IN_PUMA=1`; the queue also has a separate `bin/jobs` entrypoint for other reviewed topologies.

For an authorized deployment:

1. Record the exact reviewed Git revision, all combined-head CI results, candidate migrations, current live image digest/revision, flag state, and database recovery owner. The Docker build runs independently of CI and can request Render deployment; a main push is operationally significant.
2. Verify a recent PostgreSQL backup and a successful restore to an isolated database, including relevant data and migrations. Also preserve attachments and private database-stored branding/website image bytes. This guide has no verified provider restore receipt, backup retention guarantee, or production restore command.
3. Review the entrypoint's `db:prepare` and first-install seed behavior. Production seeds require approved admin values and create DQOR defaults; this is not generic tenant provisioning. Check migration compatibility and any data-changing migrations before letting the server start.
4. After deployment, match Render's actual running image digest with the build export/revision metadata. Record relevant migration status; check `/up` and browser journeys for the released scope. Preserve the current DQOR site/scanner/commerce behavior and default-off platform/native flags unless activation is separately authorized.
5. If recovery is needed, select the recorded prior immutable image and validate schema compatibility before application rollback. Leave compatible additive tables/data in place. Migration down, provider restore, data deletion, and reopening paid services are separate decisions; do not apply them automatically.

`lib/tasks/backup.rake` still describes SQLite and references the removed `BackupDatabaseJob`; `config/recurring.yml` has no hourly database backup entry. Neither that task nor R2 attachment configuration proves PostgreSQL recoverability. Obtain the actual provider backup/restore evidence instead.

## Security boundaries

Use approved secret injection/storage; never commit credentials, invite tokens, native bearer tokens, real resumes, or attendee exports. Use synthetic data for local checks and keep production metadata out of public logs. Existing staff, attendee, and organization identities are separate; a matching email or global staff role is not a membership grant.

The platform/free-stack/native/hiring/announcement switches remain default off. New website content accepts escaped bounded text, allowlisted configuration, and managed raster assets rather than arbitrary HTML/CSS/JavaScript or remote image URLs. Draft previews/assets remain private. DQOR faces require a confirmed conference ticket, a name, and the existing public-attendee setting; this slice changes no visibility defaults. Authentication persistence, infrastructure/security changes, commercial activation, sends, and destructive deletion are outside this documentation change.

## Troubleshooting

| Symptom | Source-backed check |
| --- | --- |
| PostgreSQL connection/role failure | Check the intended local `DATABASE_URL` or [database.yml](../config/database.yml) defaults, running PostgreSQL, role/database permissions, and `libpq` availability. Do not fall back to SQLite. |
| `pg` gem fails to build | Install PostgreSQL client/development headers and expose the intended `pg_config`, then rerun Bundler. |
| Browser/PDF launch fails | Verify the installed `CHROME_PATH` executable, fonts, and runtime. CI/container sandbox options are environment-specific; do not copy them into local security settings as a blanket fix. |
| Branding upload fails | Verify libvips and a still PNG/JPEG/WebP within 1 MB, 4096 pixels per side, and 12 megapixels. A filename/MIME label alone is insufficient. |
| `/free` or organizer event page returns 404 | Check the intended approved demo gates. Missing membership/foreign event scope also denies access; do not grant global staff access to work around it. |
| Free registration unavailable | Recheck Event/category publication, remaining capacity, event/window timezone and bounds, and published questions/windows gates. Existing registrations do not imply new capacity. |
| Stale save/publish/restore | Reload and review the current saved revision. Do not silently retry or overwrite another organizer's draft. |
| Publishing DQOR branding does not change the site | Expected: singleton public rendering is off. Static browser drafts and persisted private configuration are separate. |
| Production attachment disappears after restart | Verify approved R2 configuration: the local fallback is ephemeral without a disk. No database backup claim follows from it. |
| Queue/email appears stuck | Check configured worker/queue health and SMTP configuration through private operations. When using Solid Queue, `bin/dev` alone does not start a separate `bin/jobs` process; a transport timeout can be an uncertain send, not permission to resend. |
| Native endpoint returns 404/503 | Review its default-off switch, callback/date configuration, and documented identity contract. Web deployment is not native distribution. |
| `/up` succeeds but a feature fails | Check the exact running image, migration status, flags and relevant browser/provider journey; health alone does not certify those paths. |

This guide was checked against repository source. It does not assert that setup commands, a managed PostgreSQL restore, the candidate website browser journey, or native distribution were exercised as part of the documentation change.
