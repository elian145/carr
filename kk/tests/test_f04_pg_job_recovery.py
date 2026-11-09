"""F-04 operator recovery CLI against a REAL (disposable, local) PostgreSQL.

Runs only with ``CARNET_PG_TEST_URL`` + ``CARNET_PG_TEST_CONFIRM_DISPOSABLE=1``
(same guard as ``test_f04_pg_durable_alerts.py``, whose database/app fixtures
are reused). Covers the CLI's actual database operations: read-only ``stats``
and dry run, the guarded per-row UPDATE under real concurrent appliers, no
INSERT / no duplicate job, ``done`` rows untouched, audit marker persisted.
External push delivery remains at-least-once (not exactly-once); nothing here
sends a push.
"""

from __future__ import annotations

import io
import json
import threading
from datetime import timedelta

import pytest

from kk.tests.test_f04_pg_durable_alerts import (  # noqa: F401  (fixtures + builders)
    PG_URL,
    _car,
    _job,
    _job_count,
    _set_flag,
    _user,
    app,
    broker,
    client,
    isolate,
    pg_app,
)

pytestmark = pytest.mark.skipif(not PG_URL, reason="CARNET_PG_TEST_URL not set (PostgreSQL rehearsal only)")


def _make_jobs(app, monkeypatch, n):
    from kk import saved_search_alert_jobs as jobs
    from kk.models import db

    _set_flag(monkeypatch, "on")
    seller, _ = _user(app)
    cars = [_car(app, seller, status="active") for _ in range(n)]
    with app.app_context():
        for c in cars:
            assert jobs.record_alert_job(c["id"]) is True
        db.session.commit()
    return cars


def _set_state(app, car_id, **values):
    from kk.models import SavedSearchAlertJob, db

    with app.app_context():
        SavedSearchAlertJob.query.filter_by(car_id=car_id).update(values)
        db.session.commit()


def _rows(app):
    from kk.models import SavedSearchAlertJob

    with app.app_context():
        return sorted(
            (j.car_id, j.outcome, j.attempts, j.created_at, j.finished_at, j.last_error)
            for j in SavedSearchAlertJob.query.all()
        )


def test_pg_cli_stats_and_dry_run_write_nothing(app, monkeypatch):
    from kk.alert_jobs_cli import main
    from kk.time_utils import utcnow

    cars = _make_jobs(app, monkeypatch, 3)
    _set_state(app, cars[0]["id"], outcome="failed", finished_at=utcnow(), attempts=5)
    _set_state(app, cars[1]["id"], outcome="expired", finished_at=utcnow())
    before = _rows(app)
    buf = io.StringIO()
    assert main(["stats"], app=app, out=buf) == 0
    stats = json.loads(buf.getvalue())
    assert (stats["failed"], stats["expired"], stats["pending"]) == (1, 1, 1)
    buf = io.StringIO()
    assert main(["requeue"], app=app, out=buf) == 0
    dry = json.loads(buf.getvalue())
    assert dry["applied"] is False and dry["candidates"] == 2 and dry["requeued"] == 0
    assert _rows(app) == before


def test_pg_concurrent_applies_requeue_each_job_once_and_never_insert(app, monkeypatch):
    from kk.alert_jobs_cli import requeue_terminal_jobs
    from kk.time_utils import utcnow

    cars = _make_jobs(app, monkeypatch, 8)
    for c in cars[:6]:
        _set_state(app, c["id"], outcome="failed", finished_at=utcnow(), attempts=5)
    _set_state(app, cars[6]["id"], outcome="done", finished_at=utcnow())  # must never be touched
    done_before = _job(app, cars[6]["id"])
    n_rows = _job_count(app)

    results: list[int] = []
    errors: list[BaseException] = []
    barrier = threading.Barrier(4)

    def worker():
        try:
            with app.app_context():
                barrier.wait(timeout=30)
                out = requeue_terminal_jobs(apply=True, reason="pg concurrency", operator="tester")
                results.append(out["requeued"])
        except BaseException as exc:  # noqa: BLE001 - surfaced below
            errors.append(exc)

    threads = [threading.Thread(target=worker, daemon=True) for _ in range(4)]
    for t in threads:
        t.start()
    for t in threads:
        t.join(timeout=90)
    assert not errors, errors
    assert sum(results) == 6  # every failed job requeued exactly once across the 4 racers
    assert _job_count(app) == n_rows  # UPDATE only: no insert, no duplicate job for any listing
    for c in cars[:6]:
        j = _job(app, c["id"])
        assert (j["outcome"], j["finished_at"], j["attempts"]) == (None, None, 0)
        assert j["last_error"].startswith("requeued ") and "by tester" in j["last_error"]
        assert j["created_at"] > utcnow() - timedelta(minutes=5)  # fresh window
    assert _job(app, cars[6]["id"]) == done_before  # done untouched
    assert _job(app, cars[7]["id"])["outcome"] is None  # pending untouched
    # A repeat is a no-op.
    with app.app_context():
        assert requeue_terminal_jobs(apply=True, reason="again")["requeued"] == 0
    assert _job_count(app) == n_rows


def test_pg_cli_apply_needs_reason_and_flag(app, monkeypatch):
    from kk.alert_jobs_cli import main
    from kk.time_utils import utcnow

    cars = _make_jobs(app, monkeypatch, 1)
    _set_state(app, cars[0]["id"], outcome="expired", finished_at=utcnow())
    before = _rows(app)
    buf = io.StringIO()
    assert main(["requeue", "--apply"], app=app, out=buf) == 2  # no reason
    _set_flag(monkeypatch, "off")
    assert main(["requeue", "--apply", "--reason", "x"], app=app, out=io.StringIO()) == 2  # flag off
    assert _rows(app) == before
    _set_flag(monkeypatch, "on")
    buf = io.StringIO()
    assert main(["requeue", "--apply", "--reason", "pg smoke"], app=app, out=buf) == 0
    assert json.loads(buf.getvalue())["requeued"] == 1
