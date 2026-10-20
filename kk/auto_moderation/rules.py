"""Deterministic moderation rules (pure functions, no I/O).

Input is a ``Facts`` snapshot assembled by the engine; output is a list of
``Signal`` objects plus a per-check status map. Nothing here touches the
database, the network or the clock (the current year is passed in), so every
rule is unit-testable in isolation.

Signal levels
-------------
``hold``    the listing cannot be judged yet (media still processing / failed,
            moderation service unavailable). -> decision HOLD
``review``  an administrator must look at it. -> decision NEEDS_REVIEW
``info``    recorded for the admin, never blocks approval.

``suspicious`` separates "something looks wrong" from "routine, just not
provable by rules" (brand-new seller, AI provider not configured). Only
suspicious signals page admins by default.

There is no reject level: automation never rejects.
"""

from __future__ import annotations

import re
from dataclasses import dataclass, field
from typing import Any

HOLD = "hold"
REVIEW = "review"
INFO = "info"


@dataclass
class Signal:
    code: str
    level: str  # hold | review | info
    check: str
    suspicious: bool = False
    detail: str | None = None  # short, non-PII (numbers / field names only)

    def to_dict(self) -> dict:
        return {
            "code": self.code,
            "level": self.level,
            "check": self.check,
            "suspicious": self.suspicious,
            "detail": self.detail,
        }


@dataclass
class Facts:
    subject_type: str  # listing | revision
    fields: dict[str, Any]
    media: dict[str, Any]
    seller: dict[str, Any]
    duplicates: dict[str, Any] = field(default_factory=dict)
    revision: dict[str, Any] | None = None
    payment: dict[str, Any] = field(default_factory=dict)


# ---------------------------------------------------------------------------
# Text patterns
# ---------------------------------------------------------------------------

# Obvious scam / prohibited content. Matches only ever route a listing to a
# human; nothing is auto-rejected on a pattern hit.
_SCAM = re.compile(
    r"("
    r"guaranteed\s+profit|double\s+your\s+money|crypto\s+invest|free\s+money|"
    r"click\s+here\s+now|earn\s+\$\d+|western\s*union|money\s*gram|"
    r"advance\s+(fee|payment)|gift\s*cards?|bitcoin|usdt|binance|"
    r"ربح\s*مضمون|ارباح\s*مضمونة|أرباح\s*مضمونة|مضاعفة\s*(اموالك|أموالك)|ويسترن\s*يونيون"
    r")",
    re.IGNORECASE,
)
_PROHIBITED = re.compile(
    r"\b(cocaine|heroin|marijuana|hashish|escort|casino|porn|xxx|viagra|"
    r"firearms?|rifles?|pistols?|ammunition|weapons?)\b",
    re.IGNORECASE,
)
_NON_CAR = re.compile(
    r"\b(iphone|laptop|apartment\s+for\s+(rent|sale)|job\s+vacancy|"
    r"loans?\s+available|visa\s+service)\b",
    re.IGNORECASE,
)
_URL = re.compile(
    r"(https?://|www\.|t\.me/|wa\.me/|bit\.ly/|\b[\w-]+\.(com|net|org|io|me|ly|info|biz)\b)",
    re.IGNORECASE,
)
_EMAIL = re.compile(r"[\w.+-]+@[\w-]+\.[\w.-]+")
_PHONE = re.compile(r"(?:\+?\d[\s().-]?){9,}")
_REPEAT_CHAR = re.compile(r"(.)\1{9,}")
_VIN = re.compile(r"^[A-HJ-NPR-Z0-9]{17}$")
_PLACEHOLDERS = {"", "unknown", "n/a", "na", "none", "null", "-", "--", "test", "asdf", "xxx"}

REQUIRED_TEXT_FIELDS = (
    "brand",
    "model",
    "location",
    "engine_type",
    "transmission",
    "drive_type",
    "condition",
    "body_type",
)


def _clean(v) -> str:
    return str(v if v is not None else "").strip()


# ---------------------------------------------------------------------------
# Value normalisation (pure; tolerant of None, defaults, strings and units)
# ---------------------------------------------------------------------------

_KM_PER_MILE = 1.609344
_NUMBER_WITH_UNIT = re.compile(r"^\s*([+-]?\d+(?:[.,]\d+)?)\s*([^\d\s][^\d]*)?\s*$")


