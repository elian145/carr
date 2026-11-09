"""WSGI edge guard for ``/socket.io`` (audit C-1, second layer).

Why this exists
---------------
``kk.realtime_limits.ConnectionRegistry`` only counts sockets that reached the
Socket.IO ``connect`` handler. Under Gunicorn ``gthread`` every open Engine.IO
transport pins a worker thread *before* that handler runs, and keeps it after a
refusal, so an attacker could freeze the REST API without ever being counted:

* open N raw websockets (or long-poll sessions) and never send the Socket.IO
  CONNECT packet (``connect`` is never called);
* connect, get ``CONNECT_ERROR`` (cap / bad token) and simply keep the transport.

Reproduced on real Gunicorn with ``GUNICORN_THREADS=32``: 32 such connections
made ``/api/cars`` time out. This module closes that gap with three small,
independent mechanisms (kept deliberately minimal):

1. **Thread ceiling** -- every ``/socket.io`` request holds one slot for as long
   as its WSGI response is open (i.e. exactly while it pins a thread). Above
   ``edge_limit`` the request gets a cheap ``503`` instead of a thread. The
   limit never exceeds ``threads - EDGE_HTTP_RESERVED_THREADS`` so the REST API
   always keeps threads, whatever ``GUNICORN_THREADS`` is.
2. **No anonymous sessions** -- a new session / websocket upgrade must carry a
   *signed* access JWT (signature only, no DB), otherwise ``401`` before any
   Engine.IO session exists. Expired-but-signed tokens pass so the F-36
   ``token_expired`` -> refresh protocol is unchanged. The mobile app never
   connects without a token. ``SOCKETIO_ALLOW_ANONYMOUS=1`` re-enables guests.
3. **Orphan reaper** -- Engine.IO sessions that never completed (or lost) their
   Socket.IO connection for ``SOCKETIO_AUTH_DEADLINE_SECONDS`` (default 10) are
   closed, returning the thread.

State is per process, matching the supported single-worker deployment.
"""

from __future__ import annotations

import json
import logging
import os
import threading
import time
import urllib.parse
from dataclasses import dataclass
from typing import Any, Callable, Mapping

from .socket_account_admission import (
    ACCOUNT_KEY,
    BAD_TOKENS,
    BUCKET_LIVE,
    BUCKET_RESTRICTED,
    ESTABLISHED_KEY,
    IDENTITY_KEY,
    REFUSE_ACCOUNT_BUSY,
    REFUSED_KEY,
    AccountLedger,
    Identity,
    shutdown_transport,
)
from .socketio_deploy import resolve_gunicorn_threads

logger = logging.getLogger(__name__)

EXTENSION_KEY = "carnet_socket_edge"
REFUSE_AUTH = "authentication_required"
REFUSE_TOKEN_IN_QUERY = "token_in_query"
REFUSE_BUSY = "server_busy"

#: threads that realtime traffic may never take from the REST API
EDGE_HTTP_RESERVED_THREADS = 2

_TRUE = ("1", "true", "yes", "on")


def _env_float(env: Mapping[str, str], name: str, default: float) -> float:
    raw = (env.get(name) or "").strip()
    if not raw:
        return default
    try:
        return max(0.0, float(raw))
    except ValueError:
        return default


@dataclass(frozen=True)
class EdgeConfig:
    threads: int
    #: max ``/socket.io`` requests in flight (0 => every one is refused with 503)
    edge_limit: int
    allow_anonymous: bool
    auth_deadline: float  # seconds; 0 disables the orphan reaper
    reaper_interval: float
    # N-2 per-account admission (kk/socket_account_admission.py). 0 disables the
    # live-account cap (the restricted buckets below are only used with a ledger).
    account_limit: int = 0
    #: slots one account may hold with an expired / known-dead token
    restricted_per_account: int = 2
    #: restricted slots across ALL accounts (0 = unlimited)
    restricted_total: int = 0
    #: a refused connect (CONNECT_ERROR) keeps its transport this long, not auth_deadline
    refused_grace: float = 3.0
    #: a non-websocket request still in flight after this long is a stalled handshake
    stall_seconds: float = 60.0


