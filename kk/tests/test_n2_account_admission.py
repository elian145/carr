"""N-2: ONE account must not monopolize ``/socket.io`` admission slots.

Before the fix the edge guard only checked "some validly signed token", so a
single account could pin the whole edge limit with handshakes that never reach
the Socket.IO ``connect`` handler (the per-user registry cap never applied) and
every other user got ``503 server_busy``. These tests pin the per-account
admission added in ``kk.socket_account_admission`` / ``kk.socket_edge_guard``.

Synthetic data only; the live-server class binds 127.0.0.1 on an ephemeral port.
"""

from __future__ import annotations

import gc
import os
import socket as _socket
import sys
import tempfile
import threading
import time
from datetime import timedelta
from pathlib import Path

import pytest

_REPO_ROOT = Path(__file__).resolve().parents[2]
if str(_REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(_REPO_ROOT))

from kk.realtime_limits import default_max_total  # noqa: E402
from kk.socket_account_admission import (  # noqa: E402
    ACCOUNT_KEY,
    BAD_TOKENS,
    BUCKET_LIVE,
    BUCKET_RESTRICTED,
    ESTABLISHED_KEY,
    REFUSED_KEY,
    AccountLedger,
    BadTokenCache,
    Identity,
)
from kk.socket_edge_guard import (  # noqa: E402
    EdgeConfig,
    OrphanReaper,
    SlotCounter,
    SocketEdgeMiddleware,
    compute_account_limit,
    load_edge_config,
    make_handshake_authenticator,
)

# ---------------------------------------------------------------------------
# helpers
# ---------------------------------------------------------------------------


@pytest.fixture(scope="module")
def app():
    tmp = tempfile.TemporaryDirectory(prefix="carlist_n2_", ignore_cleanup_errors=True)
    os.environ["APP_ENV"] = "testing"
    os.environ["SMS_PROVIDER"] = "console"
    os.environ["DB_PATH"] = os.path.join(tmp.name, "n2.db")
    from kk.app_factory import create_app

    application, *_ = create_app()
    application._tmp = tmp
    return application


@pytest.fixture(autouse=True)
def _clean_negative_cache():
    BAD_TOKENS.clear()
    _KEEP.clear()
    yield
    BAD_TOKENS.clear()
    _KEEP.clear()


def _token(app, identity, *, expires=None):
    from flask_jwt_extended import create_access_token

    with app.app_context():
        return create_access_token(identity=identity, expires_delta=expires)


class _Raw:
    """Stand-in for the connection socket (``gunicorn.socket``)."""

    def __init__(self):
        self.shutdowns = 0

    def shutdown(self, how):
        self.shutdowns += 1


class _Held:
    """Inner app whose responses stay open (a pinned worker thread)."""

    def __init__(self):
        self.calls = 0
        self.closed = 0
        self.raise_next = False

    def __call__(self, environ, start_response):
        self.calls += 1
        if self.raise_next:
            self.raise_next = False
            raise RuntimeError("boom")
        start_response("200 OK", [("Content-Type", "text/plain")])
        outer = self

        class _Body:
            def __iter__(self):
                return iter([b"x"])

            def close(self):
                outer.closed += 1

        return _Body()


def _env(token=None, qs="EIO=4&transport=websocket", *, raw=None, method="GET"):
    e = {
        "PATH_INFO": "/socket.io/",
        "QUERY_STRING": qs,
        "REQUEST_METHOD": method,
        "REMOTE_ADDR": "203.0.113.9",  # every test client shares ONE address (CGNAT)
    }
    if token:
        e["HTTP_AUTHORIZATION"] = f"Bearer {token}"
    if raw is not None:
        e["gunicorn.socket"] = raw
    return e


_KEEP: list = []  # a discarded body would be garbage collected == released


def _call(mw, environ):
    box = {}

    def sr(status, headers, exc=None):
        box["status"] = status
        box["headers"] = dict(headers)

    body = mw(environ, sr)
    _KEEP.append(body)
    return box["status"], box["headers"], body


