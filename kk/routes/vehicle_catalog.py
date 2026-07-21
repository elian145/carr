"""Vehicle catalog admin + public read APIs."""

from __future__ import annotations

import logging

from flask import Blueprint, jsonify, request

from ..auth import admin_required, get_current_user, log_user_action
from ..admin_roles import assert_permission
from ..catalog_service import seed_catalog
from ..models import CatalogBodyType, CatalogBrand, CatalogTrim, CatalogVehicleModel, db
from ..response_cache import (
    CATALOG_TTL_S,
    cache_get,
    cache_set,
    catalog_cache_key,
    invalidate_catalog_cache,
)
from ..time_utils import utcnow

bp = Blueprint("vehicle_catalog", __name__)
logger = logging.getLogger(__name__)


def _deny(permission: str):
    _, err = assert_permission(permission)
    return err


def _bool(val, default=None):
    if val is None:
        return default
    if isinstance(val, bool):
        return val
    s = str(val).strip().lower()
    if s in ("1", "true", "yes", "on"):
        return True
    if s in ("0", "false", "no", "off"):
        return False
    return default


# ── Public catalog (active only) ─────────────────────────────────────────────


@bp.route("/api/catalog/brands", methods=["GET"])
def public_brands():
    try:
        cache_key = catalog_cache_key("brands")
        cached = cache_get(cache_key)
        if cached is not None:
            return jsonify(cached), 200
        rows = (
            CatalogBrand.query.filter_by(is_active=True)
            .order_by(CatalogBrand.sort_order.asc(), CatalogBrand.name.asc())
            .all()
        )
        payload = {"brands": [b.to_dict() for b in rows]}
        cache_set(cache_key, payload, CATALOG_TTL_S)
        return jsonify(payload), 200
    except Exception as e:
        logger.error("public catalog brands error: %s", e, exc_info=True)
        return jsonify({"message": "Failed to load brands"}), 500


@bp.route("/api/catalog/models", methods=["GET"])
def public_models():
    try:
        brand_name = (request.args.get("brand") or "").strip()
        brand_id = request.args.get("brand_id", type=int)
        cache_key = catalog_cache_key(
            "models",
            f"id:{brand_id}" if brand_id else f"name:{brand_name or 'all'}",
        )
        cached = cache_get(cache_key)
        if cached is not None:
            return jsonify(cached), 200

        q = CatalogVehicleModel.query.filter_by(is_active=True)
        if brand_id:
            q = q.filter_by(brand_id=brand_id)
        elif brand_name:
            brand = CatalogBrand.query.filter_by(name=brand_name, is_active=True).first()
            if not brand:
                payload = {"models": []}
                cache_set(cache_key, payload, CATALOG_TTL_S)
                return jsonify(payload), 200
            q = q.filter_by(brand_id=brand.id)
        rows = q.order_by(CatalogVehicleModel.sort_order.asc(), CatalogVehicleModel.name.asc()).all()
        payload = {"models": [m.to_dict() for m in rows]}
        cache_set(cache_key, payload, CATALOG_TTL_S)
        return jsonify(payload), 200
    except Exception as e:
        logger.error("public catalog models error: %s", e, exc_info=True)
        return jsonify({"message": "Failed to load models"}), 500


@bp.route("/api/catalog/body-types", methods=["GET"])
def public_body_types():
    try:
        cache_key = catalog_cache_key("body-types")
        cached = cache_get(cache_key)
        if cached is not None:
            return jsonify(cached), 200
        rows = (
            CatalogBodyType.query.filter_by(is_active=True)
            .order_by(CatalogBodyType.sort_order.asc(), CatalogBodyType.name.asc())
            .all()
        )
        payload = {"body_types": [b.to_dict() for b in rows]}
        cache_set(cache_key, payload, CATALOG_TTL_S)
        return jsonify(payload), 200
    except Exception as e:
        logger.error("public catalog body types error: %s", e, exc_info=True)
        return jsonify({"message": "Failed to load body types"}), 500


