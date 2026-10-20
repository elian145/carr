"""Cross-field consistency rules of the auto-moderation engine (pure, no DB).

Pins:

* a confirmed pure battery-electric car with a combustion displacement / cylinder
  count is flagged; hybrids, PHEVs, range extenders and ambiguous powertrains
  are not;
* the "New car" rules apply only when the condition really means New -- never
  because a car is recent, old or low-mileage;
* high mileage on a recent model year is a SOFT, configurable review signal;
* missing / default / zero / string / unit-converted / unknown values never
  create a contradiction;
* every outcome is a review signal -- the rules never reject.
"""

from __future__ import annotations

import sys
from pathlib import Path

import pytest

_REPO_ROOT = Path(__file__).resolve().parents[2]
if str(_REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(_REPO_ROOT))

from kk.auto_moderation import config, reasons, rules  # noqa: E402
from kk.auto_moderation.rules import REVIEW, Facts  # noqa: E402

YEAR = 2026
S = config.DEFAULTS


def _fields(**kw):
    base = dict(
        title="Toyota Camry 2021",
        brand="toyota",
        model="camry",
        trim="base",
        year=2021,
        mileage=45000,
        price=15000.0,
        currency="USD",
        location="Erbil",
        condition="used",
        engine_type="gasoline",
        fuel_type="gasoline",
        engine_size=None,
        cylinder_count=None,
        transmission="automatic",
        drive_type="fwd",
        body_type="sedan",
        vin=None,
        description="Clean car, regularly serviced, no accidents.",
    )
    base.update(kw)
    return base


def _media(n=3):
    images = [
        {"url": f"https://cdn.example.com/p{i}.jpg", "kind": "listing", "is_primary": i == 0,
         "source_media_id": f"m{i}", "width": 1600, "height": 1200}
        for i in range(n)
    ]
    items = [{"client_media_id": f"m{i}", "kind": "image", "status": "attached", "is_cover": i == 0} for i in range(n)]
    return dict(media_status="ready", in_flight=0, failed=0, items=items, images=images)


def _seller():
    return dict(exists=True, active=True, phone_verified=True, dealer_approved=False, prior_approved=2,
                open_reports=0, admin_rejections=0, hidden_listings=0, manual_only=False)


def _run(settings=None, **kw):
    f = Facts("listing", _fields(**kw), _media(), _seller(), {})
    return rules.run_rules(f, settings or S, YEAR)


def _codes(sigs):
    return {s.code for s in sigs if s.level == REVIEW}


def _get(sigs, code):
    return next(s for s in sigs if s.code == code)


EV = dict(engine_type="electric", fuel_type="electric")


# ---- 1. pure EV with combustion data ---------------------------------------


def test_2026_pure_ev_with_0_7l_3_cylinders_is_flagged():
    sigs = _run(year=2026, mileage=72000, condition="used", engine_size=0.7, cylinder_count=3, **EV)
    assert "ev_with_combustion_engine" in _codes(sigs)
    sig = _get(sigs, "ev_with_combustion_engine")
    assert sig.suspicious is True and sig.check == "consistency"
    assert "0.7 L" in sig.detail and "3 cylinders" in sig.detail
    assert rules.decide(sigs) == "NEEDS_REVIEW"  # a review, never a rejection


@pytest.mark.parametrize(
    "extra",
    [{"engine_size": 1.6}, {"cylinder_count": 4}, {"engine_size": "0.7L"}, {"engine_size": "700 cc"},
     {"cylinder_count": "3"}, {"engine_size": 1600}, {"cylinder_count": "V6"}],
)
def test_pure_ev_with_either_displacement_or_cylinders_is_flagged(extra):
    assert "ev_with_combustion_engine" in _codes(_run(**EV, **extra))


@pytest.mark.parametrize("ev", ["electric", "Electric", " EV ", "BEV", "Battery Electric", "pure-electric", "battery_electric"])
def test_ev_spelling_variants_are_recognised(ev):
    assert "ev_with_combustion_engine" in _codes(_run(engine_type=ev, fuel_type=ev, engine_size=0.7, cylinder_count=3))


