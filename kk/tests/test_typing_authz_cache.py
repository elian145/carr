"""Typing events: authorize a conversation once per socket, not on every event.

Background: with 20 sockets on a NullPool staging service every ``typing_start``
/ ``typing_stop`` re-ran the whole authorization chain on a freshly opened DB
connection and pushed the HTTP API tail latency up ~5x. This module pins

* the database work per typing event BEFORE (``CHAT_TYPING_AUTHZ_TTL_SECONDS=0``
  restores the old behaviour) and AFTER the optimization, and
* that the shortcut can never widen who sees a typing indicator: chat
  isolation, blocks, logout / revoked tokens, token expiry, deactivated
  accounts, reconnects, account switching, stale cache entries and spam.

Everything runs against the real Flask app + SQLite + the Flask-SocketIO test
client with synthetic accounts only.
"""

# ruff: noqa: F811, F401
from __future__ import annotations

import time
from contextlib import contextmanager
from unittest.mock import patch

# Re-use the F-05/F-25/F-36 harness (same synthetic world, same helpers).
from test_chat_f05_f25_f36_isolation import (  # noqa: F401  (fixtures)
    World,
    _auth,
    _car,
    _connect_raw,
    _drain,
    _events,
    _login,
    _send,
    _sock,
    _user,
    ctx,
    world,
)


# --------------------------------------------------------------- measuring ---


class DbCounter:
    """Counts SQL statements and connection checkouts made while active.

    Under the production ``NullPool`` every checkout is a brand-new database
    connection, so ``checkouts`` is the number of new connections.
    """

    def __init__(self, engine, checkout_delay: float = 0.0):
        self.engine = engine
        self.statements: list[str] = []
        self.checkouts = 0
        self._delay = checkout_delay

    def _stmt(self, conn, cursor, statement, params, context, executemany):
        self.statements.append(statement)

    def _checkout(self, *_a):
        self.checkouts += 1
        if self._delay:
            time.sleep(self._delay)  # stand-in for a new-connection handshake

    def __enter__(self):
        from sqlalchemy import event

        event.listen(self.engine, "before_cursor_execute", self._stmt)
        event.listen(self.engine, "checkout", self._checkout)
        return self

    def __exit__(self, *exc):
        from sqlalchemy import event

        event.remove(self.engine, "before_cursor_execute", self._stmt)
        event.remove(self.engine, "checkout", self._checkout)

    @property
    def n(self) -> int:
        return len(self.statements)


def _per_event_session_teardown(app):
    """Production tears the scoped session down after every socket event
    (request-context teardown). The test client does not; do it by hand so
    each event is measured like a real one (one connection per event)."""
    from kk.models import db

    with app.app_context():
        db.session.remove()


def _typing(sock):
    return [e["args"][0] for e in _events(sock, "typing")]


def _emit_counted(ctx, sock, event, payload, *, delay=0.0):
    app, _sio, _c = ctx
    from kk.models import db

    _per_event_session_teardown(app)
    with app.app_context():
        engine = db.engine
    with DbCounter(engine, checkout_delay=delay) as c:
        sock.emit(event, payload)
    _per_event_session_teardown(app)
    return c


def _pair(ctx, world, *, join=True):
    """seller + b1 sockets, b1 <-> seller thread open (joined by default)."""
    assert world.send(world.b1, "hello", to=world.s).status_code == 201
    s, b = _sock(ctx, world.tok[world.s]), _sock(ctx, world.tok[world.b1])
    if join is True:
        b.emit("join_chat", {"car_id": world.car})
    if join:  # True, or "seller_only": the seller listens, the buyer stays cold
        s.emit("join_chat", {"car_id": world.car, "peer_id": world.b1})
    s.get_received()
    b.get_received()
    return s, b


@contextmanager
def _ttl(value):
    with patch.dict("os.environ", {"CHAT_TYPING_AUTHZ_TTL_SECONDS": str(value)}):
        yield


def _bound(sh, public_id):
    return [(k, v) for k, v in sh._SOCKET_AUTH.items() if v["user_public_id"] == public_id]


# ============================================== before / after: DB work ==


