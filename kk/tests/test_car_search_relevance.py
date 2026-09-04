"""C-03 regression tests: Postgres relevance-ordering crash + `q` semantics.

Bug (PRODUCTION_AUDIT.md C-03): ``_order_cars_query()`` called
``rank_expr.desc()`` on the raw ``sqlalchemy.text(...)`` ``TextClause``
returned by ``apply_listing_text_search()`` when running against Postgres.
``TextClause`` has no ``.desc()`` method, so every ``GET /api/cars?q=...``
request that reached the relevance-ordering branch (default sort, or
``sort_by=relevance``/``rank``) raised::

    AttributeError: 'TextClause' object has no attribute 'desc'

and returned HTTP 500 in production. The fix wraps ``rank_expr`` with
SQLAlchemy's ``desc()`` *function* instead of calling the (nonexistent)
instance method.

``test_order_cars_query_relevance_with_text_rank_expr_does_not_raise`` below
exercises ``_order_cars_query()`` directly with a real ``sqlalchemy.text(...)``
rank expression -- the exact shape ``apply_listing_text_search()`` returns on
Postgres -- so it fails with the pre-fix code (``AttributeError``) regardless
of which dialect *this test process's own* DB connection uses. This is
deliberate: the app's test suite runs against SQLite, where
``apply_listing_text_search`` only builds a rank expression when
``dialect.name == "postgresql"`` (see ``kk/listing_search.py``), so a plain
end-to-end ``/api/cars?q=...`` request through the SQLite test client can
never reach the buggy branch and therefore cannot, by itself, prove this fix.
See the C-03 final report for the corresponding Postgres-evidence limitation
and the live-staging-probe evidence gathered separately.
"""

from __future__ import annotations

import os
import sys
import tempfile
import uuid
from pathlib import Path

import pytest
from sqlalchemy import text

_REPO_ROOT = Path(__file__).resolve().parents[2]
if str(_REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(_REPO_ROOT))


@pytest.fixture(scope="module")
def app_ctx():
    tmp = tempfile.TemporaryDirectory(
        prefix="carlist_c03_", ignore_cleanup_errors=True
    )
    os.environ["APP_ENV"] = "testing"
    os.environ["SMS_PROVIDER"] = "console"
    os.environ.pop("LISTING_REQUIRE_APPROVAL", None)
    os.environ["DB_PATH"] = os.path.join(tmp.name, "c03.db")

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
    """Seed a small, distinctly-worded catalog for free-text search assertions."""
    app, _client, db, User, Car = app_ctx
    with app.app_context():
        seller = User(
            username=f"c03_seller_{uuid.uuid4().hex[:8]}",
            phone_number=f"+1555{uuid.uuid4().int % 10_000_000:07d}",
            first_name="C03",
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
            brand="toyota",
            model="land cruiser",
        )
        camry = _car(
            title="2019 Toyota Camry",
            brand="toyota",
            model="camry",
            body_type="sedan",
        )
        civic = _car(
            title="2018 Honda Civic",
            brand="honda",
            model="civic",
            body_type="sedan",
        )
        db.session.commit()
        return {
            "land_cruiser": land_cruiser.public_id,
            "camry": camry.public_id,
            "civic": civic.public_id,
        }


# ---------------------------------------------------------------------------
# Part 1: backend relevance-ordering crash regression (dialect-agnostic).
# ---------------------------------------------------------------------------


def test_order_cars_query_relevance_with_text_rank_expr_does_not_raise(app_ctx):
    """Fails with AttributeError on the pre-fix ``rank_expr.desc()`` code;
    passes with ``desc(rank_expr)``."""
    app, _client, _db, _User, Car = app_ctx
    from kk.routes.cars import _order_cars_query

    with app.app_context():
        rank_expr = text(
            "ts_rank_cd(car.search_vector, websearch_to_tsquery('simple', :fts_q))"
        ).bindparams(fts_q="toyota")

        # Pre-fix, the next line raised AttributeError before ever touching the DB.
        ordered = _order_cars_query(Car.query, "relevance", rank_expr=rank_expr)

        compiled = str(
            ordered.statement.compile(compile_kwargs={"literal_binds": False})
        )
    assert "ts_rank_cd" in compiled
    assert "DESC" in compiled.upper()


def test_order_cars_query_rank_alias_also_uses_rank_expr(app_ctx):
    """`sort_by=rank` is an accepted alias for `relevance` and must take the
    same code path (and therefore the same fix)."""
    app, _client, _db, _User, Car = app_ctx
    from kk.routes.cars import _order_cars_query

    with app.app_context():
        rank_expr = text("some_rank_fn(car.search_vector)")
        ordered = _order_cars_query(Car.query, "rank", rank_expr=rank_expr)
        compiled = str(ordered.statement.compile())
    assert "some_rank_fn" in compiled


def test_order_cars_query_relevance_without_rank_expr_falls_back_to_default(app_ctx):
    """When rank_expr is None (e.g. SQLite ILIKE fallback), 'relevance' must
    not crash and must fall back to the default ordering -- unchanged by
    this fix."""
    app, _client, _db, _User, Car = app_ctx
    from kk.routes.cars import _order_cars_query

    with app.app_context():
        ordered = _order_cars_query(Car.query, "relevance", rank_expr=None)
        compiled = str(ordered.statement.compile())
    assert "is_featured" in compiled
    assert "created_at" in compiled


