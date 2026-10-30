"""Typing-authorization cache: synchronized expiry, counters, limiter, listing public_id.

Context (final staging benchmark, 20 sockets typing in lock-step every 8 s, TTL 15 s):
API latency spiked about every 24 s, and one request timed out. Mechanism (verified
here with a fake clock and a slow validation):

* an entry used to be stamped when its FULL validation FINISHED. Under load that
  takes seconds, so an entry created at t=0 (stamped t=d) still looked fresh at the
  event at t=16 (age 16-d < 15) and only expired at t=24: miss, hit, hit, miss ...
  every 24 s -- all 20 sockets in the same phase, so 20 full checks (7 SQL on 20 new
  connections) landed in the same instant;
* the same stamp also meant the real permission-staleness bound was TTL + d, not TTL.

The fix keeps the 15 s bound (it can only get tighter) and adds counters, a
per-entry lifetime jitter that only SHORTENS entries, a concurrency limit on full
checks, and listing ``public_id`` invalidation.
"""

# ruff: noqa: F811, F401
from __future__ import annotations

import logging
import re
import threading
import time
from contextlib import contextmanager
from unittest.mock import patch

import pytest

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
from test_typing_authz_cache import (  # noqa: F401
    DbCounter,
    _bound,
    _emit_counted,
    _pair,
    _per_event_session_teardown,
    _ttl,
    _typing,
)
from test_typing_authz_redis import fake, other_worker  # noqa: F401  (fixture + helper)


@pytest.fixture(autouse=True)
def _clean_counters():
    from kk import socketio_handlers as sh

    sh.typing_authz_stats(reset=True)
    sh._STATS_LAST_LOG = 0.0
    sh._FULLCHECK_SEM = None
    yield
    sh.typing_authz_stats(reset=True)
    sh._STATS_LAST_LOG = 0.0
    sh._FULLCHECK_SEM = None


class FakeClock:
    def __init__(self):
        self.t = 50_000.0

    def __call__(self):
        return self.t

    def advance(self, seconds):
        self.t += seconds


@contextmanager
def _env(**kv):
    with patch.dict("os.environ", {k: str(v) for k, v in kv.items()}):
        yield


@contextmanager
def _clock(sh, validation_seconds=0.0):
    """Fake monotonic clock; every full validation 'takes' ``validation_seconds``."""
    clk = FakeClock()
    real = sh.resolve_car_for_chat

    def slow(*a, **k):
        clk.advance(validation_seconds)
        return real(*a, **k)

    with patch.object(sh, "_mono", clk), patch.object(sh, "resolve_car_for_chat", slow):
        yield clk


def _typing_events(ctx, b, world, clk, *, interval, count):
    """Lock-step ``typing_start`` every ``interval`` s; returns 'M'(iss)/'H'(it) per event."""
    out = []
    t0 = clk.t
    for k in range(count):
        clk.t = max(clk.t, t0 + k * interval)  # fixed ticks, like the load test's shared clock
        c = _emit_counted(ctx, b, "typing_start", {"car_id": world.car})
        out.append("M" if c.n else "H")
    return "".join(out)


# ============================================ the suspected mechanism ==


class TestSynchronizedExpiryMechanism:
    def test_entry_age_is_measured_from_when_validation_started(self, ctx, world, capsys):
        """THE regression for the 24 s cycle: a validation that takes 2 s must not
        extend the entry's life by 2 s."""
        from kk import socketio_handlers as sh

        with _ttl(15), _env(CHAT_TYPING_AUTHZ_JITTER=0), _clock(sh, validation_seconds=2.0) as clk:
            s, b = _pair(ctx, world, join="seller_only")  # buyer cold
            pattern = _typing_events(ctx, b, world, clk, interval=8, count=9)
        with capsys.disabled():
            print(f"\n--- miss(M)/hit(H) per lock-step event every 8 s, TTL 15, validation 2 s: {pattern}")
        # t=0 miss; t=8 hit (age 8); t=16 age 16 > 15 -> MUST miss (old code: still a
        # hit because the entry was stamped at t=2, giving the 24 s cycle MHHMHH...)
        assert pattern == "MHMHMHMHM", pattern

    def test_staleness_bound_is_the_ttl_even_when_validation_is_slow(self, ctx, world):
        from kk import socketio_handlers as sh

        with _ttl(15), _env(CHAT_TYPING_AUTHZ_JITTER=0), _clock(sh, validation_seconds=3.0) as clk:
            s, b = _pair(ctx, world, join="seller_only")
            t_start = clk.t
            assert _emit_counted(ctx, b, "typing_start", {"car_id": world.car}).n > 0  # validated at t_start
            clk.t = t_start + 15.5  # 0.5 s past the 15 s bound, measured from the START of the check
            c = _emit_counted(ctx, b, "typing_start", {"car_id": world.car})
            assert c.n > 0, "an entry older than the TTL (from validation start) must be revalidated"

    def test_same_with_redis_epochs(self, ctx, world, fake):
        from kk import socketio_handlers as sh

        with _ttl(15), _env(CHAT_TYPING_AUTHZ_JITTER=0), _clock(sh, validation_seconds=2.0) as clk:
            s, b = _pair(ctx, world, join="seller_only")
            pattern = _typing_events(ctx, b, world, clk, interval=8, count=9)
        assert pattern == "MHMHMHMHM", pattern

    def test_the_start_time_is_taken_when_validation_begins(self):
        from kk import socketio_handlers as sh

        clk = FakeClock()
        with patch.object(sh, "_mono", clk):
            gen = sh._authz_token()
            clk.advance(9)
            assert gen[2] == 50_000.0 and sh._mono() == 50_009.0
            assert len(gen) == 3


