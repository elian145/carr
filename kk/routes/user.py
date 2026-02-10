from __future__ import annotations

import os
from datetime import datetime

from flask import Blueprint, jsonify, request, current_app
from flask_jwt_extended import jwt_required

from ..auth import get_current_user, log_user_action, validate_user_input
from ..models import User, db
from ..security import generate_secure_filename, validate_file_upload

bp = Blueprint("user", __name__)


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
        if "email" in data and data["email"] != current_user.email:
            if User.query.filter_by(email=data["email"]).first():
                return jsonify({"message": "Email already exists"}), 400
            current_user.email = data["email"]
            current_user.is_verified = False

        current_user.updated_at = datetime.utcnow()
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
        current_user.updated_at = datetime.utcnow()
        db.session.commit()

        log_user_action(current_user, "profile_picture_upload")

        return jsonify({"message": "Profile picture uploaded successfully", "profile_picture": current_user.profile_picture}), 200

    except Exception:
        return jsonify({"message": "Failed to upload profile picture"}), 500

