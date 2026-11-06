"""F-04: failed / expired alert jobs are observable and recoverable.

Reuses the app/builders of ``test_f04_durable_alert_jobs.py``. Nothing here
claims exactly-once delivery: external push stays at-least-once.
"""

from __future__ import annotations

import io
import json
import logging
from datetime import timedelta

import pytest

from kk.tests.test_f04_durable_alert_jobs import (  # noqa: F401  (fixtures + builders)
    FLAG,
    Broker,
    Pushes,
    _car,
    _job,
    _process,
    _reconcile,
    _reset_alert_state,
    _search,
    _set_flag,
    _user,
    _watchers,
    app,
    app_ctx,
    broker,
    client,
    isolate,
    pushes,
)


def _owed_car(app, monkeypatch, watchers=2, *, age=timedelta(minutes=10)):
    """An active public car with a recorded job and ``watchers`` matching
    saved searches; returns (car, watchers)."""
    from kk import saved_search_alert_jobs as jobs
    from kk.models import SavedSearchAlertJob, db
    from kk.time_utils import utcnow

    _set_flag(monkeypatch, "on")
    seller, _ = _user(app)
    car = _car(app, seller, status="active")
    ws = _watchers(app, watchers)
    with app.app_context():
        assert jobs.record_alert_job(car["id"]) is True
        db.session.commit()
        SavedSearchAlertJob.query.filter_by(car_id=car["id"]).update({"created_at": utcnow() - age})
        db.session.commit()
    return car, ws


def _set_job(app, car_id, **values):
    from kk.models import SavedSearchAlertJob, db

    with app.app_context():
        SavedSearchAlertJob.query.filter_by(car_id=car_id).update(values)
        db.session.commit()


def _requeue(app, **kw):
    from kk.alert_jobs_cli import requeue_terminal_jobs

    if kw.get("apply"):
        kw.setdefault("reason", "unit test")
    with app.app_context():
        return requeue_terminal_jobs(**kw)


def _stats(app):
    from kk import saved_search_alert_jobs as jobs

    with app.app_context():
        return jobs.job_stats()


def test_retry_exhaustion_is_logged_counted_and_recoverable(app, broker, pushes, monkeypatch, caplog):
    from kk.time_utils import utcnow

    car, ws = _owed_car(app, monkeypatch, watchers=2)
    _set_job(app, car["id"], attempts=5)

    caplog.set_level(logging.ERROR, logger="kk.saved_search_alert_jobs")
    stats = _reconcile(app, lambda *a, **k: None)
    assert stats["failed"] == 1
    assert any("FAILED (attempts exhausted)" in r.getMessage() and str(car["id"]) in r.getMessage() for r in caplog.records)
    assert _job(app, car["id"])["outcome"] == "failed"
    assert _stats(app)["failed"] == 1

    # A terminal job is NOT revived by the sweep by itself ...
    sweep_calls = []
    _reconcile(app, lambda cid, **k: sweep_calls.append(cid), now=utcnow() + timedelta(hours=1))
    assert sweep_calls == []

    # ... dry run (the default) changes nothing ...
    dry = _requeue(app)
    assert dry["candidates"] == 1 and dry["requeued"] == 0 and dry["applied"] is False
    assert _job(app, car["id"])["outcome"] == "failed"

    # ... --apply restarts it with a fresh budget and window.
    done = _requeue(app, apply=True)
    assert done["requeued"] == 1 and done["mode"] == "on"
    j = _job(app, car["id"])
    assert (j["outcome"], j["finished_at"], j["attempts"], j["claimed_at"], j["next_run_at"]) == (None, None, 0, None, None)

    # The sweep redrives it (after the normal grace) and the alerts are delivered.
    later = utcnow() + timedelta(minutes=5)
    redriven = []
    s2 = _reconcile(app, lambda cid, **k: redriven.append(cid), now=later)
    assert s2["redriven"] == 1 and redriven == [car["id"]]
    _process(app, car["id"])
    assert sorted(pushes.by_search().values()) == [1, 1]
    assert _job(app, car["id"])["outcome"] == "done"

    # done jobs are never requeued.
    again = _requeue(app, apply=True)
    assert again["candidates"] == 0 and again["requeued"] == 0


