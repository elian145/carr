from __future__ import annotations

import os
import time
from datetime import datetime

from flask import Blueprint, current_app, jsonify, request
from flask_jwt_extended import jwt_required, verify_jwt_in_request
from ..security import rate_limit
from sqlalchemy import func, select, update
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import joinedload, selectinload

from ..auth import get_current_user, log_user_action
from ..favorites_cleanup import remove_listing_from_all_favorites
from ..view_history import remove_listing_from_all_view_history
from ..models import Car, ListingReport, User, db, user_viewed_listings
from ..retention_dispatch import dispatch_price_drop_alerts, dispatch_saved_search_alerts
from ..time_utils import utcnow
from .media import _normalize_car_image_kind, _pick_primary_listing_url

bp = Blueprint("cars", __name__)


MAX_PER_PAGE = int(os.environ.get("MAX_PER_PAGE", "50"))
MAX_PER_PAGE = max(1, min(MAX_PER_PAGE, 200))

_ALLOWED_REGION_SPECS = frozenset(
    {"us", "gcc", "iraq", "canada", "eu", "cn", "korea", "ru", "iran"}
)

_ALLOWED_PLATE_TYPES = frozenset({"private", "temporary", "commercial", "taxi"})
_ALLOWED_LISTING_STATUSES = frozenset({"active", "sold"})

_VIN_ALREADY_EXISTS_MESSAGE = (
    "This VIN is already used on another listing. "
    "Use a different VIN or edit your existing listing."
)


def _normalize_vin(val) -> str | None:
    v = (val if isinstance(val, str) else str(val or "")).strip().upper()
    return v if v else None


def _vin_used_by_other_listing(vin: str, *, exclude_car_id: int | None = None) -> bool:
    q = Car.query.filter(func.upper(Car.vin) == vin.upper())
    if exclude_car_id is not None:
        q = q.filter(Car.id != exclude_car_id)
    return q.first() is not None


def _vin_conflict_response():
    return (
        jsonify(
            {
                "message": _VIN_ALREADY_EXISTS_MESSAGE,
                "errors": {"vin": "already_exists"},
            }
        ),
        409,
    )


def _listing_db_error_response(exc, *, action: str):
    db.session.rollback()
    err = str(exc).lower()
    if isinstance(exc, IntegrityError) and (
        "car_vin_key" in err
        or ("unique" in err and "vin" in err and "duplicate" in err)
    ):
        return _vin_conflict_response()
    current_app.logger.exception("%s failed: %s", action, exc)
    return jsonify({"message": f"Failed to {action}"}), 500


def _public_listings_filter(query):
    """Browseable listings only (not soft-deleted). Sold listings remain visible."""
    return query.filter(Car.is_active.is_(True))

# Best-effort anonymous view cooldown (in-memory, per process)
_anon_view_cache: dict[tuple[str, int], float] = {}
_ANON_VIEW_COOLDOWN_S = 600.0  # 10 minutes
_ANON_VIEW_CACHE_MAX = 50_000


def _clamp_pagination(page: int, per_page: int) -> tuple[int, int]:
    try:
        p = int(page)
    except Exception:
        p = 1
    try:
        pp = int(per_page)
    except Exception:
        pp = 20
    if p < 1:
        p = 1
    if pp < 1:
        pp = 1
    if pp > MAX_PER_PAGE:
        pp = MAX_PER_PAGE
    return p, pp


def _client_ip() -> str:
    xff = (request.headers.get("X-Forwarded-For") or "").split(",")[0].strip()
    return xff or (request.remote_addr or "anon")


def _increment_views_best_effort(car: Car, current_user: User | None) -> None:
    """
    Reduce write-amplification:
    - Authenticated users: increment at most once per user per listing (via user_viewed_listings).
    - Anonymous users: increment at most once per IP per listing per cooldown window (best-effort).
    """
    try:
        if not car or not getattr(car, "id", None):
            return
        now = utcnow()
        if current_user:
            from ..view_history import record_user_listing_view

            _, is_first_view = record_user_listing_view(
                current_user, car.public_id or str(car.id)
            )
            if not is_first_view:
                return
        else:
            ip = _client_ip()
            key = (ip, int(car.id))
            ts = _anon_view_cache.get(key)
            now_ts = time.time()
            if ts is not None and (now_ts - ts) < _ANON_VIEW_COOLDOWN_S:
                return
            _anon_view_cache[key] = now_ts
            if len(_anon_view_cache) > _ANON_VIEW_CACHE_MAX:
                for k in list(_anon_view_cache.keys())[: int(_ANON_VIEW_CACHE_MAX * 0.1)]:
                    _anon_view_cache.pop(k, None)

        db.session.execute(update(Car).where(Car.id == car.id).values(views_count=Car.views_count + 1))
        db.session.commit()
    except Exception:
        try:
            db.session.rollback()
        except Exception:
            pass


