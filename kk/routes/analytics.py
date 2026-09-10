from __future__ import annotations

from flask import Blueprint, current_app, jsonify, request
from flask_jwt_extended import jwt_required
from sqlalchemy.orm import joinedload, selectinload

from ..auth import get_current_user
from ..listing_metrics import (
    _bulk_create_missing_analytics,
    get_car_for_analytics,
    get_or_create_analytics,
    record_call_or_share,
    record_trusted_view,
)
from ..models import Car, ListingAnalytics, db
from ..security import rate_limit, validate_input_sanitization

bp = Blueprint("analytics", __name__)


def _get_car_by_listing_id(listing_id: str):
    return get_car_for_analytics(listing_id)


def _listing_id_from_body() -> str:
    data = validate_input_sanitization(request.get_json(silent=True) or {})
    return str(data.get("listing_id") or data.get("listingId") or "").strip()


@bp.route("/api/analytics/listings", methods=["GET"])
@jwt_required()
def get_listings_analytics():
    """Get analytics for all current user's listings."""
    try:
        current_user = get_current_user()
        if not current_user:
            return jsonify({"message": "Unauthorized"}), 401

        user_cars = Car.query.filter_by(seller_id=current_user.id).all()
        car_ids = [c.id for c in user_cars]
        if not car_ids:
            return jsonify([]), 200

        analytics = ListingAnalytics.query.filter(ListingAnalytics.car_id.in_(car_ids)).all()
        existing = {a.car_id for a in analytics}

        # D-04: build the missing-id list in Python from the already-fetched
        # `existing` set (no extra SELECT per car), then create all of them
        # in one dialect-appropriate INSERT ... ON CONFLICT DO NOTHING
        # statement instead of N per-row get-or-create calls -- preserves
        # the O(1) round-trip shape and the single conditional commit below.
        missing_ids = [c.id for c in user_cars if c.id not in existing]
        if missing_ids:
            _bulk_create_missing_analytics(missing_ids)
            db.session.commit()

        # BE-02: eager-load `car` + `car.images` -- the only relationships
        # `ListingAnalytics.to_dict()` actually reads (via its
        # `first_image_rel_path()` helper) -- so this loop doesn't
        # lazy-load one extra SELECT per row (N+1). `videos`/`seller` are
        # intentionally NOT eager-loaded here: to_dict() never accesses them.
        analytics = (
            ListingAnalytics.query.filter(ListingAnalytics.car_id.in_(car_ids))
            .options(joinedload(ListingAnalytics.car).selectinload(Car.images))
            .all()
        )
        return jsonify([a.to_dict() for a in analytics]), 200
    except Exception as e:
        db.session.rollback()
        current_app.logger.exception("get_listings_analytics failed: %s", e)
        return jsonify({"message": "Failed to get analytics"}), 500


@bp.route("/api/analytics/listings/<listing_id>", methods=["GET"])
@jwt_required()
def get_listing_analytics(listing_id: str):
    """Get analytics for a specific listing (public_id or numeric id)."""
    try:
        current_user = get_current_user()
        if not current_user:
            return jsonify({"message": "Unauthorized"}), 401

        car = _get_car_by_listing_id(listing_id)
        if not car or car.seller_id != current_user.id:
            return jsonify({"message": "Listing not found"}), 404

        a, created = get_or_create_analytics(car)
        if created:
            db.session.commit()
        return jsonify(a.to_dict()), 200
    except Exception as e:
        db.session.rollback()
        current_app.logger.exception("get_listing_analytics failed: %s", e)
        return jsonify({"message": "Failed to get analytics"}), 500


@bp.route("/api/analytics/track/view", methods=["POST"])
@jwt_required()
@rate_limit(max_requests=60, window_minutes=10, per_ip=False)
def track_view():
    """
    Record a listing view.

    Analytics ``views`` increments at most once per authenticated user per listing
    (seller self-views are excluded). Recently-viewed history is still updated.
    """
    listing_id = _listing_id_from_body()
    if not listing_id:
        return jsonify({"message": "listing_id required"}), 400
    try:
        current_user = get_current_user()
        if not current_user:
            return jsonify({"message": "Unauthorized"}), 401
        result = record_trusted_view(current_user, listing_id)
        if not result.get("ok") and result.get("code") == "listing_not_found":
            return jsonify({"message": "Listing not found"}), 404
        return (
            jsonify(
                {
                    "success": True,
                    "counted": bool(result.get("counted")),
                    "code": result.get("code"),
                }
            ),
            200,
        )
    except Exception:
        return jsonify({"message": "Failed to track view"}), 500


