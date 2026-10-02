# Deccan Queen Campfire

Sam Ruby's [Spinel Campfire bundle](https://rubys.github.io/roundhouse/apps/campfire.html), rebuilt from [our Roundhouse fork](https://github.com/vipulnsward/roundhouse) with the shared STI form routing fix, served at https://chat.deccanqueenonrails.com on the existing Hetzner server `91.99.201.249`. DQOR's signed-in dashboard and attendee directory use `CAMPFIRE_JOIN_URL` for registration. Campfire has its own login.

## Installed release

- Archive: `https://github.com/vipulnsward/roundhouse/releases/download/campfire-dqor-c0c42854/docker.tgz`
- SHA-256: `1d81d45bd31c85deb783900e5ea84af5325cafdcade911196319b18014565525`
- Bundle provenance: Roundhouse `c0c42854ebd03557edfe4aa4bee7088f5c483340`, Campfire `90b330024dec`, Spinel `ed603ed`.
- Image: `dqor-campfire:c0c42854`, built on the Linux AMD64 host.
- Storage: `/opt/dqor-campfire/storage`, owned by UID/GID 1000 with directory mode 0700. SQLite, uploads and the generated signing key survive container replacement.
- Administrator: `vipul@saeloun.com`; password in agent-vault item `dqor-campfire-admin-20261002`.

## Rebuild and start

Run on the host, with the existing `kamal` Docker network and proxy:

```sh
set -e
install -d -m 0700 /opt/dqor-campfire/releases/c0c42854
cd /opt/dqor-campfire/releases/c0c42854
if [ ! -f docker.tgz ]; then
  curl -fsSL https://github.com/vipulnsward/roundhouse/releases/download/campfire-dqor-c0c42854/docker.tgz -o docker.tgz.download
  printf '%s  %s\n' 1d81d45bd31c85deb783900e5ea84af5325cafdcade911196319b18014565525 docker.tgz.download | sha256sum -c -
  mv docker.tgz.download docker.tgz
fi
printf '%s  %s\n' 1d81d45bd31c85deb783900e5ea84af5325cafdcade911196319b18014565525 docker.tgz | sha256sum -c -
tar -xzf docker.tgz
docker build -t dqor-campfire:c0c42854 campfire-docker
install -d -m 0700 /opt/dqor-campfire/storage
chown 1000:1000 /opt/dqor-campfire/storage
docker compose -f /opt/dqor-campfire/compose.yml config --quiet
docker compose -f /opt/dqor-campfire/compose.yml up -d
```

Copy this directory's `compose.yml` to `/opt/dqor-campfire/compose.yml` first. Retain the verified archive on the host. The release is pinned by checksum; a changed checksum requires a separately tested release. The previous `dqor-campfire:a91496ff7aad` image and original archive remain available for rollback.

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

The fork fixes shared STI forms that submitted open and closed rooms to the base `/rooms` routes. Creating and renaming both room types is covered by the browser suite. The live room is named `Deccan Queen on Rails`. The fixed release passed 3,065 Rust tests (106 optional tests ignored), all six browser checks on the emitted Ruby and native Linux builds, and a production save/reload with the existing message retained. Native room checks used a 90-second limit over the SSH tunnel.

## Rebuild the fork

Check out Roundhouse commit `c0c42854ebd03557edfe4aa4bee7088f5c483340`, Campfire commit `90b330024dec`, and Spinel commit `ed603ed`. Build Spinel with its native OpenSSL package available, then use `scripts/build-campfire-archive --out RELEASE_DIR CAMPFIRE_DIR` from the Roundhouse checkout with `spin` and `spinel` on PATH. The release includes both `docker.tgz` and the emitted `spinel.tgz` source.

## Data and recovery

Do not delete `storage` or its `secret_key_base`. Before an upgrade, stop only this Compose service, copy `storage` to a private backup directory outside it, then start the service again. Copy the entire directory, including uploads and the signing key. For restoration, stop the service, preserve the current storage directory, restore the backup with UID/GID 1000 ownership, then start and verify login and messages. No automatic off-host backup is configured by this deployment.

```sh
docker compose -f /opt/dqor-campfire/compose.yml stop
cp -a /opt/dqor-campfire/storage /opt/dqor-campfire/storage-backup-$(date -u +%Y%m%dT%H%M%SZ)
docker compose -f /opt/dqor-campfire/compose.yml start
```

Push notifications require VAPID keys; they are not configured. The upstream bundle documents that real browser push delivery remains unverified.
