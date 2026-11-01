"""The one-statement typing validator (``kk/typing_authz_validator.py``) and the
"never leave a typing indicator stuck" safeguards.

What is pinned here
-------------------
* PARITY: for every authorization rule (membership, block either direction,
  revoked / logged-out token, ``tokens_invalid_before`` cut-off, inactive or
  NULL-``is_active`` user / seller, working copies, non-public listings, numeric
  vs public car ids, unnamed / unknown peers, listings without a seller, ...)
  the outcome with the validator ON is identical to the outcome with it OFF
  (the original ORM chain): same events relayed, same socket closing. The
  validator may only ever ALLOW; if the ORM chain would deny, it must defer.
* COST: an allowed cache miss costs one statement on the validator's own
  connection and nothing on the application engine.
* FALLBACK: validator busy / unavailable / erroring -> the ORM chain decides.
* CONCURRENCY: parallel validations share one connection, correctly.
* STUCK INDICATORS: a ``typing_stop`` of an open indicator is not rate limited
  and a plain disconnect turns the indicator off; a server-side close because of
  a revoked / expired token still says nothing.

Real Flask app + file-backed SQLite (the validator is opted in with
``CHAT_TYPING_AUTHZ_FAST_VALIDATOR=on``; ``auto`` only enables it on PostgreSQL)
+ the Flask-SocketIO test client; synthetic accounts only.
"""

# ruff: noqa: F811, F401
from __future__ import annotations

import os
import threading
import time
import uuid
from contextlib import contextmanager
from types import SimpleNamespace
from unittest.mock import patch

import pytest

from test_chat_f05_f25_f36_isolation import (  # noqa: F401  (fixtures)
    World,
    _auth,
    _drain,
    _events,
    _sock,
    ctx,
    world,
)
from test_typing_authz_cache import DbCounter, _emit_counted, _per_event_session_teardown, _typing


@pytest.fixture(autouse=True)
def _validator_state():
    from kk import typing_authz_validator as tv

    tv.reset_for_tests()
    yield
    tv.reset_for_tests()


@contextmanager
def _mode(value, ttl=15):
    with patch.dict(os.environ, {"CHAT_TYPING_AUTHZ_FAST_VALIDATOR": value, "CHAT_TYPING_AUTHZ_TTL_SECONDS": str(ttl)}):
        yield


def _stats(reset=False):
    from kk import socketio_handlers as sh

    return sh.typing_authz_stats(reset=reset)


def _orm(ctx, fn):
    app, _sio, _c = ctx
    from kk.models import db

    with app.app_context():
        fn()
        db.session.commit()


def _user_row(public_id):
    from kk.models import User

    return User.query.filter_by(public_id=public_id).first()


# ======================================================== parity matrix ===

SELLER, B1, B2, B3, STRANGER = "s", "b1", "b2", "b3", "x"


def _m_none(ctx, w, actor):
    pass


def _m_block_actor_blocks_other(ctx, w, actor):
    other = w.b1 if actor == SELLER else w.s
    me = w.s if actor == SELLER else w.b1
    r = ctx[2].post(f"/api/users/{other}/block", headers=_auth(w.tok[me]))
    assert r.status_code in (200, 201), r.data


def _m_block_other_blocks_actor(ctx, w, actor):
    other = w.b1 if actor == SELLER else w.s
    me = w.s if actor == SELLER else w.b1
    r = ctx[2].post(f"/api/users/{me}/block", headers=_auth(w.tok[other]))
    assert r.status_code in (200, 201), r.data


def _m_logout_actor(ctx, w, actor):
    uid = {SELLER: w.s, B1: w.b1}[actor]
    assert ctx[2].post("/api/auth/logout", headers=_auth(w.tok[uid]), json={}).status_code in (200, 204)


def _set_user(attr, value, who):
    def mut(ctx, w, actor):
        uid = {"actor": {SELLER: w.s, B1: w.b1}[actor], "seller": w.s}[who]

        def go():
            setattr(_user_row(uid), attr, value)

        _orm(ctx, go)

    return mut


def _m_cutoff_future(ctx, w, actor):
    from datetime import timedelta

    from kk.time_utils import utcnow

    uid = {SELLER: w.s, B1: w.b1}[actor]
    _orm(ctx, lambda: setattr(_user_row(uid), "tokens_invalid_before", utcnow() + timedelta(seconds=5)))


def _m_cutoff_past(ctx, w, actor):
    from datetime import timedelta

    from kk.time_utils import utcnow

    uid = {SELLER: w.s, B1: w.b1}[actor]
    _orm(ctx, lambda: setattr(_user_row(uid), "tokens_invalid_before", utcnow() - timedelta(hours=1)))


def _car_status(value):
    def mut(ctx, w, actor):
        from kk.models import Car

        _orm(ctx, lambda: setattr(Car.query.filter_by(public_id=w.car).first(), "status", value))

    return mut


def _m_seller_removed(ctx, w, actor):
    from kk.models import Car

    _orm(ctx, lambda: setattr(Car.query.filter_by(public_id=w.car).first(), "seller_id", None))


def _m_thread_deleted(ctx, w, actor):
    from kk.models import Message, User, db

    def go():
        me = _user_row(w.b1)
        Message.query.filter((Message.sender_id == me.id) | (Message.receiver_id == me.id)).delete(synchronize_session=False)

    _orm(ctx, go)


