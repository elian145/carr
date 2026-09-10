"""BE-06 regression tests: ``GET /api/my_listings`` (``compat_my_listings()``)
must not return an unbounded number of listings, and must not issue N+1 SQL
queries when serializing them.

Bug (PRODUCTION_AUDIT.md BE-06): the original implementation ran::

    cars = (
        Car.query.filter_by(seller_id=current_user.id, is_active=True)
        .order_by(Car.created_at.desc())
        .all()
    )
    result = []
    for car in cars:
        d = _with_media_compat(car)
        ...

with no ``.limit()`` at all -- a seller with an unusually large number of
active listings would have every single one fully serialized in one
response. ``_with_media_compat()`` (and the ``car.videos`` access right
below it) reads ``Car.images``, ``Car.videos``, and (via ``Car.to_dict()``)
``Car.seller`` -- three separately lazy-loaded relationships -- with no
eager-loading on the driving query, producing the classic N+1 pattern.

IMPORTANT ARCHITECTURE NOTE: ``GET /api/user/my-listings``
(``get_my_listings()``) is the properly paginated endpoint the real Flutter
"My Listings" screen actually uses. ``GET /api/my_listings``
(``compat_my_listings()``, tested here) is a *legacy* alias kept only for an
analytics fallback caller that strictly expects a bare JSON array response
(``[...]``, not ``{"cars": [...], "pagination": {...}}``). This fix therefore
does NOT add pagination params to this endpoint -- it adds a hard cap
(``_MY_LISTINGS_COMPAT_CAP = 200``, mirroring the ``_DEALER_PROFILE_LISTINGS_CAP``
precedent from BE-01 in ``kk/routes/user.py``) plus the missing
``selectinload(Car.images)`` / ``selectinload(Car.videos)`` /
``joinedload(Car.seller)`` eager-loading, while preserving:

  - ``seller_id=current_user.id`` and ``is_active=True`` filtering,
  - ``created_at DESC`` ordering,
  - the exact response fields (``numeric_id``, ``videos``, title fallback,
    media-compat fields, seller serialization),
  - the bare-JSON-array response contract,
  - existing authentication / HTTP status behavior.

These tests exercise the real HTTP endpoint end-to-end against a real
SQLite-backed SQLAlchemy session (no query/ORM mocking), matching the
project's existing BE-01 / BE-02 regression-test style (including the
``before_cursor_execute``-based query-counting pattern used for the N+1
assertions).
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

# Kept in sync with `kk/routes/cars.py::_MY_LISTINGS_COMPAT_CAP`. Imported
# directly below (not hardcoded) so this test file can't silently drift from
# the real cap if it's ever tuned.


@pytest.fixture(scope="module")
def app_ctx():
    tmp = tempfile.TemporaryDirectory(prefix="carlist_be06_", ignore_cleanup_errors=True)
    os.environ["APP_ENV"] = "testing"
    os.environ["SMS_PROVIDER"] = "console"
    os.environ.pop("LISTING_REQUIRE_APPROVAL", None)
    os.environ["DB_PATH"] = os.path.join(tmp.name, "be06.db")

    from kk.app_factory import create_app

    app, _socketio, *_ = create_app()
    from kk.models import Car, CarImage, CarVideo, User, db
    from kk.routes.cars import _MY_LISTINGS_COMPAT_CAP
    from kk.time_utils import utcnow

    with app.app_context():
        db.drop_all()
        db.create_all()

    yield app, app.test_client(), db, User, Car, CarImage, CarVideo, utcnow, _MY_LISTINGS_COMPAT_CAP

    with app.app_context():
        db.session.remove()
        db.engine.dispose()
    tmp.cleanup()


@pytest.fixture
def client(app_ctx):
    return app_ctx[1]


@pytest.fixture
def cap(app_ctx):
    return app_ctx[8]


def _unique_phone() -> str:
    return f"077{uuid.uuid4().int % 10**8:08d}"


def _make_user(app_ctx, *, username: str) -> tuple[str, int]:
    """Create an active, verified, non-dealer user. Returns (public_id, id)."""
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
        user.set_password("Aa123456!")
        db.session.add(user)
        db.session.commit()
        return user.public_id, user.id


def _login(client, username: str, password: str = "Aa123456!") -> str:
    r = client.post("/api/auth/login", json={"username": username, "password": password})
    assert r.status_code == 200, r.data
    return r.get_json()["access_token"]


def _auth(token: str) -> dict:
    return {"Authorization": f"Bearer {token}"}


def _make_cars(
    app_ctx,
    seller_id: int,
    count: int,
    *,
    status: str = "active",
    is_active: bool = True,
    created_offset_start_minutes: int = 0,
    tag: str = "car",
) -> list[int]:
    """Bulk-create ``count`` cars owned by ``seller_id``.

    Each car gets a strictly increasing ``created_at`` (offset from
    ``created_offset_start_minutes``), so ordering assertions are
    deterministic regardless of wall-clock test execution time. Returns
    the list of numeric ids, in creation order (oldest first).
    """
    app, _client, db, _User, Car, *_ = app_ctx
    ids: list[int] = []
    with app.app_context():
        base = app_ctx[7]()
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
                is_active=is_active,
                status=status,
                created_at=base + timedelta(minutes=created_offset_start_minutes + i),
            )
            db.session.add(car)
            db.session.commit()
            ids.append(car.id)
    return ids


def _make_car_with_media(app_ctx, *, seller_id: int, tag: str, created_offset_minutes: int = 0) -> int:
    """A single active car with 2 images + 1 video, owned by ``seller_id``.
    Returns the car's numeric id."""
    app, _client, db, _User, Car, CarImage, CarVideo, utcnow, *_ = app_ctx
    with app.app_context():
        car = Car(
            seller_id=seller_id,
            public_id=f"car-{tag}-{uuid.uuid4().hex[:10]}",
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
            created_at=utcnow() + timedelta(minutes=created_offset_minutes),
        )
        db.session.add(car)
        db.session.commit()
        # Absolute (already-external) URLs so `_resolve_rel()`'s on-disk
        # `_static_exists()` check (used by `_with_media_compat()`) doesn't
        # strip these fixtures out -- cloud/external URLs are kept as-is,
        # unlike local "uploads/..." relative paths that must actually exist
        # on disk under test (mirrors the BE-02 test fixtures).
        db.session.add(
            CarImage(
                car_id=car.id,
                image_url=f"https://example.com/{tag}-a.jpg",
                is_primary=True,
                order=0,
            )
        )
        db.session.add(
            CarImage(
                car_id=car.id,
                image_url=f"https://example.com/{tag}-b.jpg",
                is_primary=False,
                order=1,
            )
        )
        db.session.add(CarVideo(car_id=car.id, video_url=f"https://example.com/{tag}.mp4"))
        db.session.commit()
        return car.id


