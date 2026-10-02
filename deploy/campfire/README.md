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
