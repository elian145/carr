"""F-06 push-token registration against a REAL PostgreSQL server (deadlocks).

``POST /api/users/push_token`` moves a device token to the caller and clears it
from every other account in one transaction. SQLite has neither row locks nor
real concurrency, so the claims below can only be proven on PostgreSQL with
genuinely concurrent connections:

* two accounts SWAPPING tokens at the same instant used to make PostgreSQL abort
  one request with ``deadlock detected`` (SQLSTATE 40P01) -> HTTP 500. Rows are
  now locked in id order (no deadlock) and, as a safety net, the registration is
  retried -- boundedly, and ONLY on SQLSTATE 40P01;
* concurrent registrations of ONE token still leave exactly one owner (the last
  committer);
* the retry is bounded, is not triggered by other errors, restarts from a fresh
  transaction and leaves state untouched when it gives up;
* a failed commit rolls back cleanly and leaks no advisory lock.

It is SKIPPED unless ``CARNET_PG_TEST_URL`` is set, and it refuses to run unless
the server is local and ``CARNET_PG_TEST_CONFIRM_DISPOSABLE=1``: the target
database is DROPPED and re-created.

    CARNET_PG_TEST_URL=postgresql://postgres@127.0.0.1:55443/carnet_f06_dl
    CARNET_PG_TEST_CONFIRM_DISPOSABLE=1
    pytest kk/tests/test_f06_pg_deadlock.py
"""

from __future__ import annotations

import os
import sys
import tempfile
import threading
import time
import uuid
from pathlib import Path

import pytest

_REPO_ROOT = Path(__file__).resolve().parents[2]
if str(_REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(_REPO_ROOT))

PG_URL = (os.environ.get("CARNET_PG_TEST_URL") or "").strip()

pytestmark = pytest.mark.skipif(not PG_URL, reason="CARNET_PG_TEST_URL not set (PostgreSQL rehearsal only)")

_PASSWORD = "Aa123456!"
SWAP_ROUNDS = 30
RETRY_ONLY_ROUNDS = 10
SAME_TOKEN_ROUNDS = 12
SAME_TOKEN_ACCOUNTS = 8


# ---------------------------------------------------------------------------
# Disposable database + app
# ---------------------------------------------------------------------------


def _admin_dsn(url):
    return url.set(drivername="postgresql", database="postgres").render_as_string(hide_password=False)


@pytest.fixture(scope="module")
def pg_app():
    import psycopg
    from sqlalchemy.engine import make_url

    url = make_url(PG_URL).set(drivername="postgresql")
    if url.host not in ("localhost", "127.0.0.1", "::1") or os.environ.get("CARNET_PG_TEST_CONFIRM_DISPOSABLE") != "1":
        pytest.fail(
            "Refusing to run: the target database is dropped and re-created, so the server must be local "
            "and CARNET_PG_TEST_CONFIRM_DISPOSABLE=1 must be set."
        )
    name = url.database
    with psycopg.connect(_admin_dsn(url), autocommit=True) as c:
        c.execute(f'DROP DATABASE IF EXISTS "{name}" WITH (FORCE)')
        c.execute(f'CREATE DATABASE "{name}"')
        # Resolve a genuine deadlock in ~50 ms instead of the default 1 s so the
        # "retry alone rescues a real deadlock" test stays fast (applies to new
        # connections of this disposable database only).
        c.execute(f'ALTER DATABASE "{name}" SET deadlock_timeout = \'50ms\'')

    tmp = tempfile.TemporaryDirectory(prefix="carlist_f06_pg_", ignore_cleanup_errors=True)
    env = pytest.MonkeyPatch()
    env.setenv("APP_ENV", "testing")
    env.setenv("SMS_PROVIDER", "console")
    env.setenv("SECRET_KEY", "f06-pg-secret")
    env.setenv("JWT_SECRET_KEY", "f06-pg-jwt-secret")
    env.delenv("DB_PATH", raising=False)
    env.setenv("DATABASE_URL", url.render_as_string(hide_password=False))
    env.setenv("UPLOAD_FOLDER", os.path.join(tmp.name, "uploads"))
    env.setenv("AUTO_MIGRATE", "0")  # empty database: create_all, no migration chain

    from kk.app_factory import create_app

    app, _socketio, *_ = create_app()
    assert app.config["SQLALCHEMY_DATABASE_URI"].startswith("postgresql"), app.config["SQLALCHEMY_DATABASE_URI"]

    from kk.models import db

    with app.app_context():
        db.create_all()
    yield app
    with app.app_context():
        db.session.remove()
        db.engine.dispose()
    tmp.cleanup()
    env.undo()


