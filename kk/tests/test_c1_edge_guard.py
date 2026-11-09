"""C-1 second layer: the WSGI edge guard (``kk.socket_edge_guard``).

The registry in ``kk.realtime_limits`` only sees sockets that reached the
Socket.IO ``connect`` handler. These tests cover what it cannot: Engine.IO
transports that pin a Gunicorn thread without ever being counted (anonymous
websocket / long-poll sessions that never send CONNECT, transports kept open
after a refusal), plus the fail-safe sizing when ``GUNICORN_THREADS`` is wrong.

Synthetic data only; no network.
"""

from __future__ import annotations

import gc
import os
import sys
import tempfile
from datetime import timedelta
from pathlib import Path

import pytest

_REPO_ROOT = Path(__file__).resolve().parents[2]
if str(_REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(_REPO_ROOT))

from kk.realtime_limits import default_max_total  # noqa: E402
from kk.socket_edge_guard import (  # noqa: E402
    EDGE_HTTP_RESERVED_THREADS,
    EdgeConfig,
    OrphanReaper,
    SlotCounter,
    SocketEdgeMiddleware,
    compute_edge_limit,
    load_edge_config,
    make_handshake_authenticator,
)


# ----------------------------------------------------------------------
# sizing: the REST API always keeps threads, whatever GUNICORN_THREADS is
# ----------------------------------------------------------------------


class TestEdgeSizing:
    def test_expected_production_value(self):
        cfg = load_edge_config({}, max_total=default_max_total(32))
        assert (cfg.threads, cfg.edge_limit) == (32, 20)  # 16 sockets + 4 overflow
        assert cfg.allow_anonymous is False

    def test_render_with_four_threads_fails_safe(self):
        """Render still has the old GUNICORN_THREADS=4: realtime is squeezed to
        what leaves HTTP two threads; everything else gets a cheap 503."""
        cfg = load_edge_config({"GUNICORN_THREADS": "4"}, max_total=default_max_total(4))
        assert default_max_total(4) == 1
        assert cfg.edge_limit == 2
        assert cfg.threads - cfg.edge_limit >= EDGE_HTTP_RESERVED_THREADS

    @pytest.mark.parametrize("threads", [1, 2, 3, 4, 6, 8, 16, 32, 64])
    @pytest.mark.parametrize("max_total", [0, 1, 16, 1000])
    def test_http_always_keeps_reserved_threads(self, threads, max_total):
        limit = compute_edge_limit(threads, max_total)
        assert limit >= 0
        assert threads - limit >= min(threads, EDGE_HTTP_RESERVED_THREADS)

    def test_oversized_socket_cap_is_clamped_to_the_thread_budget(self):
        assert compute_edge_limit(32, 1000) == 30

    def test_tiny_worker_refuses_all_realtime(self):
        assert compute_edge_limit(2, 1) == 0

    def test_anonymous_is_opt_in(self):
        on = load_edge_config({"SOCKETIO_ALLOW_ANONYMOUS": "true"}, max_total=16)
        assert on.allow_anonymous is True

    def test_auth_deadline_is_configurable_and_zero_disables(self):
        assert load_edge_config({}, max_total=16).auth_deadline == 10.0
        z = load_edge_config({"SOCKETIO_AUTH_DEADLINE_SECONDS": "0"}, max_total=16)
        assert z.auth_deadline == 0


# ----------------------------------------------------------------------
# middleware (fake inner app, real JWT verification)
# ----------------------------------------------------------------------


@pytest.fixture(scope="module")
def app():
    tmp = tempfile.TemporaryDirectory(prefix="carlist_c1e_", ignore_cleanup_errors=True)
    os.environ["APP_ENV"] = "testing"
    os.environ["SMS_PROVIDER"] = "console"
    os.environ["DB_PATH"] = os.path.join(tmp.name, "c1e.db")
    from kk.app_factory import create_app

    application, *_ = create_app()
    application._tmp = tmp  # keep the directory alive
    return application


