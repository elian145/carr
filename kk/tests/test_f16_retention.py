"""F-16: retention cleanup is opt-in and never touches protected data."""

from __future__ import annotations

import os
import tempfile
import uuid
from datetime import timedelta

import pytest

from kk.tests.test_l01_report_audit_log import _make_user

_RETENTION_VARS = (
    "RETENTION_TOKEN_BLACKLIST_PURGE",
    "RETENTION_USER_ACTION_DAYS",
    "RETENTION_READ_NOTIFICATION_DAYS",
)


@pytest.fixture(scope="module")
def ctx():
    tmp = tempfile.TemporaryDirectory(prefix="carlist_f16_", ignore_cleanup_errors=True)
    os.environ["APP_ENV"] = "testing"
    os.environ["SMS_PROVIDER"] = "console"
    os.environ["DB_PATH"] = os.path.join(tmp.name, "f16.db")

    from kk.app_factory import create_app

    app, _socketio, *_ = create_app()
    from kk.models import db

    with app.app_context():
        db.drop_all()
        db.create_all()
    yield app, db
    with app.app_context():
        db.session.remove()
        db.engine.dispose()
    tmp.cleanup()


@pytest.fixture(autouse=True)
def _clean_env(monkeypatch):
    for k in _RETENTION_VARS:
        monkeypatch.delenv(k, raising=False)


def _seed(app, db):
    from kk.models import AdminAuditLog, Notification, TokenBlacklist, UserAction
    from kk.time_utils import utcnow

    uid, _p, _n = _make_user(app, db)
    now = utcnow()
    old = now - timedelta(days=400)
    with app.app_context():
        db.session.add_all([
            TokenBlacklist(jti=uuid.uuid4().hex[:36], token_type="refresh", user_id=uid,
                           expires_at=now - timedelta(days=2)),       # expired -> purgeable
            TokenBlacklist(jti=uuid.uuid4().hex[:36], token_type="refresh", user_id=uid,
                           expires_at=now + timedelta(days=2)),       # live -> keep
            TokenBlacklist(jti=uuid.uuid4().hex[:36], token_type="access", user_id=uid,
                           expires_at=now - timedelta(minutes=5)),    # inside grace -> keep
            UserAction(user_id=uid, action_type="view_listing", created_at=old),   # purge
            UserAction(user_id=uid, action_type="view_listing", created_at=now),   # keep
            UserAction(user_id=uid, action_type="admin_delete_user", created_at=old),  # keep
            Notification(user_id=uid, title="a", message="m", notification_type="x",
                         is_read=True, created_at=old),                # purge
            Notification(user_id=uid, title="b", message="m", notification_type="x",
                         is_read=False, created_at=old),               # keep (unread)
            Notification(user_id=uid, title="c", message="m", notification_type="x",
                         is_read=True, created_at=now),                # keep (recent)
            AdminAuditLog(admin_user_id=uid, action_type="admin_delete_user", created_at=old),
        ])
        db.session.commit()
    return uid


def _counts(app, db):
    from kk.models import AdminAuditLog, Notification, TokenBlacklist, UserAction

    with app.app_context():
        return {
            "tb": TokenBlacklist.query.count(),
            "ua": UserAction.query.count(),
            "n": Notification.query.count(),
            "audit": AdminAuditLog.query.count(),
        }


def test_disabled_by_default_is_a_noop(ctx):
    from kk.retention import run_retention

    app, db = ctx
    _seed(app, db)
    before = _counts(app, db)
    with app.app_context():
        assert run_retention() == {}
    assert _counts(app, db) == before


def test_invalid_values_are_ignored(ctx, monkeypatch):
    from kk.retention import run_retention

    app, db = ctx
    before = _counts(app, db)
    for bad in ("", "0", "-5", "abc"):
        monkeypatch.setenv("RETENTION_USER_ACTION_DAYS", bad)
        monkeypatch.setenv("RETENTION_READ_NOTIFICATION_DAYS", bad)
        with app.app_context():
            assert run_retention() == {}
    assert _counts(app, db) == before


def test_enabled_jobs_delete_only_eligible_rows(ctx, monkeypatch):
    from kk.retention import run_retention

    app, db = ctx
    before = _counts(app, db)
    monkeypatch.setenv("RETENTION_TOKEN_BLACKLIST_PURGE", "1")
    monkeypatch.setenv("RETENTION_USER_ACTION_DAYS", "365")
    monkeypatch.setenv("RETENTION_READ_NOTIFICATION_DAYS", "365")
    with app.app_context():
        res = run_retention()
    assert res["token_blacklist"] >= 1 and res["user_action"] >= 1 and res["read_notifications"] >= 1
    after = _counts(app, db)
    assert after["tb"] == before["tb"] - res["token_blacklist"]
    assert after["ua"] == before["ua"] - res["user_action"]
    assert after["n"] == before["n"] - res["read_notifications"]
    assert after["audit"] == before["audit"]  # audit log never touched

    from kk.models import Notification, UserAction

    with app.app_context():
        assert UserAction.query.filter_by(action_type="admin_delete_user").count() >= 1
        assert Notification.query.filter_by(is_read=False).count() >= 1

    with app.app_context():
        assert run_retention() == {"token_blacklist": 0, "user_action": 0, "read_notifications": 0}


def test_batching_handles_more_rows_than_one_batch(ctx, monkeypatch):
    import kk.retention as r
    from kk.models import UserAction
    from kk.time_utils import utcnow

    app, db = ctx
    uid, _p, _n = _make_user(app, db)
    monkeypatch.setattr(r, "BATCH_SIZE", 7)
    with app.app_context():
        for _ in range(25):
            db.session.add(UserAction(user_id=uid, action_type="view_listing",
                                      created_at=utcnow() - timedelta(days=900)))
        db.session.commit()
        assert r.purge_old_user_actions(365) == 25
        assert UserAction.query.filter_by(user_id=uid).count() == 0


def test_beat_schedule_and_task_registered():
    from kk.tasks import retention_tasks  # noqa: F401
    from kk.tasks.celery_app import celery_app

    sched = celery_app.conf.beat_schedule
    assert sched["retention-cleanup"]["task"] == "kk.tasks.retention_tasks.run_retention_cleanup"