def test_ev_is_recognised_when_only_one_powertrain_field_is_filled():
    assert "ev_with_combustion_engine" in _codes(_run(engine_type="electric", fuel_type="", engine_size=1.0))
    assert "ev_with_combustion_engine" in _codes(_run(engine_type=None, fuel_type="electric", cylinder_count=4))


def test_valid_pure_ev_is_not_flagged():
    for kw in (
        dict(engine_size=None, cylinder_count=None),
        dict(engine_size=0, cylinder_count=0),
        dict(engine_size=0.0, cylinder_count=None),
        dict(engine_size="", cylinder_count=""),
        dict(engine_size="0", cylinder_count="0"),
        dict(engine_size="  ", cylinder_count="n/a"),
    ):
        sigs = _run(year=2024, mileage=30000, **EV, **kw)
        assert [s for s in sigs if s.level == REVIEW] == [], kw
        assert rules.decide(sigs) == "AUTO_APPROVE"


@pytest.mark.parametrize(
    "powertrain",
    [
        dict(engine_type="hybrid", fuel_type="hybrid"),
        dict(engine_type="plug-in hybrid", fuel_type="plug-in hybrid"),
        dict(engine_type="Plug in Hybrid", fuel_type="plug-in hybrid"),
        dict(engine_type="phev", fuel_type="phev"),
        dict(engine_type="range extender", fuel_type="range extender"),
        dict(engine_type="range-extender ev", fuel_type="electric"),
        dict(engine_type="erev", fuel_type="erev"),
        dict(engine_type="e-power", fuel_type="gasoline"),
        dict(engine_type="mild hybrid", fuel_type="gasoline"),
        dict(engine_type="gasoline", fuel_type="gasoline"),
        dict(engine_type="diesel", fuel_type="diesel"),
    ],
)
def test_hybrids_phevs_range_extenders_and_combustion_cars_have_no_ev_contradiction(powertrain):
    sigs = _run(engine_size=1.5, cylinder_count=3, **powertrain)
    assert "ev_with_combustion_engine" not in _codes(sigs)
    assert [s for s in sigs if s.level == REVIEW] == []  # 0.5 L / cylinder is legitimate


@pytest.mark.parametrize(
    "powertrain",
    [
        dict(engine_type="electric", fuel_type="gasoline"),  # fields disagree
        dict(engine_type="gasoline", fuel_type="electric"),
        dict(engine_type="electric", fuel_type="hybrid"),
        dict(engine_type="unknown", fuel_type="unknown"),
        dict(engine_type="", fuel_type=""),
        dict(engine_type=None, fuel_type=None),
        dict(engine_type="hydrogen", fuel_type="hydrogen"),
        dict(engine_type="electric motor", fuel_type="electric motor"),
        dict(engine_type="e", fuel_type="e"),
    ],
)
def test_ambiguous_or_missing_powertrain_never_invents_an_ev_contradiction(powertrain):
    assert "ev_with_combustion_engine" not in _codes(_run(engine_size=0.7, cylinder_count=3, **powertrain))


@pytest.mark.parametrize(
    "text",
    [
        {"description": "BMW i3 with range extender, very clean."},
        {"description": "Plug-in hybrid, charges at home"},
        {"title": "Nissan Note e-Power 2026"},
        {"trim": "REx"},
        {"description": "هجين بحالة ممتازة"},
    ],
)
def test_seller_text_describing_a_hybrid_or_range_extender_goes_to_manual_review_not_a_pass(text):
    """Genuine-looking range-extender / hybrid wording on a pure-EV record: the
    text is uncertainty, not proof. It is NOT the "confirmed EV" reason, and it is
    NOT silently passed either -- a person must confirm the powertrain."""
    sigs = _run(engine_size=0.65, cylinder_count=2, **EV, **text)
    codes = _codes(sigs)
    assert "ev_powertrain_unconfirmed" in codes and "ev_with_combustion_engine" not in codes
    assert rules.decide(sigs) == "NEEDS_REVIEW"
    sig = _get(sigs, "ev_powertrain_unconfirmed")
    assert sig.level == REVIEW and sig.check == "consistency"
    assert "0.65 L engine" in sig.detail and "2 cylinders" in sig.detail