def _static_exists(rel: str) -> bool:
    try:
        if not rel:
            return False
        norm = rel.lstrip("/").replace("\\", "/")
        static_root = os.path.join(current_app.root_path, "static")
        repo_static = os.path.abspath(os.path.join(current_app.root_path, "..", "static"))
        for root in (static_root, repo_static):
            p = os.path.join(root, norm)
            if os.path.isfile(p):
                return True
        return False
    except Exception:
        return False


def _resolve_rel(rel: str) -> str:
    """
    Resolve stored image path to an existing file.
    If DB stored 'uploads/<name>', try 'uploads/car_photos/<name>' as a fallback.
    """
    try:
        if not rel:
            return ""
        # Cloud / external URLs are already absolute; keep as-is.
        if rel.startswith("http://") or rel.startswith("https://"):
            return rel
        norm = rel.lstrip("/").replace("\\", "/")
        if _static_exists(norm):
            return norm
        base = os.path.basename(norm)
        alt = os.path.join("uploads", "car_photos", base).replace("\\", "/")
        if _static_exists(alt):
            return alt
        return ""
    except Exception:
        return ""


def _with_media_compat(car: Car) -> dict:
    d = car.to_dict()
    # Keep per-image metadata (especially `kind`: listing vs damage). Plain string
    # lists made every photo look like a normal gallery image on the client.
    image_objs: list[dict] = []
    for img in car.images or []:
        rel = getattr(img, "image_url", "") or ""
        resolved = _resolve_rel(rel)
        if not resolved:
            continue
        kind = _normalize_car_image_kind(getattr(img, "kind", None))
        image_objs.append(
            {
                "id": img.id,
                "image_url": resolved,
                "is_primary": bool(getattr(img, "is_primary", False)),
                "order": int(getattr(img, "order", 0) or 0),
                "kind": kind,
            }
        )

    raw_primary = _pick_primary_listing_url(car)
    primary_rel = ""
    if raw_primary:
        primary_rel = _resolve_rel(raw_primary) or raw_primary
    if not primary_rel:
        for row in image_objs:
            if row.get("kind") == "listing":
                primary_rel = row["image_url"]
                break
    if not primary_rel and image_objs:
        primary_rel = image_objs[0]["image_url"]
    if not primary_rel and _static_exists("uploads/car_photos/placeholder.jpg"):
        primary_rel = "uploads/car_photos/placeholder.jpg"
    d["image_url"] = primary_rel
    d["images"] = image_objs
    # Match list endpoints: expose plain relative paths so mobile clients can build /static/... URLs.
    d["videos"] = [v.video_url for v in car.videos] if car.videos else []
    return d


def _safe_int(val, default=None):
    """Parse int from request arg; return default if missing or invalid."""
    if val is None or (isinstance(val, str) and val.strip() == ""):
        return default
    try:
        return int(float(val))
    except (TypeError, ValueError):
        return default


def _safe_float(val, default=None):
    """Parse float from request arg; return default if missing or invalid."""
    if val is None or (isinstance(val, str) and val.strip() == ""):
        return default
    try:
        return float(val)
    except (TypeError, ValueError):
        return default


def _leading_float(val):
    """Parse float values like '2.0', '2.0 T', '2.0L' (leading token)."""
    if val is None:
        return None
    if isinstance(val, (int, float)):
        try:
            return float(val)
        except Exception:
            return None
    s = str(val).strip()
    if not s:
        return None
    try:
        return float(s)
    except Exception:
        import re

        m = re.match(r"^(\d+(?:\.\d+)?)", s)
        if not m:
            return None
        try:
            return float(m.group(1))
        except Exception:
            return None


