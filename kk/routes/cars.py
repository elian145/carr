from __future__ import annotations

import os
import time
from datetime import datetime

from flask import Blueprint, current_app, jsonify, request
from flask_jwt_extended import jwt_required, verify_jwt_in_request
from sqlalchemy import select, update
from sqlalchemy.orm import joinedload, selectinload

from ..auth import get_current_user, log_user_action
from ..models import Car, User, db, user_viewed_listings
from ..time_utils import utcnow

bp = Blueprint("cars", __name__)


MAX_PER_PAGE = int(os.environ.get("MAX_PER_PAGE", "50"))
MAX_PER_PAGE = max(1, min(MAX_PER_PAGE, 200))

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
            exists = db.session.execute(
                select(user_viewed_listings.c.user_id).where(
                    user_viewed_listings.c.user_id == current_user.id,
                    user_viewed_listings.c.car_id == car.id,
                )
            ).first()
            if exists:
                return
            db.session.execute(
                user_viewed_listings.insert().values(
                    user_id=current_user.id,
                    car_id=car.id,
                    viewed_at=now,
                )
            )
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
    raw_list = [img.image_url for img in car.images] if car.images else []
    image_list = [r for r in (_resolve_rel(rel) for rel in raw_list) if r]
    primary_rel = image_list[0] if image_list else ""
    if not primary_rel and _static_exists("uploads/car_photos/placeholder.jpg"):
        primary_rel = "uploads/car_photos/placeholder.jpg"
    d["image_url"] = primary_rel
    d["images"] = image_list
    return d


@bp.route("/api/cars", methods=["GET"])
def get_cars():
    """Get all cars with filtering and pagination."""
    try:
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

        query = (
            Car.query.filter_by(is_active=True)
            .options(
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
        return jsonify({"message": "Failed to get cars"}), 500


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

        query = (
            Car.query.filter_by(is_active=True)
            .options(
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
        return jsonify({"message": "Failed to get cars"}), 500


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
        vin = _s(raw.get("vin"), None) or None
        currency = _s(raw.get("currency"), "USD")[:3] or "USD"
        trim = _s(raw.get("trim"), "base")
        seating = _i(raw.get("seating"), 5)
        status = _s(raw.get("status"), "active")
        engine_size = raw.get("engine_size")
        engine_size_val = _f(engine_size, 0.0) if engine_size not in (None, "") else None
        cylinder_count_raw = raw.get("cylinder_count")
        cylinder_count_val = _i(cylinder_count_raw, 0) if cylinder_count_raw not in (None, "") else None
        if cylinder_count_val == 0:
            cylinder_count_val = None
        if engine_size_val == 0.0:
            engine_size_val = None

        if not brand or not model:
            return jsonify({"message": "Validation failed", "errors": {"brand/model": "required"}}), 400

        car = Car(
            seller_id=current_user.id,
            title=(f"{brand.title()} {model.title()} {year or ''}".strip() or f"{brand.title()} {model.title()}").strip(),
            title_status="active",
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
        )

        db.session.add(car)
        db.session.commit()
        log_user_action(current_user, "create_listing", "car", car.public_id)
        return jsonify({"message": "Car listing created successfully", "car": car.to_dict()}), 201
    except Exception:
        return jsonify({"message": "Failed to create car listing"}), 500


@bp.route("/api/cars/<car_id>", methods=["PUT"])
@jwt_required()
def update_car(car_id: str):
    """Update car listing."""
    try:
        current_user = get_current_user()
        if not current_user:
            return jsonify({"message": "User not found"}), 404

        car = Car.query.filter_by(public_id=car_id).first()
        if not car:
            return jsonify({"message": "Car not found"}), 404
        if car.seller_id != current_user.id and not current_user.is_admin:
            return jsonify({"message": "Not authorized to update this listing"}), 403

        data = request.get_json(silent=True) or {}
        updatable_fields = [
            "brand",
            "model",
            "year",
            "mileage",
            "engine_type",
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
        ]
        for field in updatable_fields:
            if field in data:
                val = data[field]
                if field == "engine_size" and val is not None:
                    try:
                        val = float(val)
                    except (TypeError, ValueError):
                        val = None
                if field == "cylinder_count" and val is not None:
                    try:
                        val = int(val)
                    except (TypeError, ValueError):
                        val = None
                setattr(car, field, val)

        car.updated_at = utcnow()
        db.session.commit()
        log_user_action(current_user, "update_listing", "car", car.public_id)
        return jsonify({"message": "Car listing updated successfully", "car": car.to_dict()}), 200
    except Exception:
        return jsonify({"message": "Failed to update car listing"}), 500


@bp.route("/api/cars/<car_id>", methods=["DELETE"])
@jwt_required()
def delete_car(car_id: str):
    """Soft-delete car listing."""
    try:
        current_user = get_current_user()
        if not current_user:
            return jsonify({"message": "User not found"}), 404

        car = Car.query.filter_by(public_id=car_id).first()
        if not car:
            return jsonify({"message": "Car not found"}), 404
        if car.seller_id != current_user.id and not current_user.is_admin:
            return jsonify({"message": "Not authorized to delete this listing"}), 403

        car.is_active = False
        car.updated_at = utcnow()
        db.session.commit()
        log_user_action(current_user, "delete_listing", "car", car.public_id)
        return jsonify({"message": "Car listing deleted successfully"}), 200
    except Exception:
        return jsonify({"message": "Failed to delete car listing"}), 500


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
            Car.query.filter_by(seller_id=current_user.id)
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

        cars = Car.query.filter_by(seller_id=current_user.id).order_by(Car.created_at.desc()).all()
        result = []
        for car in cars:
            d = _with_media_compat(car)
            d["id"] = car.id
            d["videos"] = [v.video_url for v in car.videos] if car.videos else []
            if not d.get("title"):
                d["title"] = f"{(car.brand or '').title()} {(car.model or '').title()} {car.year or ''}".strip()
            result.append(d)
        return jsonify(result), 200
    except Exception:
        return jsonify({"message": "Failed to get your listings"}), 500