@bp.route("/api/catalog/trims", methods=["GET"])
def public_trims():
    """Active trims for a brand+model (query: brand, model)."""
    try:
        brand_name = (request.args.get("brand") or "").strip()
        model_name = (request.args.get("model") or "").strip()
        if not brand_name or not model_name:
            return jsonify({"message": "brand and model are required"}), 400
        cache_key = catalog_cache_key("trims", brand_name, model_name)
        cached = cache_get(cache_key)
        if cached is not None:
            return jsonify(cached), 200
        brand = CatalogBrand.query.filter_by(name=brand_name, is_active=True).first()
        if not brand:
            payload = {"trims": []}
            cache_set(cache_key, payload, CATALOG_TTL_S)
            return jsonify(payload), 200
        model = CatalogVehicleModel.query.filter_by(
            brand_id=brand.id, name=model_name, is_active=True
        ).first()
        if not model:
            payload = {"trims": []}
            cache_set(cache_key, payload, CATALOG_TTL_S)
            return jsonify(payload), 200
        rows = (
            CatalogTrim.query.filter_by(model_id=model.id, is_active=True)
            .order_by(CatalogTrim.sort_order.asc(), CatalogTrim.name.asc())
            .all()
        )
        payload = {"trims": [t.to_dict() for t in rows]}
        cache_set(cache_key, payload, CATALOG_TTL_S)
        return jsonify(payload), 200
    except Exception as e:
        logger.error("public catalog trims error: %s", e, exc_info=True)
        return jsonify({"message": "Failed to load trims"}), 500


# ── Admin catalog ────────────────────────────────────────────────────────────


@bp.route("/api/admin/catalog/summary", methods=["GET"])
@admin_required
def admin_catalog_summary():
    try:
        denied = _deny("catalog.read")
        if denied:
            return denied
        return (
            jsonify(
                {
                    "brands": CatalogBrand.query.count(),
                    "active_brands": CatalogBrand.query.filter_by(is_active=True).count(),
                    "models": CatalogVehicleModel.query.count(),
                    "active_models": CatalogVehicleModel.query.filter_by(is_active=True).count(),
                    "trims": CatalogTrim.query.count(),
                    "active_trims": CatalogTrim.query.filter_by(is_active=True).count(),
                    "body_types": CatalogBodyType.query.count(),
                    "active_body_types": CatalogBodyType.query.filter_by(is_active=True).count(),
                }
            ),
            200,
        )
    except Exception as e:
        logger.error("admin catalog summary error: %s", e, exc_info=True)
        return jsonify({"message": "Failed to load catalog summary"}), 500


@bp.route("/api/admin/catalog/seed", methods=["POST"])
@admin_required
def admin_catalog_seed():
    try:
        denied = _deny("catalog.write")
        if denied:
            return denied
        admin_user = get_current_user()
        data = request.get_json(silent=True) or {}
        force = bool(data.get("force"))
        result = seed_catalog(force=force)
        invalidate_catalog_cache()
        if admin_user:
            log_user_action(
                admin_user,
                "admin_catalog_seed",
                target_type="catalog",
                target_id="seed",
                metadata={"force": force, **{k: result.get(k) for k in ("brands_created", "models_created", "body_types_created")}},
            )
        return jsonify({"message": "Catalog seed complete", **result}), 200
    except FileNotFoundError as e:
        return jsonify({"message": f"Catalog file not found: {e}"}), 404
    except Exception as e:
        db.session.rollback()
        logger.error("admin catalog seed error: %s", e, exc_info=True)
        return jsonify({"message": "Failed to seed catalog"}), 500


@bp.route("/api/admin/catalog/brands", methods=["GET"])
@admin_required
def admin_list_brands():
    try:
        denied = _deny("catalog.read")
        if denied:
            return denied
        q = (request.args.get("q") or "").strip()
        active = _bool(request.args.get("active"))
        query = CatalogBrand.query
        if q:
            query = query.filter(CatalogBrand.name.ilike(f"%{q}%"))
        if active is not None:
            query = query.filter(CatalogBrand.is_active.is_(active))
        rows = query.order_by(CatalogBrand.sort_order.asc(), CatalogBrand.name.asc()).all()
        return jsonify({"brands": [b.to_dict(include_model_count=True) for b in rows]}), 200
    except Exception as e:
        logger.error("admin list brands error: %s", e, exc_info=True)
        return jsonify({"message": "Failed to list brands"}), 500