@bp.route("/api/cars", methods=["GET"])
def get_cars():
    """Get all cars with filtering and pagination."""
    try:
        page, per_page = _clamp_pagination(
            request.args.get("page", 1, type=int),
            request.args.get("per_page", 20, type=int),
        )

        # Query params: support both app names (min_* / max_*, city) and legacy (year_min, etc.)
        brand = request.args.get("brand")
        model = request.args.get("model")
        year_min = _safe_int(request.args.get("year_min")) or _safe_int(request.args.get("min_year"))
        year_max = _safe_int(request.args.get("year_max")) or _safe_int(request.args.get("max_year"))
        price_min = _safe_float(request.args.get("price_min")) or _safe_float(request.args.get("min_price"))
        price_max = _safe_float(request.args.get("price_max")) or _safe_float(request.args.get("max_price"))
        min_mileage = _safe_int(request.args.get("min_mileage"))
        max_mileage = _safe_int(request.args.get("max_mileage"))
        location = request.args.get("location") or request.args.get("city")
        condition = request.args.get("condition")
        body_type = request.args.get("body_type")
        transmission = request.args.get("transmission")
        drive_type = (request.args.get("drive_type") or "").strip().lower() or None
        engine_type = request.args.get("engine_type")
        # More filters (from "More Filters" in app)
        seating = _safe_int(request.args.get("seating"))
        cylinder_count = _safe_int(request.args.get("cylinder_count"))
        engine_size = _safe_float(request.args.get("engine_size"))
        fuel_type = (request.args.get("fuel_type") or "").strip().lower() or None
        color = (request.args.get("color") or "").strip().lower() or None
        trim = request.args.get("trim")
        title_status = (request.args.get("title_status") or "").strip().lower() or None
        region_specs_raw = (request.args.get("region_specs") or "").strip().lower()
        region_specs = region_specs_raw if region_specs_raw in _ALLOWED_REGION_SPECS else None
        plate_type_raw = (request.args.get("plate_type") or request.args.get("plateType") or "").strip().lower()
        plate_type = plate_type_raw if plate_type_raw in _ALLOWED_PLATE_TYPES else None
        plate_city = (request.args.get("plate_city") or request.args.get("plateCity") or "").strip() or None

        query = _public_listings_filter(
            Car.query.options(
                selectinload(Car.images),
                selectinload(Car.videos),
                joinedload(Car.seller),
            )
        )

        if brand:
            query = query.filter(Car.brand.ilike(f"%{brand}%"))
        if model:
            query = query.filter(Car.model.ilike(f"%{model}%"))
        if trim:
            query = query.filter(Car.trim.ilike(f"%{trim}%"))
        if year_min:
            query = query.filter(Car.year >= year_min)
        if year_max:
            query = query.filter(Car.year <= year_max)
        if price_min is not None:
            query = query.filter(Car.price >= price_min)
        if price_max is not None:
            query = query.filter(Car.price <= price_max)
        if min_mileage is not None:
            query = query.filter(Car.mileage >= min_mileage)
        if max_mileage is not None:
            query = query.filter(Car.mileage <= max_mileage)
        if location:
            query = query.filter(Car.location.ilike(f"%{location}%"))
        if condition:
            query = query.filter(Car.condition == condition)
        if body_type:
            query = query.filter(Car.body_type == body_type)
        if transmission:
            query = query.filter(Car.transmission == transmission)
        if drive_type:
            query = query.filter(Car.drive_type.ilike(drive_type))
        if engine_type:
            query = query.filter(Car.engine_type == engine_type)
        if fuel_type:
            query = query.filter(Car.fuel_type.ilike(fuel_type))
        if seating is not None:
            query = query.filter(Car.seating == seating)
        if cylinder_count is not None:
            query = query.filter(Car.cylinder_count == cylinder_count)
        if engine_size is not None:
            query = query.filter(Car.engine_size == engine_size)
        if color:
            query = query.filter(Car.color.ilike(f"%{color}%"))
        if title_status:
            query = query.filter(Car.title_status == title_status)
        if region_specs:
            query = query.filter(Car.region_specs == region_specs)
        if plate_type:
            query = query.filter(Car.plate_type == plate_type)
        if plate_city:
            query = query.filter(Car.plate_city.ilike(f"%{plate_city}%"))

        sort_by = (request.args.get("sort_by") or "").strip().lower()
        if sort_by == "newest":
            query = query.order_by(Car.is_featured.desc(), Car.created_at.desc())
        elif sort_by == "price_asc":
            query = query.order_by(Car.is_featured.desc(), Car.price.asc(), Car.created_at.desc())
        elif sort_by == "price_desc":
            query = query.order_by(Car.is_featured.desc(), Car.price.desc(), Car.created_at.desc())
        elif sort_by == "year_desc":
            query = query.order_by(Car.is_featured.desc(), Car.year.desc(), Car.created_at.desc())
        elif sort_by == "year_asc":
            query = query.order_by(Car.is_featured.desc(), Car.year.asc(), Car.created_at.desc())
        elif sort_by == "mileage_asc":
            query = query.order_by(Car.is_featured.desc(), Car.mileage.asc(), Car.created_at.desc())
        elif sort_by == "mileage_desc":
            query = query.order_by(Car.is_featured.desc(), Car.mileage.desc(), Car.created_at.desc())
        else:
            query = query.order_by(Car.is_featured.desc(), Car.created_at.desc())

        pagination = query.paginate(page=page, per_page=per_page, error_out=False)
        cars = [_with_media_compat(c) for c in pagination.items]

        return (
            jsonify(
                {
                    "cars": cars,
                    "pagination": {
                        "page": page,
                        "per_page": per_page,
                        "total": pagination.total,
                        "pages": pagination.pages,
                        "has_next": pagination.has_next,
                        "has_prev": pagination.has_prev,
                    },
                }
            ),
            200,
        )
    except Exception as e:
        current_app.logger.exception("get_cars failed: %s", e)
        return jsonify({"message": f"Failed to get cars: {str(e)}"}), 500


