#!/usr/bin/env python3
"""Private Campfire telemetry. Run as root on the Docker host; stdlib only."""
import argparse
import collections
from contextlib import closing
import datetime
import hashlib
import http.server
import json
import math
import os
from pathlib import Path
import re
import sqlite3
import subprocess
import threading
import time

BUCKETS = (5, 10, 25, 50, 100, 250, 500, 1000, 2500, 5000, 10000)
# Only known static route segments survive; unknown values never enter telemetry.
SEGMENTS = set("accounts account session sessions new edit rooms room open_rooms closed_rooms direct_rooms messages message users user profiles profile attachments attachment avatars avatar reads read memberships membership boosts boost searches search settings notifications notification subscriptions subscription push_subscriptions password_resets password_reset join invitations invitation first_run first_runs welcome up runtime stats assets cables cable rails active_storage blobs redirects redirect representations proxy disk service_worker webmanifest pwa uploads upload health google callback auth oauth sign_in sign_out login logout unfurls unfurl reactions reaction pins pin cards card links link transcripts transcript exports export imports import bots bot tokens token transfer logo name description bookmarks bookmark preferences preference availability presence typing index create update destroy audio video files file images image sounds sound favorite favorites archived archive removed remove restore inbox outbox participants participant accesses access entrance entrances events event status status_updates timeline timeline_events copies copy reply replies content avatar_upload attachment_upload recordings recording tasks task".split())
METHODS = {"GET", "POST", "PUT", "PATCH", "DELETE", "HEAD", "OPTIONS", "CONNECT", "TRACE"}


def utc(ts=None):
    return datetime.datetime.fromtimestamp(ts or time.time(), datetime.timezone.utc).isoformat().replace("+00:00", "Z")


def safe_path(value):
    if not isinstance(value, str) or not value.startswith("/"):
        return "/:unknown"
    parts = value.split("?", 1)[0].split("#", 1)[0].split("/")[1:]
    return "/" + "/".join(part if part in SEGMENTS or re.fullmatch(r":[a-z_]{1,32}", part) else ":redacted" for part in parts[:12] if part)


def parse_event(line):
    """Ignore ordinary logs; validate and whitelist every field before persisting."""
    if len(line) > 65536:
        return None
    timestamp, _, payload = line.partition(" ")
    if not payload:
        payload, timestamp = line, utc()
    try:
        event = json.loads(payload).get("rh_request")
        if not isinstance(event, dict):
            return None
        method = event.get("method")
        status = event.get("status")
        duration = event.get("duration_ms")
        size = event.get("bytes", 0)
        if method not in METHODS or type(status) is not int or not 100 <= status <= 599:
            return None
        if type(duration) not in (float, int) or not math.isfinite(duration) or not 0 <= duration <= 86400000:
            return None
        if type(size) is not int or not 0 <= size <= 2**53:
            return None
        datetime.datetime.fromisoformat(timestamp.replace("Z", "+00:00"))
        return {"at": timestamp, "method": method, "path": safe_path(event.get("path")), "status": status, "duration_ms": duration, "bytes": size}
    except (ValueError, TypeError, AttributeError):
        return None


def atomic_json(path, value, uid=None):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(path.suffix + ".tmp")
    with temporary.open("w") as file:
        json.dump(value, file, separators=(",", ":"), allow_nan=False)
    os.chmod(temporary, 0o600 if uid is None else 0o640)
    if uid is not None:
        os.chown(temporary, uid, uid)
    temporary.replace(path)


def command(*args):
    return subprocess.check_output(args, timeout=12, stderr=subprocess.DEVNULL, text=True)


def process_stats(pid, proc=Path("/proc")):
    root = proc / str(pid)
    status = dict(line.split(":", 1) for line in (root / "status").read_text().splitlines() if ":" in line)
    stat = (root / "stat").read_text().rsplit(")", 1)[1].split()
    return {"rss_bytes": int(status.get("VmRSS", "0 kB").split()[0]) * 1024,
            "threads": int(status.get("Threads", "0")), "open_fds": len(list((root / "fd").iterdir())),
            "ticks": int(stat[11]) + int(stat[12]), "name": status.get("Name", "").strip()}


def database_stats(storage):
    counts, size = {}, 0
    for path in sorted(Path(storage).rglob("*.sqlite3")):
        size += path.stat().st_size
        for suffix in ("-wal", "-shm"):
            sidecar = Path(str(path) + suffix)
            if sidecar.exists():
                size += sidecar.stat().st_size
        try:
            with closing(sqlite3.connect(path.as_uri() + "?mode=ro", uri=True, timeout=0.2)) as database:
                database.execute("PRAGMA query_only = ON")
                tables = {row[0] for row in database.execute("SELECT name FROM sqlite_master WHERE type='table'")}
                for table in ("users", "rooms", "messages"):
                    if table in tables:
                        counts[table] = counts.get(table, 0) + database.execute(f"SELECT COUNT(*) FROM {table}").fetchone()[0]
        except sqlite3.Error:
            return {"bytes": size, "counts": counts, "error": "Database temporarily unavailable"}
    return {"bytes": size, "counts": counts}