@pytest.fixture
def app(pg_app):
    return pg_app


@pytest.fixture(scope="module")
def accounts(pg_app):
    """SAME_TOKEN_ACCOUNTS registered users: [(user_id, access_token), ...]."""
    from kk.models import User, db

    out = []
    for i in range(SAME_TOKEN_ACCOUNTS):
        with pg_app.app_context():
            username = f"f06pg_{i}_{uuid.uuid4().hex[:8]}"
            user = User(
                username=username,
                phone_number=f"078{uuid.uuid4().int % 10**8:08d}",
                first_name="P",
                last_name="G",
                is_active=True,
                is_verified=True,
                phone_verified=True,
                public_id=f"f06pg-{uuid.uuid4().hex[:12]}",
            )
            user.set_password(_PASSWORD)
            db.session.add(user)
            db.session.commit()
            uid = user.id
        resp = pg_app.test_client().post("/api/auth/login", json={"username": username, "password": _PASSWORD})
        assert resp.status_code == 200, resp.data
        out.append((uid, resp.get_json()["access_token"]))
    # Ids ascend with creation order; the tests rely on `accounts[0].id < accounts[1].id`.
    assert [a[0] for a in out] == sorted(a[0] for a in out)
    return out


@pytest.fixture(autouse=True)
def clean_tokens(pg_app):
    from kk.models import User, db

    with pg_app.app_context():
        db.session.query(User).update({User.firebase_token: None})
        db.session.commit()
    yield


# ---------------------------------------------------------------------------
# helpers
# ---------------------------------------------------------------------------


def _auth(access):
    return {"Authorization": f"Bearer {access}"}


def _post(app, access, token):
    return app.test_client().post("/api/users/push_token", json={"token": token}, headers=_auth(access))


def _owners(app, token):
    from kk.models import User, db

    with app.app_context():
        db.session.expire_all()
        return sorted(u.id for u in User.query.filter(User.firebase_token == token).all())


def _token_of(app, uid):
    from kk.models import User, db

    with app.app_context():
        db.session.expire_all()
        return db.session.get(User, uid).firebase_token


def _set_tokens(app, mapping):
    from kk.models import User, db

    with app.app_context():
        for uid, token in mapping.items():
            db.session.get(User, uid).firebase_token = token
        db.session.commit()


def _advisory_locks(app):
    from sqlalchemy import text

    from kk.models import db

    with app.app_context():
        n = db.session.execute(text("select count(*) from pg_locks where locktype = 'advisory'")).scalar()
        db.session.rollback()
        return n


def _race(app, jobs, timeout=60):
    """Start all ``jobs`` [(access, token)] at once (barrier), each with its own client.

    Returns ``({index: status}, {index: commit_time_ns})``.
    """
    from sqlalchemy import event
    from sqlalchemy.orm import Session

    statuses, commits = {}, {}
    barrier = threading.Barrier(len(jobs))

    def on_commit(session):
        name = threading.current_thread().name
        if name.startswith("race-"):
            commits[int(name[5:])] = time.perf_counter_ns()

    event.listen(Session, "after_commit", on_commit)
    try:

        def worker(i, access, token):
            client = app.test_client()
            barrier.wait(timeout)
            statuses[i] = client.post(
                "/api/users/push_token", json={"token": token}, headers=_auth(access)
            ).status_code

        threads = [
            threading.Thread(target=worker, args=(i, a, t), name=f"race-{i}", daemon=True)
            for i, (a, t) in enumerate(jobs)
        ]
        for t in threads:
            t.start()
        for t in threads:
            t.join(timeout)
        assert not any(t.is_alive() for t in threads), "registration request hung (possible deadlock)"
    finally:
        event.remove(Session, "after_commit", on_commit)
    return statuses, commits


