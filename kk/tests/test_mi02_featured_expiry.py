"""MI-02 regression tests: featured_until + expiry beat job.

PRODUCTION_AUDIT.md MI-02: ``Car.is_featured`` had no expiry -- once an
admin turned it on, a listing stayed featured forever (no ``featured_until``
column, no un-feature job). These tests cover the fix end-to-end against a
real SQLite-backed SQLAlchemy session (no query/ORM mocking), matching the
project's existing regression-test style (see ``test_be01_...py``,
``test_d01_...py``):

A. Model / serialization -- ``Car.to_dict()`` exposes ``featured_until`` and
   an *effective* ``is_featured``.
B. Query ordering -- ``GET /api/cars`` (both the default/newest ordering
   helper and the "recommended"/interest ordering helper) ranks expired
   featured listings exactly like ordinary listings.
C/D. Admin single + bulk status endpoints -- ``featured_until`` payload
   handling, validation, and PATCH-semantics (an unrelated field update must
   not erase an existing future expiry).
E. The Celery cleanup task (``kk.tasks.listing_tasks.clear_expired_featured_listings``)
   -- data-hygiene denormalization, not the correctness mechanism.
F. Production counts/filters (`admin dashboard `featured_cars`, admin
   ``GET /api/admin/cars?is_featured=``) reflect effective, not raw, status.

Dealer/user featuring (``User.is_featured_dealer`` / ``DealerProfile.is_featured``)
is out of scope for MI-02 and is not touched or tested here.
"""

from __future__ import annotations

import os
import sys
import tempfile
import uuid
from datetime import timedelta
from pathlib import Path

import pytest

_REPO_ROOT = Path(__file__).resolve().parents[2]
if str(_REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(_REPO_ROOT))

_PASSWORD = "Aa123456!"


@pytest.fixture(scope="module")
def app_ctx():
    tmp = tempfile.TemporaryDirectory(prefix="carlist_mi02_", ignore_cleanup_errors=True)
    os.environ["APP_ENV"] = "testing"
    os.environ["SMS_PROVIDER"] = "console"
    os.environ.pop("LISTING_REQUIRE_APPROVAL", None)
    os.environ["DB_PATH"] = os.path.join(tmp.name, "mi02.db")

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


def _unique_brand() -> str:
    return f"mi02brand{uuid.uuid4().hex[:10]}"


def _make_car(app, db, seller_id: int, **extra):
    from kk.models import Car

    extra.setdefault("brand", "toyota")
    with app.app_context():
        car = Car(
            seller_id=seller_id,
            public_id=f"car-{uuid.uuid4().hex[:12]}",
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
            status="active",
            **extra,
        )
        db.session.add(car)
        db.session.commit()
        return car.id, car.public_id


# ---------------------------------------------------------------------------
# A. Model / serialization
# ---------------------------------------------------------------------------