@bp.route("/cars", methods=["GET"])
def get_cars_alias():
    """Compatibility alias: returns a bare list of cars, and supports ?id=<public_id>."""
    try:
        car_id = request.args.get("id")
        if car_id:
            car = None
            try:
                if str(car_id).isdigit():
                    car = (
                        Car.query.options(
                            selectinload(Car.images),
                            selectinload(Car.videos),
                            joinedload(Car.seller),
                        )
                        .filter_by(id=int(car_id), is_active=True)
                        .first()
                    )
            except Exception:
                pass
            if car is None:
                car = (
                    Car.query.options(
                        selectinload(Car.images),
                        selectinload(Car.videos),
                        joinedload(Car.seller),
                    )
                    .filter_by(public_id=car_id, is_active=True)
                    .first()
                )
            if not car:
                return jsonify({"message": "Car not found"}), 404
            d = _with_media_compat(car)
            # legacy client expects numeric id
            d["id"] = car.id
            d["videos"] = [v.video_url for v in car.videos] if car.videos else []
            if not d.get("title"):
                d["title"] = f"{(car.brand or '').title()} {(car.model or '').title()} {car.year or ''}".strip()
            return jsonify(d), 200

        page, per_page = _clamp_pagination(
            request.args.get("page", 1, type=int),
            request.args.get("per_page", 20, type=int),
        )

        brand = request.args.get("brand")
        model = request.args.get("model")
        year_min = request.args.get("year_min", type=int)
        year_max = request.args.get("year_max", type=int)
        price_min = request.args.get("price_min", type=float)
        price_max = request.args.get("price_max", type=float)
        location = request.args.get("location")
        condition = request.args.get("condition")
        body_type = request.args.get("body_type")
        transmission = request.args.get("transmission")
        drive_type = request.args.get("drive_type")
        engine_type = request.args.get("engine_type")

        query = _public_listings_filter(
            Car.query.options(
                selectinload(Car.images),
                selectinload(Car.videos),
                joinedload(Car.seller),
            )
        )
        if brand:
            query = query.filter(Car.brand.ilike(f"%{brand}%"))
        if model:
            query = query.filter(Car.model.ilike(f"%{model}%"))
        if year_min:
            query = query.filter(Car.year >= year_min)
        if year_max:
            query = query.filter(Car.year <= year_max)
        if price_min:
            query = query.filter(Car.price >= price_min)
        if price_max:
            query = query.filter(Car.price <= price_max)
        if location:
            query = query.filter(Car.location.ilike(f"%{location}%"))
        if condition:
            query = query.filter(Car.condition == condition)
        if body_type:
            query = query.filter(Car.body_type == body_type)
        if transmission:
            query = query.filter(Car.transmission == transmission)
        if drive_type:
            query = query.filter(Car.drive_type == drive_type)
        if engine_type:
            query = query.filter(Car.engine_type == engine_type)

        query = query.order_by(Car.is_featured.desc(), Car.created_at.desc())
        pagination = query.paginate(page=page, per_page=per_page, error_out=False)
        cars = []
        for c in pagination.items:
            d = _with_media_compat(c)
            d["id"] = c.id
            d["videos"] = [v.video_url for v in c.videos] if c.videos else []
            if not d.get("title"):
                d["title"] = f"{(c.brand or '').title()} {(c.model or '').title()} {c.year or ''}".strip()
            cars.append(d)
        return jsonify(cars), 200
    except Exception as e:
        current_app.logger.exception("get_cars_alias failed: %s", e)
        return jsonify({"message": f"Failed to get cars: {str(e)}"}), 500