@contextmanager
def _count_queries(app_ctx):
    """Count SQL statements executed against the app's engine while the
    context is active. Uses the standard SQLAlchemy ``before_cursor_execute``
    engine event -- mirrors the pattern already established in
    ``kk/tests/test_be02_n_plus_one.py`` / ``test_be17_blocked_users_batch_fetch.py``.
    """
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
# A. Under-cap
# ---------------------------------------------------------------------------


class TestUnderCap:
    def test_all_listings_returned_ordered_created_at_desc(self, app_ctx, client):
        username = f"be06_ua_{uuid.uuid4().hex[:8]}"
        _public_id, seller_id = _make_user(app_ctx, username=username)
        ids = _make_cars(app_ctx, seller_id, 5)
        token = _login(client, username)

        resp = client.get("/api/my_listings", headers=_auth(token))
        assert resp.status_code == 200, resp.data
        body = resp.get_json()

        assert isinstance(body, list)
        assert len(body) == 5
        returned_ids = [item["numeric_id"] for item in body]
        # created_at DESC -> newest (last-created) first.
        assert returned_ids == list(reversed(ids))


# ---------------------------------------------------------------------------
# B. Exact-cap
# ---------------------------------------------------------------------------


class TestExactCap:
    def test_exactly_cap_listings_returned_as_bare_list(self, app_ctx, client, cap):
        username = f"be06_eb_{uuid.uuid4().hex[:8]}"
        _public_id, seller_id = _make_user(app_ctx, username=username)
        _make_cars(app_ctx, seller_id, cap)
        token = _login(client, username)

        resp = client.get("/api/my_listings", headers=_auth(token))
        assert resp.status_code == 200, resp.data
        body = resp.get_json()

        assert isinstance(body, list)
        assert len(body) == cap


# ---------------------------------------------------------------------------
# C. Over-cap
# ---------------------------------------------------------------------------