class TestSerialization:
    def test_featured_until_serialized_iso_or_null(self, app_ctx):
        app, _c, db, _User, Car, utcnow = app_ctx
        seller_id, _p, _n = _make_user(app, db)
        future = utcnow() + timedelta(days=1)

        car_id, _pub = _make_car(app, db, seller_id, is_featured=True, featured_until=future)
        with app.app_context():
            car = db.session.get(Car, car_id)
            assert car.to_dict()["featured_until"] == future.isoformat()

        car_id2, _pub2 = _make_car(app, db, seller_id, is_featured=True, featured_until=None)
        with app.app_context():
            car = db.session.get(Car, car_id2)
            assert car.to_dict()["featured_until"] is None

    def test_future_featured_serializes_is_featured_true(self, app_ctx):
        app, _c, db, _User, Car, utcnow = app_ctx
        seller_id, _p, _n = _make_user(app, db)
        future = utcnow() + timedelta(days=1)
        car_id, _pub = _make_car(app, db, seller_id, is_featured=True, featured_until=future)
        with app.app_context():
            car = db.session.get(Car, car_id)
            assert car.to_dict()["is_featured"] is True

    def test_expired_featured_serializes_is_featured_false(self, app_ctx):
        app, _c, db, _User, Car, utcnow = app_ctx
        seller_id, _p, _n = _make_user(app, db)
        past = utcnow() - timedelta(days=1)
        car_id, _pub = _make_car(app, db, seller_id, is_featured=True, featured_until=past)
        with app.app_context():
            car = db.session.get(Car, car_id)
            data = car.to_dict()
            assert data["is_featured"] is False
            # Serialization computes effective status; the raw column is
            # untouched here -- only the (separate) cleanup task flips it.
            assert car.is_featured is True
            assert data["featured_until"] == past.isoformat()

    def test_indefinite_featured_remains_true(self, app_ctx):
        app, _c, db, _User, Car, _utcnow = app_ctx
        seller_id, _p, _n = _make_user(app, db)
        car_id, _pub = _make_car(app, db, seller_id, is_featured=True, featured_until=None)
        with app.app_context():
            car = db.session.get(Car, car_id)
            assert car.to_dict()["is_featured"] is True

    def test_raw_not_featured_stays_false_regardless_of_expiry(self, app_ctx):
        app, _c, db, _User, Car, utcnow = app_ctx
        seller_id, _p, _n = _make_user(app, db)
        future = utcnow() + timedelta(days=1)
        car_id, _pub = _make_car(app, db, seller_id, is_featured=False, featured_until=future)
        with app.app_context():
            car = db.session.get(Car, car_id)
            assert car.to_dict()["is_featured"] is False


# ---------------------------------------------------------------------------
# B. Query ordering
# ---------------------------------------------------------------------------


class TestOrdering:
    def test_future_featured_sorts_above_ordinary_newest(self, app_ctx, client):
        app, _c, db, _User, _Car, utcnow = app_ctx
        seller_id, seller_pub, _n = _make_user(app, db)
        base = utcnow()
        _make_car(app, db, seller_id, is_featured=False, created_at=base)
        future = base + timedelta(days=1)
        _fid, featured_pub = _make_car(
            app, db, seller_id, is_featured=True, featured_until=future,
            created_at=base - timedelta(minutes=5),
        )

        resp = client.get(f"/api/cars?seller_public_id={seller_pub}&sort_by=newest&per_page=50")
        assert resp.status_code == 200, resp.data
        cars = resp.get_json()["cars"]
        assert len(cars) == 2
        assert cars[0]["id"] == featured_pub

    def test_indefinite_featured_sorts_above_ordinary(self, app_ctx, client):
        app, _c, db, _User, _Car, utcnow = app_ctx
        seller_id, seller_pub, _n = _make_user(app, db)
        base = utcnow()
        _make_car(app, db, seller_id, is_featured=False, created_at=base)
        _fid, featured_pub = _make_car(
            app, db, seller_id, is_featured=True, featured_until=None,
            created_at=base - timedelta(minutes=5),
        )

        resp = client.get(f"/api/cars?seller_public_id={seller_pub}&sort_by=newest&per_page=50")
        assert resp.status_code == 200, resp.data
        cars = resp.get_json()["cars"]
        assert cars[0]["id"] == featured_pub

    def test_expired_featured_does_not_get_priority(self, app_ctx, client):
        app, _c, db, _User, _Car, utcnow = app_ctx
        seller_id, seller_pub, _n = _make_user(app, db)
        base = utcnow()
        # Expired-featured listing is OLDER; ordinary listing is NEWER.
        # If expiry were ignored, the (older) expired-featured listing would
        # still rank first. It must not.
        past = base - timedelta(hours=1)
        _eid, expired_pub = _make_car(
            app, db, seller_id, is_featured=True, featured_until=past,
            created_at=base - timedelta(minutes=10),
        )
        _oid, ordinary_pub = _make_car(app, db, seller_id, is_featured=False, created_at=base)

        resp = client.get(f"/api/cars?seller_public_id={seller_pub}&sort_by=newest&per_page=50")
        assert resp.status_code == 200, resp.data
        cars = resp.get_json()["cars"]
        assert [c["id"] for c in cars] == [ordinary_pub, expired_pub]

    def test_recommended_interest_ordering_respects_effective_featured(self, app_ctx, client):
        """Covers `_apply_interest_ordering()` -- the second ordering helper
        (`sort_by=recommended`) must apply the exact same effective-featured
        semantics as the default/newest helper."""
        app, _c, db, _User, _Car, utcnow = app_ctx
        seller_id, seller_pub, _n = _make_user(app, db)
        brand = _unique_brand()
        base = utcnow()
        past = base - timedelta(hours=1)
        _eid, expired_pub = _make_car(
            app, db, seller_id, brand=brand, is_featured=True, featured_until=past,
            created_at=base - timedelta(minutes=10),
        )
        _oid, ordinary_pub = _make_car(app, db, seller_id, brand=brand, is_featured=False, created_at=base)

        resp = client.get(
            f"/api/cars?seller_public_id={seller_pub}&sort_by=recommended"
            f"&prefer_brand={brand}&per_page=50"
        )
        assert resp.status_code == 200, resp.data
        cars = resp.get_json()["cars"]
        assert [c["id"] for c in cars] == [ordinary_pub, expired_pub]


