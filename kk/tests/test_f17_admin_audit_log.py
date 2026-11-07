"""F-17: admin actions go to an append-only table that no user delete can cascade into."""

from __future__ import annotations

import os
import tempfile

import pytest

from kk.tests.test_l01_report_audit_log import (
    _auth,
    _login,
    _make_car,
    _make_user,
    _make_user_report,
)


@pytest.fixture(scope="module")
def ctx():
    tmp = tempfile.TemporaryDirectory(prefix="carlist_f17_", ignore_cleanup_errors=True)
    os.environ["APP_ENV"] = "testing"
    os.environ["SMS_PROVIDER"] = "console"
    os.environ["DB_PATH"] = os.path.join(tmp.name, "f17.db")

    from kk.app_factory import create_app

    app, _socketio, *_ = create_app()
    from kk.models import db

    with app.app_context():
        db.drop_all()
        db.create_all()
    yield app, app.test_client(), db
    with app.app_context():
        db.session.remove()
        db.engine.dispose()
    tmp.cleanup()


def test_admin_action_is_written_to_audit_table_and_survives_user_delete(ctx):
    from kk.models import AdminAuditLog, User, UserAction

    app, client, db = ctx
    admin_id, _p, admin_name = _make_user(app, db, is_admin=True)
    reporter_id, _p, _n = _make_user(app, db)
    reported_id, _p, _n = _make_user(app, db)
    report_id = _make_user_report(app, db, reporter_id=reporter_id, reported_id=reported_id)
    token = _login(client, admin_name)

    resp = client.patch(
        f"/api/admin/reports/user/{report_id}",
        json={"status": "resolved", "admin_notes": "ok"},
        headers=_auth(token),
    )
    assert resp.status_code == 200, resp.data

    with app.app_context():
        rows = AdminAuditLog.query.filter_by(action_type="admin_update_user_report").all()
        assert len(rows) == 1
        row = rows[0]
        assert row.admin_user_id == admin_id and row.admin_username == admin_name
        assert row.target_id == str(report_id)
        audit_id = row.id
        # legacy mirror still written
        assert UserAction.query.filter_by(user_id=admin_id, action_type="admin_update_user_report").count() == 1

    # Deleting the acting user cascades their UserAction rows (FK ON DELETE
    # CASCADE) but must never touch the audit table.
    from kk.auth import log_admin_action

    actor_id, _p, _n = _make_user(app, db)
    with app.app_context():
        actor = db.session.get(User, actor_id)
        log_admin_action(actor, "admin_purge_user", "user", "123", {"k": "v"})
        audit = AdminAuditLog.query.filter_by(admin_user_id=actor_id).one()
        audit_id = audit.id
        assert UserAction.query.filter_by(user_id=actor_id).count() == 1
        if db.engine.dialect.name == "sqlite":
            db.session.execute(db.text("PRAGMA foreign_keys=ON"))
        db.session.delete(actor)
        db.session.commit()
        db.session.expire_all()
        assert UserAction.query.filter_by(user_id=actor_id).count() == 0  # cascade (the F-17 problem)
        kept = db.session.get(AdminAuditLog, audit_id)
        assert kept is not None and kept.admin_user_id == actor_id and kept.action_type == "admin_purge_user"

def test_audit_table_has_no_foreign_keys(ctx):
    from kk.models import AdminAuditLog

    assert not list(AdminAuditLog.__table__.foreign_keys)


def test_audit_rows_are_append_only_in_orm(ctx):
    from kk.models import AdminAuditLog

    app, _client, db = ctx
    with app.app_context():
        row = AdminAuditLog(admin_user_id=1, admin_username="x", action_type="t")
        db.session.add(row)
        db.session.commit()
        row.action_type = "tampered"
        with pytest.raises(RuntimeError):
            db.session.commit()
        db.session.rollback()
        db.session.delete(db.session.get(AdminAuditLog, row.id))
        with pytest.raises(RuntimeError):
            db.session.commit()
        db.session.rollback()
