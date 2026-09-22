"""Audit regression tests: "admin dashboard shows more listings for a model
than the public app search returns" bug report.

Reported symptom: in the admin dashboard, more than 2 listings are visible
for models such as "Land Cruiser Prado", but searching "Land Cruiser Prado"
in the mobile app only shows 2 listings. Same for other models.

This file traces every relevant condition end-to-end against real HTTP
routes (``GET /api/admin/cars`` for the admin table, ``GET /api/cars?q=...``
for the public/mobile search) with a real SQLite-backed SQLAlchemy session,
matching the project's existing regression-test style (see
``test_carnet_v1_fix5_deactivated_seller_listings.py``,
``test_cn_search_01_ranking.py``).

Conclusion (see final report for full detail): there is NO backend bug in
`/api/cars` pagination, ranking, joins, or dedup. `GET /api/admin/cars`
(``kk/routes/admin.py::cars()``) intentionally queries `Car.query` with NO
status/is_active/seller-active filtering by default -- it is a moderation
tool and must show pending/hidden/draft/inactive/deactivated-seller rows.
`GET /api/cars` (``kk/routes/cars.py::get_cars()``) intentionally restricts
to `_public_listings_filter()` (active+sold, active seller only) per
``kk/listing_visibility.py``. A model with N admin-visible rows and only
M < N public-eligible rows is correct, documented behavior, NOT a bug --
provided all M public-eligible rows are actually returned by search
(verified below across multiple page sizes, multiple models, and >2 public
rows per model, which the reported "only 2" ceiling does not reproduce
anywhere in this backend).
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
        prefix="carlist_admincount_", ignore_cleanup_errors=True
    )
    os.environ["APP_ENV"] = "testing"
    os.environ["SMS_PROVIDER"] = "console"
    os.environ.pop("LISTING_REQUIRE_APPROVAL", None)
    os.environ["DB_PATH"] = os.path.join(tmp.name, "admincount.db")

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


def _make_seller(app_ctx, *, is_active: bool = True):
    app, _client, db, User, _Car = app_ctx
    with app.app_context():
        user = User(
            username=f"audit_seller_{uuid.uuid4().hex[:8]}",
            phone_number=_unique_phone(),
            first_name="Audit",
            last_name="Seller",
            is_active=is_active,
            is_verified=True,
            phone_verified=True,
            public_id=f"pub-{uuid.uuid4().hex[:12]}",
        )
        user.set_password("Aa123456!")
        db.session.add(user)
        db.session.commit()
        return user.id


def _make_admin(app_ctx):
    from flask_jwt_extended import create_access_token

    app, _client, db, User, _Car = app_ctx
    with app.app_context():
        user = User(
            username=f"audit_admin_{uuid.uuid4().hex[:8]}",
            phone_number=_unique_phone(),
            first_name="Audit",
            last_name="Admin",
            is_active=True,
            is_verified=True,
            phone_verified=True,
            public_id=f"pub-{uuid.uuid4().hex[:12]}",
            is_admin=True,
        )
        user.set_password("Aa123456!")
        db.session.add(user)
        db.session.commit()
        token = create_access_token(identity=str(user.id))
        return token


def _auth(token: str) -> dict:
    return {"Authorization": f"Bearer {token}"}


def _make_car(
    app_ctx,
    seller_id: int,
    *,
    brand: str = "toyota",
    model: str = "Land Cruiser Prado",
    status: str = "active",
    is_active: bool = True,
    year: int = 2020,
) -> str:
    app, _client, db, _User, Car = app_ctx
    with app.app_context():
        car = Car(
            seller_id=seller_id,
            public_id=f"car-{uuid.uuid4().hex[:12]}",
            title=f"{year} {brand.title()} {model}",
            brand=brand,
            model=model,
            year=year,
            mileage=10000,
            engine_type="gas",
            transmission="auto",
            drive_type="fwd",
            condition="used",
            body_type="suv",
            price=25000,
            location="Erbil",
            is_active=is_active,
            status=status,
        )
        db.session.add(car)
        db.session.commit()
        return car.public_id


def _search_ids(client, **params) -> tuple[list[str], dict]:
    r = client.get("/api/cars", query_string=params)
    assert r.status_code == 200, r.data
    payload = r.get_json() or {}
    return [c["id"] for c in payload.get("cars", [])], payload.get("pagination", {})


def _admin_ids(client, token, **params) -> tuple[list[str], dict]:
    r = client.get(
        "/api/admin/cars", query_string=params, headers=_auth(token)
    )
    assert r.status_code == 200, r.data
    payload = r.get_json() or {}
    return [c["id"] for c in payload.get("cars", [])], payload.get("pagination", {})


# ---------------------------------------------------------------------------
# 1. Reproduce the exact reported shape: N admin-visible rows for a model,
#    only M of them legitimately public. Confirm search returns ALL M (not
#    just 2), and confirm each excluded row's exact exclusion reason.
# ---------------------------------------------------------------------------


class TestAdminVsPublicCountForLandCruiserPrado:
    def test_mixed_status_dataset_row_by_row_visibility(self, app_ctx, client):
        app, _client, db, User, Car = app_ctx
        active_seller = _make_seller(app_ctx)
        deactivated_seller = _make_seller(app_ctx, is_active=False)

        model = f"Land Cruiser Prado {uuid.uuid4().hex[:6]}"  # unique per test run

        # 5 genuinely public listings (active status, active seller).
        public_ids = [
            _make_car(app_ctx, active_seller, model=model, status="active", year=2018 + i)
            for i in range(5)
        ]
        # 1 sold listing -- PUBLIC_LISTING_STATUSES includes "sold".
        sold_id = _make_car(app_ctx, active_seller, model=model, status="sold", year=2017)
        # 1 pending (awaiting moderation) -- admin-only.
        pending_id = _make_car(app_ctx, active_seller, model=model, status="pending", year=2016)
        # 1 hidden (moderated off) -- admin-only.
        hidden_id = _make_car(app_ctx, active_seller, model=model, status="hidden", year=2015)
        # 1 draft (seller not finished) -- admin-only.
        draft_id = _make_car(app_ctx, active_seller, model=model, status="draft", year=2014)
        # 1 soft-deleted (is_active=False on the Car row itself) -- admin-only.
        deleted_id = _make_car(app_ctx, active_seller, model=model, status="active", is_active=False, year=2013)
        # 1 otherwise-active listing from a deactivated/banned seller -- admin-only.
        banned_seller_id = _make_car(app_ctx, deactivated_seller, model=model, status="active", year=2012)

        total_admin_rows = 5 + 1 + 1 + 1 + 1 + 1 + 1  # = 11
        expected_public_ids = set(public_ids) | {sold_id}  # 6 legitimately public

        # --- Admin dashboard sees every row (no status/is_active/seller filter). ---
        admin_token = _make_admin(app_ctx)
        admin_ids, admin_pg = _admin_ids(
            client, admin_token, search=model, per_page=50
        )
        assert set(admin_ids) == {
            *public_ids,
            sold_id,
            pending_id,
            hidden_id,
            draft_id,
            deleted_id,
            banned_seller_id,
        }
        assert admin_pg.get("total") == total_admin_rows

        # --- Public search returns ALL legitimately-public rows, not just 2. ---
        search_ids, search_pg = _search_ids(client, q=model, per_page=50)
        assert set(search_ids) == expected_public_ids
        assert len(search_ids) == 6
        assert search_pg.get("total") == 6

        # --- Exact exclusion reason for each admin-only row. ---
        with app.app_context():
            car = Car.query.filter_by(public_id=pending_id).first()
            assert car.status == "pending"  # excluded: moderation status not in {active, sold}
            car = Car.query.filter_by(public_id=hidden_id).first()
            assert car.status == "hidden"  # excluded: moderation status
            car = Car.query.filter_by(public_id=draft_id).first()
            assert car.status == "draft"  # excluded: moderation status
            car = Car.query.filter_by(public_id=deleted_id).first()
            assert car.is_active is False  # excluded: Car.is_active is False (soft-deleted)
            car = Car.query.filter_by(public_id=banned_seller_id).first()
            seller = User.query.get(car.seller_id)
            assert car.status == "active" and car.is_active is True
            assert seller.is_active is False  # excluded: seller (User.is_active) deactivated

    def test_public_count_can_exceed_two_and_all_are_returned(self, app_ctx, client):
        """Direct regression for the "only 2 results" report: with 7 fully
        public rows for one model, search must return all 7, not 2."""
        seller_id = _make_seller(app_ctx)
        model = f"Land Cruiser Prado {uuid.uuid4().hex[:6]}"
        ids = [
            _make_car(app_ctx, seller_id, model=model, status="active", year=2010 + i)
            for i in range(7)
        ]
        search_ids, pg = _search_ids(client, q=model, per_page=50)
        assert set(search_ids) == set(ids)
        assert len(search_ids) == 7
        assert pg.get("total") == 7


# ---------------------------------------------------------------------------
# 2. Pagination correctness: >20 public rows for one model (backend default
#    per_page) must all be reachable across pages, no dup/gap, and response
#    metadata (total/pages/has_next) must agree with actual returned items.
# ---------------------------------------------------------------------------


class TestPaginationAcrossManyPublicListings:
    def test_five_or_more_public_listings_all_retrievable_first_page(self, app_ctx, client):
        seller_id = _make_seller(app_ctx)
        model = f"Land Cruiser Prado {uuid.uuid4().hex[:6]}"
        ids = [
            _make_car(app_ctx, seller_id, model=model, status="active", year=2000 + i)
            for i in range(5)
        ]
        # Requirement #1: default per_page (20) fits all 5 on page 1.
        search_ids, pg = _search_ids(client, q=model)
        assert set(search_ids) == set(ids)
        assert pg.get("page") == 1
        assert pg.get("total") == 5
        assert pg.get("has_next") is False

    def test_25_public_listings_paginate_with_no_dup_no_gap(self, app_ctx, client):
        seller_id = _make_seller(app_ctx)
        model = f"Land Cruiser Prado {uuid.uuid4().hex[:6]}"
        ids = [
            _make_car(app_ctx, seller_id, model=model, status="active", year=1990 + i)
            for i in range(25)
        ]

        collected: list[str] = []
        page = 1
        seen_pages = 0
        while True:
            page_ids, pg = _search_ids(client, q=model, per_page=20, page=page)
            assert pg.get("page") == page
            assert pg.get("per_page") == 20
            collected.extend(page_ids)
            seen_pages += 1
            if not pg.get("has_next"):
                break
            page += 1
            assert seen_pages < 10  # safety valve against an infinite loop

        # No duplicates, no gaps: every id appears exactly once.
        assert sorted(collected) == sorted(ids)
        assert len(collected) == len(set(collected)) == 25
        # Metadata sanity: two pages (20 + 5), last page total matches.
        _last_page_ids, last_pg = _search_ids(client, q=model, per_page=20, page=2)
        assert last_pg.get("total") == 25
        assert last_pg.get("pages") == 2
        assert last_pg.get("has_next") is False
        assert len(_last_page_ids) == 5

    def test_relevance_ranking_never_drops_a_matching_row(self, app_ctx, client):
        """Requirement #3: no listing disappears due to relevance ranking --
        every exact-model-match row must still be present in the full
        (paged-through) result set, regardless of ranking tier."""
        seller_id = _make_seller(app_ctx)
        model = f"Land Cruiser Prado {uuid.uuid4().hex[:6]}"
        ids = [
            _make_car(app_ctx, seller_id, model=model, status="active", year=1980 + i)
            for i in range(9)
        ]
        # Explicitly request relevance ordering (the default for a `q` search).
        search_ids, pg = _search_ids(client, q=model, sort_by="relevance", per_page=50)
        assert set(search_ids) == set(ids)
        assert pg.get("total") == 9


# ---------------------------------------------------------------------------
# 3. Response metadata (total/page/per_page/has_next) must always agree
#    with the actual returned items, for both the search endpoint and the
#    admin endpoint.
# ---------------------------------------------------------------------------


class TestResultMetadataAgreesWithActualItems:
    def test_search_metadata_matches_items_across_page_sizes(self, app_ctx, client):
        seller_id = _make_seller(app_ctx)
        model = f"Corolla Cross {uuid.uuid4().hex[:6]}"
        for i in range(6):
            _make_car(app_ctx, seller_id, brand="toyota", model=model, status="active", year=2015 + i)

        for per_page in (1, 2, 3, 5, 20, 50):
            items, pg = _search_ids(client, q=model, per_page=per_page, page=1)
            assert pg.get("total") == 6
            assert pg.get("per_page") == per_page
            expected_len = min(per_page, 6)
            assert len(items) == expected_len, (per_page, items, pg)
            assert pg.get("has_next") == (per_page < 6)

    def test_admin_metadata_matches_items(self, app_ctx, client):
        seller_id = _make_seller(app_ctx)
        model = f"Corolla Cross {uuid.uuid4().hex[:6]}"
        for i, status in enumerate(["active", "active", "pending", "hidden"]):
            _make_car(app_ctx, seller_id, brand="toyota", model=model, status=status, year=2011 + i)

        admin_token = _make_admin(app_ctx)
        items, pg = _admin_ids(client, admin_token, search=model, per_page=50)
        assert pg.get("total") == 4
        assert len(items) == 4


# ---------------------------------------------------------------------------
# 4. Admin must still see the statuses it is supposed to see -- prove the
#    investigation did not accidentally narrow admin visibility.
# ---------------------------------------------------------------------------


class TestAdminVisibilityUnnarrowed:
    @pytest.mark.parametrize(
        "status,is_active,seller_active",
        [
            ("active", True, True),
            ("sold", True, True),
            ("pending", True, True),
            ("hidden", True, True),
            ("draft", True, True),
            ("active", False, True),  # soft-deleted
            ("active", True, False),  # deactivated seller
        ],
    )
    def test_admin_sees_every_status_and_visibility_combination(
        self, app_ctx, client, status, is_active, seller_active
    ):
        seller_id = _make_seller(app_ctx, is_active=seller_active)
        model = f"AuditModel {uuid.uuid4().hex[:8]}"
        car_id = _make_car(
            app_ctx, seller_id, model=model, status=status, is_active=is_active
        )
        admin_token = _make_admin(app_ctx)
        items, _pg = _admin_ids(client, admin_token, search=model, per_page=50)
        assert car_id in items


# ---------------------------------------------------------------------------
# 5. A second, independent overlapping-model pair -- proves the audited
#    behavior (both the "correct exclusion" case and pagination/ranking
#    correctness) is generic, not Land-Cruiser-Prado-specific.
# ---------------------------------------------------------------------------


class TestSecondOverlappingModelPairDiscoveryDiscoverySport:
    def test_discovery_sport_public_count_matches_search(self, app_ctx, client):
        seller_id = _make_seller(app_ctx)
        model = f"Discovery Sport {uuid.uuid4().hex[:6]}"
        public_ids = [
            _make_car(app_ctx, seller_id, brand="land rover", model=model, status="active", year=2016 + i)
            for i in range(5)
        ]
        pending_id = _make_car(
            app_ctx, seller_id, brand="land rover", model=model, status="pending", year=2021
        )

        admin_token = _make_admin(app_ctx)
        admin_items, admin_pg = _admin_ids(client, admin_token, search=model, per_page=50)
        assert set(admin_items) == set(public_ids) | {pending_id}
        assert admin_pg.get("total") == 6

        search_items, search_pg = _search_ids(client, q=model, per_page=50)
        assert set(search_items) == set(public_ids)
        assert len(search_items) == 5
        assert search_pg.get("total") == 5
        assert pending_id not in search_items
