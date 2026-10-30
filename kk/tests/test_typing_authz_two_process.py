"""Typing authorization cache: REAL cross-process invalidation through a REAL Redis.

The simulated "other worker" in ``test_typing_authz_redis.py`` shares this
process's memory. Here worker A (this process, with live sockets and a warm
cache) and worker B (a separate OS process running the real app, real ORM
listeners and real Redis client) only share the database file and Redis, exactly
like two Gunicorn workers. B commits a change; A must stop relaying typing.

Opt-in (needs a Redis server, so it is skipped in CI):

    TYPING_AUTHZ_REAL_REDIS_URL=redis://127.0.0.1:6392/0 pytest \
        kk/tests/test_typing_authz_two_process.py -s
"""

# ruff: noqa: F811, F401
from __future__ import annotations

import json
import os
import statistics
import subprocess
import sys
import time
import uuid
from pathlib import Path

import pytest

from test_chat_f05_f25_f36_isolation import _auth, _drain, _sock, ctx, world  # noqa: F401
from test_typing_authz_cache import _bound, _emit_counted, _pair, _typing

REAL_URL = os.environ.get("TYPING_AUTHZ_REAL_REDIS_URL", "").strip()
pytestmark = pytest.mark.skipif(not REAL_URL, reason="set TYPING_AUTHZ_REAL_REDIS_URL to run")

_REPO_ROOT = Path(__file__).resolve().parents[2]

_WORKER_B = r"""
import json, os, sys
sys.path.insert(0, os.getcwd())
from datetime import timedelta
from kk.app_factory import create_app
app, socketio, *_ = create_app()
from kk.models import BlockedUser, TokenBlacklist, User, db
from kk.time_utils import utcnow

def uid(pub):
    return User.query.filter_by(public_id=pub).first().id

def run(cmd):
    op = cmd["op"]
    if op == "block":
        db.session.add(BlockedUser(blocker_id=uid(cmd["a"]), blocked_id=uid(cmd["b"])))
    elif op == "unblock":
        for row in BlockedUser.query.filter_by(blocker_id=uid(cmd["a"]), blocked_id=uid(cmd["b"])).all():
            db.session.delete(row)
    elif op == "deactivate_bulk":
        User.query.filter_by(public_id=cmd["user"]).update({"is_active": False})
    elif op == "benign_bulk":
        User.query.filter_by(public_id=cmd["user"]).update({"firebase_token": "x"})
    elif op == "revoke_token":
        db.session.add(TokenBlacklist(jti=cmd["jti"], token_type="access",
                                      user_id=uid(cmd["user"]), expires_at=utcnow() + timedelta(hours=1)))
    elif op == "raw_block":
        from sqlalchemy import insert
        db.session.execute(insert(BlockedUser).values(blocker_id=uid(cmd["a"]), blocked_id=uid(cmd["b"])))
    else:
        raise SystemExit("unknown op " + op)
    db.session.commit()

print(json.dumps({"ready": True}), flush=True)
for line in sys.stdin:
    cmd = json.loads(line)
    with app.app_context():
        try:
            run(cmd)
            out = {"ok": True, "pid": os.getpid()}
        except Exception as exc:  # reported to the test
            db.session.rollback()
            out = {"ok": False, "error": repr(exc)}
    print(json.dumps(out), flush=True)
"""


class WorkerB:
    def __init__(self, env):
        self.p = subprocess.Popen(
            [sys.executable, "-c", _WORKER_B],
            cwd=str(_REPO_ROOT),
            env=env,
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            text=True,
        )
        deadline = time.time() + 180
        line = ""
        while time.time() < deadline:
            line = self.p.stdout.readline()
            if line.strip().startswith("{"):
                break
        assert json.loads(line)["ready"], "worker B did not start"

    def do(self, **cmd) -> int:
        self.p.stdin.write(json.dumps(cmd) + "\n")
        self.p.stdin.flush()
        out = json.loads(self.p.stdout.readline())
        assert out["ok"], out
        return out["pid"]

    def close(self):
        try:
            self.p.stdin.close()
            self.p.wait(timeout=20)
        except Exception:
            self.p.kill()


@pytest.fixture
def two_workers(ctx, monkeypatch):
    import redis

    from kk import socketio_handlers as sh

    monkeypatch.setenv("CHAT_TYPING_AUTHZ_REDIS_URL", REAL_URL)
    monkeypatch.setattr(sh, "_REDIS_CLIENT", None)
    monkeypatch.setattr(sh, "_REDIS_DOWN_UNTIL", 0.0)
    admin = redis.Redis.from_url(REAL_URL, decode_responses=True)
    admin.flushall()
    env = dict(os.environ)
    env["CHAT_TYPING_AUTHZ_REDIS_URL"] = REAL_URL
    env.pop("REDIS_URL", None)
    b = WorkerB(env)
    assert b.p.pid != os.getpid()
    yield b, admin
    b.close()


def _fresh_pair(ctx, world):
    s, b = _pair(ctx, world)
    b.emit("typing_start", {"car_id": world.car})
    assert [t["typing"] for t in _typing(s)] == [True]
    s.get_received()
    return s, b


