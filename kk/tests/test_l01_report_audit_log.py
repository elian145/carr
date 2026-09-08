"""L-01: report resolutions (PATCH /api/admin/reports/user|listing/<id>) must
be audit-logged via the existing UserAction / log_user_action() mechanism,
the same convention already used by every other admin mutation route in
kk/routes/admin.py (admin_update_listing, admin_update_user, etc.).

Scope: this file covers ONLY L-01 (missing audit logging on report status
mutation). It does not touch or assert on any other audit finding.
"""

from __future__ import annotations

import os
import sys
import tempfile
import uuid
from pathlib import Path

import pytest

_REPO_ROOT = Path(__file__).resolve().parents[2]
if str(_REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(_REPO_ROOT))

_PASSWORD = "Aa123456!"


@pytest.fixture(scope="module")
def app_ctx():
    tmp = tempfile.TemporaryDirectory(prefix="carlist_l01_", ignore_cleanup_errors=True)
    os.environ["APP_ENV"] = "testing"
    os.environ["SMS_PROVIDER"] = "console"
    os.environ.pop("LISTING_REQUIRE_APPROVAL", None)
    os.environ["DB_PATH"] = os.path.join(tmp.name, "l01.db")

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


@pytest.fixture
def client(app_ctx):
    return app_ctx[1]


def _phone() -> str:
    return f"077{uuid.uuid4().int % 10**8:08d}"


def _auth(token: str) -> dict:
    return {"Authorization": f"Bearer {token}"}


def _login(client, username: str) -> str:
    r = client.post("/api/auth/login", json={"username": username, "password": _PASSWORD})
    assert r.status_code == 200, r.data
    return r.get_json()["access_token"]


def _make_user(app, db, *, username=None, is_admin=False, **extra):
    from kk.models import User

    username = username or f"u_{uuid.uuid4().hex[:10]}"
    with app.app_context():
        user = User(
            username=username,
            phone_number=_phone(),
            first_name="First",
            last_name="Last",
            is_active=True,
            is_verified=True,
            phone_verified=True,
            public_id=f"pub-{uuid.uuid4().hex[:12]}",
            is_admin=is_admin,
            **extra,
        )
        user.set_password(_PASSWORD)
        db.session.add(user)
        db.session.commit()
        return user.id, user.public_id, username


def _make_car(app, db, seller_id: int, **extra):
    from kk.models import Car

    with app.app_context():
        car = Car(
            seller_id=seller_id,
            public_id=f"car-{uuid.uuid4().hex[:12]}",
            brand="toyota",
            model="corolla",
            year=2021,
            mileage=10,
            engine_type="gas",
            transmission="auto",
            drive_type="fwd",
            condition="used",
            body_type="sedan",
            price=15000,
            location="Erbil",
            is_active=True,
            **extra,
        )
        db.session.add(car)
        db.session.commit()
        return car.id, car.public_id


def _make_user_report(app, db, *, reporter_id: int, reported_id: int, **extra):
    from kk.models import UserReport

    with app.app_context():
        report = UserReport(
            reporter_id=reporter_id,
            reported_id=reported_id,
            reason="abuse",
            **extra,
        )
        db.session.add(report)
        db.session.commit()
        return report.id


def _make_listing_report(app, db, *, reporter_id: int, car_id: int, **extra):
    from kk.models import ListingReport

    with app.app_context():
        report = ListingReport(
            reporter_id=reporter_id,
            car_id=car_id,
            reason="spam",
            **extra,
        )
        db.session.add(report)
        db.session.commit()
        return report.id


def _last_actions(app, db, *, user_id: int, target_type: str, target_id: str):
    from kk.models import UserAction

    with app.app_context():
        rows = (
            UserAction.query.filter_by(
                user_id=user_id, target_type=target_type, target_id=target_id
            )
            .order_by(UserAction.id.asc())
            .all()
        )
        # Detach usable data before the session context closes.
        return [
            {
                "action_type": r.action_type,
                "user_id": r.user_id,
                "target_type": r.target_type,
                "target_id": r.target_id,
                "action_metadata": dict(r.action_metadata or {}),
            }
            for r in rows
        ]


