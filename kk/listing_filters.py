"""
Match a Car row against home-feed filter JSON (same keys as the Flutter app).
"""
from __future__ import annotations

from typing import Any

from .models import Car

_ALLOWED_REGION_SPECS = frozenset(
    {"us", "gcc", "iraq", "canada", "eu", "cn", "korea", "ru", "iran"}
)
_ALLOWED_PLATE_TYPES = frozenset({"private", "temporary", "commercial", "taxi"})


def _safe_int(val, default=None):
    if val is None or val == "":
        return default
    try:
        return int(val)
    except (TypeError, ValueError):
        try:
            return int(float(val))
        except (TypeError, ValueError):
            return default


def _safe_float(val, default=None):
    if val is None or val == "":
        return default
    try:
        return float(val)
    except (TypeError, ValueError):
        return default


def _norm_str(val) -> str:
    return str(val or "").strip().lower()


def _ilike_match(haystack: str | None, needle: str) -> bool:
    if not needle:
        return True
    h = (haystack or "").lower()
    n = needle.lower().replace("-", " ").strip()
    return n in h or n.replace(" ", "-") in h.replace(" ", "-")


def _multi_values(val) -> list[str]:
    if val is None or val == "":
        return []
    return [
        part.strip().lower()
        for part in str(val).split(",")
        if part.strip() and part.strip().lower() not in ("any", "")
    ]


def car_matches_filters(car: Car, filters: dict[str, Any] | None) -> bool:
    """Return True if car satisfies all non-empty filters."""
    if not filters or not isinstance(filters, dict):
        return True

    brands = _multi_values(filters.get("brand"))
    if brands:
        if not any(_ilike_match(car.brand, brand) for brand in brands):
            return False

    model = _norm_str(filters.get("model"))
    if model and not _ilike_match(car.model, model):
        return False

    trim = _norm_str(filters.get("trim"))
    # A-04: "any" is the only sentinel meaning "no trim filter". "Base" is a
    # real, selectable trim (lib/features/home/home_page.dart trims list) and
    # the default trim assigned to listings with no explicit trim
    # (lib/features/sell/sell_listing_payload.dart) -- it must be matched
    # like any other trim value, exactly like kk/routes/cars.py's
    # `Car.trim.ilike(f"%{trim}%", ...)`, which has no "base" special-case.
    if trim and trim != "any" and not _ilike_match(getattr(car, "trim", None), trim):
        return False

    year_min = _safe_int(filters.get("min_year") or filters.get("year_min"))
    year_max = _safe_int(filters.get("max_year") or filters.get("year_max"))
    if year_min is not None and (car.year or 0) < year_min:
        return False
    if year_max is not None and (car.year or 0) > year_max:
        return False

    price_min = _safe_float(filters.get("min_price") or filters.get("price_min"))
    price_max = _safe_float(filters.get("max_price") or filters.get("price_max"))
    if price_min is not None and (car.price or 0) < price_min:
        return False
    if price_max is not None and (car.price or 0) > price_max:
        return False

    mile_min = _safe_int(filters.get("min_mileage"))
    mile_max = _safe_int(filters.get("max_mileage"))
    if mile_min is not None and (car.mileage or 0) < mile_min:
        return False
    if mile_max is not None and (car.mileage or 0) > mile_max:
        return False

    city = _norm_str(filters.get("city") or filters.get("location"))
    if city and not _ilike_match(car.location, city):
        return False

    condition = _norm_str(filters.get("condition"))
    if condition and condition not in ("any", "") and _norm_str(car.condition) != condition:
        return False

    transmission = _norm_str(filters.get("transmission"))
    if transmission and transmission not in ("any", "") and _norm_str(car.transmission) != transmission:
        return False

    body_types = _multi_values(filters.get("body_type"))
    if body_types:
        car_body = _norm_str(car.body_type)
        if car_body not in body_types:
            return False

    drive_types = _multi_values(filters.get("drive_type"))
    if drive_types:
        if not any(_ilike_match(car.drive_type, dt) for dt in drive_types):
            return False

    # A-04: fuel_type and engine_type are separate filter/column concepts in
    # kk/routes/cars.py -- they must NOT be aliased with an `or` fallback.
    # Mirrors the exact current SQL semantics (cars.py's `get_cars()`), which
    # this fix intentionally preserves as-is (including its asymmetry
    # between the two fields) rather than changing:
    #   - fuel_type: comma-separated multi-value, case-insensitive EXACT
    #     match (`Car.fuel_type.ilike(ft)` with no `%` wildcards) against
    #     `car.fuel_type` only.
    #   - engine_type: single-value, case-SENSITIVE exact match
    #     (`Car.engine_type == engine_type`, no lowercasing/splitting)
    #     against `car.engine_type` only.
    # If both are supplied, both conditions must independently pass (SQL
    # applies both `if engine_type:` / `if fuel_type:` filters as separate,
    # AND-ed `query.filter(...)` calls).
    fuel_types = _multi_values(filters.get("fuel_type"))
    if fuel_types:
        car_fuel_type = _norm_str(getattr(car, "fuel_type", None))
        if car_fuel_type not in fuel_types:
            return False

    engine_type = filters.get("engine_type")
    if engine_type:
        if str(getattr(car, "engine_type", None) or "") != str(engine_type):
            return False

    color = _norm_str(filters.get("color"))
    if color and color not in ("any", "") and not _ilike_match(car.color, color):
        return False

    seating = _safe_int(filters.get("seating"))
    if seating is not None and getattr(car, "seating", None) != seating:
        return False

    cylinder_count = _safe_int(filters.get("cylinder_count"))
    if cylinder_count is not None and getattr(car, "cylinder_count", None) != cylinder_count:
        return False

    engine_size = filters.get("engine_size")
    if engine_size not in (None, ""):
        target = _safe_float(engine_size)
        if target is not None and getattr(car, "engine_size", None) is not None:
            if abs(float(car.engine_size) - target) > 0.15:
                return False

    region_specs = _norm_str(filters.get("region_specs"))
    if region_specs and region_specs in _ALLOWED_REGION_SPECS:
        if _norm_str(getattr(car, "region_specs", None)) != region_specs:
            return False

    plate_type = _norm_str(filters.get("plate_type") or filters.get("plateType"))
    if plate_type and plate_type in _ALLOWED_PLATE_TYPES:
        if _norm_str(getattr(car, "plate_type", None)) != plate_type:
            return False

    plate_city = _norm_str(filters.get("plate_city") or filters.get("plateCity"))
    if plate_city and not _ilike_match(getattr(car, "plate_city", None), plate_city):
        return False

    title_status = _norm_str(filters.get("title_status"))
    if title_status and title_status not in ("any", ""):
        if _norm_str(getattr(car, "title_status", None)) != title_status:
            return False

    damaged_parts = _safe_int(filters.get("damaged_parts"))
    if damaged_parts is not None and title_status == "damaged":
        if getattr(car, "damaged_parts", None) != damaged_parts:
            return False

    return True


def summarize_filters(filters: dict[str, Any] | None, *, max_len: int = 80) -> str:
    """Short human-readable summary for push notification body."""
    if not filters or not isinstance(filters, dict):
        return "New listing"
    parts: list[str] = []
    for key in ("brand", "model", "city"):
        val = filters.get(key)
        if val:
            parts.append(str(val).replace("-", " ").title())
    if not parts:
        return "New listing matches your search"
    text = " ".join(parts)
    if len(text) > max_len:
        return text[: max_len - 1] + "…"
    return text
