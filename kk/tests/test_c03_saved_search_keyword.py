"""C-03 follow-up regression tests: saved-search keyword (`q`) passthrough.

PRODUCTION_AUDIT.md's C-03 finding ("keyword search is unreachable") was
already fixed for live browsing (`homeFiltersToApiQuery` sends `q`; the
backend's `apply_listing_text_search()` in kk/listing_search.py performs
real full-text/ILIKE search). A follow-up investigation found the free-text
keyword was silently dropped from the *saved-search* path: neither
``homeFiltersToSavedSearchJson`` (lib/features/home/home_filters_query.dart)
nor ``car_matches_filters`` (kk/listing_filters.py) knew about a keyword/`q`
field, so saving a search while a keyword was active produced an alert
filter that ignored the keyword entirely.

This file tests the backend half of that fix: ``car_matches_filters``'s new
``q`` support (see ``_text_search_matches`` in kk/listing_filters.py), which
evaluates `q` using the same normalization (``normalize_search_query``) and
the same primary searchable fields (title, brand, model, trim, location,
description, color) as the live ``/api/cars`` search in kk/listing_search.py
-- an AND-of-tokens / OR-across-fields substring approximation of Postgres
``websearch_to_tsquery``, documented in detail on ``_text_search_matches``.

Uses the same ``app_ctx`` / ``_car()`` fixture pattern as
``kk/tests/test_a04_filter_matcher_parity.py`` and
``kk/tests/test_be07_saved_search_filter_bounds.py`` -- plain, unmanaged
``Car`` instances inside a real (unused) app/DB context, since
``car_matches_filters()`` is a pure function that only reads attributes off
the ``car`` object it is given.
"""
from __future__ import annotations

import os
import sys
import tempfile
from pathlib import Path

import pytest

_REPO_ROOT = Path(__file__).resolve().parents[2]
if str(_REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(_REPO_ROOT))


# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------


@pytest.fixture(scope="module")
def app_ctx():
    tmp = tempfile.TemporaryDirectory(prefix="carlist_c03_", ignore_cleanup_errors=True)
    os.environ["APP_ENV"] = "testing"
    os.environ["SMS_PROVIDER"] = "console"
    os.environ["DB_PATH"] = os.path.join(tmp.name, "c03.db")

    from kk.app_factory import create_app

    app, _socketio, *_ = create_app()
    from kk.models import db

    with app.app_context():
        db.drop_all()
        db.create_all()

    yield app

    with app.app_context():
        db.session.remove()
        db.engine.dispose()
    tmp.cleanup()


def _car(**overrides):
    """Build an unmanaged ``Car`` row; never added to a session."""
    from kk.models import Car

    defaults = dict(
        seller_id=1,
        public_id="car-c03-test",
        brand="toyota",
        model="camry",
        year=2020,
        mileage=50000,
        price=20000,
        location="Erbil",
        condition="used",
        transmission="automatic",
        body_type="sedan",
        drive_type="fwd",
        color="black",
        trim=None,
        title="",
        description=None,
        fuel_type=None,
        engine_type=None,
        is_active=True,
    )
    defaults.update(overrides)
    return Car(**defaults)


# ===========================================================================
# No q -> no keyword condition
# ===========================================================================


class TestNoKeyword:
    def test_no_q_key_matches_regardless_of_content(self, app_ctx):
        from kk.listing_filters import car_matches_filters

        with app_ctx.app_context():
            car = _car(title="anything at all")
            assert car_matches_filters(car, {}) is True
            assert car_matches_filters(car, {"brand": "toyota"}) is True

    def test_empty_q_matches_regardless_of_content(self, app_ctx):
        from kk.listing_filters import car_matches_filters

        with app_ctx.app_context():
            car = _car(title="anything at all")
            assert car_matches_filters(car, {"q": ""}) is True

    def test_whitespace_only_q_matches_regardless_of_content(self, app_ctx):
        from kk.listing_filters import car_matches_filters

        with app_ctx.app_context():
            car = _car(title="anything at all")
            assert car_matches_filters(car, {"q": "   "}) is True


# ===========================================================================
# q present -> keyword is actually evaluated
# ===========================================================================