MUTATIONS = {
    "none": _m_none,
    "actor_blocks_other": _m_block_actor_blocks_other,
    "other_blocks_actor": _m_block_other_blocks_actor,
    "logout_actor": _m_logout_actor,
    "actor_inactive": _set_user("is_active", False, "actor"),
    "actor_is_active_null": _set_user("is_active", None, "actor"),
    "seller_inactive": _set_user("is_active", False, "seller"),
    "seller_is_active_null": _set_user("is_active", None, "seller"),
    "cutoff_in_future": _m_cutoff_future,
    "cutoff_in_past": _m_cutoff_past,
    "car_sold": _car_status("sold"),
    "car_pending": _car_status("pending"),
    "car_revision": _car_status("revision"),
    "car_archived": _car_status("archived"),
    "car_status_blank": _car_status(""),
    "seller_removed": _m_seller_removed,
    "thread_deleted": _m_thread_deleted,
}

# (id, actor, peer, car_form, mutation, expect_relayed, expect_fast)
#  actor: s / b1 / b2 / b3 / x ; peer: None | actor key | "unknown"
BASE = [
    ("buyer_no_peer", B1, None, "public", "none", True, True),
    ("buyer_names_seller", B1, SELLER, "public", "none", True, True),
    ("buyer_names_unknown_falls_back_to_seller", B1, "unknown", "public", "none", True, True),
    ("buyer_names_other_buyer", B1, B2, "public", "none", False, False),
    ("buyer_numeric_car_id", B1, None, "numeric", "none", True, True),
    ("buyer_whose_message_is_unanswered", B3, None, "public", "none", True, True),
    ("seller_names_buyer", SELLER, B1, "public", "none", True, True),
    ("seller_names_buyer_numeric", SELLER, B1, "numeric", "none", True, True),
    ("seller_names_unknown", SELLER, "unknown", "public", "none", False, False),
    ("seller_without_peer_is_dynamic", SELLER, None, "public", "none", False, False),
    ("stranger_no_peer", STRANGER, None, "public", "none", False, False),
    ("stranger_names_seller", STRANGER, SELLER, "public", "none", False, False),
]
MUT_CASES = []
for _actor, _peer in ((B1, None), (SELLER, B1)):
    for _name, _rel, _fast in (
        ("actor_blocks_other", False, False),
        ("other_blocks_actor", False, False),
        ("logout_actor", False, False),
        ("actor_inactive", False, False),
        ("actor_is_active_null", False, False),
        ("seller_inactive", None, None),  # whatever the ORM chain decides, the validator must agree
        ("seller_is_active_null", None, None),
        ("cutoff_in_future", False, False),
        ("cutoff_in_past", True, True),
        ("car_sold", True, True),
        ("car_pending", None, None),
        ("car_revision", False, False),
        ("car_archived", None, None),
        ("car_status_blank", None, None),
        ("seller_removed", None, None),
        ("thread_deleted", None, None),
    ):
        MUT_CASES.append((f"{'seller' if _actor == SELLER else 'buyer'}_{_name}", _actor, _peer, "public", _name, _rel, _fast))
CASES = BASE + MUT_CASES


def _open(ctx, w, actor, peer, car_form):
    """Actor socket (cold: no join, so its first typing event is a cache miss) + a listener that joined the room."""
    car_id = w.car if car_form == "public" else _numeric_car_id(ctx, w)
    ids = {SELLER: w.s, B1: w.b1, B2: w.b2, B3: w.b3, STRANGER: w.x}
    payload = {"car_id": car_id}
    if peer == "unknown":
        payload["peer_id"] = "pub-" + uuid.uuid4().hex[:12]
    elif peer is not None:
        payload["peer_id"] = ids[peer]
    a = _sock(ctx, w.tok[ids[actor]])
    lst_user = w.b1 if actor == SELLER else w.s
    lst = _sock(ctx, w.tok[lst_user])
    lst.emit("join_chat", {"car_id": w.car} if actor == SELLER else {"car_id": w.car, "peer_id": ids[actor]})
    lst.get_received()
    a.get_received()
    return a, lst, payload


def _numeric_car_id(ctx, w):
    from kk.models import Car

    app, _s, _c = ctx
    with app.app_context():
        return str(Car.query.filter_by(public_id=w.car).first().id)


@pytest.mark.parametrize("name,actor,peer,car_form,mutation,expect_relayed,expect_fast", CASES, ids=[c[0] for c in CASES])
def test_validator_agrees_with_the_orm_chain(ctx, world, name, actor, peer, car_form, mutation, expect_relayed, expect_fast):
    world.seed()
    sockets = {m: _open(ctx, world, actor, peer, car_form) for m in ("off", "on")}
    MUTATIONS[mutation](ctx, world, actor)
    out = {}
    for m in ("off", "on"):
        a, lst, payload = sockets[m]
        with _mode(m):
            for _m2, (_a2, l2, _p2) in sockets.items():
                l2.get_received()  # drop what the other probe's actor caused
            _stats(reset=True)
            a.emit("typing_start", payload)
            out[m] = ([t["typing"] for t in _typing(lst)], a.is_connected(), _stats(reset=True))
    off_relayed, off_conn, _ = out["off"]
    on_relayed, on_conn, on_stats = out["on"]
    # the ORM chain is the reference
    assert (on_relayed, on_conn) == (off_relayed, off_conn), (name, out)
    if expect_relayed is not None:
        assert off_relayed == ([True] if expect_relayed else []), (name, "reference behaviour changed", out["off"])
    fast_allowed = on_stats.get("full_check_fast", 0)
    if not off_relayed:
        assert fast_allowed == 0, (name, "validator allowed what the ORM chain denies", on_stats)
    if expect_fast is True:
        assert fast_allowed == 1 and on_stats.get("full_check_legacy", 0) == 0, (name, on_stats)
    if expect_fast is False:
        assert fast_allowed == 0, (name, on_stats)


