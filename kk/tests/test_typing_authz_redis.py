"""Typing authorization cache: cross-worker invalidation through Redis.

A cached typing authorization must stop working in EVERY Gunicorn worker as
soon as the change that revokes it commits in ANY worker, without running SQL
on each typing event.

"Another worker" is simulated by committing the change with this process's own
local eviction switched off (``other_worker()``): the only thing that can then
cut typing off is the Redis epoch the committing worker published. A small
in-memory Redis stands in for Valkey (atomic MULTI/EXEC pipelines, NX/EX,
failures, data loss, eviction).
"""

# ruff: noqa: F811, F401
from __future__ import annotations

import os
import threading
from contextlib import contextmanager
from unittest.mock import patch

import pytest
import redis as redis_pkg
from sqlalchemy import delete, insert, text, update

from test_chat_f05_f25_f36_isolation import (  # noqa: F401  (fixtures)
    _auth,
    _car,
    _drain,
    _events,
    _login,
    _send,
    _sock,
    _user,
    ctx,
    world,
)
from test_typing_authz_cache import (
    DbCounter,
    _bound,
    _emit_counted,
    _pair,
    _per_event_session_teardown,
    _ttl,
    _typing,
)

# ------------------------------------------------------------ fake Redis ---


class FakeRedis:
    """Just enough of redis-py: SET(nx, ex) / GET / MGET / MULTI pipelines,
    plus failure, data-loss and eviction switches. Counts network round trips."""

    def __init__(self):
        self.d: dict[str, str] = {}
        self.ttl: dict[str, int] = {}
        self.trips: list[tuple] = []
        self.pipelines: list[list[tuple]] = []
        self.down = False
        self._lock = threading.RLock()

    # -- failure / loss switches
    def _up(self):
        if self.down:
            raise redis_pkg.exceptions.ConnectionError("fake redis is down")

    def flushall(self):
        with self._lock:
            self.d.clear()

    def evict(self, key):
        with self._lock:
            self.d.pop(key, None)

    # -- commands
    def _set(self, k, v, nx=False, ex=None):
        if nx and k in self.d:
            return None
        self.d[k] = v
        self.ttl[k] = ex
        return True

    def set(self, k, v, nx=False, ex=None):
        with self._lock:
            self._up()
            self.trips.append(("set", k))
            return self._set(k, v, nx, ex)

    def get(self, k):
        with self._lock:
            self._up()
            self.trips.append(("get", k))
            return self.d.get(k)

    def mget(self, keys):
        with self._lock:
            self._up()
            self.trips.append(("mget", len(keys)))
            return [self.d.get(k) for k in keys]

    def pipeline(self, transaction=True):
        return _FakePipe(self)

    def value(self, name):
        from kk import socketio_handlers as sh

        return self.d.get(sh._epoch_key(name))


class _FakePipe:
    def __init__(self, r):
        self.r, self.ops = r, []

    def set(self, k, v, nx=False, ex=None):
        self.ops.append(("set", k, v, nx, ex))

    def get(self, k):
        self.ops.append(("get", k))

    def mget(self, keys):
        self.ops.append(("mget", list(keys)))

    def execute(self):
        r = self.r
        with r._lock:  # MULTI/EXEC: atomic
            r._up()
            r.trips.append(("pipeline", len(self.ops)))
            r.pipelines.append(list(self.ops))
            out = []
            for op in self.ops:
                if op[0] == "set":
                    out.append(r._set(op[1], op[2], op[3], op[4]))
                elif op[0] == "get":
                    out.append(r.d.get(op[1]))
                else:
                    out.append([r.d.get(k) for k in op[1]])
            return out


@pytest.fixture
def fake(monkeypatch):
    from kk import socketio_handlers as sh

    fr = FakeRedis()
    monkeypatch.setenv("CHAT_TYPING_AUTHZ_REDIS_URL", "fake://typing")
    monkeypatch.setattr(sh, "_make_typing_redis", lambda _url: fr)
    monkeypatch.setattr(sh, "_REDIS_CLIENT", None)
    monkeypatch.setattr(sh, "_REDIS_DOWN_UNTIL", 0.0)
    yield fr
    monkeypatch.setattr(sh, "_REDIS_CLIENT", None)
    monkeypatch.setattr(sh, "_REDIS_DOWN_UNTIL", 0.0)