@bp.route("/api/cars/<car_id>", methods=["GET"])
def get_car(car_id: str):
    """Get single car by ID (public_id or numeric db id)."""
    try:
        car = (
            Car.query.options(
                selectinload(Car.images),
                selectinload(Car.videos),
                joinedload(Car.seller),
            )
            .filter_by(public_id=car_id, is_active=True)
            .first()
        )
        if not car and str(car_id).isdigit():
            car = (
                Car.query.options(
                    selectinload(Car.images),
                    selectinload(Car.videos),
                    joinedload(Car.seller),
                )
                .filter_by(id=int(car_id), is_active=True)
                .first()
            )
        if not car:
            return jsonify({"message": "Car not found"}), 404

        current_user = None
        try:
            verify_jwt_in_request(optional=True)
            current_user = get_current_user()
        except Exception:
            current_user = None

        if current_user:
            log_user_action(current_user, "view_listing", "car", car.public_id)

        _increment_views_best_effort(car, current_user)

        car_dict = _with_media_compat(car)
        if not car_dict.get("city") and car_dict.get("location"):
            car_dict["city"] = car_dict["location"]
        return jsonify({"car": car_dict}), 200
    except Exception as e:
        current_app.logger.exception("get_car failed: %s", e)
        return jsonify({"message": "Failed to get car"}), 500


@bp.route("/api/cars", methods=["POST"])
@jwt_required()
def create_car():
    """Create new car listing."""
    try:
        current_user = get_current_user()
        if not current_user:
            return jsonify({"message": "User not found"}), 404

        raw = request.get_json(silent=True) or {}

        def _s(val, default=""):
            return (val if isinstance(val, str) else str(val or "")).strip() or default

        def _i(val, default=0):
            try:
                return int(val)
            except Exception:
                try:
                    return int(float(val))
                except Exception:
                    return default

        def _f(val, default=0.0):
            try:
                return float(val)
            except Exception:
                return default

        def _leading_float(val):
            """Parse float values like '2.0', '2.0 T', '2.0L' (leading token)."""
            if val is None:
                return None
            if isinstance(val, (int, float)):
                try:
                    return float(val)
                except Exception:
                    return None
            s = str(val).strip()
            if not s:
                return None
            try:
                return float(s)
            except Exception:
                import re

                m = re.match(r"^(\d+(?:\.\d+)?)", s)
                if not m:
                    return None
                try:
                    return float(m.group(1))
                except Exception:
                    return None

        brand = _s(raw.get("brand"), "unknown")
        model = _s(raw.get("model"), "")
        year = _i(raw.get("year"), 0)
        mileage = _i(raw.get("mileage"), 0)
        engine_type = _s(raw.get("engine_type"), "gasoline")
        fuel_type = _s(raw.get("fuel_type"), engine_type or "gasoline")
        transmission = _s(raw.get("transmission"), "automatic")
        drive_type = _s(raw.get("drive_type"), "fwd")
        condition = _s(raw.get("condition"), "used")
        body_type = _s(raw.get("body_type"), "sedan")
        price = _f(raw.get("price"), 0.0)
        location = _s(raw.get("location"), "")
        description = _s(raw.get("description"), None) or None
        color = _s(raw.get("color"), "white")
        fuel_economy = _s(raw.get("fuel_economy"), None) or None
        vin = _normalize_vin(_s(raw.get("vin"), None) or None)
        currency = _s(raw.get("currency"), "USD")[:3] or "USD"
        trim = _s(raw.get("trim"), "base")
        seating = _i(raw.get("seating"), 5)
        status = _s(raw.get("status"), "active")
        title_status_raw = _s(raw.get("title_status"), "clean").lower()
        # Persist title status submitted by sell flows; default to clean for unknown values.
        title_status = title_status_raw if title_status_raw in {"clean", "damaged"} else "clean"
        damaged_parts_raw = raw.get("damaged_parts")
        damaged_parts_val = None
        if title_status == "damaged" and damaged_parts_raw not in (None, ""):
            damaged_parts_val = _safe_int(damaged_parts_raw)
            if damaged_parts_val is not None and damaged_parts_val < 1:
                damaged_parts_val = None
        engine_size = raw.get("engine_size")
        engine_size_val = _leading_float(engine_size) if engine_size not in (None, "") else None
        cylinder_count_raw = raw.get("cylinder_count")
        cylinder_count_val = _i(cylinder_count_raw, 0) if cylinder_count_raw not in (None, "") else None
        if cylinder_count_val == 0:
            cylinder_count_val = None
        if engine_size_val is not None and engine_size_val <= 0.0:
            engine_size_val = None

        region_specs_raw = _s(raw.get("region_specs"), "").lower()
        region_specs_val = (
            region_specs_raw if region_specs_raw in _ALLOWED_REGION_SPECS else None
        )

        plate_type_raw = _s(raw.get("plate_type") or raw.get("plateType"), "").lower()
        plate_type_val = plate_type_raw if plate_type_raw in _ALLOWED_PLATE_TYPES else None
        plate_city_val = _s(raw.get("plate_city") or raw.get("plateCity"), None) or None

        if not brand or not model:
            return jsonify({"message": "Validation failed", "errors": {"brand/model": "required"}}), 400

        if vin and _vin_used_by_other_listing(vin):
            return _vin_conflict_response()

        car = Car(
            seller_id=current_user.id,
            title=(f"{brand.title()} {model.title()} {year or ''}".strip() or f"{brand.title()} {model.title()}").strip(),
            title_status=title_status,
            damaged_parts=damaged_parts_val,
            trim=trim,
            brand=brand,
            model=model,
            year=year,
            mileage=mileage,
            engine_type=engine_type,
            fuel_type=fuel_type,
            transmission=transmission,
            drive_type=drive_type,
            condition=condition,
            body_type=body_type,
            price=price,
            location=location,
            seating=seating,
            status=status,
            description=description,
            color=color,
            fuel_economy=fuel_economy,
            vin=vin,
            currency=currency,
            engine_size=engine_size_val,
            cylinder_count=cylinder_count_val,
            region_specs=region_specs_val,
            plate_type=plate_type_val,
            plate_city=plate_city_val,
        )

        db.session.add(car)
        db.session.commit()
        log_user_action(current_user, "create_listing", "car", car.public_id)
        if car.is_active and (car.status or "active") == "active":
            try:
                dispatch_saved_search_alerts(car.id)
            except Exception:
                pass
        return jsonify({"message": "Car listing created successfully", "car": car.to_dict()}), 201
    except Exception as e:
        return _listing_db_error_response(e, action="create car listing")