class TestKeywordMatching:
    def test_matches_brand(self, app_ctx):
        from kk.listing_filters import car_matches_filters

        with app_ctx.app_context():
            car = _car(brand="toyota", model="land cruiser")
            assert car_matches_filters(car, {"q": "toyota"}) is True

    def test_matches_model(self, app_ctx):
        from kk.listing_filters import car_matches_filters

        with app_ctx.app_context():
            car = _car(brand="toyota", model="land cruiser")
            assert car_matches_filters(car, {"q": "cruiser"}) is True

    def test_matches_description(self, app_ctx):
        from kk.listing_filters import car_matches_filters

        with app_ctx.app_context():
            car = _car(description="Well maintained, sunroof, low mileage")
            assert car_matches_filters(car, {"q": "sunroof"}) is True

    def test_matches_title_location_color(self, app_ctx):
        from kk.listing_filters import car_matches_filters

        with app_ctx.app_context():
            assert car_matches_filters(
                _car(title="Clean title Land Cruiser"), {"q": "clean title"}
            ) is True
            assert car_matches_filters(_car(location="Erbil"), {"q": "erbil"}) is True
            assert car_matches_filters(_car(color="black"), {"q": "black"}) is True

    def test_matches_trim(self, app_ctx):
        from kk.listing_filters import car_matches_filters

        with app_ctx.app_context():
            car = _car(trim="GXR")
            assert car_matches_filters(car, {"q": "gxr"}) is True

    def test_case_insensitive(self, app_ctx):
        from kk.listing_filters import car_matches_filters

        with app_ctx.app_context():
            car = _car(brand="Toyota")
            assert car_matches_filters(car, {"q": "TOYOTA"}) is True
            assert car_matches_filters(car, {"q": "ToYoTa"}) is True

    def test_multi_token_query_requires_every_token_present(self, app_ctx):
        """Mirrors websearch_to_tsquery's default AND-of-terms semantics:
        every whitespace-separated token in `q` must appear somewhere across
        the searchable fields (not necessarily the same field) for a match."""
        from kk.listing_filters import car_matches_filters

        with app_ctx.app_context():
            car = _car(brand="toyota", model="land cruiser", year=2018)
            assert car_matches_filters(car, {"q": "land cruiser"}) is True
            # "toyota" (brand) AND "cruiser" (model) both present -> match,
            # even though neither field alone contains the full phrase.
            assert car_matches_filters(car, {"q": "toyota cruiser"}) is True

    def test_non_matching_keyword_fails(self, app_ctx):
        from kk.listing_filters import car_matches_filters

        with app_ctx.app_context():
            car = _car(
                brand="toyota",
                model="camry",
                trim=None,
                location="Erbil",
                color="black",
                description="Well maintained sedan",
                title="",
            )
            assert car_matches_filters(car, {"q": "honda"}) is False

    def test_partial_multi_token_match_fails(self, app_ctx):
        """Only one of two required tokens present -> must not match."""
        from kk.listing_filters import car_matches_filters

        with app_ctx.app_context():
            car = _car(brand="toyota", model="camry")
            assert car_matches_filters(car, {"q": "toyota mustang"}) is False

    def test_substring_of_unrelated_field_does_not_leak_across_fields(
        self, app_ctx
    ):
        """Each token must appear within a single field's own text -- two
        different fields' text must not be concatenated to fabricate a
        token that spans a field boundary."""
        from kk.listing_filters import car_matches_filters

        with app_ctx.app_context():
            car = _car(brand="to", model="yota")  # "toyota" only if concatenated
            assert car_matches_filters(car, {"q": "toyota"}) is False


# ===========================================================================
# q combined with existing filters
# ===========================================================================


class TestKeywordCombinedWithOtherFilters:
    def test_keyword_and_brand_filter_both_must_pass(self, app_ctx):
        from kk.listing_filters import car_matches_filters

        with app_ctx.app_context():
            car = _car(brand="toyota", model="land cruiser")
            filters = {"brand": "toyota", "q": "cruiser"}
            assert car_matches_filters(car, filters) is True

    def test_keyword_matches_but_other_filter_fails(self, app_ctx):
        from kk.listing_filters import car_matches_filters

        with app_ctx.app_context():
            car = _car(brand="toyota", model="land cruiser")
            filters = {"brand": "honda", "q": "cruiser"}
            assert car_matches_filters(car, filters) is False

    def test_other_filter_matches_but_keyword_fails(self, app_ctx):
        from kk.listing_filters import car_matches_filters

        with app_ctx.app_context():
            car = _car(brand="toyota", model="land cruiser")
            filters = {"brand": "toyota", "q": "mustang"}
            assert car_matches_filters(car, filters) is False

    def test_keyword_with_price_and_year_range(self, app_ctx):
        from kk.listing_filters import car_matches_filters

        with app_ctx.app_context():
            car = _car(
                brand="toyota",
                model="land cruiser",
                year=2018,
                price=25000,
            )
            filters = {
                "q": "cruiser",
                "min_year": 2015,
                "max_year": 2020,
                "min_price": 20000,
                "max_price": 30000,
            }
            assert car_matches_filters(car, filters) is True
            assert car_matches_filters(car, {**filters, "min_year": 2019}) is False


# ===========================================================================
# No regression to existing saved-search filters / A-04 behavior
# ===========================================================================


class TestNoRegressionToExistingBehavior:
    def test_filters_without_q_key_behave_exactly_as_before(self, app_ctx):
        """A filters dict with no `q` key at all (the shape every saved
        search had before this fix) must match/reject exactly as before."""
        from kk.listing_filters import car_matches_filters

        with app_ctx.app_context():
            car = _car(brand="toyota", model="camry")
            assert car_matches_filters(car, {"brand": "toyota"}) is True
            assert car_matches_filters(car, {"brand": "honda"}) is False

    def test_a04_trim_base_regression_unaffected_by_q_support(self, app_ctx):
        """A-04 bug #1 regression: trim="Base" must still be matched like
        any other trim value (not treated as a no-op sentinel), independent
        of whether `q` is present."""
        from kk.listing_filters import car_matches_filters

        with app_ctx.app_context():
            base_car = _car(trim="Base")
            sport_car = _car(trim="Sport")
            assert car_matches_filters(base_car, {"trim": "Base"}) is True
            assert car_matches_filters(sport_car, {"trim": "Base"}) is False
            # Same assertions, now with an (empty) q key present.
            assert car_matches_filters(base_car, {"trim": "Base", "q": ""}) is True
            assert car_matches_filters(sport_car, {"trim": "Base", "q": ""}) is False

    def test_a04_fuel_engine_type_regression_unaffected_by_q_support(
        self, app_ctx
    ):
        """A-04 bug #2 regression: fuel_type and engine_type must remain
        independent, non-aliased checks, independent of `q` support."""
        from kk.listing_filters import car_matches_filters

        with app_ctx.app_context():
            car = _car(fuel_type="", engine_type="diesel")
            assert car_matches_filters(car, {"fuel_type": "diesel"}) is False
            assert car_matches_filters(car, {"fuel_type": "diesel", "q": ""}) is False