def _stack(app, *, edge_limit=20, account_limit=6, restricted_per=2, restricted_total=5):
    inner = _Held()
    cfg = EdgeConfig(
        threads=32, edge_limit=edge_limit, allow_anonymous=False, auth_deadline=10.0,
        reaper_interval=2.0, account_limit=account_limit,
        restricted_per_account=restricted_per, restricted_total=restricted_total,
    )
    slots = SlotCounter(edge_limit)
    ledger = AccountLedger(
        per_account=account_limit, restricted_per_account=restricted_per,
        restricted_total=restricted_total,
    )
    sessions: dict = {}
    mw = SocketEdgeMiddleware(
        inner, config=cfg, slots=slots,
        authenticate=make_handshake_authenticator(app, lambda: False),
        ledger=ledger, session_env=sessions.get,
    )
    return mw, inner, slots, ledger, sessions


def _ok(status):
    return status.startswith("200")


# ---------------------------------------------------------------------------
# the reproduction (failed on 0da9101) -- production-shaped wiring
# ---------------------------------------------------------------------------


class TestOneAccountCannotMonopolize:
    def test_attacker_cannot_pin_the_edge_and_a_victim_still_connects(self, app):
        mw, _inner, slots, _ledger, _s = _stack(app)
        attacker = _token(app, "pub-attacker")
        live, peak = [], 0
        for _ in range(60):
            raw = _Raw()
            status, _h, body = _call(mw, _env(attacker, raw=raw))
            assert _ok(status)  # the newest handshake always replaces an older one
            live.append((raw, body))
            for item in list(live):  # a shut-down transport unwinds its thread
                if item[0].shutdowns:
                    item[1].close()
                    live.remove(item)
            peak = max(peak, slots.in_flight)
        assert len(live) <= 6 and peak <= 6 + 1  # per-account limit (20 // 3), not the edge
        status, _h, vbody = _call(mw, _env(_token(app, "pub-victim"), raw=_Raw()))
        assert _ok(status), status
        for _r, b in live:
            b.close()
        vbody.close()
        assert slots.in_flight == 0

    def test_attacker_with_stalled_polls_is_refused_not_admitted(self, app):
        mw, _inner, slots, _ledger, _s = _stack(app)
        attacker = _token(app, "pub-attacker")
        held = []
        for _ in range(60):
            status, _h, body = _call(mw, _env(attacker, "EIO=4&transport=polling", raw=_Raw()))
            if _ok(status):
                held.append(body)
        assert len(held) == 6 and slots.in_flight == 6
        assert _ok(_call(mw, _env(_token(app, "pub-victim"), raw=_Raw()))[0])
        for b in held:
            b.close()

    def test_three_accounts_can_never_exhaust_the_edge(self):
        for edge in (8, 12, 20, 30, 60):
            for per_user in (1, 3, 5, 10):
                assert compute_account_limit(edge, per_user) * 3 <= max(edge, 6)

    def test_attacker_loop_with_persistent_stale_connections_is_bounded(self, app):
        """An endless reconnect loop (new handshake every time, old ones never
        closed by the client) is recycled onto the account's own budget."""
        mw, _inner, slots, ledger, _s = _stack(app)
        tok = _token(app, "pub-looper")
        live, raws = [], []
        for _ in range(100):
            raw = _Raw()
            raws.append(raw)
            status, _h, body = _call(mw, _env(tok, raw=raw))
            assert _ok(status)
            live.append((raw, body))
            for item in list(live):  # shut-down transports unwind their threads
                if item[0].shutdowns:
                    item[1].close()
                    live.remove(item)
            assert ledger.held("pub-looper") <= 6 and slots.in_flight <= 7
        assert sum(r.shutdowns for r in raws) == 94  # the 94 oldest were shut down

    def test_no_per_ip_limit_for_carrier_nat(self, app):
        """Many DIFFERENT accounts behind one address are all admitted."""
        mw, _inner, _slots, _l, _s = _stack(app, edge_limit=30)
        bodies = []
        for i in range(30):
            status, _h, b = _call(mw, _env(_token(app, f"pub-nat-{i}"), raw=_Raw()))
            assert _ok(status), i
            bodies.append(b)
        assert _call(mw, _env(_token(app, "pub-nat-x"), raw=_Raw()))[0].startswith("503")  # global only


# ---------------------------------------------------------------------------
# slots are released on EVERY exit path
# ---------------------------------------------------------------------------