class Collector:
    def __init__(self, container, storage, directory, interval=5):
        self.container, self.storage, self.directory, self.interval = container, Path(storage), Path(directory), interval
        self.lock = threading.RLock()
        self.started = utc()
        self.running = True
        self.snapshot = {"available": False, "collector_started_at": self.started}
        self.metrics = "campfire_up 0\n"
        self.previous_cpu = None
        self.previous_host_cpu = None
        self.previous_rate = None
        self.history = collections.deque(maxlen=720)  # One hour at the default interval.
        self.recent = collections.deque(maxlen=50)
        self.window = collections.deque(maxlen=10000)
        self.state = {"observed_since": self.started, "total": 0, "errors": 0, "bytes": 0, "statuses": {}, "series": {}, "cursor": None, "seen": []}
        try:
            persisted = json.loads((self.directory / "state.json").read_text())
            if persisted.get("version") == 1:
                self.state.update(persisted)
                self.history.extend(persisted.get("history", [])[-720:])
                self.recent.extend(persisted.get("recent", [])[-50:])
        except (OSError, ValueError, TypeError):
            pass
        self.seen = collections.deque(self.state.get("seen", [])[-4096:], maxlen=4096)
        self.seen_set = set(self.seen)

    def ingest(self, line):
        event = parse_event(line)
        if event is None:
            return
        digest = hashlib.sha256(line.encode()).hexdigest()
        with self.lock:
            if digest in self.seen_set:
                return
            if len(self.seen) == self.seen.maxlen:
                self.seen_set.discard(self.seen[0])
            self.seen.append(digest)
            self.seen_set.add(digest)
            self.state["cursor"] = max(self.state.get("cursor") or event["at"], event["at"])
            if self.state["total"] == 0:
                self.state["observed_since"] = event["at"]
            self.state["total"] += 1
            self.state["errors"] += event["status"] >= 500
            self.state["bytes"] += event["bytes"]
            status = str(event["status"])
            self.state["statuses"][status] = self.state["statuses"].get(status, 0) + 1
            key = json.dumps([event["method"], event["path"], status], separators=(",", ":"))
            # ponytail: cap label series at 512; expand only if real routes need it.
            if key not in self.state["series"] and len(self.state["series"]) >= 512:
                key = json.dumps([event["method"], "/:other", str(event["status"] // 100) + "xx"], separators=(",", ":"))
            series = self.state["series"].setdefault(key, {"count": 0, "sum": 0, "bytes": 0, "buckets": [0] * len(BUCKETS)})
            series["count"] += 1
            series["sum"] += event["duration_ms"] / 1000
            series["bytes"] += event["bytes"]
            for index, boundary in enumerate(BUCKETS):
                series["buckets"][index] += event["duration_ms"] <= boundary
            self.recent.append(event)
            timestamp = datetime.datetime.fromisoformat(event["at"].replace("Z", "+00:00")).timestamp()
            self.window.append((timestamp, event["duration_ms"]))

    def follow_logs(self):
        while self.running:
            with self.lock:
                since = self.state.get("cursor") or "1970-01-01T00:00:00Z"
            process = None
            try:
                process = subprocess.Popen(["docker", "logs", "--timestamps", "--follow", "--since", since, self.container], stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
                for line in process.stdout:
                    if not self.running:
                        break
                    self.ingest(line.rstrip("\n"))
            except (OSError, ValueError):
                pass
            finally:
                if process is not None:
                    process.terminate()
                    try:
                        process.wait(timeout=5)
                    except subprocess.TimeoutExpired:
                        process.kill()
            time.sleep(2)

    def sample_host(self, proc=Path("/proc")):
        cpu = [int(value) for value in (proc / "stat").read_text().splitlines()[0].split()[1:9]]
        total, idle = sum(cpu), cpu[3] + cpu[4]
        percent = None
        if self.previous_host_cpu and total > self.previous_host_cpu[0]:
            percent = 100 * (1 - (idle - self.previous_host_cpu[1]) / (total - self.previous_host_cpu[0]))
        self.previous_host_cpu = (total, idle)
        memory = dict(line.split(":", 1) for line in (proc / "meminfo").read_text().splitlines() if ":" in line)
        load = os.getloadavg()
        return {"host_cpu_percent": percent, "host_cpu_count": os.cpu_count(), "load_1m": load[0], "load_5m": load[1], "load_15m": load[2],
                "host_memory_total_bytes": int(memory["MemTotal"].split()[0]) * 1024,
                "host_memory_available_bytes": int(memory["MemAvailable"].split()[0]) * 1024}

    def sample_system(self):
        # Never inspect Env, command arguments, or logs other than safe request events.
        lines = command("docker", "inspect", "--format", '{{json .State}}\n{{.Id}}\n{{.Image}}\n{{.Config.Image}}\n{{.RestartCount}}\n{{json .Config.Labels}}\n{{.HostConfig.Memory}}\n{{.HostConfig.NanoCpus}}', self.container).splitlines()
        data = json.loads(lines.pop(0))
        if not data.get("Running"):
            raise RuntimeError("Container is stopped")
        pid = data["Pid"]
        process_root = Path("/proc") / str(pid)
        cgroup_line = next((line for line in (process_root / "cgroup").read_text().splitlines() if line.startswith("0::")), None)
        cgroup = Path("/sys/fs/cgroup") / cgroup_line.split("::", 1)[1].lstrip("/") if cgroup_line else None
        if not cgroup:
            raise RuntimeError("Cgroup v2 telemetry unavailable")
        pids = [int(value) for value in (cgroup / "cgroup.procs").read_text().split()]
        processes = []
        elf_processes, ruby_present = [], False
        for process_pid in pids:
            try:
                stats = process_stats(process_pid)
                process_dir = Path("/proc") / str(process_pid)
                executable = os.readlink(process_dir / "exe")
                with (process_dir / "exe").open("rb") as binary:
                    elf = binary.read(4) == b"\x7fELF"
                ruby_present |= bool(re.search(r"(?:^|/)(?:ruby(?:[0-9.]*)?|libruby[^/]*)(?:$|\s)", executable)) or "libruby" in (process_dir / "maps").read_text()
                processes.append(stats)
                if "spinel" in executable.lower() or "campfire" in executable.lower():
                    elf_processes.append({"executable": executable, "elf": elf})
            except (OSError, ValueError):
                continue
        if not processes:
            raise RuntimeError("Process telemetry unavailable")
        cpu_stats = dict(line.split() for line in (cgroup / "cpu.stat").read_text().splitlines())
        cpu_seconds = int(cpu_stats["usage_usec"]) / 1e6
        cpu = None
        clock = time.monotonic()
        identity = (lines[0], data.get("StartedAt"))
        if self.previous_cpu and self.previous_cpu[0] == identity:
            cpu = max(0, (cpu_seconds - self.previous_cpu[1]) / (clock - self.previous_cpu[2]) * 100)
        self.previous_cpu = (identity, cpu_seconds, clock)
        memory = None
        if cgroup and (cgroup / "memory.current").exists():
            memory = int((cgroup / "memory.current").read_text())
        tcp = None
        for name in ("tcp", "tcp6"):
            try:
                tcp = (tcp or 0) + sum(line.split()[3] == "01" for line in (process_root / "net" / name).read_text().splitlines()[1:])
            except OSError:
                pass
        labels = json.loads(lines[4]) or {}
        started = datetime.datetime.fromisoformat(data["StartedAt"].replace("Z", "+00:00"))
        system = {"cpu_percent": cpu, "cpu_limit": int(lines[6]) / 1e9 or None, "rss_bytes": sum(process["rss_bytes"] for process in processes), "memory_bytes": memory,
                  "memory_limit_bytes": int(lines[5]) or None, "workers": len(elf_processes), "processes": len(processes), "threads": sum(process["threads"] for process in processes),
                  "open_fds": sum(process["open_fds"] for process in processes), "tcp_connections": tcp,
                  "uptime_seconds": max(0, time.time() - started.timestamp()), "restarts": int(lines[3])}
        system.update(self.sample_host())
        native = {"container_id": lines[0], "image_id": lines[1], "image_ref": lines[2], "image_revision": labels.get("org.opencontainers.image.revision"),
                  "campfire_revision": labels.get("io.dqor.campfire.revision"), "spinel_revision": labels.get("io.dqor.spinel.revision"), "elf": all(process["elf"] for process in elf_processes) if elf_processes else None,
                  "executable": elf_processes[0]["executable"] if elf_processes else None, "ruby_runtime_present": ruby_present if len(processes) == len(pids) and processes else None,
                  "processes_inspected": len(processes), "started_at": data["StartedAt"]}
        return system, native

    def sample(self):
        now = time.time()
        try:
            system, native = self.sample_system()
            available, error = True, None
        except (OSError, ValueError, RuntimeError, KeyError, subprocess.SubprocessError):
            system, native, available, error = {}, {}, False, "Container telemetry unavailable"
        database = database_stats(self.storage)
        with self.lock:
            while self.window and self.window[0][0] < now - 60:
                self.window.popleft()
            durations = sorted(duration for at, duration in self.window if at >= now - 60)
            percentile = lambda percent: durations[max(0, math.ceil(len(durations) * percent) - 1)] if durations else None
            total = self.state["total"]
            rate = (total - self.previous_rate[0]) / (now - self.previous_rate[1]) if self.previous_rate else None
            self.previous_rate = (total, now)
            requests = {key: self.state[key] for key in ("total", "errors", "bytes", "statuses", "observed_since")}
            requests["statuses"] = dict(self.state["statuses"])
            requests.update({"rate_per_second": rate, "p50_ms": percentile(0.5), "p95_ms": percentile(0.95), "recent": list(reversed(self.recent)), "latency_window_seconds": 60, "latency_window_requests": len(durations)})
            self.history.append({"at": utc(now), "cpu_percent": system.get("cpu_percent"), "rss_bytes": system.get("rss_bytes"), "rate_per_second": rate, "p95_ms": requests["p95_ms"]})
            self.snapshot = {"sampled_at": utc(now), "collector_started_at": self.started, "available": available, "error": error, "native": native, "system": system, "requests": requests, "database": database, "history": list(self.history), "history_interval_seconds": self.interval}
            self.metrics = self.prometheus()
            self.directory.mkdir(parents=True, exist_ok=True)
            atomic_json(self.storage / "runtime_stats.json", self.snapshot, uid=1000)
            atomic_json(self.directory / "state.json", {**self.state, "version": 1, "seen": list(self.seen), "history": list(self.history), "recent": list(self.recent)})
            temporary = self.directory / "metrics.prom.tmp"
            temporary.write_text(self.metrics)
            temporary.replace(self.directory / "metrics.prom")

    def prometheus(self):
        lines = ["# TYPE campfire_up gauge", f"campfire_up {int(self.snapshot['available'])}", f"campfire_sample_timestamp_seconds {time.time()}", "# TYPE campfire_http_requests_total counter", "# TYPE campfire_http_request_duration_seconds histogram"]
        for key, series in self.state["series"].items():
            method, path, status = json.loads(key)
            labels = f'method={json.dumps(method)},route={json.dumps(path)},status={json.dumps(status)}'
            lines.extend([f"campfire_http_requests_total{{{labels}}} {series['count']}", f"campfire_http_response_bytes_total{{{labels}}} {series['bytes']}"])
            for boundary, count in zip(BUCKETS, series["buckets"]):
                lines.append(f'campfire_http_request_duration_seconds_bucket{{{labels},le="{boundary / 1000:g}"}} {count}')
            lines.extend([f'campfire_http_request_duration_seconds_bucket{{{labels},le="+Inf"}} {series["count"]}', f'campfire_http_request_duration_seconds_count{{{labels}}} {series["count"]}', f'campfire_http_request_duration_seconds_sum{{{labels}}} {series["sum"]}'])
        for key, value in self.snapshot["system"].items():
            if isinstance(value, (int, float)):
                lines.append(f"campfire_{key} {value}")
        lines.append(f"campfire_database_bytes {self.snapshot['database']['bytes']}")
        for table, count in self.snapshot["database"]["counts"].items():
            lines.append(f'campfire_database_records{{table="{table}"}} {count}')
        return "\n".join(lines) + "\n"


def serve(collector, port):
    class Handler(http.server.BaseHTTPRequestHandler):
        def do_GET(self):
            with collector.lock:
                if self.path == "/metrics":
                    body, mime = collector.metrics.encode(), "text/plain; version=0.0.4; charset=utf-8"
                elif self.path == "/snapshot":
                    body, mime = json.dumps(collector.snapshot, allow_nan=False).encode(), "application/json"
                else:
                    self.send_error(404)
                    return
            self.send_response(200)
            self.send_header("Content-Type", mime)
            self.send_header("Cache-Control", "no-store")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)

        def log_message(self, *args):
            pass
    return http.server.ThreadingHTTPServer(("127.0.0.1", port), Handler)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--container", default="dqor-campfire")
    parser.add_argument("--storage", default="/opt/dqor-campfire/storage")
    parser.add_argument("--directory", default="/opt/dqor-campfire/monitoring")
    parser.add_argument("--interval", type=float, default=5)
    parser.add_argument("--port", type=int, default=4312)
    args = parser.parse_args()
    if args.interval < 1:
        parser.error("interval must be at least one second")
    collector = Collector(args.container, args.storage, args.directory, args.interval)
    threading.Thread(target=collector.follow_logs, daemon=True).start()
    server = serve(collector, args.port)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    while True:
        started = time.monotonic()
        collector.sample()
        time.sleep(max(0, args.interval - (time.monotonic() - started)))


if __name__ == "__main__":
    main()
