"""F-04 durable saved-search alerts against a REAL PostgreSQL server.

SQLite serialises writers and has no row locks, so these claims can only be
proven on PostgreSQL with genuinely concurrent connections:

* the lease claim (one conditional UPDATE) admits exactly ONE of N concurrent
  runners; N concurrent sweeps win the dispatch lease of each due job once (one enqueue
  per job per lease period; this is about enqueueing, not delivery);
* the claim-first pair insert BLOCKS a concurrent same-pair runner on the
  unique index until the first one commits (then it skips WITHOUT pushing) or
  rolls back (then it takes over and pushes). The external push stays
  at-least-once with bounded duplicates -- this module never asserts
  exactly-once delivery, only the committed rows (one alert row, one in-app
  Notification) and the bounded push count;
* the UNIQUE(car_id) first-publication marker survives a concurrent double
  record, rolls back with the activating transaction, degrades (without
  poisoning the surrounding transaction) if the table is missing, and is
  removed by the ``car`` FK cascade;
* the Alembic migration upgrades / downgrades / re-upgrades a database built
  by the full chain, with a single head.

SKIPPED unless ``CARNET_PG_TEST_URL`` is set; refuses to run unless the server
is local and ``CARNET_PG_TEST_CONFIRM_DISPOSABLE=1``: the target database (and
``<name>_mig``) is DROPPED and re-created.

    CARNET_PG_TEST_URL=postgresql://postgres@127.0.0.1:55432/carnet_f04_pg
    CARNET_PG_TEST_CONFIRM_DISPOSABLE=1
    pytest kk/tests/test_f04_pg_durable_alerts.py
"""

from __future__ import annotations

import os
import subprocess
import sys
import tempfile
import threading
import time
from datetime import timedelta
from pathlib import Path

import pytest

from kk.tests.test_f04_durable_alert_jobs import (  # noqa: F401  (fixtures + helpers)
    _admin_token,
    _alert_rows,
    _bulk,
    _car,
    _job,
    _job_count,
    _notif_count,
    _patch,
    _set_flag,
    _state,
    _threads,
    _user,
    _watchers,
    broker,
    isolate,
    pushes,
)

_REPO_ROOT = Path(__file__).resolve().parents[2]
if str(_REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(_REPO_ROOT))

PG_URL = (os.environ.get("CARNET_PG_TEST_URL") or "").strip()

pytestmark = pytest.mark.skipif(not PG_URL, reason="CARNET_PG_TEST_URL not set (PostgreSQL rehearsal only)")

HEAD = "f04a1b2c3d4e"
# B8: the account_deletion_request migration is stacked on the F-04 revision;
# `flask db upgrade` therefore lands on TIP, and the F-04 table is part of it.
TIP = "a7d3e1c9b5f2"
PREV_HEAD = "v0w1x2y3z4a5"
WAIT = 45


# ---------------------------------------------------------------------------
# Disposable database + app
# ---------------------------------------------------------------------------


def _admin_dsn(url):
    return url.set(drivername="postgresql", database="postgres").render_as_string(hide_password=False)


def _require_disposable(url):
    if url.host not in ("localhost", "127.0.0.1", "::1") or os.environ.get("CARNET_PG_TEST_CONFIRM_DISPOSABLE") != "1":
        pytest.fail(
            "Refusing to run: the target database is dropped and re-created, so the server must be local "
            "and CARNET_PG_TEST_CONFIRM_DISPOSABLE=1 must be set."
        )


def _recreate(url, name):
    import psycopg

    with psycopg.connect(_admin_dsn(url), autocommit=True) as c:
        c.execute(f'DROP DATABASE IF EXISTS "{name}" WITH (FORCE)')
        c.execute(f'CREATE DATABASE "{name}"')


@pytest.fixture(scope="module")
def pg_app():
    from sqlalchemy.engine import make_url

    url = make_url(PG_URL).set(drivername="postgresql")
    _require_disposable(url)
    _recreate(url, url.database)

    tmp = tempfile.TemporaryDirectory(prefix="carlist_f04_pg_", ignore_cleanup_errors=True)
    env = pytest.MonkeyPatch()  # restored at teardown: nothing leaks into later modules
    env.setenv("APP_ENV", "testing")
    env.setenv("SMS_PROVIDER", "console")
    env.setenv("SECRET_KEY", "f04-pg-secret")
    env.setenv("JWT_SECRET_KEY", "f04-pg-jwt-secret")
    env.delenv("DB_PATH", raising=False)
    env.delenv("LISTING_REQUIRE_APPROVAL", raising=False)
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


