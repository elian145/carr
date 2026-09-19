"""BE-09b regression tests.

PRODUCTION_AUDIT.md BE-09b: ``GET /api/analytics/listings``
(``get_listings_analytics()`` in ``kk/routes/analytics.py``) loaded a
seller's cars and their ``ListingAnalytics`` rows with unbounded
``.all()`` calls -- a seller with an unusually large number of listings
would have every single one fully loaded/serialized in one response.

Fix: cap the driving ``Car`` query at ``_ANALYTICS_LISTINGS_CAP`` (200,
newest-first), mirroring the existing ``_MY_LISTINGS_COMPAT_CAP`` (BE-06) /
``_DEALER_PROFILE_LISTINGS_CAP`` (BE-01) precedent. Every subsequent
``.all()`` in the endpoint filters on ``car_id.in_(car_ids)``, so bounding
the id list bounds all of them. The bare-JSON-array response contract is
unchanged (no pagination envelope added).

These tests cover:
  - Under-cap: an ordinary seller gets analytics for every listing, as
    before.
  - Exact-cap and over-cap: the result is bounded to the cap, keeping the
    newest listings.
  - Authorization: only the requesting seller's own listings are ever
    returned, cap or no cap.
"""

from __future__ import annotations

import os
import sys
import tempfile
import uuid
from contextlib import contextmanager
from datetime import timedelta
from pathlib import Path

import pytest

_REPO_ROOT = Path(__file__).resolve().parents[2]
if str(_REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(_REPO_ROOT))

_PASSWORD = "Aa123456!"


@pytest.fixture(scope="module")
def app_ctx():
    tmp = tempfile.TemporaryDirectory(prefix="carlist_be09b_", ignore_cleanup_errors=True)
    os.environ["APP_ENV"] = "testing"
    os.environ["SMS_PROVIDER"] = "console"
    os.environ.pop("LISTING_REQUIRE_APPROVAL", None)
    os.environ["DB_PATH"] = os.path.join(tmp.name, "be09b.db")

    from kk.app_factory import create_app

    app, _socketio, *_ = create_app()
    from kk.models import Car, ListingAnalytics, User, db
    from kk.routes.analytics import _ANALYTICS_LISTINGS_CAP
    from kk.time_utils import utcnow

    with app.app_context():
        db.drop_all()
        db.create_all()

    yield app, app.test_client(), db, User, Car, ListingAnalytics, utcnow, _ANALYTICS_LISTINGS_CAP

    with app.app_context():
        db.session.remove()
        db.engine.dispose()
    tmp.cleanup()


@pytest.fixture
def client(app_ctx):
    return app_ctx[1]


@pytest.fixture
def cap(app_ctx):
    return app_ctx[7]


def _unique_phone() -> str:
    return f"077{uuid.uuid4().int % 10**8:08d}"


def _make_user(app_ctx, *, username: str) -> tuple[str, int]:
    app, _client, db, User, *_ = app_ctx
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
        user.set_password(_PASSWORD)
        db.session.add(user)
        db.session.commit()
        return user.public_id, user.id


def _login(client, username: str) -> str:
    r = client.post("/api/auth/login", json={"username": username, "password": _PASSWORD})
    assert r.status_code == 200, r.data
    return r.get_json()["access_token"]


def _auth(token: str) -> dict:
    return {"Authorization": f"Bearer {token}"}


def _make_cars(app_ctx, seller_id: int, count: int, *, tag: str = "car") -> list[int]:
    """Bulk-create ``count`` active cars owned by ``seller_id`` with
    strictly increasing ``created_at`` (oldest first). Returns numeric ids
    in creation order."""
    app, _client, db, _User, Car, *_ = app_ctx
    ids: list[int] = []
    with app.app_context():
        base = app_ctx[6]()
        for i in range(count):
            car = Car(
                seller_id=seller_id,
                public_id=f"{tag}-{uuid.uuid4().hex[:12]}",
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
                status="active",
                created_at=base + timedelta(minutes=i),
            )
            db.session.add(car)
            db.session.commit()
            ids.append(car.id)
    return ids


@contextmanager
def _count_queries(app_ctx):
    from sqlalchemy import event

    app = app_ctx[0]
    db = app_ctx[2]
    counter = {"n": 0}

    def _on_execute(*_args, **_kwargs):
        counter["n"] += 1

    with app.app_context():
        engine = db.engine
    event.listen(engine, "before_cursor_execute", _on_execute)
    try:
        yield counter
    finally:
        event.remove(engine, "before_cursor_execute", _on_execute)


# ---------------------------------------------------------------------------
# A. Under-cap: ordinary sellers still get expected analytics
# ---------------------------------------------------------------------------


class TestUnderCap:
    def test_all_listings_get_analytics_rows(self, app_ctx, client):
        username = f"be09b_ua_{uuid.uuid4().hex[:8]}"
        _public_id, seller_id = _make_user(app_ctx, username=username)
        ids = _make_cars(app_ctx, seller_id, 5)
        token = _login(client, username)

        resp = client.get("/api/analytics/listings", headers=_auth(token))
        assert resp.status_code == 200, resp.data
        body = resp.get_json()

        assert isinstance(body, list)
        assert len(body) == 5
        app, _client, db, _User, Car, *_ = app_ctx
        with app.app_context():
            public_ids = {c.public_id for c in Car.query.filter(Car.id.in_(ids)).all()}
        returned_listing_ids = {item["listing_id"] for item in body}
        assert returned_listing_ids == public_ids

    def test_empty_result_is_empty_list_for_seller_with_no_listings(self, app_ctx, client):
        username = f"be09b_empty_{uuid.uuid4().hex[:8]}"
        _public_id, _seller_id = _make_user(app_ctx, username=username)
        token = _login(client, username)

        resp = client.get("/api/analytics/listings", headers=_auth(token))
        assert resp.status_code == 200, resp.data
        assert resp.get_json() == []


