"""A-04 regression tests: the Python saved-search alert matcher
(``kk/listing_filters.py::car_matches_filters()``) must follow the same
field-matching semantics as the SQL browse filter it is meant to mirror
(``kk/routes/cars.py::get_cars()``), for the two fields the audit's
duplicated-filter-logic finding (A-04) identified as already drifting.

Bug #1 -- ``trim="Base"`` (PRODUCTION_AUDIT.md A-04 investigation):
``car_matches_filters()`` used to treat both ``"base"`` and ``"any"`` as
sentinels meaning "no trim filter":

    trim = _norm_str(filters.get("trim"))
    if trim and trim not in ("base", "any") and not _ilike_match(...):
        return False

But "Base" is a real, selectable trim (``lib/features/home/home_page.dart``'s
``trims`` list) and the *default* trim assigned to any listing with no
explicit trim chosen (``lib/features/sell/sell_listing_payload.dart``:
``carData['trim'] ?? 'Base'``). ``kk/routes/cars.py``'s SQL filter
(``Car.trim.ilike(f"%{trim}%", ...)``) has no such special-case -- it
matches "Base" like any other trim. The old Python code therefore treated a
saved search filtered by ``trim=Base`` as "no trim filter at all", so the
alert task would notify a user about *every* trim (Sport, Luxury, ...) even
though the equivalent live search would only ever have shown them
Base-trim listings. Fix: remove the ``"base"`` sentinel; keep only
``"any"``.

Bug #2 -- ``engine_type``/``fuel_type`` aliasing (PRODUCTION_AUDIT.md A-04
investigation): the old code aliased the two fields with an ``or``
fallback on both the filter-key side and the car-field side:

    fuel_types = _multi_values(filters.get("fuel_type") or filters.get("engine_type"))
    ft = _norm_str(getattr(car, "fuel_type", None) or car.engine_type)

but ``kk/routes/cars.py``'s SQL filter treats them as two independent
columns/concepts, applied as separate, AND-ed ``query.filter(...)`` calls:

    if engine_type:
        query = query.filter(Car.engine_type == engine_type)   # single-value, case-SENSITIVE
    if fuel_type:
        fuel_types = _split_multi_filter(fuel_type)             # comma multi-value
        query = query.filter(or_(*[Car.fuel_type.ilike(ft) for ft in fuel_types]))  # case-insensitive, no wildcards -> exact

so a saved search filtered by only ``engine_type=diesel`` would, under the
old code, silently fall back to checking the car's ``fuel_type`` column
instead (because ``car.fuel_type`` is normally always truthy) -- matching
cars whose *engine_type* did not actually match, and missing cars whose
*engine_type* did match but whose *fuel_type* differed. Fix: check each
field independently against its own car column, exactly mirroring the SQL
semantics above (including their asymmetry: ``fuel_type`` is
comma-separated multi-value + case-insensitive exact match;
``engine_type`` is single-value + case-sensitive exact match); require both
to pass if both are supplied.

These tests use plain, unmanaged ``Car`` model instances (constructed, but
never added to a session/committed), inside an app context, so no HTTP
layer or database round-trip is needed to unit-test this pure function --
consistent with the project's existing ``Car(...)`` construction pattern in
``kk/tests/test_be07_saved_search_filter_bounds.py``.
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
    """Real Flask app + real (unused) SQLite DB, purely so ``Car(...)`` can
    be constructed inside a genuine app context. No HTTP client, no
    session commits -- ``car_matches_filters()`` is a pure function that
    only reads attributes off the ``car`` object it is given.
    """
    tmp = tempfile.TemporaryDirectory(prefix="carlist_a04_", ignore_cleanup_errors=True)
    os.environ["APP_ENV"] = "testing"
    os.environ["SMS_PROVIDER"] = "console"
    os.environ["DB_PATH"] = os.path.join(tmp.name, "a04.db")

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
    """Build an unmanaged ``Car`` row with sane defaults for fields that
    ``car_matches_filters()`` might touch, overridden per-test. Never added
    to a session -- NOT NULL column constraints are irrelevant here since
    nothing is flushed/committed.
    """
    from kk.models import Car

    defaults = dict(
        seller_id=1,
        public_id="car-a04-test",
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
        fuel_type=None,
        engine_type=None,
        is_active=True,
    )
    defaults.update(overrides)
    return Car(**defaults)


# ===========================================================================
# 1-4. trim="Base" (Bug #1)
# ===========================================================================


class TestTrimBaseMatching:
    def test_1_car_with_base_trim_matches_base_filter(self, app_ctx):
        from kk.listing_filters import car_matches_filters

        with app_ctx.app_context():
            car = _car(trim="Base")
            assert car_matches_filters(car, {"trim": "Base"}) is True

    def test_2_sport_trim_does_not_match_base_filter(self, app_ctx):
        from kk.listing_filters import car_matches_filters

        with app_ctx.app_context():
            car = _car(trim="Sport")
            assert car_matches_filters(car, {"trim": "Base"}) is False

    def test_3_luxury_trim_does_not_match_base_filter(self, app_ctx):
        from kk.listing_filters import car_matches_filters

        with app_ctx.app_context():
            car = _car(trim="Luxury")
            assert car_matches_filters(car, {"trim": "Base"}) is False

    def test_4_any_trim_filter_remains_unconditional(self, app_ctx):
        from kk.listing_filters import car_matches_filters

        with app_ctx.app_context():
            for trim_value in ("Base", "Sport", "Luxury", None, ""):
                car = _car(trim=trim_value)
                assert car_matches_filters(car, {"trim": "any"}) is True

    def test_5_base_matching_is_case_insensitive(self, app_ctx):
        from kk.listing_filters import car_matches_filters

        with app_ctx.app_context():
            # Filter value case variants against a fixed car trim.
            car = _car(trim="Base")
            assert car_matches_filters(car, {"trim": "Base"}) is True
            assert car_matches_filters(car, {"trim": "base"}) is True
            assert car_matches_filters(car, {"trim": "BASE"}) is True

            # Car's own stored value case variants against a fixed filter.
            assert car_matches_filters(_car(trim="BASE"), {"trim": "base"}) is True
            assert car_matches_filters(_car(trim="base"), {"trim": "Base"}) is True

    def test_6_base_filter_still_excludes_non_base_after_fix(self, app_ctx):
        """Sanity check that removing the "base" sentinel did not
        accidentally make the trim filter match everything."""
        from kk.listing_filters import car_matches_filters

        with app_ctx.app_context():
            assert car_matches_filters(_car(trim="Premium"), {"trim": "Base"}) is False
            assert car_matches_filters(_car(trim="Signature"), {"trim": "Base"}) is False


# ===========================================================================
# 5-8. fuel_type / engine_type independence (Bug #2)
# ===========================================================================


class TestFuelEngineTypeIndependence:
    def test_7_fuel_type_only_matches_fuel_type_column(self, app_ctx):
        from kk.listing_filters import car_matches_filters

        with app_ctx.app_context():
            car = _car(fuel_type="diesel", engine_type="gasoline")
            # fuel_type filter is satisfied purely by car.fuel_type, even
            # though car.engine_type differs -- no engine_type key means no
            # engine_type check at all.
            assert car_matches_filters(car, {"fuel_type": "diesel"}) is True
            assert car_matches_filters(car, {"fuel_type": "gasoline"}) is False

    def test_8_engine_type_only_matches_engine_type_column(self, app_ctx):
        from kk.listing_filters import car_matches_filters

        with app_ctx.app_context():
            car = _car(fuel_type="gasoline", engine_type="Diesel")
            # engine_type filter is satisfied purely by car.engine_type,
            # even though car.fuel_type differs -- no fuel_type key means
            # no fuel_type check at all.
            assert car_matches_filters(car, {"engine_type": "Diesel"}) is True
            # Mirrors SQL's `Car.engine_type == engine_type`: case-SENSITIVE.
            assert car_matches_filters(car, {"engine_type": "diesel"}) is False

    def test_9_both_supplied_both_must_pass(self, app_ctx):
        from kk.listing_filters import car_matches_filters

        with app_ctx.app_context():
            car = _car(fuel_type="diesel", engine_type="Diesel")
            # Both match -> True.
            assert (
                car_matches_filters(
                    car, {"fuel_type": "diesel", "engine_type": "Diesel"}
                )
                is True
            )

            car_mismatched_engine = _car(fuel_type="diesel", engine_type="Hybrid")
            # fuel_type matches, engine_type does not -> overall False (no
            # OR fallback between the two).
            assert (
                car_matches_filters(
                    car_mismatched_engine,
                    {"fuel_type": "diesel", "engine_type": "Diesel"},
                )
                is False
            )

            car_mismatched_fuel = _car(fuel_type="gasoline", engine_type="Diesel")
            # engine_type matches, fuel_type does not -> overall False.
            assert (
                car_matches_filters(
                    car_mismatched_fuel,
                    {"fuel_type": "diesel", "engine_type": "Diesel"},
                )
                is False
            )

    def test_10_regression_engine_type_filter_no_longer_falls_back_to_fuel_type(
        self, app_ctx
    ):
        """Direct regression test for the exact old bug: a saved search
        filtered by ``engine_type=diesel`` alone used to silently match
        against ``car.fuel_type`` whenever it was truthy (which is nearly
        always), because of the old ``car.fuel_type or car.engine_type``
        fallback. This car's ``fuel_type`` is "diesel" but its actual
        ``engine_type`` is "hybrid" -- the OLD code would have returned
        True here (matching on the wrong column); the FIXED code must
        return False, since only ``engine_type`` was filtered on and it
        does not match "diesel".
        """
        from kk.listing_filters import car_matches_filters

        with app_ctx.app_context():
            car = _car(fuel_type="diesel", engine_type="hybrid")
            assert car_matches_filters(car, {"engine_type": "diesel"}) is False

    def test_11_regression_fuel_type_filter_no_longer_falls_back_to_engine_type(
        self, app_ctx
    ):
        """Mirror of test_10 for the other direction of the old fallback:
        a saved search filtered by ``fuel_type=diesel`` alone must only
        ever check ``car.fuel_type``, never fall back to ``car.engine_type``
        even if ``car.fuel_type`` were falsy."""
        from kk.listing_filters import car_matches_filters

        with app_ctx.app_context():
            # car.fuel_type is empty/falsy; only engine_type happens to be
            # "diesel". The fixed fuel_type check must NOT fall back to
            # engine_type, so this must not match.
            car = _car(fuel_type="", engine_type="diesel")
            assert car_matches_filters(car, {"fuel_type": "diesel"}) is False


# ===========================================================================
# 9. Multi-value behavior
# ===========================================================================


class TestMultiValueBehavior:
    def test_12_fuel_type_multi_value_comma_separated(self, app_ctx):
        from kk.listing_filters import car_matches_filters

        with app_ctx.app_context():
            filters = {"fuel_type": "diesel,hybrid"}
            assert car_matches_filters(_car(fuel_type="diesel"), filters) is True
            assert car_matches_filters(_car(fuel_type="hybrid"), filters) is True
            assert car_matches_filters(_car(fuel_type="gasoline"), filters) is False

    def test_13_fuel_type_multi_value_case_insensitive(self, app_ctx):
        from kk.listing_filters import car_matches_filters

        with app_ctx.app_context():
            filters = {"fuel_type": "Diesel,Hybrid"}
            assert car_matches_filters(_car(fuel_type="diesel"), filters) is True
            assert car_matches_filters(_car(fuel_type="HYBRID"), filters) is True

    def test_14_fuel_type_exact_match_not_substring(self, app_ctx):
        """Mirrors SQL's `Car.fuel_type.ilike(ft)` with NO `%` wildcards --
        an exact (case-insensitive) match, not a substring search. A car
        whose fuel_type merely *contains* the filter term as a substring
        must NOT match."""
        from kk.listing_filters import car_matches_filters

        with app_ctx.app_context():
            car = _car(fuel_type="mild-hybrid")
            assert car_matches_filters(car, {"fuel_type": "hybrid"}) is False

    def test_15_engine_type_does_not_split_on_comma(self, app_ctx):
        """Mirrors SQL's single-value `Car.engine_type == engine_type` --
        engine_type is intentionally NOT comma-split into multiple values,
        unlike fuel_type. A comma-joined filter value must only match a
        car whose engine_type is that exact literal string."""
        from kk.listing_filters import car_matches_filters

        with app_ctx.app_context():
            car = _car(engine_type="diesel")
            # Old-style "multi-value" attempt must NOT match -- engine_type
            # has no multi-value support, exactly like the SQL side.
            assert car_matches_filters(car, {"engine_type": "diesel,hybrid"}) is False