@pytest.fixture
def client(pg_app):
    return pg_app.test_client()


def _activate(client, app, car, *, token=None):
    token = token or _admin_token(app, client)
    r = _patch(client, token, car, {"status": "active"})
    assert r.status_code == 200, r.data
    return token


class Runner(threading.Thread):
    """Runs ``fn`` in its own app context / DB connection; captures the outcome."""

    def __init__(self, app, fn):
        super().__init__(daemon=True)
        self.app, self.fn, self.result, self.error = app, fn, None, None

    def run(self):
        try:
            with self.app.app_context():
                self.result = self.fn()
        except BaseException as exc:  # noqa: BLE001 - surfaced by the test
            self.error = exc


# ---------------------------------------------------------------------------
# Concurrent lease claims / sweeps
# ---------------------------------------------------------------------------


def test_pg_concurrent_job_claims_admit_exactly_one_runner(app, client, broker, monkeypatch):
    from kk import saved_search_alert_jobs as jobs

    _set_flag(monkeypatch, "on")
    seller, _ = _user(app)
    car = _car(app, seller)
    _activate(client, app, car)
    res = _threads(app, lambda i: jobs.claim_job(car["id"]).status, 8)
    assert sorted(res) == ["claimed"] + ["not_owner"] * 7
    assert _job(app, car["id"])["attempts"] == 1


def test_pg_concurrent_sweeps_enqueue_each_due_job_exactly_once(app, client, broker, monkeypatch):
    from kk import saved_search_alert_jobs as jobs

    _set_flag(monkeypatch, "on")
    monkeypatch.setenv("SAVED_SEARCH_ALERT_SWEEP_BATCH", "50")
    seller, _ = _user(app)
    token = _admin_token(app, client)
    cars = [_car(app, seller) for _ in range(12)]
    assert _bulk(client, token, cars, {"status": "active"}).status_code == 200
    assert _job_count(app) == 12
    t = max(_job(app, c["id"])["created_at"] for c in cars) + timedelta(minutes=4)
    lock = threading.Lock()
    enqueued: list[int] = []

    def enq(cid, *, expires):
        with lock:
            enqueued.append(cid)

    outs = _threads(app, lambda i: jobs.reconcile(t, enqueue=enq), 4)
    assert sorted(enqueued) == sorted(c["id"] for c in cars)  # each job once across 4 sweeps
    assert sum(o["redriven"] for o in outs) == 12


def test_pg_concurrent_task_runs_for_one_car_leave_one_alert_row_per_pair(app, client, broker, pushes, monkeypatch):
    """Fast-path worker + redrive racing on one car: the job lease admits one
    runner and the pair claim backs it up. Committed state is exact; pushes
    are bounded (at-least-once is the contract, but here no crash happens)."""
    import kk.tasks.alert_tasks as at

    _set_flag(monkeypatch, "on")
    _watchers(app, 3)
    seller, _ = _user(app)
    car = _car(app, seller)
    _activate(client, app, car)
    _threads(app, lambda i: at.notify_saved_searches_for_car.run(car["id"]), 4)
    assert _alert_rows(app, car["id"]) == 3 and _notif_count(app) == 3
    assert sorted(pushes.by_search().values()) == [1, 1, 1]
    assert _job(app, car["id"])["outcome"] == "done"


# ---------------------------------------------------------------------------
# Claim-first pair processing under real row/index locking
# ---------------------------------------------------------------------------


def _pair_args(car, w):
    return (car["id"], w["sid"], w["uid"], "S0", w["spub"], {"brand": "toyota"})