# ============================================================ cost / path ===


class TestOneStatementOnItsOwnConnection:
    def test_cold_event_uses_no_application_connection(self, ctx, world):
        from kk import typing_authz_validator as tv

        world.seed()
        a = _sock(ctx, world.tok[world.b1])
        s = _sock(ctx, world.tok[world.s])
        s.emit("join_chat", {"car_id": world.car, "peer_id": world.b1})
        s.get_received()
        with _mode("on"):
            _stats(reset=True)
            c = _emit_counted(ctx, a, "typing_start", {"car_id": world.car})
            stats = _stats()
        assert [t["typing"] for t in _typing(s)] == [True]
        assert (len(c.statements), c.checkouts) == (0, 0), (c.statements, c.checkouts)  # the app engine is untouched
        assert tv.counters()["queries"] == 1 and tv.counters()["connects"] == 1
        assert stats.get("full_check_fast") == 1 and stats.get("full_check") == 1
        assert stats.get("full_check_legacy", 0) == 0

    def test_the_connection_is_reused_across_events_and_sockets(self, ctx, world):
        from kk import typing_authz_validator as tv

        world.seed()
        socks = [_sock(ctx, world.tok[u]) for u in (world.b1, world.b2, world.b3)]
        with _mode("on", ttl=15):
            for sk in socks:
                sk.emit("typing_start", {"car_id": world.car})
        assert tv.counters()["queries"] == 3 and tv.counters()["connects"] == 1

    def test_ttl_zero_and_mode_off_never_touch_the_validator(self, ctx, world):
        from kk import typing_authz_validator as tv

        world.seed()
        a = _sock(ctx, world.tok[world.b1])
        for mode, ttl in (("off", 15), ("on", 0), ("auto", 15)):  # auto == off on SQLite
            with _mode(mode, ttl=ttl):
                a.emit("typing_stop", {"car_id": world.car})
                a.emit("typing_start", {"car_id": world.car})
                a.emit("typing_stop", {"car_id": world.car})
        assert tv.counters()["queries"] == 0

    def test_the_cache_lifetime_is_not_extended(self, ctx, world):
        from kk import socketio_handlers as sh

        world.seed()
        a = _sock(ctx, world.tok[world.b1])
        with _mode("on", ttl=15):
            a.emit("typing_start", {"car_id": world.car})
        (rec,) = [v for v in sh._SOCKET_AUTH.values() if v["user_public_id"] == world.b1]
        (entry,) = rec["authz"].values()
        assert entry["life"] <= 15.0
        assert time.monotonic() - entry["at"] <= 15.0  # ages from the START of the validation


# ============================================== fallback behaviour ===