def _deadlock_error(statement="UPDATE user SET firebase_token=NULL"):
    import psycopg.errors
    from sqlalchemy.exc import OperationalError

    return OperationalError(statement, {}, psycopg.errors.DeadlockDetected("deadlock detected"))


class _InjectOnClear:
    """Raise ``make_exc()`` from the first ``times`` executions of the clear-UPDATE.

    The error is raised AFTER the advisory lock and the row locks were taken and
    BEFORE anything is written, i.e. in the middle of the transaction -- exactly
    where PostgreSQL reports a deadlock.
    """

    def __init__(self, times, make_exc):
        self.times, self.make_exc, self.hits = times, make_exc, 0

    def __enter__(self):
        from sqlalchemy import event
        from sqlalchemy.engine import Engine

        def before(conn, cursor, statement, parameters, context, executemany):
            up = statement.lstrip().upper()
            if up.startswith('UPDATE "USER" SET') and '!=' in up:  # the clear, not the ORM flush
                self.hits += 1
                if self.hits <= self.times:
                    raise self.make_exc()

        self._before = before
        event.listen(Engine, "before_cursor_execute", before)
        return self

    def __exit__(self, *exc):
        from sqlalchemy import event
        from sqlalchemy.engine import Engine

        event.remove(Engine, "before_cursor_execute", self._before)


# ---------------------------------------------------------------------------
# (a) swap: two (and three) accounts exchange tokens at the same instant
# ---------------------------------------------------------------------------


def test_swap_two_accounts_never_500(app, accounts):
    (a_id, a_acc), (b_id, b_acc) = accounts[0], accounts[1]
    for r in range(SWAP_ROUNDS):
        x, y = f"swap-X-{r}-{uuid.uuid4().hex[:6]}", f"swap-Y-{r}-{uuid.uuid4().hex[:6]}"
        _set_tokens(app, {a_id: y, b_id: x})
        statuses, _ = _race(app, [(a_acc, x), (b_acc, y)])
        assert statuses == {0: 200, 1: 200}, f"round {r}: {statuses}"
        assert _owners(app, x) == [a_id], f"round {r}: token X owners {_owners(app, x)}"
        assert _owners(app, y) == [b_id], f"round {r}: token Y owners {_owners(app, y)}"
    assert _advisory_locks(app) == 0


