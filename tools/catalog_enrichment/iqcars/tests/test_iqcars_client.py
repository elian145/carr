"""Client + extractor behaviour against a LOCAL test server (no internet): cache-first, resume, stop-on-pushback, pacing."""
import json
import sys
import tempfile
import threading
import time
import unittest
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import extract_iqcars as X  # noqa: E402
import iqcars_client as C  # noqa: E402


class Srv:
    def __init__(self):
        self.hits, self.paths, self.status_for = 0, [], {}  # status_for: substring -> status
        outer = self

        class H(BaseHTTPRequestHandler):
            protocol_version = "HTTP/1.1"

            def log_message(self, *a):
                pass

            def do_GET(self):
                outer.hits += 1
                outer.paths.append(self.path)
                st = next((s for k, s in outer.status_for.items() if k in self.path), 200)
                body = json.dumps({"Cylinders": [{"ID": 1, "CylinderNameen": "4 cylinder"}], "Engines": [], "path": self.path}).encode()
                self.send_response(st)
                if st == 429:
                    self.send_header("Retry-After", "120")
                self.send_header("Content-Type", "application/json")
                self.send_header("Content-Length", str(len(body)))
                self.end_headers()
                self.wfile.write(body)

        self.httpd = ThreadingHTTPServer(("127.0.0.1", 0), H)
        self.url = f"http://127.0.0.1:{self.httpd.server_address[1]}/api/"
        threading.Thread(target=self.httpd.serve_forever, daemon=True).start()

    def stop(self):
        self.httpd.shutdown()
        self.httpd.server_close()


class ClientBase(unittest.TestCase):
    def setUp(self):
        self.srv = Srv()
        self._old = C.BASE_URL
        C.BASE_URL = self.srv.url
        self.tmp = tempfile.TemporaryDirectory()
        self.cache = Path(self.tmp.name) / "raw" / "cache"

    def tearDown(self):
        C.BASE_URL = self._old
        self.srv.stop()
        self.tmp.cleanup()

    def client(self, **kw):
        c = C.IqCarsClient(self.cache, **kw)
        c.delay_s = 0.0  # tests only: the production floor (0.5 s) is asserted separately
        return c


class CacheFirst(ClientBase):
    def test_cached_response_never_requested_again(self):
        c = self.client()
        a, from_cache = c.get("cylinder_engine", model_id=7)
        self.assertFalse(from_cache)
        b, from_cache = c.get("cylinder_engine", model_id=7)
        self.assertTrue(from_cache)
        self.assertEqual(a, b)
        self.assertEqual(self.srv.hits, 1)
        self.assertEqual((c.network_requests, c.cache_hits, c.successes), (1, 1, 1))

    def test_pre_seeded_cache_means_zero_network(self):
        self.cache.mkdir(parents=True)
        (self.cache / "cylinder_engine_model_9.json").write_bytes(b'{"Cylinders": [], "Engines": []}')
        c = self.client()
        data, cached = c.get("cylinder_engine", model_id=9)
        self.assertTrue(cached)
        self.assertEqual(self.srv.hits, 0)

    def test_cache_stores_verbatim_bytes(self):
        c = self.client()
        c.get("cylinder_engine", model_id=3)
        raw = (self.cache / "cylinder_engine_model_3.json").read_bytes()
        self.assertEqual(json.loads(raw)["path"].split("ModelId=")[1], "3")

    def test_offline_miss_raises_without_network(self):
        c = self.client(offline=True)
        with self.assertRaises(C.StopRequested):
            c.get("cylinder_engine", model_id=1)
        self.assertEqual(self.srv.hits, 0)

    def test_production_pacing_floor(self):
        self.assertGreaterEqual(C.IqCarsClient(self.cache, delay_s=0.0).delay_s, 0.5)
        c = C.IqCarsClient(self.cache, delay_s=0.5)
        t0 = time.monotonic()
        c.get("cylinder_engine", model_id=1)
        c.get("cylinder_engine", model_id=2)
        self.assertGreaterEqual(time.monotonic() - t0, 0.45)

    def test_only_one_connection_is_reused(self):
        c = self.client()
        for i in range(4):
            c.get("cylinder_engine", model_id=i)
        self.assertEqual(self.srv.hits, 4)
        self.assertIsNotNone(c._conn)  # still the same persistent connection object
        c.close()


