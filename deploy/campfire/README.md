# Deccan Queen Campfire

Sam Ruby's [Spinel Campfire bundle](https://rubys.github.io/roundhouse/apps/campfire.html), rebuilt from [our Roundhouse fork](https://github.com/vipulnsward/roundhouse) with shared fixes for form routing, private helpers and exception telemetry, served at https://chat.deccanqueenonrails.com on the existing Hetzner server `91.99.201.249`. DQOR's signed-in dashboard and attendee directory use `CAMPFIRE_JOIN_URL` for registration. Campfire supports its existing password login and Google sign-in through DQOR’s existing Google client. The private live dashboard is https://chat.deccanqueenonrails.com/runtime.

## Installed release

- Archive: `https://github.com/vipulnsward/roundhouse/releases/download/campfire-dqor-be39e42-569ff565/docker.tgz`
- SHA-256: `5bb944817c831111eb389fef6bcc3d3043782eb98d339242fb35383a2d9f8d1d`
- Bundle provenance: Roundhouse `be39e428ef6f3a47719d3ab9a46041133146178a`, Campfire `569ff565dafa2516f8ff3e7374d68fc19e91f417`, Spinel `ed603ed`.
- Image: `dqor-campfire:be39e42-569ff565`, built on the Linux AMD64 host.
- Storage: `/opt/dqor-campfire/storage`, owned by UID/GID 1000 with directory mode 0700. SQLite, uploads and the generated signing key survive container replacement.
- Administrator: `vipul@saeloun.com`; verified Google sign-in in Brave.
- Branding: DQOR logo with cream/ruby light mode and warm dark mode, including the private runtime dashboard.
- Native executable: the same release includes `campfire-linux-amd64` (SHA-256 `86f6c4bc6eda8f2cee69574fa34b27e99b1620358c9b54394b82e637cd7718e1`). It needs the matching assets and Linux runtime libraries; use the Docker archive for a complete deployment.

## Rebuild and start

Run on the host, with the existing `kamal` Docker network and proxy. Create `/opt/dqor-campfire/access.env` with mode 0600 before starting the pinned compose file. It contains `CAMPFIRE_ADMIN_EMAILS`, `CAMPFIRE_SPEAKER_EMAILS`, and `CAMPFIRE_SPEAKER_ROOM_ID=2`. Keep private addresses out of source control. Promotion and lounge membership apply when an invited person signs in with their verified Google account; this is not proof that everyone has already joined.

```sh
set -e
install -d -m 0700 /opt/dqor-campfire/releases/be39e42-569ff565
cd /opt/dqor-campfire/releases/be39e42-569ff565
if [ ! -f docker.tgz ]; then
  curl -fsSL https://github.com/vipulnsward/roundhouse/releases/download/campfire-dqor-be39e42-569ff565/docker.tgz -o docker.tgz.download
  printf '%s  %s\n' 5bb944817c831111eb389fef6bcc3d3043782eb98d339242fb35383a2d9f8d1d docker.tgz.download | sha256sum -c -
  mv docker.tgz.download docker.tgz
fi
printf '%s  %s\n' 5bb944817c831111eb389fef6bcc3d3043782eb98d339242fb35383a2d9f8d1d docker.tgz | sha256sum -c -
tar -xzf docker.tgz
docker build -t dqor-campfire:be39e42-569ff565 \
  --label org.opencontainers.image.revision=be39e428ef6f3a47719d3ab9a46041133146178a \
  --label io.dqor.campfire.revision=569ff565dafa2516f8ff3e7374d68fc19e91f417 \
  --label io.dqor.spinel.revision=ed603ed595db42626c747988a091c07f54532b94 campfire-docker
install -d -m 0700 /opt/dqor-campfire/storage
chown 1000:1000 /opt/dqor-campfire/storage
docker compose -f /opt/dqor-campfire/compose.yml config --quiet
docker compose -f /opt/dqor-campfire/compose.yml up -d
```

Copy this directory's `compose.yml` to `/opt/dqor-campfire/compose.yml` first. Retain the verified archive on the host. The release is pinned by checksum; a changed checksum requires a separately tested release. The previous `dqor-campfire:605040cd-569ff565` image and release remain available for rollback.

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

