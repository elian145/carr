#!/usr/bin/env python3
"""Polite, read-only, cache-first HTTP client for the IQ Cars *public* catalog endpoints.

Scope / safety rules (hard-coded, not configurable away):
  * GET only. No cookies, no tokens, no login, no spoofed app headers.
  * Only the endpoints in ENDPOINTS are ever requested (all are unauthenticated `publicCar/...` routes
    that the official app itself calls during normal use).
  * Every response is cached verbatim on disk; an identical request is never repeated.
  * Requests are spaced by `delay_s` (default 1.5 s) and capped by `max_requests` per run.
  * ANY non-200 answer (401/403/429/5xx/...) raises `StopRequested` immediately. There is no retry loop,
    no header rotation and no workaround: a 429 means "stop, wait, resume later" (the cache makes resume cheap).
"""
from __future__ import annotations

import http.client
import json
import os
import time
import urllib.parse
from datetime import datetime, timezone
from pathlib import Path

from canonical_io import NEWLINE

BASE_URL = "https://cp.iqcars.net/api/"
USER_AGENT = "CarNet-catalog-research/0.1 (read-only; low-rate; cache-first)"

# name -> (path template, cache filename template)
ENDPOINTS = {
    "initial_data": ("publicCar/App-Initial-Data-For-Android?categoryId=1&langCode={lang}", "app_initial_data_{lang}.json"),
    "cylinder_engine": ("publicCar/cylinder-and-engine-and-specification?ModelId={model_id}", "cylinder_engine_model_{model_id}.json"),
    "brand_new_cars": ("publiccar/BrandNewCars?LocationId={location_id}", "brandnewcars_loc{location_id}.json"),
    "brand_new_sfxes": ("PublicCar/BrandNewCarSFXes?BrandNewCarId={bnc_id}", "brandnewcar_sfxes_{bnc_id}.json"),
}


class StopRequested(RuntimeError):
    """Raised when the server pushes back (or a safety cap is hit). Callers must stop, not retry."""


class IqCarsClient:
    def __init__(self, cache_dir: Path, *, delay_s: float = 1.5, max_requests: int = 25,
                 offline: bool = False, timeout_s: float = 60.0):
        self.cache_dir = Path(cache_dir)
        self.cache_dir.mkdir(parents=True, exist_ok=True)
        self.log_path = self.cache_dir.parent / "request_log.jsonl"
        self.delay_s = max(0.5, float(delay_s))  # hard floor: never faster than 2 requests / second
        self.max_requests = int(max_requests)
        self.offline = offline
        self.timeout_s = timeout_s
        self.network_requests = 0
        self.cache_hits = 0
        self.successes = 0
        self.failures: list[dict] = []
        self.status_counts: dict[str, int] = {}
        self._last_request_ts = 0.0
        self._conn = None

    def close(self) -> None:
        if self._conn is not None:
            try:
                self._conn.close()
            finally:
                self._conn = None

    def stats(self) -> dict:
        return {"network_requests": self.network_requests, "cache_hits": self.cache_hits, "successful_responses": self.successes,
                "failures": self.failures, "status_codes": dict(self.status_counts)}

    # ------------------------------------------------------------------ public API
    def get(self, endpoint: str, **params) -> tuple[dict | list, bool]:
        """Return (parsed_json, from_cache). Cache first; network only on a miss."""
        path_t, cache_t = ENDPOINTS[endpoint]
        path = path_t.format(**params)
        cache_file = self.cache_dir / cache_t.format(**params)
        if cache_file.exists():
            self.cache_hits += 1
            return json.loads(cache_file.read_bytes().decode("utf-8")), True
        if self.offline:
            raise StopRequested(f"offline mode and no cache for {cache_file.name}")
        if self.network_requests >= self.max_requests:
            raise StopRequested(f"max_requests={self.max_requests} reached (raise --max-requests / use bulk mode)")
        body = self._fetch(path)
        tmp = cache_file.with_suffix(".tmp")
        tmp.write_bytes(body)
        os.replace(tmp, cache_file)
        return json.loads(body.decode("utf-8")), False

    # ------------------------------------------------------------------ internals
    def _fetch(self, path: str) -> bytes:
        wait = self.delay_s - (time.monotonic() - self._last_request_ts)
        if wait > 0 and self.network_requests > 0:
            time.sleep(wait)
        parts = urllib.parse.urlsplit(BASE_URL)
        status, body, retry_after = None, b"", None
        try:
            if self._conn is None:  # ONE persistent keep-alive connection (ordinary HTTP behaviour, fewer handshakes)
                cls = http.client.HTTPSConnection if parts.scheme == "https" else http.client.HTTPConnection
                self._conn = cls(parts.netloc, timeout=self.timeout_s)
            self._conn.request("GET", parts.path + path, headers={"User-Agent": USER_AGENT, "Accept": "application/json",
                                                                  "Connection": "keep-alive"})
            resp = self._conn.getresponse()
            status, body, retry_after = resp.status, resp.read(), resp.getheader("Retry-After")
            if resp.will_close:
                self.close()
        except (OSError, http.client.HTTPException) as e:  # network trouble: stop, never hammer / retry
            self.close()
            self._log(path, None, 0, note=f"network error: {e}")
            self.failures.append({"path": path, "status": None, "error": str(e)})
            raise StopRequested(f"network error for {path}: {e}")
        finally:
            self._last_request_ts = time.monotonic()
            self.network_requests += 1
        self._log(path, status, len(body), note=f"retry-after={retry_after}" if retry_after else "")
        self.status_counts[str(status)] = self.status_counts.get(str(status), 0) + 1
        if status != 200:
            self.failures.append({"path": path, "status": status, "retry_after": retry_after})
            raise StopRequested(
                f"HTTP {status} for {path} (Retry-After={retry_after}). Stopping; not retrying or working around. "
                f"Resume later: cached responses are kept."
            )
        self.successes += 1
        return body

    def _log(self, path: str, status, size: int, note: str = "") -> None:
        rec = {"ts": datetime.now(timezone.utc).isoformat(timespec="seconds"), "path": path, "status": status,
               "bytes": size}
        if note:
            rec["note"] = note
        with open(self.log_path, "a", encoding="utf-8", newline=NEWLINE) as f:
            f.write(json.dumps(rec) + "\n")