def _token(app, *, expires=None, identity="pub-edge-1", claims=None):
    from flask_jwt_extended import create_access_token

    with app.app_context():
        return create_access_token(
            identity=identity, expires_delta=expires, additional_claims=claims or {}
        )


def _refresh_token(app):
    from flask_jwt_extended import create_refresh_token

    with app.app_context():
        return create_refresh_token(identity="pub-edge-1")


class _Inner:
    """Stand-in for the Socket.IO WSGI app; records calls, can stay 'open'."""

    def __init__(self):
        self.calls = 0
        self.closed = 0

    def __call__(self, environ, start_response):
        self.calls += 1
        start_response("200 OK", [("Content-Type", "text/plain")])
        outer = self

        class _Body:
            def __iter__(self):
                return iter([b"ok"])

            def close(self):
                outer.closed += 1

        return _Body()


def _env(qs="EIO=4&transport=websocket", *, token=None, method="GET", path="/socket.io/", headers=None):
    e = {
        "PATH_INFO": path,
        "QUERY_STRING": qs,
        "REQUEST_METHOD": method,
        "REMOTE_ADDR": "203.0.113.9",
    }
    if token:
        e["HTTP_AUTHORIZATION"] = f"Bearer {token}"
    e.update(headers or {})
    return e


def _call(mw, environ):
    box = {}

    def sr(status, headers, exc=None):
        box["status"] = status
        box["headers"] = dict(headers)

    body = mw(environ, sr)
    return box["status"], box["headers"], body


def _mw(app, *, limit=3, anonymous=False, query_token_ok=False):
    inner = _Inner()
    cfg = EdgeConfig(threads=32, edge_limit=limit, allow_anonymous=anonymous,
                     auth_deadline=10.0, reaper_interval=2.0)
    slots = SlotCounter(limit)
    mw = SocketEdgeMiddleware(
        inner,
        config=cfg,
        slots=slots,
        authenticate=make_handshake_authenticator(app, lambda: query_token_ok),
    )
    return mw, inner, slots


class TestEdgeAuthentication:
    def test_non_socket_paths_are_untouched(self, app):
        mw, inner, slots = _mw(app)
        status, _h, _b = _call(mw, _env(path="/api/cars", qs=""))
        assert status == "200 OK" and inner.calls == 1 and slots.in_flight == 0

    @pytest.mark.parametrize(
        "qs",
        ["EIO=4&transport=websocket", "EIO=4&transport=polling"],
    )
    def test_anonymous_session_is_refused_before_any_thread_is_used(self, app, qs):
        mw, inner, slots = _mw(app)
        status, headers, body = _call(mw, _env(qs))
        assert status.startswith("401")
        assert b"authentication_required" in b"".join(body)
        assert inner.calls == 0 and slots.in_flight == 0

    def test_garbage_unsigned_and_wrong_type_tokens_are_refused(self, app):
        mw, inner, _s = _mw(app)
        for tok in ("garbage", "a.b.c", _refresh_token(app)):
            status, _h, _b = _call(mw, _env(token=tok))
            assert status.startswith("401"), tok
        # a token signed with another key
        import jwt as pyjwt

        forged = pyjwt.encode({"sub": "x", "type": "access", "exp": 4102444800}, "z" * 40, "HS256")
        assert _call(mw, _env(token=forged))[0].startswith("401")
        assert inner.calls == 0

    def test_malformed_authorization_header_is_refused(self, app):
        mw, inner, _s = _mw(app)
        status, _h, _b = _call(mw, _env(headers={"HTTP_AUTHORIZATION": "Basic abc"}))
        assert status.startswith("401") and inner.calls == 0

    def test_valid_token_passes(self, app):
        mw, inner, _s = _mw(app)
        status, _h, body = _call(mw, _env(token=_token(app)))
        assert status == "200 OK" and inner.calls == 1
        body.close()

    def test_expired_but_signed_token_passes_so_f36_refresh_protocol_still_works(self, app):
        mw, inner, _s = _mw(app)
        tok = _token(app, expires=timedelta(seconds=-60))
        status, _h, body = _call(mw, _env(token=tok))
        assert status == "200 OK" and inner.calls == 1
        body.close()

    def test_query_token_is_refused_when_that_source_is_disabled(self, app):
        mw, inner, _s = _mw(app, query_token_ok=False)
        qs = f"EIO=4&transport=websocket&token={_token(app)}"
        status, _h, body = _call(mw, _env(qs))
        assert status.startswith("401")
        assert b"token_in_query" in b"".join(body) and inner.calls == 0

    def test_query_token_is_accepted_when_enabled(self, app):
        mw, inner, _s = _mw(app, query_token_ok=True)
        qs = f"EIO=4&transport=websocket&token={_token(app)}"
        status, _h, body = _call(mw, _env(qs))
        assert status == "200 OK"
        body.close()

    def test_established_polling_session_requests_are_not_reauthenticated(self, app):
        """Follow-up polls carry only ``sid``; Engine.IO owns that session."""
        mw, inner, _s = _mw(app)
        status, _h, body = _call(mw, _env("EIO=4&transport=polling&sid=abc"))
        assert status == "200 OK"
        body.close()

    def test_cors_preflight_needs_no_token(self, app):
        mw, inner, _s = _mw(app)
        status, _h, body = _call(mw, _env("EIO=4&transport=polling", method="OPTIONS"))
        assert status == "200 OK"
        body.close()

    def test_anonymous_can_be_enabled_explicitly(self, app):
        mw, inner, _s = _mw(app, anonymous=True)
        status, _h, body = _call(mw, _env())
        assert status == "200 OK"
        body.close()