@bp.route("/api/admin/catalog/brands", methods=["POST"])
@admin_required
def admin_create_brand():
    try:
        denied = _deny("catalog.write")
        if denied:
            return denied
        admin_user = get_current_user()
        data = request.get_json(silent=True) or {}
        name = str(data.get("name") or "").strip()
        if not name:
            return jsonify({"message": "name is required"}), 400
        if CatalogBrand.query.filter_by(name=name).first():
            return jsonify({"message": "Brand already exists"}), 409
        brand = CatalogBrand(
            name=name,
            is_active=_bool(data.get("is_active"), True),
            sort_order=int(data.get("sort_order") or 0),
            created_at=utcnow(),
            updated_at=utcnow(),
        )
        db.session.add(brand)
        db.session.commit()
        invalidate_catalog_cache()
        if admin_user:
            log_user_action(
                admin_user,
                "admin_catalog_create_brand",
                target_type="catalog_brand",
                target_id=str(brand.id),
                metadata={"name": name},
            )
        return jsonify({"brand": brand.to_dict(include_model_count=True)}), 201
    except Exception as e:
        db.session.rollback()
        logger.error("admin create brand error: %s", e, exc_info=True)
        return jsonify({"message": "Failed to create brand"}), 500


@bp.route("/api/admin/catalog/brands/<int:brand_id>", methods=["PATCH"])
@admin_required
def admin_update_brand(brand_id: int):
    try:
        denied = _deny("catalog.write")
        if denied:
            return denied
        admin_user = get_current_user()
        brand = CatalogBrand.query.get(brand_id)
        if not brand:
            return jsonify({"message": "Brand not found"}), 404
        data = request.get_json(silent=True) or {}
        if "name" in data:
            name = str(data.get("name") or "").strip()
            if not name:
                return jsonify({"message": "name cannot be empty"}), 400
            clash = CatalogBrand.query.filter(
                CatalogBrand.name == name, CatalogBrand.id != brand.id
            ).first()
            if clash:
                return jsonify({"message": "Brand already exists"}), 409
            brand.name = name
        if "is_active" in data:
            brand.is_active = bool(data["is_active"])
        if "sort_order" in data:
            brand.sort_order = int(data["sort_order"] or 0)
        brand.updated_at = utcnow()
        db.session.commit()
        invalidate_catalog_cache()
        if admin_user:
            log_user_action(
                admin_user,
                "admin_catalog_update_brand",
                target_type="catalog_brand",
                target_id=str(brand.id),
                metadata=data,
            )
        return jsonify({"brand": brand.to_dict(include_model_count=True)}), 200
    except Exception as e:
        db.session.rollback()
        logger.error("admin update brand error: %s", e, exc_info=True)
        return jsonify({"message": "Failed to update brand"}), 500


@bp.route("/api/admin/catalog/brands/<int:brand_id>/models", methods=["GET"])
@admin_required
def admin_list_models(brand_id: int):
    try:
        denied = _deny("catalog.read")
        if denied:
            return denied
        brand = CatalogBrand.query.get(brand_id)
        if not brand:
            return jsonify({"message": "Brand not found"}), 404
        active = _bool(request.args.get("active"))
        q = CatalogVehicleModel.query.filter_by(brand_id=brand_id)
        if active is not None:
            q = q.filter(CatalogVehicleModel.is_active.is_(active))
        rows = q.order_by(CatalogVehicleModel.sort_order.asc(), CatalogVehicleModel.name.asc()).all()
        return (
            jsonify(
                {
                    "brand": brand.to_dict(include_model_count=True),
                    "models": [m.to_dict(include_trim_count=True) for m in rows],
                }
            ),
            200,
        )
    except Exception as e:
        logger.error("admin list models error: %s", e, exc_info=True)
        return jsonify({"message": "Failed to list models"}), 500


@bp.route("/api/admin/catalog/models", methods=["POST"])
@admin_required
def admin_create_model():
    try:
        denied = _deny("catalog.write")
        if denied:
            return denied
        admin_user = get_current_user()
        data = request.get_json(silent=True) or {}
        brand_id = data.get("brand_id")
        name = str(data.get("name") or "").strip()
        if not brand_id or not name:
            return jsonify({"message": "brand_id and name are required"}), 400
        brand = CatalogBrand.query.get(int(brand_id))
        if not brand:
            return jsonify({"message": "Brand not found"}), 404
        if CatalogVehicleModel.query.filter_by(brand_id=brand.id, name=name).first():
            return jsonify({"message": "Model already exists for this brand"}), 409
        row = CatalogVehicleModel(
            brand_id=brand.id,
            name=name,
            is_active=_bool(data.get("is_active"), True),
            sort_order=int(data.get("sort_order") or 0),
            created_at=utcnow(),
            updated_at=utcnow(),
        )
        db.session.add(row)
        db.session.commit()
        invalidate_catalog_cache()
        if admin_user:
            log_user_action(
                admin_user,
                "admin_catalog_create_model",
                target_type="catalog_model",
                target_id=str(row.id),
                metadata={"brand_id": brand.id, "name": name},
            )
        return jsonify({"model": row.to_dict()}), 201
    except Exception as e:
        db.session.rollback()
        logger.error("admin create model error: %s", e, exc_info=True)
        return jsonify({"message": "Failed to create model"}), 500