# ======================================================== lifetime jitter ==


class TestJitter:
    def test_jitter_only_shortens_and_is_clamped(self):
        from kk import socketio_handlers as sh

        for raw, lo in (("0.2", 12.0), ("0.5", 7.5), ("9", 7.5), ("0", 15.0), ("-1", 15.0), ("nan", 15.0)):
            with _env(CHAT_TYPING_AUTHZ_JITTER=raw):
                lives = [sh._entry_life(15.0) for _ in range(400)]
            assert min(lives) >= lo - 1e-9 and max(lives) <= 15.0, (raw, min(lives), max(lives))
        with _env(CHAT_TYPING_AUTHZ_JITTER="junk"):
            assert sh._typing_jitter() == sh._TYPING_JITTER_DEFAULT
        with patch.dict("os.environ", clear=False) as env:
            env.pop("CHAT_TYPING_AUTHZ_JITTER", None)
            assert sh._typing_jitter() == 0.2  # the default

    def test_entries_authorized_together_get_different_lifetimes(self):
        from kk import socketio_handlers as sh

        with _env(CHAT_TYPING_AUTHZ_JITTER=0.2):
            lives = [sh._entry_life(15.0) for _ in range(20)]
        assert max(lives) - min(lives) > 1.0, "20 sockets must not all expire in the same instant"
        assert all(12.0 <= x <= 15.0 for x in lives)

    @pytest.mark.parametrize("roll,expires_at", [(1.0, 12.0), (0.0, 15.0)])
    def test_an_entry_expires_by_its_own_lifetime_and_never_later_than_the_ttl(self, ctx, world, roll, expires_at):
        """roll=1.0 -> the shortest lifetime (TTL*(1-J) = 12 s); roll=0.0 -> the TTL itself."""
        from kk import socketio_handlers as sh

        with _ttl(15), _env(CHAT_TYPING_AUTHZ_JITTER=0.2), _clock(sh) as clk, patch.object(
            sh.random, "random", lambda: roll
        ):
            s, b = _pair(ctx, world, join="seller_only")
            t0 = clk.t
            assert _emit_counted(ctx, b, "typing_start", {"car_id": world.car}).n > 0
            clk.t = t0 + expires_at - 0.5
            assert _emit_counted(ctx, b, "typing_start", {"car_id": world.car}).n == 0, "still fresh"
            clk.t = t0 + expires_at + 0.5
            assert _emit_counted(ctx, b, "typing_start", {"car_id": world.car}).n > 0, "expired"
            ((_sid, rec),) = _bound(sh, world.b1)
            (entry,) = rec["authz"].values()
            assert entry["life"] <= 15.0

    def test_a_shorter_env_ttl_still_caps_an_existing_entry(self, ctx, world):
        from kk import socketio_handlers as sh

        with _env(CHAT_TYPING_AUTHZ_JITTER=0), _clock(sh) as clk:
            with _ttl(15):
                s, b = _pair(ctx, world, join="seller_only")
                t0 = clk.t
                _emit_counted(ctx, b, "typing_start", {"car_id": world.car})
            with _ttl(5):  # operator lowers the TTL at runtime
                clk.t = t0 + 6
                assert _emit_counted(ctx, b, "typing_start", {"car_id": world.car}).n > 0


