"""CarNet V1 fix 5 regression tests: listings owned by a deactivated/banned
seller must disappear from every public surface, while remaining intact and
inspectable by admins/the owner.

Verified defect (final release-candidate audit): admin "Deactivate account"
only flips ``User.is_active``. Public listing visibility
(``kk/listing_visibility.py``) never considered ``seller.is_active``, so a
deactivated seller's ``active``/``sold`` listings stayed fully visible and
contactable on every public surface:

- ``GET /api/cars``            (browse/search, paginated)
- ``GET /cars``                (legacy alias, bare list)
- ``GET /api/cars/<id>``       (listing detail)
- ``GET /api/cars/<id>/contact`` (reveal contact phone)
- ``GET /api/dealers/<public_id>`` (dealer/public profile listings)

Fix: ``listing_is_public()`` now also checks ``seller.is_active``, and
``public_listings_filter()`` / ``listings_visible_to_viewer_filter()`` now
JOIN ``User`` and filter on ``User.is_active.is_(True)`` at the SQL level.
This is centralized in ``kk/listing_visibility.py`` so every caller (browse,
search, facets, dealer profile, contact reveal, favorites, recently-viewed,
saved-search alerts, chat listing previews) picks it up automatically.

These tests exercise the real HTTP endpoints end-to-end against a real
SQLite-backed SQLAlchemy session (no query/ORM mocking), matching the
project's existing BE-1x / fix1-4 regression-test style.
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
    tmp = tempfile.TemporaryDirectory(prefix="carlist_fix5_", ignore_cleanup_errors=True)
    os.environ["APP_ENV"] = "testing"
    os.environ["SMS_PROVIDER"] = "console"
    os.environ.pop("LISTING_REQUIRE_APPROVAL", None)
    os.environ["DB_PATH"] = os.path.join(tmp.name, "fix5.db")

    from kk.app_factory import create_app

    app, _socketio, *_ = create_app()
    from kk.models import Car, User, db
    from kk.time_utils import utcnow

    with app.app_context():
        db.drop_all()
        db.create_all()

    yield app, app.test_client(), db, User, Car, utcnow

    with app.app_context():
        db.session.remove()
        db.engine.dispose()
    tmp.cleanup()


@pytest.fixture
def client(app_ctx):
    return app_ctx[1]


def _unique_phone() -> str:
    return f"077{uuid.uuid4().int % 10**8:08d}"


def _make_seller(app_ctx, *, is_active: bool = True, account_type: str = "individual"):
    """Create a seller (individual or approved dealer). Returns (public_id, id)."""
    app, _client, db, User, _Car, _utcnow = app_ctx
    username = f"fix5_seller_{uuid.uuid4().hex[:8]}"
    kwargs = dict(
        username=username,
        phone_number=_unique_phone(),
        first_name="Seller",
        last_name="Test",
        email=None,
        is_active=is_active,
        is_verified=True,
        phone_verified=True,
        public_id=f"pub-{uuid.uuid4().hex[:12]}",
        account_type=account_type,
    )
    if account_type == "dealer":
        kwargs.update(
            dealer_status="approved",
            dealership_name=f"Cars {uuid.uuid4().hex[:6]}",
            dealership_location="Erbil",
        )
    with app.app_context():
        user = User(**kwargs)
        user.set_password("Aa123456!")
        db.session.add(user)
        db.session.commit()
        return user.public_id, user.id


def _make_car(app_ctx, seller_id: int, *, status: str = "active", is_active: bool = True) -> tuple[str, int]:
    """Create one car owned by ``seller_id``. Returns ``(public_id, numeric_id)``."""
    app, _client, db, _User, Car, _utcnow = app_ctx
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
            is_active=is_active,
            status=status,
        )
        db.session.add(car)
        db.session.commit()
        return car.public_id, car.id


def _deactivate(app_ctx, user_id: int) -> None:
    app, _client, db, User, _Car, _utcnow = app_ctx
    with app.app_context():
        user = User.query.get(user_id)
        user.is_active = False
        db.session.commit()


def _login_token(app_ctx, client, user_id: int) -> str:
    from flask_jwt_extended import create_access_token

    app, _client, _db, _User, _Car, _utcnow = app_ctx
    with app.app_context():
        return create_access_token(identity=str(user_id))


def _auth(token: str) -> dict:
    return {"Authorization": f"Bearer {token}"}


# ---------------------------------------------------------------------------
# A. Browse / search (GET /api/cars, GET /cars) exclude deactivated sellers
# ---------------------------------------------------------------------------


class TestBrowseAndSearchExcludeDeactivatedSeller:
    def test_active_seller_listing_appears_in_browse(self, app_ctx, client):
        _public_id, seller_id = _make_seller(app_ctx)
        car_public_id, _car_num_id = _make_car(app_ctx, seller_id)

        resp = client.get("/api/cars")
        assert resp.status_code == 200, resp.data
        # `GET /api/cars` (the main browse endpoint) keeps `Car.to_dict()`'s
        # `id` field as the public_id (only the legacy `/cars` alias below
        # swaps it for the numeric db id).
        ids = [c["id"] for c in resp.get_json()["cars"]]
        assert car_public_id in ids

    def test_deactivated_seller_listing_disappears_from_browse(self, app_ctx, client):
        _public_id, seller_id = _make_seller(app_ctx)
        car_public_id, _car_num_id = _make_car(app_ctx, seller_id)
        _deactivate(app_ctx, seller_id)

        resp = client.get("/api/cars")
        assert resp.status_code == 200, resp.data
        ids = [c["id"] for c in resp.get_json()["cars"]]
        assert car_public_id not in ids

    def test_deactivated_seller_listing_disappears_from_search_query(self, app_ctx, client):
        """Same visibility rule must hold with search/filter params applied,
        not just the unfiltered default browse query."""
        _public_id, seller_id = _make_seller(app_ctx)
        car_public_id, _car_num_id = _make_car(app_ctx, seller_id)
        _deactivate(app_ctx, seller_id)

        resp = client.get("/api/cars?brand=toyota&q=corolla")
        assert resp.status_code == 200, resp.data
        ids = [c["id"] for c in resp.get_json()["cars"]]
        assert car_public_id not in ids

    def test_deactivated_seller_listing_disappears_from_legacy_alias(self, app_ctx, client):
        _public_id, seller_id = _make_seller(app_ctx)
        _car_public_id, car_num_id = _make_car(app_ctx, seller_id)
        _deactivate(app_ctx, seller_id)

        resp = client.get("/cars")
        assert resp.status_code == 200, resp.data
        # The legacy alias overrides `id` with the numeric db id for its
        # bare-list response.
        ids = [c["id"] for c in resp.get_json()]
        assert car_num_id not in ids

    def test_reactivating_seller_restores_listing_to_browse(self, app_ctx, client):
        """Deactivation only hides via visibility rules -- it must not
        delete/alter the listing, so reactivation naturally restores it."""
        app, _client, db, User, _Car, _utcnow = app_ctx
        _public_id, seller_id = _make_seller(app_ctx)
        car_public_id, _car_num_id = _make_car(app_ctx, seller_id)
        _deactivate(app_ctx, seller_id)

        resp = client.get("/api/cars")
        ids = [c["id"] for c in resp.get_json()["cars"]]
        assert car_public_id not in ids

        with app.app_context():
            User.query.get(seller_id).is_active = True
            db.session.commit()

        resp = client.get("/api/cars")
        ids = [c["id"] for c in resp.get_json()["cars"]]
        assert car_public_id in ids


# ---------------------------------------------------------------------------
# B. Listing detail + contact reveal return 404 for a deactivated seller
# ---------------------------------------------------------------------------


class TestDetailAndContactHideDeactivatedSeller:
    def test_detail_404s_for_anonymous_viewer_once_seller_deactivated(self, app_ctx, client):
        _public_id, seller_id = _make_seller(app_ctx)
        car_public_id, _car_num_id = _make_car(app_ctx, seller_id)

        ok = client.get(f"/api/cars/{car_public_id}")
        assert ok.status_code == 200, ok.data

        _deactivate(app_ctx, seller_id)

        resp = client.get(f"/api/cars/{car_public_id}")
        assert resp.status_code == 404, resp.data

    def test_contact_404s_for_anonymous_viewer_once_seller_deactivated(self, app_ctx, client):
        _public_id, seller_id = _make_seller(app_ctx)
        car_public_id, _car_num_id = _make_car(app_ctx, seller_id)
        _deactivate(app_ctx, seller_id)

        resp = client.get(f"/api/cars/{car_public_id}/contact")
        assert resp.status_code == 404, resp.data

    def test_detail_still_visible_to_admin_when_deactivated(self, app_ctx, client):
        """Admins must still be able to inspect/moderate a deactivated
        seller's listings -- the ``User.is_admin`` branch in
        ``listing_visible_to_viewer()`` bypasses the seller-active check."""
        app, _client, db, User, _Car, _utcnow = app_ctx
        _public_id, seller_id = _make_seller(app_ctx)
        car_public_id, _car_num_id = _make_car(app_ctx, seller_id)
        _deactivate(app_ctx, seller_id)

        _admin_public_id, admin_id = _make_seller(app_ctx)
        with app.app_context():
            User.query.get(admin_id).is_admin = True
            db.session.commit()
        token = _login_token(app_ctx, client, admin_id)

        resp = client.get(f"/api/cars/{car_public_id}", headers=_auth(token))
        assert resp.status_code == 200, resp.data
        assert resp.get_json()["car"]["id"] == car_public_id

    def test_deactivated_seller_cannot_authenticate_to_view_own_listing(self, app_ctx, client):
        """A deactivated seller's own JWT no longer resolves to a user at
        all (``get_current_user()`` already filters on ``is_active`` --
        see fix 4), so they hit the exact same anonymous-viewer 404 as
        everyone else. Their listing row itself is left completely intact
        in the database (checked directly, bypassing the API)."""
        app, _client, db, _User, Car, _utcnow = app_ctx
        _public_id, seller_id = _make_seller(app_ctx)
        car_public_id, _car_num_id = _make_car(app_ctx, seller_id)
        _deactivate(app_ctx, seller_id)
        token = _login_token(app_ctx, client, seller_id)

        resp = client.get(f"/api/cars/{car_public_id}", headers=_auth(token))
        assert resp.status_code == 404, resp.data

        with app.app_context():
            car = Car.query.filter_by(public_id=car_public_id).first()
            assert car is not None
            assert car.seller_id == seller_id
            assert car.status == "active"


# ---------------------------------------------------------------------------
# C. Dealer public profile hides listings once the dealer is deactivated
# ---------------------------------------------------------------------------


class TestDealerProfileHidesDeactivatedDealerListings:
    def test_dealer_profile_listings_visible_while_active(self, app_ctx, client):
        public_id, dealer_id = _make_seller(app_ctx, account_type="dealer")
        car_public_id, _car_num_id = _make_car(app_ctx, dealer_id)

        resp = client.get(f"/api/dealers/{public_id}")
        assert resp.status_code == 200, resp.data
        ids = [c["id"] for c in resp.get_json()["listings"]]
        assert car_public_id in ids

    def test_dealer_profile_returns_404_once_dealer_deactivated(self, app_ctx, client):
        """`dealer_profile()` already gates on `dealer.is_active` at the
        route level before even building the listings query."""
        public_id, dealer_id = _make_seller(app_ctx, account_type="dealer")
        _make_car(app_ctx, dealer_id)
        _deactivate(app_ctx, dealer_id)

        resp = client.get(f"/api/dealers/{public_id}")
        assert resp.status_code == 404, resp.data


# ---------------------------------------------------------------------------
# D. listing_visibility helpers: unit-level correctness
# ---------------------------------------------------------------------------


class TestListingVisibilityHelpersDirectly:
    def test_listing_is_public_false_once_seller_deactivated(self, app_ctx):
        app, _client, db, User, Car, _utcnow = app_ctx
        _public_id, seller_id = _make_seller(app_ctx)
        car_public_id, _car_num_id = _make_car(app_ctx, seller_id)
        _deactivate(app_ctx, seller_id)

        from sqlalchemy.orm import joinedload

        from kk.listing_visibility import listing_is_public

        with app.app_context():
            car = Car.query.options(joinedload(Car.seller)).filter_by(public_id=car_public_id).first()
            assert listing_is_public(car) is False

    def test_listing_is_public_true_for_car_with_no_loaded_seller_attr_default(self, app_ctx):
        """A car object with no ``seller`` relationship attached at all
        (e.g. ``getattr`` default) must not be treated as hidden -- only an
        actually-deactivated seller should hide a listing."""
        from kk.listing_visibility import listing_is_public

        class _FakeCarNoSeller:
            status = "active"
            seller = None

        assert listing_is_public(_FakeCarNoSeller()) is True

    def test_public_listings_filter_excludes_deactivated_seller_at_sql_level(self, app_ctx):
        app, _client, db, _User, Car, _utcnow = app_ctx
        _public_id, seller_id = _make_seller(app_ctx)
        car_public_id, _car_num_id = _make_car(app_ctx, seller_id)
        _deactivate(app_ctx, seller_id)

        from kk.listing_visibility import public_listings_filter

        with app.app_context():
            results = public_listings_filter(
                Car.query.filter(Car.public_id == car_public_id)
            ).all()
            assert results == []