# ---------------------------------------------------------------------------
# C. Admin single-car status update
# ---------------------------------------------------------------------------


class TestAdminSingleUpdate:
    def test_can_set_future_featured_until(self, app_ctx, client):
        app, _c, db, _User, Car, utcnow = app_ctx
        _admin_id, _ap, admin_name = _make_user(app, db, is_admin=True)
        seller_id, _sp, _sn = _make_user(app, db)
        car_id, car_pub = _make_car(app, db, seller_id, is_featured=False)

        token = _login(client, admin_name)
        future_iso = (utcnow() + timedelta(days=3)).isoformat()
        resp = client.patch(
            f"/api/admin/cars/{car_pub}/status",
            json={"is_featured": True, "featured_until": future_iso},
            headers=_auth(token),
        )
        assert resp.status_code == 200, resp.data
        body = resp.get_json()["car"]
        assert body["is_featured"] is True
        assert body["featured_until"] == future_iso
        with app.app_context():
            car = db.session.get(Car, car_id)
            assert car.is_featured is True
            assert car.featured_until.isoformat() == future_iso

    def test_invalid_datetime_rejected(self, app_ctx, client):
        app, _c, db, _User, Car, _utcnow = app_ctx
        _admin_id, _ap, admin_name = _make_user(app, db, is_admin=True)
        seller_id, _sp, _sn = _make_user(app, db)
        car_id, car_pub = _make_car(app, db, seller_id, is_featured=False)

        token = _login(client, admin_name)
        resp = client.patch(
            f"/api/admin/cars/{car_pub}/status",
            json={"is_featured": True, "featured_until": "not-a-date"},
            headers=_auth(token),
        )
        assert resp.status_code == 400, resp.data
        with app.app_context():
            car = db.session.get(Car, car_id)
            assert car.is_featured is False
            assert car.featured_until is None

    def test_past_expiry_rejected_when_newly_featuring(self, app_ctx, client):
        app, _c, db, _User, Car, utcnow = app_ctx
        _admin_id, _ap, admin_name = _make_user(app, db, is_admin=True)
        seller_id, _sp, _sn = _make_user(app, db)
        car_id, car_pub = _make_car(app, db, seller_id, is_featured=False)

        token = _login(client, admin_name)
        past_iso = (utcnow() - timedelta(days=1)).isoformat()
        resp = client.patch(
            f"/api/admin/cars/{car_pub}/status",
            json={"is_featured": True, "featured_until": past_iso},
            headers=_auth(token),
        )
        assert resp.status_code == 400, resp.data
        with app.app_context():
            car = db.session.get(Car, car_id)
            assert car.is_featured is False
            assert car.featured_until is None

    def test_setting_is_featured_false_clears_expiry(self, app_ctx, client):
        app, _c, db, _User, Car, utcnow = app_ctx
        _admin_id, _ap, admin_name = _make_user(app, db, is_admin=True)
        seller_id, _sp, _sn = _make_user(app, db)
        future = utcnow() + timedelta(days=1)
        car_id, car_pub = _make_car(app, db, seller_id, is_featured=True, featured_until=future)

        token = _login(client, admin_name)
        resp = client.patch(
            f"/api/admin/cars/{car_pub}/status",
            json={"is_featured": False},
            headers=_auth(token),
        )
        assert resp.status_code == 200, resp.data
        with app.app_context():
            car = db.session.get(Car, car_id)
            assert car.is_featured is False
            assert car.featured_until is None

    def test_setting_is_featured_false_clears_expiry_even_if_payload_also_sends_one(
        self, app_ctx, client
    ):
        """is_featured=false must win over a simultaneously-supplied
        featured_until -- clearing is unconditional, not merely "clear if
        featured_until omitted"."""
        app, _c, db, _User, Car, utcnow = app_ctx
        _admin_id, _ap, admin_name = _make_user(app, db, is_admin=True)
        seller_id, _sp, _sn = _make_user(app, db)
        car_id, car_pub = _make_car(app, db, seller_id, is_featured=True)

        token = _login(client, admin_name)
        future_iso = (utcnow() + timedelta(days=1)).isoformat()
        resp = client.patch(
            f"/api/admin/cars/{car_pub}/status",
            json={"is_featured": False, "featured_until": future_iso},
            headers=_auth(token),
        )
        assert resp.status_code == 200, resp.data
        with app.app_context():
            car = db.session.get(Car, car_id)
            assert car.is_featured is False
            assert car.featured_until is None

    def test_unrelated_patch_without_featured_until_preserves_existing_expiry(
        self, app_ctx, client
    ):
        app, _c, db, _User, Car, utcnow = app_ctx
        _admin_id, _ap, admin_name = _make_user(app, db, is_admin=True)
        seller_id, _sp, _sn = _make_user(app, db)
        future = utcnow() + timedelta(days=2)
        car_id, car_pub = _make_car(app, db, seller_id, is_featured=True, featured_until=future)

        token = _login(client, admin_name)
        resp = client.patch(
            f"/api/admin/cars/{car_pub}/status",
            json={"is_active": False},
            headers=_auth(token),
        )
        assert resp.status_code == 200, resp.data
        with app.app_context():
            car = db.session.get(Car, car_id)
            assert car.is_active is False
            assert car.is_featured is True
            assert car.featured_until is not None
            assert car.featured_until.isoformat() == future.isoformat()