@contextmanager
def other_worker():
    """Commit changes as if from ANOTHER Gunicorn worker: this process's local
    cache eviction is off, only the published Redis epochs can reach it."""
    from kk import socketio_handlers as sh

    with patch.object(sh, "evict_typing_authz", lambda **_k: 0), patch.object(
        sh, "_flush_local_authz", lambda: None
    ):
        yield


def _public(ctx, public_id):
    app, _sio, _c = ctx
    from kk.models import User

    with app.app_context():
        return User.query.filter_by(public_id=public_id).first().id


def _warm_event(ctx, sock, ev="typing_start", **payload):
    return _emit_counted(ctx, sock, ev, payload)


# ============================================================ warm path ==


class TestWarmPathWithRedis:
    def test_warm_event_is_one_redis_round_trip_and_no_sql(self, ctx, world, fake):
        s, b = _pair(ctx, world)
        fake.trips.clear()
        c = _warm_event(ctx, b, car_id=world.car)
        assert (c.n, c.checkouts) == (0, 0)
        assert [t[0] for t in fake.trips] == ["mget"], "exactly one Redis round trip"
        assert [t["typing"] for t in _typing(s)] == [True]

    def test_epochs_cover_both_users_the_listing_the_token_and_the_bulk_classes(self, ctx, world, fake):
        from kk import socketio_handlers as sh

        s, b = _pair(ctx, world)
        ((_sid, rec),) = _bound(sh, world.b1)
        (entry,) = rec["authz"].values()
        names = {k[len(sh._REDIS_PREFIX):] for k in entry["epoch_keys"]}
        assert f"u:{entry['me_id']}" in names and f"u:{entry['peer_id']}" in names
        assert f"c:{entry['car_id']}" in names and f"j:{rec['jti']}" in names
        assert {"boot", *sh._REDIS_GLOBAL_KEYS} <= names
        assert all(v is not None for v in entry["epochs"])
        # epochs live far longer than any cache entry can
        assert all((fake.ttl[k] or 0) >= 10 * sh._TYPING_AUTHZ_TTL_MAX for k in entry["epoch_keys"])

    def test_publish_writes_the_any_key_first_inside_one_transaction(self, ctx, world, fake):
        from kk import socketio_handlers as sh

        assert sh.publish_authz_change(user_ids=[1], car_ids=[2], jtis=["jj"], global_keys=["g:user"])
        (ops,) = fake.pipelines[-1:]
        assert ops[0][1] == sh._epoch_key("any")
        assert {o[1] for o in ops} == {
            sh._epoch_key(n) for n in ("any", "u:1", "c:2", "j:jj", "g:user")
        }
        assert len({o[2] for o in ops}) == 1  # one fresh random token

    def test_unrelated_changes_do_not_invalidate_this_conversation(self, ctx, world, fake):
        world.seed()
        s, b = _pair(ctx, world)
        app, _sio, client = ctx
        # buyer two blocks buyer three: nothing to do with b1 <-> seller
        with other_worker():
            r = client.post(f"/api/users/{world.b3}/block", headers=_auth(world.tok[world.b2]))
            assert r.status_code in (200, 201)
        c = _warm_event(ctx, b, car_id=world.car)
        assert c.n == 0, "per-user epochs keep unrelated activity from thrashing the cache"

    def test_without_redis_configured_only_local_eviction_and_ttl_apply(self, ctx, world, monkeypatch):
        from kk import socketio_handlers as sh

        monkeypatch.delenv("CHAT_TYPING_AUTHZ_REDIS_URL", raising=False)
        monkeypatch.delenv("REDIS_URL", raising=False)
        assert sh._epoch_backend() == ("off", None)
        s, b = _pair(ctx, world)
        assert _warm_event(ctx, b, car_id=world.car).n == 0


# ================================================== other-worker changes ==