class TestRelease:
    def test_released_on_close(self, app):
        mw, inner, slots, ledger, _s = _stack(app)
        _st, _h, body = _call(mw, _env(_token(app, "pub-a"), raw=_Raw()))
        assert ledger.held("pub-a") == 1 and slots.in_flight == 1
        body.close()
        assert ledger.held("pub-a") == 0 and slots.in_flight == 0 and inner.closed == 1
        body.close()  # idempotent
        assert slots.in_flight == 0

    def test_released_when_the_app_raises(self, app):
        mw, inner, slots, ledger, _s = _stack(app)
        inner.raise_next = True
        with pytest.raises(RuntimeError):
            _call(mw, _env(_token(app, "pub-a"), raw=_Raw()))
        assert ledger.held("pub-a") == 0 and slots.in_flight == 0

    def test_released_when_the_server_forgets_close(self, app):
        mw, _inner, slots, ledger, _s = _stack(app)
        _call(mw, _env(_token(app, "pub-a"), raw=_Raw()))
        assert ledger.held("pub-a") == 1
        _KEEP.clear()  # the server dropped the iterable without close()
        gc.collect()
        assert ledger.held("pub-a") == 0 and slots.in_flight == 0

    def test_account_slot_is_returned_when_the_global_ceiling_refuses(self, app):
        mw, _inner, slots, ledger, _s = _stack(app, edge_limit=1, account_limit=2)
        _st, _h, first = _call(mw, _env(_token(app, "pub-a"), raw=_Raw()))
        status, _h, _b = _call(mw, _env(_token(app, "pub-b"), raw=_Raw()))
        assert status.startswith("503")
        assert ledger.held("pub-b") == 0
        first.close()
        assert slots.in_flight == 0 and ledger.accounts() == 0

    def test_refused_by_account_cap_holds_nothing(self, app):
        mw, _inner, slots, ledger, _s = _stack(app, account_limit=2)
        tok = _token(app, "pub-poller")
        keep = [_call(mw, _env(tok, "EIO=4&transport=polling"))[2] for _ in range(2)]
        status, headers, body = _call(mw, _env(tok, "EIO=4&transport=polling"))
        assert status.startswith("503") and headers["Retry-After"] == "3"
        assert b"too_many_connections" in b"".join(body)
        assert ledger.held("pub-poller") == 2 and slots.in_flight == 2
        for b in keep:
            b.close()
        assert ledger.held("pub-poller") == 0 and slots.in_flight == 0

    def test_options_preflight_takes_no_account_slot(self, app):
        mw, _inner, _slots, ledger, _s = _stack(app)
        status, *_ = _call(mw, _env(_token(app, "pub-a"), "EIO=4&transport=polling", method="OPTIONS"))
        assert _ok(status) and ledger.accounts() == 0


# ---------------------------------------------------------------------------
# legitimate reconnects replace stale transports instead of being blocked
# ---------------------------------------------------------------------------


class TestReconnect:
    def test_reconnect_after_network_switch_evicts_the_oldest_stale_socket(self, app):
        mw, _inner, _slots, ledger, sessions = _stack(app, account_limit=3)
        tok = _token(app, "pub-phone")
        raws, envs = [], []
        for _ in range(3):
            raw = _Raw()
            e = _env(tok, raw=raw)
            raws.append(raw)
            envs.append(e)
            assert _ok(_call(mw, e)[0])
        for e in envs:
            e[ESTABLISHED_KEY] = True  # all three completed their Socket.IO CONNECT
        fresh = _Raw()
        status, *_ = _call(mw, _env(tok, raw=fresh))
        assert _ok(status)
        assert [r.shutdowns for r in raws] == [1, 0, 0]  # only the OLDEST stale one
        assert fresh.shutdowns == 0 and ledger.held("pub-phone") == 3

    def test_pending_handshakes_are_sacrificed_before_established_sockets(self, app):
        mw, _inner, _slots, _ledger, _s = _stack(app, account_limit=3)
        tok = _token(app, "pub-phone")
        raws, envs = [], []
        for _ in range(3):
            raw, e = _Raw(), _env(tok, raw=_Raw())
            e["gunicorn.socket"] = raw
            raws.append(raw)
            envs.append(e)
            _call(mw, e)
        envs[0][ESTABLISHED_KEY] = True  # the OLDEST one is the healthy socket
        status, *_ = _call(mw, _env(tok, raw=_Raw()))
        assert _ok(status)
        assert [r.shutdowns for r in raws] == [0, 1, 0]  # oldest PENDING one went

    def test_other_accounts_are_never_evicted_by_an_account_at_its_limit(self, app):
        mw, _inner, _slots, _ledger, _s = _stack(app, account_limit=2)
        v_raw = _Raw()
        _call(mw, _env(_token(app, "pub-victim"), raw=v_raw))
        a_raws = [_Raw() for _ in range(10)]
        for r in a_raws:
            _call(mw, _env(_token(app, "pub-attacker"), raw=r))
        assert v_raw.shutdowns == 0


