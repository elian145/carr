"""Release Fix Batch 2 — SRCH-1 / SRCH-2 / SRCH-3 search accuracy.

SRCH-1: brand display names must match legacy Sell slug rows (land-rover).
SRCH-2: explicit exact model matching so pagination totals exclude siblings.
SRCH-3: seeded random sort is stable across pages (no dupes / skips).
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
        prefix="carlist_srch_b2_", ignore_cleanup_errors=True
    )
    os.environ["APP_ENV"] = "testing"
    os.environ["SMS_PROVIDER"] = "console"
    os.environ.pop("LISTING_REQUIRE_APPROVAL", None)
    os.environ["DB_PATH"] = os.path.join(tmp.name, "srch_b2.db")

    from kk.app_factory import create_app

    app, *_ = create_app()
    from kk.models import User, db

    with app.app_context():
        db.drop_all()
        db.create_all()

    yield app, app.test_client(), db, User

    with app.app_context():
        db.session.remove()
        db.engine.dispose()
    tmp.cleanup()


@pytest.fixture
def client(app_ctx):
    return app_ctx[1]


def _phone() -> str:
    return f"077{uuid.uuid4().int % 10**8:08d}"


def _seller(app_ctx) -> int:
    app, _c, db, User = app_ctx
    with app.app_context():
        user = User(
            username=f"srch_{uuid.uuid4().hex[:10]}",
            phone_number=_phone(),
            first_name="S",
            last_name="Rch",
            is_active=True,
            is_verified=True,
            phone_verified=True,
            public_id=f"pub-{uuid.uuid4().hex[:12]}",
        )
        user.set_password("Aa123456!")
        db.session.add(user)
        db.session.commit()
        return user.id


def _car(
    app_ctx,
    seller_id: int,
    *,
    brand: str,
    model: str,
    year: int = 2020,
    price: int = 10000,
    status: str = "active",
):
    app, _c, db, _User = app_ctx
    from kk.models import Car

    with app.app_context():
        car = Car(
            seller_id=seller_id,
            public_id=f"car-{uuid.uuid4().hex[:12]}",
            brand=brand,
            model=model,
            year=year,
            mileage=10,
            engine_type="gas",
            transmission="auto",
            drive_type="fwd",
            condition="used",
            body_type="suv",
            price=price,
            location="Erbil",
            is_active=True,
            status=status,
            title=f"{brand} {model}",
            media_status="ready",
        )
        db.session.add(car)
        db.session.commit()
        return {"id": car.id, "public_id": car.public_id, "brand": brand, "model": model}


def _ids(resp) -> list[str]:
    body = resp.get_json()
    return [c["id"] for c in body.get("cars") or []]


# ---------------------------------------------------------------------------
# SRCH-1 — brand slug / display mismatch
# ---------------------------------------------------------------------------


@pytest.mark.parametrize(
    "stored_brand,filter_brand",
    [
        ("land-rover", "Land Rover"),
        ("Land Rover", "land-rover"),
        ("alfa-romeo", "Alfa Romeo"),
        ("aston-martin", "Aston Martin"),
        ("rolls-royce", "Rolls-Royce"),
        ("toyota", "Toyota"),
        ("Toyota", "toyota"),
    ],
)
def test_srch1_brand_filter_matches_slug_and_display(
    app_ctx, client, stored_brand, filter_brand
):
    from kk.listing_search import normalize_brand_key

    seller_id = _seller(app_ctx)
    unique_model = f"M-{uuid.uuid4().hex[:8]}"
    car = _car(app_ctx, seller_id, brand=stored_brand, model=unique_model)
    _car(app_ctx, seller_id, brand="bmw", model=unique_model)

    resp = client.get(
        "/api/cars",
        query_string={
            "brand": filter_brand,
            "model": unique_model,
            "model_match": "exact",
            "per_page": 50,
        },
    )
    assert resp.status_code == 200, resp.data
    ids = _ids(resp)
    assert ids == [car["public_id"]]
    hit = resp.get_json()["cars"][0]
    assert normalize_brand_key(hit["brand"]) == normalize_brand_key(stored_brand)


def test_srch1_brand_and_model_combination(app_ctx, client):
    seller_id = _seller(app_ctx)
    hit = _car(app_ctx, seller_id, brand="land-rover", model="Discovery")
    _car(app_ctx, seller_id, brand="land-rover", model="Defender")
    _car(app_ctx, seller_id, brand="toyota", model="Discovery")

    resp = client.get(
        "/api/cars",
        query_string={
            "brand": "Land Rover",
            "model": "Discovery",
            "model_match": "exact",
            "per_page": 50,
        },
    )
    assert resp.status_code == 200, resp.data
    assert hit["public_id"] in _ids(resp)
    assert all(
        c["id"] == hit["public_id"]
        or not (
            c["model"].lower() == "discovery"
            and c["brand"].lower().replace(" ", "-") == "land-rover"
        )
        for c in resp.get_json()["cars"]
    )
    # Only the Land Rover Discovery slug row for this seller fixture pair.
    models = [
        c
        for c in resp.get_json()["cars"]
        if c["model"].lower() == "discovery"
        and "rover" in c["brand"].lower().replace("-", " ")
    ]
    assert any(c["id"] == hit["public_id"] for c in models)


def test_srch1_normalize_brand_key_unit():
    from kk.listing_search import normalize_brand_key

    assert normalize_brand_key("Land Rover") == normalize_brand_key("land-rover")
    assert normalize_brand_key("Rolls-Royce") == normalize_brand_key("rolls royce")
    assert normalize_brand_key("Toyota") == "toyota"


# ---------------------------------------------------------------------------
# SRCH-2 — exact model matching
# ---------------------------------------------------------------------------


def test_srch2_substring_default_still_includes_siblings(app_ctx, client):
    seller_id = _seller(app_ctx)
    brand = f"Make-{uuid.uuid4().hex[:8]}"
    exact = _car(app_ctx, seller_id, brand=brand, model="Land Cruiser")
    sibling = _car(app_ctx, seller_id, brand=brand, model="Land Cruiser Prado")

    resp = client.get(
        "/api/cars",
        query_string={"brand": brand, "model": "Land Cruiser", "per_page": 50},
    )
    assert resp.status_code == 200, resp.data
    ids = set(_ids(resp))
    assert exact["public_id"] in ids
    assert sibling["public_id"] in ids


def test_srch2_exact_model_excludes_siblings_and_fixes_totals(app_ctx, client):
    seller_id = _seller(app_ctx)
    brand = f"Make-{uuid.uuid4().hex[:8]}"
    exact = _car(app_ctx, seller_id, brand=brand, model="Land Cruiser")
    for i in range(25):
        _car(
            app_ctx,
            seller_id,
            brand=brand,
            model="Land Cruiser Prado",
            price=10000 + i,
        )

    page1 = client.get(
        "/api/cars",
        query_string={
            "brand": brand,
            "model": "Land Cruiser",
            "model_match": "exact",
            "page": 1,
            "per_page": 20,
            "sort_by": "newest",
        },
    )
    assert page1.status_code == 200, page1.data
    body = page1.get_json()
    ids = _ids(page1)
    assert exact["public_id"] in ids
    assert all(c["model"].lower() == "land cruiser" for c in body["cars"])
    assert body["pagination"]["total"] == 1
    assert body["pagination"]["has_next"] is False


@pytest.mark.parametrize(
    "exact_model,sibling_model",
    [
        ("Patrol", "Patrol Nismo"),
        ("Golf", "Golf R"),
        ("Corolla", "Corolla Cross"),
        ("Land Cruiser", "Land Cruiser Prado"),
    ],
)
def test_srch2_exact_model_pairs(app_ctx, client, exact_model, sibling_model):
    seller_id = _seller(app_ctx)
    brand = f"Make-{uuid.uuid4().hex[:8]}"
    hit = _car(app_ctx, seller_id, brand=brand, model=exact_model)
    _car(app_ctx, seller_id, brand=brand, model=sibling_model)

    resp = client.get(
        "/api/cars",
        query_string={
            "brand": brand,
            "model": exact_model,
            "model_match": "exact",
            "per_page": 50,
        },
    )
    assert resp.status_code == 200, resp.data
    assert _ids(resp) == [hit["public_id"]]


def test_srch2_exact_empty_when_only_siblings(app_ctx, client):
    seller_id = _seller(app_ctx)
    brand = f"Make-{uuid.uuid4().hex[:8]}"
    _car(app_ctx, seller_id, brand=brand, model="Corolla Cross")

    resp = client.get(
        "/api/cars",
        query_string={
            "brand": brand,
            "model": "Corolla",
            "model_match": "exact",
        },
    )
    assert resp.status_code == 200, resp.data
    body = resp.get_json()
    assert body["cars"] == []
    assert body["pagination"]["total"] == 0
    assert body["pagination"]["has_next"] is False


def test_srch2_exact_with_year_price_filters(app_ctx, client):
    seller_id = _seller(app_ctx)
    brand = f"Make-{uuid.uuid4().hex[:8]}"
    hit = _car(
        app_ctx, seller_id, brand=brand, model="Corolla", year=2020, price=12000
    )
    _car(app_ctx, seller_id, brand=brand, model="Corolla", year=2015, price=8000)
    _car(
        app_ctx, seller_id, brand=brand, model="Corolla Cross", year=2020, price=12000
    )

    resp = client.get(
        "/api/cars",
        query_string={
            "brand": brand,
            "model": "Corolla",
            "model_match": "exact",
            "min_year": 2018,
            "min_price": 10000,
            "per_page": 50,
        },
    )
    assert resp.status_code == 200, resp.data
    assert _ids(resp) == [hit["public_id"]]


# ---------------------------------------------------------------------------
# SRCH-3 — stable random pagination
# ---------------------------------------------------------------------------


def test_srch3_seeded_random_stable_across_pages_no_dupes(app_ctx, client):
    seller_id = _seller(app_ctx)
    brand = f"Rnd-{uuid.uuid4().hex[:8]}"
    created = [
        _car(app_ctx, seller_id, brand=brand, model=f"M{i}", price=1000 + i)[
            "public_id"
        ]
        for i in range(45)
    ]

    seed = "stable-seed-batch2"
    collected: list[str] = []
    for page in (1, 2, 3):
        resp = client.get(
            "/api/cars",
            query_string={
                "brand": brand,
                "sort_by": "random",
                "sort_seed": seed,
                "page": page,
                "per_page": 20,
            },
        )
        assert resp.status_code == 200, resp.data
        body = resp.get_json()
        assert body["pagination"].get("sort_seed") == seed
        page_ids = _ids(resp)
        collected.extend(page_ids)

    assert len(collected) == 45
    assert len(set(collected)) == 45
    assert set(collected) == set(created)

    again = client.get(
        "/api/cars",
        query_string={
            "brand": brand,
            "sort_by": "random",
            "sort_seed": seed,
            "page": 1,
            "per_page": 20,
        },
    )
    assert _ids(again) == collected[:20]


def test_srch3_different_seed_can_reorder(app_ctx, client):
    seller_id = _seller(app_ctx)
    brand = f"Rnd-{uuid.uuid4().hex[:8]}"
    for i in range(30):
        _car(app_ctx, seller_id, brand=brand, model=f"H{i}", price=2000 + i)

    a = _ids(
        client.get(
            "/api/cars",
            query_string={
                "sort_by": "random",
                "sort_seed": "seed-a",
                "page": 1,
                "per_page": 20,
                "brand": brand,
            },
        )
    )
    b = _ids(
        client.get(
            "/api/cars",
            query_string={
                "sort_by": "random",
                "sort_seed": "seed-b",
                "page": 1,
                "per_page": 20,
                "brand": brand,
            },
        )
    )
    assert len(a) == 20 and len(b) == 20
    assert a != b


def test_srch3_newest_sort_unaffected(app_ctx, client):
    seller_id = _seller(app_ctx)
    brand = f"New-{uuid.uuid4().hex[:8]}"
    older = _car(app_ctx, seller_id, brand=brand, model="A", price=1)
    newer = _car(app_ctx, seller_id, brand=brand, model="B", price=2)

    resp = client.get(
        "/api/cars",
        query_string={"brand": brand, "sort_by": "newest", "per_page": 10},
    )
    assert resp.status_code == 200, resp.data
    ids = _ids(resp)
    assert ids.index(newer["public_id"]) < ids.index(older["public_id"])


def test_srch3_minted_seed_echoed_when_omitted(app_ctx, client):
    seller_id = _seller(app_ctx)
    brand = f"Mz-{uuid.uuid4().hex[:8]}"
    _car(app_ctx, seller_id, brand=brand, model="3")

    resp = client.get(
        "/api/cars",
        query_string={"brand": brand, "sort_by": "random", "per_page": 5},
    )
    assert resp.status_code == 200, resp.data
    seed = resp.get_json()["pagination"].get("sort_seed")
    assert seed and isinstance(seed, str)


def test_srch3_old_client_omitting_sort_seed_stable_across_pages(app_ctx, client):
    """Installed apps that never send sort_seed must still paginate stably."""
    seller_id = _seller(app_ctx)
    brand = f"Old-{uuid.uuid4().hex[:8]}"
    created = [
        _car(app_ctx, seller_id, brand=brand, model=f"O{i}", price=3000 + i)[
            "public_id"
        ]
        for i in range(45)
    ]

    collected: list[str] = []
    echoed: list[str] = []
    for page in (1, 2, 3):
        resp = client.get(
            "/api/cars",
            query_string={
                "brand": brand,
                "sort_by": "random",
                "page": page,
                "per_page": 20,
            },
        )
        assert resp.status_code == 200, resp.data
        body = resp.get_json()
        seed = body["pagination"].get("sort_seed")
        assert seed and isinstance(seed, str)
        echoed.append(seed)
        collected.extend(_ids(resp))

    # Deterministic fallback: same seed echoed on every page of the same query.
    assert echoed[0] == echoed[1] == echoed[2]
    assert len(collected) == 45
    assert len(set(collected)) == 45
    assert set(collected) == set(created)

    # Replaying page 1 without sort_seed returns the same first page.
    again = client.get(
        "/api/cars",
        query_string={
            "brand": brand,
            "sort_by": "random",
            "page": 1,
            "per_page": 20,
        },
    )
    assert _ids(again) == collected[:20]


def test_srch3_invalid_sort_seed_falls_back_without_error(app_ctx, client):
    from kk.listing_search import legacy_deterministic_sort_seed, sanitize_sort_seed

    assert sanitize_sort_seed(None) is None
    assert sanitize_sort_seed("") is None
    assert sanitize_sort_seed("   ") is None
    assert sanitize_sort_seed("-1") == "-1"
    assert sanitize_sort_seed("@@@") is None
    # Oversized / garbage characters are sanitized, not rejected as 500s.
    cleaned = sanitize_sort_seed("x" * 200 + "; DROP TABLE cars; --")
    assert cleaned is not None
    assert len(cleaned) <= 64
    assert ";" not in cleaned
    assert " " not in cleaned

    day_a = legacy_deterministic_sort_seed(
        [("brand", "Toyota"), ("sort_by", "random"), ("page", "1")],
        day_key="2026-10-09",
    )
    day_b = legacy_deterministic_sort_seed(
        [("brand", "Toyota"), ("sort_by", "random"), ("page", "2")],
        day_key="2026-10-09",
    )
    day_other = legacy_deterministic_sort_seed(
        [("brand", "Toyota"), ("sort_by", "random"), ("page", "1")],
        day_key="2026-10-10",
    )
    assert day_a == day_b  # page ignored
    assert day_a != day_other

    seller_id = _seller(app_ctx)
    brand = f"Bad-{uuid.uuid4().hex[:8]}"
    for i in range(5):
        _car(app_ctx, seller_id, brand=brand, model=f"B{i}", price=100 + i)

    for bad in (
        "x" * 500,
        "'; DROP TABLE cars; --",
        "\x00\x01",
        -999,
        "@@@",
    ):
        resp = client.get(
            "/api/cars",
            query_string={
                "brand": brand,
                "sort_by": "random",
                "sort_seed": bad,
                "page": 1,
                "per_page": 5,
            },
        )
        assert resp.status_code == 200, (bad, resp.data)
        assert isinstance(resp.get_json()["pagination"].get("sort_seed"), str)