The fork fixes shared STI forms that submitted open and closed rooms to the base `/rooms` routes. Creating and renaming both room types is covered by the browser suite. The live room is named `Deccan Queen on Rails`. The earlier room-routing release passed its Rust and browser suites. The Google/monitoring release passes the full Rust suite, 39 Rails controller tests (145 assertions), and a native 200-request concurrency check with exact event/status/body-byte counts. All six native browser checks passed. Native Google callback QA verified invite-only registration, verified admin promotion, private lounge membership, dashboard/JSON access, and anonymous denial against a local mock issuer. Production verification confirmed the pinned image and source labels, ELF/Ruby absence, fresh collector data, Prometheus scrape, and capture of 40 known HTTP requests. Native room checks used a 90-second limit over the SSH tunnel. The branded native build passed light/dark checks for exact logo bytes, page palette, dashboard logo and inherited accent, with no browser errors. Production Google sign-in completed through the existing Google client in Brave; the branded upgrade preserved that authenticated session and the signing key. The live dashboard confirms the new source labels and native image.

The runtime failure fix passed 901 Rust unit tests, 82 emission checks, and a compiled Spinel exception-telemetry regression. Isolated Linux QA verified text and attachment editors return HTTP 200 and a deliberate exception records exactly one HTTP 500 event. Production verification reopened the original attachment editor successfully and confirmed fresh telemetry from the new image. The storage backup and signing key were preserved during replacement.

## Rebuild the fork

Check out Roundhouse commit `be39e428ef6f3a47719d3ab9a46041133146178a`, Campfire commit `569ff565dafa2516f8ff3e7374d68fc19e91f417`, and Spinel commit `ed603ed`. Build Spinel with its native OpenSSL package available, then use `scripts/build-campfire-archive --out RELEASE_DIR CAMPFIRE_DIR` from the Roundhouse checkout with `spin` and `spinel` on PATH. The release includes `docker.tgz` and `provenance.json`. The archive contains generated native source, public assets, and Campfire image assets needed by native file fallback. The container links OpenSSL and includes CA certificates for the HTTPS broker redemption.

## Data and recovery

Do not delete `storage` or its `secret_key_base`. Before an upgrade, stop only this Compose service, copy `storage` to a private backup directory outside it, then start the service again. Copy the entire directory, including uploads and the signing key. For restoration, stop the service, preserve the current storage directory, restore the backup with UID/GID 1000 ownership, then start and verify login and messages. No automatic off-host backup is configured by this deployment.

```sh
docker compose -f /opt/dqor-campfire/compose.yml stop
cp -a /opt/dqor-campfire/storage /opt/dqor-campfire/storage-backup-$(date -u +%Y%m%dT%H%M%SZ)
docker compose -f /opt/dqor-campfire/compose.yml start
```

Push notifications require VAPID keys; they are not configured. The upstream bundle documents that real browser push delivery remains unverified.

## Google sign-in and private access

DQOR `/chat/login` performs Google authentication using its existing client, then issues a 60-second, single-use grant. Campfire redeems that grant over HTTPS; new accounts require a valid join link, and the verified Google email controls configured administrator and Speaker Lounge access. Campfire’s signed nonce expires after 10 minutes. The callback returns existing users to their requested private page.

## Live monitoring

See [monitoring/README.md](monitoring/README.md) for the existing collector and Prometheus service. `/runtime` and `/runtime/stats` require an authenticated human Campfire user. The dashboard refreshes every five seconds and shows native binary provenance, CPU, cgroup memory/RSS, host load, requests, status/error counts, durations, response body bytes, and bounded recent request history. Unknown paths and query strings are redacted. Earlier native exceptions skipped event logging; historical totals before this release omit those failures. The fixed wrapper records exception responses before rethrowing. It records completed HTTP requests, including assets and WebSocket handshakes; WebSocket frames and proxy/TLS overhead are outside those measurements. Prometheus is loopback-only with a 15-second scrape and 14-day retention.