# ---------------------------------------------------------------------------
# sid-only requests (long poll) are attributed to the session's creator
# ---------------------------------------------------------------------------


class TestSessionAttribution:
    def _handshake(self, app, mw, sessions, tok, sid):
        e = _env(tok, "EIO=4&transport=polling", raw=_Raw())
        status, _h, body = _call(mw, e)
        assert _ok(status)
        body.close()
        sessions[sid] = e  # what python-socketio keeps as server.environ[sid]
        return e

    def test_stalled_polls_of_pending_sessions_are_charged_to_their_account(self, app):
        mw, _inner, slots, ledger, sessions = _stack(app, account_limit=3)
        tok = _token(app, "pub-attacker")
        for i in range(30):
            self._handshake(app, mw, sessions, tok, f"s{i}")
        held = []
        refused = 0
        for i in range(30):
            status, _h, body = _call(mw, _env(None, f"EIO=4&transport=polling&sid=s{i}", raw=_Raw()))
            if _ok(status):
                held.append(body)
            else:
                refused += 1
        assert len(held) == 3 and refused == 27
        assert slots.in_flight == 3
        # a different account is untouched
        assert _ok(_call(mw, _env(_token(app, "pub-victim"), raw=_Raw()))[0])
        for b in held:
            b.close()

    def test_polls_of_an_established_session_are_never_refused(self, app):
        mw, _inner, _slots, _ledger, sessions = _stack(app, account_limit=2)
        tok = _token(app, "pub-user")
        e = self._handshake(app, mw, sessions, tok, "live")
        e[ESTABLISHED_KEY] = True
        bodies = []
        for _ in range(6):  # more than the account cap: the socket is already admitted
            status, _h, b = _call(mw, _env(None, "EIO=4&transport=polling&sid=live", raw=_Raw()))
            assert _ok(status)
            bodies.append(b)

    def test_unknown_sid_is_only_subject_to_the_global_ceiling(self, app):
        mw, inner, _slots, ledger, _s = _stack(app)
        status, *_ = _call(mw, _env(None, "EIO=4&transport=polling&sid=nope"))
        assert _ok(status) and ledger.accounts() == 0 and inner.calls == 1

    def test_identity_marker_does_not_leak_into_the_session_environ(self, app):
        mw, _inner, _slots, _l, _s = _stack(app)
        e = _env(_token(app, "pub-a"), raw=_Raw())
        _call(mw, e)
        assert e[ACCOUNT_KEY] == (BUCKET_LIVE, "pub-a")
        assert "carnet.edge_identity" not in e


# ---------------------------------------------------------------------------
# expired / revoked / deleted-account tokens (F-36 protocol preserved)
# ---------------------------------------------------------------------------


