"""BE-15 regression tests: LIKE metacharacters (%, _) must be escaped in the
wildcard-wrapped ``brand``/``model``/``trim``/``location``/``color``/
``plate_city`` filters on ``GET /api/cars`` and ``GET /cars``.

Bug (PRODUCTION_AUDIT.md BE-15): these filters built patterns like
``Car.brand.ilike(f"%{brand}%")`` directly from raw request input. Because
SQL ``LIKE``/``ILIKE`` treats ``%`` as "any run of characters" and ``_`` as
"any single character", a caller-supplied ``%`` or ``_`` was interpreted as a
wildcard instead of a literal character. This let queries match rows they
should not (e.g. searching for the literal brand ``"ab_cd"`` also matched
``"abXcd"``), and let a caller construct filter values with unbounded
wildcard expansion.

The fix (``_like_escape`` in ``kk/routes/cars.py``) escapes ``\\``, ``%`` and
``_`` before the value is wrapped in the app's own ``%...%`` wildcards, and
passes ``escape="\\\\"`` to ``.ilike()`` so the escape sequences are honored
by the SQL engine.

These tests seed rows specifically designed to distinguish "literal
substring match" from "SQL LIKE wildcard match": for each metacharacter, one
seeded row contains the metacharacter literally, and a sibling row is worded
so it would ALSO match if the metacharacter were (mis)treated as a wildcard.
A search for the literal value must return only the literal-match row.
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
        prefix="carlist_be15_", ignore_cleanup_errors=True
    )
    os.environ["APP_ENV"] = "testing"
    os.environ["SMS_PROVIDER"] = "console"
    os.environ.pop("LISTING_REQUIRE_APPROVAL", None)
    os.environ["DB_PATH"] = os.path.join(tmp.name, "be15.db")

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
    """Seed rows that distinguish literal matching from LIKE-wildcard matching."""
    app, _client, db, User, Car = app_ctx
    with app.app_context():
        seller = User(
            username=f"be15_seller_{uuid.uuid4().hex[:8]}",
            phone_number=f"+1555{uuid.uuid4().int % 10_000_000:07d}",
            first_name="BE15",
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

        # --- underscore ('_') pair: literal vs. single-char-wildcard lookalike ---
        underscore_literal = _car(
            title="Underscore literal brand",
            brand="ab_cd",
            model="normal",
        )
        underscore_lookalike = _car(
            title="Underscore lookalike brand",
            brand="abXcd",  # would match "%ab_cd%" if '_' were a wildcard
            model="normal",
        )

        # --- percent ('%') pair: literal vs. wildcard-expansion lookalike ---
        percent_literal = _car(
            title="Percent literal brand",
            brand="100%off",
            model="normal",
        )
        percent_lookalike = _car(
            title="Percent lookalike brand",
            brand="100xyzoff",  # would match "%100%off%" if '%' were a wildcard
            model="normal",
        )

        # --- backslash pair: literal backslash must not corrupt escaping ---
        backslash_literal = _car(
            title="Backslash literal brand",
            brand="a\\b",
            model="normal",
        )
        backslash_unrelated = _car(
            title="Backslash unrelated brand",
            brand="ab",  # unrelated; must NOT match a search for 'a\\b'
            model="normal",
        )

        # --- model field: same underscore trick, to cover a second column ---
        model_underscore_literal = _car(
            title="Underscore literal model",
            brand="modeltest",
            model="x_y",
        )
        model_underscore_lookalike = _car(
            title="Underscore lookalike model",
            brand="modeltest",
            model="xZy",
        )

        # --- location field ---
        location_underscore_literal = _car(
            title="Underscore literal location",
            brand="loctest",
            model="normal",
            location="down_town",
        )
        location_underscore_lookalike = _car(
            title="Underscore lookalike location",
            brand="loctest2",
            model="normal",
            location="downXtown",
        )

        # --- trim / color / plate_city fields (BE-15 also covers these) ---
        trim_underscore_literal = _car(
            title="Underscore literal trim",
            brand="trimtest",
            model="normal",
            trim="lx_premium",
        )
        trim_underscore_lookalike = _car(
            title="Underscore lookalike trim",
            brand="trimtest2",
            model="normal",
            trim="lxXpremium",
        )
        color_underscore_literal = _car(
            title="Underscore literal color",
            brand="colortest",
            model="normal",
            color="jet_black",
        )
        color_underscore_lookalike = _car(
            title="Underscore lookalike color",
            brand="colortest2",
            model="normal",
            color="jetXblack",
        )
        plate_city_underscore_literal = _car(
            title="Underscore literal plate_city",
            brand="platetest",
            model="normal",
            plate_city="new_york",
        )
        plate_city_underscore_lookalike = _car(
            title="Underscore lookalike plate_city",
            brand="platetest2",
            model="normal",
            plate_city="newXyork",
        )

        # --- normal catalog values, to prove ordinary substring search is unchanged ---
        toyota_camry = _car(
            title="2019 Toyota Camry",
            brand="Toyota",
            model="Camry",
        )
        honda_civic = _car(
            title="2018 Honda Civic",
            brand="Honda",
            model="Civic",
        )

        db.session.commit()
        # NOTE: `/api/cars` returns `public_id` in its `id` field, but the
        # legacy `/cars` alias route deliberately overrides it with the
        # numeric DB `id` ("legacy client expects numeric id" -- see
        # `get_cars_alias()`). Expose both so tests for each route can match
        # on the identifier that route actually returns.
        cars_by_name = {
            "underscore_literal": underscore_literal,
            "underscore_lookalike": underscore_lookalike,
            "percent_literal": percent_literal,
            "percent_lookalike": percent_lookalike,
            "backslash_literal": backslash_literal,
            "backslash_unrelated": backslash_unrelated,
            "model_underscore_literal": model_underscore_literal,
            "model_underscore_lookalike": model_underscore_lookalike,
            "location_underscore_literal": location_underscore_literal,
            "location_underscore_lookalike": location_underscore_lookalike,
            "trim_underscore_literal": trim_underscore_literal,
            "trim_underscore_lookalike": trim_underscore_lookalike,
            "color_underscore_literal": color_underscore_literal,
            "color_underscore_lookalike": color_underscore_lookalike,
            "plate_city_underscore_literal": plate_city_underscore_literal,
            "plate_city_underscore_lookalike": plate_city_underscore_lookalike,
            "toyota_camry": toyota_camry,
            "honda_civic": honda_civic,
        }
        result = {name: car.public_id for name, car in cars_by_name.items()}
        result["_num_id"] = {name: car.id for name, car in cars_by_name.items()}
        return result


# ---------------------------------------------------------------------------
# Unit tests for the escaping helper itself.
# ---------------------------------------------------------------------------


def test_like_escape_escapes_backslash_percent_and_underscore():
    from kk.routes.cars import _like_escape

    assert _like_escape("ab_cd") == "ab\\_cd"
    assert _like_escape("100%off") == "100\\%off"
    assert _like_escape("a\\b") == "a\\\\b"
    assert _like_escape("plain") == "plain"


def test_like_escape_escapes_backslash_before_generated_escapes():
    """Backslash must be escaped FIRST, else escaping % or _ would introduce
    new backslashes that get double-escaped (or worse, re-interpreted)."""
    from kk.routes.cars import _like_escape

    # If backslash were escaped after '%', the intermediate '\%' from
    # escaping '%' would itself be corrupted by a naive backslash-escape
    # pass. Escaping backslash first avoids this entirely.
    assert _like_escape("\\%") == "\\\\\\%"
    assert _like_escape("\\_") == "\\\\\\_"


# ---------------------------------------------------------------------------
# Route-level tests: /api/cars (primary route)
# ---------------------------------------------------------------------------


def test_api_cars_underscore_is_literal_not_wildcard(app_ctx, seeded_cars):
    _app, client, *_ = app_ctx
    r = client.get("/api/cars", query_string={"brand": "ab_cd"})
    assert r.status_code == 200, r.data
    ids = {c["id"] for c in (r.get_json() or {}).get("cars", [])}
    assert seeded_cars["underscore_literal"] in ids
    assert seeded_cars["underscore_lookalike"] not in ids


def test_api_cars_percent_is_literal_not_wildcard(app_ctx, seeded_cars):
    _app, client, *_ = app_ctx
    r = client.get("/api/cars", query_string={"brand": "100%off"})
    assert r.status_code == 200, r.data
    ids = {c["id"] for c in (r.get_json() or {}).get("cars", [])}
    assert seeded_cars["percent_literal"] in ids
    assert seeded_cars["percent_lookalike"] not in ids


def test_api_cars_backslash_is_handled_without_500_and_matches_literally(
    app_ctx, seeded_cars
):
    _app, client, *_ = app_ctx
    r = client.get("/api/cars", query_string={"brand": "a\\b"})
    assert r.status_code == 200, r.data
    ids = {c["id"] for c in (r.get_json() or {}).get("cars", [])}
    assert seeded_cars["backslash_literal"] in ids
    assert seeded_cars["backslash_unrelated"] not in ids


def test_api_cars_model_underscore_is_literal(app_ctx, seeded_cars):
    _app, client, *_ = app_ctx
    r = client.get("/api/cars", query_string={"model": "x_y"})
    assert r.status_code == 200, r.data
    ids = {c["id"] for c in (r.get_json() or {}).get("cars", [])}
    assert seeded_cars["model_underscore_literal"] in ids
    assert seeded_cars["model_underscore_lookalike"] not in ids


def test_api_cars_location_underscore_is_literal(app_ctx, seeded_cars):
    _app, client, *_ = app_ctx
    r = client.get("/api/cars", query_string={"location": "down_town"})
    assert r.status_code == 200, r.data
    ids = {c["id"] for c in (r.get_json() or {}).get("cars", [])}
    assert seeded_cars["location_underscore_literal"] in ids
    assert seeded_cars["location_underscore_lookalike"] not in ids


def test_api_cars_trim_underscore_is_literal(app_ctx, seeded_cars):
    _app, client, *_ = app_ctx
    r = client.get("/api/cars", query_string={"trim": "lx_premium"})
    assert r.status_code == 200, r.data
    ids = {c["id"] for c in (r.get_json() or {}).get("cars", [])}
    assert seeded_cars["trim_underscore_literal"] in ids
    assert seeded_cars["trim_underscore_lookalike"] not in ids


def test_api_cars_color_underscore_is_literal(app_ctx, seeded_cars):
    _app, client, *_ = app_ctx
    r = client.get("/api/cars", query_string={"color": "jet_black"})
    assert r.status_code == 200, r.data
    ids = {c["id"] for c in (r.get_json() or {}).get("cars", [])}
    assert seeded_cars["color_underscore_literal"] in ids
    assert seeded_cars["color_underscore_lookalike"] not in ids


def test_api_cars_plate_city_underscore_is_literal(app_ctx, seeded_cars):
    _app, client, *_ = app_ctx
    r = client.get("/api/cars", query_string={"plate_city": "new_york"})
    assert r.status_code == 200, r.data
    ids = {c["id"] for c in (r.get_json() or {}).get("cars", [])}
    assert seeded_cars["plate_city_underscore_literal"] in ids
    assert seeded_cars["plate_city_underscore_lookalike"] not in ids


def test_api_cars_multi_brand_filter_still_escapes_each_value(app_ctx, seeded_cars):
    """Comma-separated multi-brand filter must escape each split value."""
    _app, client, *_ = app_ctx
    r = client.get("/api/cars", query_string={"brand": "ab_cd,100%off"})
    assert r.status_code == 200, r.data
    ids = {c["id"] for c in (r.get_json() or {}).get("cars", [])}
    assert seeded_cars["underscore_literal"] in ids
    assert seeded_cars["percent_literal"] in ids
    assert seeded_cars["underscore_lookalike"] not in ids
    assert seeded_cars["percent_lookalike"] not in ids


def test_api_cars_normal_brand_substring_match_unchanged(app_ctx, seeded_cars):
    """Ordinary (metacharacter-free) substring search must behave exactly as
    before the fix: case-insensitive substring match."""
    _app, client, *_ = app_ctx
    r = client.get("/api/cars", query_string={"brand": "toyo"})
    assert r.status_code == 200, r.data
    ids = {c["id"] for c in (r.get_json() or {}).get("cars", [])}
    assert seeded_cars["toyota_camry"] in ids
    assert seeded_cars["honda_civic"] not in ids


def test_api_cars_normal_model_substring_match_unchanged(app_ctx, seeded_cars):
    _app, client, *_ = app_ctx
    r = client.get("/api/cars", query_string={"model": "civ"})
    assert r.status_code == 200, r.data
    ids = {c["id"] for c in (r.get_json() or {}).get("cars", [])}
    assert seeded_cars["honda_civic"] in ids
    assert seeded_cars["toyota_camry"] not in ids


# ---------------------------------------------------------------------------
# Route-level tests: /cars (legacy alias route)
# ---------------------------------------------------------------------------


def test_cars_alias_brand_underscore_is_literal(app_ctx, seeded_cars):
    _app, client, *_ = app_ctx
    num_id = seeded_cars["_num_id"]
    r = client.get("/cars", query_string={"brand": "ab_cd"})
    assert r.status_code == 200, r.data
    payload = r.get_json() or []
    ids = {c["id"] for c in payload}
    assert num_id["underscore_literal"] in ids
    assert num_id["underscore_lookalike"] not in ids


def test_cars_alias_brand_percent_is_literal(app_ctx, seeded_cars):
    _app, client, *_ = app_ctx
    num_id = seeded_cars["_num_id"]
    r = client.get("/cars", query_string={"brand": "100%off"})
    assert r.status_code == 200, r.data
    payload = r.get_json() or []
    ids = {c["id"] for c in payload}
    assert num_id["percent_literal"] in ids
    assert num_id["percent_lookalike"] not in ids


def test_cars_alias_model_underscore_is_literal(app_ctx, seeded_cars):
    _app, client, *_ = app_ctx
    num_id = seeded_cars["_num_id"]
    r = client.get("/cars", query_string={"model": "x_y"})
    assert r.status_code == 200, r.data
    payload = r.get_json() or []
    ids = {c["id"] for c in payload}
    assert num_id["model_underscore_literal"] in ids
    assert num_id["model_underscore_lookalike"] not in ids


def test_cars_alias_location_underscore_is_literal(app_ctx, seeded_cars):
    _app, client, *_ = app_ctx
    num_id = seeded_cars["_num_id"]
    r = client.get("/cars", query_string={"location": "down_town"})
    assert r.status_code == 200, r.data
    payload = r.get_json() or []
    ids = {c["id"] for c in payload}
    assert num_id["location_underscore_literal"] in ids
    assert num_id["location_underscore_lookalike"] not in ids


def test_cars_alias_normal_brand_substring_match_unchanged(app_ctx, seeded_cars):
    _app, client, *_ = app_ctx
    num_id = seeded_cars["_num_id"]
    r = client.get("/cars", query_string={"brand": "toyo"})
    assert r.status_code == 200, r.data
    payload = r.get_json() or []
    ids = {c["id"] for c in payload}
    assert num_id["toyota_camry"] in ids
    assert num_id["honda_civic"] not in ids
