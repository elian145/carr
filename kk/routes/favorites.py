from __future__ import annotations

from flask import Blueprint, jsonify, request
from flask_jwt_extended import jwt_required

from ..auth import get_current_user, log_user_action
from ..models import Car, db, user_favorites

bp = Blueprint("favorites", __name__)


@bp.route("/api/user/favorites", methods=["GET"])
@jwt_required()
def get_favorites():
    """Get user's favorite cars"""
    try:
        current_user = get_current_user()
        if not current_user:
            return jsonify({"message": "User not found"}), 404

        page = request.args.get("page", 1, type=int)
        per_page = request.args.get("per_page", 20, type=int)

        # Order by "favorited at" so newest favorites appear first.
        q = (
            db.session.query(
                Car,
                user_favorites.c.created_at.label("favorited_at"),
            )
            .join(user_favorites, user_favorites.c.car_id == Car.id)
            .filter(user_favorites.c.user_id == current_user.id)
            .order_by(user_favorites.c.created_at.desc())
        )
        pagination = q.paginate(page=page, per_page=per_page, error_out=False)

        cars = []
        for car, fav_at in pagination.items:
            d = car.to_dict()
            if fav_at is not None:
                try:
                    d["favorited_at"] = fav_at.isoformat()
                except Exception:
                    d["favorited_at"] = str(fav_at)
            cars.append(d)

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
        return jsonify({"message": "Failed to get favorites"}), 500


@bp.route("/api/cars/<car_id>/favorite", methods=["GET", "POST"])
@jwt_required()
def toggle_favorite(car_id):
    """Toggle favorite status for a car (POST) or check status (GET)."""
    try:
        current_user = get_current_user()
        if not current_user:
            return jsonify({"message": "User not found"}), 404

        car = Car.query.filter_by(public_id=car_id, is_active=True).first()
        if not car and str(car_id).isdigit():
            car = Car.query.filter_by(id=int(car_id), is_active=True).first()
        if not car:
            return jsonify({"message": "Car not found"}), 404

        if request.method == "GET":
            is_favorited = current_user.favorites.filter_by(id=car.id).first() is not None
            return jsonify({"is_favorited": is_favorited}), 200

        if current_user.favorites.filter_by(id=car.id).first():
            current_user.favorites.remove(car)
            action = "removed"
        else:
            current_user.favorites.append(car)
            action = "added"

        db.session.commit()
        log_user_action(current_user, f"favorite_{action}", "car", car.public_id)

        return jsonify({"message": f"Car {action} from favorites", "is_favorited": action == "added"}), 200

    except Exception:
        return jsonify({"message": "Failed to toggle favorite"}), 500

