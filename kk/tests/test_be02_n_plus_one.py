"""BE-02 regression tests: three authenticated list endpoints must not
issue N+1 SQL queries when serializing their results.

Bug (PRODUCTION_AUDIT.md BE-02): none of

  - ``GET /api/user/favorites``        (``get_favorites()``,   kk/routes/favorites.py)
  - ``GET /api/user/recently-viewed``  (``recently_viewed()``, kk/routes/user.py)
  - ``GET /api/analytics/listings``    (``get_listings_analytics()``, kk/routes/analytics.py)

eager-loaded the relationships their own serializers read per row:

  - favorites / recently-viewed call ``Car.to_dict()`` (directly, or via
    ``_with_media_compat()``), which reads ``Car.images``, ``Car.videos``,
    and ``Car.seller`` -- three separately lazy-loaded relationships.
  - analytics calls ``ListingAnalytics.to_dict()``, which reads
    ``ListingAnalytics.car`` and (via its ``first_image_rel_path()`` helper)
    ``car.images`` -- two separately lazy-loaded relationships.

With no ``.options(...)`` on the driving query, each of those relationship
accesses issued one extra SQL statement *per returned row* -- the classic
N+1 pattern. A throwaway diagnostic (real Flask app + real SQLite,
``before_cursor_execute`` query counting, no ORM/query mocking) measured
this directly before the fix: favorites/recently-viewed went from 16
queries at N=5 favorited/viewed cars to 46 at N=20 (~2 extra queries per
additional row); analytics went from 11 to 26 (~1 extra query per
additional row).

The fix adds ``.options(selectinload(Car.images), selectinload(Car.videos),
joinedload(Car.seller))`` to the favorites/recently-viewed driving queries,
and ``.options(joinedload(ListingAnalytics.car).selectinload(Car.images))``
to the analytics one (intentionally *not* eager-loading ``videos``/``seller``
there, since ``ListingAnalytics.to_dict()`` never reads them) -- with no
other behavior change.

These tests exercise the real HTTP endpoints end-to-end against a real
SQLite-backed SQLAlchemy session (no query/ORM mocking), and use the
project's existing ``before_cursor_execute``-based query-counting pattern
(see ``kk/tests/test_be17_blocked_users_batch_fetch.py``) to prove the
number of SQL statements per request does not grow with the number of
returned rows. Each dataset uses a *distinct* seller per car (not one
shared seller) so that a missing ``joinedload(Car.seller)`` would still
show up as one extra query per row -- a shared seller would otherwise let
SQLAlchemy's identity-map short-circuit hide a missing seller eager-load.
"""

from __future__ import annotations

import os
import sys
import tempfile
import uuid
from contextlib import contextmanager
from pathlib import Path

import pytest

_REPO_ROOT = Path(__file__).resolve().parents[2]
if str(_REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(_REPO_ROOT))


@pytest.fixture(scope="module")
def app_ctx():
    tmp = tempfile.TemporaryDirectory(prefix="carlist_be02_", ignore_cleanup_errors=True)
    os.environ["APP_ENV"] = "testing"
    os.environ["SMS_PROVIDER"] = "console"
    os.environ.pop("LISTING_REQUIRE_APPROVAL", None)
    os.environ["DB_PATH"] = os.path.join(tmp.name, "be02.db")

    from kk.app_factory import create_app

    app, _socketio, *_ = create_app()
    from kk.models import Car, CarImage, CarVideo, ListingAnalytics, User, db, user_favorites, user_viewed_listings

    with app.app_context():
        db.drop_all()
        db.create_all()

    yield (
        app,
        app.test_client(),
        db,
        User,
        Car,
        CarImage,
        CarVideo,
        ListingAnalytics,
        user_favorites,
        user_viewed_listings,
    )

    with app.app_context():
        db.session.remove()
        db.engine.dispose()
    tmp.cleanup()


@pytest.fixture
def client(app_ctx):
    return app_ctx[1]


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


def _make_car_with_media(app_ctx, *, seller_id: int, tag: str) -> int:
    """A single active, public car with 2 images + 1 video, owned by
    ``seller_id``. Returns the car's numeric id."""
    app, _client, db, _User, Car, CarImage, CarVideo, *_ = app_ctx
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
        )
        db.session.add(car)
        db.session.commit()
        # Absolute (already-external) URLs so `_resolve_rel()`'s on-disk
        # `_static_exists()` check (used by `_with_media_compat()` for the
        # recently-viewed endpoint) doesn't strip these fixtures out --
        # cloud/external URLs are kept as-is, unlike local "uploads/..."
        # relative paths that must actually exist on disk under test.
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


