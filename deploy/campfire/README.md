# Deccan Queen Campfire

Sam Ruby's [Spinel Campfire bundle](https://rubys.github.io/roundhouse/apps/campfire.html), served at https://chat.deccanqueenonrails.com on the existing Hetzner server `91.99.201.249`. DQOR's signed-in dashboard and attendee directory use `CAMPFIRE_JOIN_URL` for registration. Campfire has its own login.

## Installed release

- Archive: `https://rubys.github.io/roundhouse/campfire/docker.tgz`
- SHA-256: `a91496ff7aad9232a79ba72017656698388ea02976b97c48cf0921f7205d921e`
- Bundle provenance: Roundhouse `d6da862`, Campfire `90b330024dec`, Spinel `ed603ed`.
- Image: `dqor-campfire:a91496ff7aad`, built on the Linux AMD64 host.
- Storage: `/opt/dqor-campfire/storage`, owned by UID/GID 1000 with directory mode 0700. SQLite, uploads and the generated signing key survive container replacement.
- Administrator: `vipul@saeloun.com`; password in agent-vault item `dqor-campfire-admin-20261002`.

## Rebuild and start

Run on the host, with the existing `kamal` Docker network and proxy:

```sh
set -e
cd /opt/dqor-campfire
if [ ! -f docker.tgz ]; then
  curl -fsSL https://rubys.github.io/roundhouse/campfire/docker.tgz -o docker.tgz.download
  printf '%s  %s\n' a91496ff7aad9232a79ba72017656698388ea02976b97c48cf0921f7205d921e docker.tgz.download | sha256sum -c -
  mv docker.tgz.download docker.tgz
fi
printf '%s  %s\n' a91496ff7aad9232a79ba72017656698388ea02976b97c48cf0921f7205d921e docker.tgz | sha256sum -c -
tar -xzf docker.tgz
docker build -t dqor-campfire:a91496ff7aad campfire-docker
install -d -m 0700 -o 1000 -g 1000 storage
docker compose -f compose.yml config --quiet
docker compose -f compose.yml up -d
```

Copy this directory's `compose.yml` to `/opt/dqor-campfire/compose.yml` first. Retain the verified archive on the host: upstream's download URL can change, and a changed checksum requires a separately tested release.

On a new installation, complete first-run setup over an SSH tunnel to `127.0.0.1:4300` before publishing the domain. On the current installation it is already complete. Retrieve the account's join link from Campfire account settings and configure `CAMPFIRE_JOIN_URL` on DQOR's Render service. Keep the real invite out of the repository and public pages.

## HTTPS and health

The Cloudflare A record points to `91.99.201.249` and is proxied. Kamal proxy terminates origin TLS with a Let's Encrypt certificate and forwards WebSockets to port 3000:

```sh
docker exec kamal-proxy kamal-proxy deploy dqor-campfire \
  --target dqor-campfire:3000 --host chat.deccanqueenonrails.com \
  --tls --forward-headers --health-check-path /session/new
curl --fail --silent --show-error https://chat.deccanqueenonrails.com/session/new > /dev/null
```

Use GET for this check: this bundle returns 404 for HEAD. Its `/up` returns 500; `/session/new` renders successfully and is the proxy health check. Public first-run setup is disabled after creating the administrator. Verify registration and a live message between two browser tabs after changing the image or proxy.

The room-name edit returned a Turbo form-response error and left the default `All Talk` name unchanged during setup. Account branding, login and live messages worked. Room-settings editing requires an upstream fix before relying on it.

## Data and recovery

Do not delete `storage` or its `secret_key_base`. Before an upgrade, stop only this Compose service, copy `storage` to a private backup directory outside it, then start the service again. Copy the entire directory, including uploads and the signing key. For restoration, stop the service, preserve the current storage directory, restore the backup with UID/GID 1000 ownership, then start and verify login and messages. No automatic off-host backup is configured by this deployment.

```sh
docker compose -f /opt/dqor-campfire/compose.yml stop
cp -a /opt/dqor-campfire/storage /opt/dqor-campfire/storage-backup-$(date -u +%Y%m%dT%H%M%SZ)
docker compose -f /opt/dqor-campfire/compose.yml start
```

Push notifications require VAPID keys; they are not configured. The upstream bundle documents that real browser push delivery remains unverified.

## Dedicated binary service with Kamal (prepared, not yet migrated)

`kamal.yml` manages Campfire independently of the ticketing Rails app. It runs
`./campfire` directly as UID/GID 1000, using the existing storage path, hostname,
resource limits and login-page health check. It does not deploy the ticketing
app. The existing Compose service is still the recorded production deployment;
do not run both managers against its live SQLite volume during migration.

The deployment artifact is a native executable generated from Campfire's Rails
source by Roundhouse and Spinel. There is no CRuby interpreter, Rails gem bundle,
Puma, Redis or separate job worker in the upstream runtime image. This is not a
fully static, single-file distribution: the executable uses native system
libraries (SQLite, jemalloc, OpenSSL, libvips and others), prebuilt assets and
persistent storage; ffmpeg supports video previews. Docker is packaging for the
binary, and Kamal is its deployment manager. Ruby used to run Kamal on the
operator's machine is not the application's runtime.

### Source provenance and repeatability

Keep the installed release's checksum above. The upstream `docker.tgz` URL is
mutable. On 2026-10-02 it returned SHA-256
`c8673c3e4e70598ab9806992fd51ac1d8c5a78e7d7cbcba8805f5076d8566c3d`,
with Roundhouse `dad9b58` and Spinel `50efd55`; it is not the deployed release.
It was inspected only, not executed or approved as an upgrade. Obtain the
retained `/opt/dqor-campfire/docker.tgz` through a verified, already authorized
SSH connection, then prepare from repository root with Python 3.12 or newer:

```sh
python3 deploy/campfire/prepare.py /path/to/retained/docker.tgz
python3 -m unittest discover -s deploy/campfire -p 'test_*.py' -v
```

Preparation checks the exact archive hash and rejects unsafe archive members
before extracting into `.campfire-build/campfire-docker`. It executes no archive
code, never refreshes a download, and refuses to overwrite an existing context.
Review that context's Dockerfile, Makefile, boot script, native sources and
provenance before building. The C-source bundle avoids needing Roundhouse or
Spinel installed to compile this exact emit. For custom application changes,
pin all three upstream commits, use Roundhouse's `scripts/build-campfire-archive`
recipe at the pinned revision, and review and test the newly emitted source as a
new release. Do not equate a freshly downloaded archive with the reviewed pin.

This pins source, not bit-for-bit image output. Upstream uses a mutable Debian
base tag and apt repositories. Before claiming reproducible image bytes, pin a
reviewed base digest and dependency snapshot, retain compiler/build logs, record
the target architecture and final image digest, and retain the source archive.
The configured target is Linux AMD64, matching the recorded host, not the M4's
ARM64 architecture. Local Docker can build AMD64 through emulation; verify the
result's ELF architecture and dynamic libraries before release.

Licenses: Campfire and Spinel are MIT; Roundhouse is MIT OR Apache-2.0. Preserve
their copyright/license notices and the notices of included native components
and assets when distributing a custom image. The inspected download exposes
Campfire's MIT-LICENSE but does not provide a complete top-level third-party
notice inventory; that inventory is a release prerequisite, not a claim of
completed licensing review.

Official references:

- https://rubys.github.io/roundhouse/apps/campfire.html
- https://github.com/rubys/roundhouse/blob/d6da862/scripts/campfire-docker-files
- https://github.com/rubys/roundhouse/blob/d6da862/scripts/build-campfire-archive
- https://github.com/rubys/roundhouse/blob/d6da862/LICENSE-MIT
- https://github.com/matz/spinel/blob/ed603ed/LICENSE
- https://github.com/basecamp/once-campfire/blob/90b330024dec/MIT-LICENSE
- https://kamal-deploy.org/docs/configuration/overview/

### Migration gates and operator configuration

No new machine, registry, credentials, DNS, firewall rules, SSH trust entries or
permission grants are created by this configuration. Set `CAMPFIRE_HOST`,
`CAMPFIRE_SSH_USER`, `CAMPFIRE_IMAGE`, `CAMPFIRE_REGISTRY` and
`CAMPFIRE_REGISTRY_USERNAME` only after verifying existing authorized values.
The documented host is `91.99.201.249`; its authorized SSH username and registry
have not been verified from this task. Supply the existing registry password
through Kamal's secret mechanism as `KAMAL_REGISTRY_PASSWORD`; never commit it.
Do not use a new paid resource or create a registry to fill these values.

Validate locally with Kamal 2.12:

```sh
kamal -c deploy/campfire/kamal.yml config
```

Do not run deployment until all of these are complete:

1. Independently verify the server host-key fingerprint and existing SSH user;
   retain strict host-key checking. The current M4 has no trusted key for the
   documented host, so remote inspection stopped before authentication.
2. Inspect the running image/command, host architecture, available disk/RAM,
   Docker network and Kamal Proxy route, storage ownership, registry access and
   any active deployment. Confirm no change in hosting cost or permissions.
3. Retrieve and verify the retained source archive; complete source trust and
   license review. Build and test the candidate on disposable storage with no
   production secrets. Check native executable format/dependencies and confirm
   Ruby, Rails and Puma are absent from the runtime image.
4. Exercise first-run setup privately, sign-in/sign-out, non-admin invite signup,
   two-browser live messages, unauthorized WebSocket rejection, room settings,
   uploads and restart persistence. Regression-test the documented room-edit
   failure before claiming it fixed. Do not reuse upstream's latest conformance
   score as evidence for this older pinned release.
5. Plan a brief maintenance window: stop only the existing Campfire writer,
   preserve the SQLite database, files and signing key together, and retain the
   prior image plus proxy target for rollback. Boot the Kamal candidate against
   that preserved storage only after the old writer is stopped. Never regenerate
   its signing key. Inspect the existing proxy route ownership before cutover;
   Kamal's service naming may differ from the manually registered Compose route.
6. Deploy the tested immutable image with Kamal, verify HTTPS login, invite scope,
   live messaging and persistence, then verify rollback instructions. Leave the
   ticketing application and its PRs untouched.

Current evidence: the public `/session/new` page returned HTTP 200 and a Sign in
form on 2026-10-02. No new deployment or authenticated production test occurred.
The URL is a sign-in page, not an attendee invite. The existing attendee-scoped
registration link and its access rules still require authenticated inspection.

### Optional ticketing-account linkage (proposal only)

Today Campfire has a separate account. The main application's signed-in chat
link is navigation, not single sign-on, and the configured join code can be a
reusable bearer invitation rather than proof of attendee eligibility.

For a future integration, use an authorization-code flow: after a ticketing
login and an explicit eligibility check, issue a short-lived, single-use opaque
code bound to the intended Campfire audience, exact callback URL and browser
state/PKCE challenge. Campfire exchanges it server-to-server with the issuer and
validates expiry, replay protection and eligibility before establishing its own
session. Use a stable issuer/subject mapping, not an unverified email match;
link existing accounts only after proving ownership of both. Grant attendee
membership only, never administrator access. Keep each application's cookies
host-only and its signing keys separate. Protect callback redirects, redact
codes from logs and test replay, wrong audience, revoked eligibility and account
collision. This requires reviewed endpoint and binary changes plus an approved
client trust arrangement; none is implemented or provisioned here.