class TestDeadTokens:
    def test_expired_token_still_reaches_connect_for_the_f36_refresh_signal(self, app):
        mw, inner, _slots, _l, _s = _stack(app)
        expired = _token(app, "pub-a", expires=timedelta(seconds=-30))
        status, *_ = _call(mw, _env(expired, raw=_Raw()))
        assert _ok(status) and inner.calls == 1  # the handler answers CONNECT_ERROR token_expired

    def test_expired_tokens_do_not_consume_the_accounts_live_budget(self, app):
        mw, _inner, _slots, ledger, _s = _stack(app, account_limit=3, restricted_per=2)
        expired = _token(app, "pub-a", expires=timedelta(seconds=-30))
        for _ in range(10):
            _call(mw, _env(expired, raw=_Raw()))
        assert ledger.held("pub-a", BUCKET_LIVE) == 0
        assert ledger.held("pub-a", BUCKET_RESTRICTED) == 2
        # the real owner can still use every live slot
        live = _token(app, "pub-a")
        for _ in range(3):
            assert _ok(_call(mw, _env(live, raw=_Raw()))[0])

    def test_replayed_expired_token_cannot_evict_the_owners_live_sockets(self, app):
        mw, _inner, _slots, _l, _s = _stack(app, account_limit=2)
        live_raws = [_Raw(), _Raw()]
        live = _token(app, "pub-a")
        for r in live_raws:
            _call(mw, _env(live, raw=r))
        expired = _token(app, "pub-a", expires=timedelta(seconds=-30))
        for _ in range(20):
            _call(mw, _env(expired, raw=_Raw()))
        assert [r.shutdowns for r in live_raws] == [0, 0]

    def test_expired_tokens_across_many_accounts_hit_a_global_restricted_cap(self, app):
        mw, _inner, slots, ledger, _s = _stack(app, edge_limit=20, restricted_total=4)
        admitted = 0
        for i in range(30):
            expired = _token(app, f"pub-old-{i}", expires=timedelta(seconds=-30))
            if _ok(_call(mw, _env(expired, raw=_Raw()))[0]):
                admitted += 1
        assert admitted == 4 and ledger.restricted_held() == 4
        # live users keep the rest of the edge
        assert _ok(_call(mw, _env(_token(app, "pub-live"), raw=_Raw()))[0])

    def test_revoked_token_is_classified_restricted_once_the_handler_saw_it(self, app):
        mw, _inner, _slots, ledger, _s = _stack(app)
        from flask_jwt_extended import decode_token

        tok = _token(app, "pub-a")
        with app.app_context():
            jti = decode_token(tok)["jti"]
        BAD_TOKENS.add_token(jti, tok, 60)
        for _ in range(5):
            _call(mw, _env(tok, raw=_Raw()))
        assert ledger.held("pub-a", BUCKET_LIVE) == 0
        assert ledger.held("pub-a", BUCKET_RESTRICTED) == 2
        # another token of the same account is unaffected
        assert _ok(_call(mw, _env(_token(app, "pub-a"), raw=_Raw()))[0])
        assert ledger.held("pub-a", BUCKET_LIVE) == 1

    def test_deleted_or_inactive_account_is_classified_restricted(self, app):
        mw, _inner, _slots, ledger, _s = _stack(app)
        BAD_TOKENS.add_account("pub-gone", 60)
        for _ in range(5):
            _call(mw, _env(_token(app, "pub-gone"), raw=_Raw()))
        assert ledger.held("pub-gone", BUCKET_LIVE) == 0
        assert ledger.held("pub-gone", BUCKET_RESTRICTED) == 2

    def test_forged_or_garbage_tokens_cost_nothing(self, app):
        mw, inner, slots, ledger, _s = _stack(app)
        for tok in ("garbage", "a.b.c"):
            assert _call(mw, _env(tok))[0].startswith("401")
        assert inner.calls == 0 and slots.in_flight == 0 and ledger.accounts() == 0

    def test_anonymous_opt_in_is_not_attributed_to_an_account(self, app):
        inner = _Held()
        cfg = EdgeConfig(threads=32, edge_limit=5, allow_anonymous=True, auth_deadline=10.0,
                         reaper_interval=2.0, account_limit=2)
        ledger = AccountLedger(per_account=2, restricted_per_account=2, restricted_total=2)
        mw = SocketEdgeMiddleware(
            inner, config=cfg, slots=SlotCounter(5),
            authenticate=make_handshake_authenticator(app, lambda: False), ledger=ledger,
        )
        status, *_ = _call(mw, _env(None))
        assert _ok(status) and ledger.accounts() == 0


class TestBadTokenCache:
    def test_entries_expire(self):
        t = [0.0]
        c = BadTokenCache(clock=lambda: t[0])
        c.add_token("jti-1", None, 10)
        ident = Identity(sub="s", jti="jti-1", exp=1e12)
        assert c.is_bad(ident)
        t[0] = 11
        assert not c.is_bad(ident)

    def test_cache_is_bounded(self):
        c = BadTokenCache(max_size=50)
        for i in range(500):
            c.add_token(f"j{i}", None, 1000)
        assert len(c._items) <= 50
        assert c.is_bad(Identity(sub="s", jti="j499", exp=1e12))

    def test_unrelated_tokens_are_not_bad(self):
        c = BadTokenCache()
        c.add_token("a", None, 10)
        assert not c.is_bad(Identity(sub="s", jti="b", exp=1e12))


# ---------------------------------------------------------------------------
# ledger unit tests
# ---------------------------------------------------------------------------


