from __future__ import annotations

import json

from flask import Blueprint, jsonify, request
from flask_jwt_extended import jwt_required

from ..auth import get_current_user, log_user_action
from ..models import SavedSearch, db
from ..time_utils import utcnow
from .user import _to_bool

bp = Blueprint("saved_searches", __name__)

_MAX_SAVED_SEARCHES = 50


def _clean_filters(raw) -> dict:
    if isinstance(raw, dict):
        return {str(k): v for k, v in raw.items() if v is not None and str(v).strip() != ""}
    return {}


def _filters_fingerprint(filters: dict) -> str:
    cleaned = _clean_filters(filters)
    return json.dumps(cleaned, sort_keys=True, separators=(",", ":"))


def _find_by_filters(user_id: int, filters: dict) -> SavedSearch | None:
    target = _filters_fingerprint(filters)
    for row in SavedSearch.query.filter_by(user_id=user_id).all():
        if _filters_fingerprint(row.filters or {}) == target:
            return row
    return None


def _get_owned_search(user, public_id: str) -> SavedSearch | None:
    return SavedSearch.query.filter_by(public_id=public_id, user_id=user.id).first()


@bp.route("/api/saved-searches", methods=["GET"])
@jwt_required()
def list_saved_searches():
    try:
        current_user = get_current_user()
        if not current_user:
            return jsonify({"message": "User not found"}), 404

        rows = (
            SavedSearch.query.filter_by(user_id=current_user.id)
            .order_by(SavedSearch.created_at.desc())
            .limit(_MAX_SAVED_SEARCHES)
            .all()
        )
        return jsonify({"saved_searches": [r.to_dict() for r in rows]}), 200
    except Exception:
        return jsonify({"message": "Failed to list saved searches"}), 500


@bp.route("/api/saved-searches", methods=["POST"])
@jwt_required()
def create_saved_search():
    try:
        current_user = get_current_user()
        if not current_user:
            return jsonify({"message": "User not found"}), 404

        count = SavedSearch.query.filter_by(user_id=current_user.id).count()
        if count >= _MAX_SAVED_SEARCHES:
            return jsonify({"message": f"Maximum {_MAX_SAVED_SEARCHES} saved searches allowed"}), 400

        data = request.get_json(silent=True) or {}
        name = (data.get("name") or "").strip() or "Saved search"
        filters = _clean_filters(data.get("filters"))
        notify = data.get("notify")
        if notify is None:
            notify = True
        auto_saved = _to_bool(data.get("auto_saved"))

        existing = _find_by_filters(current_user.id, filters)
        if existing:
            if name and existing.name != name[:200]:
                existing.name = name[:200]
            existing.notify = bool(notify)
            existing.auto_saved = auto_saved
            existing.updated_at = utcnow()
            db.session.commit()
            return jsonify({"saved_search": existing.to_dict(), "existing": True}), 200

        row = SavedSearch(
            user_id=current_user.id,
            name=name[:200],
            filters=filters,
            notify=bool(notify),
            auto_saved=auto_saved,
        )
        db.session.add(row)
        db.session.commit()
        log_user_action(current_user, "saved_search_create", "saved_search", row.public_id)
        return jsonify({"saved_search": row.to_dict()}), 201
    except Exception:
        db.session.rollback()
        return jsonify({"message": "Failed to create saved search"}), 500


@bp.route("/api/saved-searches/<search_id>", methods=["PUT"])
@jwt_required()
def update_saved_search(search_id: str):
    try:
        current_user = get_current_user()
        if not current_user:
            return jsonify({"message": "User not found"}), 404

        row = _get_owned_search(current_user, search_id)
        if not row:
            return jsonify({"message": "Saved search not found"}), 404

        data = request.get_json(silent=True) or {}
        if "name" in data:
            name = (data.get("name") or "").strip()
            if name:
                row.name = name[:200]
        if "filters" in data:
            row.filters = _clean_filters(data.get("filters"))
        if "notify" in data:
            row.notify = bool(data.get("notify"))
        if "auto_saved" in data:
            row.auto_saved = _to_bool(data.get("auto_saved"))

        row.updated_at = utcnow()
        db.session.commit()
        return jsonify({"saved_search": row.to_dict()}), 200
    except Exception:
        db.session.rollback()
        return jsonify({"message": "Failed to update saved search"}), 500


@bp.route("/api/saved-searches/<search_id>", methods=["DELETE"])
@jwt_required()
def delete_saved_search(search_id: str):
    try:
        current_user = get_current_user()
        if not current_user:
            return jsonify({"message": "User not found"}), 404

        row = _get_owned_search(current_user, search_id)
        if not row:
            return jsonify({"message": "Saved search not found"}), 404

        db.session.delete(row)
        db.session.commit()
        log_user_action(current_user, "saved_search_delete", "saved_search", search_id)
        return jsonify({"message": "Deleted"}), 200
    except Exception:
        db.session.rollback()
        return jsonify({"message": "Failed to delete saved search"}), 500


@bp.route("/api/saved-searches/sync", methods=["POST"])
@jwt_required()
def sync_saved_searches():
    """
    Upsert saved searches from the mobile app (local → server merge).
    Body: { "items": [ { "id"?, "name", "filters", "notify", "auto_saved", "created_at"? } ] }
    Returns the canonical server list.
    """
    try:
        current_user = get_current_user()
        if not current_user:
            return jsonify({"message": "User not found"}), 404

        data = request.get_json(silent=True) or {}
        items = data.get("items")
        if not isinstance(items, list):
            return jsonify({"message": "items must be a list"}), 400

        existing = {
            s.public_id: s
            for s in SavedSearch.query.filter_by(user_id=current_user.id).all()
        }

        for raw in items[:_MAX_SAVED_SEARCHES]:
            if not isinstance(raw, dict):
                continue
            public_id = (raw.get("id") or raw.get("public_id") or "").strip()
            name = (raw.get("name") or "").strip() or "Saved search"
            filters = _clean_filters(raw.get("filters"))
            notify = raw.get("notify")
            if notify is None:
                notify = True
            auto_saved = _to_bool(raw.get("auto_saved"))

            row = existing.get(public_id) if public_id else None
            if not row:
                row = _find_by_filters(current_user.id, filters)
            if row:
                row.name = name[:200]
                row.filters = filters
                row.notify = bool(notify)
                row.auto_saved = auto_saved
                row.updated_at = utcnow()
                existing[row.public_id] = row
            else:
                if SavedSearch.query.filter_by(user_id=current_user.id).count() >= _MAX_SAVED_SEARCHES:
                    continue
                row = SavedSearch(
                    user_id=current_user.id,
                    name=name[:200],
                    filters=filters,
                    notify=bool(notify),
                    auto_saved=auto_saved,
                )
                if public_id:
                    row.public_id = public_id
                db.session.add(row)
                existing[row.public_id] = row

        db.session.commit()
        rows = (
            SavedSearch.query.filter_by(user_id=current_user.id)
            .order_by(SavedSearch.created_at.desc())
            .limit(_MAX_SAVED_SEARCHES)
            .all()
        )
        return jsonify({"saved_searches": [r.to_dict() for r in rows]}), 200
    except Exception:
        db.session.rollback()
        return jsonify({"message": "Failed to sync saved searches"}), 500