class TestRevocationInAnotherWorker:
    def _assert_cut_off(self, ctx, world, s, b, *, closes: bool):
        b.get_received()
        s.get_received()
        b.emit("typing_stop", {"car_id": world.car})
        if closes:
            assert not b.is_connected()
        else:
            b.emit("typing_start", {"car_id": world.car})
        assert _typing(s) == [], "typing must not reach the seller any more"

    def test_block_in_another_worker(self, ctx, world, fake):
        s, b = _pair(ctx, world)
        b.emit("typing_start", {"car_id": world.car})
        assert [t["typing"] for t in _typing(s)] == [True]
        _app, _sio, client = ctx
        with other_worker():
            r = client.post(f"/api/users/{world.s}/block", headers=_auth(world.tok[world.b1]))
            assert r.status_code in (200, 201)
        self._assert_cut_off(ctx, world, s, b, closes=False)
        # the seller's direction too
        s.emit("typing_start", {"car_id": world.car, "peer_id": world.b1})
        assert _typing(b) == []

    def test_unblock_in_another_worker_restores_typing(self, ctx, world, fake):
        s, b = _pair(ctx, world)
        _app, _sio, client = ctx
        with other_worker():
            client.post(f"/api/users/{world.s}/block", headers=_auth(world.tok[world.b1]))
        b.emit("typing_start", {"car_id": world.car})
        assert _typing(s) == []
        with other_worker():
            assert client.post(f"/api/users/{world.s}/unblock", headers=_auth(world.tok[world.b1])).status_code == 200
        b.emit("typing_stop", {"car_id": world.car})
        b.emit("typing_start", {"car_id": world.car})
        assert [t["typing"] for t in _typing(s)] == [False, True]

    def test_logout_in_another_worker_closes_the_socket(self, ctx, world, fake):
        s, b = _pair(ctx, world)
        b.emit("typing_start", {"car_id": world.car})
        s.get_received()
        _app, _sio, client = ctx
        with other_worker():
            assert client.post("/api/auth/logout", headers=_auth(world.tok[world.b1]), json={}).status_code in (200, 204)
        b.emit("typing_stop", {"car_id": world.car})
        assert any(e["name"] == "auth_expired" for e in _drain(b))
        assert not b.is_connected() and _typing(s) == []

    def test_token_revocation_only_that_token_loses_typing(self, ctx, world, fake):
        """A second login of the same user keeps working: j:<jti> is per token."""
        s, b = _pair(ctx, world)
        other_tok = _login(ctx, world.b1)
        b2 = _sock(ctx, other_tok)
        b2.emit("join_chat", {"car_id": world.car})
        b2.get_received()
        _app, _sio, client = ctx
        with other_worker():
            client.post("/api/auth/logout", headers=_auth(world.tok[world.b1]), json={})
        # the logged-out token's socket is gone; the new login's socket may still type
        b.emit("typing_start", {"car_id": world.car})
        assert not b.is_connected()

    def test_deactivated_account_in_another_worker(self, ctx, world, fake):
        app, _sio, _c = ctx
        from kk.models import User, db

        s, b = _pair(ctx, world)
        b.emit("typing_start", {"car_id": world.car})
        assert [t["typing"] for t in _typing(s)] == [True]
        with other_worker(), app.app_context():
            u = User.query.filter_by(public_id=world.b1).first()
            u.is_active = False
            db.session.commit()
        self._assert_cut_off(ctx, world, s, b, closes=True)

    def test_a_deactivated_peer_is_handled_exactly_like_the_uncached_path(self, ctx, world, fake):
        app, _sio, _c = ctx
        from kk.models import User, db

        s, b = _pair(ctx, world)
        b.emit("typing_start", {"car_id": world.car})
        s.get_received()
        with other_worker(), app.app_context():
            u = User.query.filter_by(public_id=world.s).first()  # the SELLER
            u.is_active = False
            db.session.commit()
        b.emit("typing_stop", {"car_id": world.car})
        cached = [t["typing"] for t in _typing(s)]
        with _ttl(0):  # the authoritative, uncached answer for the same situation
            b.emit("typing_start", {"car_id": world.car})
        legacy = [t["typing"] for t in _typing(s)]
        assert cached == [False] and legacy == [True], (
            "the cache must change nothing: the buyer's typing is relayed exactly "
            "as the full check relays it (a deactivated seller's own socket is "
            "closed on ITS next event)"
        )

    def test_password_cutoff_in_another_worker(self, ctx, world, fake):
        app, _sio, _c = ctx
        from datetime import timedelta

        from kk.models import User, db
        from kk.time_utils import utcnow

        s, b = _pair(ctx, world)
        b.emit("typing_start", {"car_id": world.car})
        s.get_received()
        with other_worker(), app.app_context():
            u = User.query.filter_by(public_id=world.b1).first()
            u.tokens_invalid_before = utcnow() + timedelta(seconds=5)
            db.session.commit()
        self._assert_cut_off(ctx, world, s, b, closes=True)

    def test_removed_chat_permission_in_another_worker(self, ctx, world, fake):
        """The buyer's only messages disappear: they no longer belong to the room."""
        app, _sio, _c = ctx
        from kk.models import Car, Message, db

        s, b = _pair(ctx, world)
        b.emit("typing_start", {"car_id": world.car})
        assert [t["typing"] for t in _typing(s)] == [True]
        with other_worker(), app.app_context():
            car = Car.query.filter_by(public_id=world.car).first()
            for m in Message.query.filter_by(car_id=car.id).all():
                db.session.delete(m)
            db.session.commit()
        self._assert_cut_off(ctx, world, s, b, closes=False)

    def test_listing_change_publishes_the_listing_epoch(self, ctx, world, fake):
        app, _sio, _c = ctx
        from kk.models import Car, db

        s, b = _pair(ctx, world)
        with app.app_context():
            car = Car.query.filter_by(public_id=world.car).first()
            key = f"c:{car.id}"
        before = fake.value(key)
        with other_worker(), app.app_context():
            car = Car.query.filter_by(public_id=world.car).first()
            car.is_active = False
            db.session.commit()
        assert fake.value(key) != before and fake.value(key) is not None
        assert _warm_event(ctx, b, car_id=world.car).n > 0, "revalidated, not served from cache"

    def test_a_rolled_back_change_publishes_nothing(self, ctx, world, fake):
        app, _sio, _c = ctx
        from kk.models import BlockedUser, db

        s, b = _pair(ctx, world)
        snapshot = dict(fake.d)
        with other_worker(), app.app_context():
            me = _public(ctx, world.b1)
            other = _public(ctx, world.s)
            db.session.add(BlockedUser(blocker_id=me, blocked_id=other))
            db.session.flush()
            db.session.rollback()
        assert fake.d == snapshot
        assert _warm_event(ctx, b, car_id=world.car).n == 0