class TestLedger:
    def test_release_is_idempotent_and_ignores_none(self):
        ledger = AccountLedger(per_account=2, restricted_per_account=1, restricted_total=1)
        t, _v = ledger.reserve("a", BUCKET_LIVE, is_ws=True, raw=_Raw())
        ledger.release(t)
        ledger.release(t)
        ledger.release(None)
        assert ledger.held("a") == 0 and ledger.accounts() == 0

    def test_evicted_ticket_is_not_double_counted_on_release(self):
        ledger = AccountLedger(per_account=1, restricted_per_account=1, restricted_total=1)
        a, _ = ledger.reserve("x", BUCKET_LIVE, is_ws=True, raw=_Raw())
        b, victims = ledger.reserve("x", BUCKET_LIVE, is_ws=True, raw=_Raw())
        assert victims == [a] and a.evicted
        ledger.release(a)  # the dying request finally closes
        assert ledger.held("x") == 1
        ledger.release(b)
        assert ledger.held("x") == 0

    def test_non_websocket_requests_cannot_be_evicted_only_refused(self):
        ledger = AccountLedger(per_account=1, restricted_per_account=1, restricted_total=1)
        ledger.reserve("x", BUCKET_LIVE, is_ws=False, raw=_Raw())
        t, victims = ledger.reserve("x", BUCKET_LIVE, is_ws=False, raw=_Raw())
        assert t is None and victims == []
        assert ledger.refusals_total == 1

    def test_zero_disables_the_live_cap(self):
        ledger = AccountLedger(per_account=0, restricted_per_account=1, restricted_total=1)
        for _ in range(50):
            t, _v = ledger.reserve("x", BUCKET_LIVE, is_ws=False)
            assert t is not None

    def test_stalled_reports_only_old_non_websocket_requests(self):
        clock = [100.0]
        ledger = AccountLedger(per_account=9, restricted_per_account=1, restricted_total=1,
                               clock=lambda: clock[0])
        poll_raw, ws_raw = _Raw(), _Raw()
        poll, _ = ledger.reserve("x", BUCKET_LIVE, is_ws=False, raw=poll_raw)
        ledger.reserve("x", BUCKET_LIVE, is_ws=True, raw=ws_raw)
        assert ledger.stalled(60) == []
        clock[0] += 61
        assert ledger.stalled(60) == [poll]
        assert ledger.stalled(0) == []  # disabled


# ---------------------------------------------------------------------------
# configuration
# ---------------------------------------------------------------------------


class TestConfig:
    def test_production_defaults(self):
        cfg = load_edge_config({}, max_total=default_max_total(32))
        assert (cfg.edge_limit, cfg.account_limit) == (20, 6)
        assert cfg.restricted_per_account == 2 and cfg.restricted_total == 5
        assert cfg.refused_grace == 3.0 and cfg.stall_seconds == 60.0

    def test_small_worker_still_allows_a_reconnect(self):
        cfg = load_edge_config({"GUNICORN_THREADS": "4"}, max_total=default_max_total(4))
        assert cfg.edge_limit == 2 and cfg.account_limit == 2

    def test_env_overrides(self):
        env = {
            "SOCKETIO_EDGE_MAX_PER_ACCOUNT": "4",
            "SOCKETIO_EDGE_RESTRICTED_PER_ACCOUNT": "1",
            "SOCKETIO_EDGE_REFUSED_GRACE_SECONDS": "1",
            "SOCKETIO_EDGE_STALL_SECONDS": "30",
        }
        cfg = load_edge_config(env, max_total=16)
        assert (cfg.account_limit, cfg.restricted_per_account) == (4, 1)
        assert (cfg.refused_grace, cfg.stall_seconds) == (1.0, 30.0)

    def test_zero_disables_and_garbage_falls_back(self):
        assert load_edge_config({"SOCKETIO_EDGE_MAX_PER_ACCOUNT": "0"}, max_total=16).account_limit == 0
        assert load_edge_config({"SOCKETIO_EDGE_MAX_PER_ACCOUNT": "x"}, max_total=16).account_limit == 6

    def test_follows_the_per_user_socket_cap(self):
        cfg = load_edge_config({"SOCKETIO_MAX_CONNECTIONS_PER_USER": "2"}, max_total=default_max_total(32))
        assert cfg.account_limit == 3


# ---------------------------------------------------------------------------
# reaper: refused connections and stalled requests
# ---------------------------------------------------------------------------


class _Eio:
    def __init__(self):
        self.sockets = {}


class _Mgr:
    def sid_from_eio_sid(self, eio_sid, ns):
        return None


class _Sio:
    def __init__(self):
        self.server = type("S", (), {})()
        self.server.eio = _Eio()
        self.server.manager = _Mgr()
        self.server.environ = {}