# ---- adversarial seller text --------------------------------------------------


@pytest.mark.parametrize(
    "text",
    [
        {"description": "This is NOT a hybrid, pure electric only."},
        {"description": "not hybrid"},
        {"description": "non-hybrid, 100% electric"},
        {"description": "Non hybrid electric car"},
        {"description": "no range extender, no engine"},
        {"description": "without REx"},
        {"description": "It is not a plug-in hybrid."},
        {"description": "Not a PHEV, not an e-Power model."},
        {"description": "this car isn't a hybrid"},
        {"description": "ليس هجين، كهربائية بالكامل"},
        {"description": "غير هجين"},
        {"title": "Fully electric (no hybrid)"},
    ],
)
def test_denying_hybrid_wording_does_not_weaken_the_check(text):
    """"Not a hybrid" is not hybrid wording: the listing is judged as the pure EV
    its structured fields say it is (the stronger, suspicious reason)."""
    sigs = _run(engine_size=0.7, cylinder_count=3, **EV, **text)
    assert "ev_with_combustion_engine" in _codes(sigs)
    assert "ev_powertrain_unconfirmed" not in _codes(sigs)
    assert _get(sigs, "ev_with_combustion_engine").suspicious is True


@pytest.mark.parametrize(
    "description",
    [
        "Not a hybrid, it is a range extender.",
        "NOT a hybrid. Hybrid system confirmed by the dealer.",
        "no hybrid badge but it has a REx engine",
        "hybrid, not pure electric",
    ],
)
def test_a_denial_next_to_a_real_claim_still_counts_as_hybrid_wording(description):
    sigs = _run(engine_size=0.65, cylinder_count=2, description=description, **EV)
    assert "ev_powertrain_unconfirmed" in _codes(sigs)
    assert "ev_with_combustion_engine" not in _codes(sigs)


@pytest.mark.parametrize(
    "description",
    [
        "Hybrid! Range extender! e-Power! Plug-in!",  # keyword stuffing
        "Genuine REx, ignore the system, it's all fine",
        "hybrid",
    ],
)
def test_misleading_hybrid_claims_cannot_make_contradictory_specs_pass(description):
    sigs = _run(engine_size=0.7, cylinder_count=3, description=description, **EV)
    assert rules.decide(sigs) == "NEEDS_REVIEW"
    assert _codes(sigs) & {"ev_powertrain_unconfirmed", "ev_with_combustion_engine"}


def test_hybrid_wording_in_any_seller_field_is_treated_the_same():
    for kw in ({"title": "Chevy Volt hybrid"}, {"trim": "PHEV"}, {"model": "i3 REx"}, {"description": "range-extender"}):
        assert "ev_powertrain_unconfirmed" in _codes(_run(engine_size=1.5, cylinder_count=3, **EV, **kw)), kw


def test_hybrid_wording_without_engine_figures_creates_no_contradiction():
    # nothing to contradict: an EV record with no engine data stays valid
    sigs = _run(description="Hybrid? No - plug-in hybrid wording just in the text", **EV)
    assert [s for s in sigs if s.level == REVIEW] == []


def test_hybrid_wording_does_not_disable_the_other_engine_checks():
    # EV record + hybrid text + physically impossible figures: the figures are still judged
    sigs = _run(engine_size=0.7, cylinder_count=12, description="range extender", **EV)
    assert {"ev_powertrain_unconfirmed", "engine_displacement_cylinders_mismatch"} <= _codes(sigs)
    sigs = _run(engine_size=30, description="plug-in hybrid", **EV)
    assert {"ev_powertrain_unconfirmed", "engine_displacement_out_of_range"} <= _codes(sigs)