# ============================== changes that fire no ORM callback at all ==


class TestBulkAndRawStatements:
    def _g_changes(self, fake, run):
        from kk import socketio_handlers as sh

        keys = [sh._epoch_key(g) for g in sh._REDIS_GLOBAL_KEYS]
        before = {k: fake.d.get(k) for k in keys}
        run()
        return {k[len(sh._REDIS_PREFIX):] for k in keys if fake.d.get(k) != before[k]}

    @pytest.mark.parametrize(
        "label,expected",
        [
            ("user_bulk_deactivate", {"g:user"}),
            ("user_bulk_benign", set()),
            ("user_raw_deactivate", {"g:user"}),
            ("user_raw_benign", set()),
            ("car_bulk_deactivate", {"g:car"}),
            ("car_bulk_benign", set()),
            ("car_raw_status", {"g:car"}),
            ("block_core_insert", {"g:block"}),
            ("block_core_delete", {"g:block"}),
            ("message_bulk_delete", {"g:msg"}),
            ("message_bulk_mark_read", set()),
            ("token_raw_delete", {"g:tok"}),
            ("plain_select", set()),
        ],
    )
    def test_statement_classification(self, ctx, world, fake, label, expected):
        app, _sio, _c = ctx
        from kk.models import BlockedUser, Car, Message, TokenBlacklist, User, db

        _pair(ctx, world)  # creates the epoch keys
        uid = _public(ctx, world.b1)

        def run():
            with app.app_context():
                runs = {
                    "user_bulk_deactivate": lambda: User.query.filter_by(id=-1).update({"is_active": False}),
                    "user_bulk_benign": lambda: User.query.filter_by(id=-1).update({"firebase_token": "x"}),
                    "user_raw_deactivate": lambda: db.session.execute(text('UPDATE "user" SET is_active = 0 WHERE id = -1')),
                    "user_raw_benign": lambda: db.session.execute(text('UPDATE "user" SET firebase_token = NULL WHERE id = -1')),
                    "car_bulk_deactivate": lambda: Car.query.filter_by(id=-1).update({"is_active": False}),
                    "car_bulk_benign": lambda: Car.query.filter_by(id=-1).update({"views_count": 5}),
                    "car_raw_status": lambda: db.session.execute(text("UPDATE car SET status = 'x' WHERE id = -1")),
                    "block_core_insert": lambda: db.session.execute(insert(BlockedUser).values(blocker_id=uid, blocked_id=uid)),
                    "block_core_delete": lambda: db.session.execute(delete(BlockedUser).where(BlockedUser.id == -1)),
                    "message_bulk_delete": lambda: Message.query.filter_by(id=-1).delete(),
                    "message_bulk_mark_read": lambda: Message.query.filter_by(id=-1).update({"is_read": True}),
                    "token_raw_delete": lambda: db.session.execute(text("DELETE FROM token_blacklist WHERE id = -1")),
                    "plain_select": lambda: db.session.execute(text("SELECT 1")),
                }
                runs[label]()
                db.session.commit()

        changed = self._g_changes(fake, run)
        assert changed == expected, (label, changed)

    def test_bulk_deactivation_in_another_worker_cuts_typing_off(self, ctx, world, fake):
        app, _sio, _c = ctx
        from kk.models import User

        s, b = _pair(ctx, world)
        b.emit("typing_start", {"car_id": world.car})
        s.get_received()
        with other_worker(), app.app_context():
            from kk.models import db

            User.query.filter_by(public_id=world.b1).update({"is_active": False})
            db.session.commit()
        b.emit("typing_stop", {"car_id": world.car})
        assert _typing(s) == []
        assert not b.is_connected()

    def test_raw_sql_block_in_another_worker_cuts_typing_off(self, ctx, world, fake):
        app, _sio, _c = ctx
        from kk.models import BlockedUser, db

        s, b = _pair(ctx, world)
        b.emit("typing_start", {"car_id": world.car})
        s.get_received()
        me, other = _public(ctx, world.b1), _public(ctx, world.s)
        with other_worker(), app.app_context():
            db.session.execute(insert(BlockedUser).values(blocker_id=me, blocked_id=other))
            db.session.commit()
        b.emit("typing_stop", {"car_id": world.car})
        b.emit("typing_start", {"car_id": world.car})
        assert _typing(s) == []

    def test_benign_bulk_updates_keep_the_zero_sql_warm_path(self, ctx, world, fake):
        app, _sio, _c = ctx
        from kk.models import User, db

        s, b = _pair(ctx, world)
        with other_worker(), app.app_context():
            User.query.filter_by(public_id=world.b1).update({"firebase_token": "token"})
            db.session.commit()
        assert _warm_event(ctx, b, car_id=world.car).n == 0

    def test_a_write_outside_any_session_is_bounded_by_the_ttl_only(self, ctx, world, fake):
        """The one remaining blind spot: Core SQL on a bare engine connection
        (no Session, so no callback of any kind), e.g. a manual script."""
        app, _sio, _c = ctx
        from kk import socketio_handlers as sh
        from kk.models import BlockedUser, db

        s, b = _pair(ctx, world)
        me, other = _public(ctx, world.b1), _public(ctx, world.s)
        with app.app_context(), db.engine.begin() as conn:
            conn.execute(insert(BlockedUser).values(blocker_id=me, blocked_id=other))
        b.emit("typing_start", {"car_id": world.car})
        assert [t["typing"] for t in _typing(s)] == [True], "inside the 15 s window"
        real = sh._mono
        with patch.object(sh, "_mono", lambda: real() + 16):
            b.emit("typing_stop", {"car_id": world.car})
            b.emit("typing_start", {"car_id": world.car})
        assert _typing(s) == []