class TestDatabaseWorkPerTypingEvent:
    def test_before_and_after_counts(self, ctx, world, capsys):
        """Legacy (TTL=0) vs optimized, same events, same data."""
        results = {}
        for label, ttl in (("before (legacy)", 0), ("after  (cached)", 15)):
            with _ttl(ttl):
                s, b = _pair(ctx, world)
                rows = []
                for ev in ("typing_start", "typing_stop", "typing_start", "typing_stop"):
                    c = _emit_counted(ctx, b, ev, {"car_id": world.car})
                    rows.append((ev, c.n, c.checkouts))
                relayed = [t["typing"] for t in _typing(s)]
                results[label] = (rows, relayed)
                b.disconnect()
                s.disconnect()
                # a fresh thread for the next round is not needed: same data

        legacy_rows, legacy_relayed = results["before (legacy)"]
        cached_rows, cached_relayed = results["after  (cached)"]
        with capsys.disabled():
            print("\n--- DB work per typing event (buyer -> seller) ---")
            for label, (rows, relayed) in results.items():
                print(f"{label}: relayed={relayed}")
                for ev, n, co in rows:
                    print(f"    {ev:13s} sql_statements={n:2d}  connection_checkouts={co}")

        # BEFORE: every event pays for the whole chain on its own connection.
        assert all(n >= 5 and co >= 1 for _ev, n, co in legacy_rows), legacy_rows
        assert legacy_relayed == [True, False, True, False]
        # AFTER: the conversation was authorized at join_chat -> zero DB work.
        assert all(n == 0 and co == 0 for _ev, n, co in cached_rows), cached_rows
        assert cached_relayed == [True, False, True, False]

    def test_cold_first_event_pays_once_then_everything_is_free(self, ctx, world):
        with _ttl(15):
            s, b = _pair(ctx, world, join="seller_only")  # buyer never joined: cold cache
            first = _emit_counted(ctx, b, "typing_start", {"car_id": world.car})
            assert first.n >= 5 and first.checkouts >= 1
            for ev in ("typing_stop", "typing_start", "typing_stop"):
                c = _emit_counted(ctx, b, ev, {"car_id": world.car})
                assert (c.n, c.checkouts) == (0, 0), ev
            assert [t["typing"] for t in _typing(s)] == [True, False, True, False]

    def test_simulated_new_connection_latency(self, ctx, world, capsys):
        """A 50 ms per-connection handshake (staging measured 94-290 ms)."""
        delay = 0.05
        timings = {}
        for label, ttl in (("before", 0), ("after", 15)):
            with _ttl(ttl):
                s, b = _pair(ctx, world)
                t0 = time.perf_counter()
                for _ in range(5):
                    _emit_counted(ctx, b, "typing_start", {"car_id": world.car}, delay=delay)
                    _emit_counted(ctx, b, "typing_stop", {"car_id": world.car}, delay=delay)
                timings[label] = time.perf_counter() - t0
                b.disconnect()
                s.disconnect()
        with capsys.disabled():
            print(
                f"\n--- 10 typing events, {int(delay * 1000)} ms per new connection: "
                f"before={timings['before']:.2f}s after={timings['after']:.3f}s"
            )
        assert timings["before"] >= 10 * delay  # one connection per event
        assert timings["after"] < timings["before"] / 5


# ============================================================ isolation ==


