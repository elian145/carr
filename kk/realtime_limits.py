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

  **Capacity is spent on conversations, not on logged-in users.** The app opens
  one socket per signed-in session, but a socket only matters while its user
  is inside a chat conversation (text is always sent over REST; offline users
  get FCM push). A socket that has joined no conversation room is *idle*:
  it is released after ``idle_release_s`` and is the first thing preempted when
  the total ceiling is reached, so the ceiling bounds simultaneously ENGAGED
  chat users instead of everyone who has the app open. Released sockets get a
  ``connection_released`` event; the client does not auto-reconnect and simply
  reconnects when the user opens a conversation.
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
    # Seconds a socket with no joined conversation may stay connected
    # (0 disables the idle sweep entirely).
    idle_release_s: int = 120
    # Same, for credential-less sockets (they can never join a conversation).
    guest_idle_s: int = 30
    # An idle socket must be at least this old before a new connection may
    # preempt it (prevents connect/evict thrash at the ceiling).
    preempt_min_idle_s: int = 15


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
        idle_release_s=_env_int(env, "SOCKETIO_IDLE_RELEASE_SECONDS", 120, minimum=0),
        guest_idle_s=_env_int(env, "SOCKETIO_GUEST_IDLE_SECONDS", 30, minimum=0),
        preempt_min_idle_s=_env_int(env, "SOCKETIO_PREEMPT_MIN_IDLE_SECONDS", 15),
    )


@dataclass
class Admission:
    refused: str | None = None
    # Older sockets of the SAME user dropped to respect the per-user cap.
    evict: list[str] = field(default_factory=list)
    # Idle sockets (of anyone) released to make room under the total ceiling.
    released: list[str] = field(default_factory=list)


@dataclass
class _Conn:
    user_id: str | None
    ip: str
    idle_since: float
    rooms: set = field(default_factory=set)


class ConnectionRegistry:
    """Tracks live sockets and decides whether a new one may connect."""

    def __init__(self, limits: SocketLimits, clock=time.monotonic):
        self.limits = limits
        self._clock = clock
        self._lock = threading.Lock()
        # sid -> _Conn; insertion order == connect order.
        self._conns: dict[str, _Conn] = {}

    # -- introspection (tests / health) ---------------------------------
    def total(self) -> int:
        with self._lock:
            return len(self._conns)

    def guests(self) -> int:
        with self._lock:
            return sum(1 for c in self._conns.values() if c.user_id is None)

    def user_sids(self, user_id: str) -> list[str]:
        with self._lock:
            return [s for s, c in self._conns.items() if c.user_id == user_id]

    def engaged(self) -> int:
        """Sockets currently inside at least one conversation room."""
        with self._lock:
            return sum(1 for c in self._conns.values() if c.rooms)

    def is_engaged(self, sid: str) -> bool:
        with self._lock:
            c = self._conns.get(sid)
            return bool(c and c.rooms)

    # -- engagement -------------------------------------------------------
    def note_room(self, sid: str, room: str, joined: bool) -> None:
        with self._lock:
            c = self._conns.get(sid)
            if c is None:
                return
            if joined:
                c.rooms.add(room)
            else:
                c.rooms.discard(room)
                if not c.rooms:
                    c.idle_since = self._clock()

    def touch(self, sid: str) -> None:
        """Conversation-scoped activity (opening a thread that has no messages
        yet, typing): restart the idle clock without engaging the socket."""
        with self._lock:
            c = self._conns.get(sid)
            if c is not None:
                c.idle_since = self._clock()

    # -- admission --------------------------------------------------------
    def admit(self, sid: str, ip: str, user_id: str | None) -> Admission:
        """Register ``sid`` or refuse it.

        On success the returned ``evict`` / ``released`` list sids that were
        already dropped from the registry and must be disconnected by the
        caller.
        """
        lim = self.limits
        now = self._clock()
        with self._lock:
            if sid in self._conns:
                return Admission()
            evict: list[str] = []
            released: list[str] = []
            if user_id is not None:
                mine = [s for s, c in self._conns.items() if c.user_id == user_id]
                overflow = len(mine) - lim.max_per_user + 1
                if overflow > 0:
                    evict = mine[:overflow]
            else:
                guests = [c for c in self._conns.values() if c.user_id is None]
                if len(guests) >= lim.max_guests_total:
                    return Admission(refused=REFUSE_SERVER_BUSY)
                if sum(1 for c in guests if c.ip == ip) >= lim.max_guests_per_ip:
                    return Admission(refused=REFUSE_TOO_MANY_FROM_ADDRESS)
            if len(self._conns) - len(evict) >= lim.max_total:
                victim = None
                if user_id is not None:  # a guest never preempts anyone
                    victim = self._preempt_candidate(now, set(evict))
                if victim is None:
                    return Admission(refused=REFUSE_SERVER_BUSY)
                released.append(victim)
            for s in evict + released:
                self._conns.pop(s, None)
            self._conns[sid] = _Conn(user_id=user_id, ip=ip, idle_since=now)
            return Admission(evict=evict, released=released)

    def _preempt_candidate(self, now: float, skip: set) -> str | None:
        """Oldest idle socket (guests first) that has been idle long enough."""
        best = None
        for pass_guests in (True, False):
            for s, c in self._conns.items():
                if s in skip or c.rooms:
                    continue
                if (c.user_id is None) != pass_guests:
                    continue
                if now - c.idle_since < self.limits.preempt_min_idle_s:
                    continue
                best = s
                break
            if best is not None:
                return best
        return None

    # -- idle sweep -------------------------------------------------------
    def idle_sids(self) -> list[str]:
        """Sockets past their idle allowance (not removed; caller releases)."""
        lim = self.limits
        now = self._clock()
        out: list[str] = []
        with self._lock:
            for s, c in self._conns.items():
                if c.rooms:
                    continue
                allowance = lim.guest_idle_s if c.user_id is None else lim.idle_release_s
                if allowance <= 0:
                    continue
                if now - c.idle_since >= allowance:
                    out.append(s)
        return out

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