def test_swap_three_account_rotation_never_500(app, accounts):
    ids = [a[0] for a in accounts[:3]]
    for r in range(SWAP_ROUNDS // 2):
        toks = [f"rot-{k}-{r}-{uuid.uuid4().hex[:6]}" for k in range(3)]
        # account k holds toks[k-1] and registers toks[k]: a cycle A->B->C->A.
        _set_tokens(app, {ids[k]: toks[k - 1] for k in range(3)})
        statuses, _ = _race(app, [(accounts[k][1], toks[k]) for k in range(3)])
        assert statuses == {0: 200, 1: 200, 2: 200}, f"round {r}: {statuses}"
        for k in range(3):
            assert _owners(app, toks[k]) == [ids[k]], f"round {r}: token {k} owners {_owners(app, toks[k])}"


def test_retry_alone_rescues_a_real_deadlock(app, accounts, monkeypatch):
    """Safety net: with the id-ordered locking removed, genuine PostgreSQL
    deadlocks still happen on a swap -- and the bounded retry hides every one."""
    import kk.routes.chat as chat_mod
    from kk.models import User, db

    attempts = {"n": 0}
    lock = threading.Lock()

    def unordered_assign(me, token):  # the baseline (pre-ordering) sequence
        with lock:
            attempts["n"] += 1
        chat_mod._serialize_push_token_registration(token)
        db.session.query(User).filter(User.firebase_token == token, User.id != me.id).update(
            {User.firebase_token: None}, synchronize_session=False
        )
        me.firebase_token = token
        db.session.commit()

    monkeypatch.setattr(chat_mod, "_assign_push_token", unordered_assign)

    (a_id, a_acc), (b_id, b_acc) = accounts[0], accounts[1]
    for r in range(RETRY_ONLY_ROUNDS):
        x, y = f"retry-X-{r}-{uuid.uuid4().hex[:6]}", f"retry-Y-{r}-{uuid.uuid4().hex[:6]}"
        _set_tokens(app, {a_id: y, b_id: x})
        statuses, _ = _race(app, [(a_acc, x), (b_acc, y)])
        assert statuses == {0: 200, 1: 200}, f"round {r}: {statuses}"
        assert _owners(app, x) == [a_id] and _owners(app, y) == [b_id], f"round {r}"
    # Every deadlock shows up as an extra attempt: without any, this test would
    # not be exercising the retry at all.
    assert attempts["n"] > 2 * RETRY_ONLY_ROUNDS, attempts
    assert _advisory_locks(app) == 0


# ---------------------------------------------------------------------------
# (b) one token, many accounts
# ---------------------------------------------------------------------------


def test_same_token_many_accounts_exactly_one_owner_the_last_committer(app, accounts):
    ids = [a[0] for a in accounts]
    for r in range(SAME_TOKEN_ROUNDS):
        token = f"same-{r}-{uuid.uuid4().hex[:6]}"
        statuses, commits = _race(app, [(acc, token) for _, acc in accounts])
        assert set(statuses.values()) == {200}, f"round {r}: {statuses}"
        owners = _owners(app, token)
        assert len(owners) == 1, f"round {r}: owners {owners}"
        last = max(commits, key=commits.get)
        assert owners == [ids[last]], f"round {r}: owner {owners}, last committer {ids[last]}"
    assert _advisory_locks(app) == 0


# ---------------------------------------------------------------------------
# (c) retry bounds + specificity
# ---------------------------------------------------------------------------


def _setup_ab(app, accounts, a_tok, b_tok):
    (a_id, a_acc), (b_id, b_acc) = accounts[0], accounts[1]
    _set_tokens(app, {a_id: a_tok, b_id: b_tok})
    return a_id, a_acc, b_id, b_acc


def test_deadlock_is_retried_a_bounded_number_of_times_then_500_and_state_unchanged(app, accounts):
    import kk.routes.chat as chat_mod

    a_id, a_acc, b_id, _ = _setup_ab(app, accounts, "old-A", "target")
    # B owns "target"; A tries to take it, but PostgreSQL "deadlocks" every time.
    with _InjectOnClear(times=10**6, make_exc=_deadlock_error) as inj:
        started = time.perf_counter()
        resp = _post(app, accounts[0][1], "target")
        elapsed = time.perf_counter() - started
    assert chat_mod._PUSH_TOKEN_MAX_ATTEMPTS == 3
    assert inj.hits == chat_mod._PUSH_TOKEN_MAX_ATTEMPTS, "exactly the bounded number of attempts"
    assert resp.status_code == 500
    assert resp.get_json() == {"message": "Failed to register token"}  # nothing leaked
    assert elapsed < 2.0, "backoff must stay tiny"
    assert _token_of(app, a_id) == "old-A" and _token_of(app, b_id) == "target"  # nothing changed
    assert _advisory_locks(app) == 0


@pytest.mark.parametrize("fail_times", [1, 2])
def test_deadlock_then_success_uses_a_fresh_transaction_and_reloads_the_user(app, accounts, monkeypatch, fail_times):
    import kk.routes.chat as chat_mod

    a_id, a_acc, b_id, _ = _setup_ab(app, accounts, "old-A", "target")
    loads = {"n": 0}
    real_get_user = chat_mod.get_current_user

    def counting_get_user():
        loads["n"] += 1
        return real_get_user()

    monkeypatch.setattr(chat_mod, "get_current_user", counting_get_user)
    with _InjectOnClear(times=fail_times, make_exc=_deadlock_error) as inj:
        resp = _post(app, a_acc, "target")
    assert resp.status_code == 200, resp.data
    assert inj.hits == fail_times + 1
    assert loads["n"] == fail_times + 1, "the caller is re-read from the DB on every retry"
    assert _owners(app, "target") == [a_id]  # exactly one owner, the registrant
    assert _token_of(app, b_id) is None
    assert _advisory_locks(app) == 0


def _other_errors():
    import psycopg.errors
    from sqlalchemy.exc import IntegrityError, OperationalError

    stmt = "UPDATE user SET firebase_token=NULL"
    return {
        "serialization_failure_40001": lambda: OperationalError(stmt, {}, psycopg.errors.SerializationFailure("x")),
        "lock_not_available_55P03": lambda: OperationalError(stmt, {}, psycopg.errors.LockNotAvailable("x")),
        "unique_violation": lambda: IntegrityError(stmt, {}, psycopg.errors.UniqueViolation("x")),
        "plain_dbapi_error_without_sqlstate": lambda: OperationalError(stmt, {}, Exception("deadlock detected")),
        "plain_runtime_error": lambda: RuntimeError("deadlock detected"),
    }


@pytest.mark.parametrize("kind", sorted(_other_errors()))
def test_only_deadlock_is_retried_other_errors_fail_on_the_first_attempt(app, accounts, kind):
    a_id, a_acc, b_id, _ = _setup_ab(app, accounts, "old-A", "target")
    with _InjectOnClear(times=10**6, make_exc=_other_errors()[kind]) as inj:
        resp = _post(app, a_acc, "target")
    assert inj.hits == 1, f"{kind} must not be retried"
    assert resp.status_code == 500
    assert resp.get_json() == {"message": "Failed to register token"}
    assert _token_of(app, a_id) == "old-A" and _token_of(app, b_id) == "target"
    assert _advisory_locks(app) == 0


def test_pg_deadlock_detection_is_specific(app):
    import psycopg.errors
    from sqlalchemy.exc import IntegrityError, OperationalError

    import kk.routes.chat as chat_mod

    class Psycopg2Style(Exception):  # psycopg2 exposes ``pgcode`` instead of ``sqlstate``
        pgcode = "40P01"

    with app.app_context():
        assert chat_mod._is_pg_deadlock(_deadlock_error())
        assert chat_mod._is_pg_deadlock(OperationalError("s", {}, Psycopg2Style()))
        assert not chat_mod._is_pg_deadlock(OperationalError("s", {}, psycopg.errors.SerializationFailure("x")))
        assert not chat_mod._is_pg_deadlock(IntegrityError("s", {}, psycopg.errors.UniqueViolation("x")))
        assert not chat_mod._is_pg_deadlock(RuntimeError("deadlock detected"))


# ---------------------------------------------------------------------------
# (d) rollback
# ---------------------------------------------------------------------------


def test_failed_commit_keeps_the_previous_owner_and_leaks_no_advisory_lock(app, accounts):
    from sqlalchemy import event
    from sqlalchemy.orm import Session

    (a_id, a_acc), (b_id, b_acc), (c_id, c_acc) = accounts[0], accounts[1], accounts[2]
    assert _post(app, a_acc, "tok-rb").status_code == 200
    assert _owners(app, "tok-rb") == [a_id]

    armed = {"on": True}

    def boom(session):
        if armed["on"]:
            armed["on"] = False
            raise RuntimeError("injected commit failure")

    event.listen(Session, "before_commit", boom)
    try:
        resp = _post(app, b_acc, "tok-rb")  # clears A's token, then the commit fails
    finally:
        event.remove(Session, "before_commit", boom)
    assert resp.status_code == 500
    assert _owners(app, "tok-rb") == [a_id], "failed registration must change nothing"
    assert _token_of(app, b_id) is None
    assert _advisory_locks(app) == 0

    started = time.perf_counter()
    assert _post(app, c_acc, "tok-rb").status_code == 200  # must not block on a leaked lock
    assert time.perf_counter() - started < 5
    assert _owners(app, "tok-rb") == [c_id]
    assert _advisory_locks(app) == 0


# ---------------------------------------------------------------------------
# unchanged behaviours on PostgreSQL
# ---------------------------------------------------------------------------


def test_blank_token_disable_and_idempotent_reregister_unchanged(app, accounts):
    (a_id, a_acc), (b_id, b_acc) = accounts[0], accounts[1]
    assert _post(app, a_acc, "   ").status_code == 400
    assert _post(app, a_acc, "idem").status_code == 200
    assert _post(app, a_acc, "idem").status_code == 200  # same user re-registers: idempotent
    assert _owners(app, "idem") == [a_id]
    assert _post(app, b_acc, "idem").status_code == 200  # another account takes it over
    assert _owners(app, "idem") == [b_id]
    resp = app.test_client().post("/api/users/push_token", json={"enabled": False}, headers=_auth(b_acc))
    assert resp.status_code == 200 and resp.get_json() == {"message": "Push disabled"}
    assert _owners(app, "idem") == []