def _num_unit(v) -> tuple[float | None, str]:
    """``(number, lowercase unit)`` from a number or a string such as
    ``"1.6 L"`` / ``"72,000 km"``. ``(None, "")`` when there is no usable
    number (bools, NaN, text). Thousands separators ("72,000") are accepted
    only when unambiguous (a comma followed by exactly three digits)."""
    if v is None or isinstance(v, bool):
        return None, ""
    if isinstance(v, (int, float)):
        x = float(v)
        return (x, "") if x == x and x not in (float("inf"), float("-inf")) else (None, "")
    text = str(v).strip()
    if not text:
        return None, ""
    text = re.sub(r"(?<=\d),(?=\d{3}(?!\d))", "", text)
    m = _NUMBER_WITH_UNIT.match(text.replace("\u00a0", " "))
    if not m:
        return None, ""
    try:
        x = float(m.group(1).replace(",", "."))
    except ValueError:
        return None, ""
    return x, (m.group(2) or "").strip().lower().rstrip(".")


def _to_int(v) -> int | None:
    x, unit = _num_unit(v)
    if x is None or unit or x != int(x):
        return None
    return int(x)


def _mileage_km(v) -> int | None:
    """Odometer reading in kilometres. The database stores kilometres (the app
    converts miles before sending); a string with an explicit ``mi`` / ``miles``
    unit is converted too. Anything else that is not a plain number is
    unknown (``None``), never guessed."""
    x, unit = _num_unit(v)
    if x is None:
        return None
    if unit in ("", "km", "kms", "kilometer", "kilometers", "kilometre", "kilometres"):
        return int(round(x))
    if unit in ("mi", "mile", "miles"):
        return int(round(x * _KM_PER_MILE))
    return None


_CONDITION_ALIASES = {
    "new": "new",
    "brand new": "new",
    "جديد": "new",
    "جديدة": "new",
    "used": "used",
    "pre owned": "used",
    "preowned": "used",
    "second hand": "used",
    "secondhand": "used",
    "مستعمل": "used",
    "مستعملة": "used",
    "certified": "certified",
    "certified pre owned": "certified",
    "cpo": "certified",
}


def _token(v) -> str:
    """Lowercase, separators (``-`` ``_`` ``/`` ``+``) collapsed to one space."""
    return re.sub(r"[\s_\-/+]+", " ", _clean(v).lower()).strip()


def normalize_condition(v) -> str | None:
    """Canonical listing condition: ``new`` | ``used`` | ``certified`` |
    ``other`` (non-empty, not recognised) | ``None`` (blank / placeholder).

    ``new`` is returned only for an explicit New value, so a vehicle is never
    treated as brand new because it is recent or low-mileage."""
    t = _token(v)
    if t in _PLACEHOLDERS:
        return None
    return _CONDITION_ALIASES.get(t, "other")


# Powertrain classification ---------------------------------------------------

#: Values that mean a pure battery-electric vehicle, and nothing else.
_BEV_VALUES = frozenset(
    {
        "electric",
        "ev",
        "bev",
        "battery electric",
        "battery electric vehicle",
        "pure electric",
        "full electric",
        "all electric",
        "electric vehicle",
        "كهربائية",
        "كهربائي",
        "كهرباء",
    }
)
#: Plain combustion fuels (no electric component).
_COMBUSTION_VALUES = frozenset(
    {"gasoline", "gas", "petrol", "benzin", "diesel", "lpg", "cng", "gasoline lpg", "petrol lpg"}
)
#: Anything that suggests an electrified-but-combustion-assisted powertrain:
#: hybrid / plug-in / range extender / e-power ... Such a vehicle legitimately
#: has an engine, so it is never "a pure EV".
_HYBRID_TERMS_LATIN = (
    r"(?:hybrid|phev|mhev|hev|erev|reev|rex|range\s*-?\s*extender|e[\s-]?power|plug[\s-]*in|fuel\s*cell)"
)
_HYBRID_TERMS_AR = r"(?:هجين|هايبرد|هايبريد)"
_HYBRID_HINT = re.compile(rf"(\b{_HYBRID_TERMS_LATIN}\b|{_HYBRID_TERMS_AR})", re.IGNORECASE)
#: "not a hybrid", "non-hybrid", "no range extender", "without REx", "not a
#: plug-in hybrid", "ليس هجين" ... A negated mention is not wording that
#: suggests a hybrid. (Negation makes the listing MORE suspicious, never less:
#: it is then judged as the pure EV its structured fields say it is.)
_NEGATED_HYBRID = re.compile(
    r"(?:\b(?:not|no|non|never|without|isn'?t|neither|nor)\b[\s-]*(?:(?:an?|any|the)\s+)?"
    r"|غير\s*|ليس\w*\s*|بدون\s*)"
    rf"(?:(?:plug[\s-]*in|mild|full|self[\s-]*charging)[\s-]+)?(?:\b{_HYBRID_TERMS_LATIN}\b|{_HYBRID_TERMS_AR})",
    re.IGNORECASE,
)