class TestUserReportAuditLog:
    def test_resolve_creates_single_audit_action_with_expected_fields(
        self, app_ctx, client
    ):
        app, _c, db = app_ctx
        admin_id, _ap, admin_name = _make_user(app, db, is_admin=True)
        reporter_id, _rp, _rn = _make_user(app, db)
        reported_id, _tp, _tn = _make_user(app, db)
        report_id = _make_user_report(
            app, db, reporter_id=reporter_id, reported_id=reported_id
        )

        token = _login(client, admin_name)
        resp = client.patch(
            f"/api/admin/reports/user/{report_id}",
            json={"status": "resolved", "admin_notes": "handled"},
            headers=_auth(token),
        )
        assert resp.status_code == 200, resp.data
        payload = resp.get_json()
        # Existing response shape unchanged.
        assert set(payload.keys()) == {"report"}
        assert payload["report"]["status"] == "resolved"
        assert payload["report"]["admin_notes"] == "handled"

        with app.app_context():
            from kk.models import UserReport

            report = db.session.get(UserReport, report_id)
            assert report.status == "resolved"

        actions = _last_actions(
            app, db, user_id=admin_id, target_type="user_report", target_id=str(report_id)
        )
        assert len(actions) == 1, actions
        action = actions[0]
        assert action["action_type"] == "admin_update_user_report"
        assert action["user_id"] == admin_id
        assert action["target_type"] == "user_report"
        assert action["target_id"] == str(report_id)
        assert action["action_metadata"]["previous_status"] == "pending"
        assert action["action_metadata"]["new_status"] == "resolved"
        assert action["action_metadata"]["admin_notes_provided"] is True

    def test_dismiss_without_notes_records_admin_notes_provided_false(
        self, app_ctx, client
    ):
        app, _c, db = app_ctx
        admin_id, _ap, admin_name = _make_user(app, db, is_admin=True)
        reporter_id, _rp, _rn = _make_user(app, db)
        reported_id, _tp, _tn = _make_user(app, db)
        report_id = _make_user_report(
            app, db, reporter_id=reporter_id, reported_id=reported_id
        )

        token = _login(client, admin_name)
        resp = client.patch(
            f"/api/admin/reports/user/{report_id}",
            json={"status": "dismissed"},
            headers=_auth(token),
        )
        assert resp.status_code == 200, resp.data

        actions = _last_actions(
            app, db, user_id=admin_id, target_type="user_report", target_id=str(report_id)
        )
        assert len(actions) == 1, actions
        assert actions[0]["action_metadata"]["admin_notes_provided"] is False
        assert actions[0]["action_metadata"]["new_status"] == "dismissed"

    def test_invalid_status_creates_no_audit_action(self, app_ctx, client):
        app, _c, db = app_ctx
        admin_id, _ap, admin_name = _make_user(app, db, is_admin=True)
        reporter_id, _rp, _rn = _make_user(app, db)
        reported_id, _tp, _tn = _make_user(app, db)
        report_id = _make_user_report(
            app, db, reporter_id=reporter_id, reported_id=reported_id
        )

        token = _login(client, admin_name)
        resp = client.patch(
            f"/api/admin/reports/user/{report_id}",
            json={"status": "not-a-real-status"},
            headers=_auth(token),
        )
        assert resp.status_code == 400, resp.data

        actions = _last_actions(
            app, db, user_id=admin_id, target_type="user_report", target_id=str(report_id)
        )
        assert actions == []

        with app.app_context():
            from kk.models import UserReport

            report = db.session.get(UserReport, report_id)
            assert report.status == "pending"

    def test_missing_report_creates_no_audit_action(self, app_ctx, client):
        app, _c, db = app_ctx
        admin_id, _ap, admin_name = _make_user(app, db, is_admin=True)

        token = _login(client, admin_name)
        missing_id = 9_999_999
        resp = client.patch(
            f"/api/admin/reports/user/{missing_id}",
            json={"status": "resolved"},
            headers=_auth(token),
        )
        assert resp.status_code == 404, resp.data

        actions = _last_actions(
            app, db, user_id=admin_id, target_type="user_report", target_id=str(missing_id)
        )
        assert actions == []

    def test_reopening_resolved_report_records_correct_previous_status(
        self, app_ctx, client
    ):
        app, _c, db = app_ctx
        admin_id, _ap, admin_name = _make_user(app, db, is_admin=True)
        reporter_id, _rp, _rn = _make_user(app, db)
        reported_id, _tp, _tn = _make_user(app, db)
        report_id = _make_user_report(
            app, db, reporter_id=reporter_id, reported_id=reported_id
        )

        token = _login(client, admin_name)
        first = client.patch(
            f"/api/admin/reports/user/{report_id}",
            json={"status": "resolved"},
            headers=_auth(token),
        )
        assert first.status_code == 200, first.data

        second = client.patch(
            f"/api/admin/reports/user/{report_id}",
            json={"status": "pending"},
            headers=_auth(token),
        )
        assert second.status_code == 200, second.data

        actions = _last_actions(
            app, db, user_id=admin_id, target_type="user_report", target_id=str(report_id)
        )
        assert len(actions) == 2, actions
        assert actions[0]["action_metadata"]["previous_status"] == "pending"
        assert actions[0]["action_metadata"]["new_status"] == "resolved"
        assert actions[1]["action_metadata"]["previous_status"] == "resolved"
        assert actions[1]["action_metadata"]["new_status"] == "pending"