def _resolve_car_for_user(car_id: str, user, *, require_owner: bool = True, require_active: bool = True):
    """Find car by public_id or numeric id; optional owner/admin check."""
    car = Car.query.filter_by(public_id=car_id).first()
    if not car and str(car_id).isdigit():
        try:
            car = Car.query.filter_by(id=int(car_id)).first()
        except (TypeError, ValueError):
            car = None
    if not car:
        return None, (jsonify({"message": "Car not found"}), 404)
    if require_active and not car.is_active and not getattr(user, "is_admin", False):
        return None, (jsonify({"message": "Car not found"}), 404)
    if require_owner and car.seller_id != user.id and not user.is_admin:
        return None, (
            jsonify({"message": "Not authorized to update this listing"}),
            403,
        )
    return car, None


@bp.route("/api/cars/<car_id>", methods=["PUT"])
@jwt_required()
def update_car(car_id: str):
    """Update car listing."""
    try:
        current_user = get_current_user()
        if not current_user:
            return jsonify({"message": "User not found"}), 404

        car, err = _resolve_car_for_user(car_id, current_user)
        if err:
            return err

        old_price = float(car.price or 0)

        raw = request.get_json(silent=True) or {}

        def _s(val, default=""):
            return (val if isinstance(val, str) else str(val or "")).strip() or default

        def _i(val, default=0):
            try:
                return int(val)
            except Exception:
                try:
                    return int(float(val))
                except Exception:
                    return default

        def _f(val, default=0.0):
            try:
                return float(val)
            except Exception:
                return default

        data = dict(raw)
        if "brand" in data:
            data["brand"] = _s(data.get("brand"), car.brand or "unknown").lower().replace(" ", "-")
        if "model" in data:
            data["model"] = _s(data.get("model"), car.model or "")
        if "year" in data:
            data["year"] = _i(data.get("year"), car.year or 0)
        if "mileage" in data:
            data["mileage"] = _i(data.get("mileage"), car.mileage or 0)
        if "price" in data:
            data["price"] = _f(data.get("price"), car.price or 0.0)
        if "condition" in data:
            data["condition"] = _s(data.get("condition"), car.condition or "used").lower()
        if "transmission" in data:
            data["transmission"] = _s(
                data.get("transmission"), car.transmission or "automatic"
            ).lower()
        if "drive_type" in data:
            data["drive_type"] = _s(data.get("drive_type"), car.drive_type or "fwd").lower()
        if "body_type" in data:
            data["body_type"] = _s(data.get("body_type"), car.body_type or "sedan").lower()
        if "engine_type" in data:
            data["engine_type"] = _s(
                data.get("engine_type"), car.engine_type or "gasoline"
            ).lower()
        if "fuel_type" in data:
            data["fuel_type"] = _s(data.get("fuel_type"), car.fuel_type or "gasoline").lower()
        if "color" in data:
            data["color"] = _s(data.get("color"), car.color or "white").lower()
        if "location" in data:
            data["location"] = _s(data.get("location"), car.location or "")
        if "description" in data:
            desc = _s(data.get("description"), "")
            data["description"] = desc or None
        if "title_status" in data:
            ts = _s(data.get("title_status"), car.title_status or "clean").lower()
            data["title_status"] = ts if ts in {"clean", "damaged"} else "clean"

        updatable_fields = [
            "brand",
            "model",
            "year",
            "mileage",
            "engine_type",
            "fuel_type",
            "transmission",
            "drive_type",
            "condition",
            "body_type",
            "price",
            "location",
            "description",
            "color",
            "fuel_economy",
            "vin",
            "engine_size",
            "cylinder_count",
            "region_specs",
            "title_status",
            "damaged_parts",
            "plate_type",
            "plate_city",
        ]
        for field in updatable_fields:
            if field not in data:
                continue
            val = data[field]
            if field == "region_specs":
                rs = (str(val or "").strip().lower())
                val = rs if rs in _ALLOWED_REGION_SPECS else None
            elif field == "plate_type":
                pt = (str(val or "").strip().lower())
                val = pt if pt in _ALLOWED_PLATE_TYPES else None
            elif field == "engine_size" and val is not None:
                val = _leading_float(val)
            elif field == "cylinder_count" and val is not None:
                val = _safe_int(val)
                if val is not None and val < 1:
                    val = None
            elif field == "title_status":
                val = str(val or "").strip().lower()
                if val not in {"clean", "damaged"}:
                    continue
            elif field == "damaged_parts":
                if (car.title_status or "").lower() != "damaged":
                    continue
                val = _safe_int(val)
                if val is not None and val < 1:
                    val = None
            elif field == "vin":
                val = _normalize_vin(val) if val not in (None, "") else None
            setattr(car, field, val)

        if "trim" in data:
            car.trim = _s(data.get("trim"), car.trim or "base").lower()
        if "seating" in data:
            seat = _safe_int(data.get("seating"))
            if seat is not None and seat > 0:
                car.seating = seat
        if "title" in data:
            car.title = _s(data.get("title"), car.title or "")[:200]
        else:
            car.title = f"{car.brand} {car.model} {car.trim or ''} {car.year or ''}".strip()[:200]

        if "status" in data:
            st = (str(data.get("status") or "").strip().lower())
            if st not in _ALLOWED_LISTING_STATUSES:
                return jsonify({"message": "Invalid status"}), 400
            car.status = st

        if (car.title_status or "").lower() == "clean":
            car.damaged_parts = None

        if car.vin:
            car.vin = _normalize_vin(car.vin)
            if _vin_used_by_other_listing(car.vin, exclude_car_id=car.id):
                return _vin_conflict_response()

        car.updated_at = utcnow()
        db.session.commit()
        log_user_action(current_user, "update_listing", "car", car.public_id)
        if "price" in data:
            new_price = float(car.price or 0)
            if new_price < old_price and car.is_active:
                try:
                    dispatch_price_drop_alerts(car.id, old_price, new_price)
                except Exception:
                    pass
        try:
            car_payload = car.to_dict()
        except Exception as serialize_err:
            current_app.logger.exception(
                "update_car to_dict failed: %s", serialize_err
            )
            car_payload = {
                "id": car.public_id if getattr(car, "public_id", None) else str(car.id),
                "title": car.title,
                "brand": car.brand,
                "model": car.model,
                "year": car.year,
                "price": car.price,
            }
        return jsonify(
            {"message": "Car listing updated successfully", "car": car_payload}
        ), 200
    except Exception as e:
        return _listing_db_error_response(e, action="update car listing")


