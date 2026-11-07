"""C-1: WebSocket / API resource exhaustion.

Production runs one Gunicorn ``gthread`` worker with threading Socket.IO, where
every open WebSocket pins a worker thread for its whole life. Before this fix
the worker had 4 threads, sockets were uncapped (per user, per address, in
total), the socket ``send_message`` path had no rate limit (REST allows 120 per
10 minutes), event payloads were unvalidated, and JSON endpoints accepted up to
250 MB bodies.

Synthetic accounts only; no network or external services.
"""

from __future__ import annotations

import os
import sys
import tempfile
import uuid
from pathlib import Path

import pytest

_REPO_ROOT = Path(__file__).resolve().parents[2]
if str(_REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(_REPO_ROOT))

from kk.realtime_limits import (  # noqa: E402
    REFUSE_SERVER_BUSY,
    REFUSE_TOO_MANY_FROM_ADDRESS,
    ConnectionRegistry,
    EventRateLimiter,
    SocketLimits,
    default_max_total,
    load_limits,
)
from kk.socketio_deploy import (  # noqa: E402
    DEFAULT_GUNICORN_THREADS,
    resolve_gunicorn_threads,
    resolve_json_max_content_length,
    resolve_socketio_max_http_buffer_size,
)

PASSWORD = "Aa123456!"


# ======================================================================
# Pure unit tests
# ======================================================================


def _limits(**kw):
    base = dict(max_total=10, max_guests_total=4, max_guests_per_ip=2, max_per_user=2)
    base.update(kw)
    return SocketLimits(**base)