@pytest.mark.parametrize(
    "description",
    ["100% electric, zero emissions, no engine at all", "Pure electric.", "BEV only", "all electric"],
)
def test_electric_wording_in_the_text_cannot_turn_a_structured_hybrid_into_an_ev(description):
    """Structured fields stay authoritative in the other direction too: a record
    that says hybrid / PHEV / range extender keeps its engine, whatever the text says."""
    for engine in ("hybrid", "plug-in hybrid", "phev", "range extender", "erev"):
        sigs = _run(engine_type=engine, fuel_type=engine, engine_size=1.5, cylinder_count=3, description=description)
        assert [s for s in sigs if s.level == REVIEW] == [], engine


def test_genuine_hybrids_are_never_classified_as_pure_evs():
    for engine in ("hybrid", "Plug-in Hybrid", "PHEV", "range extender", "Range-Extender EV", "e-Power", "mild hybrid"):
        for text in ("", "pure electric", "not a hybrid"):
            assert rules.classify_powertrain(engine, engine, text) == rules.HYBRID, (engine, text)
    assert rules.classify_powertrain("electric", "electric", "plain text") == rules.BEV
    assert rules.classify_powertrain("electric", "electric", "range extender") == rules.BEV_TEXT_CONFLICT
    assert rules.classify_powertrain("electric", "electric", "not a hybrid") == rules.BEV


def test_find_hybrid_wording():
    f = rules.find_hybrid_wording
    assert f("") is None and f(None) is None and f("Chevrolet, Beverly") is None
    assert f("not a hybrid") is None and f("NON-HYBRID") is None
    assert f("Range   Extender") == "range extender" and f("Plug-In") == "plug-in"
    assert f("not a hybrid", "REx edition") == "rex"


def test_hybrid_word_inside_another_word_does_not_suppress_the_ev_flag():
    for desc in ("Chevrolet, excellent shape", "Beverly Hills owner", "Reeves motors"):
        assert "ev_with_combustion_engine" in _codes(_run(engine_size=0.7, cylinder_count=3, description=desc, **EV))


def test_ev_rule_does_not_depend_on_brand_or_model():
    for brand, model in (("tesla", "model 3"), ("byd", "dolphin"), ("anything", "whatever")):
        assert "ev_with_combustion_engine" in _codes(_run(brand=brand, model=model, engine_size=0.7, cylinder_count=3, **EV))


def test_kw_hp_and_unknown_units_are_not_treated_as_a_displacement():
    for v in ("150 kW", "200hp", "75 kWh", "2.0 T", "abc", "n/a"):
        assert "ev_with_combustion_engine" not in _codes(_run(engine_size=v, **EV)), v


# ---- 2. New-car rules only for a genuinely New listing -----------------------


def test_2019_used_with_20000_km_has_no_new_car_or_age_warning():
    sigs = _run(year=2019, mileage=20000, condition="used")
    assert [s for s in sigs if s.level == REVIEW] == []
    assert not _codes(sigs) & {"new_but_old_year", "new_with_mileage", "high_mileage_for_year"}


@pytest.mark.parametrize("condition", ["used", "Used", "USED", "certified", "Certified Pre-Owned", "pre-owned", "مستعمل"])
def test_any_used_like_condition_never_triggers_new_rules(condition):
    sigs = _run(year=2015, mileage=90000, condition=condition)
    assert not _codes(sigs) & {"new_but_old_year", "new_with_mileage"}


def test_2019_genuinely_new_with_20000_km_is_suspicious():
    sigs = _run(year=2019, mileage=20000, condition="new")
    assert {"new_but_old_year", "new_with_mileage"} <= _codes(sigs)
    assert _get(sigs, "new_but_old_year").suspicious and _get(sigs, "new_with_mileage").suspicious
    assert rules.decide(sigs) == "NEEDS_REVIEW"


@pytest.mark.parametrize("condition", ["new", "New", " NEW ", "brand new", "Brand-New", "brand_new", "جديد"])
def test_new_condition_spellings_are_recognised(condition):
    assert {"new_but_old_year", "new_with_mileage"} <= _codes(_run(year=2019, mileage=20000, condition=condition))