@bp.route("/api/cars/<car_id>", methods=["DELETE"])
@jwt_required()
def delete_car(car_id: str):
    """Soft-delete car listing."""
    try:
        current_user = get_current_user()
        if not current_user:
            return jsonify({"message": "User not found"}), 404

        car, err = _resolve_car_for_user(car_id, current_user)
        if err:
            return err

        remove_listing_from_all_favorites(car.id)
        remove_listing_from_all_view_history(car.id)
        car.is_active = False
        car.updated_at = utcnow()
        db.session.commit()
        log_user_action(current_user, "delete_listing", "car", car.public_id)
        return jsonify({"message": "Car listing deleted successfully"}), 200
    except Exception:
        return jsonify({"message": "Failed to delete car listing"}), 500


@bp.route("/api/cars/<car_id>/mark-sold", methods=["POST"])
@jwt_required()
def mark_car_sold(car_id: str):
    """Mark the owner's listing as sold while keeping it visible."""
    try:
        current_user = get_current_user()
        if not current_user:
            return jsonify({"message": "User not found"}), 404

        car, err = _resolve_car_for_user(
            car_id, current_user, require_active=False
        )
        if err:
            return err

        car.status = "sold"
        car.updated_at = utcnow()
        db.session.commit()
        log_user_action(current_user, "mark_listing_sold", "car", car.public_id)
        return jsonify({"message": "Listing marked as sold", "car": car.to_dict()}), 200
    except Exception:
        db.session.rollback()
        return jsonify({"message": "Failed to mark listing as sold"}), 500