def test_expired_job_is_logged_counted_and_recoverable(app, broker, pushes, monkeypatch, caplog):
    from kk.time_utils import utcnow

    car, ws = _owed_car(app, monkeypatch, watchers=1, age=timedelta(hours=80))
    caplog.set_level(logging.WARNING, logger="kk.saved_search_alert_jobs")
    calls = []
    stats = _reconcile(app, lambda cid, **k: calls.append(cid))
    assert stats["expired"] == 1 and calls == []
    assert any("EXPIRED unsent" in r.getMessage() and str(car["id"]) in r.getMessage() for r in caplog.records)
    assert _stats(app)["expired"] == 1
    assert pushes.sent == []  # never delivered late by itself

    out = _requeue(app, outcomes=("expired",), apply=True)
    assert out["requeued"] == 1
    # The window was restarted: the very next sweep must NOT re-expire it.
    later = utcnow() + timedelta(minutes=5)
    s2 = _reconcile(app, lambda cid, **k: calls.append(cid), now=later)
    assert s2["expired"] == 0 and s2["redriven"] == 1 and calls == [car["id"]]
    _process(app, car["id"])
    assert len(pushes.sent) == 1
    assert _job(app, car["id"])["outcome"] == "done"


def test_requeue_is_scoped_idempotent_and_refuses_bad_input(app, monkeypatch):
    car1, _ = _owed_car(app, monkeypatch, watchers=0)
    car2, _ = _owed_car(app, monkeypatch, watchers=0)
    car3, _ = _owed_car(app, monkeypatch, watchers=0)  # stays pending
    from kk.time_utils import utcnow

    _set_job(app, car1["id"], outcome="failed", finished_at=utcnow(), attempts=5)
    _set_job(app, car2["id"], outcome="expired", finished_at=utcnow())

    only1 = _requeue(app, car_ids=[car1["id"]], apply=True)
    assert only1["requeued"] == 1
    assert _job(app, car1["id"])["outcome"] is None
    assert _job(app, car2["id"])["outcome"] == "expired"  # untouched
    assert _job(app, car3["id"])["attempts"] == 0 and _job(app, car3["id"])["finished_at"] is None

    # Second apply for the same car: nothing left to do (no double requeue).
    assert _requeue(app, car_ids=[car1["id"]], apply=True)["requeued"] == 0

    with pytest.raises(ValueError):
        _requeue(app, outcomes=("done",), apply=True)
    with pytest.raises(ValueError):
        _requeue(app, outcomes=(), apply=True)
    # limit is clamped, not trusted
    assert _requeue(app, limit=10**9)["candidates"] == 1


def test_crashed_worker_lease_expiry_is_redriven_not_hidden(app, monkeypatch):
    """A worker that claimed the job and died (no finish/defer) cannot hide it:
    once the lease lapses the sweep selects it again; attempts are bounded and
    exhaustion ends in a visible ``failed`` state (recoverable above)."""
    from kk import saved_search_alert_jobs as jobs
    from kk.time_utils import utcnow

    car, _ = _owed_car(app, monkeypatch, watchers=0)
    t0 = utcnow()
    with app.app_context():
        claim = jobs.claim_job(car["id"], now=t0)
        assert claim.status == jobs.CLAIMED
        # while the lease is live: not selectable, not claimable by a 2nd worker
        assert jobs.select_due(t0 + timedelta(seconds=60), 10) == []
        assert jobs.claim_job(car["id"], now=t0 + timedelta(seconds=60)).status == jobs.NOT_OWNER
        # lease lapsed (default 900 s): selectable again
        later = t0 + timedelta(seconds=jobs.lease_seconds() + 5)
        assert [c for _j, c in jobs.select_due(later, 10)] == [car["id"]]

    # Burn the remaining attempts through crashes: ends 'failed', never silent.
    _set_job(app, car["id"], attempts=jobs.max_attempts(), claimed_at=t0)
    stats = _reconcile(app, lambda *a, **k: None, now=t0 + timedelta(seconds=jobs.lease_seconds() + 5))
    assert stats["failed"] == 1
    assert _job(app, car["id"])["outcome"] == "failed"