BEV = "bev"
#: Structured fields say pure electric, but seller-written text claims a hybrid /
#: range-extender system. Free text is NOT proof of the powertrain, so this is
#: neither "confirmed pure EV" nor silently fine: it goes to a person.
BEV_TEXT_CONFLICT = "bev_text_conflict"
COMBUSTION = "combustion"
HYBRID = "hybrid"
UNKNOWN = "unknown"


def find_hybrid_wording(*texts) -> str | None:
    """The first (non-negated) hybrid / plug-in / range-extender term found in
    seller-written text, lower-cased; ``None`` when there is none."""
    for t in texts:
        if not t:
            continue
        m = _HYBRID_HINT.search(_NEGATED_HYBRID.sub(" ", str(t)))
        if m:
            return re.sub(r"\s+", " ", m.group(0)).strip().lower()
    return None


def classify_powertrain(engine_type, fuel_type, *texts) -> str:
    """The powertrain implied by the STRUCTURED fields (``engine_type`` /
    ``fuel_type``); seller text can never change that verdict.

    ``bev``              every filled-in field says pure battery-electric.
    ``bev_text_conflict``  same, but title / trim / model / description
                         mention a hybrid or range-extender system: the text
                         is uncertainty to be resolved by a person, not proof.
    ``hybrid``           a structured field says hybrid / PHEV / range extender.
    ``combustion``       plain gasoline / diesel / LPG / CNG.
    ``unknown``          missing, contradicting or unrecognised values (never a
                         basis for a contradiction)."""
    values = [t for t in (_token(engine_type), _token(fuel_type)) if t and t not in _PLACEHOLDERS]
    if not values:
        return UNKNOWN
    if any(_HYBRID_HINT.search(v) for v in values):
        return HYBRID
    electric = [v in _BEV_VALUES for v in values]
    if all(electric):
        return BEV_TEXT_CONFLICT if find_hybrid_wording(*texts) else BEV
    if any(electric):
        return UNKNOWN  # e.g. engine_type "electric" but fuel_type "gasoline"
    if all(v in _COMBUSTION_VALUES for v in values):
        return COMBUSTION
    return UNKNOWN


# Engine displacement / cylinders ----------------------------------------------

#: Units that identify a number as something other than a displacement.
_NOT_DISPLACEMENT_UNITS = frozenset({"kw", "hp", "ps", "bhp", "kwh", "wh", "nm", "kg", "v", "ah", "a"})
_CC_UNITS = frozenset({"cc", "cm3", "cm³", "cm^3", "ml"})
_LITER_UNITS = frozenset({"l", "lt", "ltr", "liter", "liters", "litre", "litres"})

MIN_DISPLACEMENT_L = 0.05
MAX_DISPLACEMENT_L = 16.0
MAX_CYLINDERS = 16
#: Bodies whose engines are legitimately tiny / single-cylinder; the
#: displacement-per-cylinder plausibility check does not apply to them.
_SMALL_ENGINE_BODIES = frozenset(
    {"motorcycle", "scooter", "super bike", "superbike", "atv", "utv", "micro", "moped"}
)


def parse_displacement_liters(v) -> tuple[float | None, str]:
    """``(liters, status)``. status: ``none`` (missing / zero), ``ok``,
    ``invalid`` (negative), ``ignored`` (not a displacement figure: kW, text
    ...). The app stores litres; a unitless value of 50 or more is read as
    cubic centimetres (``1600`` -> 1.6 L), an explicit unit always wins."""
    if v is None or (isinstance(v, str) and _token(v) in _PLACEHOLDERS):
        return None, "none"
    x, unit = _num_unit(v)
    if x is None:
        return None, "ignored"
    if unit in _NOT_DISPLACEMENT_UNITS:
        return None, "ignored"
    if unit in _CC_UNITS:
        x = x / 1000.0
    elif unit in _LITER_UNITS or unit == "":
        if unit == "" and x >= 50:
            x = x / 1000.0
    else:
        return None, "ignored"
    if x == 0:
        return None, "none"
    if x < 0:
        return x, "invalid"
    return x, "ok"