# ---------------------------------------------------------------------------
# D. Admin bulk status update
# ---------------------------------------------------------------------------


class TestAdminBulkUpdate:
    def test_bulk_applies_valid_future_expiry(self, app_ctx, client):
        app, _c, db, _User, Car, utcnow = app_ctx
        _admin_id, _ap, admin_name = _make_user(app, db, is_admin=True)
        seller_id, _sp, _sn = _make_user(app, db)
        _id1, pub1 = _make_car(app, db, seller_id, is_featured=False)
        _id2, pub2 = _make_car(app, db, seller_id, is_featured=False)

        token = _login(client, admin_name)
        future_iso = (utcnow() + timedelta(days=5)).isoformat()
        resp = client.post(
            "/api/admin/cars/bulk-status",
            json={"ids": [pub1, pub2], "is_featured": True, "featured_until": future_iso},
            headers=_auth(token),
        )
        assert resp.status_code == 200, resp.data
        with app.app_context():
            for cid in (_id1, _id2):
                car = db.session.get(Car, cid)
                assert car.is_featured is True
                assert car.featured_until.isoformat() == future_iso

    def test_bulk_disabling_featured_clears_expiry(self, app_ctx, client):
        app, _c, db, _User, Car, utcnow = app_ctx
        _admin_id, _ap, admin_name = _make_user(app, db, is_admin=True)
        seller_id, _sp, _sn = _make_user(app, db)
        future = utcnow() + timedelta(days=1)
        _id1, pub1 = _make_car(app, db, seller_id, is_featured=True, featured_until=future)
        _id2, pub2 = _make_car(app, db, seller_id, is_featured=True, featured_until=None)

        token = _login(client, admin_name)
        resp = client.post(
            "/api/admin/cars/bulk-status",
            json={"ids": [pub1, pub2], "is_featured": False},
            headers=_auth(token),
        )
        assert resp.status_code == 200, resp.data
        with app.app_context():
            for cid in (_id1, _id2):
                car = db.session.get(Car, cid)
                assert car.is_featured is False
                assert car.featured_until is None

    def test_bulk_malformed_expiry_rejected(self, app_ctx, client):
        app, _c, db, _User, Car, _utcnow = app_ctx
        _admin_id, _ap, admin_name = _make_user(app, db, is_admin=True)
        seller_id, _sp, _sn = _make_user(app, db)
        _id1, pub1 = _make_car(app, db, seller_id, is_featured=False)

        token = _login(client, admin_name)
        resp = client.post(
            "/api/admin/cars/bulk-status",
            json={"ids": [pub1], "is_featured": True, "featured_until": "garbage"},
            headers=_auth(token),
        )
        assert resp.status_code == 400, resp.data
        with app.app_context():
            car = db.session.get(Car, _id1)
            assert car.is_featured is False
            assert car.featured_until is None

    def test_bulk_past_expiry_rejected(self, app_ctx, client):
        app, _c, db, _User, Car, utcnow = app_ctx
        _admin_id, _ap, admin_name = _make_user(app, db, is_admin=True)
        seller_id, _sp, _sn = _make_user(app, db)
        _id1, pub1 = _make_car(app, db, seller_id, is_featured=False)

        token = _login(client, admin_name)
        past_iso = (utcnow() - timedelta(days=1)).isoformat()
        resp = client.post(
            "/api/admin/cars/bulk-status",
            json={"ids": [pub1], "is_featured": True, "featured_until": past_iso},
            headers=_auth(token),
        )
        assert resp.status_code == 400, resp.data
        with app.app_context():
            car = db.session.get(Car, _id1)
            assert car.is_featured is False
            assert car.featured_until is None


