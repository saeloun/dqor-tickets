# Deccan Queen on Rails Tickets

Self-hosted Rails conference ticketing for Deccan Queen on Rails 2026: Razorpay checkout, GST documents, attendee accounts, and QR check-in.

[![CI](https://github.com/saeloun/dqor-tickets/actions/workflows/ci.yml/badge.svg)](https://github.com/saeloun/dqor-tickets/actions/workflows/ci.yml)

The repository also contains an opt-in organization/free-event foundation and theme previews. **ConfOSS is a working name**, not a renamed or generally available product. The existing DQOR site and commerce remain separate from the default-off platform routes. See the [launch foundation guide](docs/CONFOSS_LAUNCH_FOUNDATION.md) for capability status and organizer workflows.

## Included in the source

- Orders containing multiple attendee tickets with snapshotted prices, coupons, checkout holds, and separate assignment.
- Paid conference tiers, supporter passes, and hidden complimentary passes share a 200-seat pool. Paid orders and unexpired holds reserve seats; canceled tickets and expired holds do not. Rails Girls and Explore Pune are outside this pool. Existing valid holds remain payable even when historical obligations already exceed the cap.
- Razorpay payment events, verified webhooks, idempotent confirmation, and reconciliation. Checkout holds last 30 minutes.
- GST invoice snapshots, credit notes, archived PDFs, and document-recovery workflows. Tax and seller policy require verified configuration before live sales.
- Avo administration, explicit refunds/complimentary issuance, exports, and staff QR scanning at `/checkin`; `/scanner_rehearsal` provides a staff rehearsal without writing real attendance.
- Conference-only “Rails Developers attending” counts and faces from named profiles whose public-attendee setting is enabled.
- Organization-scoped event publication and a free-registration pilot, including published questions and registration windows, behind separate default-off gates.

Source presence is not proof of deployment, provider readiness, feature activation, or native app distribution.

## Stack and local setup

- Ruby **4.0.6** ([mise.toml](mise.toml), [.ruby-version](.ruby-version)); Rails 8.1.
- **PostgreSQL 16** is the CI database version. All configured environments use PostgreSQL; install its client/development libraries for the `pg` gem.
- Chrome or Chromium for Ferrum PDFs and Cuprite browser tests; set `CHROME_PATH` to the installed executable if automatic discovery fails. Install appropriate fonts, including Devanagari fonts, for PDF rendering.
- **libvips** for image processing and bounded branding uploads.
- Propshaft, importmap, Turbo, and Stimulus; the Rails app has no Node build requirement. The optional static theme validation script has its own Node requirement.

Start PostgreSQL and ensure your local role can create/access the development and test databases. [database.yml](config/database.yml) defaults to `dqor_tickets_development` and `dqor_tickets_test`; `DATABASE_URL` can override the connection. Check that any inherited URL points to disposable local data before setup or tests.

```sh
mise install
bundle install
RAILS_ENV=development bin/rails db:prepare db:seed
RAILS_ENV=development bin/dev
```

Open `http://localhost:3000`. `bin/dev` starts Rails directly. A separate `bin/jobs` entrypoint is available when using Solid Queue. Development seeds create DQOR sample ticket types and a known sample staff account; use this only on an isolated local instance. Supply `ADMIN_EMAIL` and `ADMIN_PASSWORD` through your approved secret flow for other environments. There is no checked-in `.env.example`; `dotenv-rails` supports a private development `.env` if needed.

Run checks against the dedicated test database:

```sh
RAILS_ENV=test bundle exec rspec
bin/rubocop
bin/brakeman --no-pager
bin/bundler-audit
bin/importmap audit
```

System tests launch real Chromium. The optional ClamAV integration examples require their explicit test configuration; a skipped example does not establish a working production scanner. See [.github/workflows/ci.yml](.github/workflows/ci.yml).

## Configuration

Keep real values out of Git, logs, screenshots, and public documentation. Supply production secrets through the authorized deployment secret store.

| Settings | Purpose |
| --- | --- |
| `DATABASE_URL` | Production PostgreSQL connection; required separately because `render.yaml` does not provision a database or declare this variable. |
| `RAILS_MASTER_KEY` | Access to encrypted Rails credentials. |
| `APP_HOST` | Public hostname used for host authorization and HTTPS email links; review the blueprint's existing hostname for your own deployment. |
| `RAZORPAY_KEY_ID`, `RAZORPAY_KEY_SECRET`, `RAZORPAY_WEBHOOK_SECRET` | Payment API, checkout verification, and raw-body webhook verification. Use a reviewed test account for local payment exercises. |
| `R2_ENDPOINT`, `R2_ACCESS_KEY_ID`, `R2_SECRET_ACCESS_KEY`, `R2_BUCKET` | Private S3-compatible attachment storage. These settings do not establish a PostgreSQL backup service. |
| `SMTP_ADDRESS`, `SMTP_PORT`, `SMTP_USERNAME`, `SMTP_PASSWORD`, `MAIL_FROM` | Production SMTP delivery; the current configuration uses SSL. |
| `SELLER_NAME`, `SELLER_GSTIN`, `SELLER_ADDRESS` | Seller identity for tax documents; additional document-policy prerequisites are described in [finance readiness](docs/finance-readiness-admin.md). |
| `ADMIN_EMAIL`, `ADMIN_PASSWORD` | Initial seed staff identity; seeds do not replace an existing account's password. |
| `SENTRY_DSN` | Optional production error reporting. |
| `CHROME_PATH` | Browser executable for PDFs and system tests. |

Platform, hiring, native-session, and announcement gates default off. The [guide's status matrix](docs/CONFOSS_LAUNCH_FOUNDATION.md#capability-status) names them and distinguishes source implementation from activation. A global staff account does not acquire organization membership.

## Deploy and recover

The [Docker workflow](.github/workflows/docker-build.yml) builds Linux/AMD64 images in GHCR, tags the default branch as `latest` and each revision with a short SHA tag, and requests a Render image deployment when its existing GitHub secrets are present. CI and the Docker workflow run independently; a successful image build does not prove the full suite passed.

[render.yaml](render.yaml) defines a Singapore web service with `/up` health checks and **no persistent disk**. [Dockerfile](Dockerfile) supplies Chromium/libvips and enables Solid Queue inside Puma. Primary data and Solid Queue/Cache/Cable use PostgreSQL. Production attachments use R2 when `R2_BUCKET` is set; the local-storage fallback is not durable on this diskless deployment.

The [entrypoint](bin/docker-entrypoint) runs `db:prepare` before the Rails server and loads seeds only when no ticket types exist. Review migrations, database backup/restore evidence, flags, seed credentials, and the exact candidate before deployment. Then verify the actual running image digest/revision, migrations, health, and relevant browser journeys. `/up` or green CI alone is insufficient.

For application rollback, choose the recorded prior image digest, keep additive schema/data where compatible, and repeat live checks. A migration down may delete data and is not an automatic rollback step. This repository does **not** establish a tested managed-PostgreSQL recovery procedure: arrange and verify a provider backup or isolated restore before relying on it. The leftover [SQLite backup tasks](lib/tasks/backup.rake) reference a removed job and must not be used as PostgreSQL recovery commands.

See the [deployment, recovery, and troubleshooting guide](docs/CONFOSS_LAUNCH_FOUNDATION.md#deployment-and-recovery) for the operational evidence to record.

## Useful contracts

- [Staff scanner and rehearsal](docs/SCANNER_REHEARSAL.md), [staff API](docs/NATIVE_STAFF_API.md), and [staff deployment gates](docs/STAFF_CHECKIN_DEPLOYMENT.md).
- [Published-only DQOR programme feed](docs/PUBLIC_PROGRAMME_API.md) and its [JSON Schema](docs/contracts/public_programme_v1.schema.json).
- [Attendee read API](docs/NATIVE_ATTENDEE_READ_API_DRAFT.md) and [default-off native authorization bridge](docs/NATIVE_ATTENDEE_PKCE_DRAFT.md).
- [Free-event pilot](docs/FREE_EVENT_PILOT.md), [questions](docs/FREE_EVENT_QUESTIONS.md), and [registration windows](docs/FREE_REGISTRATION_WINDOWS.md).
- [Private persisted DQOR branding](docs/theme-studio/PERSISTED_CONFIGURATION.md) and [browser-only theme studio](docs/theme-studio/README.md).

Increment documents include historical validation/deployment notes. Consult the checked-out source and current release evidence before treating those notes as a live-state assertion. Merging Rails code does not ship iOS/Android binaries, configure signing/testers, or prove live native integration.

## Contributing and license

Keep changes focused, preserve legacy DQOR behavior and tenant boundaries, and run appropriate checks before review. Feature activation, grants, sends, payments, and destructive recovery require their own operational authorization.

This public repository remains available under the [MIT License](LICENSE).