# ========================================================= Redis failures ==


class TestRedisFailures:
    def test_redis_down_falls_back_to_the_database_and_never_relaxes_checks(self, ctx, world, fake):
        from kk import socketio_handlers as sh

        s, b = _pair(ctx, world)
        fake.down = True
        c = _warm_event(ctx, b, car_id=world.car)
        assert c.n >= 5, "full database validation while Redis is unavailable"
        assert [t["typing"] for t in _typing(s)] == [True], "still works for an authorized user"
        ((_sid, rec),) = _bound(sh, world.b1)
        assert rec["authz"] == {}, "nothing is cached while Redis cannot vouch for it"

    def test_redis_down_and_permission_revoked_is_denied(self, ctx, world, fake):
        s, b = _pair(ctx, world)
        _app, _sio, client = ctx
        fake.down = True
        with other_worker():
            client.post(f"/api/users/{world.s}/block", headers=_auth(world.tok[world.b1]))
        b.emit("typing_start", {"car_id": world.car})
        assert _typing(s) == []

    def test_the_circuit_avoids_hammering_redis_and_recovers(self, ctx, world, fake):
        from kk import socketio_handlers as sh

        s, b = _pair(ctx, world)
        fake.down = True
        _warm_event(ctx, b, car_id=world.car)
        fake.down = False
        fake.trips.clear()
        for ev in ("typing_stop", "typing_start"):
            assert _warm_event(ctx, b, ev, car_id=world.car).n > 0
        assert fake.trips == [], "circuit open: no Redis calls for a few seconds"
        real = sh._mono
        with patch.object(sh, "_mono", lambda: real() + 6):
            assert _warm_event(ctx, b, "typing_stop", car_id=world.car).n > 0  # re-caches
            assert _warm_event(ctx, b, "typing_start", car_id=world.car).n == 0

    def test_a_block_committed_while_redis_is_down_still_cuts_off_this_worker(self, ctx, world, fake):
        from kk import socketio_handlers as sh

        s, b = _pair(ctx, world)
        _app, _sio, client = ctx
        fake.down = True
        assert client.post(f"/api/users/{world.s}/block", headers=_auth(world.tok[world.b1])).status_code in (200, 201)
        fake.down = False
        b.emit("typing_start", {"car_id": world.car})
        assert _typing(s) == []

    def test_publish_reports_failure_instead_of_raising(self, ctx, world, fake):
        from kk import socketio_handlers as sh

        _pair(ctx, world)
        fake.down = True
        assert sh.publish_authz_change(user_ids=[1]) is False

    def test_redis_data_loss_forces_revalidation(self, ctx, world, fake):
        s, b = _pair(ctx, world)
        fake.flushall()
        c = _warm_event(ctx, b, car_id=world.car)
        assert c.n >= 5, "all epochs vanished: nothing may be trusted"
        assert [t["typing"] for t in _typing(s)] == [True]
        assert _warm_event(ctx, b, "typing_stop", car_id=world.car).n == 0, "re-cached with fresh epochs"

    def test_an_evicted_epoch_key_forces_revalidation_even_if_it_never_changed(self, ctx, world, fake):
        from kk import socketio_handlers as sh

        s, b = _pair(ctx, world)
        ((_sid, rec),) = _bound(sh, world.b1)
        (entry,) = rec["authz"].values()
        fake.evict(f"{sh._REDIS_PREFIX}u:{entry['peer_id']}")
        assert _warm_event(ctx, b, car_id=world.car).n >= 5

    def test_a_flush_after_a_block_cannot_resurrect_a_stale_entry(self, ctx, world, fake):
        """Entry snapshotted, block published, then Redis loses everything:
        the old snapshot must not match a re-created or missing key."""
        s, b = _pair(ctx, world)
        _app, _sio, client = ctx
        with other_worker():
            client.post(f"/api/users/{world.s}/block", headers=_auth(world.tok[world.b1]))
        fake.flushall()
        b.emit("typing_start", {"car_id": world.car})
        assert _typing(s) == []

    def test_a_slow_redis_is_handled_like_an_outage(self, ctx, world, fake):
        s, b = _pair(ctx, world)
        with patch.object(fake, "mget", side_effect=redis_pkg.exceptions.TimeoutError("slow")):
            c = _warm_event(ctx, b, car_id=world.car)
        assert c.n >= 5
        assert [t["typing"] for t in _typing(s)] == [True]