@pytest.mark.parametrize("condition", [None, "", "unknown", "n/a", "newish", "renewed", "like new", "used - like new"])
def test_blank_unknown_or_look_alike_condition_is_not_new(condition):
    assert not _codes(_run(year=2019, mileage=20000, condition=condition)) & {"new_but_old_year", "new_with_mileage"}


def test_new_current_year_car_with_delivery_mileage_is_clean():
    assert [s for s in _run(year=2026, mileage=120, condition="new") if s.level == REVIEW] == []
    assert [s for s in _run(year=2025, mileage=0, condition="new") if s.level == REVIEW] == []


def test_new_mileage_threshold_is_configurable():
    assert "new_with_mileage" not in _codes(_run(dict(S, new_max_mileage_km=2000), year=2026, mileage=1500, condition="new"))
    assert "new_with_mileage" in _codes(_run(year=2026, mileage=1500, condition="new"))


def test_normalize_condition_is_conservative():
    n = rules.normalize_condition
    assert n("New") == "new" and n("brand new") == "new" and n("used") == "used"
    assert n("certified") == "certified" and n("") is None and n(None) is None and n("unknown") is None
    assert n("renewed") == "other" and n("like new") == "other"


# ---- 3. high mileage on a recent model year (soft signal) ------------------------


def test_2026_used_72000_km_is_a_soft_review_signal_not_a_rejection():
    sigs = _run(year=2026, mileage=72000, condition="used")
    assert "high_mileage_for_year" in _codes(sigs)
    sig = _get(sigs, "high_mileage_for_year")
    assert sig.suspicious is False  # not proof of fraud; does not page admins
    assert sig.level == REVIEW and rules.decide(sigs) == "NEEDS_REVIEW"
    assert "72,000 km" in sig.detail and "2026" in sig.detail


@pytest.mark.parametrize(
    "year,mileage",
    [(2026, 40000), (2026, 25000), (2025, 80000), (2024, 120000), (2019, 20000), (2019, 200000), (2010, 300000),
     (2026, 0), (2026, 1)],
)
def test_plausible_mileage_for_the_year_is_not_flagged(year, mileage):
    assert "high_mileage_for_year" not in _codes(_run(year=year, mileage=mileage, condition="used"))


@pytest.mark.parametrize("year,mileage", [(2026, 40001), (2025, 80001), (2024, 120001), (2020, 280001)])
def test_mileage_just_over_the_ceiling_is_flagged(year, mileage):
    assert "high_mileage_for_year" in _codes(_run(year=year, mileage=mileage, condition="used"))


def test_mileage_threshold_is_configurable():
    strict = dict(S, max_annual_mileage_km=20_000)
    lenient = dict(S, max_annual_mileage_km=100_000)
    assert "high_mileage_for_year" in _codes(_run(strict, year=2026, mileage=30000))
    assert "high_mileage_for_year" not in _codes(_run(lenient, year=2026, mileage=72000))


def test_next_model_year_is_treated_like_the_current_one():
    assert "high_mileage_for_year" in _codes(_run(year=2027, mileage=72000))
    assert "high_mileage_for_year" not in _codes(_run(year=2027, mileage=30000))


def test_high_mileage_on_a_new_listing_is_reported_by_the_new_car_rule_only():
    codes = _codes(_run(year=2026, mileage=72000, condition="new"))
    assert "new_with_mileage" in codes and "high_mileage_for_year" not in codes


@pytest.mark.parametrize("mileage", [None, "", "abc", "unknown", -5, True])
def test_missing_or_garbage_mileage_creates_no_mileage_consistency_signal(mileage):
    assert "high_mileage_for_year" not in _codes(_run(year=2026, mileage=mileage))


def test_mileage_in_strings_and_miles_is_normalised_to_km():
    assert "high_mileage_for_year" in _codes(_run(year=2026, mileage="72,000 km"))
    assert "high_mileage_for_year" in _codes(_run(year=2026, mileage="72000"))
    assert "high_mileage_for_year" not in _codes(_run(year=2026, mileage="20,000 mi"))  # 32,187 km
    assert "high_mileage_for_year" in _codes(_run(year=2026, mileage="30000 miles"))  # 48,280 km