def test_cli_stats_and_requeue_default_to_dry_run(app, monkeypatch):
    from kk.alert_jobs_cli import main
    from kk.time_utils import utcnow

    car, _ = _owed_car(app, monkeypatch, watchers=0)
    _set_job(app, car["id"], outcome="failed", finished_at=utcnow(), attempts=5)

    buf = io.StringIO()
    assert main(["stats"], app=app, out=buf) == 0
    s = json.loads(buf.getvalue())
    assert s["failed"] == 1 and s["mode"] == "on"

    buf = io.StringIO()
    assert main(["requeue"], app=app, out=buf) == 0
    r = json.loads(buf.getvalue())
    assert r["applied"] is False and r["candidates"] == 1 and r["requeued"] == 0
    assert _job(app, car["id"])["outcome"] == "failed"

    buf = io.StringIO()
    # --apply without --reason is refused (exit 2) and writes nothing
    buf = io.StringIO()
    assert main(["requeue", "--apply"], app=app, out=buf) == 2
    assert "reason" in json.loads(buf.getvalue())["error"]
    assert _job(app, car["id"])["outcome"] == "failed"

    buf = io.StringIO()
    argv = ["requeue", "--outcome", "failed", "--car-id", str(car["id"]), "--apply", "--reason", "cli test"]
    assert main(argv, app=app, out=buf) == 0
    assert json.loads(buf.getvalue())["requeued"] == 1
    assert _job(app, car["id"])["outcome"] is None


def _snapshot(app):
    from kk.models import SavedSearchAlertJob

    with app.app_context():
        return sorted(
            (j.id, j.car_id, j.outcome, j.attempts, j.created_at, j.finished_at, j.last_error)
            for j in SavedSearchAlertJob.query.all()
        )


def test_stats_and_dry_run_are_read_only(app, monkeypatch):
    from kk.alert_jobs_cli import main
    from kk.time_utils import utcnow

    car, _ = _owed_car(app, monkeypatch, watchers=0)
    car2, _ = _owed_car(app, monkeypatch, watchers=0)
    _set_job(app, car["id"], outcome="failed", finished_at=utcnow(), attempts=5)
    before = _snapshot(app)
    buf = io.StringIO()
    assert main(["stats"], app=app, out=buf) == 0
    assert main(["requeue"], app=app, out=buf) == 0
    assert main(["requeue", "--outcome", "expired", "--car-id", str(car["id"])], app=app, out=buf) == 0
    assert _snapshot(app) == before


def test_apply_is_refused_while_the_flag_is_off_and_without_a_reason(app, monkeypatch):
    from kk.alert_jobs_cli import RequeueRefused, requeue_terminal_jobs
    from kk.time_utils import utcnow

    car, _ = _owed_car(app, monkeypatch, watchers=0)
    _set_job(app, car["id"], outcome="failed", finished_at=utcnow(), attempts=5)
    before = _snapshot(app)
    with app.app_context():
        with pytest.raises(RequeueRefused):
            requeue_terminal_jobs(apply=True)  # no reason
        with pytest.raises(RequeueRefused):
            requeue_terminal_jobs(apply=True, reason="   ")
    _set_flag(monkeypatch, "off")
    with app.app_context():
        with pytest.raises(RequeueRefused):
            requeue_terminal_jobs(apply=True, reason="flag is off")
        assert requeue_terminal_jobs()["candidates"] == 1  # dry run still works
    assert _snapshot(app) == before