class _Sess:
    def __init__(self):
        self.closed = False

    def close(self, wait=True, **_kw):
        assert wait is False
        self.closed = True


class TestReaper:
    def _reaper(self, **kw):
        clock = [1000.0]
        cfg = EdgeConfig(threads=32, edge_limit=20, allow_anonymous=False, auth_deadline=10.0,
                         reaper_interval=2.0, **kw)
        sio = _Sio()
        return OrphanReaper(sio, cfg, lambda: clock[0]), sio, clock

    def test_refused_session_is_closed_after_the_short_grace_not_the_full_deadline(self):
        r, sio, clock = self._reaper(refused_grace=3.0)
        s = _Sess()
        sio.server.eio.sockets["bad"] = s
        sio.server.environ["bad"] = {REFUSED_KEY: True}
        r.scan_once()
        clock[0] += 3.5
        assert r.scan_once() == 1 and s.closed

    def test_unrefused_orphan_keeps_the_full_deadline(self):
        r, sio, clock = self._reaper(refused_grace=3.0)
        s = _Sess()
        sio.server.eio.sockets["slow"] = s
        sio.server.environ["slow"] = {}
        r.scan_once()
        clock[0] += 5
        assert r.scan_once() == 0 and not s.closed
        clock[0] += 6
        assert r.scan_once() == 1

    def test_grace_never_exceeds_the_auth_deadline(self):
        r, sio, clock = self._reaper(refused_grace=99.0)
        s = _Sess()
        sio.server.eio.sockets["bad"] = s
        sio.server.environ["bad"] = {REFUSED_KEY: True}
        r.scan_once()
        clock[0] += 10.5
        assert r.scan_once() == 1

    def test_stalled_poll_transport_is_shut_down(self):
        r, sio, clock = self._reaper(stall_seconds=60.0)
        ledger = AccountLedger(per_account=9, restricted_per_account=1, restricted_total=1,
                               clock=lambda: clock[0])
        r.ledger = ledger
        raw = _Raw()
        ledger.reserve("x", BUCKET_LIVE, is_ws=False, raw=raw)
        r.scan_once()
        assert raw.shutdowns == 0
        clock[0] += 61
        r.scan_once()
        assert raw.shutdowns == 1 and r.stalled_total == 1


# ---------------------------------------------------------------------------
# the real thing in-process: Werkzeug threaded server + raw websocket clients
# ---------------------------------------------------------------------------


def _free_port():
    s = _socket.socket()
    s.bind(("127.0.0.1", 0))
    port = s.getsockname()[1]
    s.close()
    return port


class _Live:
    """Real app + production guard on a threaded Werkzeug server."""

    def __init__(self, app):
        from werkzeug.serving import make_server

        self.app = app
        self.port = _free_port()
        self.srv = make_server("127.0.0.1", self.port, app, threaded=True)
        self.thread = threading.Thread(target=self.srv.serve_forever, daemon=True)
        self.thread.start()

    def stop(self):
        self.srv.shutdown()
        self.srv.server_close()


@pytest.fixture(scope="module")
def live(app):
    from kk.models import User, db

    with app.app_context():
        db.create_all()
        for pid in ("pub-live-attacker", "pub-live-victim"):
            if not User.query.filter_by(public_id=pid).first():
                u = User(
                    username=pid.replace("-", "_"), phone_number=f"077{abs(hash(pid)) % 10**8:08d}",
                    first_name="N2", last_name="Live", email=None, is_active=True,
                    is_verified=True, phone_verified=True, public_id=pid,
                )
                u.set_password("Passw0rd!123")
                db.session.add(u)
        db.session.commit()
    srv = _Live(app)
    yield srv
    srv.stop()


def _ws_open(port, token, timeout=5.0):
    import base64
    import struct  # noqa: F401

    s = _socket.create_connection(("127.0.0.1", port), timeout=timeout)
    key = base64.b64encode(os.urandom(16)).decode()
    req = (
        f"GET /socket.io/?EIO=4&transport=websocket HTTP/1.1\r\nHost: 127.0.0.1:{port}\r\n"
        f"Upgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Key: {key}\r\n"
        "Sec-WebSocket-Version: 13\r\n"
        f"Authorization: Bearer {token}\r\n\r\n"
    )
    s.sendall(req.encode())
    buf = b""
    while b"\r\n\r\n" not in buf:
        chunk = s.recv(4096)
        if not chunk:
            break
        buf += chunk
    status = int(buf.split(b" ", 2)[1]) if buf.startswith(b"HTTP/") else 0
    return s, status, buf.split(b"\r\n\r\n", 1)[1] if b"\r\n\r\n" in buf else b""