class TestValidatorFailuresFallBackToTheOrmChain:
    @pytest.mark.parametrize("exc_name,counter", [("ValidatorUnavailable", "fast_unavailable"), ("ValidatorBusy", "fast_busy"), ("RuntimeError", "fast_error")])
    def test_failure_modes_still_relay_via_orm(self, ctx, world, exc_name, counter):
        from kk import typing_authz_validator as tv

        world.seed()
        s = _sock(ctx, world.tok[world.s])
        s.emit("join_chat", {"car_id": world.car, "peer_id": world.b1})
        s.get_received()
        a = _sock(ctx, world.tok[world.b1])
        exc = getattr(tv, exc_name, None) or RuntimeError
        with _mode("on"), patch.object(tv, "_fetch", side_effect=exc("boom")):
            _stats(reset=True)
            a.emit("typing_start", {"car_id": world.car})
            stats = _stats()
        assert [t["typing"] for t in _typing(s)] == [True]
        assert stats.get(counter) == 1 and stats.get("full_check_legacy") == 1 and stats.get("full_check_fast", 0) == 0
        assert a.is_connected()

    def test_failure_does_not_open_the_door_for_a_denied_user(self, ctx, world):
        from kk import typing_authz_validator as tv

        world.seed()
        s = _sock(ctx, world.tok[world.s])
        s.emit("join_chat", {"car_id": world.car})
        s.get_received()
        x = _sock(ctx, world.tok[world.x])
        with _mode("on"), patch.object(tv, "_fetch", side_effect=tv.ValidatorUnavailable("down")):
            x.emit("typing_start", {"car_id": world.car})
            x.emit("typing_start", {"car_id": world.car, "peer_id": world.s})
        assert _typing(s) == []

    def test_a_dead_database_opens_the_circuit_and_is_not_retried_every_event(self, ctx, world):
        from kk import typing_authz_validator as tv

        world.seed()
        app, _s, _c = ctx
        with app.app_context():
            from kk.models import db

            url = db.engine.url
        calls = {"n": 0}

        def broken(_url):
            calls["n"] += 1
            raise OSError("db unreachable")

        claims = {"sub": world.b1, "iat": int(time.time()), "jti": "j"}
        kwargs = dict(user_id=1, user_public_id=world.b1, claims=claims, car_raw=world.car, peer_raw="")
        with _mode("on"), patch.object(tv, "_create_engine", side_effect=broken):
            with pytest.raises(tv.ValidatorUnavailable):
                tv.validate(url, **kwargs)
            first = calls["n"]
            assert first == 2  # one retry on a fresh connection
            for _ in range(5):
                with pytest.raises(tv.ValidatorUnavailable):
                    tv.validate(url, **kwargs)
            assert calls["n"] == first  # circuit open: no further attempts for RETRY_AFTER_SECONDS

    @pytest.mark.parametrize(
        "car_raw",
        ["99999999999999999999", "2147483648", "0", "9" * 500, "a\x00b", "١٢٣", "x" * 129],
        ids=["huge_int", "just_over_int4", "zero", "very_long", "nul_byte", "non_ascii_digits", "over_max_len"],
    )
    def test_client_controlled_ids_cannot_break_or_disable_the_validator(self, ctx, world, car_raw):
        """A statement error caused by client input must not look like a dead connection (that would open the circuit for everybody)."""
        from kk import typing_authz_validator as tv

        world.seed()
        app, _s, _c = ctx
        with app.app_context():
            from kk.models import db

            url = db.engine.url
            uid = _user_row(world.b1).id
        claims = {"sub": world.b1, "iat": int(time.time()), "jti": "j"}
        with _mode("on"):
            verdict, why = tv.validate(url, user_id=uid, user_public_id=world.b1, claims=claims, car_raw=car_raw, peer_raw="")
            assert verdict is None  # deferred / no such listing: the ORM chain decides
            assert tv.counters()["errors"] == 0 and tv._STATE["down_until"] == 0.0
            verdict, why = tv.validate(url, user_id=uid, user_public_id=world.b1, claims=claims, car_raw=world.car, peer_raw="")
            assert verdict is not None and why == "allow"  # still fully functional afterwards
            verdict, why = tv.validate(url, user_id=uid, user_public_id=world.b1, claims=claims, car_raw=world.car, peer_raw="q" * 129)
            assert verdict is None and why == "bad_input" and tv.counters()["errors"] == 0

    def test_busy_connection_defers_instead_of_queueing_forever(self, ctx, world):
        from kk import typing_authz_validator as tv

        world.seed()
        app, _s, _c = ctx
        with app.app_context():
            from kk.models import db

            url = db.engine.url
        claims = {"sub": world.b1, "iat": int(time.time()), "jti": "j"}
        assert tv._LOCK.acquire(timeout=1)
        try:
            with patch.object(tv, "LOCK_WAIT_SECONDS", 0.05):
                t0 = time.monotonic()
                with pytest.raises(tv.ValidatorBusy):
                    tv.validate(url, user_id=1, user_public_id=world.b1, claims=claims, car_raw=world.car, peer_raw="")
                assert time.monotonic() - t0 < 1.0
        finally:
            tv._LOCK.release()

    def test_a_dropped_connection_is_replaced_once(self, ctx, world):
        from kk import typing_authz_validator as tv

        world.seed()
        app, _s, _c = ctx
        with app.app_context():
            from kk.models import db

            url = db.engine.url
            uid = _user_row(world.b1).id
        claims = {"sub": world.b1, "iat": int(time.time()), "jti": "j"}
        kwargs = dict(user_id=uid, user_public_id=world.b1, claims=claims, car_raw=world.car, peer_raw="")
        with _mode("on"):
            verdict, why = tv.validate(url, **kwargs)
            assert verdict is not None and why == "allow"
            from sqlalchemy.exc import OperationalError

            # simulate the server having dropped the idle connection: the next use fails once
            with patch.object(tv._STATE["engine"], "connect", side_effect=OperationalError("select", {}, Exception("server closed the connection"))):
                verdict, why = tv.validate(url, **kwargs)
            assert verdict is not None and why == "allow"
        c = tv.counters()
        assert c["connects"] == 2 and c["errors"] == 1


class TestRedisRevocationStillWins:
    def test_a_token_revoked_in_redis_is_never_fast_allowed(self, ctx, world):
        world.seed()
        s = _sock(ctx, world.tok[world.s])
        s.emit("join_chat", {"car_id": world.car, "peer_id": world.b1})
        s.get_received()
        a = _sock(ctx, world.tok[world.b1])

        class Revoked:
            def exists(self, key):
                return str(key).startswith("bl:jti:")

        with _mode("on"), patch("kk.routes.auth._redis_client", return_value=Revoked()):
            _stats(reset=True)
            a.emit("typing_start", {"car_id": world.car})
            stats = _stats()
        assert stats.get("fast_defer_revoked") == 1 and stats.get("full_check_fast", 0) == 0
        assert _typing(s) == []  # and the ORM chain (which also reads Redis first) denies it
        assert not a.is_connected()

    def test_redis_lookup_error_is_ignored_and_the_database_blocklist_still_revokes(self, ctx, world):
        """A Redis ``bl:jti`` lookup error is ignored (exactly as in the existing
        loader); the database blocklist, read by the same statement, still revokes.
        A token revoked ONLY in Redis while Redis is unreachable is not detected here
        -- nor by the existing loader."""
        world.seed()
        s = _sock(ctx, world.tok[world.s])
        s.emit("join_chat", {"car_id": world.car, "peer_id": world.b1})
        s.get_received()
        a = _sock(ctx, world.tok[world.b1])
        assert ctx[2].post("/api/auth/logout", headers=_auth(world.tok[world.b1]), json={}).status_code in (200, 204)

        class Down:
            def exists(self, key):
                raise ConnectionError("redis down")

        with _mode("on"), patch("kk.routes.auth._redis_client", return_value=Down()):
            a.emit("typing_start", {"car_id": world.car})
        assert _typing(s) == []
        assert not a.is_connected()