@bp.route("/api/cars/<car_id>/mark-active", methods=["POST"])
@jwt_required()
def mark_car_active(car_id: str):
    """Mark a sold listing as available again."""
    try:
        current_user = get_current_user()
        if not current_user:
            return jsonify({"message": "User not found"}), 404

        car, err = _resolve_car_for_user(
            car_id, current_user, require_active=False
        )
        if err:
            return err

        car.status = "active"
        car.updated_at = utcnow()
        db.session.commit()
        log_user_action(current_user, "mark_listing_active", "car", car.public_id)
        return jsonify({"message": "Listing marked as available", "car": car.to_dict()}), 200
    except Exception:
        db.session.rollback()
        return jsonify({"message": "Failed to mark listing as available"}), 500


@bp.route("/api/user/my-listings", methods=["GET"])
@jwt_required()
def get_my_listings():
    """Get current user's car listings."""
    try:
        current_user = get_current_user()
        if not current_user:
            return jsonify({"message": "User not found"}), 404

        page = request.args.get("page", 1, type=int)
        per_page = min(request.args.get("per_page", 10, type=int), 50)

        pagination = (
            Car.query.filter_by(seller_id=current_user.id, is_active=True)
            .order_by(Car.created_at.desc())
            .paginate(page=page, per_page=per_page, error_out=False)
        )
        cars = [car.to_dict(include_private=True) for car in pagination.items]
        return (
            jsonify(
                {
                    "cars": cars,
                    "pagination": {
                        "page": page,
                        "per_page": per_page,
                        "total": pagination.total,
                        "pages": pagination.pages,
                        "has_next": pagination.has_next,
                        "has_prev": pagination.has_prev,
                    },
                }
            ),
            200,
        )
    except Exception:
        return jsonify({"message": "Failed to get your listings"}), 500


@bp.route("/api/my_listings", methods=["GET"])
@jwt_required()
def compat_my_listings():
    """Legacy alias for mobile clients expecting /api/my_listings."""
    try:
        current_user = get_current_user()
        if not current_user:
            return jsonify({"message": "Unauthorized"}), 401

        cars = (
            Car.query.filter_by(seller_id=current_user.id, is_active=True)
            .order_by(Car.created_at.desc())
            .all()
        )
        result = []
        for car in cars:
            d = _with_media_compat(car)
            # Keep public_id as `id` (from to_dict); expose numeric id for legacy clients.
            d["numeric_id"] = car.id
            d["videos"] = [v.video_url for v in car.videos] if car.videos else []
            if not d.get("title"):
                d["title"] = f"{(car.brand or '').title()} {(car.model or '').title()} {car.year or ''}".strip()
            result.append(d)
        return jsonify(result), 200
    except Exception:
        return jsonify({"message": "Failed to get your listings"}), 500


@bp.route("/api/cars/<car_id>/report", methods=["POST"])
@jwt_required()
@rate_limit(max_requests=10, window_minutes=60, per_ip=False)
def report_car(car_id: str):
    """Report a listing for policy violations or fraud."""
    try:
        current_user = get_current_user()
        if not current_user:
            return jsonify({"message": "Unauthorized"}), 401

        car, err = _resolve_car_for_user(
            car_id, current_user, require_owner=False, require_active=False
        )
        if err:
            return err

        if car.seller_id == current_user.id:
            return jsonify({"message": "Cannot report your own listing"}), 400

        data = request.get_json(silent=True) or {}
        reason = str(data.get("reason") or "").strip()
        if not reason:
            return jsonify({"message": "reason is required"}), 400
        if len(reason) > 200:
            reason = reason[:200]
        details = str(data.get("details") or "").strip()[:2000] or None

        db.session.add(
            ListingReport(
                reporter_id=current_user.id,
                car_id=car.id,
                reason=reason,
                details=details,
            )
        )
        db.session.commit()
        return jsonify({"message": "Report submitted. Thank you."}), 201
    except Exception:
        db.session.rollback()
        return jsonify({"message": "Failed to submit report"}), 500