class TestIsolationIsPreserved:
    def test_typing_still_reaches_only_the_other_participant(self, ctx, world):
        world.seed()
        sk = {u: _sock(ctx, world.tok[u]) for u in (world.s, world.b1, world.b2, world.b3, world.x)}
        for u in (world.b1, world.b2, world.b3, world.x):
            sk[u].emit("join_chat", {"car_id": world.car})
        for b in (world.b1, world.b2, world.b3):
            sk[world.s].emit("join_chat", {"car_id": world.car, "peer_id": b})
        for s in sk.values():
            s.get_received()
        for _ in range(2):  # second round = cached fast path
            sk[world.b1].emit("typing_start", {"car_id": world.car})
            sk[world.b1].emit("typing_stop", {"car_id": world.car})
            got = {u: _typing(s) for u, s in sk.items()}
            assert [t["typing"] for t in got[world.s]] == [True, False]
            assert all(got[u] == [] for u in (world.b1, world.b2, world.b3, world.x))
        sk[world.s].emit("typing_start", {"car_id": world.car, "peer_id": world.b2})
        got = {u: _typing(s) for u, s in sk.items()}
        assert [t["user_id"] for t in got[world.b2]] == [world.s]
        assert all(got[u] == [] for u in (world.s, world.b1, world.b3, world.x))

    def test_a_cached_conversation_does_not_authorize_another_peer(self, ctx, world):
        world.seed()
        b1 = _sock(ctx, world.tok[world.b1])
        b2 = _sock(ctx, world.tok[world.b2])
        b1.emit("join_chat", {"car_id": world.car})
        b1.emit("typing_start", {"car_id": world.car})  # warms (car, "")
        b1.get_received()
        b1.emit("typing_stop", {"car_id": world.car})
        b1.get_received()
        # same car, but the client now NAMES another buyer: not the cached key
        b1.emit("typing_start", {"car_id": world.car, "peer_id": world.b2})
        b2.emit("join_chat", {"car_id": world.car})
        assert _typing(b2) == []

    def test_one_sockets_cache_is_never_used_by_another_socket(self, ctx, world):
        world.seed()
        s1 = _sock(ctx, world.tok[world.b1])
        s1.emit("join_chat", {"car_id": world.car})
        s1.emit("typing_start", {"car_id": world.car})  # warm for b1
        x = _sock(ctx, world.tok[world.x])  # stranger, same payload
        sock_seller = _sock(ctx, world.tok[world.s])
        sock_seller.emit("join_chat", {"car_id": world.car, "peer_id": world.b1})
        sock_seller.get_received()
        x.emit("typing_start", {"car_id": world.car})
        assert _typing(sock_seller) == []

    def test_the_cache_only_holds_server_resolved_values_of_the_bound_user(self, ctx, world):
        from kk import socketio_handlers as sh

        s, b = _pair(ctx, world)
        b.emit("typing_start", {"car_id": world.car, "user_id": world.s, "room": "chat:evil"})
        ((sid, rec),) = _bound(sh, world.b1)
        assert rec["authz"], "join/typing should have cached the conversation"
        for entry in rec["authz"].values():
            assert entry["me"] == world.b1 == rec["user_public_id"]
            assert entry["peer_public_id"] == world.s
            assert entry["room"].startswith(f"chat:{world.car}:")
            assert "evil" not in entry["room"]
        # the spoofed identity was ignored: the seller sees b1, not itself
        assert [t["user_id"] for t in _typing(s)] == [world.b1]

    def test_a_seller_without_a_named_buyer_is_never_cached(self, ctx, world):
        from kk import socketio_handlers as sh

        # exactly one buyer: unambiguous, so it works ...
        assert world.send(world.b1, "hi", to=world.s).status_code == 201
        s = _sock(ctx, world.tok[world.s])
        b1 = _sock(ctx, world.tok[world.b1])
        b1.emit("join_chat", {"car_id": world.car})
        b1.get_received()
        s.emit("join_chat", {"car_id": world.car, "peer_id": world.b1})
        s.get_received()
        s.emit("typing_start", {"car_id": world.car})
        assert [t["user_id"] for t in _typing(b1)] == [world.s]
        ((_sid, rec),) = _bound(sh, world.s)
        assert ("%s" % world.car, "") not in rec["authz"]
        # ... then a second buyer appears: it must become ambiguous at once.
        assert world.send(world.b2, "me too", to=world.s).status_code == 201
        b2 = _sock(ctx, world.tok[world.b2])
        b2.emit("join_chat", {"car_id": world.car})
        b2.get_received()
        s.emit("typing_stop", {"car_id": world.car})
        assert _typing(b1) == [] and _typing(b2) == []


# ==================================================== stale permissions ==