class TestAChangeDuringTheValidatorQueryIsNeverCached:
    def test_eviction_between_read_and_store_skips_the_store(self, ctx, world):
        """The eviction generation is taken before the validator reads, so a
        block / logout / listing change that lands while it runs prevents the
        (possibly stale) result from being cached. The racing event itself is
        relayed once, exactly like the ORM chain."""
        from kk import socketio_handlers as sh
        from kk import typing_authz_validator as tv

        world.seed()
        s = _sock(ctx, world.tok[world.s])
        s.emit("join_chat", {"car_id": world.car, "peer_id": world.b1})
        s.get_received()
        b = _sock(ctx, world.tok[world.b1])
        real, fired = tv._fetch, []

        def fetch_then_something_changes(url, params):
            row = real(url, params)
            if not fired:
                fired.append(1)
                sh.evict_typing_authz(user_ids=[params["me_id"]])  # another request's commit
            return row

        with _mode("on"), patch.object(tv, "_fetch", fetch_then_something_changes):
            _stats(reset=True)
            b.emit("typing_start", {"car_id": world.car})
            stats = _stats()
        assert fired and _typing_states(s) == [True]
        assert stats.get("skip_store_evicted") == 1 and stats.get("store", 0) == 0
        ((_sid, rec),) = [(k, v) for k, v in sh._SOCKET_AUTH.items() if v["user_public_id"] == world.b1]
        assert rec["authz"] == {}
        with _mode("on"):
            b.emit("typing_stop", {"car_id": world.car})  # nothing cached -> validated again, then cached
            assert _stats().get("full_check_fast") == 2
            assert list(rec["authz"]) == [(world.car, "")]


class TestRolloutSwitch:
    """The new authorization path is OFF unless explicitly switched on."""

    def test_default_is_off_for_every_backend(self):
        from sqlalchemy.engine import make_url

        from kk import typing_authz_validator as tv

        with patch.dict(os.environ):
            os.environ.pop("CHAT_TYPING_AUTHZ_FAST_VALIDATOR", None)
            assert tv.mode() == "off"
            for url in ("postgresql+psycopg://u@127.0.0.1/db", "sqlite:////tmp/x.db", "sqlite://"):
                assert tv.enabled(make_url(url)) is False

    @pytest.mark.parametrize("raw", ["", "off", "OFF", "0", "false", "no", "enabled", "yes please", "autoo", " "])
    def test_unset_unknown_or_garbled_values_are_off(self, raw):
        from sqlalchemy.engine import make_url

        from kk import typing_authz_validator as tv

        with patch.dict(os.environ, {"CHAT_TYPING_AUTHZ_FAST_VALIDATOR": raw}):
            assert tv.mode() == "off" and tv.enabled(make_url("postgresql+psycopg://u@127.0.0.1/db")) is False

    def test_auto_means_postgresql_only_and_on_needs_a_file_database(self):
        from sqlalchemy.engine import make_url

        from kk import typing_authz_validator as tv

        pg, lite, mem = make_url("postgresql+psycopg://u@127.0.0.1/db"), make_url("sqlite:////tmp/x.db"), make_url("sqlite://")
        with patch.dict(os.environ, {"CHAT_TYPING_AUTHZ_FAST_VALIDATOR": "auto"}):
            assert (tv.enabled(pg), tv.enabled(lite), tv.enabled(mem)) == (True, False, False)
        with patch.dict(os.environ, {"CHAT_TYPING_AUTHZ_FAST_VALIDATOR": "on"}):
            assert (tv.enabled(pg), tv.enabled(lite), tv.enabled(mem)) == (True, True, False)

    def test_a_default_run_never_touches_the_validator(self, ctx, world):
        from kk import typing_authz_validator as tv

        world.seed()
        s = _sock(ctx, world.tok[world.s])
        s.emit("join_chat", {"car_id": world.car, "peer_id": world.b1})
        s.get_received()
        b = _sock(ctx, world.tok[world.b1])
        with patch.dict(os.environ, {"CHAT_TYPING_AUTHZ_TTL_SECONDS": "15"}):
            os.environ.pop("CHAT_TYPING_AUTHZ_FAST_VALIDATOR", None)
            _stats(reset=True)
            b.emit("typing_start", {"car_id": world.car})
            stats = _stats()
        assert [t["typing"] for t in _typing(s)] == [True]
        assert tv.counters() == {"queries": 0, "connects": 0, "errors": 0}
        assert stats.get("full_check_legacy") == 1 and stats.get("full_check_fast", 0) == 0


def _row(**over):
    base = dict(
        me_id=1, me_public_id="pub-me", me_active=True, me_first_name="A", me_last_name="B", me_cutoff=None,
        car_id=10, car_public_id="car-1", car_seller_id=2, car_status="active", seller_uid=2, seller_active=True,
        named_id=None, recv_id=2, recv_public_id="pub-seller", is_member=True, has_prior=False, is_blocked=False, jti_revoked=False,
    )
    base.update(over)
    return base