class TestDeploymentDefaults:
    def test_default_threads_leave_room_for_sockets_and_http(self):
        assert DEFAULT_GUNICORN_THREADS == 32
        assert resolve_gunicorn_threads(None) == 32
        assert resolve_gunicorn_threads("") == 32
        assert resolve_gunicorn_threads("abc") == 32
        assert resolve_gunicorn_threads("0") == 32
        assert resolve_gunicorn_threads("-3") == 32
        assert resolve_gunicorn_threads("12") == 12

    def test_gunicorn_conf_uses_the_shared_resolver(self):
        src = (_REPO_ROOT / "gunicorn.conf.py").read_text(encoding="utf-8")
        assert 'os.environ.get("GUNICORN_THREADS", "4")' not in src
        assert "resolve_gunicorn_threads" in src

    def test_sockets_never_take_more_than_half_the_threads(self):
        # At least half of the threads (and at least 8) stay free for HTTP.
        for threads in (4, 8, 16, 32, 64, 128):
            total = default_max_total(threads)
            assert total >= 1
            assert threads - total >= min(threads - 1, max(8, threads // 2))
        assert default_max_total(32) == 16
        assert default_max_total(64) == 32

    def test_load_limits_defaults_and_overrides(self):
        lim = load_limits({})
        assert lim.max_total == 16
        assert lim.max_guests_total == 4
        assert lim.max_guests_per_ip == 2
        assert lim.max_per_user == 5
        lim = load_limits(
            {
                "GUNICORN_THREADS": "64",
                "SOCKETIO_MAX_GUESTS_PER_IP": "7",
                "SOCKETIO_MAX_CONNECTIONS_PER_USER": "9",
            }
        )
        assert lim.max_total == 32
        assert lim.max_guests_per_ip == 7
        assert lim.max_per_user == 9
        assert load_limits({"SOCKETIO_MAX_CONNECTIONS": "junk"}).max_total == 16
        assert load_limits({"SOCKETIO_MAX_CONNECTIONS": "3"}).max_total == 3

    def test_buffer_and_json_limits(self):
        assert resolve_socketio_max_http_buffer_size(None) == 65536
        assert resolve_socketio_max_http_buffer_size("131072") == 131072
        assert resolve_socketio_max_http_buffer_size("5") == 65536  # nonsense -> default
        assert resolve_socketio_max_http_buffer_size("x") == 65536
        assert resolve_json_max_content_length(None) == 1024 * 1024
        assert resolve_json_max_content_length("2048") == 2048
        assert resolve_json_max_content_length("0") == 1024 * 1024


class TestConnectionRegistry:
    def test_user_over_cap_evicts_the_oldest_not_the_newest(self):
        r = ConnectionRegistry(_limits(max_per_user=2))
        assert r.admit("a", "1.1.1.1", "u1").evict == []
        assert r.admit("b", "1.1.1.1", "u1").evict == []
        adm = r.admit("c", "1.1.1.1", "u1")
        assert adm.refused is None and adm.evict == ["a"]
        assert r.user_sids("u1") == ["b", "c"]
        assert r.total() == 2

    def test_one_user_can_never_hold_more_than_the_cap(self):
        r = ConnectionRegistry(_limits(max_per_user=3, max_total=100))
        for i in range(50):
            adm = r.admit(f"s{i}", "9.9.9.9", "u1")
            assert adm.refused is None
            assert len(r.user_sids("u1")) <= 3
        assert r.total() == 3

    def test_global_ceiling_refuses_new_users_with_server_busy(self):
        r = ConnectionRegistry(_limits(max_total=3, max_per_user=5))
        for i in range(3):
            assert r.admit(f"s{i}", "1.1.1.1", f"u{i}").refused is None
        adm = r.admit("late", "1.1.1.1", "u9")
        assert adm.refused == REFUSE_SERVER_BUSY
        assert r.total() == 3  # a refused socket is not recorded

    def test_a_user_at_the_global_ceiling_can_still_reconnect(self):
        # The user's own oldest socket is replaced, so the total does not grow.
        r = ConnectionRegistry(_limits(max_total=2, max_per_user=1))
        assert r.admit("a", "1.1.1.1", "u1").refused is None
        assert r.admit("b", "1.1.1.1", "u2").refused is None
        adm = r.admit("a2", "1.1.1.1", "u1")
        assert adm.refused is None and adm.evict == ["a"]
        assert r.total() == 2

    def test_guests_are_limited_per_address_and_in_total(self):
        r = ConnectionRegistry(_limits(max_guests_per_ip=2, max_guests_total=3))
        assert r.admit("g1", "1.1.1.1", None).refused is None
        assert r.admit("g2", "1.1.1.1", None).refused is None
        assert r.admit("g3", "1.1.1.1", None).refused == REFUSE_TOO_MANY_FROM_ADDRESS
        assert r.admit("g4", "2.2.2.2", None).refused is None
        assert r.admit("g5", "3.3.3.3", None).refused == REFUSE_SERVER_BUSY
        assert r.guests() == 3

    def test_guests_do_not_block_authenticated_users_per_ip(self):
        # CGNAT: many real users share one address; only guests are per-IP.
        r = ConnectionRegistry(_limits(max_guests_per_ip=1, max_total=50, max_per_user=1))
        assert r.admit("g1", "1.1.1.1", None).refused is None
        for i in range(20):
            assert r.admit(f"s{i}", "1.1.1.1", f"u{i}").refused is None

    def test_release_frees_the_slot_and_is_idempotent(self):
        r = ConnectionRegistry(_limits(max_total=1))
        assert r.admit("a", "1.1.1.1", "u1").refused is None
        assert r.admit("b", "1.1.1.1", "u2").refused == REFUSE_SERVER_BUSY
        assert r.release("a") is True
        assert r.release("a") is False
        assert r.release(None) is False
        assert r.admit("b", "1.1.1.1", "u2").refused is None

    def test_admitting_the_same_sid_twice_is_a_noop(self):
        r = ConnectionRegistry(_limits(max_total=1))
        assert r.admit("a", "1.1.1.1", "u1").refused is None
        assert r.admit("a", "1.1.1.1", "u1").refused is None
        assert r.total() == 1


class TestEventRateLimiter:
    def test_sliding_window(self):
        now = [100.0]
        lim = EventRateLimiter(clock=lambda: now[0])
        assert [lim.allow("k", 3, 10)[0] for _ in range(3)] == [True, True, True]
        ok, retry = lim.allow("k", 3, 10)
        assert ok is False and 1 <= retry <= 11
        now[0] += 10.5
        assert lim.allow("k", 3, 10)[0] is True

    def test_keys_are_independent_and_forgettable(self):
        lim = EventRateLimiter(clock=lambda: 1.0)
        assert lim.allow("sid:a:x", 1, 60)[0] is True
        assert lim.allow("sid:a:x", 1, 60)[0] is False
        assert lim.allow("sid:b:x", 1, 60)[0] is True
        lim.forget_prefix("sid:a:")
        assert lim.allow("sid:a:x", 1, 60)[0] is True
        assert lim.size() == 2

    def test_stale_buckets_are_swept_so_memory_stays_bounded(self):
        now = [0.0]
        lim = EventRateLimiter(clock=lambda: now[0])
        lim._SWEEP_AT = 50
        for i in range(50):
            lim.allow(f"k{i}", 1, 10)
        now[0] = 10_000.0
        lim.allow("fresh", 1, 10)
        assert lim.size() < 50


# ======================================================================
# Full-app tests (Flask + SQLite + Flask-SocketIO test client)
# ======================================================================


@pytest.fixture(scope="module")
def ctx():
    tmp = tempfile.TemporaryDirectory(prefix="carlist_c1_", ignore_cleanup_errors=True)
    os.environ["APP_ENV"] = "testing"
    os.environ["SMS_PROVIDER"] = "console"
    os.environ.pop("LISTING_REQUIRE_APPROVAL", None)
    os.environ["DB_PATH"] = os.path.join(tmp.name, "c1.db")
    os.environ["JSON_MAX_CONTENT_LENGTH"] = "4096"

    from kk.app_factory import create_app

    app, socketio, *_ = create_app()
    from kk.models import db

    with app.app_context():
        db.drop_all()
        db.create_all()
    yield app, socketio, app.test_client()
    with app.app_context():
        db.session.remove()
        db.engine.dispose()
    tmp.cleanup()


def _user(ctx, name):
    app, _sio, _c = ctx
    from kk.models import User, db

    with app.app_context():
        u = User(
            username=f"{name}_{uuid.uuid4().hex[:6]}",
            phone_number=f"077{uuid.uuid4().int % 10**8:08d}",
            first_name=name.title(),
            last_name="Test",
            email=None,
            is_active=True,
            is_verified=True,
            phone_verified=True,
            public_id=f"pub-{uuid.uuid4().hex[:12]}",
        )
        u.set_password(PASSWORD)
        db.session.add(u)
        db.session.commit()
        return u.public_id, u.username


def _token(ctx, username):
    _a, _s, client = ctx
    r = client.post("/api/auth/login", json={"username": username, "password": PASSWORD})
    assert r.status_code == 200, r.data
    return r.get_json()["access_token"]


def _car(ctx, seller_public_id):
    app, _sio, _c = ctx
    from kk.models import Car, User, db

    with app.app_context():
        seller = User.query.filter_by(public_id=seller_public_id).first()
        car = Car(
            seller_id=seller.id,
            brand="toyota",
            model="corolla",
            year=2021,
            mileage=10,
            engine_type="gas",
            transmission="auto",
            drive_type="fwd",
            condition="used",
            body_type="sedan",
            price=15.0,
            location="Erbil",
            is_active=True,
        )
        db.session.add(car)
        db.session.commit()
        return car.public_id


def _connect(ctx, token=None):
    app, sio, client = ctx
    headers = {"Authorization": f"Bearer {token}"} if token else {}
    return sio.test_client(app, flask_test_client=client, headers=headers)


def _named(sock, name):
    return [e for e in sock.get_received() if e["name"] == name]


@pytest.fixture
def world(ctx):
    seller, seller_name = _user(ctx, "seller")
    buyer, buyer_name = _user(ctx, "buyer")
    return {
        "seller": seller,
        "buyer": buyer,
        "buyer_name": buyer_name,
        "seller_name": seller_name,
        "buyer_tok": _token(ctx, buyer_name),
        "seller_tok": _token(ctx, seller_name),
        "car": _car(ctx, seller),
    }


@pytest.fixture
def sh():
    from kk import socketio_handlers

    return socketio_handlers


def _with_limits(monkeypatch, sh, **kw):
    reg = ConnectionRegistry(_limits(**kw))
    monkeypatch.setattr(sh, "_REGISTRY", reg)
    monkeypatch.setattr(sh, "_LIMITER", EventRateLimiter())
    return reg


class TestSocketAdmission:
    def test_third_socket_of_a_user_replaces_the_oldest(self, ctx, world, sh, monkeypatch):
        reg = _with_limits(monkeypatch, sh, max_per_user=2)
        s1 = _connect(ctx, world["buyer_tok"])
        s2 = _connect(ctx, world["buyer_tok"])
        assert s1.is_connected() and s2.is_connected()
        s3 = _connect(ctx, world["buyer_tok"])
        assert s3.is_connected()
        assert not s1.is_connected()  # oldest was dropped
        assert s2.is_connected()
        assert len(reg.user_sids(world["buyer"])) == 2
        evicted = [
            e for e in s1.queue if e.get("name") == "connection_replaced"
        ]
        assert evicted and evicted[0]["args"][0]["code"] == "too_many_connections"

    def test_global_ceiling_refuses_sockets_before_http_threads_run_out(
        self, ctx, world, sh, monkeypatch
    ):
        reg = _with_limits(monkeypatch, sh, max_total=2, max_per_user=5)
        a = _connect(ctx, world["buyer_tok"])
        b = _connect(ctx, world["seller_tok"])
        assert a.is_connected() and b.is_connected()
        other, other_name = _user(ctx, "late")
        late = _connect(ctx, _token(ctx, other_name))
        assert not late.is_connected()
        assert reg.total() == 2
        # ... and REST keeps working while the socket ceiling is hit.
        _a, _s, client = ctx
        r = client.post("/api/auth/login", json={"username": other_name, "password": PASSWORD})
        assert r.status_code == 200

    def test_disconnect_releases_the_slot(self, ctx, world, sh, monkeypatch):
        reg = _with_limits(monkeypatch, sh, max_total=1, max_per_user=5)
        a = _connect(ctx, world["buyer_tok"])
        assert a.is_connected() and reg.total() == 1
        a.disconnect()
        assert reg.total() == 0
        b = _connect(ctx, world["seller_tok"])
        assert b.is_connected() and reg.total() == 1

    def test_guest_sockets_are_capped_per_address(self, ctx, sh, monkeypatch):
        reg = _with_limits(monkeypatch, sh, max_guests_per_ip=2, max_guests_total=10)
        g1, g2, g3 = _connect(ctx), _connect(ctx), _connect(ctx)
        assert g1.is_connected() and g2.is_connected()
        assert not g3.is_connected()
        assert reg.guests() == 2

    def test_guest_connect_without_credentials_still_works_under_default_limits(
        self, ctx, sh, monkeypatch
    ):
        _with_limits(monkeypatch, sh)  # generous defaults for one guest
        g = _connect(ctx)
        assert g.is_connected()
        got = _named(g, "connected")
        assert got and got[0]["args"][0]["authenticated"] is False

    def test_engineio_frame_size_is_capped(self, ctx):
        _app, sio, _c = ctx
        assert sio.server.eio.max_http_buffer_size == 65536


class TestSocketEventLimits:
    def _msg_count(self, ctx):
        app, _s, _c = ctx
        from kk.models import Message

        with app.app_context():
            return Message.query.count()

    def test_send_message_burst_is_limited_and_nothing_extra_is_stored(
        self, ctx, world, sh, monkeypatch
    ):
        _with_limits(monkeypatch, sh)
        monkeypatch.setattr(sh, "_LIMIT_SEND_BURST", (3, 60.0))
        before = self._msg_count(ctx)
        c = _connect(ctx, world["buyer_tok"])
        c.get_received()
        for i in range(8):
            c.emit(
                "send_message",
                {"car_id": world["car"], "receiver_id": world["seller"], "content": f"m{i}"},
            )
        got = c.get_received()
        sent = [e for e in got if e["name"] == "message_sent"]
        limited = [
            e for e in got if e["name"] == "error" and e["args"][0].get("code") == "rate_limited"
        ]
        assert len(sent) == 3
        assert len(limited) == 5
        assert limited[0]["args"][0]["retry_after"] >= 1
        assert self._msg_count(ctx) - before == 3

    def test_user_budget_is_shared_across_all_of_their_sockets(
        self, ctx, world, sh, monkeypatch
    ):
        _with_limits(monkeypatch, sh)
        monkeypatch.setattr(sh, "_LIMIT_SEND_BURST", (100, 60.0))
        monkeypatch.setattr(sh, "_LIMIT_SEND_USER", (3, 600.0))
        a = _connect(ctx, world["buyer_tok"])
        b = _connect(ctx, world["buyer_tok"])
        a.get_received(), b.get_received()
        ok = 0
        for sock in (a, b, a, b, a):
            sock.emit(
                "send_message",
                {"car_id": world["car"], "receiver_id": world["seller"], "content": "hi"},
            )
            ok += len(_named(sock, "message_sent"))
        assert ok == 3

    def test_another_users_budget_is_unaffected(self, ctx, world, sh, monkeypatch):
        _with_limits(monkeypatch, sh)
        monkeypatch.setattr(sh, "_LIMIT_SEND_USER", (1, 600.0))
        b = _connect(ctx, world["buyer_tok"])
        s = _connect(ctx, world["seller_tok"])
        b.get_received(), s.get_received()
        for _ in range(3):
            b.emit(
                "send_message",
                {"car_id": world["car"], "receiver_id": world["seller"], "content": "x"},
            )
        s.emit(
            "send_message",
            {"car_id": world["car"], "receiver_id": world["buyer"], "content": "y"},
        )
        assert len(_named(s, "message_sent")) == 1

    def test_join_chat_flood_is_limited(self, ctx, world, sh, monkeypatch):
        _with_limits(monkeypatch, sh)
        monkeypatch.setattr(sh, "_LIMIT_JOIN", (2, 60.0))
        c = _connect(ctx, world["buyer_tok"])
        c.get_received()
        for _ in range(5):
            c.emit("join_chat", {"car_id": world["car"]})
        got = c.get_received()
        assert len([e for e in got if e["name"] == "joined_chat"]) == 2
        assert len(
            [e for e in got if e["name"] == "error" and e["args"][0].get("code") == "rate_limited"]
        ) == 3

    def test_typing_flood_is_dropped_silently(self, ctx, world, sh, monkeypatch):
        _with_limits(monkeypatch, sh)
        monkeypatch.setattr(sh, "_LIMIT_TYPING", (2, 60.0))
        # A real conversation so typing events are delivered at all.
        b = _connect(ctx, world["buyer_tok"])
        s = _connect(ctx, world["seller_tok"])
        b.emit(
            "send_message",
            {"car_id": world["car"], "receiver_id": world["seller"], "content": "hello"},
        )
        s.emit("join_chat", {"car_id": world["car"], "peer_id": world["buyer"]})
        b.emit("join_chat", {"car_id": world["car"]})
        s.get_received(), b.get_received()
        for _ in range(6):
            b.emit("typing_start", {"car_id": world["car"]})
        typing = _named(s, "typing")
        assert len(typing) == 2
        assert not [e for e in b.get_received() if e["name"] == "error"]

    def test_limits_reset_for_a_new_socket(self, ctx, world, sh, monkeypatch):
        _with_limits(monkeypatch, sh)
        monkeypatch.setattr(sh, "_LIMIT_JOIN", (1, 60.0))
        a = _connect(ctx, world["buyer_tok"])
        a.get_received()
        a.emit("join_chat", {"car_id": world["car"]})
        a.emit("join_chat", {"car_id": world["car"]})
        assert any(
            e["name"] == "error" and e["args"][0].get("code") == "rate_limited"
            for e in a.get_received()
        )
        a.disconnect()
        b = _connect(ctx, world["buyer_tok"])
        b.get_received()
        b.emit("join_chat", {"car_id": world["car"]})
        assert _named(b, "joined_chat")


class TestSocketPayloadValidation:
    @pytest.mark.parametrize("bad", ["just a string", ["a", "list"], 42, None, True])
    def test_non_object_payloads_do_not_crash_handlers(self, ctx, world, sh, monkeypatch, bad):
        _with_limits(monkeypatch, sh)
        c = _connect(ctx, world["buyer_tok"])
        c.get_received()
        for event in ("send_message", "join_chat", "leave_chat", "typing_start", "typing_stop"):
            c.emit(event, bad)
        assert c.is_connected()
        errors = [e for e in c.get_received() if e["name"] == "error"]
        assert any(e["args"][0].get("message") == "car_id required" for e in errors)

    def test_oversized_listing_preview_is_dropped_not_stored(
        self, ctx, world, sh, monkeypatch
    ):
        _with_limits(monkeypatch, sh)
        c = _connect(ctx, world["buyer_tok"])
        c.get_received()
        c.emit(
            "send_message",
            {
                "car_id": world["car"],
                "receiver_id": world["seller"],
                "content": "with preview",
                "listing_preview": {"title": "x" * 20000},
            },
        )
        sent = _named(c, "message_sent")
        assert len(sent) == 1
        assert sent[0]["args"][0]["message"].get("listing_preview") in (None, {})

    def test_small_listing_preview_is_kept(self, ctx, world, sh, monkeypatch):
        _with_limits(monkeypatch, sh)
        c = _connect(ctx, world["buyer_tok"])
        c.get_received()
        c.emit(
            "send_message",
            {
                "car_id": world["car"],
                "receiver_id": world["seller"],
                "content": "small preview",
                "listing_preview": {"title": "Corolla 2021"},
            },
        )
        sent = _named(c, "message_sent")
        assert sent[0]["args"][0]["message"]["listing_preview"] == {"title": "Corolla 2021"}


class TestJsonBodyCap:
    """``JSON_MAX_CONTENT_LENGTH`` is 4096 for this module's app."""

    def test_oversized_json_is_rejected_with_a_json_413(self, ctx):
        _a, _s, client = ctx
        r = client.post("/api/auth/login", json={"username": "a", "password": "p" * 10000})
        assert r.status_code == 413
        body = r.get_json()
        assert body["code"] == "payload_too_large"
        assert body["max_bytes"] == 4096

    def test_normal_json_is_unaffected(self, ctx):
        _a, _s, client = ctx
        r = client.post("/api/auth/login", json={"username": "nobody", "password": "x"})
        assert r.status_code != 413

    def test_body_without_content_length_is_still_bounded(self, ctx):
        from werkzeug.test import EnvironBuilder

        _a, _s, client = ctx
        payload = b'{"username":"a","password":"' + b"p" * 20000 + b'"}'
        environ = EnvironBuilder(
            "/api/auth/login",
            method="POST",
            data=payload,
            content_type="application/json",
        ).get_environ()
        # What Gunicorn presents for a chunked body: no length, but the server
        # already de-chunked it (wsgi.input_terminated).
        environ.pop("CONTENT_LENGTH", None)
        environ["wsgi.input_terminated"] = True
        r = client.open(environ)
        assert r.status_code == 413

    def test_multipart_uploads_are_not_subject_to_the_json_cap(self, ctx):
        # Photo/video uploads keep MAX_CONTENT_LENGTH; the JSON cap must not
        # reject a multipart body (the route itself may answer 401/400).
        _a, _s, client = ctx
        import io

        r = client.post(
            "/api/auth/login",
            data={"file": (io.BytesIO(b"x" * 20000), "a.bin")},
            content_type="multipart/form-data",
        )
        body = r.get_json(silent=True) or {}
        assert body.get("code") != "payload_too_large"

    def test_get_requests_are_never_capped(self, ctx):
        _a, _s, client = ctx
        r = client.get("/api/cars")
        assert r.status_code != 413
