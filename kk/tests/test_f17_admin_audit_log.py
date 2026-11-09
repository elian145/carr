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


# ---------------------------------------------------------------------------
# Data minimisation: the audit table is permanent, so what enters it is bounded.
# ---------------------------------------------------------------------------


def test_audit_metadata_redacts_personal_keys_and_bounds_free_text():
    from kk.auth import audit_safe_metadata

    out = audit_safe_metadata(
        {
            "email": "someone@example.com",
            "phone_number": "07701234567",
            "New_Password": "x",
            "reason": "r" * 5000,
            "nested": {"contact_phone": "0770", "ok": 1},
            "status": "active",
        }
    )
    assert out["email"] == out["phone_number"] == out["New_Password"] == "[redacted]"
    assert out["nested"] == {"contact_phone": "[redacted]", "ok": 1}
    assert out["status"] == "active"  # legitimate audit detail is kept
    assert len(out["reason"]) < 300 and out["reason"].endswith("...[truncated]")
    assert "someone@example.com" not in repr(out) and "07701234567" not in repr(out)


def test_audit_metadata_is_size_bounded_and_negative_controls_pass_through():
    from kk.auth import audit_safe_metadata

    huge = {f"k{i}": "v" * 190 for i in range(25)}  # ~5 KB once serialised
    out = audit_safe_metadata(huge)
    assert out.get("_truncated") is True and len(out["keys"]) <= 25
    many = audit_safe_metadata({"ids": list(range(1000))})
    assert len(many["ids"]) == 26 and many["ids"][-1] == "[+975 more]"
    # negative controls: small, ordinary metadata is stored unchanged
    small = {"resolution": "dismissed", "is_featured_dealer": True, "n": 3, "none": None}
    assert audit_safe_metadata(small) == small
    assert audit_safe_metadata(None) is None


def test_update_user_status_audits_only_is_active_never_the_raw_body(ctx):
    from kk.models import AdminAuditLog

    app, client, db = ctx
    _aid, _p, admin_name = _make_user(app, db, is_admin=True)
    target_id, _p, _n = _make_user(app, db)
    token = _login(client, admin_name)
    with app.app_context():
        from kk.models import User

        public_id = db.session.get(User, target_id).public_id
    resp = client.patch(
        f"/api/admin/users/{public_id}/status",
        json={"is_active": False, "email": "leak@example.com", "note": "free text " * 50},
        headers=_auth(token),
    )
    assert resp.status_code == 200, resp.data
    with app.app_context():
        row = AdminAuditLog.query.filter_by(action_type="admin_update_user", target_id=public_id).one()
        assert row.action_metadata == {"is_active": False}
        assert "leak@example.com" not in repr(row.action_metadata)