def parse_cylinders(v) -> tuple[int | None, str]:
    """``(count, status)`` with status ``none`` | ``ok`` | ``invalid`` |
    ``ignored``. Accepts ``3``, ``"3"``, ``"3 cylinders"`` and ``"V6"`` style
    strings; anything else is ignored (unknown), not an error."""
    if v is None:
        return None, "none"
    if isinstance(v, bool):
        return None, "ignored"
    if isinstance(v, str) and _clean(v).lower() in _PLACEHOLDERS:
        return None, "none"
    x, unit = _num_unit(v)
    if x is not None and (unit == "" or re.fullmatch(r"cyl\w*|cylinders?", unit)):
        if x != int(x):
            return None, "ignored"
        n = int(x)
    else:
        # "V6" / "I4" / "W12" style engine layouts.
        m = re.fullmatch(r"[vwil]\s?-?(\d{1,2})", _clean(v).lower()) if isinstance(v, str) else None
        if not m:
            return None, "ignored"
        n = int(m.group(1))
    if n == 0:
        return None, "none"
    if n < 0:
        return n, "invalid"
    return n, "ok"


def normalize_text(text: str | None) -> str:
    """Lowercased, whitespace/punctuation collapsed -- used for duplicate
    description comparison."""
    return re.sub(r"[\W_]+", " ", (text or "").lower()).strip()


def redact_for_provider(text: str | None) -> str:
    """Remove contact details before text is sent to an external provider."""
    t = text or ""
    t = _EMAIL.sub("[email]", t)
    t = _URL.sub("[link]", t)
    t = _PHONE.sub("[phone]", t)
    return t[:4000]


# ---------------------------------------------------------------------------
# Rule groups
# ---------------------------------------------------------------------------


def check_required_fields(f: Facts, s: dict) -> list[Signal]:
    out: list[Signal] = []
    for name in REQUIRED_TEXT_FIELDS:
        if _clean(f.fields.get(name)).lower() in _PLACEHOLDERS:
            out.append(Signal("missing_field", REVIEW, "required_fields", False, name))
    for name in ("year", "mileage", "price"):
        if f.fields.get(name) in (None, ""):
            out.append(Signal("missing_field", REVIEW, "required_fields", False, name))
    return out


def check_values(f: Facts, s: dict, current_year: int) -> list[Signal]:
    out: list[Signal] = []
    year = _to_int(f.fields.get("year"))
    mileage = _mileage_km(f.fields.get("mileage"))
    price = f.fields.get("price")
    currency = _clean(f.fields.get("currency")).upper() or "USD"
    # The listing's condition is a free-form string column (the app sends
    # "new" / "used"; the create endpoint stores it as received, the update
    # endpoint lower-cases it). The "new car" rules below apply ONLY when it
    # unambiguously means New -- never because of a vehicle's age or mileage.
    condition = normalize_condition(f.fields.get("condition"))
    is_new = condition == "new"

    if year is not None:
        if year < int(s.get("min_year", 1950)) or year > current_year + 1:
            out.append(Signal("year_out_of_range", REVIEW, "values", True, str(year)))
        if is_new and year < current_year - 1:
            out.append(Signal("new_but_old_year", REVIEW, "values", True, f"{year} model year, listed as New"))
    if mileage is not None:
        if mileage < 0 or mileage > int(s.get("max_mileage", 1_000_000)):
            out.append(Signal("mileage_out_of_range", REVIEW, "values", True, str(mileage)))
        elif is_new and mileage > int(s.get("new_max_mileage_km", 500)):
            out.append(Signal("new_with_mileage", REVIEW, "values", True, f"{mileage:,} km, listed as New"))
        elif mileage == 0 and condition not in ("new", None) and year is not None and year < current_year:
            # The create endpoint defaults a missing mileage to 0.
            out.append(Signal("used_zero_mileage", REVIEW, "values", False, None))
    if price is not None:
        try:
            p = float(price)
        except (TypeError, ValueError):
            p = None
        bounds = (s.get("currency_price_bounds") or {}).get(currency)
        if p is None or p <= 0:
            out.append(Signal("price_invalid", REVIEW, "values", True, None))
        elif not bounds:
            out.append(Signal("unknown_currency", REVIEW, "values", False, currency))
        elif p < float(bounds[0]) or p > float(bounds[1]):
            out.append(Signal("price_out_of_range", REVIEW, "values", True, f"{currency} {p:g}"))
    vin = _clean(f.fields.get("vin")).upper()
    if vin and not _VIN.match(vin):
        out.append(Signal("vin_invalid", REVIEW, "values", True, None))
    return out


