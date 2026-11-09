"""F-16: retention cleanup is opt-in and never touches protected data."""

from __future__ import annotations

import os
import tempfile
import uuid
from datetime import timedelta

import pytest

from kk.tests.test_l01_report_audit_log import _make_user

_RETENTION_VARS = (
    "RETENTION_ENABLED",
    "RETENTION_DRY_RUN",
    "RETENTION_AUTH_TOKEN_PURGE",
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
            # retention_run rows are the job's own audit trail (tested separately).
            "audit": AdminAuditLog.query.filter(AdminAuditLog.action_type != "retention_run").count(),
        }


def test_disabled_by_default_is_a_noop(ctx):
    from kk.retention import run_retention

    app, db = ctx
    _seed(app, db)
    before = _counts(app, db)
    with app.app_context():
        assert run_retention() == {}
    assert _counts(app, db) == before


def _enable_real_deletes(monkeypatch):
    monkeypatch.setenv("RETENTION_ENABLED", "1")
    monkeypatch.setenv("RETENTION_DRY_RUN", "0")


def test_invalid_values_are_ignored(ctx, monkeypatch):
    from kk.retention import run_retention

    app, db = ctx
    before = _counts(app, db)
    _enable_real_deletes(monkeypatch)
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
    _enable_real_deletes(monkeypatch)
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


def test_auth_token_purge_is_opt_in_and_removes_only_long_expired_rows(ctx, monkeypatch):
    """Reset / email-verification rows: purged only past expiry+grace, only when enabled."""
    import secrets

    import kk.retention as r
    from kk.models import EmailVerification, PasswordReset
    from kk.time_utils import utcnow

    app, db = ctx
    uid, _p, _n = _make_user(app, db)
    now = utcnow()
    with app.app_context():
        # PasswordReset.token is hashed on bind, so unique raw values give unique rows.
        for expires, used in (
            (now - timedelta(days=2), False),     # expired, unused -> purge
            (now - timedelta(days=2), True),      # expired, used   -> purge
            (now - timedelta(minutes=5), False),  # inside grace    -> keep
            (now + timedelta(minutes=30), False),  # live            -> keep
        ):
            db.session.add(PasswordReset(user_id=uid, token=secrets.token_hex(8),
                                         expires_at=expires, is_used=used))
            db.session.add(EmailVerification(user_id=uid, token=secrets.token_hex(8),
                                             expires_at=expires, is_used=used))
        db.session.commit()
        pr0, ev0 = PasswordReset.query.count(), EmailVerification.query.count()

        assert "password_reset" not in r.run_retention()  # disabled by default
        assert PasswordReset.query.count() == pr0 and EmailVerification.query.count() == ev0

        monkeypatch.setenv("RETENTION_AUTH_TOKEN_PURGE", "1")
        assert "password_reset" not in r.run_retention()  # job flag alone: master switch still off
        assert PasswordReset.query.count() == pr0
        _enable_real_deletes(monkeypatch)
        res = r.run_retention()
        assert res["password_reset"] >= 2 and res["email_verification"] >= 2
        assert PasswordReset.query.count() == pr0 - res["password_reset"]
        assert EmailVerification.query.count() == ev0 - res["email_verification"]
        # live + inside-grace rows survive
        assert PasswordReset.query.filter_by(user_id=uid).filter(
            PasswordReset.expires_at > now - timedelta(hours=1)).count() == 2
        assert r.run_retention()["password_reset"] == 0  # idempotent


# --------------------------------------------------------------------------
# Safety gates: master switch, dry-run default, unset periods, limits, audit, failure
# --------------------------------------------------------------------------

_OLD_DAYS = 400


def _all_jobs_configured(monkeypatch):
    monkeypatch.setenv("RETENTION_TOKEN_BLACKLIST_PURGE", "1")
    monkeypatch.setenv("RETENTION_AUTH_TOKEN_PURGE", "1")
    monkeypatch.setenv("RETENTION_USER_ACTION_DAYS", "365")
    monkeypatch.setenv("RETENTION_READ_NOTIFICATION_DAYS", "365")


def _retention_audit_rows(app):
    from kk.models import AdminAuditLog

    with app.app_context():
        return [
            (r.admin_user_id, r.target_type, dict(r.action_metadata or {}))
            for r in AdminAuditLog.query.filter_by(action_type="retention_run").order_by(AdminAuditLog.id)
        ]


def _jobs(meta):
    """Audit metadata -> {job: rows}."""
    return {j["job"]: j["rows"] for j in meta["jobs"]}


def _fresh_state(app, db):
    """Seed deletable rows and return (counts-before, audit-rows-before)."""
    _seed(app, db)
    return _counts(app, db), len(_retention_audit_rows(app))