class StopOnPushback(ClientBase):
    def test_stop_without_retry_or_cache_write(self):
        for st in (401, 403, 429, 500, 502, 503):
            with self.subTest(status=st):
                self.srv.hits = 0
                self.srv.status_for = {"ModelId=55": st}
                c = self.client()
                with self.assertRaises(C.StopRequested) as cm:
                    c.get("cylinder_engine", model_id=55)
                self.assertIn(str(st), str(cm.exception))
                self.assertEqual(self.srv.hits, 1, "must not retry")
                self.assertFalse((self.cache / "cylinder_engine_model_55.json").exists())
                self.assertEqual(c.failures[0]["status"], st)
                self.assertEqual(c.status_counts, {str(st): 1})

    def test_429_records_retry_after(self):
        self.srv.status_for = {"ModelId=1": 429}
        c = self.client()
        with self.assertRaises(C.StopRequested):
            c.get("cylinder_engine", model_id=1)
        self.assertEqual(c.failures[0]["retry_after"], "120")

    def test_max_requests_cap(self):
        c = self.client(max_requests=2)
        c.get("cylinder_engine", model_id=1)
        c.get("cylinder_engine", model_id=2)
        with self.assertRaises(C.StopRequested):
            c.get("cylinder_engine", model_id=3)
        self.assertEqual(self.srv.hits, 2)

    def test_connection_refused_stops(self):
        C.BASE_URL = "http://127.0.0.1:1/api/"  # nothing listens here
        c = self.client()
        with self.assertRaises(C.StopRequested):
            c.get("cylinder_engine", model_id=1)
        self.assertIsNone(c.failures[0]["status"])


def _write_initial(cache: Path, n_models: int):
    cache.mkdir(parents=True, exist_ok=True)
    models = [{"ID": 100 + i, "ModelNameen": f"M{i}", "ModelSFXes": []} for i in range(n_models)]
    data = {"FilterConfig": {"Brands": [{"ID": 1, "BrandNameen": "B", "Models": models}]}}
    (cache / "app_initial_data_en.json").write_text(json.dumps(data), encoding="utf-8")


class ResumeBehaviour(ClientBase):
    def _patch_extractor(self):
        self._saved = (X.RAW_DIR, X.CACHE_DIR, X.CATALOG_PATH)
        X.RAW_DIR, X.CACHE_DIR, X.CATALOG_PATH = self.cache.parent, self.cache, self.cache.parent / "iqcars_catalog.json"
        self.addCleanup(lambda: setattr(X, "RAW_DIR", self._saved[0]) or setattr(X, "CACHE_DIR", self._saved[1]) or
                        setattr(X, "CATALOG_PATH", self._saved[2]))

    def test_bulk_stops_on_429_then_resumes_without_rerequesting(self):
        self._patch_extractor()
        _write_initial(self.cache, 5)
        self.srv.status_for = {"ModelId=103": 429}  # 4th model pushes back
        args = type("A", (), {"confirm_bulk": True, "delay": 0.5, "max_requests": 100, "brands": "", "limit": 0})()
        old_floor = C.IqCarsClient.__init__

        def fast_init(self_, *a, **k):  # keep production floor for the real class, shorten only inside this test
            old_floor(self_, *a, **k)
            self_.delay_s = 0.0
        C.IqCarsClient.__init__ = fast_init
        self.addCleanup(lambda: setattr(C.IqCarsClient, "__init__", old_floor))
        self.assertEqual(X.cmd_bulk(args), 3)  # stopped
        self.assertEqual(sorted(p.name for p in self.cache.glob("cylinder_engine_model_*.json")),
                         [f"cylinder_engine_model_{i}.json" for i in (100, 101, 102)])
        first_hits = self.srv.hits
        self.assertEqual(first_hits, 4)  # 3 ok + the 429, no retry
        self.srv.status_for = {}  # server recovers
        self.srv.paths.clear()
        self.assertEqual(X.cmd_bulk(args), 0)
        # only the 2 missing models were requested; the 3 cached ones were not requested again
        self.assertEqual(sorted(self.srv.paths), sorted(f"/api/publicCar/cylinder-and-engine-and-specification?ModelId={i}" for i in (103, 104)))
        runs = [json.loads(line) for line in (self.cache.parent / "run_summaries.jsonl").read_text().splitlines()]
        self.assertEqual(len(runs), 2)
        self.assertTrue(runs[0]["stopped"])
        self.assertEqual(runs[0]["status_codes"], {"200": 3, "429": 1})
        self.assertEqual(runs[0]["skipped_models_not_fetched"], [103, 104])
        self.assertFalse(runs[1]["stopped"])
        self.assertEqual(runs[1]["cache_hits"], 3 + 1)  # 3 models + initial_data

    def test_bulk_requires_confirm_flag(self):
        self._patch_extractor()
        _write_initial(self.cache, 2)
        args = type("A", (), {"confirm_bulk": False, "delay": 1.5, "max_requests": 10, "brands": "", "limit": 0})()
        self.assertEqual(X.cmd_bulk(args), 2)
        self.assertEqual(self.srv.hits, 0)


if __name__ == "__main__":
    unittest.main()