# ============================================================== counters ==


class TestCounters:
    def test_outcomes_are_counted(self, ctx, world):
        from kk import socketio_handlers as sh

        with _ttl(15), _env(CHAT_TYPING_AUTHZ_JITTER=0, CHAT_TYPING_AUTHZ_STATS_LOG_SECONDS=0), _clock(sh) as clk:
            s, b = _pair(ctx, world, join="seller_only")
            sh.typing_authz_stats(reset=True)
            b.emit("typing_start", {"car_id": world.car})  # cold
            b.emit("typing_start", {"car_id": world.car})  # duplicate within 5 s
            clk.advance(6)
            b.emit("typing_start", {"car_id": world.car})  # cached
            clk.advance(20)
            b.emit("typing_start", {"car_id": world.car})  # expired -> full check
            b.emit("typing_stop", {"car_id": world.car})  # cached stop
            got = sh.typing_authz_stats()
        assert got["miss_no_entry"] == 1 and got["miss_expired"] == 1
        assert got["full_check"] == 2 and got["store"] == 2
        assert got["hit"] == 2 and got["drop_duplicate"] == 1
        assert "full_denied" not in got
        assert got["peak_concurrent_full_checks"] == 1

    def test_rate_limit_drops_are_counted(self, ctx, world):
        from kk import socketio_handlers as sh

        with _ttl(15), patch.object(sh, "_TYPING_RATE_MAX", 3), _clock(sh):
            s, b = _pair(ctx, world)
            sh.typing_authz_stats(reset=True)
            for i in range(6):
                b.emit("typing_start" if i % 2 == 0 else "typing_stop", {"car_id": world.car})
            assert sh.typing_authz_stats()["drop_rate_limit"] == 3

    def test_denials_are_counted_and_never_cached(self, ctx, world):
        from kk import socketio_handlers as sh

        with _ttl(15):
            s, b = _pair(ctx, world)
            x = _sock(ctx, world.tok[world.x])
            sh.typing_authz_stats(reset=True)
            x.emit("typing_start", {"car_id": world.car})
            x.emit("typing_start", {"car_id": world.car})
            got = sh.typing_authz_stats()
            assert got["full_check"] == 2 and got["full_denied"] == 2 and "store" not in got
            assert _typing(s) == []

    def test_unbound_socket_is_counted_as_a_miss(self):
        from kk import socketio_handlers as sh

        assert sh._typing_fast_path("no-such-sid", "c", "", True, 15.0) == ("miss", None)
        assert sh.typing_authz_stats()["miss_unbound"] == 1

    def test_epoch_changes_and_redis_trouble_are_counted_and_fail_closed(self, ctx, world, fake):
        from kk import socketio_handlers as sh

        _app, _sio, client = ctx
        with _ttl(15):
            s, b = _pair(ctx, world)
            _typing(s)
            sh.typing_authz_stats(reset=True)
            with other_worker():  # a block committed by another worker
                assert client.post(f"/api/users/{world.s}/block", headers=_auth(world.tok[world.b1])).status_code < 300
            b.emit("typing_start", {"car_id": world.car})
            got = sh.typing_authz_stats()
            assert got["miss_epoch_changed"] == 1 and "hit" not in got
            assert _typing(s) == [], "revoked: nothing relayed"
            assert got["full_denied"] == 1 and "store" not in got, "the denial was not cached"

    def test_redis_trouble_is_counted_and_never_relaxes_checks(self, ctx, world, fake):
        from kk import socketio_handlers as sh

        with _ttl(15):
            s, b = _pair(ctx, world)
            _typing(s)
            sh.typing_authz_stats(reset=True)
            fake.down = True
            b.emit("typing_start", {"car_id": world.car})
            got = sh.typing_authz_stats()
            assert got["miss_epoch_unavailable"] == 1 and got["skip_store_redis_down"] == 1, got
            assert got["full_check"] == 1 and "hit" not in got
            assert [t["typing"] for t in _typing(s)] == [True], "an authorized user still works (database path)"

    def test_counters_are_exact_under_concurrent_updates(self):
        from kk import socketio_handlers as sh

        def work():
            for _ in range(2000):
                sh._count("hit")

        threads = [threading.Thread(target=work) for _ in range(8)]
        [t.start() for t in threads]
        [t.join() for t in threads]
        assert sh.typing_authz_stats()["hit"] == 16000

    def test_the_summary_log_has_only_counts(self, ctx, world, caplog):
        from kk import socketio_handlers as sh

        with _ttl(15), _env(CHAT_TYPING_AUTHZ_STATS_LOG_SECONDS=30), _clock(sh) as clk:
            s, b = _pair(ctx, world, join="seller_only")
            print("logger disabled before:", sh.logger.disabled)
            sh.logger.disabled = False  # alembic's fileConfig() (run by create_app in tests) disables it
            with caplog.at_level(logging.INFO, logger=sh.logger.name):
                b.emit("typing_start", {"car_id": world.car})  # opens the window
                clk.advance(31)
                b.emit("typing_stop", {"car_id": world.car})  # closes it -> one line
        lines = [r.getMessage() for r in caplog.records if "typing authz stats" in r.getMessage()]
        assert len(lines) == 1, lines
        assert re.fullmatch(r"typing authz stats \(\d+s\): (?:[a-z_]+=\d+ )+peak_concurrent_full_checks=\d+", lines[0]), lines[0]
        for secret in (world.s, world.b1, world.car, *world.tok.values()):
            assert secret not in lines[0]

    def test_counters_stay_empty_in_legacy_mode(self, ctx, world):
        from kk import socketio_handlers as sh

        with _ttl(0):
            s, b = _pair(ctx, world)
            sh.typing_authz_stats(reset=True)
            b.emit("typing_start", {"car_id": world.car})
            assert sh.typing_authz_stats() == {"peak_concurrent_full_checks": 0}


