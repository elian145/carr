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

FOLLOW-UP (CN-SEARCH-02, see ``test_cn_search_02_model_family_restriction.py``):
ranking alone (tier 5, "related but different model") still let "Land
Cruiser Prado" appear -- just lower -- for a "Land Cruiser" search. Product
feedback wanted it excluded entirely whenever the query exactly matches a
known canonical model name. That stricter exclusion is layered on top of
(and reuses) the ranking machinery here; the tests below were updated where
they previously asserted the old "still appears, just lower" behavior, and
now note where CN-SEARCH-02 governs instead.

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
    ``assets/car_catalog.json``'s Toyota model list), a second independent
    overlapping-model pair ("Corolla" / "Corolla Cross"), and a fictitious
    (NOT in the canonical catalog) overlapping-model pair used to prove
    ranking-only behavior still applies when the query does not exactly
    match a known canonical model (CN-SEARCH-02 requirement #4).
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
        # listings -- this is the exact shape that triggered the original
        # bug report. Under CN-SEARCH-02 these are now excluded outright
        # from a "Land Cruiser" search (see that test file); they remain
        # seeded here so this file's case-insensitivity/whitespace tests
        # exercise the same realistic, Prado-heavy dataset.
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

        # Fictitious brand/model NOT present in assets/car_catalog.json --
        # proves ranking (not exclusion) governs when the query itself is
        # not a known canonical model (CN-SEARCH-02 requirement #4: "if the
        # query does NOT exactly match a known model, retain normal broad
        # keyword search behavior").
        zeta_x = _car(
            title="2021 Zetaworks Zeta X",
            brand="Zetaworks",
            model="Zeta X",
        )
        zeta_x_sport = _car(
            title="2021 Zetaworks Zeta X Sport",
            brand="Zetaworks",
            model="Zeta X Sport",
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
            "zeta_x": zeta_x.public_id,
            "zeta_x_sport": zeta_x_sport.public_id,
        }


def _search(client, **params):
    r = client.get("/api/cars", query_string=params)
    assert r.status_code == 200, r.data
    payload = r.get_json() or {}
    return [c["id"] for c in payload.get("cars", [])], payload.get("pagination", {})


# ---------------------------------------------------------------------------
# 1. "Land Cruiser": exact + variant listings appear; Prado is excluded
#    outright (CN-SEARCH-02 -- see that test file for the full matrix).
# ---------------------------------------------------------------------------


def test_land_cruiser_query_returns_exact_and_variant_listings(app_ctx, seeded_cars):
    _app, client, *_ = app_ctx
    ids, _pg = _search(client, q="Land Cruiser", per_page=50)
    assert seeded_cars["land_cruiser"] in ids
    assert seeded_cars["land_cruiser_70"] in ids
    assert seeded_cars["land_cruiser_76"] in ids
    # CN-SEARCH-02: "Land Cruiser" is an exact canonical model match, so the
    # distinct sibling model "Land Cruiser Prado" is excluded entirely, not
    # merely ranked lower.
    for prado_id in seeded_cars["prados"]:
        assert prado_id not in ids
    # Unrelated brand/model must never match.
    assert seeded_cars["civic"] not in ids
    assert seeded_cars["camry"] not in ids


def test_land_cruiser_variants_rank_ahead_of_each_other_by_recency(
    app_ctx, seeded_cars
):
    """With Prado excluded, the remaining Land Cruiser family members are
    all tier-90 ("model variant") or tier-100 (exact) matches; the exact
    match must still be first."""
    _app, client, *_ = app_ctx
    ids, _pg = _search(client, q="Land Cruiser", per_page=50)
    assert ids[0] == seeded_cars["land_cruiser"]
    assert set(ids) == {
        seeded_cars["land_cruiser"],
        seeded_cars["land_cruiser_70"],
        seeded_cars["land_cruiser_76"],
    }


def test_non_canonical_query_ranks_related_model_lower_without_excluding_it(
    app_ctx, seeded_cars
):
    """CN-SEARCH-02 requirement #4: when the query does NOT exactly match a
    known canonical model (here: a fictitious brand/model absent from
    ``assets/car_catalog.json``), normal broad ranking applies -- the
    related-but-different model ("Zeta X Sport") still appears, just ranked
    below the exact match, rather than being excluded."""
    _app, client, *_ = app_ctx
    ids, _pg = _search(client, q="Zeta X", per_page=50)
    assert seeded_cars["zeta_x"] in ids
    assert seeded_cars["zeta_x_sport"] in ids
    assert ids.index(seeded_cars["zeta_x"]) < ids.index(seeded_cars["zeta_x_sport"])


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
# 4. "Land Cruiser Prado": Prado listings match (and only Prado listings --
# a plain "Land Cruiser" must not satisfy this more specific query).
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
# proves the fix is generic, not Land-Cruiser-specific. Full exclusion
# matrix lives in test_cn_search_02_model_family_restriction.py.
# ---------------------------------------------------------------------------


def test_corolla_query_excludes_corolla_cross(app_ctx, seeded_cars):
    _app, client, *_ = app_ctx
    ids, _pg = _search(client, q="Corolla", per_page=50)
    assert seeded_cars["corolla"] in ids
    assert seeded_cars["corolla_cross"] not in ids


def test_corolla_cross_query_returns_only_corolla_cross(app_ctx, seeded_cars):
    _app, client, *_ = app_ctx
    ids, _pg = _search(client, q="Corolla Cross", per_page=50)
    assert ids == [seeded_cars["corolla_cross"]]


# ---------------------------------------------------------------------------
# 7. Pagination must not resurrect an excluded sibling model, and must not
# hide an exact match behind a small page size either.
# ---------------------------------------------------------------------------


def test_pagination_does_not_resurrect_excluded_sibling_model(app_ctx, seeded_cars):
    _app, client, *_ = app_ctx
    ids, pagination = _search(client, q="Land Cruiser", per_page=2, page=1)
    assert seeded_cars["land_cruiser"] in ids
    # Only the 3 real family members (exact + 2 numeric variants) can ever
    # match "Land Cruiser" now that Prado is excluded at the query level --
    # so the total must reflect that, and no amount of paging can surface
    # a Prado id (there are none left in the underlying result set).
    assert pagination.get("total") == 3


def test_pagination_page_two_still_consistent_with_ranking(app_ctx, seeded_cars):
    """Sanity check: paging through with a small page size and concatenating
    pages reproduces the same order as a single large-page request (i.e.
    ranking/exclusion is applied consistently before LIMIT/OFFSET, not
    per-page), and no excluded sibling model id ever appears on any page."""
    _app, client, *_ = app_ctx
    full_ids, _ = _search(client, q="Land Cruiser", per_page=50, page=1)

    paged_ids: list[str] = []
    page = 1
    while True:
        page_ids, pg = _search(client, q="Land Cruiser", per_page=2, page=page)
        paged_ids.extend(page_ids)
        if not pg.get("has_next"):
            break
        page += 1

    assert paged_ids == full_ids
    for prado_id in seeded_cars["prados"]:
        assert prado_id not in paged_ids