def test_requeue_is_audited_per_job_and_never_creates_or_duplicates_jobs(app, monkeypatch, caplog):
    from kk.models import SavedSearchAlertJob
    from kk.time_utils import utcnow

    car1, _ = _owed_car(app, monkeypatch, watchers=0)
    car2, _ = _owed_car(app, monkeypatch, watchers=0)
    _set_job(app, car1["id"], outcome="failed", finished_at=utcnow(), attempts=5)
    _set_job(app, car2["id"], outcome="expired", finished_at=utcnow(), attempts=2)
    with app.app_context():
        n_before = SavedSearchAlertJob.query.count()

    caplog.set_level(logging.WARNING, logger="kk.alert_jobs_cli")
    first = _requeue(app, apply=True, reason="FCM outage", operator="alice")
    assert first["requeued"] == 2
    audit = [r.getMessage() for r in caplog.records if "AUDIT" in r.getMessage()]
    assert len(audit) == 2  # one explicit line per requeued job
    joined = "\n".join(audit)
    for needle in (f"car_id={car1['id']}", "was=failed", "attempts=5", f"car_id={car2['id']}", "was=expired",
                   "attempts=2", "operator=alice", "FCM outage"):
        assert needle in joined
    marker = _job(app, car1["id"])["last_error"]
    assert marker.startswith("requeued ") and "by alice" in marker and "was failed" in marker

    # Repeating it (also racing it) can never add or duplicate a job row.
    for _ in range(3):
        assert _requeue(app, apply=True, reason="again")["requeued"] == 0
    with app.app_context():
        assert SavedSearchAlertJob.query.count() == n_before
        assert SavedSearchAlertJob.query.filter_by(car_id=car1["id"]).count() == 1
    assert len([r for r in caplog.records if "AUDIT" in r.getMessage()]) == 2  # no phantom audit lines


def test_requeued_job_still_respects_visibility_eligibility_and_flag(app, broker, pushes, monkeypatch):
    """Manual requeue bypasses nothing: hidden listing -> nothing sent and the job stays owed (no attempt
    burned); inactive / notify-off / seller's own searches are never alerted; record mode only counts."""
    from kk.models import Car, SavedSearch, User, db
    from kk.time_utils import utcnow

    car, ws = _owed_car(app, monkeypatch, watchers=3)
    # ws[0]: eligible; ws[1]: account deactivated; ws[2]: notifications turned off.
    own_search_uid = car["uid"]
    _search(app, own_search_uid, name="own")  # seller's own search must not be alerted
    with app.app_context():
        User.query.filter_by(id=ws[1]["uid"]).update({"is_active": False})
        SavedSearch.query.filter_by(id=ws[2]["sid"]).update({"notify": False})
        db.session.commit()
    _set_job(app, car["id"], outcome="failed", finished_at=utcnow(), attempts=5)
    assert _requeue(app, apply=True)["requeued"] == 1

    # record mode: the sweep sends/enqueues nothing even though the job is pending again.
    _set_flag(monkeypatch, "record")
    calls = []
    s = _reconcile(app, lambda cid, **k: calls.append(cid), now=utcnow() + timedelta(minutes=5))
    assert calls == [] and s.get("would_redrive") == 1 and pushes.sent == []
    _set_flag(monkeypatch, "on")

    # hidden listing: processed but deferred, nothing pushed, no attempt burned
    with app.app_context():
        Car.query.filter_by(id=car["id"]).update({"status": "hidden", "is_active": False})
        db.session.commit()
    out = _process(app, car["id"])
    assert pushes.sent == [] and out.get("skipped") == "inactive_or_missing"
    j = _job(app, car["id"])
    assert j["outcome"] is None and j["attempts"] == 0  # still owed, no attempt burned
    assert j["next_run_at"] is not None  # re-checked later, not dropped

    # visible again within the (fresh) window -> only the eligible watcher is alerted
    with app.app_context():
        Car.query.filter_by(id=car["id"]).update({"status": "active", "is_active": True})
        db.session.commit()
    _set_job(app, car["id"], claimed_at=None, next_run_at=None)
    _process(app, car["id"])
    assert list(pushes.by_search()) == [ws[0]["spub"]]
    assert len(pushes.sent) == 1