class TestStalePermissions:
    def test_a_block_takes_effect_immediately(self, ctx, world):
        s, b = _pair(ctx, world)
        b.emit("typing_start", {"car_id": world.car})
        assert [t["typing"] for t in _typing(s)] == [True]  # warm and relayed
        _app, _sio, client = ctx
        assert client.post(f"/api/users/{world.s}/block", headers=_auth(world.tok[world.b1])).status_code in (200, 201)
        b.get_received()
        b.emit("typing_stop", {"car_id": world.car})
        b.emit("typing_start", {"car_id": world.car})
        assert _typing(s) == []
        s.emit("typing_start", {"car_id": world.car, "peer_id": world.b1})
        assert _typing(b) == []
        # unblocking restores it (and re-authorizes from scratch)
        assert client.post(f"/api/users/{world.s}/unblock", headers=_auth(world.tok[world.b1])).status_code == 200
        b.emit("typing_start", {"car_id": world.car})
        assert [t["typing"] for t in _typing(s)] == [True]

    def test_logout_closes_the_socket_even_with_a_warm_cache(self, ctx, world):
        s, b = _pair(ctx, world)
        b.emit("typing_start", {"car_id": world.car})
        b.get_received()
        s.get_received()
        _app, _sio, client = ctx
        assert client.post("/api/auth/logout", headers=_auth(world.tok[world.b1]), json={}).status_code in (200, 204)
        b.emit("typing_stop", {"car_id": world.car})
        assert any(e["name"] == "auth_expired" for e in _drain(b))
        assert not b.is_connected()
        assert _typing(s) == []

    def test_a_deactivated_account_is_cut_off(self, ctx, world):
        app, _sio, _c = ctx
        from kk.models import User, db

        s, b = _pair(ctx, world)
        b.emit("typing_start", {"car_id": world.car})
        assert [t["typing"] for t in _typing(s)] == [True]
        with app.app_context():
            u = User.query.filter_by(public_id=world.b1).first()
            u.is_active = False
            db.session.commit()
        b.emit("typing_stop", {"car_id": world.car})
        assert _typing(s) == []
        assert not b.is_connected()

    def test_a_password_change_cutoff_closes_old_sockets(self, ctx, world):
        app, _sio, _c = ctx
        from datetime import timedelta

        from kk.models import User, db
        from kk.time_utils import utcnow

        s, b = _pair(ctx, world)
        b.emit("typing_start", {"car_id": world.car})
        s.get_received()
        with app.app_context():
            u = User.query.filter_by(public_id=world.b1).first()
            u.tokens_invalid_before = utcnow() + timedelta(seconds=5)
            db.session.commit()
        b.emit("typing_stop", {"car_id": world.car})
        assert _typing(s) == []
        assert not b.is_connected()

    def test_a_rolled_back_change_evicts_nothing(self, ctx, world):
        app, _sio, _c = ctx
        from kk.models import BlockedUser, User, db

        s, b = _pair(ctx, world)
        b.emit("typing_start", {"car_id": world.car})
        s.get_received()
        with app.app_context():
            me = User.query.filter_by(public_id=world.b1).first()
            other = User.query.filter_by(public_id=world.s).first()
            db.session.add(BlockedUser(blocker_id=me.id, blocked_id=other.id))
            db.session.flush()
            db.session.rollback()
        c = _emit_counted(ctx, b, "typing_stop", {"car_id": world.car})
        assert c.n == 0, "no eviction for a change that never committed"
        assert [t["typing"] for t in _typing(s)] == [False]

    def test_ttl_backstops_changes_that_bypass_the_orm(self, ctx, world):
        """A bulk SQL INSERT fires no ORM event (e.g. another worker). The
        cached entry survives only until the TTL, then is re-authorized."""
        app, _sio, _c = ctx
        from sqlalchemy import insert

        from kk import socketio_handlers as sh
        from kk.models import BlockedUser, User, db

        s, b = _pair(ctx, world)
        with app.app_context():
            me = User.query.filter_by(public_id=world.b1).first().id
            other = User.query.filter_by(public_id=world.s).first().id
            db.session.execute(insert(BlockedUser).values(blocker_id=me, blocked_id=other))
            db.session.commit()
        b.emit("typing_start", {"car_id": world.car})
        assert [t["typing"] for t in _typing(s)] == [True], "within the TTL (documented bound)"
        real = sh._mono
        with patch.object(sh, "_mono", lambda: real() + 16):
            b.emit("typing_stop", {"car_id": world.car})
            b.emit("typing_start", {"car_id": world.car})
        assert _typing(s) == [], "after the TTL the block is enforced"

    def test_ttl_expiry_revalidates_and_still_works_when_allowed(self, ctx, world):
        from kk import socketio_handlers as sh

        s, b = _pair(ctx, world)
        real = sh._mono
        with patch.object(sh, "_mono", lambda: real() + 16):
            c = _emit_counted(ctx, b, "typing_start", {"car_id": world.car})
        assert c.n >= 5, "stale entry -> full validation"
        assert [t["typing"] for t in _typing(s)] == [True]
        c2 = _emit_counted(ctx, b, "typing_stop", {"car_id": world.car})
        assert c2.n == 0

    def test_ttl_is_clamped_and_zero_disables_the_cache(self):
        from kk import socketio_handlers as sh

        with _ttl(0):
            assert sh._typing_authz_ttl() == 0
        with _ttl(-3):
            assert sh._typing_authz_ttl() == 0
        with _ttl("garbage"):
            assert sh._typing_authz_ttl() == sh._TYPING_AUTHZ_TTL_DEFAULT
        with _ttl(10**6):
            assert sh._typing_authz_ttl() == sh._TYPING_AUTHZ_TTL_MAX