class TestDecideRulesOnRawFacts:
    """Every rule of the allow decision on synthetic facts (NULLs included): it allows only when ALL hold."""

    claims = {"sub": "pub-me", "iat": 1_800_000_000, "jti": "j"}

    def _decide(self, row, claims=None, peer_raw=""):
        from kk import typing_authz_validator as tv

        return tv.decide(row, user_id=1, user_public_id="pub-me", claims=claims or self.claims, peer_raw=peer_raw)

    def test_the_baseline_row_is_allowed(self):
        v, why = self._decide(_row())
        assert why == "allow" and (v.me.id, v.car.public_id, v.peer.public_id) == (1, "car-1", "pub-seller")

    @pytest.mark.parametrize(
        "over,why",
        [
            (dict(me_id=None), "no_user"),
            (dict(me_id=5), "identity"),
            (dict(me_public_id="pub-someone-else"), "identity"),
            (dict(me_active=False), "inactive"),
            (dict(me_active=None), "inactive"),
            (dict(jti_revoked=True), "revoked"),
            (dict(car_id=None), "no_car"),
            (dict(car_public_id=None), "no_public_id"),
            (dict(car_status="revision"), "working_copy"),
            (dict(car_status=" REVISION "), "working_copy"),
            (dict(is_member=False, car_seller_id=3, recv_id=3), "no_membership"),
            (dict(recv_id=None), "no_peer"),
            (dict(recv_id=1), "no_peer"),
            (dict(recv_public_id=None), "no_peer"),
            (dict(is_blocked=True), "blocked"),
            # first contact on a non-public listing needs an existing thread
            (dict(car_status="pending"), "peer_not_allowed"),
            (dict(car_status="hidden"), "peer_not_allowed"),
            (dict(car_status="draft"), "peer_not_allowed"),
            (dict(car_status="archived"), "peer_not_allowed"),
            (dict(seller_active=False), "peer_not_allowed"),
            (dict(seller_active=None), "peer_not_allowed"),
            # a seller who did not name the buyer is resolved dynamically by the ORM chain
            (dict(car_seller_id=1, named_id=None, recv_id=None), "dynamic_peer"),
        ],
    )
    def test_each_failed_rule_defers(self, over, why):
        v, got = self._decide(_row(**over))
        assert v is None and got == why

    def test_non_public_listing_is_allowed_with_an_existing_thread_and_blocks_still_win(self):
        assert self._decide(_row(car_status="pending", has_prior=True))[1] == "allow"
        assert self._decide(_row(seller_active=False, has_prior=True))[1] == "allow"
        assert self._decide(_row(car_status="pending", has_prior=True, is_blocked=True))[1] == "blocked"

    def test_status_variants_that_the_orm_chain_treats_as_public(self):
        for status in ("active", "sold", "ACTIVE", " Sold ", "", None):
            assert self._decide(_row(car_status=status))[1] == "allow", status

    def test_a_seller_with_a_named_buyer_needs_a_thread_with_that_buyer(self):
        row = dict(car_seller_id=1, named_id=7, recv_id=7, recv_public_id="pub-b", is_member=True)
        assert self._decide(_row(**row))[1] == "peer_not_allowed"
        assert self._decide(_row(has_prior=True, **row))[1] == "allow"

    @pytest.mark.parametrize(
        "claims,why",
        [
            ({"sub": "pub-other", "iat": 1_800_000_000, "jti": "j"}, "identity"),
            ({"sub": None, "iat": 1_800_000_000, "jti": "j"}, "identity"),
            ({"sub": "user:1", "iat": 1_800_000_000, "jti": "j"}, "identity"),  # other identity spellings: the ORM chain
        ],
    )
    def test_the_token_subject_must_be_exactly_the_bound_account(self, claims, why):
        assert self._decide(_row(), claims=claims)[1] == why

    def test_cutoff_compares_the_token_issue_time_like_the_loader_does(self):
        from datetime import datetime, timezone

        iat = 1_800_000_000
        issued = datetime.fromtimestamp(iat, tz=timezone.utc).replace(tzinfo=None)
        from datetime import timedelta

        assert self._decide(_row(me_cutoff=issued + timedelta(seconds=1)))[1] == "cutoff"
        assert self._decide(_row(me_cutoff=issued))[1] == "allow"  # strictly before is revoked
        assert self._decide(_row(me_cutoff=issued - timedelta(seconds=1)))[1] == "allow"
        assert self._decide(_row(me_cutoff=issued + timedelta(days=1)), claims={"sub": "pub-me", "jti": "j"})[1] == "allow"  # no iat: the loader skips it too


class TestHostileStringsAreHarmless:
    @pytest.mark.parametrize(
        "text",
        ["' OR '1'='1", "'; DROP TABLE car; --", "%", "_", "\\", "1 OR 1=1", "null", "None", "-1", "1.5", "0x10", "\u202e", "😀", " ", "\t", "../etc/passwd", "car'--"],
    )
    def test_same_outcome_with_and_without_the_validator(self, ctx, world, text):
        world.seed()
        sockets = {}
        for m in ("off", "on"):
            a = _sock(ctx, world.tok[world.b1])
            lst = _sock(ctx, world.tok[world.s])
            lst.emit("join_chat", {"car_id": world.car, "peer_id": world.b1})
            lst.get_received()
            a.get_received()
            sockets[m] = (a, lst)
        payloads = [{"car_id": text}, {"car_id": text, "peer_id": world.s}, {"car_id": world.car, "peer_id": text}, {"car_id": world.car, "receiver_id": text}]
        for payload in payloads:
            out = {}
            for m in ("off", "on"):
                a, lst = sockets[m]
                with _mode(m):
                    for _m2, (_a2, l2) in sockets.items():
                        l2.get_received()
                    _stats(reset=True)
                    a.emit("typing_start", payload)
                    a.emit("typing_stop", payload)
                    out[m] = ([t["typing"] for t in _typing(lst)], a.is_connected(), _stats(reset=True))
            assert out["on"][:2] == out["off"][:2], (payload, out)
            if not out["off"][0]:
                assert out["on"][2].get("full_check_fast", 0) == 0, (payload, out)
        # the data is intact and the validator still works afterwards
        from kk import typing_authz_validator as tv

        assert tv.counters()["errors"] == 0
        with _mode("on"):
            sockets["on"][0].emit("typing_start", {"car_id": world.car})
        assert [t["typing"] for t in _typing(sockets["on"][1])][-1:] in ([True], [])  # relayed or de-duplicated, never an error
        assert _stats().get("fast_error", 0) == 0