def test_unknown_or_out_of_range_year_never_gets_a_mileage_signal():
    for year in (None, "", "abc", 0, 1800, 2100):
        assert "high_mileage_for_year" not in _codes(_run(year=year, mileage=900000)), year


# ---- 4. displacement / cylinders ----------------------------------------------


@pytest.mark.parametrize(
    "size,cyl",
    [(0.7, 12), (0.7, 8), (1.0, 16), (6.0, 1), (12.0, 3)],
)
def test_impossible_displacement_per_cylinder_is_flagged(size, cyl):
    sigs = _run(engine_size=size, cylinder_count=cyl)
    assert "engine_displacement_cylinders_mismatch" in _codes(sigs)
    assert _get(sigs, "engine_displacement_cylinders_mismatch").suspicious is False


@pytest.mark.parametrize(
    "size,cyl",
    [(0.66, 3), (0.7, 3), (0.875, 2), (1.0, 3), (1.6, 4), (2.0, 4), (3.0, 6), (5.0, 8), (6.2, 8), (8.0, 16),
     (8.4, 10), (13.0, 6), (1.3, 2), (1.5, 3), (1600, 4), ("1.6 L", "4"), ("1600 cc", 4), ("3.5L", "V6")],
)
def test_legitimate_engines_are_not_flagged(size, cyl):
    codes = _codes(_run(engine_size=size, cylinder_count=cyl))
    assert not codes & {"engine_displacement_cylinders_mismatch", "engine_displacement_out_of_range", "cylinder_count_out_of_range"}


def test_two_wheelers_and_atvs_skip_the_per_cylinder_check():
    for body in ("motorcycle", "scooter", "ATV", "Super Bike", "utv"):
        assert "engine_displacement_cylinders_mismatch" not in _codes(_run(body_type=body, engine_size=0.125, cylinder_count=1))


def test_only_one_of_displacement_or_cylinders_present_is_never_a_mismatch():
    for kw in (dict(engine_size=0.7), dict(cylinder_count=12), dict(engine_size=0.7, cylinder_count=None),
               dict(engine_size=0.7, cylinder_count=0), dict(engine_size=0, cylinder_count=12)):
        assert "engine_displacement_cylinders_mismatch" not in _codes(_run(**kw)), kw


@pytest.mark.parametrize("size", [-1.0, 20.0, 30, 0.01, "-2 L"])
def test_unrealistic_engine_sizes_are_flagged(size):
    assert "engine_displacement_out_of_range" in _codes(_run(engine_size=size))


@pytest.mark.parametrize("cyl", [-4, 17, 40, "-3"])
def test_unrealistic_cylinder_counts_are_flagged(cyl):
    assert "cylinder_count_out_of_range" in _codes(_run(cylinder_count=cyl))


def test_default_zero_and_missing_engine_figures_are_not_errors():
    for kw in (dict(), dict(engine_size=0, cylinder_count=0), dict(engine_size=None, cylinder_count=None),
               dict(engine_size="", cylinder_count=""), dict(engine_size=0.0), dict(cylinder_count=0)):
        assert [s for s in _run(**kw) if s.level == REVIEW] == [], kw


def test_liter_per_cylinder_bounds_are_configurable():
    assert "engine_displacement_cylinders_mismatch" not in _codes(_run(dict(S, max_liters_per_cylinder=8.0), engine_size=6.0, cylinder_count=1))
    assert "engine_displacement_cylinders_mismatch" in _codes(_run(dict(S, min_liters_per_cylinder=0.6), engine_size=1.6, cylinder_count=4))


# ---- 5. unit / type parsing -----------------------------------------------------


