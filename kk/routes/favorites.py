from __future__ import annotations

from flask import Blueprint, jsonify, request
from flask_jwt_extended import jwt_required

from ..auth import get_current_user, log_user_action
from ..models import Car, db

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

        pagination = current_user.favorites.paginate(page=page, per_page=per_page, error_out=False)
        cars = [car.to_dict() for car in pagination.items]

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

