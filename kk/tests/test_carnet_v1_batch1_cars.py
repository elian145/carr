"""CarNet V1 feature-completeness batch 1 -- backend regression tests.

Covers the backend half of three items from the batch:

  * Item 1 (currency persistence): ``POST /api/cars`` and
    ``PUT /api/cars/<id>`` must persist and return the listing's currency,
    default to USD when omitted on create, and never overwrite an existing
    currency on update unless the caller explicitly sends a new one.
  * Item 3 (damaged_parts backend filtering): ``GET /api/cars`` must filter
    on the existing ``Car.damaged_parts`` column when a ``damaged_parts``
    query parameter is supplied.
  * Item 5 (damaged-title validation): both ``create_car`` and
    ``update_car`` must reject (with HTTP 400) any request that leaves the
    listing with ``title_status=damaged`` but no ``damaged_parts`` value,
    while never retroactively blocking an unrelated edit to a pre-existing
    listing that predates this validation.

These exercise the real HTTP endpoints end-to-end against a real
SQLite-backed SQLAlchemy session, matching this project's existing
BE-06 / C-03 regression-test style.
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


@pytest.fixture(scope="module")
def app_ctx():
    tmp = tempfile.TemporaryDirectory(
        prefix="carlist_carnetv1_", ignore_cleanup_errors=True
    )
    os.environ["APP_ENV"] = "testing"
    os.environ["SMS_PROVIDER"] = "console"
    os.environ.pop("LISTING_REQUIRE_APPROVAL", None)
    os.environ["DB_PATH"] = os.path.join(tmp.name, "carnetv1.db")

    from kk.app_factory import create_app

    app, _socketio, *_ = create_app()
    from kk.models import Car, User, db

    with app.app_context():
        db.drop_all()
        db.create_all()

    yield app, app.test_client(), db, User, Car

    with app.app_context():
        db.session.remove()
        db.engine.dispose()
    tmp.cleanup()


@pytest.fixture
def client(app_ctx):
    return app_ctx[1]


def _unique_phone() -> str:
    return f"077{uuid.uuid4().int % 10**8:08d}"


def _make_user(app_ctx, *, username: str) -> str:
    """Create an active, verified, phone-verified user. Returns username."""
    app, _client, db, User, _Car = app_ctx
    with app.app_context():
        user = User(
            username=username,
            phone_number=_unique_phone(),
            first_name=username[:20],
            last_name="Test",
            is_active=True,
            is_verified=True,
            phone_verified=True,
            public_id=f"pub-{uuid.uuid4().hex[:12]}",
        )
        user.set_password("Aa123456!")
        db.session.add(user)
        db.session.commit()
    return username


def _login(client, username: str, password: str = "Aa123456!") -> str:
    r = client.post(
        "/api/auth/login", json={"username": username, "password": password}
    )
    assert r.status_code == 200, r.data
    return r.get_json()["access_token"]


def _auth(token: str) -> dict:
    return {"Authorization": f"Bearer {token}"}


def _base_car_payload(**overrides) -> dict:
    payload = {
        "brand": "toyota",
        "model": "camry",
        "year": 2021,
        "mileage": 1000,
        "price": 15000,
        "location": "Erbil",
        "condition": "used",
        "body_type": "sedan",
        "transmission": "automatic",
        "drive_type": "fwd",
    }
    payload.update(overrides)
    return payload


@pytest.fixture
def seller_token(client, app_ctx):
    username = f"cnv1_{uuid.uuid4().hex[:10]}"
    _make_user(app_ctx, username=username)
    return _login(client, username)


# ---------------------------------------------------------------------------
# Item 1: currency persistence
# ---------------------------------------------------------------------------


def test_create_car_defaults_currency_to_usd_when_omitted(client, seller_token):
    r = client.post(
        "/api/cars", json=_base_car_payload(), headers=_auth(seller_token)
    )
    assert r.status_code == 201, r.data
    car = r.get_json()["car"]
    assert car["currency"] == "USD"


def test_create_car_persists_and_returns_selected_currency(client, seller_token):
    r = client.post(
        "/api/cars",
        json=_base_car_payload(currency="IQD"),
        headers=_auth(seller_token),
    )
    assert r.status_code == 201, r.data
    car = r.get_json()["car"]
    assert car["currency"] == "IQD"

    # Persisted, not just echoed back -- re-fetch confirms it round-trips.
    r2 = client.get(f"/api/cars/{car['id']}")
    assert r2.status_code == 200, r2.data
    assert r2.get_json()["car"]["currency"] == "IQD"


def test_update_car_persists_new_currency(client, seller_token):
    create = client.post(
        "/api/cars", json=_base_car_payload(), headers=_auth(seller_token)
    )
    car_id = create.get_json()["car"]["id"]
    assert create.get_json()["car"]["currency"] == "USD"

    r = client.put(
        f"/api/cars/{car_id}",
        json={"currency": "IQD"},
        headers=_auth(seller_token),
    )
    assert r.status_code == 200, r.data
    assert r.get_json()["car"]["currency"] == "IQD"

    r2 = client.get(f"/api/cars/{car_id}")
    assert r2.get_json()["car"]["currency"] == "IQD"


def test_update_car_preserves_currency_when_field_omitted(client, seller_token):
    """Editing an IQD listing without touching currency must not silently
    reset it back to USD (the BE-01/Item-1 regression)."""
    create = client.post(
        "/api/cars",
        json=_base_car_payload(currency="IQD"),
        headers=_auth(seller_token),
    )
    car_id = create.get_json()["car"]["id"]
    assert create.get_json()["car"]["currency"] == "IQD"

    r = client.put(
        f"/api/cars/{car_id}",
        json={"mileage": 5000},
        headers=_auth(seller_token),
    )
    assert r.status_code == 200, r.data
    assert r.get_json()["car"]["currency"] == "IQD"


def test_existing_usd_listing_update_keeps_working(client, seller_token):
    create = client.post(
        "/api/cars", json=_base_car_payload(), headers=_auth(seller_token)
    )
    car_id = create.get_json()["car"]["id"]

    r = client.put(
        f"/api/cars/{car_id}",
        json={"price": 16000},
        headers=_auth(seller_token),
    )
    assert r.status_code == 200, r.data
    assert r.get_json()["car"]["currency"] == "USD"
    assert r.get_json()["car"]["price"] == 16000


# ---------------------------------------------------------------------------
# Item 3: damaged_parts backend filtering
# ---------------------------------------------------------------------------


def test_get_cars_filters_by_damaged_parts_count(client, seller_token):
    two_parts = client.post(
        "/api/cars",
        json=_base_car_payload(title_status="damaged", damaged_parts=2),
        headers=_auth(seller_token),
    ).get_json()["car"]
    four_parts = client.post(
        "/api/cars",
        json=_base_car_payload(title_status="damaged", damaged_parts=4),
        headers=_auth(seller_token),
    ).get_json()["car"]
    clean = client.post(
        "/api/cars", json=_base_car_payload(), headers=_auth(seller_token)
    ).get_json()["car"]

    r = client.get("/api/cars", query_string={"damaged_parts": "2"})
    assert r.status_code == 200, r.data
    ids = {c["id"] for c in r.get_json()["cars"]}
    assert two_parts["id"] in ids
    assert four_parts["id"] not in ids
    assert clean["id"] not in ids


def test_get_cars_without_damaged_parts_param_returns_all(client, seller_token):
    r_before = client.get("/api/cars")
    before_ids = {c["id"] for c in r_before.get_json()["cars"]}

    created = client.post(
        "/api/cars",
        json=_base_car_payload(title_status="damaged", damaged_parts=3),
        headers=_auth(seller_token),
    ).get_json()["car"]

    r_after = client.get("/api/cars")
    after_ids = {c["id"] for c in r_after.get_json()["cars"]}
    assert after_ids == before_ids | {created["id"]}


# ---------------------------------------------------------------------------
# Item 5: damaged-title validation (backend)
# ---------------------------------------------------------------------------


def test_create_car_rejects_damaged_title_without_damaged_parts(
    client, seller_token
):
    r = client.post(
        "/api/cars",
        json=_base_car_payload(title_status="damaged"),
        headers=_auth(seller_token),
    )
    assert r.status_code == 400, r.data
    assert "damaged_parts" in r.get_json().get("errors", {})


def test_create_car_accepts_damaged_title_with_damaged_parts(client, seller_token):
    r = client.post(
        "/api/cars",
        json=_base_car_payload(title_status="damaged", damaged_parts=1),
        headers=_auth(seller_token),
    )
    assert r.status_code == 201, r.data
    assert r.get_json()["car"]["damaged_parts"] == 1


def test_update_car_rejects_switching_to_damaged_without_damaged_parts(
    client, seller_token
):
    create = client.post(
        "/api/cars", json=_base_car_payload(), headers=_auth(seller_token)
    )
    car_id = create.get_json()["car"]["id"]

    r = client.put(
        f"/api/cars/{car_id}",
        json={"title_status": "damaged"},
        headers=_auth(seller_token),
    )
    assert r.status_code == 400, r.data
    assert "damaged_parts" in r.get_json().get("errors", {})


def test_update_car_accepts_switching_to_damaged_with_damaged_parts(
    client, seller_token
):
    create = client.post(
        "/api/cars", json=_base_car_payload(), headers=_auth(seller_token)
    )
    car_id = create.get_json()["car"]["id"]

    r = client.put(
        f"/api/cars/{car_id}",
        json={"title_status": "damaged", "damaged_parts": 5},
        headers=_auth(seller_token),
    )
    assert r.status_code == 200, r.data
    assert r.get_json()["car"]["title_status"] == "damaged"
    assert r.get_json()["car"]["damaged_parts"] == 5


def test_update_car_unrelated_edit_on_legacy_damaged_listing_not_blocked(
    client, app_ctx
):
    """A listing created before this validation existed (title_status
    already "damaged" with no damaged_parts) must not be retroactively
    blocked from unrelated edits that never touch title_status/damaged_parts."""
    app, _client, db, User, Car = app_ctx
    username = f"cnv1_legacy_{uuid.uuid4().hex[:10]}"
    _make_user(app_ctx, username=username)
    token = _login(client, username)
    with app.app_context():
        user = User.query.filter_by(username=username).first()
        legacy = Car(
            seller_id=user.id,
            public_id=f"legacy-{uuid.uuid4().hex[:10]}",
            brand="toyota",
            model="camry",
            year=2019,
            mileage=1000,
            engine_type="gasoline",
            fuel_type="gasoline",
            transmission="automatic",
            drive_type="fwd",
            condition="used",
            body_type="sedan",
            price=10000,
            location="Erbil",
            title_status="damaged",
            damaged_parts=None,
            is_active=True,
        )
        db.session.add(legacy)
        db.session.commit()
        car_id = legacy.public_id

    r = client.put(
        f"/api/cars/{car_id}",
        json={"mileage": 12345},
        headers=_auth(token),
    )
    assert r.status_code == 200, r.data
    assert r.get_json()["car"]["mileage"] == 12345