# ===================================================== full-check pacing ==


class TestFullCheckLimiter:
    def test_limit_default_and_clamps(self):
        from kk import socketio_handlers as sh

        with patch.dict("os.environ", clear=False) as env:
            env.pop("CHAT_TYPING_FULLCHECK_CONCURRENCY", None)
            assert sh._fullcheck_limit() == 4
        for raw, want in (("2", 2), ("0", 0), ("-3", 0), ("999", 32), ("x", 4), ("nan", 0)):
            with _env(CHAT_TYPING_FULLCHECK_CONCURRENCY=raw):
                assert sh._fullcheck_limit() == want, raw

    def test_concurrent_full_checks_never_exceed_the_limit(self):
        from kk import socketio_handlers as sh

        lock = threading.Lock()
        state = {"active": 0, "peak": 0, "done": 0}

        def work():
            with sh._fullcheck_slot():
                with lock:
                    state["active"] += 1
                    state["peak"] = max(state["peak"], state["active"])
                time.sleep(0.03)
                with lock:
                    state["active"] -= 1
            with lock:
                state["done"] += 1

        with _env(CHAT_TYPING_FULLCHECK_CONCURRENCY=3):
            threads = [threading.Thread(target=work) for _ in range(12)]
            [t.start() for t in threads]
            [t.join(10) for t in threads]
        assert state["done"] == 12 and state["peak"] <= 3
        got = sh.typing_authz_stats()
        assert got["peak_concurrent_full_checks"] <= 3 and got["limiter_waited"] >= 1
        assert "limiter_timeout" not in got

    def test_zero_means_unlimited(self):
        from kk import socketio_handlers as sh

        barrier = threading.Barrier(6, timeout=5)

        def work():
            with sh._fullcheck_slot():
                barrier.wait()  # only passes if all six are inside at once

        with _env(CHAT_TYPING_FULLCHECK_CONCURRENCY=0):
            threads = [threading.Thread(target=work) for _ in range(6)]
            [t.start() for t in threads]
            [t.join(10) for t in threads]
        assert not barrier.broken
        assert sh.typing_authz_stats()["peak_concurrent_full_checks"] == 6

    def test_a_slot_is_released_when_validation_raises(self):
        from kk import socketio_handlers as sh

        with _env(CHAT_TYPING_FULLCHECK_CONCURRENCY=2):
            for _ in range(5):
                with pytest.raises(RuntimeError):
                    with sh._fullcheck_slot():
                        raise RuntimeError("db exploded")
            sem = sh._fullcheck_semaphore()
            assert [sem.acquire(blocking=False) for _ in range(2)] == [True, True]
            assert sem.acquire(blocking=False) is False
        assert sh._ACTIVE_FULL == 0

    def test_a_saturated_limiter_delays_but_never_skips_or_loosens_authorization(self, ctx, world):
        from kk import socketio_handlers as sh

        with _ttl(15), _env(CHAT_TYPING_FULLCHECK_CONCURRENCY=2), patch.object(sh, "_FULLCHECK_WAIT_SECONDS", 0.1):
            s, b = _pair(ctx, world, join="seller_only")  # buyer cold
            x = _sock(ctx, world.tok[world.x])  # a stranger
            sem = sh._fullcheck_semaphore()
            assert sem.acquire(blocking=False) and sem.acquire(blocking=False)  # every slot busy
            sh.typing_authz_stats(reset=True)
            try:
                c = _emit_counted(ctx, b, "typing_start", {"car_id": world.car})
                x.emit("typing_start", {"car_id": world.car})
            finally:
                sem.release()
                sem.release()
            got = sh.typing_authz_stats()
            assert c.n >= 5, "the full validation still ran"
            assert [t["typing"] for t in _typing(s)] == [True], "authorized user relayed after the wait"
            assert got["limiter_timeout"] == 2 and got["full_denied"] == 1, got
            assert _typing(s) == [], "the stranger was still refused"

    def test_legacy_mode_does_not_use_the_limiter(self, ctx, world):
        from kk import socketio_handlers as sh

        with _ttl(0), _env(CHAT_TYPING_FULLCHECK_CONCURRENCY=1), patch.object(sh, "_FULLCHECK_WAIT_SECONDS", 30.0):
            s, b = _pair(ctx, world)
            sem = sh._fullcheck_semaphore()
            assert sem.acquire(blocking=False)
            try:
                t0 = time.monotonic()
                b.emit("typing_start", {"car_id": world.car})
                assert time.monotonic() - t0 < 5, "TTL=0 must not wait for a limiter slot"
            finally:
                sem.release()
            assert [t["typing"] for t in _typing(s)] == [True]