class TestLimiterAndValidator:
    def test_validator_allowed_events_do_not_queue_but_denials_still_wait_in_the_orm_fallback(self, ctx, world):
        from kk import socketio_handlers as sh

        world.seed()
        s = _sock(ctx, world.tok[world.s])
        s.emit("join_chat", {"car_id": world.car, "peer_id": world.b1})
        s.get_received()
        b = _sock(ctx, world.tok[world.b1])
        x = _sock(ctx, world.tok[world.x])
        with patch.dict(os.environ, {"CHAT_TYPING_FULLCHECK_CONCURRENCY": "2"}), patch.object(sh, "_FULLCHECK_SEM", None), patch.object(sh, "_FULLCHECK_WAIT_SECONDS", 0.1):
            with _mode("on"):
                sem = sh._fullcheck_semaphore()
                assert sem.acquire(blocking=False) and sem.acquire(blocking=False)  # every ORM slot busy
                _stats(reset=True)
                try:
                    t0 = time.monotonic()
                    b.emit("typing_start", {"car_id": world.car})
                    allowed_wait = time.monotonic() - t0
                    x.emit("typing_start", {"car_id": world.car})
                finally:
                    sem.release()
                    sem.release()
                stats = _stats()
        assert [t["typing"] for t in _typing(s)] == [True]  # the stranger is still refused
        assert allowed_wait < 0.09, "an allowed event must not wait for an ORM slot"
        assert stats.get("full_check_fast") == 1 and stats.get("limiter_timeout") == 1 and stats.get("full_denied") == 1, stats


class TestIdleAndSlowConnections:
    def _url_and_user(self, ctx, world):
        app, _s, _c = ctx
        with app.app_context():
            from kk.models import db

            return db.engine.url, _user_row(world.b1).id

    def test_a_long_idle_connection_is_replaced_before_use(self, ctx, world):
        from kk import typing_authz_validator as tv

        world.seed()
        url, uid = self._url_and_user(ctx, world)
        claims = {"sub": world.b1, "iat": int(time.time()), "jti": "j"}
        kw = dict(user_id=uid, user_public_id=world.b1, claims=claims, car_raw=world.car, peer_raw="")
        with _mode("on"):
            assert tv.validate(url, **kw)[1] == "allow"
            assert tv.counters()["connects"] == 1
            tv.validate(url, **kw)
            assert tv.counters()["connects"] == 1  # reused while warm
            tv._STATE["last_used"] -= tv.IDLE_RECYCLE_SECONDS + 1  # as if nothing had used it for 5+ minutes
            assert tv.validate(url, **kw)[1] == "allow"
            assert tv.counters()["connects"] == 2 and tv.counters()["errors"] == 0

    def test_a_slow_failure_is_not_retried_but_a_quick_one_is(self, ctx, world):
        from sqlalchemy.exc import OperationalError

        from kk import typing_authz_validator as tv

        world.seed()
        url, uid = self._url_and_user(ctx, world)
        claims = {"sub": world.b1, "iat": int(time.time()), "jti": "j"}
        kw = dict(user_id=uid, user_public_id=world.b1, claims=claims, car_raw=world.car, peer_raw="")
        err = OperationalError("select", {}, Exception("timeout"))
        with _mode("on"):
            tv.validate(url, **kw)
            attempts = {"n": 0}

            def slow_failure(*_a, **_k):
                attempts["n"] += 1
                raise err

            with patch.object(tv, "QUICK_FAIL_SECONDS", -1.0), patch.object(tv._STATE["engine"], "connect", side_effect=slow_failure):
                with pytest.raises(tv.ValidatorUnavailable):
                    tv.validate(url, **kw)
            assert attempts["n"] == 1  # "slow" (every failure counts as slow here): no second attempt
            assert tv._STATE["down_until"] > time.monotonic()  # the circuit is open: the ORM chain serves for a few seconds


# ================================================== parallel validation ===


class TestConcurrentValidations:
    def test_many_threads_share_one_connection_and_all_get_the_right_answer(self, ctx, world):
        from kk import typing_authz_validator as tv

        world.seed()
        app, _s, _c = ctx
        with app.app_context():
            from kk.models import db

            url = db.engine.url
            ids = {u: _user_row(u).id for u in (world.b1, world.b2, world.x)}
        results, errors = [], []

        def worker(user, expect_allow):
            claims = {"sub": user, "iat": int(time.time()), "jti": "j-" + user}
            try:
                for _ in range(10):
                    v, why = tv.validate(url, user_id=ids[user], user_public_id=user, claims=claims, car_raw=world.car, peer_raw="")
                    results.append((user, v is not None, why))
            except Exception as exc:  # noqa: BLE001
                errors.append(exc)

        with _mode("on"):
            threads = [threading.Thread(target=worker, args=(u, u != world.x)) for u in (world.b1, world.b2, world.x) * 4]
            [t.start() for t in threads]
            [t.join(30) for t in threads]
        assert not errors, errors
        assert len(results) == 120
        for user, allowed, why in results:
            assert allowed == (user != world.x), (user, why)
        c = tv.counters()
        assert c["queries"] == 120 and c["connects"] == 1 and c["errors"] == 0

    def test_a_burst_of_cold_sockets_is_one_query_each(self, ctx, world):
        from kk import typing_authz_validator as tv

        world.seed()
        s = _sock(ctx, world.tok[world.s])
        s.emit("join_chat", {"car_id": world.car})
        s.get_received()
        buyers = [_sock(ctx, world.tok[u]) for u in (world.b1, world.b2, world.b3)]
        with _mode("on"):
            _stats(reset=True)
            for b in buyers:
                b.emit("typing_start", {"car_id": world.car})
            stats = _stats()
        assert stats.get("full_check_fast") == 3 and stats.get("full_check_legacy", 0) == 0
        assert tv.counters()["queries"] == 3