# ================================== token expiry, reconnect, switching ==


class TestSocketLifecycle:
    def test_token_expiry_closes_the_socket_even_with_a_warm_cache(self, ctx, world):
        from kk import socketio_handlers as sh

        s, b = _pair(ctx, world)
        b.emit("typing_start", {"car_id": world.car})
        s.get_received()
        real = sh._now
        with patch.object(sh, "_now", lambda: real() + 3600):
            b.emit("typing_stop", {"car_id": world.car})
            got = _drain(b)
        assert any(e["name"] == "auth_expired" for e in got)
        assert not b.is_connected()
        assert _typing(s) == []

    def test_disconnect_drops_the_cache_and_a_reconnect_starts_cold(self, ctx, world):
        from kk import socketio_handlers as sh

        s, b = _pair(ctx, world)
        ((old_sid, rec),) = _bound(sh, world.b1)
        assert rec["authz"]
        b.disconnect()
        assert old_sid not in sh._SOCKET_AUTH
        b2 = _sock(ctx, world.tok[world.b1])  # reconnect
        ((new_sid, rec2),) = _bound(sh, world.b1)
        assert new_sid != old_sid and rec2["authz"] == {}
        c = _emit_counted(ctx, b2, "typing_start", {"car_id": world.car})
        assert c.n >= 5, "a reconnected socket re-authorizes in full"
        assert [t["typing"] for t in _typing(s)] == [True]

    def test_account_switch_gets_its_own_cold_socket(self, ctx, world):
        """Same device, other account: a NEW token -> a NEW socket -> no reuse."""
        from kk import socketio_handlers as sh

        world.seed()
        a = _sock(ctx, world.tok[world.b1])
        a.emit("join_chat", {"car_id": world.car})
        a.emit("typing_start", {"car_id": world.car})
        a.get_received()
        a.disconnect()
        other = _sock(ctx, world.tok[world.b2])
        ((_sid, rec),) = _bound(sh, world.b2)
        assert rec["authz"] == {}
        assert all(r["user_public_id"] != world.b1 for r in sh._SOCKET_AUTH.values())
        seller = _sock(ctx, world.tok[world.s])
        seller.emit("join_chat", {"car_id": world.car, "peer_id": world.b1})
        seller.emit("join_chat", {"car_id": world.car, "peer_id": world.b2})
        seller.get_received()
        other.emit("typing_start", {"car_id": world.car})
        got = _typing(seller)
        assert [(t["user_id"], t["peer_id"]) for t in got] == [(world.b2, world.s)]

    def test_a_binding_for_another_user_is_never_honoured(self, ctx, world):
        from kk import socketio_handlers as sh

        s, b = _pair(ctx, world)
        ((_sid, rec),) = _bound(sh, world.b1)
        # tamper: pretend the cached entry was produced for somebody else
        for e in rec["authz"].values():
            e["me"] = world.s
        c = _emit_counted(ctx, b, "typing_start", {"car_id": world.car})
        assert c.n >= 5, "mismatching owner -> ignored -> full validation"


# ============================================== de-duplication, abuse ==