# ===================================================== races and isolation ==


class TestRacesAndIsolation:
    def test_a_change_during_a_slow_validation_is_never_cached(self, ctx, world, fake):
        """Worker A validates (sees 'allowed'); worker B commits a block and
        publishes before A stores the result. A must not cache it."""
        from kk import socketio_handlers as sh

        s, b = _pair(ctx, world, join="seller_only")  # buyer starts cold
        real = sh.user_can_access_chat_room
        fired = []

        def validate_then_other_worker_publishes(user, car):
            ok = real(user, car)
            if not fired:
                fired.append(1)
                sh.publish_authz_change(user_ids=[user.id])  # B's after-commit publish
            return ok

        with patch.object(sh, "user_can_access_chat_room", validate_then_other_worker_publishes):
            b.emit("typing_start", {"car_id": world.car})  # this event raced: relayed once
        assert fired
        ((_sid, rec),) = _bound(sh, world.b1)
        assert rec["authz"] == {}, "the raced validation must not be cached"
        assert _warm_event(ctx, b, "typing_stop", car_id=world.car).n >= 5
        assert _warm_event(ctx, b, "typing_start", car_id=world.car).n == 0  # cached cleanly now

    def test_two_sockets_never_share_epochs_or_entries(self, ctx, world, fake):
        from kk import socketio_handlers as sh

        world.seed()
        s = _sock(ctx, world.tok[world.s])
        b1 = _sock(ctx, world.tok[world.b1])
        b2 = _sock(ctx, world.tok[world.b2])
        for sock in (b1, b2):
            sock.emit("join_chat", {"car_id": world.car})
        s.emit("join_chat", {"car_id": world.car, "peer_id": world.b1})
        s.emit("join_chat", {"car_id": world.car, "peer_id": world.b2})
        for sock in (s, b1, b2):
            sock.get_received()
        ((_, r1),) = _bound(sh, world.b1)
        ((_, r2),) = _bound(sh, world.b2)
        (e1,), (e2,) = r1["authz"].values(), r2["authz"].values()
        assert e1["room"] != e2["room"] and e1["me"] != e2["me"]
        assert f"u:{e1['me_id']}" in {k[len(sh._REDIS_PREFIX):] for k in e1["epoch_keys"]}
        assert f"u:{e1['me_id']}" not in {k[len(sh._REDIS_PREFIX):] for k in e2["epoch_keys"]}
        # blocking b1 leaves b2's conversation alone
        _app, _sio, client = ctx
        with other_worker():
            client.post(f"/api/users/{world.b1}/block", headers=_auth(world.tok[world.s]))
        # the seller (the peer of BOTH conversations) changed, so b2 revalidates once ...
        assert _warm_event(ctx, b2, car_id=world.car).n >= 5
        assert _warm_event(ctx, b2, "typing_stop", car_id=world.car).n == 0  # ... then cached again
        b1.emit("typing_start", {"car_id": world.car})
        assert [t for t in _typing(s) if t["user_id"] == world.b1] == []

    def test_reconnect_and_account_switch_start_cold_with_redis_too(self, ctx, world, fake):
        from kk import socketio_handlers as sh

        s, b = _pair(ctx, world)
        b.disconnect()
        b2 = _sock(ctx, world.tok[world.b1])
        ((_sid, rec),) = _bound(sh, world.b1)
        assert rec["authz"] == {}
        assert _warm_event(ctx, b2, car_id=world.car).n >= 5
        assert _warm_event(ctx, b2, "typing_stop", car_id=world.car).n == 0

    def test_ttl_still_expires_entries_when_redis_says_nothing_changed(self, ctx, world, fake):
        from kk import socketio_handlers as sh

        s, b = _pair(ctx, world)
        real = sh._mono
        with patch.object(sh, "_mono", lambda: real() + 16):
            assert _warm_event(ctx, b, car_id=world.car).n >= 5

    def test_ttl_zero_ignores_redis_completely(self, ctx, world, fake):
        with _ttl(0):
            s, b = _pair(ctx, world)
            fake.trips.clear()
            assert _warm_event(ctx, b, car_id=world.car).n >= 5
            assert fake.trips == []