def test_master_switch_off_does_nothing_even_with_every_job_configured(ctx, monkeypatch):
    import kk.retention as r

    app, db = ctx
    before, audits = _fresh_state(app, db)
    _all_jobs_configured(monkeypatch)
    monkeypatch.setenv("RETENTION_DRY_RUN", "0")  # even with dry-run explicitly off
    assert r.retention_mode() == "disabled"
    for off in (None, "", "0", "false", "no", "banana"):
        if off is None:
            monkeypatch.delenv("RETENTION_ENABLED", raising=False)
        else:
            monkeypatch.setenv("RETENTION_ENABLED", off)
        with app.app_context():
            assert r.run_retention() == {}
    assert _counts(app, db) == before
    assert len(_retention_audit_rows(app)) == audits  # disabled => nothing to audit


def test_enabled_defaults_to_dry_run_and_deletes_nothing(ctx, monkeypatch):
    import kk.retention as r

    app, db = ctx
    before, audits = _fresh_state(app, db)
    _all_jobs_configured(monkeypatch)
    monkeypatch.setenv("RETENTION_ENABLED", "1")
    # unset and every non-"off" value (typos included) keep dry-run ON
    for value in (None, "", "1", "true", "maybe", "dry"):
        if value is None:
            monkeypatch.delenv("RETENTION_DRY_RUN", raising=False)
        else:
            monkeypatch.setenv("RETENTION_DRY_RUN", value)
        assert r.retention_mode() == "dry-run"
        with app.app_context():
            res = r.run_retention()
        assert res["token_blacklist"] >= 1 and res["user_action"] >= 1 and res["read_notifications"] >= 1
        assert set(res) == {
            "token_blacklist", "password_reset", "email_verification", "user_action", "read_notifications",
        }
        assert _counts(app, db) == before  # nothing was deleted
    rows = _retention_audit_rows(app)[audits:]
    assert len(rows) == 6 and all(m["mode"] == "dry-run" for _u, _t, m in rows) and _jobs(rows[-1][2]) == dict(res)
    assert all(uid is None and target == "retention" for uid, target, _m in rows)


def test_dry_run_off_requires_an_explicit_value_and_really_deletes(ctx, monkeypatch):
    import kk.retention as r

    app, db = ctx
    before, audits = _fresh_state(app, db)
    _all_jobs_configured(monkeypatch)
    monkeypatch.setenv("RETENTION_ENABLED", "1")
    for off in ("0", "false", "NO", "off"):
        monkeypatch.setenv("RETENTION_DRY_RUN", off)
        assert r.retention_mode() == "delete"
    monkeypatch.setenv("RETENTION_DRY_RUN", "0")
    dry_counts = None
    monkeypatch.setenv("RETENTION_DRY_RUN", "1")
    with app.app_context():
        dry_counts = r.run_retention()
    monkeypatch.setenv("RETENTION_DRY_RUN", "0")
    with app.app_context():
        res = r.run_retention()
    assert res["token_blacklist"] == dry_counts["token_blacklist"] >= 1  # dry-run predicted exactly
    assert res["user_action"] == dry_counts["user_action"] >= 1
    after = _counts(app, db)
    assert after["tb"] == before["tb"] - res["token_blacklist"]
    assert after["audit"] == before["audit"]
    meta = _retention_audit_rows(app)[-1][2]
    assert meta["mode"] == "delete" and _jobs(meta) == res and "error" not in meta


def test_unset_or_invalid_periods_are_never_defaulted_and_are_reported(ctx, monkeypatch):
    import kk.retention as r

    app, db = ctx
    before, audits = _fresh_state(app, db)
    _enable_real_deletes(monkeypatch)  # real deletes ON, but no job configured
    for bad in (None, "", "0", "-1", "abc", "1.5"):
        for name in ("RETENTION_USER_ACTION_DAYS", "RETENTION_READ_NOTIFICATION_DAYS"):
            if bad is None:
                monkeypatch.delenv(name, raising=False)
            else:
                monkeypatch.setenv(name, bad)
        with app.app_context():
            assert r.run_retention() == {}
        assert _counts(app, db) == before  # old rows survive: no invented period
    meta = _retention_audit_rows(app)[-1][2]
    assert meta["jobs"] == [] and len(meta["skipped_unconfigured"]) == 2
    assert any("RETENTION_USER_ACTION_DAYS" in s for s in meta["skipped_unconfigured"])
    assert any("RETENTION_READ_NOTIFICATION_DAYS" in s for s in meta["skipped_unconfigured"])


