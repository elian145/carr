"""Resource limits for Socket.IO connections and events (audit C-1).

Why this exists
---------------
Production runs Gunicorn ``gthread`` with ``threading`` Socket.IO (see
``gunicorn.conf.py``). In that mode **every open WebSocket pins one Gunicorn
worker thread for the whole life of the connection**, and the worker had only
4 threads by default. Four idle (or hostile) sockets therefore starved the
entire REST API, and nothing capped how many sockets one user / address could
open, how fast ``send_message`` could be called (the REST equivalent is limited
to 120 per 10 minutes; the socket path had no limit at all), or how large a
single Socket.IO frame / JSON body could be.

This module is deliberately framework-free so it is unit-testable:

* :class:`ConnectionRegistry` -- admission control. Authenticated users are
  limited to ``max_per_user`` sockets (the OLDEST is evicted, so a legitimate
  reconnect while a zombie socket lingers never locks the user out); guests are
  limited per address and in total; every connection counts against a total
  that always leaves threads free for HTTP.
* :class:`EventRateLimiter` -- in-process sliding-window limiter for socket
  events (per socket and per user).

Both are per-process (the deployment is one worker; see ``gunicorn.conf.py``).
All limits are overridable by environment variable.
"""

from __future__ import annotations

import os
import threading
import time
from collections import deque
from dataclasses import dataclass, field
from typing import Mapping

# Mirrors gunicorn.conf.py (kk.socketio_deploy.DEFAULT_GUNICORN_THREADS).
from .socketio_deploy import resolve_gunicorn_threads

REFUSE_SERVER_BUSY = "server_busy"
REFUSE_TOO_MANY_FROM_ADDRESS = "too_many_connections"


def _env_int(env: Mapping[str, str], name: str, default: int, *, minimum: int = 1) -> int:
    raw = (env.get(name) or "").strip()
    if not raw:
        return default
    try:
        return max(minimum, int(raw))
    except ValueError:
        return default


@dataclass(frozen=True)
class SocketLimits:
    max_total: int
    max_guests_total: int
    max_guests_per_ip: int
    max_per_user: int


def default_max_total(threads: int) -> int:
    """Sockets allowed in total: always leave at least half the threads (and
    never fewer than 8) for ordinary HTTP requests."""
    reserved = max(8, threads // 2)
    return max(1, threads - reserved)


def load_limits(env: Mapping[str, str] | None = None) -> SocketLimits:
    env = os.environ if env is None else env
    threads = resolve_gunicorn_threads(env.get("GUNICORN_THREADS"))
    max_total = _env_int(env, "SOCKETIO_MAX_CONNECTIONS", default_max_total(threads))
    return SocketLimits(
        max_total=max_total,
        max_guests_total=_env_int(
            env, "SOCKETIO_MAX_GUEST_CONNECTIONS", max(1, max_total // 4)
        ),
        max_guests_per_ip=_env_int(env, "SOCKETIO_MAX_GUESTS_PER_IP", 2),
        max_per_user=_env_int(env, "SOCKETIO_MAX_CONNECTIONS_PER_USER", 5),
    )


@dataclass
class Admission:
    refused: str | None = None
    evict: list[str] = field(default_factory=list)


class ConnectionRegistry:
    """Tracks live sockets and decides whether a new one may connect."""

    def __init__(self, limits: SocketLimits):
        self.limits = limits
        self._lock = threading.Lock()
        # sid -> (user_id | None, ip); insertion order == connect order.
        self._conns: dict[str, tuple[str | None, str]] = {}

    # -- introspection (tests / health) ---------------------------------
    def total(self) -> int:
        with self._lock:
            return len(self._conns)

    def guests(self) -> int:
        with self._lock:
            return sum(1 for u, _ in self._conns.values() if u is None)

    def user_sids(self, user_id: str) -> list[str]:
        with self._lock:
            return [s for s, (u, _) in self._conns.items() if u == user_id]

    # -- admission --------------------------------------------------------
    def admit(self, sid: str, ip: str, user_id: str | None) -> Admission:
        """Register ``sid`` or refuse it.

        On success the returned ``evict`` lists older sids of the same user
        that were already dropped from the registry and must be disconnected
        by the caller.
        """
        lim = self.limits
        with self._lock:
            if sid in self._conns:
                return Admission()
            evict: list[str] = []
            if user_id is not None:
                mine = [s for s, (u, _) in self._conns.items() if u == user_id]
                overflow = len(mine) - lim.max_per_user + 1
                if overflow > 0:
                    evict = mine[:overflow]
            else:
                guests = [(s, i) for s, (u, i) in self._conns.items() if u is None]
                if len(guests) >= lim.max_guests_total:
                    return Admission(refused=REFUSE_SERVER_BUSY)
                if sum(1 for _, i in guests if i == ip) >= lim.max_guests_per_ip:
                    return Admission(refused=REFUSE_TOO_MANY_FROM_ADDRESS)
            if len(self._conns) - len(evict) >= lim.max_total:
                return Admission(refused=REFUSE_SERVER_BUSY)
            for s in evict:
                self._conns.pop(s, None)
            self._conns[sid] = (user_id, ip)
            return Admission(evict=evict)

    def release(self, sid: str | None) -> bool:
        if not sid:
            return False
        with self._lock:
            return self._conns.pop(sid, None) is not None


class EventRateLimiter:
    """Sliding-window limiter keyed by an arbitrary string."""

    _SWEEP_AT = 20000

    def __init__(self, clock=time.monotonic):
        self._clock = clock
        self._lock = threading.Lock()
        self._hits: dict[str, deque] = {}

    def allow(self, key: str, limit: int, window_s: float) -> tuple[bool, int]:
        """Record one hit. Returns ``(allowed, retry_after_seconds)``."""
        now = self._clock()
        with self._lock:
            dq = self._hits.get(key)
            if dq is None:
                if len(self._hits) >= self._SWEEP_AT:
                    self._sweep(now, window_s)
                dq = self._hits[key] = deque()
            cutoff = now - window_s
            while dq and dq[0] <= cutoff:
                dq.popleft()
            if len(dq) >= limit:
                retry = max(1, int(dq[0] + window_s - now) + 1)
                return False, retry
            dq.append(now)
            return True, 0

    def forget_prefix(self, prefix: str) -> None:
        with self._lock:
            for k in [k for k in self._hits if k.startswith(prefix)]:
                self._hits.pop(k, None)

    def size(self) -> int:
        with self._lock:
            return len(self._hits)

    def _sweep(self, now: float, window_s: float) -> None:
        # Called with the lock held. Drop buckets whose newest hit is stale
        # (the longest window we use is 10 minutes).
        horizon = now - max(window_s, 600.0)
        for k in [k for k, dq in self._hits.items() if not dq or dq[-1] <= horizon]:
            self._hits.pop(k, None)