class TestOverCap:
    def test_over_cap_returns_newest_cap_listings_only(self, app_ctx, client, cap):
        username = f"be06_oc_{uuid.uuid4().hex[:8]}"
        _public_id, seller_id = _make_user(app_ctx, username=username)
        ids = _make_cars(app_ctx, seller_id, cap + 1)
        token = _login(client, username)

        resp = client.get("/api/my_listings", headers=_auth(token))
        assert resp.status_code == 200, resp.data
        body = resp.get_json()

        assert isinstance(body, list)
        assert len(body) == cap

        returned_ids = [item["numeric_id"] for item in body]
        # Newest `cap` listings, newest first: ids[-1] .. ids[1] (the oldest,
        # ids[0], is excluded by the cap).
        expected_ids = list(reversed(ids[1:]))
        assert returned_ids == expected_ids
        assert ids[0] not in returned_ids


# ---------------------------------------------------------------------------
# D. Authorization isolation
# ---------------------------------------------------------------------------


class TestAuthorizationIsolation:
    def test_only_authenticated_users_own_listings_are_returned(self, app_ctx, client):
        username_a = f"be06_a_{uuid.uuid4().hex[:8]}"
        username_b = f"be06_b_{uuid.uuid4().hex[:8]}"
        _public_a, seller_a = _make_user(app_ctx, username=username_a)
        _public_b, seller_b = _make_user(app_ctx, username=username_b)
        ids_a = _make_cars(app_ctx, seller_a, 3, tag="carA")
        _make_cars(app_ctx, seller_b, 4, tag="carB")

        token_a = _login(client, username_a)
        resp = client.get("/api/my_listings", headers=_auth(token_a))
        assert resp.status_code == 200, resp.data
        body = resp.get_json()

        assert isinstance(body, list)
        assert len(body) == 3
        returned_ids = {item["numeric_id"] for item in body}
        assert returned_ids == set(ids_a)

    def test_unauthenticated_request_is_rejected(self, client):
        resp = client.get("/api/my_listings")
        assert resp.status_code in (401, 422)


# ---------------------------------------------------------------------------
# E. Status behavior (is_active filter only, matching current intent)
# ---------------------------------------------------------------------------


class TestStatusBehavior:
    def test_inactive_listings_excluded_regardless_of_status(self, app_ctx, client):
        username = f"be06_st_{uuid.uuid4().hex[:8]}"
        _public_id, seller_id = _make_user(app_ctx, username=username)
        # is_active=True, status="active" -- included.
        active_ids = _make_cars(app_ctx, seller_id, 2, status="active", is_active=True, tag="act")
        # is_active=False rows are excluded no matter the `status` value --
        # the existing compat endpoint only filters on `is_active`, not `status`.
        _make_cars(app_ctx, seller_id, 2, status="active", is_active=False, tag="inact")
        # is_active=True but status="sold"/"pending" is still INCLUDED, since
        # the current implementation never filters on `status` at all.
        sold_ids = _make_cars(app_ctx, seller_id, 1, status="sold", is_active=True, tag="sold")
        pending_ids = _make_cars(app_ctx, seller_id, 1, status="pending", is_active=True, tag="pending")

        token = _login(client, username)
        resp = client.get("/api/my_listings", headers=_auth(token))
        assert resp.status_code == 200, resp.data
        body = resp.get_json()

        returned_ids = {item["numeric_id"] for item in body}
        expected_ids = set(active_ids) | set(sold_ids) | set(pending_ids)
        assert returned_ids == expected_ids
        assert len(body) == 4


# ---------------------------------------------------------------------------
# F. Bare-array response contract
# ---------------------------------------------------------------------------


class TestBareArrayResponseContract:
    def test_top_level_json_is_a_list_not_an_envelope(self, app_ctx, client):
        username = f"be06_bc_{uuid.uuid4().hex[:8]}"
        _public_id, seller_id = _make_user(app_ctx, username=username)
        _make_cars(app_ctx, seller_id, 2)
        token = _login(client, username)

        resp = client.get("/api/my_listings", headers=_auth(token))
        assert resp.status_code == 200, resp.data
        body = resp.get_json()

        assert isinstance(body, list)
        assert not isinstance(body, dict)

    def test_empty_result_is_empty_list_not_null_or_object(self, app_ctx, client):
        username = f"be06_empty_{uuid.uuid4().hex[:8]}"
        _public_id, _seller_id = _make_user(app_ctx, username=username)
        token = _login(client, username)

        resp = client.get("/api/my_listings", headers=_auth(token))
        assert resp.status_code == 200, resp.data
        body = resp.get_json()

        assert body == []