# ---------------------------------------------------------------------------
# E. Celery cleanup task
# ---------------------------------------------------------------------------


class TestCleanupTask:
    def _run_task(self, app, monkeypatch):
        from kk.tasks import celery_app as celery_app_module
        from kk.tasks.listing_tasks import clear_expired_featured_listings

        monkeypatch.setattr(celery_app_module, "get_celery_flask_app", lambda: app)
        return clear_expired_featured_listings.apply()

    def test_expired_featured_is_cleared(self, app_ctx, monkeypatch):
        app, _c, db, _User, Car, utcnow = app_ctx
        seller_id, _p, _n = _make_user(app, db)
        past = utcnow() - timedelta(hours=1)
        car_id, _pub = _make_car(app, db, seller_id, is_featured=True, featured_until=past)

        result = self._run_task(app, monkeypatch)
        assert result.successful(), result.result

        with app.app_context():
            car = db.session.get(Car, car_id)
            assert car.is_featured is False
            assert car.featured_until is None

    def test_future_featured_unchanged(self, app_ctx, monkeypatch):
        app, _c, db, _User, Car, utcnow = app_ctx
        seller_id, _p, _n = _make_user(app, db)
        future = utcnow() + timedelta(days=1)
        car_id, _pub = _make_car(app, db, seller_id, is_featured=True, featured_until=future)

        self._run_task(app, monkeypatch)

        with app.app_context():
            car = db.session.get(Car, car_id)
            assert car.is_featured is True
            assert car.featured_until is not None
            assert car.featured_until.isoformat() == future.isoformat()

    def test_indefinite_featured_unchanged(self, app_ctx, monkeypatch):
        app, _c, db, _User, Car, _utcnow = app_ctx
        seller_id, _p, _n = _make_user(app, db)
        car_id, _pub = _make_car(app, db, seller_id, is_featured=True, featured_until=None)

        self._run_task(app, monkeypatch)

        with app.app_context():
            car = db.session.get(Car, car_id)
            assert car.is_featured is True
            assert car.featured_until is None

    def test_ordinary_listing_unchanged(self, app_ctx, monkeypatch):
        app, _c, db, _User, Car, _utcnow = app_ctx
        seller_id, _p, _n = _make_user(app, db)
        car_id, _pub = _make_car(app, db, seller_id, is_featured=False)

        self._run_task(app, monkeypatch)

        with app.app_context():
            car = db.session.get(Car, car_id)
            assert car.is_featured is False
            assert car.featured_until is None

    def test_second_run_is_harmless_and_idempotent(self, app_ctx, monkeypatch):
        app, _c, db, _User, Car, utcnow = app_ctx
        seller_id, _p, _n = _make_user(app, db)
        past = utcnow() - timedelta(hours=1)
        car_id, _pub = _make_car(app, db, seller_id, is_featured=True, featured_until=past)

        first = self._run_task(app, monkeypatch)
        assert first.result["cleared"] >= 1

        second = self._run_task(app, monkeypatch)
        assert second.successful()
        # The row is already cleared -- a second run must not error and
        # must not touch it again (no matching rows left for this car).
        with app.app_context():
            car = db.session.get(Car, car_id)
            assert car.is_featured is False
            assert car.featured_until is None