def _fmt_liters(x: float) -> str:
    return f"{x:.1f}".rstrip("0").rstrip(".") if x >= 1 else f"{x:.2f}".rstrip("0").rstrip(".")


def check_consistency(f: Facts, s: dict, current_year: int) -> list[Signal]:
    """Relationships BETWEEN the listing's own specifications.

    Every rule needs positive evidence on both sides and stays silent on
    missing, default, zero, unit-less-and-ambiguous or unrecognised values --
    a missing attribute is never a contradiction. Nothing here compares a
    vehicle against brand / model factory specifications (the server has no
    reliable spec data for that); only physical / logical impossibilities and
    soft statistical outliers are raised. All of them route to a human; none
    rejects."""
    out: list[Signal] = []
    fx = f.fields
    powertrain = classify_powertrain(
        fx.get("engine_type"), fx.get("fuel_type"), fx.get("title"), fx.get("trim"), fx.get("model"),
        fx.get("description"),
    )
    disp, dstatus = parse_displacement_liters(fx.get("engine_size"))
    cyl, cstatus = parse_cylinders(fx.get("cylinder_count"))
    has_disp = dstatus == "ok"
    has_cyl = cstatus == "ok"

    # 1. A pure battery-electric vehicle has no combustion engine. The verdict
    #    comes from the structured fields only; seller wording about a hybrid /
    #    range extender can change WHICH reason a person sees, never whether one
    #    is raised.
    parts = []
    if has_disp:
        parts.append(f"a {_fmt_liters(disp)} L engine")
    if has_cyl:
        parts.append(f"{cyl} cylinder{'s' if cyl != 1 else ''}")
    if powertrain == BEV and parts:
        out.append(
            Signal(
                "ev_with_combustion_engine",
                REVIEW,
                "consistency",
                True,
                "Electric powertrain, but the listing also states " + " and ".join(parts),
            )
        )
    elif powertrain == BEV_TEXT_CONFLICT and parts:
        wording = find_hybrid_wording(
            fx.get("title"), fx.get("trim"), fx.get("model"), fx.get("description")
        )
        out.append(
            Signal(
                "ev_powertrain_unconfirmed",
                REVIEW,
                "consistency",
                False,
                f"Fuel / engine type says Electric and the listing states {' and '.join(parts)}; the "
                f"seller's text mentions \"{wording}\". Confirm the real powertrain",
            )
        )
    if powertrain != BEV:
        # 2. Engine figures that cannot be real for any road vehicle.
        if dstatus == "invalid" or (has_disp and not MIN_DISPLACEMENT_L <= disp <= MAX_DISPLACEMENT_L):
            out.append(
                Signal(
                    "engine_displacement_out_of_range",
                    REVIEW,
                    "consistency",
                    False,
                    f"Engine size {disp:g} L is outside {MIN_DISPLACEMENT_L:g}-{MAX_DISPLACEMENT_L:g} L",
                )
            )
        if cstatus == "invalid" or (has_cyl and cyl > MAX_CYLINDERS):
            out.append(
                Signal(
                    "cylinder_count_out_of_range",
                    REVIEW,
                    "consistency",
                    False,
                    f"{cyl} cylinders is outside 1-{MAX_CYLINDERS}",
                )
            )
        # 3. Displacement per cylinder outside what any engine has. Wide, generic
        #    bounds (not a per-model spec) and not applied to two-wheelers / ATVs.
        body = _token(fx.get("body_type"))
        if (
            has_disp
            and has_cyl
            and MIN_DISPLACEMENT_L <= disp <= MAX_DISPLACEMENT_L
            and 1 <= cyl <= MAX_CYLINDERS
            and body not in _SMALL_ENGINE_BODIES
        ):
            per_cyl = disp / cyl
            lo = float(s.get("min_liters_per_cylinder", 0.15))
            hi = float(s.get("max_liters_per_cylinder", 3.0))
            if per_cyl < lo or per_cyl > hi:
                out.append(
                    Signal(
                        "engine_displacement_cylinders_mismatch",
                        REVIEW,
                        "consistency",
                        False,
                        f"{_fmt_liters(disp)} L with {cyl} cylinders is {per_cyl:.2f} L per cylinder "
                        f"(expected {lo:g}-{hi:g})",
                    )
                )

    # 4. Soft signal: far more kilometres than a vehicle of this model year can
    #    plausibly have covered. Never applied to a vehicle listed as New (the
    #    New-car rules cover that) and never to old / low-mileage vehicles.
    year = _to_int(fx.get("year"))
    km = _mileage_km(fx.get("mileage"))
    per_year = float(s.get("max_annual_mileage_km", 40_000))
    if (
        per_year > 0
        and km is not None
        and km > 0
        and year is not None
        and int(s.get("min_year", 1950)) <= year <= current_year + 1
        and normalize_condition(fx.get("condition")) != "new"
    ):
        # A model year starts before its calendar year: a 2026 model can
        # already have been driven for about a year.
        years = max(current_year - year + 1, 1)
        ceiling = per_year * years
        if km > ceiling:
            out.append(
                Signal(
                    "high_mileage_for_year",
                    REVIEW,
                    "consistency",
                    False,
                    f"{km:,} km on a {year} model; a vehicle of this age normally has at most "
                    f"about {int(ceiling):,} km ({int(per_year):,} km/year over {years} "
                    f"year{'s' if years != 1 else ''})",
                )
            )
    return out


