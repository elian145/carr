"""Automated listing moderation against a REAL PostgreSQL server.

SQLite (the default test database) has no row locks and no real concurrency, so
it cannot prove the claims the engine makes about races. This module runs the
real engine, the real admin API and the real Alembic migration on PostgreSQL
with genuinely concurrent connections:

* duplicate Celery tasks for one listing;
* the seller editing while the AI call is in flight / between decision and apply;
* an administrator approving while automation is mid-flight (and racing it);
* the listing being deleted / purged while it is being moderated or published;
* the kill switch engaged during approval -- and strictly ordered against an
  approval that is already publishing;
* the migration from the production head (data kept, bounded lock wait, the
  tables dropped and re-created on the disposable database).

It is SKIPPED unless ``CARNET_PG_TEST_URL`` is set, and it refuses to run
unless the server is local and ``CARNET_PG_TEST_CONFIRM_DISPOSABLE=1``: the
target database is DROPPED and re-created.

    CARNET_PG_TEST_URL=postgresql://postgres@127.0.0.1:55432/carnet_conc
    CARNET_PG_TEST_CONFIRM_DISPOSABLE=1
    CARNET_PG_TEMPLATE_DB=carnet_prod_head      # optional: clone a production-
                                                # head schema; the app then
                                                # migrates it to the new head
    pytest kk/tests/test_auto_moderation_postgres.py
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

from kk.tests.test_auto_moderation_engine import (  # noqa: E402
    _admin_token,
    _auth,
    _car,
    _car_state,
    _events,
    _live,
    _notifications,
    _revision,
    _runs,
    _trusted_seller,
)

PG_URL = (os.environ.get("CARNET_PG_TEST_URL") or "").strip()
NEW_HEAD = "v0w1x2y3z4a5"
PREV_HEAD = "u9v0w1x2y3z4"

pytestmark = pytest.mark.skipif(not PG_URL, reason="CARNET_PG_TEST_URL not set (PostgreSQL rehearsal only)")


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
    template = (os.environ.get("CARNET_PG_TEMPLATE_DB") or "").strip()
    with psycopg.connect(_admin_dsn(url), autocommit=True) as c:
        c.execute(f'DROP DATABASE IF EXISTS "{name}" WITH (FORCE)')
        c.execute(f'CREATE DATABASE "{name}"' + (f' TEMPLATE "{template}"' if template else ""))

    tmp = tempfile.TemporaryDirectory(prefix="carlist_automod_pg_", ignore_cleanup_errors=True)
    # Test isolation: every variable below is restored when this module's
    # fixture ends. Previously they leaked (DATABASE_URL above all), so every
    # test module collected after this one -- and the `flask db ...`
    # subprocesses some of them spawn -- silently ran against this PostgreSQL
    # server instead of their own SQLite file.
    env = pytest.MonkeyPatch()
    env.setenv("APP_ENV", "testing")
    env.setenv("SMS_PROVIDER", "console")
    env.delenv("LISTING_REQUIRE_APPROVAL", raising=False)
    env.delenv("DB_PATH", raising=False)
    env.setenv("DATABASE_URL", url.render_as_string(hide_password=False))
    env.setenv("UPLOAD_FOLDER", os.path.join(tmp.name, "uploads"))
    env.setenv("R2_PUBLIC_URL", "https://cdn.example.com")
    env.setenv("R2_ACCOUNT_ID", "test-account")
    env.setenv("R2_BUCKET_NAME", "test-bucket")
    env.setenv("R2_ACCESS_KEY_ID", "test-key")
    env.setenv("R2_SECRET_ACCESS_KEY", "test-secret")
    if not template:
        env.setenv("AUTO_MIGRATE", "0")  # empty database: create_all fallback, no migration chain

    from kk.app_factory import create_app

    app, _socketio, *_ = create_app()
    for key in ("R2_PUBLIC_URL", "R2_ACCOUNT_ID", "R2_BUCKET_NAME", "R2_ACCESS_KEY_ID", "R2_SECRET_ACCESS_KEY"):
        app.config[key] = os.environ[key]
    assert app.config["SQLALCHEMY_DATABASE_URI"].startswith("postgresql"), app.config["SQLALCHEMY_DATABASE_URI"]
    app._pg_dsn = url.render_as_string(hide_password=False)

    from kk.models import db

    if not template:
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


@pytest.fixture(autouse=True)
def clean(pg_app, monkeypatch):
    from kk.auto_moderation import ai, config
    from kk.models import AppSetting, db

    for k in (
        "AUTO_MODERATION_DISABLED",
        "AUTO_MODERATION_KILL_SWITCH",
        "AUTO_MODERATION_ALLOW_LIVE",
        "AUTO_MODERATION_ALERT_EMAILS",
        "AUTO_MODERATION_TELEGRAM_BOT_TOKEN",
        "AUTO_MODERATION_TELEGRAM_CHAT_ID",
        "ADMIN_WEB_BASE_URL",
        "LISTING_REQUIRE_APPROVAL",
    ):
        monkeypatch.delenv(k, raising=False)
    monkeypatch.setenv("AUTO_MODERATION_AI_PROVIDER", "stub")
    ai.STUB_RESPONSE = None
    import kk.tasks.moderation_tasks as mt

    monkeypatch.setattr(mt.moderate_listing_task, "apply_async", lambda *a, **k: None)
    monkeypatch.setattr(mt.send_moderation_alert_task, "apply_async", lambda *a, **k: None)
    with pg_app.app_context():
        AppSetting.query.filter_by(key=config.SETTINGS_KEY).delete()
        db.session.commit()
    yield
    ai.STUB_RESPONSE = None


# ---------------------------------------------------------------------------
# Concurrency helpers
# ---------------------------------------------------------------------------

WAIT = 45  # seconds: generous for CI, small enough that a deadlock fails fast


class Gate:
    """Pause a thread at a precise point until the test lets it go."""

    def __init__(self):
        self.reached = threading.Event()
        self.release = threading.Event()

    def hit(self):
        self.reached.set()
        assert self.release.wait(WAIT), "gate never released"

    def wait_reached(self, worker=None):
        if worker is not None:
            # fail fast with the worker's own outcome instead of idling for WAIT
            deadline = time.time() + WAIT
            while not self.reached.is_set() and worker.is_alive() and time.time() < deadline:
                self.reached.wait(0.05)
            assert self.reached.is_set(), (
                f"worker never reached the gate: result={worker.result!r} error={worker.error!r}"
            )
            return
        assert self.reached.wait(WAIT), "worker never reached the gate"


class Worker(threading.Thread):
    """Runs ``fn`` in its own app context / DB connection; captures the result."""

    def __init__(self, app, fn):
        super().__init__(daemon=True)
        self.app, self.fn, self.result, self.error = app, fn, None, None

    def run(self):
        from kk.models import db

        try:
            with self.app.app_context():
                self.result = self.fn()
        except BaseException as exc:  # noqa: BLE001 -- surfaced by finish()
            self.error = exc
        finally:
            with self.app.app_context():
                db.session.remove()

    def finish(self, timeout=WAIT):
        self.join(timeout)
        assert not self.is_alive(), "worker still running: deadlock / hang"
        if self.error is not None:
            raise self.error
        return self.result


def _spawn(app, fn):
    w = Worker(app, fn)
    w.start()
    return w


def _moderate_job(car_id, subject="listing"):
    from kk.tasks.moderation_tasks import moderate_listing_task

    return lambda: moderate_listing_task.run(subject, car_id)


def _ok_ai(urls):
    return {
        "text": {"ok": True, "flags": []},
        "images": [{"index": i, "is_car_photo": True, "flags": []} for i in range(len(urls))],
        "confidence": 0.95,
    }


def _lcar(app, uid, **kw):
    """A listing with its own description: identical text on several of one seller's
    listings is itself a review signal, which would hide the race under test."""
    # Letters only: a random hex token can hold 9+ consecutive digits, which the
    # (correct) phone-number rule reads as contact details and sends to review,
    # randomly hiding the race under test.
    ref = "".join(chr(ord("a") + int(ch, 16) % 26) for ch in uuid.uuid4().hex[:10])
    kw.setdefault("description", f"Well kept, one owner, full service book, ref {ref}.")
    return _car(app, uid, **kw)


def _cars_of_distinct_sellers(app, n):
    """n pending listings, each from its own proven seller: one seller posting
    many listings at once trips the posting-rate rule (correctly) and would
    send them all to review instead of exercising the race."""
    out = []
    for i in range(n):
        uid, _ = _trusted_seller(app)
        out.append(_lcar(app, uid, price=15000 + i * 900, mileage=30000 + i * 9000))
    return out



def _published_runs(app, car_id):
    return [r for r in _runs(app, car_id) if r["outcome"] == "published"]


def _published_events(app, car_id):
    return [e for e in _events(app, car_id) if e == "published"]


# ---------------------------------------------------------------------------
# Environment sanity
# ---------------------------------------------------------------------------


def test_server_is_postgresql_17_and_schema_is_at_the_new_head(app):
    from sqlalchemy import text

    from kk.models import db

    with app.app_context():
        assert db.engine.dialect.name == "postgresql"
        version = db.session.execute(text("show server_version")).scalar()
        assert version.startswith("17."), version
        head = db.session.execute(text("select version_num from alembic_version")).scalar()
        if os.environ.get("CARNET_PG_TEMPLATE_DB"):
            assert head == NEW_HEAD
        for t in ("listing_moderation_run", "listing_moderation_event"):
            assert db.session.execute(text("select to_regclass(:t)"), {"t": t}).scalar() is not None


# ---------------------------------------------------------------------------
# Duplicate Celery tasks
# ---------------------------------------------------------------------------


def test_duplicate_celery_tasks_publish_exactly_once(app, monkeypatch):
    from kk.auto_moderation import ai

    _live(monkeypatch, app)
    uid, _ = _trusted_seller(app)
    c = _car(app, uid)
    calls, lock = [], threading.Lock()

    def slow_ai(title, desc, urls):
        with lock:
            calls.append(1)
        time.sleep(0.6)  # keep the claim open so the duplicates really overlap
        return _ok_ai(urls)

    ai.STUB_RESPONSE = slow_ai
    barrier = threading.Barrier(8)

    def job():
        barrier.wait(WAIT)
        return _moderate_job(c["car_id"])()

    workers = [_spawn(app, job) for _ in range(8)]
    results = [w.finish() for w in workers]
    outcomes = sorted(r["outcome"] for r in results)

    assert outcomes.count("published") == 1, outcomes
    assert set(outcomes) <= {"published", "busy", "done", "backoff"}, outcomes
    assert len(calls) == 1, "the AI was consulted more than once for one decision"
    assert len(_runs(app, c["car_id"])) == 1
    assert len(_published_events(app, c["car_id"])) == 1
    assert _notifications(app, uid) == 1
    assert _car_state(app, c["car_id"])["status"] == "active"


def test_duplicate_tasks_across_many_listings_never_double_publish(app, monkeypatch):
    from kk.auto_moderation import ai

    _live(monkeypatch, app)
    cars = _cars_of_distinct_sellers(app, 4)
    ai.STUB_RESPONSE = lambda title, desc, urls: (time.sleep(0.2), _ok_ai(urls))[1]
    barrier = threading.Barrier(len(cars) * 3)

    def job(cid):
        def run():
            barrier.wait(WAIT)
            return _moderate_job(cid)()

        return run

    workers = [_spawn(app, job(c["car_id"])) for c in cars for _ in range(3)]
    for w in workers:
        w.finish()
    for c in cars:
        assert len(_published_runs(app, c["car_id"])) <= 1
        assert len(_published_events(app, c["car_id"])) <= 1
        assert _notifications(app, c["uid"]) == (1 if _published_runs(app, c["car_id"]) else 0)
    with app.app_context():
        from kk.models import ListingModerationRun

        # one decision row per (listing, content, mode): the unique key held
        keys = [r.subject_key for r in ListingModerationRun.query.filter(
            ListingModerationRun.car_id.in_([c["car_id"] for c in cars])
        )]
        assert len(keys) == len(set(keys)) == len(cars)


# ---------------------------------------------------------------------------
# Seller edits during moderation
# ---------------------------------------------------------------------------


def test_seller_edit_while_ai_runs_never_publishes_stale_content(app, monkeypatch):
    from kk.auto_moderation import ai
    from kk.models import Car, db

    _live(monkeypatch, app)
    uid, _ = _trusted_seller(app)
    c = _car(app, uid)
    gate = Gate()

    def ai_with_gate(title, desc, urls):
        gate.hit()
        return _ok_ai(urls)

    ai.STUB_RESPONSE = ai_with_gate
    w = _spawn(app, _moderate_job(c["car_id"]))
    gate.wait_reached()

    with app.app_context():  # the seller edits on another connection, mid-evaluation
        car = db.session.get(Car, c["car_id"])
        car.description = "western union only, guaranteed profit"
        db.session.commit()
    gate.release.set()
    out = w.finish()

    assert out["outcome"] == "stale", out
    assert _car_state(app, c["car_id"])["status"] == "pending"
    assert _published_runs(app, c["car_id"]) == []
    assert _notifications(app, uid) == 0

    ai.STUB_RESPONSE = None  # the new text is judged on its own merits
    again = _moderate_job(c["car_id"])
    with app.app_context():
        res = again()
    assert res["outcome"] != "published"
    assert _car_state(app, c["car_id"])["status"] == "pending"
    assert "scam_language" in _runs(app, c["car_id"])[-1]["codes"]


def test_seller_edit_between_decision_and_apply_is_stale(app, monkeypatch):
    from kk.auto_moderation import engine
    from kk.models import Car, db

    _live(monkeypatch, app)
    uid, _ = _trusted_seller(app)
    c = _car(app, uid)
    gate = Gate()
    real_apply = engine._apply

    def gated_apply(*a, **k):
        gate.hit()  # decision is durably recorded; apply has not started
        return real_apply(*a, **k)

    monkeypatch.setattr(engine, "_apply", gated_apply)
    w = _spawn(app, _moderate_job(c["car_id"]))
    gate.wait_reached()
    with app.app_context():
        db.session.get(Car, c["car_id"]).price = 1
        db.session.commit()
    gate.release.set()
    out = w.finish()

    assert out["outcome"] == "stale", out
    assert _car_state(app, c["car_id"])["status"] == "pending"
    assert _published_runs(app, c["car_id"]) == []


def test_seller_edit_of_a_pending_revision_during_moderation_is_stale(app, monkeypatch):
    from kk.auto_moderation import ai
    from kk.models import Car, CarRevision, db

    _live(monkeypatch, app)
    uid, _ = _trusted_seller(app)
    c = _car(app, uid, status="active", media="ready")
    rev_id, shadow_id, _pub = _revision(
        app, c["car_id"], description="Updated: new tyres fitted, service done."
    )
    gate = Gate()

    def ai_with_gate(title, desc, urls):
        gate.hit()
        return _ok_ai(urls)

    ai.STUB_RESPONSE = ai_with_gate
    rid = rev_id
    w = _spawn(app, _moderate_job(rid, "revision"))
    gate.wait_reached()
    with app.app_context():
        shadow = db.session.get(Car, shadow_id)
        shadow.description = "wire the deposit to my agent first"
        db.session.commit()
    gate.release.set()
    out = w.finish()

    assert out["outcome"] == "stale", out
    assert _car_state(app, c["car_id"])["description"].startswith("Clean car")  # live version untouched
    with app.app_context():
        assert db.session.get(CarRevision, rev_id).status == "pending"  # kept for review / re-evaluation
    assert _published_runs(app, c["car_id"]) == []


# ---------------------------------------------------------------------------
# Administrator acting during automation
# ---------------------------------------------------------------------------


def test_admin_approval_during_automation_wins_and_no_second_publish(app, client, monkeypatch):
    from kk.auto_moderation import engine

    _live(monkeypatch, app)
    uid, _ = _trusted_seller(app)
    c = _car(app, uid)
    tok = _admin_token(app, client)
    gate = Gate()
    real_apply = engine._apply

    def gated_apply(*a, **k):
        gate.hit()
        return real_apply(*a, **k)

    monkeypatch.setattr(engine, "_apply", gated_apply)
    w = _spawn(app, _moderate_job(c["car_id"]))
    gate.wait_reached()
    r = client.patch(
        f"/api/admin/cars/{c['public_id']}/status",
        json={"is_active": True, "status": "active"},
        headers=_auth(tok),
    )
    assert r.status_code == 200
    gate.release.set()
    out = w.finish()

    assert out["outcome"] == "superseded", out
    assert _published_runs(app, c["car_id"]) == []
    assert _notifications(app, uid) == 1
    assert _car_state(app, c["car_id"])["status"] == "active"


def test_admin_approval_racing_automation_publishes_once(app, client, monkeypatch):
    from kk.auto_moderation import ai

    _live(monkeypatch, app)
    tok = _admin_token(app, client)
    cars = _cars_of_distinct_sellers(app, 6)
    ai.STUB_RESPONSE = lambda title, desc, urls: (time.sleep(0.05), _ok_ai(urls))[1]
    barrier = threading.Barrier(len(cars) * 2)
    statuses = {}

    def admin_job(c):
        def run():
            barrier.wait(WAIT)
            cl = app.test_client()
            statuses[c["car_id"]] = cl.patch(
                f"/api/admin/cars/{c['public_id']}/status",
                json={"is_active": True, "status": "active"},
                headers=_auth(tok),
            ).status_code

        return run

    def auto_job(c):
        def run():
            barrier.wait(WAIT)
            return _moderate_job(c["car_id"])()

        return run

    workers = []
    for c in cars:
        workers += [_spawn(app, auto_job(c)), _spawn(app, admin_job(c))]
    for w in workers:
        w.finish()

    for c in cars:
        assert statuses[c["car_id"]] == 200
        assert _car_state(app, c["car_id"])["status"] == "active"
        assert len(_published_runs(app, c["car_id"])) <= 1
        assert len(_published_events(app, c["car_id"])) <= 1
    # each seller is told exactly once, whoever got there first
    for c in cars:
        assert _notifications(app, c["uid"]) == 1


# ---------------------------------------------------------------------------
# Listing deleted during moderation
# ---------------------------------------------------------------------------


def test_soft_delete_while_ai_runs_is_never_published(app, client, monkeypatch):
    from kk.auto_moderation import ai

    _live(monkeypatch, app)
    uid, _ = _trusted_seller(app)
    c = _car(app, uid)
    tok = _admin_token(app, client)
    gate = Gate()

    def ai_with_gate(title, desc, urls):
        gate.hit()
        return _ok_ai(urls)

    ai.STUB_RESPONSE = ai_with_gate
    w = _spawn(app, _moderate_job(c["car_id"]))
    gate.wait_reached()
    assert client.delete(f"/api/admin/cars/{c['public_id']}", headers=_auth(tok)).status_code == 200
    gate.release.set()
    out = w.finish()

    assert out["outcome"] != "published", out
    state = _car_state(app, c["car_id"])
    assert state["is_active"] is False and state["status"] != "active"
    assert _published_runs(app, c["car_id"]) == []


def test_purge_while_ai_runs_and_between_decision_and_apply_publishes_nothing(app, client, monkeypatch):
    from kk.auto_moderation import ai, engine
    from kk.models import Car, db

    _live(monkeypatch, app)
    uid, _ = _trusted_seller(app)
    sup = _admin_token(app, client, "super_admin")

    # (1) purged while the AI call is in flight
    c1 = _lcar(app, uid, price=15100)
    gate = Gate()

    def ai_with_gate(title, desc, urls):
        gate.hit()
        return _ok_ai(urls)

    ai.STUB_RESPONSE = ai_with_gate
    w = _spawn(app, _moderate_job(c1["car_id"]))
    gate.wait_reached()
    assert client.delete(f"/api/admin/cars/{c1['public_id']}/purge", headers=_auth(sup)).status_code == 200
    gate.release.set()
    out = w.finish()
    assert out["outcome"] != "published", out

    # (2) purged between decision and apply
    ai.STUB_RESPONSE = None
    c2 = _lcar(app, uid, price=15200, mileage=61000)
    gate2 = Gate()
    real_apply = engine._apply

    def gated_apply(*a, **k):
        gate2.hit()
        return real_apply(*a, **k)

    monkeypatch.setattr(engine, "_apply", gated_apply)
    w2 = _spawn(app, _moderate_job(c2["car_id"]))
    gate2.wait_reached()
    assert client.delete(f"/api/admin/cars/{c2['public_id']}/purge", headers=_auth(sup)).status_code == 200
    gate2.release.set()
    out2 = w2.finish()
    assert out2["outcome"] == "superseded", out2

    with app.app_context():
        assert db.session.get(Car, c1["car_id"]) is None and db.session.get(Car, c2["car_id"]) is None
        from kk.models import ListingModerationEvent, ListingModerationRun

        # the decision history survives the purge with the listing link cleared (FK ON DELETE SET NULL)
        runs = ListingModerationRun.query.filter(
            ListingModerationRun.car_public_id.in_([c1["public_id"], c2["public_id"]])
        ).all()
        assert runs and all(r.car_id is None and r.outcome != "published" for r in runs)
        events = ListingModerationEvent.query.filter(
            ListingModerationEvent.car_public_id.in_([c1["public_id"], c2["public_id"]])
        ).all()
        assert events and all(e.car_id is None for e in events)


def test_purge_waits_for_an_in_flight_publish_and_history_survives(app, client, monkeypatch):
    """The publish transaction holds the listing's row lock: a purge cannot
    interleave with it. Whichever commits first, nothing is corrupted and the
    published decision stays on record after the purge."""
    from kk.auto_moderation import engine
    from kk.models import Car, ListingModerationRun, db

    _live(monkeypatch, app)
    uid, _ = _trusted_seller(app)
    c = _lcar(app, uid, price=15300)
    sup = _admin_token(app, client, "super_admin")
    gate = Gate()
    real_publish = engine.publish_subject

    def gated_publish(*a, **k):
        res = real_publish(*a, **k)
        gate.hit()  # publication staged inside the open transaction, row locked
        return res

    monkeypatch.setattr(engine, "publish_subject", gated_publish)
    publisher = _spawn(app, _moderate_job(c["car_id"]))
    gate.wait_reached()

    purge_status = {}

    def purge():
        purge_status["code"] = app.test_client().delete(
            f"/api/admin/cars/{c['public_id']}/purge", headers=_auth(sup)
        ).status_code

    purger = _spawn(app, purge)
    time.sleep(1.5)
    assert purger.is_alive(), "purge did not wait for the in-flight publication"
    gate.release.set()
    out = publisher.finish()
    purger.finish()

    assert out["outcome"] == "published", out
    assert purge_status["code"] == 200
    with app.app_context():
        assert db.session.get(Car, c["car_id"]) is None
        run = ListingModerationRun.query.filter_by(car_public_id=c["public_id"]).one()
        assert run.outcome == "published" and run.car_id is None


# ---------------------------------------------------------------------------
# Kill switch during approval
# ---------------------------------------------------------------------------


def test_kill_switch_engaged_between_decision_and_apply_blocks_publication(app, client, monkeypatch):
    from kk.auto_moderation import engine

    _live(monkeypatch, app)
    uid, _ = _trusted_seller(app)
    c = _car(app, uid)
    sup = _admin_token(app, client, "super_admin")
    gate = Gate()
    real_apply = engine._apply

    def gated_apply(*a, **k):
        gate.hit()
        return real_apply(*a, **k)

    monkeypatch.setattr(engine, "_apply", gated_apply)
    w = _spawn(app, _moderate_job(c["car_id"]))
    gate.wait_reached()
    r = client.post("/api/admin/auto-moderation/kill-switch", json={"enabled": True, "reason": "test"}, headers=_auth(sup))
    assert r.status_code == 200
    gate.release.set()
    out = w.finish()

    assert out["outcome"] == "blocked_killswitch", out
    assert _car_state(app, c["car_id"])["status"] == "pending"
    assert _published_runs(app, c["car_id"]) == []
    assert _notifications(app, uid) == 0


def test_kill_switch_during_many_in_flight_evaluations_publishes_none(app, client, monkeypatch):
    from kk.auto_moderation import ai

    _live(monkeypatch, app)
    sup = _admin_token(app, client, "super_admin")
    cars = _cars_of_distinct_sellers(app, 6)
    in_ai, release, lock = [], threading.Event(), threading.Lock()

    def ai_hold(title, desc, urls):
        with lock:
            in_ai.append(1)
        assert release.wait(WAIT)
        return _ok_ai(urls)

    ai.STUB_RESPONSE = ai_hold
    workers = [_spawn(app, _moderate_job(c["car_id"])) for c in cars]
    deadline = time.time() + WAIT
    while len(in_ai) < len(cars) and time.time() < deadline:
        time.sleep(0.05)
    assert len(in_ai) == len(cars)
    assert client.post(
        "/api/admin/auto-moderation/kill-switch", json={"enabled": True, "reason": "test"}, headers=_auth(sup)
    ).status_code == 200
    release.set()
    outs = [w.finish() for w in workers]

    assert all(o["outcome"] == "blocked_killswitch" for o in outs), outs
    for c in cars:
        assert _car_state(app, c["car_id"])["status"] == "pending"
        assert _published_runs(app, c["car_id"]) == []


def test_kill_switch_is_strictly_ordered_against_an_in_flight_publication(app, monkeypatch):
    """An approval that has already passed the kill-switch check and is
    publishing makes the switch WAIT (FOR SHARE vs FOR UPDATE on the settings
    row); once the switch commits, the very next approval is blocked. There is
    no interleaving in which the switch is 'on' and an approval then commits
    unaware of it."""
    from kk.auto_moderation import config, engine

    _live(monkeypatch, app)
    uid, _ = _trusted_seller(app)
    first = _lcar(app, uid, price=15400)
    second = _lcar(app, uid, price=15500, mileage=71000)
    gate = Gate()
    real_publish = engine.publish_subject
    monkeypatch.setattr(
        engine, "publish_subject",
        lambda *a, **k: (lambda r: (gate.hit(), r)[1])(real_publish(*a, **k)),
    )
    publisher = _spawn(app, _moderate_job(first["car_id"]))
    gate.wait_reached(publisher)

    switcher = _spawn(app, lambda: config.set_kill_switch(True, actor="tester", reason="rehearsal"))
    time.sleep(1.5)
    assert switcher.is_alive(), "the kill switch committed while an approval was mid-publication"
    with app.app_context():
        assert not config.kill_switch_active(), "switch visible before it committed"

    gate.release.set()
    out = publisher.finish()
    switcher.finish()
    assert out["outcome"] == "published", out  # it passed the check before the switch existed
    with app.app_context():
        assert config.kill_switch_active()

    monkeypatch.setattr(engine, "publish_subject", real_publish)
    blocked = _spawn(app, _moderate_job(second["car_id"])).finish()
    # with the switch on the engine runs in shadow: it may decide, never publish
    assert blocked["outcome"] != "published" and blocked["outcome"] in (
        "shadow_would_approve", "blocked_killswitch", "skipped_off"
    ), blocked
    assert _car_state(app, second["car_id"])["status"] == "pending"
    assert _published_runs(app, second["car_id"]) == []


# ---------------------------------------------------------------------------
# Migration (disposable database only)
# ---------------------------------------------------------------------------


def _table_exists(app, name):
    from sqlalchemy import text

    from kk.models import db

    with app.app_context():
        return db.session.execute(text("select to_regclass(:t)"), {"t": name}).scalar() is not None


def _alembic_version(app):
    from sqlalchemy import text

    from kk.models import db

    with app.app_context():
        v = db.session.execute(text("select version_num from alembic_version")).scalar()
        db.session.rollback()
        return v


def test_migration_waits_a_bounded_time_for_locks_instead_of_stalling_writers(app):
    """A long write transaction on ``car`` would make an un-bounded
    CREATE TABLE ... FOREIGN KEY wait (and queue every later write behind it).
    The migration sets a 5 s lock_timeout: it fails fast and cleanly, stalls
    writers for at most that long, and can simply be re-run."""
    import psycopg
    from flask_migrate import downgrade, upgrade

    from kk.models import Car, db

    if os.environ.get("CARNET_PG_TEMPLATE_DB") is None:
        pytest.skip("needs the production-head template to start from the previous revision")
    uid, _ = _trusted_seller(app)
    victim = _lcar(app, uid, price=15600)

    with app.app_context():
        downgrade(revision=PREV_HEAD)
    assert _alembic_version(app) == PREV_HEAD
    assert not _table_exists(app, "listing_moderation_run")

    blocker = psycopg.connect(app._pg_dsn, autocommit=False)
    try:
        blocker.execute("update car set updated_at = updated_at where id = %s", (victim["car_id"],))  # open write txn
        started = time.time()

        def migrate():
            upgrade()

        mig = _spawn(app, migrate)
        time.sleep(1.0)
        late_write = {}

        def writer():
            t0 = time.time()
            db.session.execute(
                db.text("update car set updated_at = updated_at where id = :i"), {"i": victim["car_id"]}
            )
            db.session.commit()
            late_write["seconds"] = time.time() - t0

        w = _spawn(app, writer)
        mig.join(WAIT)
        assert not mig.is_alive()
        assert mig.error is not None, "migration should fail fast while the lock is held"
        assert "lock timeout" in str(mig.error).lower() or "lock_timeout" in str(mig.error).lower(), mig.error
        elapsed = time.time() - started
        assert 4.0 <= elapsed <= 15.0, elapsed
        assert _alembic_version(app) == PREV_HEAD  # nothing half-applied
        assert not _table_exists(app, "listing_moderation_run")
        blocker.rollback()  # the blocking transaction ends
        w.join(WAIT)
        assert not w.is_alive()
    finally:
        blocker.close()

    # re-run is clean now that the lock is free
    with app.app_context():
        upgrade()
    assert _alembic_version(app) == NEW_HEAD
    assert _table_exists(app, "listing_moderation_run") and _table_exists(app, "listing_moderation_event")
    assert _car_state(app, victim["car_id"])["status"] == "pending"
    with app.app_context():
        assert db.session.get(Car, victim["car_id"]) is not None


def test_migration_downgrade_and_reupgrade_keeps_listings_on_the_disposable_db(app, monkeypatch):
    """Rehearsal only (never production): with moderation rows present, a
    downgrade drops just the two new tables; every listing survives; the
    upgrade then re-creates them."""
    from flask_migrate import downgrade, upgrade

    from kk.models import Car, db

    _live(monkeypatch, app)
    uid, _ = _trusted_seller(app)
    c = _lcar(app, uid, price=15700, mileage=33000)
    with app.app_context():
        out = _moderate_job(c["car_id"])()
    assert out["outcome"] == "published"
    assert _runs(app, c["car_id"])

    with app.app_context():
        downgrade(revision=PREV_HEAD)
    assert not _table_exists(app, "listing_moderation_run") and not _table_exists(app, "listing_moderation_event")
    with app.app_context():
        assert db.session.get(Car, c["car_id"]).status == "active"  # listings untouched

    with app.app_context():
        upgrade()
    assert _alembic_version(app) == NEW_HEAD
    assert _table_exists(app, "listing_moderation_run")
    assert _runs(app, c["car_id"]) == []  # history is gone only because we dropped it on a throw-away DB
