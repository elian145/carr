"""CN-SEARCH-01 regression tests: exactness-aware free-text search ranking.

Bug report: searching "Land Cruiser" mainly/only returned "Land Cruiser
Prado" listings; real "Land Cruiser" listings barely appeared.

Root causes (both fixed here):

1. ``kk/listing_search.py::apply_listing_text_search`` filtered rows
   correctly -- both "Land Cruiser" and "Land Cruiser Prado" legitimately
   contain the "land"/"cruiser" tokens the query is looking for -- but its
   *ranking* did not distinguish an exact/near-exact model match from a
   broader match that merely contains the same tokens. Ties fell back to
   recency/featured status. If "Land Cruiser Prado" listings simply
   outnumbered (or were newer/featured relative to) the real "Land Cruiser"
   listings, they dominated the paginated result window and hid the exact
   matches on later pages. This affected Postgres (weak ``ts_rank_cd``
   discrimination between same-token documents) and was even worse on
   SQLite/ILIKE fallback, where no rank was computed at all (pure recency
   order). Fixed by ``build_relevance_rank_expr()``, a generic, brand/model-
   agnostic tiered ``CASE`` score (exact model > brand+model exact > model
   variant e.g. "Land Cruiser 70" > brand+model suffix match > related-but-
   different model e.g. "Land Cruiser Prado" > substring elsewhere), used
   for ordering on *both* dialects.

2. ``lib/features/home/home_fetch_core.dart::_buildFilters`` unconditionally
   fell back to the home feed's *ambient* default sort (``random`` for new
   users, ``recommended`` after activity) whenever the user had not
   explicitly picked a sort option -- including during an active keyword
   search. Because that fallback sent an explicit ``sort_by=random`` (or
   ``recommended``) on essentially every search request, the backend's
   "auto-upgrade empty/relevance/rank sort_by to relevance when a rank
   expression exists" logic (`kk/routes/cars.py::get_cars`) never triggered
   for real app traffic: matches were shuffled (or interest-boosted)
   instead of ranked by relevance at all. With more "Land Cruiser Prado"
   rows than real "Land Cruiser" rows, a random sample was overwhelmingly
   Prado. Fixed by ``homeFeedDefaultSortAllowed()``
   (`lib/features/home/home_filters_query.dart`) plus the corresponding
   `_buildFilters` change -- see `test/home_filters_query_test.dart` for the
   Flutter-side regression tests for that half of the fix.

This file covers the backend half end-to-end via ``GET /api/cars?q=...``
(SQLite ILIKE-fallback dialect, same as the rest of the suite -- the ranking
fix is dialect-agnostic by construction, see the ``build_relevance_rank_expr``
docstring in ``kk/listing_search.py``).
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
        prefix="carlist_cnsearch01_", ignore_cleanup_errors=True
    )
    os.environ["APP_ENV"] = "testing"
    os.environ["SMS_PROVIDER"] = "console"
    os.environ.pop("LISTING_REQUIRE_APPROVAL", None)
    os.environ["DB_PATH"] = os.path.join(tmp.name, "cnsearch01.db")

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


@pytest.fixture(scope="module")
def seeded_cars(app_ctx):
    """Seed a catalog reproducing the reported bug shape: a handful of real
    "Land Cruiser" listings alongside many more "Land Cruiser Prado"
    listings (a different, but overlapping-named, real Toyota model -- see
    ``assets/car_catalog.json``'s Toyota model list), plus a second,
    independent overlapping-model pair ("Corolla" / "Corolla Cross") to
    prove the fix is generic and not specific to Land Cruiser/Prado.
    """
    app, _client, db, User, Car = app_ctx
    with app.app_context():
        seller = User(
            username=f"cnsearch01_seller_{uuid.uuid4().hex[:8]}",
            phone_number=f"+1555{uuid.uuid4().int % 10_000_000:07d}",
            first_name="CnSearch01",
            last_name="Seller",
            is_active=True,
            is_verified=True,
            phone_verified=True,
            public_id=f"pub-{uuid.uuid4().hex[:12]}",
        )
        seller.set_password("Aa123456!")
        db.session.add(seller)
        db.session.commit()

        def _car(**overrides):
            defaults = dict(
                seller_id=seller.id,
                year=2020,
                mileage=10000,
                engine_type="gas",
                transmission="auto",
                drive_type="fwd",
                condition="used",
                body_type="suv",
                price=25000.0,
                location="Erbil",
                is_active=True,
            )
            defaults.update(overrides)
            car = Car(**defaults)
            db.session.add(car)
            return car

        land_cruiser = _car(
            title="2020 Toyota Land Cruiser",
            brand="Toyota",
            model="Land Cruiser",
        )
        land_cruiser_70 = _car(
            title="2019 Toyota Land Cruiser 70",
            brand="Toyota",
            model="Land Cruiser 70",
        )
        land_cruiser_76 = _car(
            title="2021 Toyota Land Cruiser 76",
            brand="Toyota",
            model="Land Cruiser 76",
        )
        # Deliberately many more Prado listings than real Land Cruiser
        # listings -- this is the exact shape that triggered the bug: if
        # ranking doesn't discriminate, sheer Prado volume dominates any
        # recency/random ordering and any fixed-size results page.
        prados = [
            _car(
                title=f"20{18 + i} Toyota Land Cruiser Prado",
                brand="Toyota",
                model="Land Cruiser Prado",
                year=2018 + i,
            )
            for i in range(8)
        ]

        corolla = _car(
            title="2018 Toyota Corolla",
            brand="Toyota",
            model="Corolla",
            body_type="sedan",
        )
        corolla_cross = _car(
            title="2019 Toyota Corolla Cross",
            brand="Toyota",
            model="Corolla Cross",
        )

        camry = _car(
            title="2019 Toyota Camry",
            brand="Toyota",
            model="Camry",
            body_type="sedan",
        )
        civic = _car(
            title="2018 Honda Civic",
            brand="Honda",
            model="Civic",
            body_type="sedan",
        )
        db.session.commit()

        return {
            "land_cruiser": land_cruiser.public_id,
            "land_cruiser_70": land_cruiser_70.public_id,
            "land_cruiser_76": land_cruiser_76.public_id,
            "prados": [p.public_id for p in prados],
            "corolla": corolla.public_id,
            "corolla_cross": corolla_cross.public_id,
            "camry": camry.public_id,
            "civic": civic.public_id,
        }


def _search(client, **params):
    r = client.get("/api/cars", query_string=params)
    assert r.status_code == 200, r.data
    payload = r.get_json() or {}
    return [c["id"] for c in payload.get("cars", [])], payload.get("pagination", {})


# ---------------------------------------------------------------------------
# 1. "Land Cruiser": exact listings appear and rank ahead of Prado listings.
# ---------------------------------------------------------------------------


def test_land_cruiser_query_returns_exact_and_variant_listings(app_ctx, seeded_cars):
    _app, client, *_ = app_ctx
    ids, _pg = _search(client, q="Land Cruiser", per_page=50)
    assert seeded_cars["land_cruiser"] in ids
    assert seeded_cars["land_cruiser_70"] in ids
    assert seeded_cars["land_cruiser_76"] in ids
    # Prado legitimately contains both query tokens -- it must still appear,
    # just ranked lower (see next test), never excluded outright.
    for prado_id in seeded_cars["prados"]:
        assert prado_id in ids
    # Unrelated brand/model must never match.
    assert seeded_cars["civic"] not in ids
    assert seeded_cars["camry"] not in ids


def test_land_cruiser_ranks_ahead_of_land_cruiser_prado(app_ctx, seeded_cars):
    _app, client, *_ = app_ctx
    ids, _pg = _search(client, q="Land Cruiser", per_page=50)
    lc_index = ids.index(seeded_cars["land_cruiser"])
    for prado_id in seeded_cars["prados"]:
        assert lc_index < ids.index(prado_id), (
            "exact 'Land Cruiser' must rank ahead of every 'Land Cruiser "
            "Prado' listing"
        )


def test_land_cruiser_variants_rank_ahead_of_prado(app_ctx, seeded_cars):
    """"Land Cruiser 70"/"Land Cruiser 76" are variants of the same base
    model (numeric generation suffix) and must outrank the different,
    broader "Land Cruiser Prado" model."""
    _app, client, *_ = app_ctx
    ids, _pg = _search(client, q="Land Cruiser", per_page=50)
    lc70_index = ids.index(seeded_cars["land_cruiser_70"])
    lc76_index = ids.index(seeded_cars["land_cruiser_76"])
    min_prado_index = min(ids.index(p) for p in seeded_cars["prados"])
    assert lc70_index < min_prado_index
    assert lc76_index < min_prado_index


# ---------------------------------------------------------------------------
# 2/3. Case-insensitivity + whitespace normalization produce identical
# results/ranking to the canonical query.
# ---------------------------------------------------------------------------


def test_land_cruiser_query_is_case_insensitive(app_ctx, seeded_cars):
    _app, client, *_ = app_ctx
    canonical_ids, _ = _search(client, q="Land Cruiser", per_page=50)
    lower_ids, _ = _search(client, q="land cruiser", per_page=50)
    assert lower_ids == canonical_ids


def test_land_cruiser_query_normalizes_whitespace(app_ctx, seeded_cars):
    _app, client, *_ = app_ctx
    canonical_ids, _ = _search(client, q="Land Cruiser", per_page=50)
    messy_ids, _ = _search(client, q="  land   cruiser  ", per_page=50)
    assert messy_ids == canonical_ids


# ---------------------------------------------------------------------------
# 4. "Land Cruiser Prado": Prado listings rank first (and only Prado
# listings match -- a plain "Land Cruiser" must not satisfy this more
# specific query).
# ---------------------------------------------------------------------------


def test_land_cruiser_prado_query_returns_only_prado_listings(app_ctx, seeded_cars):
    _app, client, *_ = app_ctx
    ids, _pg = _search(client, q="Land Cruiser Prado", per_page=50)
    assert set(ids) == set(seeded_cars["prados"])
    assert seeded_cars["land_cruiser"] not in ids
    assert seeded_cars["land_cruiser_70"] not in ids
    assert seeded_cars["land_cruiser_76"] not in ids


# ---------------------------------------------------------------------------
# 5. "Prado": Prado listings appear; the plain "Land Cruiser" listing (which
# does not contain the word "Prado" anywhere) must not.
# ---------------------------------------------------------------------------


def test_prado_query_returns_prado_listings_only(app_ctx, seeded_cars):
    _app, client, *_ = app_ctx
    ids, _pg = _search(client, q="Prado", per_page=50)
    assert set(ids) == set(seeded_cars["prados"])
    assert seeded_cars["land_cruiser"] not in ids
    assert seeded_cars["land_cruiser_70"] not in ids
    assert seeded_cars["land_cruiser_76"] not in ids


# ---------------------------------------------------------------------------
# 6. A second, independent overlapping-model pair behaves the same way --
# proves the fix is generic, not Land-Cruiser-specific.
# ---------------------------------------------------------------------------


def test_corolla_query_ranks_exact_model_ahead_of_corolla_cross(app_ctx, seeded_cars):
    _app, client, *_ = app_ctx
    ids, _pg = _search(client, q="Corolla", per_page=50)
    assert seeded_cars["corolla"] in ids
    assert seeded_cars["corolla_cross"] in ids
    assert ids.index(seeded_cars["corolla"]) < ids.index(seeded_cars["corolla_cross"])


def test_corolla_cross_query_returns_only_corolla_cross(app_ctx, seeded_cars):
    _app, client, *_ = app_ctx
    ids, _pg = _search(client, q="Corolla Cross", per_page=50)
    assert ids == [seeded_cars["corolla_cross"]]


# ---------------------------------------------------------------------------
# 7. Pagination must not hide the exact match behind partial/broader
# matches: with a small page size and many more Prado rows than real Land
# Cruiser rows, the exact match must still land on page 1.
# ---------------------------------------------------------------------------


def test_pagination_does_not_hide_exact_match_behind_partial_matches(
    app_ctx, seeded_cars
):
    _app, client, *_ = app_ctx
    ids, pagination = _search(client, q="Land Cruiser", per_page=3, page=1)
    assert len(ids) == 3
    assert seeded_cars["land_cruiser"] in ids, (
        "the exact 'Land Cruiser' match must be on page 1 even though there "
        "are 8 'Land Cruiser Prado' rows and only a 3-row page size"
    )
    # Total count must still reflect every legitimately matching row
    # (exact + variants + Prado) -- ranking must not have narrowed the
    # underlying result set, only reordered it.
    assert pagination.get("total") == 1 + 2 + len(seeded_cars["prados"])


def test_pagination_page_two_still_consistent_with_ranking(app_ctx, seeded_cars):
    """Sanity check: paging through with a small page size and concatenating
    pages reproduces the same order as a single large-page request (i.e.
    ranking is applied consistently before LIMIT/OFFSET, not per-page)."""
    _app, client, *_ = app_ctx
    full_ids, _ = _search(client, q="Land Cruiser", per_page=50, page=1)

    paged_ids: list[str] = []
    page = 1
    while True:
        page_ids, pg = _search(client, q="Land Cruiser", per_page=3, page=page)
        paged_ids.extend(page_ids)
        if not pg.get("has_next"):
            break
        page += 1

    assert paged_ids == full_ids