def check_text(f: Facts, s: dict) -> list[Signal]:
    out: list[Signal] = []
    text = _clean(f.fields.get("description"))
    # The title is public text too (and is not necessarily derived from the
    # vehicle fields), so the pattern checks cover it as well.
    scan = f"{_clean(f.fields.get('title'))}\n{text}"
    if _SCAM.search(scan):
        out.append(Signal("scam_language", REVIEW, "text", True))
    if _PROHIBITED.search(scan):
        out.append(Signal("prohibited_content", REVIEW, "text", True))
    if _NON_CAR.search(scan):
        out.append(Signal("non_car_content", REVIEW, "text", True))
    if not text:
        return out
    if _REPEAT_CHAR.search(text):
        out.append(Signal("repeated_characters", REVIEW, "text", True))
    letters = [c for c in text if c.isalpha()]
    if len(letters) >= 30:
        upper = sum(1 for c in letters if c.isupper() and c.isascii())
        ascii_letters = sum(1 for c in letters if c.isascii())
        if ascii_letters >= 30 and upper / ascii_letters > 0.7:
            out.append(Signal("excessive_caps", REVIEW, "text", False))
    words = normalize_text(text).split()
    if len(words) >= 20:
        top = max((words.count(w) for w in set(words)), default=0)
        if top / len(words) > 0.3:
            out.append(Signal("repetitive_text", REVIEW, "text", True))
    if len(text) > 5000:
        out.append(Signal("description_too_long", REVIEW, "text", False))
    if s.get("flag_contact_in_description", True) and (
        _URL.search(text) or _EMAIL.search(text) or _PHONE.search(text)
    ):
        out.append(Signal("contact_in_description", REVIEW, "text", False))
    return out


def check_media(f: Facts, s: dict) -> list[Signal]:
    m = f.media
    out: list[Signal] = []
    in_flight = int(m.get("in_flight") or 0)
    failed = int(m.get("failed") or 0)
    media_status = m.get("media_status")
    if in_flight > 0 or media_status == "processing":
        out.append(Signal("media_processing", HOLD, "media", False, str(in_flight)))
    if failed > 0 or media_status == "failed":
        out.append(Signal("media_failed", HOLD, "media", False, str(failed)))
    if out:
        return out

    images = [i for i in m.get("images", []) if (i.get("kind") or "listing") != "damage"]
    all_images = m.get("images", [])
    min_photos = int(s.get("min_photos", 1))
    if len(images) < min_photos:
        out.append(Signal("too_few_photos", REVIEW, "media", False, f"{len(images)}<{min_photos}"))
    if any(not i.get("url") for i in all_images):
        out.append(Signal("media_missing", REVIEW, "media", True, "empty url"))
    if int(m.get("unapproved_video_count") or 0) > 0:
        # No provider inspects video content, so unreviewed video is never
        # auto-approved (it would be public, unverified media).
        out.append(Signal("videos_not_inspected", REVIEW, "media", False, str(m["unapproved_video_count"])))
    if images:
        primaries = [i for i in images if i.get("is_primary")]
        if len(primaries) != 1:
            out.append(Signal("cover_invalid", REVIEW, "media", True, f"primaries={len(primaries)}"))
        # Declared cover (server-owned choice) must be the stored cover.
        by_source = {i.get("source_media_id"): i for i in all_images if i.get("source_media_id")}
        for it in m.get("items", []):
            if it.get("kind") != "image" or it.get("status") != "attached":
                continue
            img = by_source.get(it.get("client_media_id"))
            if img is None:
                out.append(Signal("media_missing", REVIEW, "media", True, "attached item without photo"))
                break
            if it.get("is_cover") and not img.get("is_primary"):
                out.append(Signal("cover_mismatch", REVIEW, "media", True, None))
                break
    min_side = int(s.get("min_image_side_px", 0))
    if min_side:
        for i in images:
            w, h = i.get("width"), i.get("height")
            if w and h and min(int(w), int(h)) < min_side:
                out.append(Signal("low_resolution", REVIEW, "media", False, f"{w}x{h}"))
                break
    return out


