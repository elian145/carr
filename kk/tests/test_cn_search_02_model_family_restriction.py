"""CN-SEARCH-02 regression tests: exact-canonical-model search restriction.

Follow-up to CN-SEARCH-01 (test_cn_search_01_ranking.py). That fix made
"Land Cruiser" rank ahead of "Land Cruiser Prado" -- but Prado still
*appeared*, just lower. Product feedback: that's not enough. When the query
exactly matches a known model name, results must be *restricted* to that
model family (including numeric/generation variants, e.g. "Land Cruiser
300"/"70"/"76") -- a distinct sibling model whose name merely starts with
the same words (e.g. "Land Cruiser Prado") must be excluded outright, not
just demoted.

Implementation (``kk/listing_search.py``):

- ``_canonical_model_names()`` loads every model name across every brand
  from the app's existing canonical vehicle catalog
  (``assets/car_catalog.json`` -- the same static dataset
  ``kk/catalog_service.py::seed_catalog`` uses to populate
  ``CatalogVehicleModel``, and that the Flutter app bundles for its
  make/model pickers). Nothing is hardcoded per brand/model.
- ``_sibling_canonical_models(term_norm)`` returns every OTHER canonical
  model name that starts with ``term_norm`` followed by a separator and a
  WORD (not a digit) -- e.g. "land cruiser prado" for "land cruiser". A
  digit right after the separator (e.g. "land cruiser 70") is treated as a
  generation/variant of the SAME model and is never a sibling, regardless
  of whether that specific generation is itself cataloged.
- ``_exclude_sibling_models()`` adds a ``NOT`` filter removing any row whose
  ``Car.model`` matches (or extends) a sibling model name, applied inside
  ``apply_listing_text_search()`` -- i.e. before ``ORDER BY``/``LIMIT`` --
  so an excluded sibling can never resurface on a later page.
- The restriction only engages when the *normalized query itself* exactly
  matches a known canonical model name. Any other query (including partial
  words, non-cataloged fictitious models, or plain free text over
  title/description/trim/location) keeps the prior broad, ranked-not-
  excluded behavior -- see test_cn_search_01_ranking.py's
  ``test_non_canonical_query_ranks_related_model_lower_without_excluding_it``.

This file seeds three independent overlapping-model pairs pulled from the
*real* ``assets/car_catalog.json`` (Toyota "Land Cruiser"/"Land Cruiser
Prado", Toyota "Corolla"/"Corolla Cross", Land Rover "Discovery"/"Discovery
Sport") to prove the fix is generic across brands/models, not hardcoded.
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
        prefix="carlist_cnsearch02_", ignore_cleanup_errors=True
    )
    os.environ["APP_ENV"] = "testing"
    os.environ["SMS_PROVIDER"] = "console"
    os.environ.pop("LISTING_REQUIRE_APPROVAL", None)
    os.environ["DB_PATH"] = os.path.join(tmp.name, "cnsearch02.db")

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
    app, _client, db, User, Car = app_ctx
    with app.app_context():
        seller = User(
            username=f"cnsearch02_seller_{uuid.uuid4().hex[:8]}",
            phone_number=f"+1555{uuid.uuid4().int % 10_000_000:07d}",
            first_name="CnSearch02",
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

        # --- Toyota Land Cruiser family --------------------------------
        land_cruiser = _car(
            title="2020 Toyota Land Cruiser", brand="Toyota", model="Land Cruiser"
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
        # Not literally enumerated in assets/car_catalog.json -- proves the
        # numeric-continuation rule (not literal catalog membership) is what
        # keeps a generation variant included.
        land_cruiser_300 = _car(
            title="2022 Toyota Land Cruiser 300",
            brand="Toyota",
            model="Land Cruiser 300",
        )
        land_cruiser_prado = [
            _car(
                title=f"20{18 + i} Toyota Land Cruiser Prado",
                brand="Toyota",
                model="Land Cruiser Prado",
                year=2018 + i,
            )
            for i in range(5)
        ]

        # --- Toyota Corolla family --------------------------------------
        corolla = _car(
            title="2018 Toyota Corolla", brand="Toyota", model="Corolla",
            body_type="sedan",
        )
        corolla_cross = _car(
            title="2019 Toyota Corolla Cross", brand="Toyota", model="Corolla Cross"
        )

        # --- Land Rover Discovery family (third, independent overlapping
        # pair pulled from the real catalog) ------------------------------
        discovery = _car(
            title="2019 Land Rover Discovery",
            brand="Land Rover",
            model="Discovery",
        )
        discovery_sport = [
            _car(
                title=f"20{19 + i} Land Rover Discovery Sport",
                brand="Land Rover",
                model="Discovery Sport",
                year=2019 + i,
            )
            for i in range(3)
        ]

        # --- Unrelated controls ------------------------------------------
        camry = _car(
            title="2019 Toyota Camry", brand="Toyota", model="Camry",
            body_type="sedan",
        )
        civic = _car(
            title="2018 Honda Civic", brand="Honda", model="Civic",
            body_type="sedan",
        )
        # Free-text control: matches only via description, not any model
        # name -- proves broad multi-field search still works untouched.
        sunroof_car = _car(
            title="2017 Toyota Camry Special Edition",
            brand="Toyota",
            model="Camry",
            body_type="sedan",
            description="Comes with a factory panoramic sunroof and leather seats.",
        )

        db.session.commit()

        return {
            "land_cruiser": land_cruiser.public_id,
            "land_cruiser_70": land_cruiser_70.public_id,
            "land_cruiser_76": land_cruiser_76.public_id,
            "land_cruiser_300": land_cruiser_300.public_id,
            "land_cruiser_prado": [c.public_id for c in land_cruiser_prado],
            "corolla": corolla.public_id,
            "corolla_cross": corolla_cross.public_id,
            "discovery": discovery.public_id,
            "discovery_sport": [c.public_id for c in discovery_sport],
            "camry": camry.public_id,
            "civic": civic.public_id,
            "sunroof_car": sunroof_car.public_id,
        }


def _search(client, **params):
    r = client.get("/api/cars", query_string=params)
    assert r.status_code == 200, r.data
    payload = r.get_json() or {}
    return [c["id"] for c in payload.get("cars", [])], payload.get("pagination", {})


# ---------------------------------------------------------------------------
# 1. Land Cruiser vs Land Cruiser Prado.
# ---------------------------------------------------------------------------


def test_land_cruiser_excludes_prado(app_ctx, seeded_cars):
    _app, client, *_ = app_ctx
    ids, _pg = _search(client, q="Land Cruiser", per_page=50)
    assert seeded_cars["land_cruiser"] in ids
    for prado_id in seeded_cars["land_cruiser_prado"]:
        assert prado_id not in ids


def test_land_cruiser_prado_query_includes_only_prado(app_ctx, seeded_cars):
    """Exact longer-model search: 'Land Cruiser Prado' is itself a known
    canonical model, so it restricts to (only) itself -- the shorter base
    'Land Cruiser' family never matches this more specific query."""
    _app, client, *_ = app_ctx
    ids, _pg = _search(client, q="Land Cruiser Prado", per_page=50)
    assert set(ids) == set(seeded_cars["land_cruiser_prado"])
    assert seeded_cars["land_cruiser"] not in ids
    assert seeded_cars["land_cruiser_70"] not in ids
    assert seeded_cars["land_cruiser_300"] not in ids


# ---------------------------------------------------------------------------
# 2. Numeric Land Cruiser variants remain included (same family).
# ---------------------------------------------------------------------------


def test_land_cruiser_numeric_variants_remain_included(app_ctx, seeded_cars):
    _app, client, *_ = app_ctx
    ids, _pg = _search(client, q="Land Cruiser", per_page=50)
    assert seeded_cars["land_cruiser_70"] in ids
    assert seeded_cars["land_cruiser_76"] in ids
    # Not literally in assets/car_catalog.json, but still a numeric
    # continuation of the same base model -- must not be excluded.
    assert seeded_cars["land_cruiser_300"] in ids


def test_land_cruiser_result_set_is_exactly_the_family(app_ctx, seeded_cars):
    """No more, no less: exactly the real family members, nothing from the
    Prado sibling, nothing unrelated."""
    _app, client, *_ = app_ctx
    ids, _pg = _search(client, q="Land Cruiser", per_page=50)
    assert set(ids) == {
        seeded_cars["land_cruiser"],
        seeded_cars["land_cruiser_70"],
        seeded_cars["land_cruiser_76"],
        seeded_cars["land_cruiser_300"],
    }


# ---------------------------------------------------------------------------
# 3. Corolla vs Corolla Cross (second overlapping pair).
# ---------------------------------------------------------------------------


def test_corolla_excludes_corolla_cross(app_ctx, seeded_cars):
    _app, client, *_ = app_ctx
    ids, _pg = _search(client, q="Corolla", per_page=50)
    assert seeded_cars["corolla"] in ids
    assert seeded_cars["corolla_cross"] not in ids


def test_corolla_cross_exact_query_includes_only_corolla_cross(app_ctx, seeded_cars):
    _app, client, *_ = app_ctx
    ids, _pg = _search(client, q="Corolla Cross", per_page=50)
    assert ids == [seeded_cars["corolla_cross"]]


# ---------------------------------------------------------------------------
# 4. Discovery vs Discovery Sport -- a THIRD, independent overlapping pair
# pulled from the real catalog (Land Rover), proving genericity.
# ---------------------------------------------------------------------------


def test_discovery_excludes_discovery_sport(app_ctx, seeded_cars):
    _app, client, *_ = app_ctx
    ids, _pg = _search(client, q="Discovery", per_page=50)
    assert seeded_cars["discovery"] in ids
    for sport_id in seeded_cars["discovery_sport"]:
        assert sport_id not in ids


def test_discovery_sport_exact_query_includes_only_discovery_sport(
    app_ctx, seeded_cars
):
    _app, client, *_ = app_ctx
    ids, _pg = _search(client, q="Discovery Sport", per_page=50)
    assert set(ids) == set(seeded_cars["discovery_sport"])
    assert seeded_cars["discovery"] not in ids


# ---------------------------------------------------------------------------
# 5. Normal free-text search stays broad when the query is NOT an exact
# canonical model match.
# ---------------------------------------------------------------------------


def test_non_model_free_text_query_still_matches_description(app_ctx, seeded_cars):
    """'sunroof' is not a model name at all -- broad multi-field search
    (title/description/trim/location/etc.) must be completely unaffected by
    the CN-SEARCH-02 restriction."""
    _app, client, *_ = app_ctx
    ids, _pg = _search(client, q="sunroof", per_page=50)
    assert ids == [seeded_cars["sunroof_car"]]


def test_partial_model_word_query_does_not_trigger_restriction(app_ctx, seeded_cars):
    """'cruiser' alone is not itself a canonical model name (only "Land
    Cruiser", "Land Cruiser Prado", etc. are) -- it must broadly match every
    row containing that token, Prado included, since restriction never
    engages for a non-exact query."""
    _app, client, *_ = app_ctx
    ids, _pg = _search(client, q="cruiser", per_page=50)
    assert seeded_cars["land_cruiser"] in ids
    assert seeded_cars["land_cruiser_70"] in ids
    for prado_id in seeded_cars["land_cruiser_prado"]:
        assert prado_id in ids


def test_brand_only_query_is_unrestricted(app_ctx, seeded_cars):
    """A bare brand name is not a model name -- must return every listing
    for that brand, including both Land Cruiser and Prado."""
    _app, client, *_ = app_ctx
    ids, _pg = _search(client, q="Toyota", per_page=50)
    assert seeded_cars["land_cruiser"] in ids
    for prado_id in seeded_cars["land_cruiser_prado"]:
        assert prado_id in ids
    assert seeded_cars["corolla"] in ids
    assert seeded_cars["corolla_cross"] in ids
    assert seeded_cars["camry"] in ids


# ---------------------------------------------------------------------------
# 6. Pagination: an excluded sibling model must never reappear on any page.
# ---------------------------------------------------------------------------


def test_pagination_never_surfaces_excluded_sibling_model(app_ctx, seeded_cars):
    _app, client, *_ = app_ctx
    seen: list[str] = []
    page = 1
    while True:
        ids, pg = _search(client, q="Land Cruiser", per_page=2, page=page)
        seen.extend(ids)
        if not pg.get("has_next"):
            break
        page += 1

    assert set(seen) == {
        seeded_cars["land_cruiser"],
        seeded_cars["land_cruiser_70"],
        seeded_cars["land_cruiser_76"],
        seeded_cars["land_cruiser_300"],
    }
    for prado_id in seeded_cars["land_cruiser_prado"]:
        assert prado_id not in seen


def test_pagination_total_reflects_restricted_set_not_broad_match(
    app_ctx, seeded_cars
):
    """The ``pagination.total`` count itself must reflect the *restricted*
    family size (4: exact + 70 + 76 + 300), not the broader 9-row set that
    would match "land"/"cruiser" tokens before CN-SEARCH-02's exclusion."""
    _app, client, *_ = app_ctx
    _ids, pg = _search(client, q="Land Cruiser", per_page=2, page=1)
    assert pg.get("total") == 4