def compute_edge_limit(threads: int, max_total: int) -> int:
    """``max_total`` sockets plus a small transient overflow (handshakes, sockets
    being replaced), never more than ``threads - EDGE_HTTP_RESERVED_THREADS``."""
    overflow = max(2, max_total // 4)
    return max(0, min(max_total + overflow, threads - EDGE_HTTP_RESERVED_THREADS))


def compute_account_limit(edge_limit: int, max_per_user: int) -> int:
    """Edge slots ONE account may hold: its per-user socket cap plus one in-flight
    reconnect, but never more than a third of the edge limit (so three accounts
    can never exhaust it), and at least 2 (a reconnect needs a spare slot)."""
    return max(2, min(max_per_user + 1, edge_limit // 3))


def load_edge_config(
    env: Mapping[str, str] | None = None, *, max_total: int, max_per_user: int | None = None
) -> EdgeConfig:
    env = os.environ if env is None else env
    threads = resolve_gunicorn_threads(env.get("GUNICORN_THREADS"))
    edge_limit = compute_edge_limit(threads, max_total)
    if max_per_user is None:
        from .realtime_limits import load_limits

        max_per_user = load_limits(env).max_per_user
    raw_limit = (env.get("SOCKETIO_EDGE_MAX_PER_ACCOUNT") or "").strip()
    try:
        account_limit = max(0, int(raw_limit)) if raw_limit else compute_account_limit(edge_limit, max_per_user)
    except ValueError:
        account_limit = compute_account_limit(edge_limit, max_per_user)
    restricted_per_account = int(_env_float(env, "SOCKETIO_EDGE_RESTRICTED_PER_ACCOUNT", 2))
    return EdgeConfig(
        threads=threads,
        edge_limit=edge_limit,
        account_limit=account_limit,
        restricted_per_account=max(1, restricted_per_account),
        restricted_total=max(2, edge_limit // 4),
        refused_grace=_env_float(env, "SOCKETIO_EDGE_REFUSED_GRACE_SECONDS", 3.0),
        stall_seconds=_env_float(env, "SOCKETIO_EDGE_STALL_SECONDS", 60.0),
        allow_anonymous=(env.get("SOCKETIO_ALLOW_ANONYMOUS") or "").strip().lower() in _TRUE,
        auth_deadline=_env_float(env, "SOCKETIO_AUTH_DEADLINE_SECONDS", 10.0),
        reaper_interval=max(0.2, _env_float(env, "SOCKETIO_REAPER_INTERVAL_SECONDS", 2.0)),
    )


class SlotCounter:
    def __init__(self, limit: int):
        self.limit = limit
        self._lock = threading.Lock()
        self._n = 0

    def acquire(self) -> bool:
        with self._lock:
            if self._n >= self.limit:
                return False
            self._n += 1
            return True

    def release(self) -> None:
        with self._lock:
            self._n = max(0, self._n - 1)

    @property
    def in_flight(self) -> int:
        with self._lock:
            return self._n


AUTH_NONE, AUTH_INVALID, AUTH_OK = "none", "invalid", "ok"


def make_handshake_authenticator(
    app, allow_query_token: Callable[[], bool]
) -> Callable[[Any], tuple[str, str]]:
    """``authenticate(environ) -> (state, detail)``; signature check only."""

    def authenticate(environ) -> tuple[str, str]:
        raw = None
        header = (environ.get("HTTP_AUTHORIZATION") or "").strip()
        if header:
            parts = header.split(None, 1)
            if len(parts) != 2 or parts[0].lower() != "bearer" or not parts[1].strip():
                return AUTH_INVALID, REFUSE_AUTH
            raw = parts[1].strip()
        else:
            query = urllib.parse.parse_qs(environ.get("QUERY_STRING") or "")
            tok = (query.get("token") or [""])[0].strip()
            if tok:
                if not allow_query_token():
                    return AUTH_INVALID, REFUSE_TOKEN_IN_QUERY
                raw = tok
        if raw is None:
            return AUTH_NONE, REFUSE_AUTH
        try:
            from flask_jwt_extended import decode_token

            with app.app_context():
                claims = decode_token(raw, allow_expired=True)
        except Exception:
            return AUTH_INVALID, REFUSE_AUTH
        if claims.get("type") not in (None, "access") or not claims.get("sub"):
            return AUTH_INVALID, REFUSE_AUTH
        exp = claims.get("exp")
        # N-2: the signature-verified account, for per-account admission
        environ[IDENTITY_KEY] = Identity(
            sub=str(claims["sub"]),
            jti=str(claims["jti"]) if claims.get("jti") else None,
            exp=float(exp) if isinstance(exp, (int, float)) else None,
        )
        return AUTH_OK, ""

    return authenticate


def _refuse(start_response, status: str, code: str, message: str, retry_after: int | None = None):
    body = json.dumps({"code": code, "message": message}).encode("utf-8")
    headers = [
        ("Content-Type", "application/json"),
        ("Content-Length", str(len(body))),
        ("Cache-Control", "no-store"),
    ]
    if retry_after is not None:
        headers.append(("Retry-After", str(retry_after)))
    start_response(status, headers)
    return [body]


class _ReleasingIterable:
    """Releases the slot when the server closes the response (or on GC)."""

    def __init__(self, inner, release: Callable[[], None]):
        self._inner = inner
        self._release = release
        self._done = False

    def __iter__(self):
        return iter(self._inner)

    def close(self):
        try:
            close = getattr(self._inner, "close", None)
            if close is not None:
                close()
        finally:
            self._finish()

    def _finish(self):
        if not self._done:
            self._done = True
            self._release()

    def __del__(self):  # a server that forgets close() must not leak a slot
        try:
            self._finish()
        except Exception:  # pragma: no cover
            pass


class SocketEdgeMiddleware:
    def __init__(
        self,
        app,
        *,
        config: EdgeConfig,
        slots: SlotCounter,
        authenticate: Callable[[Any], tuple[str, str]],
        on_first_request: Callable[[], None] | None = None,
        prefix: str = "/socket.io",
        ledger: AccountLedger | None = None,
        session_env: Callable[[str], dict | None] | None = None,
        now: Callable[[], float] = time.time,
        on_evict: Callable[[Any], None] | None = None,
    ):
        self.app = app
        self.config = config
        self.slots = slots
        self.authenticate = authenticate
        self.on_first_request = on_first_request
        self.prefix = prefix.rstrip("/")
        #: N-2 per-account admission (``None`` = only the global ceiling)
        self.ledger = ledger
        #: ``sid -> handshake environ`` kept by python-socketio for each session
        self.session_env = session_env
        self._now = now
        #: closes an evicted ticket's session + transport (default: transport only)
        self.on_evict = on_evict or (lambda t: shutdown_transport(t.raw))

    def _account_ticket(self, environ, query, is_ws: bool, authenticated: bool):
        """Reserve the caller's per-account slot. ``(ticket, refusal_or_None)``."""
        identity = environ.pop(IDENTITY_KEY, None) if authenticated else None
        sid = (query.get("sid") or [""])[0]
        state_env = None
        if sid and self.session_env is not None:
            try:
                state_env = self.session_env(sid)
            except Exception:  # pragma: no cover - never block on a lookup
                state_env = None
        account = bucket = None
        protected = False
        owner = state_env.get(ACCOUNT_KEY) if isinstance(state_env, dict) else None
        if owner:
            bucket, account = owner  # the session's creator, not whoever sends the request
            protected = bool(state_env.get(ESTABLISHED_KEY))
        elif identity is not None:
            account = identity.sub
            bucket = (
                BUCKET_RESTRICTED
                if identity.expired(self._now()) or BAD_TOKENS.is_bad(identity)
                else BUCKET_LIVE
            )
            if not sid:
                state_env = environ  # python-socketio keeps this very dict per session
                environ[ACCOUNT_KEY] = (bucket, account)
        if account is None:
            return None, None  # unattributable (unknown sid / anonymous opt-in): global ceiling only
        raw = environ.get("gunicorn.socket") or environ.get("werkzeug.socket")
        ticket, victims = self.ledger.reserve(
            account, bucket, is_ws=is_ws, raw=raw, state_env=state_env, protected=protected
        )
        for v in victims:  # a legitimate reconnect replaces the account's oldest transport
            try:
                self.on_evict(v)
            except Exception:  # pragma: no cover - the new request must still be served
                logger.exception("socket edge guard: eviction failed")
                shutdown_transport(v.raw)
        if victims:
            logger.info(
                "socket edge guard: account at its limit; closed %d older transport(s)", len(victims)
            )
        if ticket is None:
            logger.info("socket edge guard: per-account limit reached (%s bucket)", bucket)
            return None, REFUSE_ACCOUNT_BUSY
        return ticket, None

    def __call__(self, environ, start_response):
        path = environ.get("PATH_INFO") or ""
        if path != self.prefix and not path.startswith(self.prefix + "/"):
            return self.app(environ, start_response)

        if self.on_first_request is not None:
            try:
                self.on_first_request()
            except Exception:  # pragma: no cover - never block a request on this
                logger.exception("socket edge guard: reaper start failed")

        query = urllib.parse.parse_qs(environ.get("QUERY_STRING") or "")
        is_ws = (query.get("transport") or ["polling"])[0] == "websocket"
        new_session = "sid" not in query
        preflight = (environ.get("REQUEST_METHOD") or "GET").upper() == "OPTIONS"

        if not preflight and (is_ws or new_session) and not self.config.allow_anonymous:
            state, code = self.authenticate(environ)
            if state != AUTH_OK:
                return _refuse(
                    start_response,
                    "401 Unauthorized",
                    code,
                    "A valid access token is required for realtime connections.",
                )

        ticket = None
        if self.ledger is not None and not preflight:
            ticket, refusal = self._account_ticket(
                environ, query, is_ws, authenticated=not self.config.allow_anonymous and (is_ws or new_session)
            )
            if refusal:
                return _refuse(
                    start_response,
                    "503 Service Unavailable",
                    refusal,
                    "Too many realtime connections for this account; retry shortly.",
                    retry_after=3,
                )

        if not self.slots.acquire():
            self.ledger.release(ticket) if self.ledger is not None else None
            return _refuse(
                start_response,
                "503 Service Unavailable",
                REFUSE_BUSY,
                "Realtime capacity is full; use HTTP polling and retry later.",
                retry_after=5,
            )

        def release() -> None:
            try:
                if self.ledger is not None:
                    self.ledger.release(ticket)
            finally:
                self.slots.release()

        try:
            result = self.app(environ, start_response)
        except BaseException:
            release()
            raise
        return _ReleasingIterable(result, release)


class OrphanReaper:
    """Closes Engine.IO sessions that hold a thread without a Socket.IO connection."""

    def __init__(self, socketio, config: EdgeConfig, clock: Callable[[], float] = time.monotonic):
        self.socketio = socketio
        self.config = config
        self._clock = clock
        self._orphan_since: dict[str, float] = {}
        self._lock = threading.Lock()
        self._started_pid: int | None = None
        self.closed_total = 0
        #: N-2: set by ``install_socket_edge_guard`` (stalled-request sweep)
        self.ledger: AccountLedger | None = None
        self.stalled_total = 0

    def ensure_started(self) -> None:
        if self.config.auth_deadline <= 0:
            return
        pid = os.getpid()
        if self._started_pid == pid:
            return
        with self._lock:
            if self._started_pid == pid:
                return
            self._started_pid = pid
            threading.Thread(target=self._run, name="socketio-orphan-reaper", daemon=True).start()

    def _run(self) -> None:
        while True:
            time.sleep(self.config.reaper_interval)
            try:
                self.scan_once()
            except Exception:  # pragma: no cover - keep the reaper alive
                logger.exception("socket orphan reaper scan failed")

    @staticmethod
    def _websocket_transport_socket(server, eio_sid: str):
        """Raw TCP socket of a *direct* websocket session, else ``None``.

        ``eio.disconnect`` only ends the Engine.IO session: under gthread the
        websocket request thread stays blocked in ``ws.receive()`` (still
        holding its edge slot and worker thread) until the ping timeout
        (~45 s). Shutting the transport socket down unblocks it at once.
        Polling-first sessions are skipped: their stored environ belongs to
        the first poll request, whose connection may be shared.
        """
        try:
            environ = (getattr(server, "environ", None) or {}).get(eio_sid) or {}
            query = urllib.parse.parse_qs(environ.get("QUERY_STRING") or "")
            if (query.get("transport") or [""])[0] != "websocket" or "sid" in query:
                return None
            return environ.get("gunicorn.socket") or environ.get("werkzeug.socket")
        except Exception:  # pragma: no cover - never break the reaper
            return None

    @staticmethod
    def _close_session(eio, eio_sid: str) -> None:
        """Close one Engine.IO session WITHOUT blocking the (single) reaper thread.

        ``eio.disconnect()`` closes with ``wait=True``, i.e. ``queue.join()`` until a
        consumer drains the CLOSE packet. An orphan with no pending poll has no
        consumer, so that call would hang the reaper and stall every later
        reap. ``close(wait=False)`` + removal is the same cleanup minus the wait.
        """
        session = eio.sockets.get(eio_sid)
        close = getattr(session, "close", None)
        if close is None:  # unknown engine implementation: use the public API
            eio.disconnect(eio_sid)
            return
        try:
            close(wait=False)
        finally:
            eio.sockets.pop(eio_sid, None)

    @staticmethod
    def _release_transport(raw) -> None:
        import socket as _socket

        try:
            raw.shutdown(_socket.SHUT_RDWR)
        except (OSError, AttributeError):
            pass  # already closed / not a real socket

    def _deadline_for(self, server, eio_sid: str) -> float:
        """A session whose ``connect`` was refused (CONNECT_ERROR) only needs its
        transport long enough for the client to read the reason (N-2: refusals
        must not keep a thread for the full auth deadline)."""
        deadline = self.config.auth_deadline
        try:
            env = (getattr(server, "environ", None) or {}).get(eio_sid) or {}
            if env.get(REFUSED_KEY):
                return min(deadline, self.config.refused_grace)
        except Exception:  # pragma: no cover
            pass
        return deadline

    def reap_stalled_requests(self) -> int:
        """Shut down non-websocket requests (handshake / long-poll / body read)
        that have been in flight far longer than Engine.IO ever holds one."""
        if self.ledger is None:
            return 0
        n = 0
        for t in self.ledger.stalled(self.config.stall_seconds):
            shutdown_transport(t.raw)
            n += 1
        if n:
            self.stalled_total += n
            logger.info("socket edge guard: shut down %d stalled request(s)", n)
        return n

    def scan_once(self) -> int:
        server = getattr(self.socketio, "server", None)
        if server is None:
            return 0
        try:
            self.reap_stalled_requests()
        except Exception:  # pragma: no cover - never break the reaper
            logger.exception("stalled request sweep failed")
        eio, manager = server.eio, server.manager
        now = self._clock()
        live = list(eio.sockets.keys())
        live_set = set(live)
        closed = 0
        for eio_sid in live:
            try:
                connected = manager.sid_from_eio_sid(eio_sid, "/") is not None
            except Exception:
                connected = False
            if connected:
                self._orphan_since.pop(eio_sid, None)
                continue
            since = self._orphan_since.setdefault(eio_sid, now)
            if now - since >= self._deadline_for(server, eio_sid):
                self._orphan_since.pop(eio_sid, None)
                # Read BEFORE disconnect: python-socketio forgets the request
                # environ as soon as the Engine.IO session is closed.
                raw = self._websocket_transport_socket(server, eio_sid)
                try:
                    self._close_session(eio, eio_sid)
                    closed += 1
                except Exception:  # pragma: no cover - already gone
                    logger.debug("orphan close failed", exc_info=True)
                if raw is not None:
                    self._release_transport(raw)
        for gone in [s for s in self._orphan_since if s not in live_set]:
            self._orphan_since.pop(gone, None)
        self.closed_total += closed
        if closed:
            logger.info("socket orphan reaper closed %d session(s) without a connection", closed)
        return closed


def install_socket_edge_guard(app, socketio, config: EdgeConfig) -> dict:
    """Wrap ``app.wsgi_app`` (call AFTER ``socketio.init_app``)."""
    from .socketio_handlers import _allow_socket_query_token

    slots = SlotCounter(config.edge_limit)
    reaper = OrphanReaper(socketio, config)
    ledger = AccountLedger(
        per_account=config.account_limit,
        restricted_per_account=config.restricted_per_account,
        restricted_total=config.restricted_total,
    )
    reaper.ledger = ledger

    def session_env(sid: str):
        server = getattr(socketio, "server", None)
        return (getattr(server, "environ", None) or {}).get(sid)

    def evict(ticket) -> None:
        """Close an evicted websocket's Engine.IO session (so the registry and
        the auth binding are released at once) AND its transport (so the
        gthread request thread parked in ``ws.receive()`` returns)."""
        server = getattr(socketio, "server", None)
        try:
            if server is not None and ticket.state_env is not None:
                for eio_sid, env in list(getattr(server, "environ", {}).items()):
                    if env is ticket.state_env:
                        OrphanReaper._close_session(server.eio, eio_sid)
                        break
        except Exception:  # pragma: no cover - already gone
            logger.debug("evicted session close failed", exc_info=True)
        finally:
            shutdown_transport(ticket.raw)

    app.wsgi_app = SocketEdgeMiddleware(
        app.wsgi_app,
        config=config,
        slots=slots,
        authenticate=make_handshake_authenticator(app, _allow_socket_query_token),
        on_first_request=reaper.ensure_started,
        ledger=ledger,
        session_env=session_env,
        on_evict=evict,
    )
    guard = {"config": config, "slots": slots, "reaper": reaper, "ledger": ledger}
    app.extensions[EXTENSION_KEY] = guard
    if config.edge_limit < 8:
        app.logger.warning(
            "socket edge guard: GUNICORN_THREADS=%s leaves room for only %s concurrent "
            "realtime connection(s); the rest are refused with 503 and the app uses REST "
            "polling. Set GUNICORN_THREADS=32 (default) for launch.",
            config.threads,
            config.edge_limit,
        )
    app.logger.info(
        "socket edge guard: threads=%s edge_limit=%s per_account=%s anonymous=%s auth_deadline=%ss",
        config.threads,
        config.edge_limit,
        config.account_limit,
        config.allow_anonymous,
        config.auth_deadline,
    )
    return guard