class TestRealTwoProcessInvalidation:
    def test_warm_path_is_sql_free_and_fast_against_real_redis(self, ctx, world, two_workers, capsys):
        from kk import socketio_handlers as sh

        _w, _admin = two_workers
        s, b = _fresh_pair(ctx, world)
        assert _emit_counted(ctx, b, "typing_stop", {"car_id": world.car}).n == 0
        ((_sid, rec),) = _bound(sh, world.b1)
        (entry,) = rec["authz"].values()
        times = []
        for _ in range(300):
            t = time.perf_counter()
            assert sh._entry_epochs_current(entry)
            times.append((time.perf_counter() - t) * 1000)
        times.sort()
        with capsys.disabled():
            print(
                f"\n[real Redis] warm epoch check: p50={statistics.median(times):.3f} ms "
                f"p95={times[int(len(times) * .95)]:.3f} ms max={times[-1]:.3f} ms"
            )

    def test_a_block_committed_in_another_process_cuts_typing_off(self, ctx, world, two_workers):
        worker, _admin = two_workers
        s, b = _fresh_pair(ctx, world)
        pid = worker.do(op="block", a=world.b1, b=world.s)
        assert pid != os.getpid()
        b.emit("typing_stop", {"car_id": world.car})
        b.emit("typing_start", {"car_id": world.car})
        assert _typing(s) == []
        s.emit("typing_start", {"car_id": world.car, "peer_id": world.b1})
        assert _typing(b) == []
        worker.do(op="unblock", a=world.b1, b=world.s)
        b.emit("typing_start", {"car_id": world.car})
        assert [t["typing"] for t in _typing(s)] == [True]

    def test_a_raw_core_block_in_another_process_cuts_typing_off(self, ctx, world, two_workers):
        worker, _admin = two_workers
        s, b = _fresh_pair(ctx, world)
        worker.do(op="raw_block", a=world.b1, b=world.s)
        b.emit("typing_stop", {"car_id": world.car})
        assert _typing(s) == []

    def test_a_token_revoked_in_another_process_closes_the_socket(self, ctx, world, two_workers):
        from kk import socketio_handlers as sh

        worker, _admin = two_workers
        s, b = _fresh_pair(ctx, world)
        ((_sid, rec),) = _bound(sh, world.b1)
        worker.do(op="revoke_token", jti=rec["jti"], user=world.b1)
        b.emit("typing_stop", {"car_id": world.car})
        assert any(e["name"] == "auth_expired" for e in _drain(b))
        assert not b.is_connected() and _typing(s) == []

    def test_a_bulk_deactivation_in_another_process_closes_the_socket(self, ctx, world, two_workers):
        worker, _admin = two_workers
        s, b = _fresh_pair(ctx, world)
        worker.do(op="deactivate_bulk", user=world.b1)
        b.emit("typing_stop", {"car_id": world.car})
        assert not b.is_connected() and _typing(s) == []

    def test_a_benign_update_in_another_process_keeps_the_warm_path(self, ctx, world, two_workers):
        worker, _admin = two_workers
        s, b = _fresh_pair(ctx, world)
        worker.do(op="benign_bulk", user=world.b1)
        assert _emit_counted(ctx, b, "typing_stop", {"car_id": world.car}).n == 0

    def test_real_redis_data_loss_forces_revalidation(self, ctx, world, two_workers):
        _worker, admin = two_workers
        s, b = _fresh_pair(ctx, world)
        admin.flushall()
        assert _emit_counted(ctx, b, "typing_stop", {"car_id": world.car}).n >= 5
        assert _emit_counted(ctx, b, "typing_start", {"car_id": world.car}).n == 0

    def test_real_redis_unreachable_fails_closed_then_recovers(self, ctx, world, two_workers, monkeypatch):
        from kk import socketio_handlers as sh

        _worker, _admin = two_workers
        s, b = _fresh_pair(ctx, world)
        monkeypatch.setenv("CHAT_TYPING_AUTHZ_REDIS_URL", "redis://127.0.0.1:1/0")  # refused
        monkeypatch.setattr(sh, "_REDIS_CLIENT", None)
        t = time.perf_counter()
        c = _emit_counted(ctx, b, "typing_stop", {"car_id": world.car})
        first_ms = (time.perf_counter() - t) * 1000
        assert c.n >= 5, "full database validation while Redis is unreachable"
        assert first_ms < 2000
        assert _emit_counted(ctx, b, "typing_start", {"car_id": world.car}).n >= 5
        real = sh._mono
        monkeypatch.setenv("CHAT_TYPING_AUTHZ_REDIS_URL", REAL_URL)
        monkeypatch.setattr(sh, "_REDIS_CLIENT", None)
        monkeypatch.setattr(sh, "_mono", lambda: real() + 6)
        _emit_counted(ctx, b, "typing_stop", {"car_id": world.car})  # re-caches
        assert _emit_counted(ctx, b, "typing_start", {"car_id": world.car}).n == 0


class TestControl:
    def test_without_publication_the_other_process_cannot_cut_typing_off(self, ctx, world, two_workers):
        """Negative control: if worker B does NOT talk to Redis, A's cache stays
        valid until the TTL. Proves the tests above pass because of Redis."""
        _w, _admin = two_workers
        env = dict(os.environ)
        env.pop("CHAT_TYPING_AUTHZ_REDIS_URL", None)
        env.pop("REDIS_URL", None)
        silent_b = WorkerB(env)
        try:
            s, b = _fresh_pair(ctx, world)
            silent_b.do(op="block", a=world.b1, b=world.s)
            b.emit("typing_stop", {"car_id": world.car})
            assert [t["typing"] for t in _typing(s)] == [False], "stale inside the TTL, as expected"
        finally:
            silent_b.close()