# ========================================================= stuck typing ===


def _typing_states(sock):
    return [t["typing"] for t in _typing(sock)]


class TestTypingIndicatorsAreNeverLeftOn:
    def _setup(self, ctx, world):
        world.seed()
        s = _sock(ctx, world.tok[world.s])
        s.emit("join_chat", {"car_id": world.car, "peer_id": world.b1})
        s.get_received()
        b = _sock(ctx, world.tok[world.b1])
        b.emit("join_chat", {"car_id": world.car})
        b.get_received()
        return s, b

    def test_a_stop_of_an_open_indicator_is_not_rate_limited(self, ctx, world):
        s, b = self._setup(ctx, world)
        with _mode("off"):
            b.emit("typing_start", {"car_id": world.car})
            assert _typing_states(s) == [True]
            for i in range(60):  # exhaust the per-socket budget (30 events / 10 s) on other conversations
                b.emit("typing_start", {"car_id": f"no-such-car-{i}"})
            _stats(reset=True)
            b.emit("typing_stop", {"car_id": world.car})
            stats = _stats()
        assert _typing_states(s) == [False]
        assert stats.get("stop_exempt_rate_limit") == 1

    def test_a_stop_for_something_that_is_not_open_is_still_rate_limited(self, ctx, world):
        s, b = self._setup(ctx, world)
        with _mode("off"):
            for i in range(60):
                b.emit("typing_start", {"car_id": f"no-such-car-{i}"})
            _stats(reset=True)
            b.emit("typing_stop", {"car_id": world.car})
            stats = _stats()
        assert _typing_states(s) == []
        assert stats.get("drop_rate_limit") == 1 and stats.get("stop_exempt_rate_limit", 0) == 0

    def test_exempt_stops_cannot_be_used_to_flood(self, ctx, world):
        """Exemption is bounded by the starts that were relayed: a second stop is a duplicate."""
        s, b = self._setup(ctx, world)
        with _mode("off"):
            b.emit("typing_start", {"car_id": world.car})
            for i in range(60):
                b.emit("typing_start", {"car_id": f"no-such-car-{i}"})
            for _ in range(20):
                b.emit("typing_stop", {"car_id": world.car})
        assert _typing_states(s) == [True, False]

    def test_disconnect_turns_an_open_indicator_off(self, ctx, world):
        s, b = self._setup(ctx, world)
        b.emit("typing_start", {"car_id": world.car})
        assert _typing_states(s) == [True]
        b.disconnect()
        assert _typing_states(s) == [False]
        assert _stats().get("typing_closed_on_unbind", 0) >= 1

    def test_disconnect_is_silent_when_nothing_is_open(self, ctx, world):
        s, b = self._setup(ctx, world)
        b.disconnect()
        assert _typing_states(s) == []

    def test_disconnect_after_a_normal_stop_adds_nothing(self, ctx, world):
        s, b = self._setup(ctx, world)
        b.emit("typing_start", {"car_id": world.car})
        b.emit("typing_stop", {"car_id": world.car})
        b.disconnect()
        assert _typing_states(s) == [True, False]

    def test_disconnect_stop_goes_only_to_the_conversation_it_was_sent_to(self, ctx, world):
        s, b = self._setup(ctx, world)
        other = _sock(ctx, world.tok[world.b2])
        other.emit("join_chat", {"car_id": world.car})
        other.get_received()
        b.emit("typing_start", {"car_id": world.car})
        b.disconnect()
        assert _typing(other) == []
        assert _typing_states(s) == [True, False]

    def test_a_server_side_close_for_a_revoked_token_still_says_nothing(self, ctx, world):
        s, b = self._setup(ctx, world)
        b.emit("typing_start", {"car_id": world.car})
        assert _typing_states(s) == [True]
        assert ctx[2].post("/api/auth/logout", headers=_auth(world.tok[world.b1]), json={}).status_code in (200, 204)
        b.emit("typing_start", {"car_id": world.car, "peer_id": world.s})
        assert not b.is_connected()
        assert _typing(s) == []

    def test_open_indicator_tracking_is_bounded(self, ctx, world):
        from kk import socketio_handlers as sh

        s, b = self._setup(ctx, world)
        with _mode("off"):
            for i in range(sh._TYPING_STATE_MAX_ENTRIES + 20):
                sh._mark_typing_open(next(iter(sh._SOCKET_AUTH)), (f"c{i}", ""), True, {"room": "r", "car_id": f"c{i}", "peer_id": "p", "user_id": "u"})
        for rec in sh._SOCKET_AUTH.values():
            assert len(rec["typing_open"]) <= sh._TYPING_STATE_MAX_ENTRIES
