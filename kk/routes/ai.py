from __future__ import annotations

import os

from flask import Blueprint, Response, abort, current_app, jsonify, request
from flask_jwt_extended import jwt_required

from ..ai_service import car_analysis_service
from ..auth import get_current_user
from ..media_processing import blur_image_bytes, heic_to_jpeg, process_and_store_image
from ..security import generate_secure_filename
from ..tasks.image_tasks import process_car_image_file
from ..config import get_app_env
from ..time_utils import utcnow

bp = Blueprint("ai", __name__)


@bp.route("/api/analyze-car-image", methods=["POST"])
@jwt_required()
def analyze_car_image():
    try:
        current_user = get_current_user()
        if not current_user:
            return jsonify({"error": "User not found"}), 404

        if "image" not in request.files:
            return jsonify({"error": "No image file provided"}), 400
        file = request.files["image"]
        if not file.filename:
            return jsonify({"error": "No image file selected"}), 400

        filename = generate_secure_filename(file.filename)
        timestamp = utcnow().strftime("%Y%m%d_%H%M%S_%f")
        temp_rel = f"temp/ai_{timestamp}_{filename}"
        temp_abs = os.path.join(current_app.config["UPLOAD_FOLDER"], temp_rel)
        os.makedirs(os.path.dirname(temp_abs), exist_ok=True)
        file.save(temp_abs)

        try:
            analysis_result = car_analysis_service.analyze_car_image(temp_abs)
        finally:
            try:
                os.remove(temp_abs)
            except Exception:
                pass

        if isinstance(analysis_result, dict) and analysis_result.get("error"):
            return jsonify({"error": analysis_result["error"]}), 500

        return jsonify({"success": True, "analysis": analysis_result}), 200
    except Exception:
        return jsonify({"error": "Failed to analyze car image"}), 500


@bp.route("/api/blur-image", methods=["POST"])
@jwt_required()
def blur_image():
    """Accept one image, return blurred image bytes (for client-side local replacement)."""
    try:
        file_storage = request.files.get("image")
        if not file_storage or not file_storage.filename:
            return jsonify({"error": "No image file provided"}), 400
        raw_bytes = file_storage.read()
        if not raw_bytes:
            return jsonify({"error": "Empty image"}), 400

        ext = (os.path.splitext(file_storage.filename)[1] or ".jpg").lower()
        if ext in (".heic", ".heif"):
            raw_bytes, converted = heic_to_jpeg(raw_bytes)
            if converted:
                ext = ".jpg"

        out_bytes = blur_image_bytes(raw_bytes, ext, skip_blur=False)
        mime = "image/jpeg" if ext in (".jpg", ".jpeg") else ("image/png" if ext == ".png" else "image/jpeg")
        resp = Response(out_bytes, mimetype=mime)
        resp.headers["Content-Length"] = str(len(out_bytes))
        return resp
    except Exception:
        return jsonify({"error": "Failed to blur image"}), 500


@bp.route("/api/process-car-images-test", methods=["POST"])
@jwt_required()
def process_car_images_test():
    """Dev-only sanity endpoint for multipart processing."""
    if get_app_env() == "production":
        abort(404)
    try:
        files = request.files.getlist("images")
        if not files:
            return jsonify({"error": "No image files provided"}), 400
        if len(files) > 5:
            return jsonify({"error": "Too many files"}), 400
        want_b64 = request.args.get("inline_base64") == "1"
        processed, processed_b64 = [], []
        for fs in files:
            if not fs or not fs.filename:
                continue
            rel, b64 = process_and_store_image(fs, want_b64, skip_blur=False)
            processed.append(rel)
            if want_b64 and b64:
                processed_b64.append(b64)
        return jsonify({"success": True, "processed_images": processed, "processed_images_base64": processed_b64}), 200
    except Exception:
        return jsonify({"error": "Failed to process car images"}), 500


@bp.route("/api/process-car-images", methods=["POST"])
@jwt_required()
def process_car_images():
    try:
        current_user = get_current_user()
        if not current_user:
            return jsonify({"error": "User not found"}), 404

        files = request.files.getlist("images")
        if not files:
            return jsonify({"error": "No image files provided"}), 400

        want_b64 = request.args.get("inline_base64") == "1"

        # Optional async mode: enqueue work to Celery.
        if (request.args.get("async") or "").strip().lower() in ("1", "true", "yes", "on"):
            from uuid import uuid4

            job_ids = []
            for fs in files:
                if not fs or not fs.filename:
                    continue
                filename = generate_secure_filename(fs.filename)
                ts = utcnow().strftime("%Y%m%d_%H%M%S_%f")
                temp_rel = f"temp/celery_{ts}_{uuid4().hex}_{filename}"
                temp_abs = os.path.join(current_app.config["UPLOAD_FOLDER"], temp_rel)
                os.makedirs(os.path.dirname(temp_abs), exist_ok=True)
                fs.save(temp_abs)
                res = process_car_image_file.delay(temp_abs, fs.filename, want_b64, False)
                job_ids.append(res.id)
            if not job_ids:
                return jsonify({"error": "No image files provided"}), 400
            return jsonify({"success": True, "job_ids": job_ids}), 202

        processed, processed_b64 = [], []
        for fs in files:
            if not fs or not fs.filename:
                continue
            rel, b64 = process_and_store_image(fs, want_b64, skip_blur=False)
            processed.append(rel)
            if want_b64 and b64:
                processed_b64.append(b64)

        return jsonify({"success": True, "processed_images": processed, "processed_images_base64": processed_b64}), 200
    except Exception:
        return jsonify({"error": "Failed to process car images"}), 500

