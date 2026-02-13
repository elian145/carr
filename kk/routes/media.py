from __future__ import annotations

import os
from datetime import datetime

from flask import Blueprint, current_app, jsonify, request
from flask_jwt_extended import jwt_required
from werkzeug.utils import safe_join

from ..auth import get_current_user, log_user_action
from ..media_processing import process_and_store_image
from ..models import Car, CarImage, CarVideo, db
from ..security import generate_secure_filename, validate_file_upload

bp = Blueprint("media", __name__)


def _get_car_by_any_id(car_id: str):
    car = Car.query.filter_by(public_id=car_id).first()
    if not car and str(car_id).isdigit():
        try:
            car = Car.query.filter_by(id=int(car_id)).first()
        except Exception:
            car = None
    return car


@bp.route("/api/cars/<car_id>/images", methods=["POST"])
@jwt_required()
def upload_car_images(car_id: str):
    """Upload car images (accepts 'files' or 'images') and save them."""
    try:
        current_user = get_current_user()
        if not current_user:
            return jsonify({"message": "User not found"}), 404

        car = _get_car_by_any_id(car_id)
        if not car:
            return jsonify({"message": "Car not found"}), 404

        if car.seller_id != current_user.id and not current_user.is_admin:
            return jsonify({"message": "Not authorized to upload images for this listing"}), 403

        incoming_files = []
        for key in ("files", "images", "image", "upload", "file", "photo", "photos"):
            if key in request.files:
                incoming_files.extend(request.files.getlist(key))
        if not incoming_files:
            return jsonify({"message": "No image files provided"}), 400

        uploaded_images = []

        # Privacy by default: blur plates unless explicitly skipped in dev/admin flows.
        # - Production: ignore skip_blur unless admin.
        # - Development/testing: allow skip_blur for faster iteration.
        from ..config import get_app_env

        env_name = get_app_env()
        skip_param = (request.args.get("skip_blur") or "").strip().lower()
        requested_skip = skip_param in ("1", "true", "yes", "y", "on")
        skip_blur = False
        if requested_skip and (env_name in ("development", "testing") or getattr(current_user, "is_admin", False)):
            skip_blur = True

        for fs in incoming_files:
            if not fs or not fs.filename:
                continue

            is_valid, _msg = validate_file_upload(
                fs,
                max_size_mb=25,
                allowed_extensions=current_app.config["ALLOWED_EXTENSIONS"],
            )
            if not is_valid:
                continue

            rel_path, _b64 = process_and_store_image(fs, inline_base64=False, skip_blur=skip_blur)
            car_image = CarImage(
                car_id=car.id,
                image_url=rel_path,
                is_primary=len(car.images) == 0,
            )
            db.session.add(car_image)
            uploaded_images.append(car_image.to_dict())

        db.session.commit()

        if not uploaded_images:
            return jsonify({"message": "No valid images were uploaded (file type/size)."}), 400

        log_user_action(current_user, "upload_images", "car", car.public_id)

        try:
            primary = next((img.image_url for img in car.images if getattr(img, "is_primary", False)), None)
            if not primary and car.images:
                primary = car.images[0].image_url
        except Exception:
            primary = None

        return (
            jsonify(
                {
                    "message": f"{len(uploaded_images)} images uploaded successfully",
                    "images": [ci for ci in uploaded_images],
                    "image_url": primary or (uploaded_images[0]["image_url"] if uploaded_images else ""),
                }
            ),
            201,
        )
    except Exception:
        db.session.rollback()
        return jsonify({"message": "Failed to upload images"}), 500


@bp.route("/api/cars/<car_id>/images/attach", methods=["POST"])
@jwt_required()
def attach_car_images(car_id: str):
    """Attach already-processed images by relative paths without re-uploading/saving files."""
    try:
        current_user = get_current_user()
        if not current_user:
            return jsonify({"message": "User not found"}), 404

        car = _get_car_by_any_id(car_id)
        if not car:
            return jsonify({"message": "Car not found"}), 404

        if car.seller_id != current_user.id and not current_user.is_admin:
            return jsonify({"message": "Not authorized to attach images for this listing"}), 403

        data = request.get_json(silent=True) or {}
        paths = data.get("paths") or []
        if not isinstance(paths, list) or not paths:
            return jsonify({"message": "No image paths provided"}), 400

        attached = []
        upload_root = os.path.abspath(os.path.join(current_app.root_path, "static", "uploads"))
        for rel in paths:
            try:
                rel_str = str(rel or "").strip().lstrip("/").replace("\\", "/")
                if not rel_str.lower().startswith("uploads/"):
                    continue
                subpath = os.path.relpath(rel_str, "uploads").replace("\\", "/")
                abs_path = safe_join(upload_root, subpath)
                if not abs_path:
                    continue
                abs_path = os.path.abspath(abs_path)
                if not abs_path.startswith(upload_root + os.sep):
                    continue
                if not os.path.isfile(abs_path):
                    continue
                rel_str = f"uploads/{subpath}".replace("\\", "/")
                ci = CarImage(car_id=car.id, image_url=rel_str, is_primary=len(car.images) == 0)
                db.session.add(ci)
                attached.append(ci)
            except Exception:
                continue

        db.session.commit()

        try:
            primary = next((img.image_url for img in car.images if getattr(img, "is_primary", False)), None)
            if not primary and car.images:
                primary = car.images[0].image_url
        except Exception:
            primary = None

        return (
            jsonify(
                {
                    "message": f"{len(attached)} images attached successfully",
                    "images": [ci.to_dict() for ci in attached],
                    "image_url": primary or ((attached[0].image_url) if attached else ""),
                }
            ),
            201,
        )
    except Exception:
        db.session.rollback()
        return jsonify({"message": "Failed to attach images"}), 500


@bp.route("/api/cars/<car_id>/videos", methods=["POST"])
@jwt_required()
def upload_car_videos(car_id: str):
    """Upload car videos"""
    try:
        current_user = get_current_user()
        if not current_user:
            return jsonify({"message": "User not found"}), 404

        car = _get_car_by_any_id(car_id)
        if not car:
            return jsonify({"message": "Car not found"}), 404

        if car.seller_id != current_user.id and not current_user.is_admin:
            return jsonify({"message": "Not authorized to upload videos for this listing"}), 403

        if "files" not in request.files:
            return jsonify({"message": "No files provided"}), 400

        files = request.files.getlist("files")
        uploaded_videos = []

        for f in files:
            if not f or not f.filename:
                continue
            is_valid, _msg = validate_file_upload(
                f,
                max_size_mb=100,
                allowed_extensions=current_app.config["ALLOWED_VIDEO_EXTENSIONS"],
            )
            if not is_valid:
                continue

            filename = generate_secure_filename(f.filename)
            file_path = os.path.join(current_app.config["UPLOAD_FOLDER"], "car_videos", filename)
            os.makedirs(os.path.dirname(file_path), exist_ok=True)
            f.save(file_path)

            car_video = CarVideo(car_id=car.id, video_url=f"uploads/car_videos/{filename}")
            db.session.add(car_video)
            uploaded_videos.append(car_video.to_dict())

        db.session.commit()
        log_user_action(current_user, "upload_videos", "car", car.public_id)

        return jsonify({"message": f"{len(uploaded_videos)} videos uploaded successfully", "videos": uploaded_videos}), 201
    except Exception:
        db.session.rollback()
        return jsonify({"message": "Failed to upload videos"}), 500