def test_pg_same_pair_second_runner_blocks_on_the_claim_then_skips_without_pushing(app, pushes):
    import kk.tasks.alert_tasks as at

    w = _watchers(app, 1)[0]
    seller, _ = _user(app)
    car = _car(app, seller, status="active")
    in_push, release = threading.Event(), threading.Event()

    def hook(token, data):
        in_push.set()
        assert release.wait(WAIT)

    pushes.hook = hook
    a = Runner(app, lambda: at._alert_one_pair(*_pair_args(car, w)))
    a.start()
    assert in_push.wait(WAIT), (a.result, a.error)  # A holds the uncommitted claim, mid-push
    b = Runner(app, lambda: at._alert_one_pair(*_pair_args(car, w)))
    b.start()
    time.sleep(1.5)
    assert b.is_alive(), "B must be blocked on A's uncommitted claim (unique index)"
    assert pushes.sent == []  # nothing sent while A is still mid-push
    release.set()
    a.join(WAIT)
    b.join(WAIT)
    assert (a.error, b.error) == (None, None)
    assert a.result == "sent" and b.result == "lost_race"
    assert len(pushes.sent) == 1  # B did NOT push
    assert _alert_rows(app, car["id"]) == 1 and _notif_count(app) == 1


def test_pg_same_pair_when_the_first_runner_fails_the_second_takes_over_and_pushes(app, pushes):
    import kk.tasks.alert_tasks as at

    w = _watchers(app, 1)[0]
    seller, _ = _user(app)
    car = _car(app, seller, status="active")
    in_push, release = threading.Event(), threading.Event()
    calls = []
    lock = threading.Lock()

    def hook(token, data):
        with lock:
            calls.append(1)
            first = len(calls) == 1
        if first:
            in_push.set()
            assert release.wait(WAIT)
            raise RuntimeError("crash before the push completed")

    pushes.hook = hook
    a = Runner(app, lambda: at._alert_one_pair(*_pair_args(car, w)))
    a.start()
    assert in_push.wait(WAIT)
    b = Runner(app, lambda: at._alert_one_pair(*_pair_args(car, w)))
    b.start()
    time.sleep(1.0)
    assert b.is_alive()
    release.set()
    a.join(WAIT)
    b.join(WAIT)
    assert isinstance(a.error, RuntimeError) and b.error is None
    assert b.result == "sent"  # the rolled-back claim was released; nothing was lost
    assert len(pushes.sent) == 1  # A never completed its push; B's is the only one
    assert _alert_rows(app, car["id"]) == 1 and _notif_count(app) == 1


# ---------------------------------------------------------------------------
# The UNIQUE(car_id) first-publication marker
# ---------------------------------------------------------------------------


def test_pg_concurrent_double_record_yields_one_job_and_no_error(app, monkeypatch):
    from kk import saved_search_alert_jobs as jobs
    from kk.models import db

    _set_flag(monkeypatch, "on")
    seller, _ = _user(app)
    car = _car(app, seller, status="active")

    def record(i):
        out = jobs.record_alert_job(car["id"])
        db.session.commit()
        return out

    res = _threads(app, record, 2)
    assert sorted(res) == [False, True]
    assert _job_count(app) == 1


def test_pg_job_rolls_back_with_the_activating_transaction(app, monkeypatch):
    from kk import saved_search_alert_jobs as jobs
    from kk.models import Car, db

    _set_flag(monkeypatch, "on")
    seller, _ = _user(app)
    car = _car(app, seller)
    with app.app_context():
        c = db.session.get(Car, car["id"])
        c.status = "active"
        assert jobs.record_alert_job(car["id"]) is True
        db.session.rollback()
    assert _job_count(app) == 0 and _state(app, car["id"]) == ("pending", True)


def test_pg_missing_table_degrades_without_poisoning_the_activation(app, client, broker, monkeypatch):
    """Code deployed before the migration: the job insert fails inside its
    SAVEPOINT; PostgreSQL would abort the whole transaction without it."""
    from kk.models import SavedSearchAlertJob, db

    _set_flag(monkeypatch, "on")
    seller, _ = _user(app)
    car = _car(app, seller)
    token = _admin_token(app, client)
    with app.app_context():
        SavedSearchAlertJob.__table__.drop(db.engine)
    try:
        r = _patch(client, token, car, {"status": "active"})
        assert r.status_code == 200, r.data
        assert _state(app, car["id"]) == ("active", True)
        assert broker.car_ids == [car["id"]]  # post-commit fast path still dispatched
    finally:
        with app.app_context():
            SavedSearchAlertJob.__table__.create(db.engine)
    assert _job_count(app) == 0


def test_pg_deleting_the_car_cascades_to_its_job(app, client, broker, monkeypatch):
    from sqlalchemy import text

    from kk.models import db

    _set_flag(monkeypatch, "on")
    seller, _ = _user(app)
    car = _car(app, seller, photos=0)
    _activate(client, app, car)
    assert _job(app, car["id"]) is not None
    with app.app_context():
        db.session.execute(text("DELETE FROM car WHERE id = :i"), {"i": car["id"]})
        db.session.commit()
    assert _job(app, car["id"]) is None