@pytest.mark.parametrize(
    "sort_by",
    [
        "newest",
        "price_asc",
        "price_desc",
        "year_desc",
        "year_asc",
        "mileage_asc",
        "mileage_desc",
        "random",
        "",
    ],
)
def test_order_cars_query_existing_non_search_sorts_unchanged(app_ctx, sort_by):
    """Existing non-search sort branches must be unaffected by the fix."""
    app, _client, _db, _User, Car = app_ctx
    from kk.routes.cars import _order_cars_query

    with app.app_context():
        ordered = _order_cars_query(Car.query, sort_by, rank_expr=None)
        # Building/compiling the query must not raise for any known sort.
        str(ordered.statement.compile())


# ---------------------------------------------------------------------------
# Parts 2/3: /api/cars?q=... route-level behavior (SQLite ILIKE fallback).
#
# NOTE: these run against SQLite, so `search_rank` is always None and the
# fixed `_order_cars_query` relevance branch is never entered here. They
# prove the *route* stays at HTTP 200 and returns sane results for the
# required q/sort_by combinations; they do NOT by themselves prove the
# Postgres relevance-ordering fix (see module docstring + final report).
# ---------------------------------------------------------------------------


def test_cars_route_with_q_returns_200(app_ctx, seeded_cars):
    _app, client, *_ = app_ctx
    r = client.get("/api/cars", query_string={"q": "toyota"})
    assert r.status_code == 200, r.data
    payload = r.get_json() or {}
    assert "cars" in payload
    assert "pagination" in payload
    ids = {c["id"] for c in payload["cars"]}
    assert seeded_cars["land_cruiser"] in ids
    assert seeded_cars["camry"] in ids
    assert seeded_cars["civic"] not in ids


def test_cars_route_with_q_and_sort_by_relevance_returns_200(app_ctx, seeded_cars):
    _app, client, *_ = app_ctx
    r = client.get("/api/cars", query_string={"q": "toyota", "sort_by": "relevance"})
    assert r.status_code == 200, r.data


def test_cars_route_with_q_and_sort_by_newest_returns_200(app_ctx, seeded_cars):
    _app, client, *_ = app_ctx
    r = client.get("/api/cars", query_string={"q": "toyota", "sort_by": "newest"})
    assert r.status_code == 200, r.data


def test_cars_route_multi_word_query_matches_model(app_ctx, seeded_cars):
    """Multi-word free text ('Land Cruiser') must match the model field via
    the ILIKE fallback (SQLite)."""
    _app, client, *_ = app_ctx
    r = client.get("/api/cars", query_string={"q": "Land Cruiser"})
    assert r.status_code == 200, r.data
    ids = {c["id"] for c in (r.get_json() or {}).get("cars", [])}
    assert seeded_cars["land_cruiser"] in ids
    assert seeded_cars["camry"] not in ids
    assert seeded_cars["civic"] not in ids


def test_cars_route_brand_only_query_matches_all_matching_brand(app_ctx, seeded_cars):
    _app, client, *_ = app_ctx
    r = client.get("/api/cars", query_string={"q": "honda"})
    assert r.status_code == 200, r.data
    ids = {c["id"] for c in (r.get_json() or {}).get("cars", [])}
    assert ids == {seeded_cars["civic"]}


def test_cars_route_keyword_combined_with_existing_filters(app_ctx, seeded_cars):
    """q combined with an existing filter (body_type) narrows correctly."""
    _app, client, *_ = app_ctx
    r = client.get(
        "/api/cars",
        query_string={"q": "toyota", "body_type": "sedan"},
    )
    assert r.status_code == 200, r.data
    ids = {c["id"] for c in (r.get_json() or {}).get("cars", [])}
    assert ids == {seeded_cars["camry"]}


def test_cars_route_nonsense_query_returns_empty_not_500(app_ctx, seeded_cars):
    _app, client, *_ = app_ctx
    r = client.get(
        "/api/cars", query_string={"q": "zzzznonexistentqueryxyz123"}
    )
    assert r.status_code == 200, r.data
    payload = r.get_json() or {}
    assert payload.get("cars") == []


def test_cars_route_empty_query_behaves_like_no_search(app_ctx, seeded_cars):
    _app, client, *_ = app_ctx
    r_empty = client.get("/api/cars", query_string={"q": ""})
    r_none = client.get("/api/cars")
    assert r_empty.status_code == 200, r_empty.data
    assert r_none.status_code == 200, r_none.data
    empty_ids = sorted(c["id"] for c in (r_empty.get_json() or {}).get("cars", []))
    none_ids = sorted(c["id"] for c in (r_none.get_json() or {}).get("cars", []))
    assert empty_ids == none_ids


def test_cars_route_whitespace_only_query_behaves_like_no_search(app_ctx, seeded_cars):
    _app, client, *_ = app_ctx
    r_blank = client.get("/api/cars", query_string={"q": "   "})
    r_none = client.get("/api/cars")
    assert r_blank.status_code == 200, r_blank.data
    blank_ids = sorted(c["id"] for c in (r_blank.get_json() or {}).get("cars", []))
    none_ids = sorted(c["id"] for c in (r_none.get_json() or {}).get("cars", []))
    assert blank_ids == none_ids


def test_cars_route_special_character_only_query_returns_200_not_500(app_ctx, seeded_cars):
    _app, client, *_ = app_ctx
    r = client.get("/api/cars", query_string={"q": "!!! ??? ###"})
    assert r.status_code == 200, r.data


def test_cars_route_pagination_with_q(app_ctx, seeded_cars):
    _app, client, *_ = app_ctx
    r = client.get(
        "/api/cars", query_string={"q": "toyota", "page": "1", "per_page": "1"}
    )
    assert r.status_code == 200, r.data
    payload = r.get_json() or {}
    assert len(payload.get("cars", [])) <= 1
    assert "pagination" in payload
    assert payload["pagination"].get("page") == 1