@bp.route("/api/admin/catalog/models/<int:model_id>", methods=["PATCH"])
@admin_required
def admin_update_model(model_id: int):
    try:
        denied = _deny("catalog.write")
        if denied:
            return denied
        admin_user = get_current_user()
        row = CatalogVehicleModel.query.get(model_id)
        if not row:
            return jsonify({"message": "Model not found"}), 404
        data = request.get_json(silent=True) or {}
        if "name" in data:
            name = str(data.get("name") or "").strip()
            if not name:
                return jsonify({"message": "name cannot be empty"}), 400
            clash = CatalogVehicleModel.query.filter(
                CatalogVehicleModel.brand_id == row.brand_id,
                CatalogVehicleModel.name == name,
                CatalogVehicleModel.id != row.id,
            ).first()
            if clash:
                return jsonify({"message": "Model already exists for this brand"}), 409
            row.name = name
        if "is_active" in data:
            row.is_active = bool(data["is_active"])
        if "sort_order" in data:
            row.sort_order = int(data["sort_order"] or 0)
        row.updated_at = utcnow()
        db.session.commit()
        invalidate_catalog_cache()
        if admin_user:
            log_user_action(
                admin_user,
                "admin_catalog_update_model",
                target_type="catalog_model",
                target_id=str(row.id),
                metadata=data,
            )
        return jsonify({"model": row.to_dict()}), 200
    except Exception as e:
        db.session.rollback()
        logger.error("admin update model error: %s", e, exc_info=True)
        return jsonify({"message": "Failed to update model"}), 500


@bp.route("/api/admin/catalog/body-types", methods=["GET"])
@admin_required
def admin_list_body_types():
    try:
        denied = _deny("catalog.read")
        if denied:
            return denied
        active = _bool(request.args.get("active"))
        q = CatalogBodyType.query
        if active is not None:
            q = q.filter(CatalogBodyType.is_active.is_(active))
        rows = q.order_by(CatalogBodyType.sort_order.asc(), CatalogBodyType.name.asc()).all()
        return jsonify({"body_types": [b.to_dict() for b in rows]}), 200
    except Exception as e:
        logger.error("admin list body types error: %s", e, exc_info=True)
        return jsonify({"message": "Failed to list body types"}), 500


@bp.route("/api/admin/catalog/body-types", methods=["POST"])
@admin_required
def admin_create_body_type():
    try:
        denied = _deny("catalog.write")
        if denied:
            return denied
        admin_user = get_current_user()
        data = request.get_json(silent=True) or {}
        name = str(data.get("name") or "").strip()
        if not name:
            return jsonify({"message": "name is required"}), 400
        if CatalogBodyType.query.filter_by(name=name).first():
            return jsonify({"message": "Body type already exists"}), 409
        row = CatalogBodyType(
            name=name,
            is_active=_bool(data.get("is_active"), True),
            sort_order=int(data.get("sort_order") or 0),
            created_at=utcnow(),
            updated_at=utcnow(),
        )
        db.session.add(row)
        db.session.commit()
        invalidate_catalog_cache()
        if admin_user:
            log_user_action(
                admin_user,
                "admin_catalog_create_body_type",
                target_type="catalog_body_type",
                target_id=str(row.id),
                metadata={"name": name},
            )
        return jsonify({"body_type": row.to_dict()}), 201
    except Exception as e:
        db.session.rollback()
        logger.error("admin create body type error: %s", e, exc_info=True)
        return jsonify({"message": "Failed to create body type"}), 500


@bp.route("/api/admin/catalog/body-types/<int:body_type_id>", methods=["PATCH"])
@admin_required
def admin_update_body_type(body_type_id: int):
    try:
        denied = _deny("catalog.write")
        if denied:
            return denied
        admin_user = get_current_user()
        row = CatalogBodyType.query.get(body_type_id)
        if not row:
            return jsonify({"message": "Body type not found"}), 404
        data = request.get_json(silent=True) or {}
        if "name" in data:
            name = str(data.get("name") or "").strip()
            if not name:
                return jsonify({"message": "name cannot be empty"}), 400
            clash = CatalogBodyType.query.filter(
                CatalogBodyType.name == name, CatalogBodyType.id != row.id
            ).first()
            if clash:
                return jsonify({"message": "Body type already exists"}), 409
            row.name = name
        if "is_active" in data:
            row.is_active = bool(data["is_active"])
        if "sort_order" in data:
            row.sort_order = int(data["sort_order"] or 0)
        row.updated_at = utcnow()
        db.session.commit()
        invalidate_catalog_cache()
        if admin_user:
            log_user_action(
                admin_user,
                "admin_catalog_update_body_type",
                target_type="catalog_body_type",
                target_id=str(row.id),
                metadata=data,
            )
        return jsonify({"body_type": row.to_dict()}), 200
    except Exception as e:
        db.session.rollback()
        logger.error("admin update body type error: %s", e, exc_info=True)
        return jsonify({"message": "Failed to update body type"}), 500


