from __future__ import annotations

from datetime import datetime

from flask import Blueprint, jsonify, request
from flask_jwt_extended import jwt_required
from sqlalchemy import update

from ..auth import get_current_user
from ..models import Car, ListingAnalytics, db, user_viewed_listings
from ..security import rate_limit, validate_input_sanitization
from ..time_utils import utcnow

bp = Blueprint("analytics", __name__)


def _get_car_by_listing_id(listing_id: str):
    lid = (listing_id or "").strip()
    if not lid:
        return None
    car = Car.query.filter_by(public_id=lid).first()
    if car:
        return car
    if lid.isdigit():
        try:
            return Car.query.filter_by(id=int(lid)).first()
        except Exception:
            return None
    return None


def _get_or_create_analytics(car: Car) -> ListingAnalytics:
    a = ListingAnalytics.query.filter_by(car_id=car.id).first()
    if a:
        return a
    a = ListingAnalytics(car_id=car.id)
    db.session.add(a)
    db.session.commit()
    return a


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


def _track_increment(listing_id: str, field: str, *, dedupe_view: bool = False):
    """
    Increment an analytics field for a listing.

    This is used by the mobile client to record events like views/messages/calls/shares/favorites.
    """
    current_user = get_current_user()
    if not current_user:
        return jsonify({"message": "Unauthorized"}), 401

    car = _get_car_by_listing_id(listing_id)
    if not car or not car.is_active:
        return jsonify({"message": "Listing not found"}), 404

    # Optional: dedupe views per user per listing (prevents spam).
    if dedupe_view:
        exists = db.session.execute(
            user_viewed_listings.select()
            .with_only_columns(user_viewed_listings.c.user_id)
            .where(
                user_viewed_listings.c.user_id == current_user.id,
                user_viewed_listings.c.car_id == car.id,
            )
        ).first()
        if exists:
            return jsonify({"success": True, "deduped": True}), 200
        db.session.execute(
            user_viewed_listings.insert().values(
                user_id=current_user.id,
                car_id=car.id,
                viewed_at=utcnow(),
            )
        )

    a = ListingAnalytics.query.filter_by(car_id=car.id).first()
    if not a:
        a = ListingAnalytics(car_id=car.id)
        db.session.add(a)
        db.session.flush()

    col = getattr(ListingAnalytics, field, None)
    if col is None:
        return jsonify({"message": "Unsupported metric"}), 400

    db.session.execute(
        update(ListingAnalytics)
        .where(ListingAnalytics.car_id == car.id)
        .values(**{field: col + 1})
    )
    db.session.commit()
    return jsonify({"success": True}), 200


@bp.route("/api/analytics/track/view", methods=["POST"])
@jwt_required()
@rate_limit(max_requests=120, window_minutes=10, per_ip=False)
def track_view():
    data = validate_input_sanitization(request.get_json(silent=True) or {})
    listing_id = str(data.get("listing_id") or data.get("listingId") or "").strip()
    if not listing_id:
        return jsonify({"message": "listing_id required"}), 400
    try:
        return _track_increment(listing_id, "views", dedupe_view=True)
    except Exception:
        return jsonify({"message": "Failed to track view"}), 500


@bp.route("/api/analytics/track/message", methods=["POST"])
@jwt_required()
@rate_limit(max_requests=300, window_minutes=10, per_ip=False)
def track_message():
    data = validate_input_sanitization(request.get_json(silent=True) or {})
    listing_id = str(data.get("listing_id") or data.get("listingId") or "").strip()
    if not listing_id:
        return jsonify({"message": "listing_id required"}), 400
    try:
        return _track_increment(listing_id, "messages")
    except Exception:
        return jsonify({"message": "Failed to track message"}), 500


@bp.route("/api/analytics/track/call", methods=["POST"])
@jwt_required()
@rate_limit(max_requests=300, window_minutes=10, per_ip=False)
def track_call():
    data = validate_input_sanitization(request.get_json(silent=True) or {})
    listing_id = str(data.get("listing_id") or data.get("listingId") or "").strip()
    if not listing_id:
        return jsonify({"message": "listing_id required"}), 400
    try:
        return _track_increment(listing_id, "calls")
    except Exception:
        return jsonify({"message": "Failed to track call"}), 500


@bp.route("/api/analytics/track/share", methods=["POST"])
@jwt_required()
@rate_limit(max_requests=300, window_minutes=10, per_ip=False)
def track_share():
    data = validate_input_sanitization(request.get_json(silent=True) or {})
    listing_id = str(data.get("listing_id") or data.get("listingId") or "").strip()
    if not listing_id:
        return jsonify({"message": "listing_id required"}), 400
    try:
        return _track_increment(listing_id, "shares")
    except Exception:
        return jsonify({"message": "Failed to track share"}), 500


@bp.route("/api/analytics/track/favorite", methods=["POST"])
@jwt_required()
@rate_limit(max_requests=300, window_minutes=10, per_ip=False)
def track_favorite():
    data = validate_input_sanitization(request.get_json(silent=True) or {})
    listing_id = str(data.get("listing_id") or data.get("listingId") or "").strip()
    if not listing_id:
        return jsonify({"message": "listing_id required"}), 400
    try:
        return _track_increment(listing_id, "favorites")
    except Exception:
        return jsonify({"message": "Failed to track favorite"}), 500