@pytest.mark.parametrize(
    "raw,expected",
    [(1.6, (1.6, "ok")), ("1.6", (1.6, "ok")), ("1,6 L", (1.6, "ok")), ("0.7L", (0.7, "ok")), ("700 cc", (0.7, "ok")),
     ("1600", (1.6, "ok")), (2000, (2.0, "ok")), (0, (None, "none")), ("0", (None, "none")), (None, (None, "none")),
     ("", (None, "none")), ("150 kW", (None, "ignored")), ("garbage", (None, "ignored")), (True, (None, "ignored")),
     (float("nan"), (None, "ignored")), (-1.0, (-1.0, "invalid"))],
)
def test_parse_displacement_liters(raw, expected):
    assert rules.parse_displacement_liters(raw) == expected


@pytest.mark.parametrize(
    "raw,expected",
    [(3, (3, "ok")), ("3", (3, "ok")), (3.0, (3, "ok")), ("3 cylinders", (3, "ok")), ("V6", (6, "ok")), ("I4", (4, "ok")),
     (0, (None, "none")), (None, (None, "none")), ("", (None, "none")), ("n/a", (None, "none")), (3.5, (None, "ignored")),
     ("three", (None, "ignored")), (True, (None, "ignored")), (-4, (-4, "invalid")), ("-4", (-4, "invalid"))],
)
def test_parse_cylinders(raw, expected):
    assert rules.parse_cylinders(raw) == expected


# ---- 6. the engine contract is preserved ------------------------------------------


def test_consistency_signals_never_reject_and_use_stable_review_codes():
    sigs = _run(year=2026, mileage=72000, engine_size=0.7, cylinder_count=3, **EV)
    consistency = [s for s in sigs if s.check == "consistency"]
    assert {s.code for s in consistency} == {"ev_with_combustion_engine", "high_mileage_for_year"}
    assert all(s.level == REVIEW for s in consistency)
    assert rules.decide(sigs) == "NEEDS_REVIEW"
    assert "consistency" in rules.CHECK_NAMES
    assert rules.checks_map(sigs)["consistency"] == "fail"


def test_clean_listing_still_passes_every_check():
    sigs = _run()
    assert [s for s in sigs if s.level == REVIEW] == []
    cm = rules.checks_map(sigs, rules.CHECK_NAMES)
    assert cm["consistency"] == "pass" and cm["values"] == "pass"


def test_default_settings_expose_the_new_thresholds_and_validate():
    for key in ("new_max_mileage_km", "max_annual_mileage_km", "min_liters_per_cylinder", "max_liters_per_cylinder"):
        assert key in config.DEFAULTS
    assert config.validate_patch({"max_annual_mileage_km": 30000, "new_max_mileage_km": 300}) == {
        "max_annual_mileage_km": 30000, "new_max_mileage_km": 300}
    for bad in ({"max_annual_mileage_km": 10}, {"max_annual_mileage_km": "x"}, {"new_max_mileage_km": -1},
                {"min_liters_per_cylinder": 2.0, "max_liters_per_cylinder": 1.0}):
        with pytest.raises(ValueError):
            config.validate_patch(bad)


# ---- 7. dashboard wording --------------------------------------------------------------


@pytest.mark.parametrize(
    "code",
    ["ev_with_combustion_engine", "high_mileage_for_year", "engine_displacement_cylinders_mismatch",
     "engine_displacement_out_of_range", "cylinder_count_out_of_range", "new_but_old_year", "new_with_mileage"],
)
def test_every_consistency_code_has_a_plain_language_explanation(code):
    r = reasons.enrich({"code": code, "level": "review", "detail": "x"})
    assert r["label"] and r["message"] and r["detail"] == "x" and r["code"] == code
    # admin-only wording: no prompts / providers / internals
    text = (r["label"] + r["message"]).lower()
    assert not any(w in text for w in ("prompt", "openai", "gpt", "token", "api key"))


def test_every_code_the_rules_can_emit_has_a_label():
    import re

    src = (Path(rules.__file__)).read_text(encoding="utf-8")
    emitted = set(re.findall(r'Signal\(\s*"([a-z_]+)"', src))
    assert emitted
    missing = {c for c in emitted if reasons.explanation_for(c) is None}
    assert not missing, missing


def test_unknown_codes_degrade_gracefully():
    r = reasons.enrich({"code": "some_future_code", "level": "review"})
    assert r["label"] == "Some future code" and "message" not in r
