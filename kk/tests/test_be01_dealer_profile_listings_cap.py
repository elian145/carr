"""BE-01 regression tests: ``GET /api/dealers/<dealer_public_id>``
(``dealer_profile()``) must not return an unbounded number of listings.

Bug (PRODUCTION_AUDIT.md BE-01): the original implementation ran::

    listings = (
        public_listings_filter(Car.query.filter(Car.seller_id == dealer.id))
        .options(selectinload(Car.images), selectinload(Car.videos))
        .order_by(Car.is_featured.desc(), Car.created_at.desc())
        .all()
    )
    ...
    stats = {"total_listings": len(listing_dicts), ...}

with no ``.limit()`` at all -- a dealer with an unusually large number of
active listings would have every single one fully serialized in one public,
unauthenticated response. ``stats.total_listings`` was also derived from the
same unbounded list rather than a real ``COUNT(*)``.

The fix adds a hard cap (``_DEALER_PROFILE_LISTINGS_CAP = 200``) to the
returned ``listings`` array while computing ``stats.total_listings`` from a
separate ``COUNT(*)`` query using the exact same ``public_listings_filter``
visibility rules, so the stat stays accurate even once the array is capped.
Deliberately NOT implemented here: real pagination -- the current Flutter
dealer profile screen has no load-more/pagination support and expects the
complete listings array in one response, so a page/per_page contract change
would be a client-incompatible behavior change.

These tests exercise the real HTTP endpoint end-to-end against a real
SQLite-backed SQLAlchemy session (no query/ORM mocking), matching the
project's existing BE-1x regression-test style.
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


@pytest.fixture(scope="module")
def app_ctx():
    tmp = tempfile.TemporaryDirectory(prefix="carlist_be01_", ignore_cleanup_errors=True)
    os.environ["APP_ENV"] = "testing"
    os.environ["SMS_PROVIDER"] = "console"
    os.environ.pop("LISTING_REQUIRE_APPROVAL", None)
    os.environ["DB_PATH"] = os.path.join(tmp.name, "be01.db")

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


def _make_dealer(app_ctx) -> tuple[str, int]:
    """Create an approved, active, public dealer. Returns (public_id, id)."""
    app, _client, db, User, _Car, _utcnow = app_ctx
    username = f"be01_dealer_{uuid.uuid4().hex[:8]}"
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
            dealership_name=f"Cars {uuid.uuid4().hex[:6]}",
            dealership_location="Erbil",
        )
        user.set_password("Aa123456!")
        db.session.add(user)
        db.session.commit()
        return user.public_id, user.id


def _make_cars(
    app_ctx,
    dealer_id: int,
    count: int,
    *,
    status: str = "active",
    is_active: bool = True,
    is_featured: bool = False,
    created_offset_start_minutes: int = 0,
) -> None:
    """Bulk-create ``count`` cars owned by ``dealer_id``.

    Each car gets a strictly increasing ``created_at`` (offset from
    ``created_offset_start_minutes``), so ordering assertions are
    deterministic regardless of wall-clock test execution time.
    """
    app, _client, db, _User, Car, utcnow = app_ctx
    with app.app_context():
        base = utcnow()
        for i in range(count):
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
                is_active=is_active,
                status=status,
                is_featured=is_featured,
                created_at=base + timedelta(minutes=created_offset_start_minutes + i),
            )
            db.session.add(car)
        db.session.commit()


# ---------------------------------------------------------------------------
# A. Over-cap: more than 200 active public listings
# ---------------------------------------------------------------------------


class TestOverCap:
    def test_listings_capped_at_200_but_total_listings_reflects_full_count(self, app_ctx, client):
        public_id, dealer_id = _make_dealer(app_ctx)
        _make_cars(app_ctx, dealer_id, 210)

        resp = client.get(f"/api/dealers/{public_id}")
        assert resp.status_code == 200, resp.data
        body = resp.get_json()

        assert len(body["listings"]) == 200
        assert body["stats"]["total_listings"] == 210

    def test_over_cap_response_does_not_error_and_keeps_shape(self, app_ctx, client):
        public_id, dealer_id = _make_dealer(app_ctx)
        _make_cars(app_ctx, dealer_id, 201)

        resp = client.get(f"/api/dealers/{public_id}")
        assert resp.status_code == 200, resp.data
        body = resp.get_json()

        assert set(body.keys()) == {"dealer", "listings", "stats"}
        assert isinstance(body["listings"], list)
        assert len(body["listings"]) == 200
        assert body["stats"]["total_listings"] == 201


# ---------------------------------------------------------------------------
# B. Under-cap: <= 200 active public listings -- unchanged behavior
# ---------------------------------------------------------------------------


class TestUnderCap:
    def test_all_listings_returned_and_total_matches(self, app_ctx, client):
        public_id, dealer_id = _make_dealer(app_ctx)
        _make_cars(app_ctx, dealer_id, 5)

        resp = client.get(f"/api/dealers/{public_id}")
        assert resp.status_code == 200, resp.data
        body = resp.get_json()

        assert len(body["listings"]) == 5
        assert body["stats"]["total_listings"] == 5

    def test_no_listings_returns_empty_array_and_zero_total(self, app_ctx, client):
        public_id, _dealer_id = _make_dealer(app_ctx)

        resp = client.get(f"/api/dealers/{public_id}")
        assert resp.status_code == 200, resp.data
        body = resp.get_json()

        assert body["listings"] == []
        assert body["stats"]["total_listings"] == 0
        assert body["stats"]["featured_listings"] == 0

    def test_response_shape_unchanged_for_common_case(self, app_ctx, client):
        """Regression guard: below the cap, the response must be identical
        in shape/content to the pre-fix behavior (dealer/listings/stats keys,
        listing dicts fully populated, no extraneous pagination fields)."""
        public_id, dealer_id = _make_dealer(app_ctx)
        _make_cars(app_ctx, dealer_id, 3)

        resp = client.get(f"/api/dealers/{public_id}")
        assert resp.status_code == 200, resp.data
        body = resp.get_json()

        assert set(body.keys()) == {"dealer", "listings", "stats"}
        assert set(body["stats"].keys()) == {"total_listings", "featured_listings"}
        # No pagination metadata was introduced.
        assert "page" not in body
        assert "pagination" not in body
        for item in body["listings"]:
            assert item["brand"] == "toyota"
            assert item["price"] == 15000


# ---------------------------------------------------------------------------
# C. Ordering: is_featured DESC, created_at DESC preserved within the cap
# ---------------------------------------------------------------------------


class TestOrderingPreservedWithinCap:
    def test_featured_first_then_created_at_desc_across_the_cap_boundary(self, app_ctx, client):
        public_id, dealer_id = _make_dealer(app_ctx)
        # 10 older, non-featured listings, then 205 newer, featured listings.
        # With a 200 cap and featured-first ordering, the response must be
        # exactly the 200 most-recently-created featured listings (in
        # descending created_at order) -- none of the non-featured or the
        # 5 oldest featured listings should appear.
        _make_cars(
            app_ctx,
            dealer_id,
            10,
            is_featured=False,
            created_offset_start_minutes=0,
        )
        _make_cars(
            app_ctx,
            dealer_id,
            205,
            is_featured=True,
            created_offset_start_minutes=1000,
        )

        resp = client.get(f"/api/dealers/{public_id}")
        assert resp.status_code == 200, resp.data
        body = resp.get_json()

        listings = body["listings"]
        assert len(listings) == 200
        assert body["stats"]["total_listings"] == 215

        # Every returned listing is featured (the non-featured batch and the
        # 5 oldest featured listings were pushed out by the cap).
        assert all(item["is_featured"] is True for item in listings)

        # created_at strictly descending across the full capped result.
        created_ats = [item["created_at"] for item in listings]
        assert created_ats == sorted(created_ats, reverse=True)

    def test_ordering_observable_with_mixed_featured_status_under_cap(self, app_ctx, client):
        public_id, dealer_id = _make_dealer(app_ctx)
        _make_cars(app_ctx, dealer_id, 3, is_featured=False, created_offset_start_minutes=0)
        _make_cars(app_ctx, dealer_id, 2, is_featured=True, created_offset_start_minutes=100)

        resp = client.get(f"/api/dealers/{public_id}")
        assert resp.status_code == 200, resp.data
        listings = resp.get_json()["listings"]

        assert len(listings) == 5
        # Featured listings first (both of them), most-recent first.
        assert listings[0]["is_featured"] is True
        assert listings[1]["is_featured"] is True
        assert listings[0]["created_at"] >= listings[1]["created_at"]
        # Then the non-featured listings, most-recent first.
        assert all(item["is_featured"] is False for item in listings[2:])
        non_featured_created_ats = [item["created_at"] for item in listings[2:]]
        assert non_featured_created_ats == sorted(non_featured_created_ats, reverse=True)


# ---------------------------------------------------------------------------
# D. Visibility: inactive / non-public-status listings excluded from BOTH
#    the returned listings AND stats.total_listings
# ---------------------------------------------------------------------------


class TestVisibilityExcludesNonPublicListings:
    def test_inactive_and_non_public_status_excluded_from_listings_and_total(
        self, app_ctx, client
    ):
        public_id, dealer_id = _make_dealer(app_ctx)
        # 4 genuinely public listings.
        _make_cars(app_ctx, dealer_id, 4, status="active", is_active=True)
        # Excluded: inactive (even though status is the public "active").
        _make_cars(app_ctx, dealer_id, 3, status="active", is_active=False)
        # Excluded: active row but non-public status (moderation states).
        _make_cars(app_ctx, dealer_id, 2, status="pending", is_active=True)
        _make_cars(app_ctx, dealer_id, 2, status="hidden", is_active=True)
        _make_cars(app_ctx, dealer_id, 2, status="draft", is_active=True)
        # Included: "sold" is a public status per PUBLIC_LISTING_STATUSES.
        _make_cars(app_ctx, dealer_id, 1, status="sold", is_active=True)

        resp = client.get(f"/api/dealers/{public_id}")
        assert resp.status_code == 200, resp.data
        body = resp.get_json()

        # Only the 4 active + 1 sold listings are public: 5 total.
        assert len(body["listings"]) == 5
        assert body["stats"]["total_listings"] == 5
        returned_statuses = {item.get("status") for item in body["listings"]}
        assert returned_statuses.issubset({"active", "sold"})

    def test_total_listings_over_cap_still_excludes_non_public_rows(self, app_ctx, client):
        """The COUNT(*) used for stats.total_listings must apply the same
        public_listings_filter as the capped listings query -- it must not
        count hidden/pending/draft/inactive rows even when the public count
        exceeds the cap."""
        public_id, dealer_id = _make_dealer(app_ctx)
        _make_cars(app_ctx, dealer_id, 205, status="active", is_active=True)
        _make_cars(app_ctx, dealer_id, 50, status="pending", is_active=True)
        _make_cars(app_ctx, dealer_id, 50, status="active", is_active=False)

        resp = client.get(f"/api/dealers/{public_id}")
        assert resp.status_code == 200, resp.data
        body = resp.get_json()

        assert len(body["listings"]) == 200
        # Total reflects only the 205 genuinely public rows, not 305.
        assert body["stats"]["total_listings"] == 205


# ---------------------------------------------------------------------------
# E. Dealer-not-found / unrelated behavior unchanged
# ---------------------------------------------------------------------------


class TestUnrelatedBehaviorUnchanged:
    def test_unknown_dealer_still_returns_404(self, client):
        resp = client.get("/api/dealers/does-not-exist")
        assert resp.status_code == 404, resp.data