# ---------------------------------------------------------------------------
# B. Result count is bounded (exact-cap and over-cap)
# ---------------------------------------------------------------------------


class TestBoundedResultCount:
    def test_exactly_cap_listings_returned(self, app_ctx, client, cap):
        username = f"be09b_eb_{uuid.uuid4().hex[:8]}"
        _public_id, seller_id = _make_user(app_ctx, username=username)
        _make_cars(app_ctx, seller_id, cap)
        token = _login(client, username)

        resp = client.get("/api/analytics/listings", headers=_auth(token))
        assert resp.status_code == 200, resp.data
        body = resp.get_json()
        assert isinstance(body, list)
        assert len(body) == cap

    def test_over_cap_result_is_bounded_to_newest_listings(self, app_ctx, client, cap):
        username = f"be09b_oc_{uuid.uuid4().hex[:8]}"
        _public_id, seller_id = _make_user(app_ctx, username=username)
        ids = _make_cars(app_ctx, seller_id, cap + 10)
        token = _login(client, username)

        resp = client.get("/api/analytics/listings", headers=_auth(token))
        assert resp.status_code == 200, resp.data
        body = resp.get_json()

        assert isinstance(body, list)
        assert len(body) == cap

        app, _client, db, _User, Car, *_ = app_ctx
        with app.app_context():
            oldest_10 = Car.query.filter(Car.id.in_(ids[:10])).all()
            oldest_10_public_ids = {c.public_id for c in oldest_10}

        returned_listing_ids = {item["listing_id"] for item in body}
        # The oldest 10 (beyond the cap) must be excluded entirely.
        assert not (returned_listing_ids & oldest_10_public_ids)

    def test_query_count_does_not_scale_past_the_cap(self, app_ctx, client, cap):
        """Regression guard: exceeding the cap must not blow up the query
        count/result size -- the capped id list bounds every subsequent
        `.all()` in the endpoint."""
        username = f"be09b_qc_{uuid.uuid4().hex[:8]}"
        _public_id, seller_id = _make_user(app_ctx, username=username)
        _make_cars(app_ctx, seller_id, cap + 25)
        token = _login(client, username)

        with _count_queries(app_ctx) as counter:
            resp = client.get("/api/analytics/listings", headers=_auth(token))
        assert resp.status_code == 200, resp.data
        assert len(resp.get_json()) == cap
        # A small, constant number of statements regardless of how far over
        # the cap the seller's real listing count is (bulk-create-missing +
        # the two capped SELECTs + eager-loaded relationships) -- not one
        # per extra listing.
        assert counter["n"] < 20, f"expected a small constant query count, got {counter['n']}"


# ---------------------------------------------------------------------------
# C. Authorization remains correct
# ---------------------------------------------------------------------------


class TestAuthorizationIsolation:
    def test_only_authenticated_sellers_own_listings_are_returned(self, app_ctx, client):
        username_a = f"be09b_a_{uuid.uuid4().hex[:8]}"
        username_b = f"be09b_b_{uuid.uuid4().hex[:8]}"
        _public_a, seller_a = _make_user(app_ctx, username=username_a)
        _public_b, seller_b = _make_user(app_ctx, username=username_b)
        ids_a = _make_cars(app_ctx, seller_a, 3, tag="carA")
        _make_cars(app_ctx, seller_b, 4, tag="carB")

        token_a = _login(client, username_a)
        resp = client.get("/api/analytics/listings", headers=_auth(token_a))
        assert resp.status_code == 200, resp.data
        body = resp.get_json()
        assert len(body) == 3

        app, _client, db, _User, Car, *_ = app_ctx
        with app.app_context():
            public_ids_a = {c.public_id for c in Car.query.filter(Car.id.in_(ids_a)).all()}
        returned_listing_ids = {item["listing_id"] for item in body}
        assert returned_listing_ids == public_ids_a

    def test_unauthenticated_request_is_rejected(self, client):
        resp = client.get("/api/analytics/listings")
        assert resp.status_code in (401, 422)

    def test_bounding_does_not_leak_other_sellers_listings_when_over_cap(
        self, app_ctx, client, cap
    ):
        """Even when one seller is over the cap, a different seller's
        (unrelated, small) listing set must never appear in their
        analytics response."""
        big_username = f"be09b_big_{uuid.uuid4().hex[:8]}"
        other_username = f"be09b_other_{uuid.uuid4().hex[:8]}"
        _big_public, big_seller = _make_user(app_ctx, username=big_username)
        _other_public, other_seller = _make_user(app_ctx, username=other_username)

        _make_cars(app_ctx, big_seller, cap + 5, tag="big")
        other_ids = _make_cars(app_ctx, other_seller, 2, tag="other")

        other_token = _login(client, other_username)
        resp = client.get("/api/analytics/listings", headers=_auth(other_token))
        assert resp.status_code == 200, resp.data
        body = resp.get_json()
        assert len(body) == 2

        app, _client, db, _User, Car, *_ = app_ctx
        with app.app_context():
            other_public_ids = {c.public_id for c in Car.query.filter(Car.id.in_(other_ids)).all()}
        returned_listing_ids = {item["listing_id"] for item in body}
        assert returned_listing_ids == other_public_ids