class TestEdgeThreadCeiling:
    def test_requests_above_the_ceiling_get_503_not_a_thread(self, app):
        mw, inner, slots = _mw(app, limit=2)
        tok = _token(app)
        held = [_call(mw, _env(token=tok))[2] for _ in range(2)]
        assert slots.in_flight == 2
        status, headers, body = _call(mw, _env(token=tok))
        assert status.startswith("503")
        assert headers["Retry-After"] == "5"
        assert b"server_busy" in b"".join(body)
        assert inner.calls == 2  # the refused one never reached Engine.IO
        for h in held:
            h.close()

    def test_slot_is_released_when_the_transport_closes(self, app):
        mw, inner, slots = _mw(app, limit=1)
        tok = _token(app)
        first = _call(mw, _env(token=tok))[2]
        assert _call(mw, _env(token=tok))[0].startswith("503")
        first.close()
        assert slots.in_flight == 0 and inner.closed == 1
        again = _call(mw, _env(token=tok))
        assert again[0] == "200 OK"
        again[2].close()

    def test_slot_is_released_when_the_response_is_garbage_collected(self, app):
        mw, _inner, slots = _mw(app, limit=1)
        body = _call(mw, _env(token=_token(app)))[2]
        assert slots.in_flight == 1
        del body
        gc.collect()
        assert slots.in_flight == 0

    def test_slot_is_released_when_the_app_raises(self, app):
        mw, _inner, slots = _mw(app, limit=1)

        def boom(environ, start_response):
            raise RuntimeError("x")

        mw.app = boom
        with pytest.raises(RuntimeError):
            _call(mw, _env(token=_token(app)))
        assert slots.in_flight == 0

    def test_zero_limit_refuses_every_socket_request_but_not_rest(self, app):
        mw, inner, _s = _mw(app, limit=0)
        assert _call(mw, _env(token=_token(app)))[0].startswith("503")
        assert _call(mw, _env(path="/api/health", qs=""))[0] == "200 OK"

    def test_anonymous_flood_never_consumes_a_slot(self, app):
        mw, inner, slots = _mw(app, limit=2)
        for _ in range(200):
            assert _call(mw, _env())[0].startswith("401")
        assert slots.in_flight == 0 and inner.calls == 0
        # ... so a legitimate user still gets in afterwards.
        ok = _call(mw, _env(token=_token(app)))
        assert ok[0] == "200 OK"
        ok[2].close()


# ----------------------------------------------------------------------
# orphan reaper
# ----------------------------------------------------------------------


