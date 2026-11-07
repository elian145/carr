"""F-18: GET /api/admin/reports paginates server-side over the union of user and
listing reports. Old reports beyond the former 200-per-type cap stay reachable.
"""

from __future__ import annotations

import os
import tempfile
import uuid
from datetime import datetime, timedelta

import pytest

from kk.tests.test_l01_report_audit_log import (
    _auth,
    _login,
    _make_car,
    _make_user,
    _phone,
)


@pytest.fixture(scope="module")
def ctx():
    tmp = tempfile.TemporaryDirectory(prefix="carlist_f18_", ignore_cleanup_errors=True)
    os.environ["APP_ENV"] = "testing"
    os.environ["SMS_PROVIDER"] = "console"
    os.environ["DB_PATH"] = os.path.join(tmp.name, "f18.db")

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


def _seed(app, db, n_user, n_listing):
    """Create reports with strictly decreasing created_at; returns admin name."""
    from kk.models import ListingReport, UserReport

    admin_id, _p, admin_name = _make_user(app, db, is_admin=True)
    reporter_id, _p, _n = _make_user(app, db)
    reported_id, _p, _n = _make_user(app, db)
    seller_id, _p, _n = _make_user(app, db)
    car_id, _p = _make_car(app, db, seller_id)
    base = datetime(2026, 1, 1)
    from kk.models import User

    with app.app_context():
        # (reporter, car) is unique for listing reports -> one cheap reporter each.
        reporters = []
        for i in range(n_listing):
            u = User(username=f"rep_{uuid.uuid4().hex[:10]}", phone_number=_phone(),
                     is_active=True, password_hash="x", first_name="R", last_name="R", public_id=f"pub-{uuid.uuid4().hex[:12]}")
            db.session.add(u)
            reporters.append(u)
        db.session.flush()
        # index 0 = newest. user reports occupy even minutes, listing odd.
        for i in range(n_user):
            db.session.add(UserReport(reporter_id=reporter_id, reported_id=reported_id,
                                      reason="abuse", status="pending",
                                      created_at=base - timedelta(minutes=2 * i)))
        for i, u in enumerate(reporters):
            db.session.add(ListingReport(reporter_id=u.id, car_id=car_id,
                                         reason="spam", status="pending",
                                         created_at=base - timedelta(minutes=2 * i + 1)))
        db.session.commit()
    return admin_name


def _get(client, token, **params):
    q = "&".join(f"{k}={v}" for k, v in params.items())
    resp = client.get(f"/api/admin/reports?{q}", headers=_auth(token))
    assert resp.status_code in (200, 400), resp.data
    return resp


def test_reports_beyond_old_200_cap_are_reachable_and_ordered(ctx):
    app, client, db = ctx
    admin = _seed(app, db, n_user=250, n_listing=250)
    token = _login(client, admin)

    seen = []
    page = 1
    while True:
        body = _get(client, token, page=page, per_page=100).get_json()
        pg = body["pagination"]
        assert pg["total"] == 500
        assert len(body["reports"]) <= 100
        seen.extend(body["reports"])
        if not pg["has_next"]:
            break
        page += 1
    assert page == 5
    assert len(seen) == 500
    keys = {(r["type"], r["id"]) for r in seen}
    assert {t for t, _i in keys} == {"user", "listing"}
    assert len(keys) == 500  # no duplicates, nothing dropped
    stamps = [r["created_at"] for r in seen]
    assert stamps == sorted(stamps, reverse=True)  # globally newest-first


def test_type_filter_counts_in_sql_not_capped(ctx):
    app, client, db = ctx
    admin = _seed(app, db, n_user=0, n_listing=0)  # fresh admin only
    token = _login(client, admin)
    body = _get(client, token, type="user", per_page=5, page=50).get_json()
    assert body["pagination"]["total"] == 250
    assert body["pagination"]["pages"] == 50
    assert len(body["reports"]) == 5  # oldest user reports, formerly invisible


def test_page_window_is_bounded(ctx):
    app, client, db = ctx
    admin = _seed(app, db, n_user=0, n_listing=0)
    token = _login(client, admin)
    resp = _get(client, token, page=101, per_page=100)  # offset window > 10000
    assert resp.status_code == 400