# ---------------------------------------------------------------------------
# F. Featured counts / filters
# ---------------------------------------------------------------------------


class TestFeaturedCountsAndFilters:
    def test_dashboard_featured_cars_count_excludes_expired(self, app_ctx, client):
        app, _c, db, _User, Car, utcnow = app_ctx
        _admin_id, _ap, admin_name = _make_user(app, db, is_admin=True)
        seller_id, _sp, _sn = _make_user(app, db)
        token = _login(client, admin_name)

        def _current_count() -> int:
            resp = client.get("/api/admin/dashboard", headers=_auth(token))
            assert resp.status_code == 200, resp.data
            return resp.get_json()["stats"]["featured_cars"]

        before = _current_count()

        past = utcnow() - timedelta(hours=1)
        _make_car(app, db, seller_id, is_featured=True, featured_until=past)  # expired
        after_expired_only = _current_count()
        assert after_expired_only == before, (
            "an expired featured listing must not count toward featured_cars"
        )

        future = utcnow() + timedelta(days=1)
        _make_car(app, db, seller_id, is_featured=True, featured_until=future)  # active
        after_both = _current_count()
        assert after_both == before + 1, (
            "a currently-active featured listing must count toward featured_cars"
        )

    def test_admin_cars_is_featured_filter_uses_effective_status(self, app_ctx, client):
        app, _c, db, _User, Car, utcnow = app_ctx
        _admin_id, _ap, admin_name = _make_user(app, db, is_admin=True)
        seller_id, _sp, _sn = _make_user(app, db)
        brand = _unique_brand()
        past = utcnow() - timedelta(hours=1)
        future = utcnow() + timedelta(days=1)
        _eid, expired_pub = _make_car(
            app, db, seller_id, brand=brand, is_featured=True, featured_until=past
        )
        _aid, active_pub = _make_car(
            app, db, seller_id, brand=brand, is_featured=True, featured_until=future
        )
        _nid, ordinary_pub = _make_car(app, db, seller_id, brand=brand, is_featured=False)

        token = _login(client, admin_name)

        resp_true = client.get(
            f"/api/admin/cars?search={brand}&is_featured=true", headers=_auth(token)
        )
        assert resp_true.status_code == 200, resp_true.data
        ids_true = {c["id"] for c in resp_true.get_json()["cars"]}
        assert ids_true == {active_pub}

        resp_false = client.get(
            f"/api/admin/cars?search={brand}&is_featured=false", headers=_auth(token)
        )
        assert resp_false.status_code == 200, resp_false.data
        ids_false = {c["id"] for c in resp_false.get_json()["cars"]}
        assert ids_false == {expired_pub, ordinary_pub}
