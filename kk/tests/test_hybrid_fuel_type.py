"""Hybrid / Plug-in Hybrid fuel handling end to end (backend half).

Toyota Corolla / Corolla Cross (and every other model with hybrid variants) were
missing Hybrid in the app's Sell + Search pickers because the spec catalog never
produced it (see lib/services/car_spec_powertrain.dart). These tests pin the
backend half of the fix:

* the canonical vocabulary (``kk/fuel_types.py``) mirrors the Flutter one;
* a saved Hybrid / Plug-in Hybrid listing is returned by the matching Search
  filter, and ONLY by that filter (never by Electric / Gasoline / the other
  hybrid kind, never a ``mild-hybrid``);
* legacy rows (``plug_in_hybrid``, ``HYBRID`` ...) stay searchable;
* Petrol / Diesel / Electric filtering is byte for byte what it was;
* the auto-moderation engine does not treat a hybrid's combustion displacement /
  cylinders as an "electric car with an engine".
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

from kk import fuel_types as ft  # noqa: E402

# ---------------------------------------------------------------------------
# Canonical vocabulary (pure)
# ---------------------------------------------------------------------------


@pytest.mark.parametrize(
    "raw, expected",
    [
        ("hybrid", "hybrid"),
        ("Hybrid", "hybrid"),
        (" HYBRID ", "hybrid"),
        ("HEV", "hybrid"),
        ("full-hybrid", "hybrid"),
        ("plug-in hybrid", "plug-in hybrid"),
        ("Plug-in Hybrid", "plug-in hybrid"),
        ("plug_in_hybrid", "plug-in hybrid"),
        ("plugin hybrid", "plug-in hybrid"),
        ("Plug in Hybrid", "plug-in hybrid"),
        ("PHEV", "plug-in hybrid"),
        ("erev", "plug-in hybrid"),
        ("Range Extender", "plug-in hybrid"),
        ("gasoline", "gasoline"),
        ("Petrol", "gasoline"),
        ("diesel", "diesel"),
        ("Electric", "electric"),
        ("BEV", "electric"),
    ],
)
def test_canonical_fuel_type(raw, expected):
    assert ft.canonical_fuel_type(raw) == expected


@pytest.mark.parametrize("raw", ["mild-hybrid", "mild hybrid", "lpg", "hydrogen", "", None, "hybridish"])
def test_unrecognised_values_are_not_folded_into_a_fuel(raw):
    assert ft.canonical_fuel_type(raw) is None


def test_mild_hybrid_is_never_a_hybrid():
    assert ft.fuel_filter_matches("mild-hybrid", "hybrid") is False
    assert ft.fuel_filter_matches("mild hybrid", "plug-in hybrid") is False


def test_hybrid_family_is_distinct_from_electric_and_petrol_and_each_other():
    assert ft.fuel_filter_matches("hybrid", "hybrid") is True
    assert ft.fuel_filter_matches("plug-in hybrid", "hybrid") is False
    assert ft.fuel_filter_matches("hybrid", "plug-in hybrid") is False
    assert ft.fuel_filter_matches("electric", "hybrid") is False
    assert ft.fuel_filter_matches("gasoline", "hybrid") is False
    assert ft.fuel_filter_matches("hybrid", "electric") is False
    assert ft.fuel_filter_matches("hybrid", "gasoline") is False
    assert ft.fuel_filter_matches("plug_in_hybrid", "plug-in hybrid") is True
    assert ft.fuel_filter_matches("PHEV", "plug-in hybrid") is True


def test_storage_value_only_normalises_the_hybrid_family():
    assert ft.storage_fuel_value("Plug_In_Hybrid") == "plug-in hybrid"
    assert ft.storage_fuel_value("HEV") == "hybrid"
    assert ft.storage_fuel_value("hybrid") == "hybrid"
    # every other value is returned untouched (existing behaviour)
    for v in ("Gasoline", "Petrol", "diesel", "Electric", "lpg", "mild-hybrid"):
        assert ft.storage_fuel_value(v) == v


def test_python_filter_matcher_uses_the_same_rules():
    from kk.listing_filters import car_matches_filters
    from kk.models import Car

    def car(fuel):
        return Car(fuel_type=fuel, engine_type=fuel, brand="toyota", model="corolla", year=2021)

    assert car_matches_filters(car("hybrid"), {"fuel_type": "hybrid"}) is True
    assert car_matches_filters(car("HYBRID"), {"fuel_type": "Hybrid"}) is True
    assert car_matches_filters(car("plug_in_hybrid"), {"fuel_type": "plug-in hybrid"}) is True
    assert car_matches_filters(car("plug-in hybrid"), {"fuel_type": "hybrid"}) is False
    assert car_matches_filters(car("hybrid"), {"fuel_type": "plug-in hybrid"}) is False
    assert car_matches_filters(car("electric"), {"fuel_type": "hybrid"}) is False
    assert car_matches_filters(car("gasoline"), {"fuel_type": "hybrid"}) is False
    assert car_matches_filters(car("hybrid"), {"fuel_type": "gasoline,hybrid"}) is True
    # untouched fuels keep their exact comparison
    assert car_matches_filters(car("diesel"), {"fuel_type": "Diesel"}) is True
    assert car_matches_filters(car("diesel"), {"fuel_type": "gasoline"}) is False


# ---------------------------------------------------------------------------
# Moderation: hybrid specs are legitimate
# ---------------------------------------------------------------------------

from kk.auto_moderation import config, rules  # noqa: E402
from kk.auto_moderation.rules import REVIEW, Facts  # noqa: E402

_YEAR = 2026


def _mod_fields(**kw):
    base = dict(
        title="Toyota Corolla 2021",
        brand="toyota",
        model="corolla",
        trim="base",
        year=2021,
        mileage=45000,
        price=15000.0,
        currency="USD",
        location="Erbil",
        condition="used",
        engine_type="hybrid",
        fuel_type="hybrid",
        engine_size=1.8,
        cylinder_count=4,
        transmission="automatic",
        drive_type="fwd",
        body_type="sedan",
        vin=None,
        description="Clean car, regularly serviced, no accidents.",
    )
    base.update(kw)
    return base


def _mod_run(**kw):
    images = [
        {"url": f"https://cdn.example.com/p{i}.jpg", "kind": "listing", "is_primary": i == 0,
         "source_media_id": f"m{i}", "width": 1600, "height": 1200}
        for i in range(3)
    ]
    items = [{"client_media_id": f"m{i}", "kind": "image", "status": "attached", "is_cover": i == 0}
             for i in range(3)]
    media = dict(media_status="ready", in_flight=0, failed=0, items=items, images=images)
    seller = dict(exists=True, active=True, phone_verified=True, dealer_approved=False, prior_approved=2,
                  open_reports=0, admin_rejections=0, hidden_listings=0, manual_only=False)
    f = Facts("listing", _mod_fields(**kw), media, seller, {})
    return rules.run_rules(f, config.DEFAULTS, _YEAR)


def _review_codes(sigs):
    return {s.code for s in sigs if s.level == REVIEW}


@pytest.mark.parametrize(
    "fuel, model, engine_size, cylinders",
    [
        ("hybrid", "corolla", 1.8, 4),
        ("hybrid", "corolla", 2.0, 4),
        ("hybrid", "corolla cross", 1.8, 4),
        ("hybrid", "corolla cross", 2.0, 4),
        ("hybrid", "camry", 2.5, 4),
        ("hybrid", "rav4", 2.5, 4),
        ("hybrid", "prius", 1.8, 4),
        ("plug-in hybrid", "prius", 1.8, 4),
        ("plug-in hybrid", "prius prime", 2.0, 4),
        ("plug-in hybrid", "x5", 2.0, 4),
        ("plug-in hybrid", "c-class", 2.0, 4),
        # every spelling the catalog / legacy rows can produce
        ("plug_in_hybrid", "prius", 1.8, 4),
        ("Plug-in Hybrid", "prius", 1.8, 4),
        ("PHEV", "prius", 1.8, 4),
        ("HEV", "corolla", 1.8, 4),
        ("range extender", "i3", 0.65, 2),
    ],
)
def test_hybrid_with_engine_displacement_and_cylinders_is_not_flagged(fuel, model, engine_size, cylinders):
    sigs = _mod_run(
        model=model, title=f"Toyota {model}", engine_type=fuel, fuel_type=fuel,
        engine_size=engine_size, cylinder_count=cylinders,
    )
    assert "ev_with_combustion_engine" not in _review_codes(sigs)
    assert "ev_powertrain_unconfirmed" not in _review_codes(sigs)
    assert _review_codes(sigs) == set()
    assert rules.decide(sigs) == "AUTO_APPROVE"


def test_pure_electric_with_an_engine_is_still_flagged_unchanged():
    sigs = _mod_run(engine_type="electric", fuel_type="electric", engine_size=1.8, cylinder_count=4)
    assert "ev_with_combustion_engine" in _review_codes(sigs)


@pytest.mark.parametrize(
    "brand, model, fuel, engine_size, cylinders",
    [
        # Nissan e-POWER: a gasoline engine generates the electricity -> hybrid
        ("nissan", "note", "hybrid", 1.2, 3),
        ("nissan", "kicks", "hybrid", 1.2, 3),
        ("nissan", "qashqai", "hybrid", 1.5, 3),
        ("nissan", "x-trail", "hybrid", 1.5, 3),
        # range extenders the catalog now stores as plug-in hybrid
        ("deepal", "s07", "plug-in hybrid", 1.5, 4),
        ("mazda", "ez-6", "plug-in hybrid", 1.5, 4),
        ("leapmotor", "b10", "plug-in hybrid", 1.5, 4),
        # first-generation hybrids the source lists without hybrid wording
        ("toyota", "prius", "hybrid", 1.5, 4),
        ("honda", "insight", "hybrid", 1.0, 3),
    ],
)
def test_audit_epower_range_extender_and_nameplate_hybrids_are_not_flagged(
    brand, model, fuel, engine_size, cylinders
):
    sigs = _mod_run(
        brand=brand, model=model, title=f"{brand} {model}", engine_type=fuel,
        fuel_type=fuel, engine_size=engine_size, cylinder_count=cylinders,
    )
    assert _review_codes(sigs) == set()
    assert rules.decide(sigs) == "AUTO_APPROVE"
    assert rules.classify_powertrain(fuel, fuel) == rules.HYBRID


def test_audit_battery_extended_range_ev_stays_a_clean_bev():
    # "Electric Extended Range" (Nissan Micra EV, 52 kWh) is a big battery, not
    # a generator: it stays Electric and carries no engine fields.
    sigs = _mod_run(
        brand="nissan", model="micra", title="Nissan Micra Electric Extended Range",
        engine_type="electric", fuel_type="electric", engine_size=None, cylinder_count=None,
        description="52 kWh extended range battery, 150 hp.",
    )
    assert rules.classify_powertrain("electric", "electric") == rules.BEV
    assert _review_codes(sigs) == set()


def test_audit_a_mild_hybrid_stored_as_gasoline_keeps_its_engine_unflagged():
    sigs = _mod_run(
        brand="mazda", model="3", title="Mazda 3 SkyActiv-G M Hybrid", engine_type="gasoline",
        fuel_type="gasoline", engine_size=2.0, cylinder_count=4,
    )
    assert _review_codes(sigs) == set()

def test_hybrid_wording_in_the_description_does_not_change_a_structured_hybrid():
    sigs = _mod_run(description="Toyota Corolla hybrid, full service history.")
    assert _review_codes(sigs) == set()


# ---------------------------------------------------------------------------
# API: store + search
# ---------------------------------------------------------------------------


@pytest.fixture(scope="module")
def app_ctx():
    tmp = tempfile.TemporaryDirectory(prefix="carlist_hybrid_", ignore_cleanup_errors=True)
    os.environ["APP_ENV"] = "testing"
    os.environ["SMS_PROVIDER"] = "console"
    os.environ.pop("LISTING_REQUIRE_APPROVAL", None)
    os.environ["DB_PATH"] = os.path.join(tmp.name, "hybrid.db")

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


def _make_user(app_ctx, username: str) -> None:
    app, _client, db, User, _Car = app_ctx
    with app.app_context():
        user = User(
            username=username,
            phone_number=f"077{uuid.uuid4().int % 10**8:08d}",
            first_name=username[:20],
            last_name="Test",
            is_active=True,
            is_verified=True,
            phone_verified=True,
            public_id=f"pub-{uuid.uuid4().hex[:12]}",
        )
        user.set_password("Aa123456!")
        db.session.add(user)
        db.session.commit()


@pytest.fixture
def seller_headers(client, app_ctx):
    username = f"hyb_{uuid.uuid4().hex[:10]}"
    _make_user(app_ctx, username)
    r = client.post("/api/auth/login", json={"username": username, "password": "Aa123456!"})
    assert r.status_code == 200, r.data
    return {"Authorization": f"Bearer {r.get_json()['access_token']}"}


def _flutter_payload(model: str, fuel: str, engine_size, cylinders, **extra) -> dict:
    """The exact shape lib/features/sell/sell_listing_payload.dart sends: the
    canonical fuel key goes into BOTH engine_type and fuel_type."""
    payload = {
        "brand": "toyota",
        "model": model,
        "year": 2021,
        "mileage": 1000,
        "price": 15000,
        "location": "Erbil",
        "condition": "used",
        "body_type": "sedan",
        "transmission": "automatic",
        "drive_type": "fwd",
        "engine_type": fuel,
        "fuel_type": fuel,
        "engine_size": engine_size,
        "cylinder_count": cylinders,
    }
    payload.update(extra)
    return payload


def _post(client, headers, **kw) -> dict:
    r = client.post("/api/cars", json=_flutter_payload(**kw), headers=headers)
    assert r.status_code == 201, r.data
    return r.get_json()["car"]


def _search_ids(client, **qs) -> set:
    r = client.get("/api/cars", query_string=qs)
    assert r.status_code == 200, r.data
    return {c["id"] for c in r.get_json()["cars"]}


def test_saved_hybrid_listing_is_returned_by_the_hybrid_filter_only(client, app_ctx, seller_headers):
    corolla_h = _post(client, seller_headers, model="corolla", fuel="hybrid", engine_size=1.8, cylinders=4)
    cross_h = _post(client, seller_headers, model="corolla cross", fuel="hybrid", engine_size=2.0, cylinders=4)
    prius_p = _post(client, seller_headers, model="prius", fuel="plug-in hybrid", engine_size=1.8, cylinders=4)
    corolla_g = _post(client, seller_headers, model="corolla", fuel="gasoline", engine_size=1.6, cylinders=4)
    leaf_e = _post(client, seller_headers, model="leaf", fuel="electric", engine_size=None, cylinders=None)

    # the stored value is the canonical one, in both columns
    assert corolla_h["fuel_type"] == "hybrid" and corolla_h["engine_type"] == "hybrid"
    assert prius_p["fuel_type"] == "plug-in hybrid"

    hyb = _search_ids(client, fuel_type="hybrid")
    assert {corolla_h["id"], cross_h["id"]} <= hyb
    assert not ({prius_p["id"], corolla_g["id"], leaf_e["id"]} & hyb)

    # the app sends the label lower-cased; case never matters
    assert {corolla_h["id"], cross_h["id"]} <= _search_ids(client, fuel_type="Hybrid")

    # combined with the model filter (Corolla Cross only)
    only_cross = _search_ids(client, fuel_type="hybrid", model="Corolla Cross")
    assert cross_h["id"] in only_cross and corolla_h["id"] not in only_cross

    phev = _search_ids(client, fuel_type="plug-in hybrid")
    assert prius_p["id"] in phev
    assert not ({corolla_h["id"], cross_h["id"], corolla_g["id"], leaf_e["id"]} & phev)

    both = _search_ids(client, fuel_type="hybrid,plug-in hybrid")
    assert {corolla_h["id"], cross_h["id"], prius_p["id"]} <= both
    assert not ({corolla_g["id"], leaf_e["id"]} & both)


def test_existing_fuel_filters_are_unchanged(client, app_ctx, seller_headers):
    gas = _post(client, seller_headers, model="yaris", fuel="gasoline", engine_size=1.5, cylinders=4)
    dsl = _post(client, seller_headers, model="hilux", fuel="diesel", engine_size=2.4, cylinders=4)
    ele = _post(client, seller_headers, model="bz4x", fuel="electric", engine_size=None, cylinders=None)
    hyb = _post(client, seller_headers, model="yaris", fuel="hybrid", engine_size=1.5, cylinders=3)

    assert gas["id"] in _search_ids(client, fuel_type="gasoline")
    assert hyb["id"] not in _search_ids(client, fuel_type="gasoline")
    assert dsl["id"] in _search_ids(client, fuel_type="Diesel")
    assert ele["id"] in _search_ids(client, fuel_type="electric")
    assert hyb["id"] not in _search_ids(client, fuel_type="electric")
    assert {gas["id"], dsl["id"]} <= _search_ids(client, fuel_type="gasoline,diesel")
    assert ele["id"] not in _search_ids(client, fuel_type="gasoline,diesel")


def test_legacy_spellings_stay_searchable(client, app_ctx, seller_headers):
    app, _c, db, _User, Car = app_ctx
    a = _post(client, seller_headers, model="camry", fuel="hybrid", engine_size=2.5, cylinders=4)
    b = _post(client, seller_headers, model="prius", fuel="hybrid", engine_size=1.8, cylinders=4)
    c = _post(client, seller_headers, model="rav4", fuel="hybrid", engine_size=2.5, cylinders=4)
    mild = _post(client, seller_headers, model="swift", fuel="hybrid", engine_size=1.2, cylinders=3)
    with app.app_context():
        # rows written before this fix / by seed scripts
        for car, spelling in (
            (a, "HYBRID"),
            (b, "plug_in_hybrid"),
            (c, "Plug-in Hybrid"),
            (mild, "mild-hybrid"),
        ):
            Car.query.filter_by(public_id=car["id"]).one().fuel_type = spelling
        db.session.commit()

    hyb = _search_ids(client, fuel_type="hybrid")
    assert a["id"] in hyb
    assert not ({b["id"], c["id"], mild["id"]} & hyb)
    phev = _search_ids(client, fuel_type="plug-in hybrid")
    assert {b["id"], c["id"]} <= phev
    assert not ({a["id"], mild["id"]} & phev)


def test_hybrid_spellings_are_normalised_when_a_listing_is_saved(client, app_ctx, seller_headers):
    car = _post(client, seller_headers, model="prius", fuel="Plug_In_Hybrid", engine_size=1.8, cylinders=4)
    assert car["fuel_type"] == "plug-in hybrid"
    assert car["engine_type"] == "plug-in hybrid"
    assert car["id"] in _search_ids(client, fuel_type="plug-in hybrid")

    # an edit that changes the fuel keeps the same canonical storage. A
    # published listing's edit goes to a hidden revision, so hold the listing
    # (Under Review) to exercise the direct-edit path.
    with app_ctx[0].app_context():
        Car = app_ctx[4]
        Car.query.filter_by(public_id=car["id"]).one().status = "pending"
        app_ctx[2].session.commit()
    r = client.put(
        f"/api/cars/{car['id']}",
        json={"fuel_type": "Hybrid", "engine_type": "Hybrid"},
        headers=seller_headers,
    )
    assert r.status_code == 200, r.data
    assert r.get_json()["car"]["fuel_type"] == "hybrid"
    with app_ctx[0].app_context():
        Car = app_ctx[4]
        Car.query.filter_by(public_id=car["id"]).one().status = "active"
        app_ctx[2].session.commit()
    assert car["id"] in _search_ids(client, fuel_type="hybrid")
    assert car["id"] not in _search_ids(client, fuel_type="plug-in hybrid")


def test_other_stored_values_are_saved_exactly_as_before(client, app_ctx, seller_headers):
    car = _post(client, seller_headers, model="corolla", fuel="Gasoline", engine_size=1.6, cylinders=4)
    assert car["fuel_type"] == "Gasoline"
    assert car["id"] in _search_ids(client, fuel_type="gasoline")