def _ws_send_connect(s):
    data, mask = b"40", os.urandom(4)
    s.sendall(bytes([0x81, 0x80 | len(data)]) + mask + bytes(b ^ mask[i % 4] for i, b in enumerate(data)))


def _read_frames(s, first=b"", wait=2.0):
    """Return the text payloads received within ``wait`` seconds."""
    out, buf = [], first
    s.settimeout(0.3)
    end = time.monotonic() + wait
    while time.monotonic() < end:
        while len(buf) >= 2:
            ln, off = buf[1] & 0x7F, 2
            if ln == 126:
                if len(buf) < 4:
                    break
                ln, off = int.from_bytes(buf[2:4], "big"), 4
            if len(buf) < off + ln:
                break
            out.append(buf[off:off + ln])
            buf = buf[off + ln:]
        try:
            chunk = s.recv(4096)
            if not chunk:
                break
            buf += chunk
        except _socket.timeout:
            if any(p.startswith((b"40", b"44")) for p in out):
                break
        except OSError:
            break
    return out


class TestLiveServer:
    def test_account_marker_and_established_flag_reach_the_real_session_environ(self, live, app):
        from kk.extensions import socketio as sio

        tok = _token(app, "pub-live-victim")
        s, status, rest = _ws_open(live.port, tok)
        assert status == 101
        _ws_send_connect(s)
        frames = _read_frames(s, rest)
        assert any(f.startswith(b"40") for f in frames), frames
        envs = list(sio.server.environ.values())
        mine = [e for e in envs if e.get(ACCOUNT_KEY) == (BUCKET_LIVE, "pub-live-victim")]
        assert mine and all(e.get(ESTABLISHED_KEY) for e in mine)
        s.close()

    def test_one_account_flood_leaves_room_for_another_account(self, live, app):
        guard = app.extensions["carnet_socket_edge"]
        limit = guard["config"].account_limit
        assert limit and limit < guard["config"].edge_limit
        attacker = _token(app, "pub-live-attacker")
        socks, statuses = [], []
        # Windows' shutdown() does not wake a blocked recv(), so evicted threads
        # may linger here: stay below the global edge limit and judge the ledger.
        attempts = min(limit * 2, guard["config"].edge_limit - 2)
        for _ in range(attempts):
            s, status, _r = _ws_open(live.port, attacker)
            socks.append(s)
            statuses.append(status)
        try:
            assert statuses.count(101) == attempts  # older ones are recycled, never 503
            assert guard["ledger"].held("pub-live-attacker") <= limit
            assert guard["ledger"].evictions_total >= attempts - limit
            vs, vstatus, vrest = _ws_open(live.port, _token(app, "pub-live-victim"))
            assert vstatus == 101
            _ws_send_connect(vs)
            assert any(f.startswith(b"40") for f in _read_frames(vs, vrest))
            vs.close()
        finally:
            for s in socks:
                s.close()

    def test_refused_connect_marks_the_session_for_fast_reaping(self, live, app):
        from kk.extensions import socketio as sio
        from kk.models import User, db

        with app.app_context():
            u = User.query.filter_by(public_id="pub-live-attacker").first()
            u.is_active = False
            db.session.commit()
        try:
            from flask_jwt_extended import decode_token

            tok = _token(app, "pub-live-attacker")
            with app.app_context():
                jti = decode_token(tok)["jti"]
            s, status, rest = _ws_open(live.port, tok)
            assert status == 101
            _ws_send_connect(s)
            frames = _read_frames(s, rest)
            assert any(f.startswith(b"44") for f in frames), frames  # CONNECT_ERROR kept (F-36 style)
            assert any(e.get(REFUSED_KEY) for e in sio.server.environ.values())
            # the deactivated account's token (blocklisted by H-01) is now
            # classified restricted at the edge: replays cost the owner nothing
            assert BAD_TOKENS.is_bad(Identity(sub="pub-live-attacker", jti=jti, exp=1e12))
            assert not BAD_TOKENS.is_bad(Identity(sub="pub-live-attacker", jti="other", exp=1e12))
            s.close()
        finally:
            with app.app_context():
                u = User.query.filter_by(public_id="pub-live-attacker").first()
                u.is_active = True
                db.session.commit()