def test_batch_limits_cap_a_single_run_for_deletes_and_dry_runs(ctx, monkeypatch):
    import kk.retention as r
    from kk.models import UserAction
    from kk.time_utils import utcnow

    app, db = ctx
    uid, _p, _n = _make_user(app, db)
    monkeypatch.setattr(r, "BATCH_SIZE", 5)
    monkeypatch.setattr(r, "MAX_BATCHES", 2)
    with app.app_context():
        for _ in range(23):
            db.session.add(UserAction(user_id=uid, action_type="view_listing",
                                      created_at=utcnow() - timedelta(days=_OLD_DAYS * 3)))
        db.session.commit()
        assert r._count_matching(UserAction, r._user_action_predicate(365, utcnow())) >= 10
        monkeypatch.setenv("RETENTION_USER_ACTION_DAYS", "365")
        monkeypatch.setenv("RETENTION_ENABLED", "1")
        monkeypatch.setenv("RETENTION_DRY_RUN", "1")
        assert r.run_retention()["user_action"] == 10  # dry-run reports the capped figure
        monkeypatch.setenv("RETENTION_DRY_RUN", "0")
        assert r.run_retention()["user_action"] == 10  # 2 batches x 5, never more per run
        assert UserAction.query.filter_by(user_id=uid).count() >= 13


def test_failure_rolls_back_is_audited_and_reraised(ctx, monkeypatch):
    import kk.retention as r

    app, db = ctx
    before, audits = _fresh_state(app, db)
    _all_jobs_configured(monkeypatch)
    _enable_real_deletes(monkeypatch)
    real = r._delete_in_batches
    calls = []

    def flaky(model, predicate):
        calls.append(model.__name__)
        if len(calls) == 2:
            raise RuntimeError("db exploded SECRET-DETAIL")
        return real(model, predicate)

    monkeypatch.setattr(r, "_delete_in_batches", flaky)
    with app.app_context():
        with pytest.raises(RuntimeError):
            r.run_retention()
    assert calls == ["TokenBlacklist", "PasswordReset"]  # stopped at the failure
    meta = _retention_audit_rows(app)[-1][2]
    assert meta["mode"] == "delete" and meta["error"] == "RuntimeError"
    assert "token_blacklist" in _jobs(meta) and "password_reset" not in _jobs(meta)
    assert "SECRET-DETAIL" not in str(meta)  # exception text (may hold row data) is not persisted
    assert _counts(app, db)["audit"] == before["audit"]


def test_dry_run_failure_is_audited_and_reraised(ctx, monkeypatch):
    import kk.retention as r

    app, db = ctx
    before, audits = _fresh_state(app, db)
    _all_jobs_configured(monkeypatch)
    monkeypatch.setenv("RETENTION_ENABLED", "1")

    def boom(model, predicate):
        raise ValueError("nope")

    monkeypatch.setattr(r, "_count_matching", boom)
    with app.app_context():
        with pytest.raises(ValueError):
            r.run_retention()
    assert _retention_audit_rows(app)[-1][2]["error"] == "ValueError"
    assert _counts(app, db) == before


def test_job_flags_alone_never_delete_and_audit_log_is_never_deleted(ctx, monkeypatch):
    import kk.retention as r
    from kk.models import AdminAuditLog

    app, db = ctx
    _all_jobs_configured(monkeypatch)
    _enable_real_deletes(monkeypatch)
    with app.app_context():
        total_before = AdminAuditLog.query.count()
        r.run_retention()
        assert AdminAuditLog.query.filter(AdminAuditLog.action_type != "retention_run").count() >= 1
        assert AdminAuditLog.query.count() >= total_before  # append-only: only ever grows


def test_celery_task_reports_mode_and_counts(ctx, monkeypatch):
    from kk.tasks.retention_tasks import run_retention_cleanup

    app, db = ctx
    # .run(), not run_retention_cleanup(): Task.__call__ is FlaskContextTask, which would
    # create_app() a second, process-global Flask app and leak into later test modules.
    with app.app_context():
        assert run_retention_cleanup.run() == {"mode": "disabled", "counts": {}}
        monkeypatch.setenv("RETENTION_ENABLED", "1")
        out = run_retention_cleanup.run()
        assert out["mode"] == "dry-run" and out["counts"] == {}


def test_docs_and_env_names_stay_in_sync():
    import pathlib

    doc = (pathlib.Path(__file__).resolve().parents[2] / "docs" / "RETENTION_CLEANUP.md").read_text(encoding="utf-8")
    for name in ("RETENTION_ENABLED", "RETENTION_DRY_RUN", "RETENTION_USER_ACTION_DAYS",
                 "RETENTION_READ_NOTIFICATION_DAYS", "RETENTION_TOKEN_BLACKLIST_PURGE",
                 "RETENTION_AUTH_TOKEN_PURGE", "retention_run"):
        assert name in doc, name
