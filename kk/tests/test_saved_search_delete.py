"""Regression: deleting a saved search that already fired an alert must not 500.

Pre-D-01, ``SavedSearchAlert.saved_search_id`` had no ON DELETE policy and
``delete_saved_search()`` did not clean child rows, so Postgres/SQLite-with-FKs
raised IntegrityError and the route returned 500. Group-A CASCADE on
``saved_search_alert.saved_search_id`` is the fix.
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
    tmp = tempfile.TemporaryDirectory(
        prefix="carlist_saved_search_del_", ignore_cleanup_errors=True
    )
    os.environ["APP_ENV"] = "testing"
    os.environ["SMS_PROVIDER"] = "console"
    os.environ["DB_PATH"] = os.path.join(tmp.name, "saved_search_del.db")

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


def test_delete_saved_search_with_existing_alert_returns_200(app_ctx, client):
    app, _c, db = app_ctx
    from kk.models import Car, SavedSearch, SavedSearchAlert, User

    with app.app_context():
        user = User(
            username=f"ss_{uuid.uuid4().hex[:8]}",
            phone_number=_phone(),
            first_name="Save",
            last_name="Search",
            is_active=True,
            is_verified=True,
            phone_verified=True,
            public_id=f"pub-{uuid.uuid4().hex[:12]}",
        )
        user.set_password(_PASSWORD)
        db.session.add(user)
        db.session.flush()
        car = Car(
            seller_id=user.id,
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
        )
        db.session.add(car)
        db.session.commit()
        username = user.username
        car_pk = car.id

    login = client.post(
        "/api/auth/login", json={"username": username, "password": _PASSWORD}
    )
    assert login.status_code == 200, login.data
    token = login.get_json()["access_token"]
    headers = {"Authorization": f"Bearer {token}"}

    created = client.post(
        "/api/saved-searches",
        json={"name": "Toyotas", "filters": {"brand": "toyota"}, "notify": True},
        headers=headers,
    )
    assert created.status_code == 201, created.data
    search_public_id = created.get_json()["saved_search"]["id"]

    with app.app_context():
        row = SavedSearch.query.filter_by(public_id=search_public_id).first()
        assert row is not None
        db.session.add(SavedSearchAlert(saved_search_id=row.id, car_id=car_pk))
        db.session.commit()
        search_pk = row.id

    deleted = client.delete(f"/api/saved-searches/{search_public_id}", headers=headers)
    assert deleted.status_code == 200, deleted.data
    assert deleted.get_json()["message"] == "Deleted"

    with app.app_context():
        assert SavedSearch.query.filter_by(id=search_pk).first() is None
        assert SavedSearchAlert.query.filter_by(saved_search_id=search_pk).count() == 0
