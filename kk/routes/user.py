from __future__ import annotations

import os
from datetime import datetime

from flask import Blueprint, jsonify, request, current_app
from flask_jwt_extended import jwt_required
from sqlalchemy.orm import selectinload

from ..auth import get_current_user, log_user_action, validate_user_input
from ..models import Car, User, db
from ..security import generate_secure_filename, validate_file_upload
from ..time_utils import utcnow

bp = Blueprint("user", __name__)


def _to_bool(value) -> bool:
    if isinstance(value, bool):
        return value
    if value is None:
        return False
    return str(value).strip().lower() in {"1", "true", "yes", "on"}


@bp.route("/api/user/profile", methods=["GET"])
@jwt_required()
def get_profile():
    """Get user profile"""
    try:
        current_user = get_current_user()
        if not current_user:
            return jsonify({"message": "User not found"}), 404

        return jsonify({"user": current_user.to_dict(include_private=True)}), 200

    except Exception:
        return jsonify({"message": "Failed to get profile"}), 500


@bp.route("/api/user/profile", methods=["PUT"])
@jwt_required()
def update_profile():
    """Update user profile"""
    try:
        current_user = get_current_user()
        if not current_user:
            return jsonify({"message": "User not found"}), 404

        data = request.get_json()

        errors = validate_user_input(data)
        if errors:
            return jsonify({"message": "Validation failed", "errors": errors}), 400

        if "first_name" in data:
            current_user.first_name = data["first_name"]
        if "last_name" in data:
            current_user.last_name = data["last_name"]
        if "phone_number" in data:
            current_user.phone_number = data["phone_number"]
        if "username" in data and data["username"] != current_user.username:
            new_username = (data["username"] or "").strip()
            if not new_username:
                return jsonify({"message": "Username is required"}), 400
            existing = User.query.filter_by(username=new_username).first()
            if existing and existing.id != current_user.id:
                return jsonify({"message": "Username already exists"}), 400
            current_user.username = new_username
        if "email" in data and data["email"] != current_user.email:
            if User.query.filter_by(email=data["email"]).first():
                return jsonify({"message": "Email already exists"}), 400
            current_user.email = data["email"]
            current_user.is_verified = False

        # Dealer request flow: keep account_type as user until admin approval.
        if _to_bool(data.get("is_dealer")):
            dealership_name = (data.get("dealership_name") or "").strip()
            dealership_phone = (data.get("dealership_phone") or "").strip()
            dealership_location = (data.get("dealership_location") or "").strip()
            if not dealership_name:
                return jsonify({"message": "Dealership name is required for dealer accounts"}), 400
            if not dealership_phone:
                return jsonify({"message": "Dealership phone is required for dealer accounts"}), 400
            if not dealership_location:
                return jsonify({"message": "Dealership location is required for dealer accounts"}), 400
            current_user.account_type = "user"
            current_user.dealer_status = "pending"
            current_user.dealership_name = dealership_name
            current_user.dealership_phone = dealership_phone
            current_user.dealership_location = dealership_location
        elif "is_dealer" in data and not _to_bool(data.get("is_dealer")):
            if (current_user.dealer_status or "none") == "none":
                current_user.account_type = "user"
                current_user.dealer_status = "none"
                current_user.dealership_name = None
                current_user.dealership_phone = None
                current_user.dealership_location = None

        current_user.updated_at = utcnow()
        db.session.commit()

        log_user_action(current_user, "profile_update")

        return jsonify({"message": "Profile updated successfully", "user": current_user.to_dict(include_private=True)}), 200

    except Exception:
        return jsonify({"message": "Failed to update profile"}), 500


@bp.route("/api/user/upload-profile-picture", methods=["POST"])
@jwt_required()
def upload_profile_picture():
    """Upload profile picture"""
    try:
        current_user = get_current_user()
        if not current_user:
            return jsonify({"message": "User not found"}), 404

        if "file" not in request.files:
            return jsonify({"message": "No file provided"}), 400

        file = request.files["file"]

        is_valid, message = validate_file_upload(
            file, max_size_mb=5, allowed_extensions=current_app.config["ALLOWED_EXTENSIONS"]
        )

        if not is_valid:
            return jsonify({"message": message}), 400

        filename = generate_secure_filename(file.filename)
        upload_folder = current_app.config["UPLOAD_FOLDER"]
        file_path = os.path.join(upload_folder, "profile_pictures", filename)

        file.save(file_path)

        current_user.profile_picture = f"uploads/profile_pictures/{filename}"
        current_user.updated_at = utcnow()
        db.session.commit()

        log_user_action(current_user, "profile_picture_upload")

        return jsonify({"message": "Profile picture uploaded successfully", "profile_picture": current_user.profile_picture}), 200

    except Exception:
        return jsonify({"message": "Failed to upload profile picture"}), 500


@bp.route("/api/dealers/<dealer_public_id>", methods=["GET"])
def dealer_profile(dealer_public_id: str):
    """Public dealer profile + active listings for dealer page."""
    try:
        pid = (dealer_public_id or "").strip()
        if not pid:
            return jsonify({"message": "Dealer id is required"}), 400

        dealer = User.query.filter_by(public_id=pid).first()
        if not dealer:
            return jsonify({"message": "Dealer not found"}), 404

        if (dealer.account_type or "").strip().lower() != "dealer":
            return jsonify({"message": "This seller is not a dealer"}), 400

        listings = (
            Car.query.filter_by(seller_id=dealer.id, is_active=True)
            .options(selectinload(Car.images), selectinload(Car.videos))
            .order_by(Car.is_featured.desc(), Car.created_at.desc())
            .all()
        )

        listing_dicts = []
        for car in listings:
            item = car.to_dict()
            if not item.get("image_url"):
                imgs = item.get("images") or []
                if isinstance(imgs, list) and imgs:
                    first = imgs[0] or {}
                    if isinstance(first, dict):
                        item["image_url"] = first.get("image_url")
            listing_dicts.append(item)

        stats = {
            "total_listings": len(listing_dicts),
            "featured_listings": sum(1 for c in listing_dicts if c.get("is_featured") is True),
        }

        return jsonify({"dealer": dealer.to_dict(), "listings": listing_dicts, "stats": stats}), 200
    except Exception as e:
        current_app.logger.exception("dealer_profile failed: %s", e)
        return jsonify({"message": "Failed to load dealer profile"}), 500