def _favorite(app_ctx, *, user_id: int, car_id: int) -> None:
    app, _client, db, *_rest, user_favorites, _uvl = app_ctx
    with app.app_context():
        db.session.execute(
            user_favorites.insert().values(user_id=user_id, car_id=car_id, created_at=db.func.now())
        )
        db.session.commit()


def _record_view(app_ctx, *, user_id: int, car_id: int) -> None:
    app, _client, db, *_rest, _uf, user_viewed_listings = app_ctx
    with app.app_context():
        db.session.execute(
            user_viewed_listings.insert().values(user_id=user_id, car_id=car_id, viewed_at=db.func.now())
        )
        db.session.commit()


def _make_analytics(app_ctx, *, car_id: int) -> None:
    app, _client, db, _User, _Car, _CarImage, _CarVideo, ListingAnalytics, *_ = app_ctx
    with app.app_context():
        db.session.add(ListingAnalytics(car_id=car_id, views=1))
        db.session.commit()


@contextmanager
def _count_queries(app_ctx):
    """Count SQL statements executed against the app's engine while the
    context is active. Uses the standard SQLAlchemy ``before_cursor_execute``
    engine event -- no extra test dependency needed. Mirrors the pattern
    already established in ``kk/tests/test_be17_blocked_users_batch_fetch.py``.
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


def _build_dataset(app_ctx, *, tag: str, count: int):
    """Create ``count`` cars, each with its OWN distinct seller (so a
    missing seller eager-load can't hide behind the identity-map cache a
    single shared seller would provide), 2 images + 1 video each, favorited
    and recently-viewed by one shared buyer, and each with an analytics row
    owned by one shared "analytics_seller" account (analytics.py scopes
    listings to a single current_user, so those cars share one seller --
    that's fine, since the analytics fix never eager-loads `seller` at all).

    Returns (buyer_username, analytics_seller_username, car_ids).
    """
    buyer_username = f"be02_buyer_{tag}_{uuid.uuid4().hex[:8]}"
    buyer_public, buyer_id = _make_user(app_ctx, username=buyer_username)

    analytics_seller_username = f"be02_aseller_{tag}_{uuid.uuid4().hex[:8]}"
    _analytics_seller_public, analytics_seller_id = _make_user(
        app_ctx, username=analytics_seller_username
    )

    fav_view_car_ids = []
    for i in range(count):
        _own_seller_public, own_seller_id = _make_user(
            app_ctx, username=f"be02_dseller_{tag}_{i}_{uuid.uuid4().hex[:6]}"
        )
        car_id = _make_car_with_media(app_ctx, seller_id=own_seller_id, tag=f"{tag}-fv-{i}")
        _favorite(app_ctx, user_id=buyer_id, car_id=car_id)
        _record_view(app_ctx, user_id=buyer_id, car_id=car_id)
        fav_view_car_ids.append(car_id)

    analytics_car_ids = []
    for i in range(count):
        car_id = _make_car_with_media(app_ctx, seller_id=analytics_seller_id, tag=f"{tag}-an-{i}")
        _make_analytics(app_ctx, car_id=car_id)
        analytics_car_ids.append(car_id)

    return buyer_username, analytics_seller_username, fav_view_car_ids, analytics_car_ids


# ---------------------------------------------------------------------------
# A. Correctness regression
# ---------------------------------------------------------------------------


class TestCorrectnessRegression:
    def test_favorites_returns_200_with_expected_media_and_seller(self, app_ctx, client):
        buyer_username, _aseller, car_ids, _ = _build_dataset(app_ctx, tag="corA", count=3)
        token = _login(client, buyer_username)

        r = client.get("/api/user/favorites", headers=_auth(token))
        assert r.status_code == 200, r.data
        body = r.get_json()
        assert len(body["cars"]) == 3
        for item in body["cars"]:
            assert item["brand"] == "toyota"
            assert len(item["images"]) == 2
            assert len(item["videos"]) == 1
            assert item["seller"] is not None
            assert "favorited_at" in item

    def test_recently_viewed_returns_200_with_expected_media_and_seller(self, app_ctx, client):
        buyer_username, _aseller, car_ids, _ = _build_dataset(app_ctx, tag="corB", count=3)
        token = _login(client, buyer_username)

        r = client.get("/api/user/recently-viewed", headers=_auth(token))
        assert r.status_code == 200, r.data
        body = r.get_json()
        assert len(body["cars"]) == 3
        for item in body["cars"]:
            assert item["brand"] == "toyota"
            assert len(item["images"]) == 2
            assert len(item["videos"]) == 1
            assert item["seller"] is not None
            assert "viewed_at" in item

    def test_analytics_returns_200_with_expected_fields(self, app_ctx, client):
        _buyer, aseller_username, _fv, analytics_car_ids = _build_dataset(
            app_ctx, tag="corC", count=3
        )
        token = _login(client, aseller_username)

        r = client.get("/api/analytics/listings", headers=_auth(token))
        assert r.status_code == 200, r.data
        body = r.get_json()
        assert len(body) == 3
        for item in body:
            assert item["brand"] == "toyota"
            assert item["views"] == 1
            assert item["image_url"]  # first image's rel path, non-empty


# ---------------------------------------------------------------------------
# B. Query-count regression: no linear growth with N
# ---------------------------------------------------------------------------


class TestQueryCountDoesNotScaleWithRowCount:
    def test_favorites_query_count_is_constant_not_linear_in_favorite_count(
        self, app_ctx, client
    ):
        """Regression guard for the N+1: favoriting many cars must not issue
        one extra SQL statement per relationship per favorited car. Fails
        under the old (no eager-loading) implementation, whose statement
        count grows by ~2 per additional car (images + videos; seller is
        distinct per car here so a missing seller eager-load would add a
        3rd)."""
        few_username, _a, _fv_few, _ = _build_dataset(app_ctx, tag="cntFavFew", count=5)
        many_username, _a2, _fv_many, _ = _build_dataset(app_ctx, tag="cntFavMany", count=20)

        few_token = _login(client, few_username)
        many_token = _login(client, many_username)

        with _count_queries(app_ctx) as counter:
            r_few = client.get("/api/user/favorites?per_page=50", headers=_auth(few_token))
        assert r_few.status_code == 200, r_few.data
        few_query_count = counter["n"]
        assert len(r_few.get_json()["cars"]) == 5

        with _count_queries(app_ctx) as counter:
            r_many = client.get("/api/user/favorites?per_page=50", headers=_auth(many_token))
        assert r_many.status_code == 200, r_many.data
        many_query_count = counter["n"]
        assert len(r_many.get_json()["cars"]) == 20

        assert many_query_count == few_query_count, (
            f"expected a constant query count independent of favorite count, "
            f"got {few_query_count} queries for 5 favorites vs {many_query_count} "
            f"queries for 20 favorites"
        )

    def test_recently_viewed_query_count_is_constant_not_linear_in_viewed_count(
        self, app_ctx, client
    ):
        """Same N+1 regression guard as favorites, for the recently-viewed
        endpoint (a structurally identical query)."""
        few_username, _a, _fv_few, _ = _build_dataset(app_ctx, tag="cntRvFew", count=5)
        many_username, _a2, _fv_many, _ = _build_dataset(app_ctx, tag="cntRvMany", count=20)

        few_token = _login(client, few_username)
        many_token = _login(client, many_username)

        with _count_queries(app_ctx) as counter:
            r_few = client.get("/api/user/recently-viewed?per_page=50", headers=_auth(few_token))
        assert r_few.status_code == 200, r_few.data
        few_query_count = counter["n"]
        assert len(r_few.get_json()["cars"]) == 5

        with _count_queries(app_ctx) as counter:
            r_many = client.get("/api/user/recently-viewed?per_page=50", headers=_auth(many_token))
        assert r_many.status_code == 200, r_many.data
        many_query_count = counter["n"]
        assert len(r_many.get_json()["cars"]) == 20

        assert many_query_count == few_query_count, (
            f"expected a constant query count independent of viewed count, "
            f"got {few_query_count} queries for 5 recently-viewed vs "
            f"{many_query_count} queries for 20 recently-viewed"
        )

    def test_analytics_query_count_is_constant_not_linear_in_listing_count(
        self, app_ctx, client
    ):
        """Same N+1 regression guard for analytics: owning many listings
        (each with its own ListingAnalytics row) must not issue one extra
        SQL statement per listing. Fails under the old (no eager-loading)
        implementation, whose statement count grows by ~1 per additional
        listing (car.images access inside ListingAnalytics.to_dict())."""
        _b1, few_aseller, _fv1, few_car_ids = _build_dataset(app_ctx, tag="cntAnFew", count=5)
        _b2, many_aseller, _fv2, many_car_ids = _build_dataset(app_ctx, tag="cntAnMany", count=20)

        few_token = _login(client, few_aseller)
        many_token = _login(client, many_aseller)

        with _count_queries(app_ctx) as counter:
            r_few = client.get("/api/analytics/listings", headers=_auth(few_token))
        assert r_few.status_code == 200, r_few.data
        few_query_count = counter["n"]
        assert len(r_few.get_json()) == 5

        with _count_queries(app_ctx) as counter:
            r_many = client.get("/api/analytics/listings", headers=_auth(many_token))
        assert r_many.status_code == 200, r_many.data
        many_query_count = counter["n"]
        assert len(r_many.get_json()) == 20

        assert many_query_count == few_query_count, (
            f"expected a constant query count independent of listing count, "
            f"got {few_query_count} queries for 5 listings vs {many_query_count} "
            f"queries for 20 listings"
        )
