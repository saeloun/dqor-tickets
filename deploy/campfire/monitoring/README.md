# Private native Campfire telemetry

A Python stdlib collector samples `dqor-campfire` every five seconds. It reads Docker's selected metadata, Linux cgroup v2 and `/proc`; SQLite access is read-only, limited to database size and users/rooms/messages counts. It never reads environment variables, process command arguments, request bodies, email addresses or message contents. Only validated `rh_request` JSON events from Docker logs enter request telemetry. Routes have an additional static-segment whitelist; query strings and unknown route values are removed.

The authenticated Campfire `/runtime` dashboard is enabled by `RUNTIME_DASHBOARD_ENABLED=true`. `/runtime/stats` reads `/app/storage/runtime_stats.json`; both routes inherit Campfire's session authentication. No public exporter is exposed. The collector writes that file atomically, UID/GID 1000, mode 0640. State is private to root (0600).

## Install on the Linux Docker host

Copy this directory to `/opt/dqor-campfire/monitoring`, then:

```sh
install -o root -g root -m 0644 /opt/dqor-campfire/monitoring/campfire-monitoring.service /etc/systemd/system/campfire-monitoring.service
systemctl daemon-reload
systemctl enable --now campfire-monitoring.service
docker compose -f /opt/dqor-campfire/monitoring/compose.yml config --quiet
docker compose -f /opt/dqor-campfire/monitoring/compose.yml up -d
curl --fail http://127.0.0.1:4312/metrics
curl --fail http://127.0.0.1:4313/-/ready
```

Prometheus is the [official image](https://prometheus.io/docs/prometheus/latest/installation/), pinned to [v3.13.4 LTS](https://prometheus.io/download/) and its Docker registry manifest digest. It uses host networking solely to reach the loopback exporter, and listens on `127.0.0.1:4313`. Scrapes run every 15 seconds; named-volume history is retained for 14 days, capped at 2 GB. Use an SSH tunnel to access Prometheus.

## Measurements and limits

- CPU is container cgroup CPU time; 100% represents one fully used core. RSS sums process resident memory; shared mappings may count in multiple processes. Cgroup memory measures the whole container, including page cache. Workers are executable processes whose path contains `campfire` or `spinel`; threads, FDs, TCP connections, uptime and Docker restart count come from the host.
- ELF proof reads the running executable's magic bytes. Ruby evidence checks every accessible process executable and memory maps for `ruby` / `libruby`. An incomplete inspection is unavailable. Image ID is Docker's local content ID, alongside image reference and revision labels; it is not a registry manifest digest.
- Host CPU comes from aggregate `/proc/stat` deltas; memory from `MemTotal` / `MemAvailable`; 1/5/15-minute load averages come from the OS.
- Requests cover every completed HTTP event emitted by the instrumented runtime, including dashboard requests. WebSocket connections are counted at the handshake; individual frames do not complete HTTP requests. Uninstrumented requests cannot be inferred. Durations measure native handler execution, excluding network/TLS/proxy time. Bytes measure response bodies, excluding headers and WebSocket frames. HTTP 5xx counts as an error; all statuses remain visible.
- Counter history starts with Docker's retained logs, survives collector/container restarts, and deduplicates replay at the persisted log cursor. Docker log rotation while the collector is stopped can lose events; the collector cannot recover deleted logs. Latency percentiles cover the latest 10,000 events within 60 seconds. Charts retain the latest 720 samples; recent requests retain 50 entries. Histogram/counter label series are capped at 512 plus bounded overflow buckets.
- The first CPU/rate sample and empty latency windows are unavailable. Collection failure marks the sample unavailable. Missing provenance labels remain unavailable. Configure `org.opencontainers.image.revision`, `io.dqor.campfire.revision` and `io.dqor.spinel.revision` when building the image.
- `runtime_stats.json` is operational data in persistent storage. Existing private storage backup procedures should continue to cover it; Prometheus's named volume is independent.

## Check

```sh
python3 -m unittest discover -s deploy/campfire/monitoring -v
```

This exercises parser validation/redaction, real read-only WAL SQLite access, Linux proc formats, bounded history and restart/deduplication persistence. Live Linux host collection and authenticated browser behavior require deployment verification.
