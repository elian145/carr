"""BE-16 regression tests: ``condition``/``transmission`` filters on
``GET /api/cars`` and ``GET /cars`` must match case-insensitively.

Bug (PRODUCTION_AUDIT.md BE-16): ``get_cars()`` and ``get_cars_alias()`` built
these filters with a plain SQL exact match::

    query = query.filter(Car.condition == condition)
    query = query.filter(Car.transmission == transmission)

Because SQL ``==`` on a text column is case-sensitive (both on SQLite and
PostgreSQL, the two engines this app runs on), a caller-supplied value like
``"Used"`` would NOT match a stored row of ``"used"``, and a stored row of
``"New"`` would NOT match a caller-supplied ``"new"``. Every sibling filter
in the same function (``body_type`` via ``func.lower(...)``, ``drive_type``/
``fuel_type`` via ``.ilike(...)``) was already case-insensitive; only
``condition``/``transmission`` were not.

The fix changes both filters to::

    query = query.filter(func.lower(Car.condition) == condition.strip().lower())
    query = query.filter(func.lower(Car.transmission) == transmission.strip().lower())

These tests seed rows with deliberately mixed-case stored ``condition``/
``transmission`` values (bypassing the create-listing route, which is legal
here because the ``Car.condition``/``Car.transmission`` columns have no
``CHECK`` constraint or DB-level case normalization -- see ``kk/models.py``)
alongside normal lowercase rows, then issue filter requests with the
opposite casing. Every assertion below would FAIL under the old
case-sensitive ``==`` implementation and PASSES only because of the BE-16
fix.
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
        prefix="carlist_be16_", ignore_cleanup_errors=True
    )
    os.environ["APP_ENV"] = "testing"
    os.environ["SMS_PROVIDER"] = "console"
    os.environ.pop("LISTING_REQUIRE_APPROVAL", None)
    os.environ["DB_PATH"] = os.path.join(tmp.name, "be16.db")

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
    """Seed rows that distinguish case-sensitive matching from
    case-insensitive matching for ``condition``/``transmission``."""
    app, _client, db, User, Car = app_ctx
    with app.app_context():
        seller = User(
            username=f"be16_seller_{uuid.uuid4().hex[:8]}",
            phone_number=f"+1555{uuid.uuid4().int % 10_000_000:07d}",
            first_name="BE16",
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
                transmission="automatic",
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

        # --- normal lowercase-stored row: baseline control ---
        lowercase_row = _car(
            title="BE16 lowercase-stored row",
            brand="be16lower",
            model="normal",
            condition="used",
            transmission="automatic",
        )

        # --- mixed-case-stored row: simulates data written before/without
        # the client's own lowercasing convention, or via a non-Flutter
        # caller. Legal because the column has no CHECK constraint. ---
        mixedcase_row = _car(
            title="BE16 mixed-case-stored row",
            brand="be16mixed",
            model="normal",
            condition="New",
            transmission="Manual",
        )

        # --- control row: distinct condition/transmission values that must
        # never match the filters used against the two rows above. ---
        control_row = _car(
            title="BE16 control row",
            brand="be16control",
            model="normal",
            condition="certified",
            transmission="cvt",
        )

        db.session.commit()
        cars_by_name = {
            "lowercase_row": lowercase_row,
            "mixedcase_row": mixedcase_row,
            "control_row": control_row,
        }
        result = {name: car.public_id for name, car in cars_by_name.items()}
        result["_num_id"] = {name: car.id for name, car in cars_by_name.items()}
        return result


# ---------------------------------------------------------------------------
# Route-level tests: /api/cars (primary route)
# ---------------------------------------------------------------------------


def test_api_cars_condition_mixed_case_query_matches_lowercase_stored(
    app_ctx, seeded_cars
):
    """Lowercase-stored condition ('used') must match a mixed-case query
    ('Used'). Fails under the old ``Car.condition == condition`` exact
    match."""
    _app, client, *_ = app_ctx
    r = client.get(
        "/api/cars", query_string={"brand": "be16lower", "condition": "Used"}
    )
    assert r.status_code == 200, r.data
    ids = {c["id"] for c in (r.get_json() or {}).get("cars", [])}
    assert seeded_cars["lowercase_row"] in ids


def test_api_cars_transmission_mixed_case_query_matches_lowercase_stored(
    app_ctx, seeded_cars
):
    """Lowercase-stored transmission ('automatic') must match a mixed-case
    (upper) query ('AUTOMATIC'). Fails under the old exact match."""
    _app, client, *_ = app_ctx
    r = client.get(
        "/api/cars",
        query_string={"brand": "be16lower", "transmission": "AUTOMATIC"},
    )
    assert r.status_code == 200, r.data
    ids = {c["id"] for c in (r.get_json() or {}).get("cars", [])}
    assert seeded_cars["lowercase_row"] in ids


def test_api_cars_condition_lowercase_query_matches_mixed_case_stored(
    app_ctx, seeded_cars
):
    """Mixed-case-stored condition ('New') must match a lowercase query
    ('new'). Fails under the old exact match."""
    _app, client, *_ = app_ctx
    r = client.get(
        "/api/cars", query_string={"brand": "be16mixed", "condition": "new"}
    )
    assert r.status_code == 200, r.data
    ids = {c["id"] for c in (r.get_json() or {}).get("cars", [])}
    assert seeded_cars["mixedcase_row"] in ids


def test_api_cars_transmission_lowercase_query_matches_mixed_case_stored(
    app_ctx, seeded_cars
):
    """Mixed-case-stored transmission ('Manual') must match a lowercase
    query ('manual'). Fails under the old exact match."""
    _app, client, *_ = app_ctx
    r = client.get(
        "/api/cars",
        query_string={"brand": "be16mixed", "transmission": "manual"},
    )
    assert r.status_code == 200, r.data
    ids = {c["id"] for c in (r.get_json() or {}).get("cars", [])}
    assert seeded_cars["mixedcase_row"] in ids


def test_api_cars_condition_filter_excludes_non_matching_values(
    app_ctx, seeded_cars
):
    """Case-insensitivity must not turn the filter into a no-op: an
    unrelated condition value must still be excluded."""
    _app, client, *_ = app_ctx
    r = client.get("/api/cars", query_string={"condition": "Used"})
    assert r.status_code == 200, r.data
    ids = {c["id"] for c in (r.get_json() or {}).get("cars", [])}
    assert seeded_cars["lowercase_row"] in ids
    assert seeded_cars["mixedcase_row"] not in ids
    assert seeded_cars["control_row"] not in ids


def test_api_cars_transmission_filter_excludes_non_matching_values(
    app_ctx, seeded_cars
):
    _app, client, *_ = app_ctx
    r = client.get("/api/cars", query_string={"transmission": "Manual"})
    assert r.status_code == 200, r.data
    ids = {c["id"] for c in (r.get_json() or {}).get("cars", [])}
    assert seeded_cars["mixedcase_row"] in ids
    assert seeded_cars["lowercase_row"] not in ids
    assert seeded_cars["control_row"] not in ids


def test_api_cars_condition_normal_lowercase_filter_still_works(
    app_ctx, seeded_cars
):
    """Ordinary same-case filtering (the common path) must be unaffected by
    the fix."""
    _app, client, *_ = app_ctx
    r = client.get(
        "/api/cars", query_string={"brand": "be16control", "condition": "certified"}
    )
    assert r.status_code == 200, r.data
    ids = {c["id"] for c in (r.get_json() or {}).get("cars", [])}
    assert seeded_cars["control_row"] in ids


def test_api_cars_transmission_normal_lowercase_filter_still_works(
    app_ctx, seeded_cars
):
    _app, client, *_ = app_ctx
    r = client.get(
        "/api/cars",
        query_string={"brand": "be16control", "transmission": "cvt"},
    )
    assert r.status_code == 200, r.data
    ids = {c["id"] for c in (r.get_json() or {}).get("cars", [])}
    assert seeded_cars["control_row"] in ids


def test_api_cars_condition_and_transmission_combined_case_insensitive(
    app_ctx, seeded_cars
):
    """Both filters applied together, each with mismatched case, must both
    apply correctly (AND semantics preserved)."""
    _app, client, *_ = app_ctx
    r = client.get(
        "/api/cars",
        query_string={
            "brand": "be16mixed",
            "condition": "NEW",
            "transmission": "MANUAL",
        },
    )
    assert r.status_code == 200, r.data
    ids = {c["id"] for c in (r.get_json() or {}).get("cars", [])}
    assert seeded_cars["mixedcase_row"] in ids


# ---------------------------------------------------------------------------
# Route-level tests: /cars (legacy alias route)
# ---------------------------------------------------------------------------


def test_cars_alias_condition_mixed_case_query_matches_lowercase_stored(
    app_ctx, seeded_cars
):
    _app, client, *_ = app_ctx
    num_id = seeded_cars["_num_id"]
    r = client.get(
        "/cars", query_string={"brand": "be16lower", "condition": "Used"}
    )
    assert r.status_code == 200, r.data
    ids = {c["id"] for c in (r.get_json() or [])}
    assert num_id["lowercase_row"] in ids


def test_cars_alias_transmission_mixed_case_query_matches_lowercase_stored(
    app_ctx, seeded_cars
):
    _app, client, *_ = app_ctx
    num_id = seeded_cars["_num_id"]
    r = client.get(
        "/cars",
        query_string={"brand": "be16lower", "transmission": "AUTOMATIC"},
    )
    assert r.status_code == 200, r.data
    ids = {c["id"] for c in (r.get_json() or [])}
    assert num_id["lowercase_row"] in ids


def test_cars_alias_condition_lowercase_query_matches_mixed_case_stored(
    app_ctx, seeded_cars
):
    _app, client, *_ = app_ctx
    num_id = seeded_cars["_num_id"]
    r = client.get(
        "/cars", query_string={"brand": "be16mixed", "condition": "new"}
    )
    assert r.status_code == 200, r.data
    ids = {c["id"] for c in (r.get_json() or [])}
    assert num_id["mixedcase_row"] in ids


def test_cars_alias_transmission_lowercase_query_matches_mixed_case_stored(
    app_ctx, seeded_cars
):
    _app, client, *_ = app_ctx
    num_id = seeded_cars["_num_id"]
    r = client.get(
        "/cars",
        query_string={"brand": "be16mixed", "transmission": "manual"},
    )
    assert r.status_code == 200, r.data
    ids = {c["id"] for c in (r.get_json() or [])}
    assert num_id["mixedcase_row"] in ids


def test_cars_alias_condition_normal_lowercase_filter_still_works(
    app_ctx, seeded_cars
):
    _app, client, *_ = app_ctx
    num_id = seeded_cars["_num_id"]
    r = client.get(
        "/cars", query_string={"brand": "be16control", "condition": "certified"}
    )
    assert r.status_code == 200, r.data
    ids = {c["id"] for c in (r.get_json() or [])}
    assert num_id["control_row"] in ids