class _Clock:
    def __init__(self):
        self.t = 1000.0

    def __call__(self):
        return self.t


class _FakeEio:
    def __init__(self):
        self.sockets = {}
        self.disconnected = []

    def disconnect(self, eio_sid):
        self.disconnected.append(eio_sid)
        self.sockets.pop(eio_sid, None)


class _FakeManager:
    def __init__(self):
        self.connected = {}  # eio_sid -> sio sid

    def sid_from_eio_sid(self, eio_sid, namespace):
        return self.connected.get(eio_sid)


class _FakeSocketIO:
    def __init__(self):
        self.server = type("S", (), {})()
        self.server.eio = _FakeEio()
        self.server.manager = _FakeManager()


def _reaper(deadline=10.0):
    sio = _FakeSocketIO()
    clock = _Clock()
    cfg = EdgeConfig(threads=32, edge_limit=20, allow_anonymous=False,
                     auth_deadline=deadline, reaper_interval=2.0)
    return OrphanReaper(sio, cfg, clock), sio, clock


class TestOrphanReaper:
    def test_session_without_a_socketio_connection_is_closed_after_the_deadline(self):
        r, sio, clock = _reaper()
        sio.server.eio.sockets["raw"] = object()
        assert r.scan_once() == 0
        clock.t += 9
        assert r.scan_once() == 0
        clock.t += 2
        assert r.scan_once() == 1
        assert sio.server.eio.disconnected == ["raw"]

    def test_connected_sockets_are_never_touched(self):
        r, sio, clock = _reaper()
        sio.server.eio.sockets["ok"] = object()
        sio.server.manager.connected["ok"] = "sid-1"
        for _ in range(5):
            clock.t += 60
            assert r.scan_once() == 0
        assert sio.server.eio.disconnected == []

    def test_a_refused_connect_that_keeps_its_transport_is_reaped(self):
        """CONNECT_ERROR leaves the Engine.IO transport (and thread) open."""
        r, sio, clock = _reaper()
        sio.server.eio.sockets["held"] = object()  # never gets a sio sid
        r.scan_once()
        clock.t += 11
        assert r.scan_once() == 1

    def test_a_late_connect_inside_the_deadline_is_not_closed(self):
        r, sio, clock = _reaper()
        sio.server.eio.sockets["slow"] = object()
        r.scan_once()
        clock.t += 5
        sio.server.manager.connected["slow"] = "sid-2"
        r.scan_once()
        clock.t += 60
        assert r.scan_once() == 0

    def test_state_for_departed_sessions_is_forgotten(self):
        r, sio, clock = _reaper()
        sio.server.eio.sockets["gone"] = object()
        r.scan_once()
        del sio.server.eio.sockets["gone"]
        r.scan_once()
        assert r._orphan_since == {}

    # -- transport release: eio.disconnect alone leaves the gthread request
    #    thread blocked in ws.receive() for the ping timeout (found with real
    #    gunicorn); the reaper must also shut the transport socket down.

    class _RawSock:
        def __init__(self, raises=None):
            self.shutdowns = []
            self.raises = raises

        def shutdown(self, how):
            self.shutdowns.append(how)
            if self.raises:
                raise self.raises

    def _orphan_with_environ(self, query, raw, *, connected=False):
        r, sio, clock = _reaper()
        sio.server.eio.sockets["o"] = object()
        sio.server.environ = {"o": {"QUERY_STRING": query, "gunicorn.socket": raw}}
        if connected:
            sio.server.manager.connected["o"] = "sid-1"
        real_disconnect = sio.server.eio.disconnect

        def disconnect(eio_sid):  # python-socketio drops environ on disconnect
            sio.server.environ.pop(eio_sid, None)
            real_disconnect(eio_sid)

        sio.server.eio.disconnect = disconnect
        r.scan_once()
        clock.t += 11
        return r, sio

    def test_direct_websocket_orphan_has_its_transport_shut_down(self):
        import socket

        raw = self._RawSock()
        r, sio = self._orphan_with_environ("EIO=4&transport=websocket", raw)
        assert r.scan_once() == 1
        assert sio.server.eio.disconnected == ["o"]
        assert raw.shutdowns == [socket.SHUT_RDWR]

    def test_polling_orphan_transport_is_not_touched(self):
        raw = self._RawSock()
        r, sio = self._orphan_with_environ("EIO=4&transport=polling", raw)
        assert r.scan_once() == 1
        assert raw.shutdowns == []  # the first poll's connection may be shared

    def test_upgraded_session_transport_is_not_touched(self):
        raw = self._RawSock()
        r, _sio = self._orphan_with_environ("EIO=4&transport=websocket&sid=abc", raw)
        assert r.scan_once() == 1
        assert raw.shutdowns == []

    def test_connected_socket_transport_is_never_shut_down(self):
        raw = self._RawSock()
        r, sio = self._orphan_with_environ("EIO=4&transport=websocket", raw, connected=True)
        assert r.scan_once() == 0
        assert sio.server.eio.disconnected == [] and raw.shutdowns == []

    def test_already_closed_transport_does_not_break_the_reaper(self):
        raw = self._RawSock(raises=OSError("not connected"))
        r, sio = self._orphan_with_environ("EIO=4&transport=websocket", raw)
        assert r.scan_once() == 1
        assert sio.server.eio.disconnected == ["o"]

    class _Session:
        """Engine.IO Socket stand-in: ``close(wait=True)`` would block forever
        (no consumer for the CLOSE packet), exactly like an orphan with no poll."""

        def __init__(self):
            self.calls = []

        def close(self, wait=True, **_kw):
            self.calls.append(wait)
            if wait:
                raise AssertionError("reaper must never wait on a consumer")

    def test_reaper_closes_without_waiting_and_removes_the_session(self):
        r, sio, clock = _reaper()
        sess = self._Session()
        sio.server.eio.sockets["p"] = sess
        r.scan_once()
        clock.t += 11
        assert r.scan_once() == 1
        assert sess.calls == [False]
        assert "p" not in sio.server.eio.sockets
        assert sio.server.eio.disconnected == []  # eio.disconnect() waits; not used

    def test_one_stuck_session_never_prevents_reaping_the_next(self):
        r, sio, clock = _reaper()
        first, second = self._Session(), self._Session()
        sio.server.eio.sockets.update({"a": first, "b": second})
        r.scan_once()
        clock.t += 11
        assert r.scan_once() == 2
        assert first.calls == [False] and second.calls == [False]

    def test_missing_environ_is_tolerated(self):
        r, sio, clock = _reaper()
        sio.server.eio.sockets["x"] = object()  # fake server has no .environ at all
        r.scan_once()
        clock.t += 11
        assert r.scan_once() == 1

    def test_deadline_zero_never_starts_the_thread(self):
        r, _sio, _clock = _reaper(deadline=0)
        r.ensure_started()
        assert r._started_pid is None


# ----------------------------------------------------------------------
# wired into the real app
# ----------------------------------------------------------------------


class TestWiredIntoTheApp:
    def test_guard_is_installed_and_outermost(self, app):
        from kk.socket_edge_guard import EXTENSION_KEY

        assert isinstance(app.wsgi_app, SocketEdgeMiddleware)
        assert EXTENSION_KEY in app.extensions

    def test_anonymous_handshake_is_401_through_the_real_app(self, app):
        client = app.test_client()
        r = client.get("/socket.io/?EIO=4&transport=polling")
        assert r.status_code == 401
        assert r.get_json()["code"] == "authentication_required"

    def test_rest_api_is_unaffected(self, app):
        client = app.test_client()
        assert client.get("/api/cars?per_page=1").status_code == 200

    def test_signed_handshake_reaches_engineio(self, app):
        client = app.test_client()
        r = client.get(
            "/socket.io/?EIO=4&transport=polling",
            headers={"Authorization": f"Bearer {_token(app)}"},
        )
        assert r.status_code == 200
        assert r.get_data(as_text=True).startswith("0{")