@bp.route("/api/admin/catalog/models/<int:model_id>/trims", methods=["GET"])
@admin_required
def admin_list_trims(model_id: int):
    try:
        denied = _deny("catalog.read")
        if denied:
            return denied
        model = CatalogVehicleModel.query.get(model_id)
        if not model:
            return jsonify({"message": "Model not found"}), 404
        rows = (
            CatalogTrim.query.filter_by(model_id=model_id)
            .order_by(CatalogTrim.sort_order.asc(), CatalogTrim.name.asc())
            .all()
        )
        return jsonify({"model": model.to_dict(include_trim_count=True), "trims": [t.to_dict() for t in rows]}), 200
    except Exception as e:
        logger.error("admin list trims error: %s", e, exc_info=True)
        return jsonify({"message": "Failed to list trims"}), 500


@bp.route("/api/admin/catalog/trims", methods=["POST"])
@admin_required
def admin_create_trim():
    try:
        denied = _deny("catalog.write")
        if denied:
            return denied
        admin_user = get_current_user()
        data = request.get_json(silent=True) or {}
        model_id = data.get("model_id")
        name = str(data.get("name") or "").strip()
        if not model_id or not name:
            return jsonify({"message": "model_id and name are required"}), 400
        model = CatalogVehicleModel.query.get(int(model_id))
        if not model:
            return jsonify({"message": "Model not found"}), 404
        if CatalogTrim.query.filter_by(model_id=model.id, name=name).first():
            return jsonify({"message": "Trim already exists"}), 409
        row = CatalogTrim(
            model_id=model.id,
            name=name,
            is_active=_bool(data.get("is_active"), True),
            sort_order=int(data.get("sort_order") or 0),
            created_at=utcnow(),
            updated_at=utcnow(),
        )
        db.session.add(row)
        db.session.commit()
        invalidate_catalog_cache()
        if admin_user:
            log_user_action(
                admin_user,
                "admin_catalog_create_trim",
                target_type="catalog_trim",
                target_id=str(row.id),
                metadata={"model_id": model.id, "name": name},
            )
        return jsonify({"trim": row.to_dict()}), 201
    except Exception as e:
        db.session.rollback()
        logger.error("admin create trim error: %s", e, exc_info=True)
        return jsonify({"message": "Failed to create trim"}), 500


@bp.route("/api/admin/catalog/trims/<int:trim_id>", methods=["PATCH"])
@admin_required
def admin_update_trim(trim_id: int):
    try:
        denied = _deny("catalog.write")
        if denied:
            return denied
        admin_user = get_current_user()
        row = CatalogTrim.query.get(trim_id)
        if not row:
            return jsonify({"message": "Trim not found"}), 404
        data = request.get_json(silent=True) or {}
        if "name" in data:
            name = str(data.get("name") or "").strip()
            if not name:
                return jsonify({"message": "name cannot be empty"}), 400
            clash = CatalogTrim.query.filter(
                CatalogTrim.model_id == row.model_id,
                CatalogTrim.name == name,
                CatalogTrim.id != row.id,
            ).first()
            if clash:
                return jsonify({"message": "Trim already exists"}), 409
            row.name = name
        if "is_active" in data:
            row.is_active = bool(data["is_active"])
        if "sort_order" in data:
            row.sort_order = int(data["sort_order"] or 0)
        row.updated_at = utcnow()
        db.session.commit()
        invalidate_catalog_cache()
        if admin_user:
            log_user_action(
                admin_user,
                "admin_catalog_update_trim",
                target_type="catalog_trim",
                target_id=str(row.id),
                metadata=data,
            )
        return jsonify({"trim": row.to_dict()}), 200
    except Exception as e:
        db.session.rollback()
        logger.error("admin update trim error: %s", e, exc_info=True)
        return jsonify({"message": "Failed to update trim"}), 500
