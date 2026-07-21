from __future__ import annotations

from flask import Blueprint, jsonify, request
from flask_jwt_extended import jwt_required

from ..auth import get_current_user
from ..listing_metrics import (
    get_car_for_analytics,
    record_call_or_share,
    record_trusted_view,
)
from ..models import Car, ListingAnalytics, db
from ..security import rate_limit, validate_input_sanitization

bp = Blueprint("analytics", __name__)


def _get_car_by_listing_id(listing_id: str):
    return get_car_for_analytics(listing_id)


def _get_or_create_analytics(car: Car) -> ListingAnalytics:
    a = ListingAnalytics.query.filter_by(car_id=car.id).first()
    if a:
        return a
    a = ListingAnalytics(car_id=car.id)
    db.session.add(a)
    db.session.commit()
    return a


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

        created_any = False
        for c in user_cars:
            if c.id not in existing:
                db.session.add(ListingAnalytics(car_id=c.id))
                created_any = True
        if created_any:
            db.session.commit()

        analytics = ListingAnalytics.query.filter(ListingAnalytics.car_id.in_(car_ids)).all()
        return jsonify([a.to_dict() for a in analytics]), 200
    except Exception:
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

        a = _get_or_create_analytics(car)
        return jsonify(a.to_dict()), 200
    except Exception:
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