# ---------------------------------------------------------------------------
# G. Eager-loading / N+1 regression
# ---------------------------------------------------------------------------


class TestQueryCountDoesNotScaleWithRowCount:
    def test_query_count_is_constant_not_linear_in_listing_count(self, app_ctx, client):
        """Regression guard for the N+1: owning many listings (each with its
        own images/video/seller) must not issue one extra SQL statement per
        relationship per listing. Fails under the old (no eager-loading)
        implementation, whose statement count grows with the number of
        returned rows."""
        few_username = f"be06_qcf_{uuid.uuid4().hex[:8]}"
        many_username = f"be06_qcm_{uuid.uuid4().hex[:8]}"
        _few_public, few_seller = _make_user(app_ctx, username=few_username)
        _many_public, many_seller = _make_user(app_ctx, username=many_username)

        for i in range(5):
            _make_car_with_media(app_ctx, seller_id=few_seller, tag=f"few-{i}", created_offset_minutes=i)
        for i in range(20):
            _make_car_with_media(app_ctx, seller_id=many_seller, tag=f"many-{i}", created_offset_minutes=i)

        few_token = _login(client, few_username)
        many_token = _login(client, many_username)

        with _count_queries(app_ctx) as counter:
            r_few = client.get("/api/my_listings", headers=_auth(few_token))
        assert r_few.status_code == 200, r_few.data
        few_query_count = counter["n"]
        few_body = r_few.get_json()
        assert len(few_body) == 5
        for item in few_body:
            assert len(item["images"]) == 2
            assert len(item["videos"]) == 1
            assert item["seller"] is not None

        with _count_queries(app_ctx) as counter:
            r_many = client.get("/api/my_listings", headers=_auth(many_token))
        assert r_many.status_code == 200, r_many.data
        many_query_count = counter["n"]
        many_body = r_many.get_json()
        assert len(many_body) == 20
        for item in many_body:
            assert len(item["images"]) == 2
            assert len(item["videos"]) == 1
            assert item["seller"] is not None

        assert many_query_count == few_query_count, (
            f"expected a constant query count independent of listing count, "
            f"got {few_query_count} queries for 5 listings vs {many_query_count} "
            f"queries for 20 listings"
        )


# ---------------------------------------------------------------------------
# H. Cap + eager loading together
# ---------------------------------------------------------------------------


class TestCapAndEagerLoadingTogether:
    def test_over_cap_result_is_bounded_and_query_count_does_not_scale(self, app_ctx, client, cap):
        username = f"be06_ch_{uuid.uuid4().hex[:8]}"
        _public_id, seller_id = _make_user(app_ctx, username=username)
        for i in range(cap + 10):
            _make_car_with_media(app_ctx, seller_id=seller_id, tag=f"cheager-{i}", created_offset_minutes=i)

        # Baseline with a small dataset (well under the cap) for the
        # query-count comparison, using a separate user so the two requests
        # are independently measurable.
        baseline_username = f"be06_chb_{uuid.uuid4().hex[:8]}"
        _baseline_public, baseline_seller = _make_user(app_ctx, username=baseline_username)
        for i in range(5):
            _make_car_with_media(
                app_ctx, seller_id=baseline_seller, tag=f"chbaseline-{i}", created_offset_minutes=i
            )

        baseline_token = _login(client, baseline_username)
        with _count_queries(app_ctx) as counter:
            r_baseline = client.get("/api/my_listings", headers=_auth(baseline_token))
        assert r_baseline.status_code == 200, r_baseline.data
        baseline_query_count = counter["n"]
        assert len(r_baseline.get_json()) == 5

        token = _login(client, username)
        with _count_queries(app_ctx) as counter:
            resp = client.get("/api/my_listings", headers=_auth(token))
        assert resp.status_code == 200, resp.data
        over_cap_query_count = counter["n"]
        body = resp.get_json()

        assert isinstance(body, list)
        assert len(body) == cap
        for item in body:
            assert len(item["images"]) == 2
            assert len(item["videos"]) == 1
            assert item["seller"] is not None

        assert over_cap_query_count == baseline_query_count, (
            f"expected a constant query count independent of listing count "
            f"even when the cap is exceeded, got {baseline_query_count} queries "
            f"for 5 listings vs {over_cap_query_count} queries for {cap} "
            f"(capped) listings out of {cap + 10} created"
        )