class TestListingReportAuditLog:
    def test_resolve_creates_single_audit_action_with_expected_fields(
        self, app_ctx, client
    ):
        app, _c, db = app_ctx
        admin_id, _ap, admin_name = _make_user(app, db, is_admin=True)
        seller_id, _sp, _sn = _make_user(app, db)
        reporter_id, _rp, _rn = _make_user(app, db)
        car_id, _cp = _make_car(app, db, seller_id)
        report_id = _make_listing_report(app, db, reporter_id=reporter_id, car_id=car_id)

        token = _login(client, admin_name)
        resp = client.patch(
            f"/api/admin/reports/listing/{report_id}",
            json={"status": "resolved", "admin_notes": "removed listing"},
            headers=_auth(token),
        )
        assert resp.status_code == 200, resp.data
        payload = resp.get_json()
        assert set(payload.keys()) == {"report"}
        assert payload["report"]["status"] == "resolved"
        assert payload["report"]["admin_notes"] == "removed listing"

        actions = _last_actions(
            app, db, user_id=admin_id, target_type="listing_report", target_id=str(report_id)
        )
        assert len(actions) == 1, actions
        action = actions[0]
        assert action["action_type"] == "admin_update_listing_report"
        assert action["user_id"] == admin_id
        assert action["target_type"] == "listing_report"
        assert action["target_id"] == str(report_id)
        assert action["action_metadata"]["previous_status"] == "pending"
        assert action["action_metadata"]["new_status"] == "resolved"
        assert action["action_metadata"]["admin_notes_provided"] is True

    def test_dismiss_without_notes_records_admin_notes_provided_false(
        self, app_ctx, client
    ):
        app, _c, db = app_ctx
        admin_id, _ap, admin_name = _make_user(app, db, is_admin=True)
        seller_id, _sp, _sn = _make_user(app, db)
        reporter_id, _rp, _rn = _make_user(app, db)
        car_id, _cp = _make_car(app, db, seller_id)
        report_id = _make_listing_report(app, db, reporter_id=reporter_id, car_id=car_id)

        token = _login(client, admin_name)
        resp = client.patch(
            f"/api/admin/reports/listing/{report_id}",
            json={"status": "dismissed"},
            headers=_auth(token),
        )
        assert resp.status_code == 200, resp.data

        actions = _last_actions(
            app, db, user_id=admin_id, target_type="listing_report", target_id=str(report_id)
        )
        assert len(actions) == 1, actions
        assert actions[0]["action_metadata"]["admin_notes_provided"] is False
        assert actions[0]["action_metadata"]["new_status"] == "dismissed"

    def test_invalid_status_creates_no_audit_action(self, app_ctx, client):
        app, _c, db = app_ctx
        admin_id, _ap, admin_name = _make_user(app, db, is_admin=True)
        seller_id, _sp, _sn = _make_user(app, db)
        reporter_id, _rp, _rn = _make_user(app, db)
        car_id, _cp = _make_car(app, db, seller_id)
        report_id = _make_listing_report(app, db, reporter_id=reporter_id, car_id=car_id)

        token = _login(client, admin_name)
        resp = client.patch(
            f"/api/admin/reports/listing/{report_id}",
            json={"status": "bogus"},
            headers=_auth(token),
        )
        assert resp.status_code == 400, resp.data

        actions = _last_actions(
            app, db, user_id=admin_id, target_type="listing_report", target_id=str(report_id)
        )
        assert actions == []

        with app.app_context():
            from kk.models import ListingReport

            report = db.session.get(ListingReport, report_id)
            assert report.status == "pending"

    def test_missing_report_creates_no_audit_action(self, app_ctx, client):
        app, _c, db = app_ctx
        admin_id, _ap, admin_name = _make_user(app, db, is_admin=True)

        token = _login(client, admin_name)
        missing_id = 9_999_998
        resp = client.patch(
            f"/api/admin/reports/listing/{missing_id}",
            json={"status": "resolved"},
            headers=_auth(token),
        )
        assert resp.status_code == 404, resp.data

        actions = _last_actions(
            app, db, user_id=admin_id, target_type="listing_report", target_id=str(missing_id)
        )
        assert actions == []

    def test_reopening_resolved_report_records_correct_previous_status(
        self, app_ctx, client
    ):
        app, _c, db = app_ctx
        admin_id, _ap, admin_name = _make_user(app, db, is_admin=True)
        seller_id, _sp, _sn = _make_user(app, db)
        reporter_id, _rp, _rn = _make_user(app, db)
        car_id, _cp = _make_car(app, db, seller_id)
        report_id = _make_listing_report(app, db, reporter_id=reporter_id, car_id=car_id)

        token = _login(client, admin_name)
        first = client.patch(
            f"/api/admin/reports/listing/{report_id}",
            json={"status": "resolved"},
            headers=_auth(token),
        )
        assert first.status_code == 200, first.data

        second = client.patch(
            f"/api/admin/reports/listing/{report_id}",
            json={"status": "dismissed"},
            headers=_auth(token),
        )
        assert second.status_code == 200, second.data

        actions = _last_actions(
            app, db, user_id=admin_id, target_type="listing_report", target_id=str(report_id)
        )
        assert len(actions) == 2, actions
        assert actions[0]["action_metadata"]["previous_status"] == "pending"
        assert actions[0]["action_metadata"]["new_status"] == "resolved"
        assert actions[1]["action_metadata"]["previous_status"] == "resolved"
        assert actions[1]["action_metadata"]["new_status"] == "dismissed"