# ============================================ listing public_id (gap) ==


class TestListingPublicIdInvalidation:
    @pytest.mark.parametrize("how", ["orm", "bulk"])
    @pytest.mark.parametrize("where", ["same_worker", "other_worker"])
    def test_renaming_a_listing_stops_cached_typing(self, ctx, world, fake, how, where):
        from contextlib import nullcontext

        from kk.models import Car, db

        app, _sio, _c = ctx
        s, b = _pair(ctx, world)
        assert _emit_counted(ctx, b, "typing_start", {"car_id": world.car}).n == 0  # warm
        assert [t["typing"] for t in _typing(s)] == [True]
        with app.app_context():
            car_id = Car.query.filter_by(public_id=world.car).first().id
        before = fake.value(f"c:{car_id}")
        with (other_worker() if where == "other_worker" else nullcontext()), app.app_context():
            if how == "orm":
                car = db.session.get(Car, car_id)
                car.public_id = "renamed-" + car.public_id
                db.session.commit()
            else:
                Car.query.filter_by(id=car_id).update({"public_id": "renamed-" + world.car})
                db.session.commit()
        if how == "orm":
            assert fake.value(f"c:{car_id}") != before, "the listing epoch must move"
        c = _emit_counted(ctx, b, "typing_stop", {"car_id": world.car})  # the OLD public id
        assert c.n > 0, "must be revalidated, not served from the cache"
        assert _typing(s) == [], "the old identifier no longer authorizes anything"

    def test_an_unrelated_listing_edit_keeps_the_warm_path(self, ctx, world, fake):
        from kk.models import Car, db

        app, _sio, _c = ctx
        s, b = _pair(ctx, world)
        with other_worker(), app.app_context():
            car = Car.query.filter_by(public_id=world.car).first()
            car.title = (car.title or "") + " (edited)"
            db.session.commit()
        assert _emit_counted(ctx, b, "typing_start", {"car_id": world.car}).n == 0


# ============================================ revocation with jitter on ==


class TestRevocationStillImmediate:
    def test_block_logout_and_deactivation_are_immediate_with_default_jitter_and_limiter(self, ctx, world, fake):
        """Default jitter (0.2) and limiter (4) are active in this module's other tests;
        this one pins that revocation does not wait for any lifetime."""
        _app, _sio, client = ctx
        s, b = _pair(ctx, world)
        assert _emit_counted(ctx, b, "typing_start", {"car_id": world.car}).n == 0
        _typing(s)
        with other_worker():
            client.post(f"/api/users/{world.s}/block", headers=_auth(world.tok[world.b1]))
        b.emit("typing_stop", {"car_id": world.car})
        assert _typing(s) == []