class TestDuplicatesAndAbuse:
    def test_duplicate_states_are_not_relayed(self, ctx, world):
        from kk import socketio_handlers as sh

        s, b = _pair(ctx, world)
        for _ in range(5):
            b.emit("typing_start", {"car_id": world.car})
        assert [t["typing"] for t in _typing(s)] == [True]
        for _ in range(3):
            b.emit("typing_stop", {"car_id": world.car})
        assert [t["typing"] for t in _typing(s)] == [False]
        b.emit("typing_start", {"car_id": world.car})
        b.emit("typing_stop", {"car_id": world.car})
        assert [t["typing"] for t in _typing(s)] == [True, False]
        # a long typing burst is refreshed after the refresh interval
        b.emit("typing_start", {"car_id": world.car})
        s.get_received()
        real = sh._mono
        with patch.object(sh, "_mono", lambda: real() + 6):
            b.emit("typing_start", {"car_id": world.car})
        assert [t["typing"] for t in _typing(s)] == [True]

    def test_a_stop_with_unknown_state_is_still_relayed(self, ctx, world):
        # new socket after a reconnect: the old socket's "start" is unknown here
        s, b = _pair(ctx, world, join="seller_only")
        b.emit("typing_stop", {"car_id": world.car})
        assert [t["typing"] for t in _typing(s)] == [False]

    def test_flooding_is_rate_limited_before_any_database_work(self, ctx, world):
        from kk import socketio_handlers as sh

        s, b = _pair(ctx, world)
        total = sh._TYPING_RATE_MAX + 20
        app, _sio, _c = ctx
        from kk.models import db

        with app.app_context():
            engine = db.engine
        with DbCounter(engine) as c:
            for i in range(total):
                b.emit("typing_start" if i % 2 == 0 else "typing_stop", {"car_id": world.car})
        relayed = _typing(s)
        assert len(relayed) == sh._TYPING_RATE_MAX
        assert c.n == 0

    def test_unauthorized_spam_costs_at_most_the_rate_limit(self, ctx, world):
        from kk import socketio_handlers as sh

        world.seed()
        s = _sock(ctx, world.tok[world.s])
        s.emit("join_chat", {"car_id": world.car, "peer_id": world.b1})
        s.get_received()
        x = _sock(ctx, world.tok[world.x])  # stranger: every attempt is denied
        app, _sio, _c = ctx
        from kk.models import db

        with app.app_context():
            engine = db.engine
        with DbCounter(engine) as c:
            for _ in range(sh._TYPING_RATE_MAX * 3):
                x.emit("typing_start", {"car_id": world.car, "peer_id": world.b1})
        assert _typing(s) == []
        per_event_cost = 8  # generous upper bound of the full chain
        assert c.n <= sh._TYPING_RATE_MAX * per_event_cost
        ((_sid, rec),) = _bound(sh, world.x)
        assert rec["authz"] == {}, "denials are never cached"

    def test_the_cache_is_bounded(self, ctx, world):
        from kk import socketio_handlers as sh

        world.seed()
        b = _sock(ctx, world.tok[world.b1])
        cars = [_car(ctx, world.s) for _ in range(sh._TYPING_CACHE_MAX_ENTRIES + 4)]
        for car in cars:
            assert _send(ctx, world.tok[world.b1], car, "hi", receiver=world.s).status_code == 201
        for car in cars:
            b.emit("join_chat", {"car_id": car})
        ((_sid, rec),) = _bound(sh, world.b1)
        assert len(rec["authz"]) <= sh._TYPING_CACHE_MAX_ENTRIES
        assert len(rec["typing_state"]) <= sh._TYPING_STATE_MAX_ENTRIES

    def test_oversized_keys_are_not_cached(self, ctx, world):
        from kk import socketio_handlers as sh

        s, b = _pair(ctx, world)
        b.emit("typing_start", {"car_id": world.car, "peer_id": "p" * 500})
        ((_sid, rec),) = _bound(sh, world.b1)
        assert all(len(k[1]) <= sh._TYPING_KEY_MAX_LEN for k in rec["authz"])


# =========================================== legacy switch equivalence ==


class TestLegacyMode:
    def test_ttl_zero_keeps_the_previous_behaviour(self, ctx, world):
        from kk import socketio_handlers as sh

        with _ttl(0):
            s, b = _pair(ctx, world)
            for _ in range(3):  # no de-duplication in legacy mode
                b.emit("typing_start", {"car_id": world.car})
            assert [t["typing"] for t in _typing(s)] == [True, True, True]
            ((_sid, rec),) = _bound(sh, world.b1)
            assert rec["authz"] == {} and not rec["typing_state"]