def check_duplicates(f: Facts, s: dict) -> list[Signal]:
    d = f.duplicates or {}
    out: list[Signal] = []
    if d.get("own_similar"):
        out.append(Signal("duplicate_listing", REVIEW, "duplicates", True, str(d["own_similar"])))
    if d.get("own_same_description"):
        out.append(Signal("repeated_description", REVIEW, "duplicates", True, str(d["own_same_description"])))
    if d.get("vin_own"):
        out.append(Signal("vin_reused_own", REVIEW, "duplicates", True, None))
    if d.get("vin_other_seller"):
        out.append(Signal("vin_other_seller", REVIEW, "duplicates", True, None))
    if int(d.get("recent_24h") or 0) > int(s.get("max_listings_per_24h", 5)):
        out.append(Signal("high_posting_rate", REVIEW, "duplicates", True, str(d.get("recent_24h"))))
    return out


def check_seller(f: Facts, s: dict) -> list[Signal]:
    sl = f.seller
    out: list[Signal] = []
    if not sl.get("exists"):
        return [Signal("seller_missing", REVIEW, "seller", True)]
    if not sl.get("active"):
        out.append(Signal("seller_inactive", REVIEW, "seller", True))
    if not sl.get("phone_verified"):
        out.append(Signal("seller_not_verified", REVIEW, "seller", False))
    if int(sl.get("open_reports") or 0) > 0:
        out.append(Signal("seller_open_reports", REVIEW, "seller", True, str(sl["open_reports"])))
    if int(sl.get("admin_rejections") or 0) > 0 or int(sl.get("hidden_listings") or 0) > 0:
        out.append(
            Signal(
                "seller_abuse_history",
                REVIEW,
                "seller",
                True,
                f"rejected={sl.get('admin_rejections', 0)} hidden={sl.get('hidden_listings', 0)}",
            )
        )
    trusted = (s.get("dealers_count_as_trusted", True) and sl.get("dealer_approved")) or (
        int(sl.get("prior_approved") or 0) >= int(s.get("min_seller_prior_approved", 1))
    )
    if not trusted:
        out.append(Signal("seller_unproven", REVIEW, "seller", False))
    if sl.get("manual_only"):
        out.append(Signal("pinned_manual_review", REVIEW, "seller", False))
    return out


def check_payment(f: Facts, s: dict) -> list[Signal]:
    """Payment is never assumed. ``f.payment`` comes from ``payment.assess``
    (server-side verifier only). Missing facts are treated as unverified when
    the deployment requires payment."""
    if f.subject_type != "listing" or not s.get("listing_payment_required"):
        return []
    p = f.payment or {}
    if p.get("status") == "verified":
        # Audit trail only (INFO never blocks): what proved payment / allowance.
        return [Signal("payment_verified", INFO, "payment", False, f"{p.get('kind')}:{p.get('reference')}")]
    if p.get("status") == "error":
        return [Signal("payment_check_unavailable", HOLD, "payment", False, p.get("reason"))]
    return [Signal("payment_unverifiable", REVIEW, "payment", False, p.get("reason"))]


def check_revision(f: Facts, s: dict) -> list[Signal]:
    r = f.revision
    if f.subject_type != "revision" or not r:
        return []
    out: list[Signal] = []
    changed = set(r.get("changed_fields") or [])
    if not changed and not r.get("new_media"):
        out.append(Signal("no_effective_changes", REVIEW, "revision", False))
    identity = changed & {"brand", "model", "year", "vin"}
    if identity:
        out.append(Signal("identity_changed", REVIEW, "revision", True, ",".join(sorted(identity))))
    old, new = r.get("old_price"), r.get("new_price")
    if old and new is not None and old > 0:
        pct = abs(new - old) / old * 100
        if pct > float(s.get("price_change_review_pct", 50)):
            out.append(Signal("large_price_change", REVIEW, "revision", True, f"{pct:.0f}%"))
    return out


