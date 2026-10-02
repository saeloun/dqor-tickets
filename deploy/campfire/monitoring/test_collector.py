from contextlib import closing
import json
import os
from pathlib import Path
import sqlite3
import tempfile
import threading
import urllib.request
import unittest
from unittest.mock import patch

from collector import Collector, database_stats, parse_event, process_stats, safe_path, serve


def event(path="/rooms/:id", status=200, duration=12.3, at="2026-10-03T12:00:00.123456789Z"):
    return at + " " + json.dumps({"rh_request": {"method": "GET", "path": path, "status": status, "duration_ms": duration, "bytes": 123, "email": "private@example.org", "body": "private body"}})


class CollectorTest(unittest.TestCase):
    def test_events_validate_and_redact_before_storage(self):
        parsed = parse_event(event("/join/secret-invite?token=private@example.org"))
        self.assertEqual(parsed["path"], "/join/:redacted")
        self.assertNotIn("private", json.dumps(parsed))
        self.assertNotIn("body", parsed)
        self.assertEqual(safe_path("/users/private@example.org/avatar"), "/users/:redacted/avatar")
        self.assertEqual(safe_path("/rooms/:id/messages/:id"), "/rooms/:id/messages/:id")
        self.assertEqual(safe_path("https://secret.example/token"), "/:unknown")
        for line in ("ordinary log", event(status=99), event(duration=float("nan")), event(duration=-1), event(duration=True)):
            self.assertIsNone(parse_event(line))

    def test_restart_keeps_totals_and_deduplicates_replayed_log(self):
        with tempfile.TemporaryDirectory() as root:
            directory = Path(root)
            collector = Collector("example", directory / "storage", directory / "metrics")
            first = event(status=503, duration=251)
            second = event(at="2026-10-03T12:00:00.123456790Z")
            collector.ingest(first)
            collector.ingest(first)
            collector.ingest(second)
            with patch.object(collector, "sample_system", return_value=({"rss_bytes": 4096, "cpu_percent": None}, {})), patch("collector.os.chown"):
                collector.sample()
            self.assertEqual(collector.snapshot["requests"]["total"], 2)
            self.assertEqual(collector.snapshot["requests"]["errors"], 1)
            self.assertIn('le="0.5"} 1', collector.metrics)
            self.assertIn('le="0.25"} 0', collector.metrics)
            self.assertNotIn("private", collector.metrics)
            resumed = Collector("example", directory / "storage", directory / "metrics")
            resumed.ingest(first)
            resumed.ingest(second)
            self.assertEqual(resumed.state["total"], 2)
            resumed.ingest(event(at="2026-10-03T12:00:00.123456791Z"))
            self.assertEqual(resumed.state["total"], 3)
            snapshot = json.loads((directory / "storage/runtime_stats.json").read_text())
            self.assertEqual(snapshot["system"]["rss_bytes"], 4096)
            self.assertIsNone(snapshot["system"]["cpu_percent"])
            self.assertEqual(os.stat(directory / "storage/runtime_stats.json").st_mode & 0o777, 0o640)

    def test_series_and_request_history_are_bounded(self):
        with tempfile.TemporaryDirectory() as root:
            collector = Collector("example", root, root)
            for index in range(1200):
                collector.ingest(event(path=f"/rooms/:route_{'a' * (index % 30 + 1)}/{':id/' * (index // 30 + 1)}", status=200 + index % 300, at=f"2026-10-03T12:00:00.{index:09}Z"))
            self.assertLessEqual(len(collector.state["series"]), 517)
            self.assertEqual(collector.state["total"], 1200)
            self.assertEqual(len(collector.recent), 50)
            self.assertEqual(len(collector.seen), 1200)

    def test_database_is_read_only_and_returns_counts_without_contents(self):
        with tempfile.TemporaryDirectory() as root:
            path = Path(root) / "production.sqlite3"
            with closing(sqlite3.connect(path)) as database:
                database.execute("PRAGMA journal_mode=WAL")
                database.execute("CREATE TABLE users (email TEXT)")
                database.execute("INSERT INTO users VALUES ('private@example.org')")
                database.commit()
                stats = database_stats(root)
                self.assertEqual(stats["counts"], {"users": 1})
                self.assertGreater(stats["bytes"], 0)
                self.assertNotIn("private", json.dumps(stats))
                self.assertEqual(database.execute("SELECT email FROM users").fetchone()[0], "private@example.org")

    def test_exporter_binds_loopback_and_serves_valid_json_and_metrics(self):
        with tempfile.TemporaryDirectory() as root:
            collector = Collector("example", root, root)
            server = serve(collector, 0)
            self.assertEqual(server.server_address[0], "127.0.0.1")
            thread = threading.Thread(target=server.serve_forever, daemon=True)
            thread.start()
            try:
                base = f"http://127.0.0.1:{server.server_address[1]}"
                with urllib.request.urlopen(base + "/metrics") as response:
                    self.assertEqual(response.status, 200)
                    self.assertEqual(response.headers["Cache-Control"], "no-store")
                    self.assertIn("campfire_up 0", response.read().decode())
                with urllib.request.urlopen(base + "/snapshot") as response:
                    self.assertFalse(json.load(response)["available"])
            finally:
                server.shutdown()
                server.server_close()
                thread.join(timeout=2)

    def test_host_cpu_delta_memory_and_load(self):
        with tempfile.TemporaryDirectory() as root:
            proc = Path(root)
            (proc / "stat").write_text("cpu  10 0 10 80 0 0 0 0 0 0\n")
            (proc / "meminfo").write_text("MemTotal: 1000 kB\nMemAvailable: 400 kB\n")
            collector = Collector("example", root, root)
            with patch("collector.os.getloadavg", return_value=(0.2, 0.3, 0.4)):
                self.assertIsNone(collector.sample_host(proc)["host_cpu_percent"])
                (proc / "stat").write_text("cpu  20 0 20 160 0 0 0 0 0 0\n")
                sample = collector.sample_host(proc)
            self.assertAlmostEqual(sample["host_cpu_percent"], 20)
            self.assertEqual(sample["host_memory_total_bytes"], 1024000)
            self.assertEqual(sample["host_memory_available_bytes"], 409600)
            self.assertEqual(sample["load_1m"], 0.2)

    def test_linux_proc_parser_handles_spaces_in_process_name(self):
        with tempfile.TemporaryDirectory() as root:
            proc = Path(root)
            pid = proc / "123"
            (pid / "fd").mkdir(parents=True)
            (pid / "fd/0").touch()
            (pid / "status").write_text("Name:\tcampfire\nVmRSS:\t42 kB\nThreads:\t8\n")
            fields = ["S"] + ["0"] * 20
            fields[11], fields[12] = "20", "7"
            (pid / "stat").write_text("123 (native campfire) " + " ".join(fields))
            stats = process_stats(123, proc)
            self.assertEqual(stats["ticks"], 27)
            self.assertEqual(stats["rss_bytes"], 42 * 1024)
            self.assertEqual(stats["threads"], 8)
            self.assertEqual(stats["open_fds"], 1)


if __name__ == "__main__":
    unittest.main()