@bp.route("/api/analytics/track/message", methods=["POST"])
@jwt_required()
@rate_limit(max_requests=60, window_minutes=10, per_ip=False)
def track_message():
    """
    Client hint only — message metrics are counted on real chat sends.

    Kept for mobile compatibility; does not increment counters.
    """
    listing_id = _listing_id_from_body()
    if not listing_id:
        return jsonify({"message": "listing_id required"}), 400
    car = _get_car_by_listing_id(listing_id)
    if not car or not car.is_active:
        return jsonify({"message": "Listing not found"}), 404
    return jsonify({"success": True, "counted": False, "code": "server_bound"}), 200


@bp.route("/api/analytics/track/call", methods=["POST"])
@jwt_required()
@rate_limit(max_requests=30, window_minutes=10, per_ip=False)
def track_call():
    listing_id = _listing_id_from_body()
    if not listing_id:
        return jsonify({"message": "listing_id required"}), 400
    try:
        current_user = get_current_user()
        if not current_user:
            return jsonify({"message": "Unauthorized"}), 401
        result = record_call_or_share(current_user, listing_id, "calls")
        if not result.get("ok") and result.get("code") == "listing_not_found":
            return jsonify({"message": "Listing not found"}), 404
        return (
            jsonify(
                {
                    "success": True,
                    "counted": bool(result.get("counted")),
                    "code": result.get("code"),
                }
            ),
            200,
        )
    except Exception:
        return jsonify({"message": "Failed to track call"}), 500


@bp.route("/api/analytics/track/share", methods=["POST"])
@jwt_required()
@rate_limit(max_requests=30, window_minutes=10, per_ip=False)
def track_share():
    listing_id = _listing_id_from_body()
    if not listing_id:
        return jsonify({"message": "listing_id required"}), 400
    try:
        current_user = get_current_user()
        if not current_user:
            return jsonify({"message": "Unauthorized"}), 401
        result = record_call_or_share(current_user, listing_id, "shares")
        if not result.get("ok") and result.get("code") == "listing_not_found":
            return jsonify({"message": "Listing not found"}), 404
        return (
            jsonify(
                {
                    "success": True,
                    "counted": bool(result.get("counted")),
                    "code": result.get("code"),
                }
            ),
            200,
        )
    except Exception:
        return jsonify({"message": "Failed to track share"}), 500


@bp.route("/api/analytics/track/favorite", methods=["POST"])
@jwt_required()
@rate_limit(max_requests=60, window_minutes=10, per_ip=False)
def track_favorite():
    """
    Client hint only — favorite metrics are counted on real favorite adds.

    Kept for mobile compatibility; does not increment counters.
    """
    listing_id = _listing_id_from_body()
    if not listing_id:
        return jsonify({"message": "listing_id required"}), 400
    car = _get_car_by_listing_id(listing_id)
    if not car or not car.is_active:
        return jsonify({"message": "Listing not found"}), 404
    return jsonify({"success": True, "counted": False, "code": "server_bound"}), 200

_ALLOWED_PRODUCT_EVENTS = frozenset(
    {
        "signup",
        "listing_created",
        "search",
        "login",
    }
)


@bp.route("/api/analytics/events", methods=["POST"])
@rate_limit(max_requests=120, window_minutes=10)
def track_product_event():
    """Lightweight product analytics (sign-up, listing created, search, login)."""
    from flask import current_app
    from flask_jwt_extended import verify_jwt_in_request

    from ..auth import log_user_action

    data = validate_input_sanitization(request.get_json(silent=True) or {})
    event = str(data.get("event") or data.get("name") or "").strip().lower()
    if event not in _ALLOWED_PRODUCT_EVENTS:
        return jsonify({"message": "Unsupported event"}), 400

    meta = data.get("metadata") if isinstance(data.get("metadata"), dict) else {}
    safe_meta = {str(k)[:64]: str(v)[:256] for k, v in list(meta.items())[:20]}

    current_user = None
    try:
        verify_jwt_in_request(optional=True)
        current_user = get_current_user()
    except Exception:
        current_user = None

    if current_user:
        log_user_action(
            current_user,
            f"product_{event}",
            metadata=safe_meta or None,
        )
    else:
        current_app.logger.info(
            "product_event event=%s meta=%s",
            event,
            safe_meta,
        )

    return jsonify({"success": True}), 200