def ai_signals(ai: dict | None, s: dict) -> list[Signal]:
    """Translate an advisory AI result into signals. AI is never proof of
    anything: a clean result only *fails to add a reason* to look closer, an
    unavailable service is HOLD (never an approval), and a clean result that
    did not cover EVERY image that needed checking (cover included) is not
    clean at all.

    Only these statuses can leave the list empty (= no objection):
    ``ok`` with full coverage, ``not_needed`` (nothing new to judge) and -- when
    the operator explicitly allows rules-only approval -- ``disabled``."""
    ai = ai or {}
    status = ai.get("status", "disabled")
    required = s.get("ai_required_effective", s.get("require_ai_for_auto_approve", True))
    if status == "disabled":
        return [Signal("ai_not_configured", REVIEW, "ai", False)] if required else []
    if status == "unavailable":
        return [Signal("ai_unavailable", HOLD, "ai", False, ai.get("error"))]
    if status == "flagged":
        flags = sorted(set(ai.get("text_flags", []) + ai.get("image_flags", [])))
        return [Signal("ai_flagged", REVIEW, "ai", True, ",".join(flags)[:120] or None)]
    if status == "skipped":
        return [Signal("ai_not_run", REVIEW, "ai", False, ai.get("reason"))]
    if status == "not_needed":
        return []
    if status == "uncertain":
        if ai.get("error") == "too_many_images":
            return [
                Signal(
                    "ai_image_coverage_incomplete",
                    REVIEW,
                    "ai",
                    False,
                    f"{ai.get('images_expected', '?')} photos exceed the automatic limit",
                )
            ]
        return [Signal("ai_uncertain", REVIEW, "ai", False, ai.get("error"))]
    if status != "ok":
        return [Signal("ai_uncertain", REVIEW, "ai", False, "unknown_status")]
    out: list[Signal] = []
    expected = int(ai.get("images_expected") or 0)
    checked = int(ai.get("images_checked") or 0)
    if checked < expected:
        out.append(
            Signal("ai_image_coverage_incomplete", REVIEW, "ai", False, f"{checked}/{expected} photos inspected")
        )
    if ai.get("cover_expected") and not ai.get("cover_checked"):
        out.append(Signal("ai_cover_not_checked", REVIEW, "ai", False))
    conf = ai.get("confidence")
    if conf is not None and conf < float((s.get("ai") or {}).get("min_confidence", 0.7)):
        out.append(Signal("ai_low_confidence", REVIEW, "ai", False, f"{conf:.2f}"))
    return out

# ---------------------------------------------------------------------------
# Orchestration of the deterministic part
# ---------------------------------------------------------------------------

CHECK_NAMES = (
    "required_fields",
    "values",
    "consistency",
    "text",
    "media",
    "duplicates",
    "seller",
    "payment",
    "revision",
    "ai",
)


def run_rules(f: Facts, s: dict, current_year: int) -> list[Signal]:
    signals: list[Signal] = []
    signals += check_required_fields(f, s)
    signals += check_values(f, s, current_year)
    signals += check_consistency(f, s, current_year)
    signals += check_text(f, s)
    signals += check_media(f, s)
    signals += check_duplicates(f, s)
    signals += check_seller(f, s)
    signals += check_payment(f, s)
    signals += check_revision(f, s)
    return signals


def checks_map(signals: list[Signal], ran: tuple[str, ...] = CHECK_NAMES) -> dict[str, str]:
    """pass / fail / hold per check (a check that never ran is 'skipped')."""
    out = {name: "skipped" for name in CHECK_NAMES}
    for name in ran:
        out[name] = "pass"
    for sg in signals:
        if sg.level == HOLD:
            out[sg.check] = "hold"
        elif sg.level == REVIEW and out.get(sg.check) != "hold":
            out[sg.check] = "fail"
    return out


def decide(signals: list[Signal]) -> str:
    """HOLD beats NEEDS_REVIEW beats AUTO_APPROVE. AUTO_APPROVE only when no
    hold/review signal remains."""
    if any(sg.level == HOLD for sg in signals):
        return "HOLD"
    if any(sg.level == REVIEW for sg in signals):
        return "NEEDS_REVIEW"
    return "AUTO_APPROVE"