# ---------------------------------------------------------------------------
# Migration: full chain on a throw-away database
# ---------------------------------------------------------------------------


def test_single_alembic_head_is_stacked_on_the_f04_revision():
    from alembic.config import Config
    from alembic.script import ScriptDirectory

    cfg = Config(str(_REPO_ROOT / "migrations" / "alembic.ini"))
    cfg.set_main_option("script_location", str(_REPO_ROOT / "migrations"))
    script = ScriptDirectory.from_config(cfg)
    assert script.get_heads() == [TIP]
    assert script.get_revision(TIP).down_revision == HEAD
    assert script.get_revision(HEAD).down_revision == PREV_HEAD


def _flask_db(url_str, *args):
    env = os.environ.copy()
    env.update(
        {
            "DATABASE_URL": url_str,
            "FLASK_APP": "kk.wsgi:app",
            "APP_ENV": "testing",
            "AUTO_MIGRATE": "0",
            "SMS_PROVIDER": "console",
            "SECRET_KEY": "f04-mig-secret",
            "JWT_SECRET_KEY": "f04-mig-jwt-secret",
            "UPLOAD_FOLDER": tempfile.gettempdir(),
        }
    )
    env.pop("DB_PATH", None)
    proc = subprocess.run(
        [sys.executable, "-m", "flask", "db", *args],
        cwd=str(_REPO_ROOT),
        env=env,
        capture_output=True,
        text=True,
        timeout=900,
    )
    assert proc.returncode == 0, f"flask db {' '.join(args)} failed:\n{proc.stdout}\n{proc.stderr}"
    return proc


def test_migration_up_down_up_on_a_disposable_database():
    import psycopg
    from sqlalchemy.engine import make_url

    url = make_url(PG_URL).set(drivername="postgresql")
    _require_disposable(url)
    name = f"{url.database}_mig"
    _recreate(url, name)
    target = url.set(database=name)
    dsn = target.render_as_string(hide_password=False)

    def q(sql, *params):
        with psycopg.connect(dsn, autocommit=True) as c:
            return c.execute(sql, params).fetchall()

    def table_exists():
        return q("select to_regclass('public.saved_search_alert_job') is not null")[0][0]

    try:
        _flask_db(dsn, "upgrade")
        assert q("select version_num from alembic_version") == [(TIP,)]
        assert table_exists()
        cols = {r[0]: (r[1], r[2]) for r in q(
            "select column_name, is_nullable, data_type from information_schema.columns "
            "where table_name = 'saved_search_alert_job'"
        )}
        assert cols["car_id"][0] == "NO" and cols["created_at"][0] == "NO" and cols["attempts"][0] == "NO"
        for nullable in ("claimed_at", "next_run_at", "finished_at", "outcome", "last_error"):
            assert cols[nullable][0] == "YES", nullable
        assert q(
            "select count(*) from pg_constraint where conname = 'uq_saved_search_alert_job_car' and contype = 'u'"
        ) == [(1,)]
        # FK to car, ON DELETE CASCADE
        assert q(
            "select confdeltype from pg_constraint where conrelid = 'saved_search_alert_job'::regclass "
            "and contype = 'f'"
        ) == [("c",)]
        assert q(
            "select count(*) from pg_indexes where indexname = 'ix_saved_search_alert_job_pending'"
        ) == [(1,)]
        cars_before = q("select count(*) from car")[0][0]

        _flask_db(dsn, "upgrade")  # idempotent at head
        assert q("select version_num from alembic_version") == [(TIP,)]

        _flask_db(dsn, "downgrade", PREV_HEAD)
        assert q("select version_num from alembic_version") == [(PREV_HEAD,)]
        assert not table_exists()
        assert q("select to_regclass('public.car') is not null") == [(True,)]  # only the new table went
        assert q("select count(*) from car")[0][0] == cars_before

        _flask_db(dsn, "upgrade")
        assert q("select version_num from alembic_version") == [(TIP,)]
        assert table_exists()
    finally:
        with psycopg.connect(_admin_dsn(url), autocommit=True) as c:
            c.execute(f'DROP DATABASE IF EXISTS "{name}" WITH (FORCE)')
