"""H-05: exact dealer GPS coordinates must stay confined to the intentional
public dealer-profile map feature (``GET /api/dealers/<id>``) and to
owner/admin (``include_private=True``) views. They must NOT be replicated
into the generic public ``seller`` embed used by the browse/detail/favorites
feeds, which have no map feature.

See ``kk/tests/test_user_public_dict_privacy.py`` for the unit-level
(no Flask app) coverage of ``User.to_dict()`` / ``DealerProfile.to_dict()``.
This file adds HTTP-level regression coverage proving the actual routes
behave correctly end-to-end.

Non-round coordinates are used throughout so a rounding/coarsening
regression would be caught, not just an omission regression.
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

DEALER_LATITUDE = 33.123456
DEALER_LONGITUDE = 44.654321

MAP_LOCATION_KEYS = ("dealership_latitude", "dealership_longitude")


@pytest.fixture(scope="module")
def app_ctx():
    tmp = tempfile.TemporaryDirectory(prefix="carlist_h05_", ignore_cleanup_errors=True)
    os.environ["APP_ENV"] = "testing"
    os.environ["SMS_PROVIDER"] = "console"
    os.environ.pop("LISTING_REQUIRE_APPROVAL", None)
    os.environ["DB_PATH"] = os.path.join(tmp.name, "h05.db")

    from kk.app_factory import create_app

    app, socketio, *_ = create_app()
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


def _login(client, username: str, password: str = "Aa123456!") -> str:
    r = client.post("/api/auth/login", json={"username": username, "password": password})
    assert r.status_code == 200, r.data
    return r.get_json()["access_token"]


def _auth(token: str) -> dict:
    return {"Authorization": f"Bearer {token}"}


@pytest.fixture(scope="module")
def dealer_ctx(app_ctx):
    """An approved, active dealer with exact map coordinates set."""
    app, _client, db, User, _Car = app_ctx
    username = f"h05_dealer_{uuid.uuid4().hex[:8]}"
    with app.app_context():
        user = User(
            username=username,
            phone_number=_unique_phone(),
            first_name="Dealer",
            last_name="Test",
            email=None,
            is_active=True,
            is_verified=True,
            phone_verified=True,
            public_id=f"pub-{uuid.uuid4().hex[:12]}",
            account_type="dealer",
            dealer_status="approved",
            dealership_name="Best Cars",
            dealership_phone="+9647709999999",
            dealership_phones=["+9647709999999"],
            dealership_location="Erbil",
            dealership_latitude=DEALER_LATITUDE,
            dealership_longitude=DEALER_LONGITUDE,
        )
        user.set_password("Aa123456!")
        db.session.add(user)
        db.session.commit()
        return username, user.public_id, user.id


@pytest.fixture(scope="module")
def buyer_ctx(app_ctx):
    app, _client, db, User, _Car = app_ctx
    username = f"h05_buyer_{uuid.uuid4().hex[:8]}"
    with app.app_context():
        user = User(
            username=username,
            phone_number=_unique_phone(),
            first_name="Buyer",
            last_name="Test",
            email=None,
            is_active=True,
            is_verified=True,
            phone_verified=True,
            public_id=f"pub-{uuid.uuid4().hex[:12]}",
        )
        user.set_password("Aa123456!")
        db.session.add(user)
        db.session.commit()
        return username, user.public_id


@pytest.fixture(scope="module")
def admin_ctx(app_ctx):
    app, _client, db, User, _Car = app_ctx
    username = f"h05_admin_{uuid.uuid4().hex[:8]}"
    with app.app_context():
        user = User(
            username=username,
            phone_number=_unique_phone(),
            first_name="Admin",
            last_name="Test",
            email=None,
            is_active=True,
            is_verified=True,
            phone_verified=True,
            public_id=f"pub-{uuid.uuid4().hex[:12]}",
            is_admin=True,
        )
        user.set_password("Aa123456!")
        db.session.add(user)
        db.session.commit()
        return username, user.public_id


@pytest.fixture(scope="module")
def dealer_car_ctx(app_ctx, dealer_ctx):
    """A single active listing owned by the dealer, used by every
    seller-embed assertion below."""
    app, _client, db, _User, Car = app_ctx
    _username, dealer_public_id, dealer_id = dealer_ctx
    with app.app_context():
        car = Car(
            seller_id=dealer_id,
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
        return car.public_id


# ---------------------------------------------------------------------------
# C. Public dealer profile: exact coordinates preserved (Google Maps feature)
# ---------------------------------------------------------------------------


class TestPublicDealerProfileKeepsExactCoordinates:
    def test_anonymous_dealer_profile_returns_exact_coordinates(
        self, client, dealer_ctx, dealer_car_ctx
    ):
        _username, dealer_public_id, _dealer_id = dealer_ctx
        resp = client.get(f"/api/dealers/{dealer_public_id}")
        assert resp.status_code == 200, resp.data
        dealer = resp.get_json()["dealer"]
        assert dealer["dealership_latitude"] == DEALER_LATITUDE
        assert dealer["dealership_longitude"] == DEALER_LONGITUDE


# ---------------------------------------------------------------------------
# D. Public listing seller embed: no exact coordinates
# ---------------------------------------------------------------------------


class TestPublicListingSellerEmbedHidesCoordinates:
    def test_api_cars_list_seller_has_no_map_location(
        self, client, dealer_ctx, dealer_car_ctx
    ):
        resp = client.get("/api/cars")
        assert resp.status_code == 200, resp.data
        cars = resp.get_json()["cars"]
        matches = [c for c in cars if c.get("id") == dealer_car_ctx]
        assert matches, "expected the dealer's listing in /api/cars"
        seller = matches[0]["seller"]
        for key in MAP_LOCATION_KEYS:
            assert key not in seller, f"{key} leaked through GET /api/cars seller embed"

    def test_cars_alias_seller_has_no_map_location(
        self, client, dealer_ctx, dealer_car_ctx
    ):
        # `/cars` (legacy alias) overwrites `id` with the numeric DB id
        # instead of `public_id` (see get_cars_alias()), so look the listing
        # up directly via its `?id=` support instead of matching by id.
        resp = client.get(f"/cars?id={dealer_car_ctx}")
        assert resp.status_code == 200, resp.data
        car = resp.get_json()
        seller = car["seller"]
        for key in MAP_LOCATION_KEYS:
            assert key not in seller, f"{key} leaked through GET /cars seller embed"

    def test_api_car_detail_seller_has_no_map_location_for_anonymous_viewer(
        self, client, dealer_car_ctx
    ):
        resp = client.get(f"/api/cars/{dealer_car_ctx}")
        assert resp.status_code == 200, resp.data
        seller = resp.get_json()["car"]["seller"]
        for key in MAP_LOCATION_KEYS:
            assert key not in seller, f"{key} leaked through GET /api/cars/<id> seller embed"


# ---------------------------------------------------------------------------
# E. Favorites: no exact coordinates
# ---------------------------------------------------------------------------


class TestFavoritesSellerEmbedHidesCoordinates:
    def test_favorites_seller_has_no_map_location(
        self, client, dealer_car_ctx, buyer_ctx
    ):
        username, _public_id = buyer_ctx
        token = _login(client, username)
        fav_resp = client.post(
            f"/api/cars/{dealer_car_ctx}/favorite", headers=_auth(token)
        )
        assert fav_resp.status_code == 200, fav_resp.data

        resp = client.get("/api/user/favorites", headers=_auth(token))
        assert resp.status_code == 200, resp.data
        cars = resp.get_json()["cars"]
        matches = [c for c in cars if c.get("id") == dealer_car_ctx]
        assert matches, "expected the dealer's listing in /api/user/favorites"
        seller = matches[0]["seller"]
        for key in MAP_LOCATION_KEYS:
            assert key not in seller, f"{key} leaked through GET /api/user/favorites seller embed"


# ---------------------------------------------------------------------------
# F. Owner/admin behavior unchanged: exact coordinates still present
# ---------------------------------------------------------------------------


class TestPrivateSellerEmbedKeepsExactCoordinates:
    def test_owner_viewing_own_car_still_sees_exact_seller_coordinates(
        self, client, dealer_ctx, dealer_car_ctx
    ):
        username, _public_id, _dealer_id = dealer_ctx
        token = _login(client, username)
        resp = client.get(f"/api/cars/{dealer_car_ctx}", headers=_auth(token))
        assert resp.status_code == 200, resp.data
        seller = resp.get_json()["car"]["seller"]
        assert seller["dealership_latitude"] == DEALER_LATITUDE
        assert seller["dealership_longitude"] == DEALER_LONGITUDE

    def test_admin_my_listings_style_view_still_sees_exact_seller_coordinates(
        self, client, admin_ctx, dealer_car_ctx
    ):
        username, _public_id = admin_ctx
        token = _login(client, username)
        resp = client.get(f"/api/cars/{dealer_car_ctx}", headers=_auth(token))
        assert resp.status_code == 200, resp.data
        seller = resp.get_json()["car"]["seller"]
        assert seller["dealership_latitude"] == DEALER_LATITUDE
        assert seller["dealership_longitude"] == DEALER_LONGITUDE
