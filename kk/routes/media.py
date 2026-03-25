from __future__ import annotations

import os
import secrets
from datetime import datetime

from flask import Blueprint, current_app, jsonify, request
from flask_jwt_extended import jwt_required
from werkzeug.utils import safe_join

from ..auth import get_current_user, log_user_action
from ..media_processing import process_and_store_image
from ..models import Car, CarImage, CarVideo, db
from ..security import generate_secure_filename, validate_file_upload

bp = Blueprint("media", __name__)


def _r2_configured() -> bool:
    """True if R2 is configured (account + bucket + credentials)."""
    c = current_app.config
    return bool(
        c.get("R2_ACCOUNT_ID")
        and c.get("R2_BUCKET_NAME")
        and c.get("R2_ACCESS_KEY_ID")
        and c.get("R2_SECRET_ACCESS_KEY")
    )


def _r2_client():
    """S3-compatible client for Cloudflare R2."""
    import boto3
    from botocore.config import Config

    c = current_app.config
    account_id = c["R2_ACCOUNT_ID"]
    region = (os.environ.get("R2_REGION") or "auto").strip() or "auto"
    endpoint = f"https://{account_id}.r2.cloudflarestorage.com"
    return boto3.client(
        "s3",
        region_name=region,
        endpoint_url=endpoint,
        aws_access_key_id=c["R2_ACCESS_KEY_ID"],
        aws_secret_access_key=c["R2_SECRET_ACCESS_KEY"],
        config=Config(signature_version="s3v4"),
    )


def _r2_public_base() -> str:
    return (current_app.config.get("R2_PUBLIC_URL") or "").strip().rstrip("/")


def _r2_ready_for_public_object_urls() -> bool:
    """Upload objects to R2 and expose them via R2_PUBLIC_URL (custom domain or r2.dev)."""
    return _r2_configured() and bool(_r2_public_base())


def _video_content_type_for_ext(ext: str) -> str:
    ext = (ext or "").lower()
    if not ext.startswith("."):
        ext = "." + ext
    return {
        ".mp4": "video/mp4",
        ".mov": "video/quicktime",
        ".webm": "video/webm",
        ".mkv": "video/x-matroska",
        ".avi": "video/x-msvideo",
    }.get(ext, "application/octet-stream")


def _upload_video_file_to_r2(file_storage) -> str:
    """
    Read validated multipart file, put to R2, return public HTTPS URL for DB storage.
    Caller must ensure stream is at position 0 or call seek(0) after validation.
    """
    public_base = _r2_public_base()
    if not public_base:
        raise RuntimeError("R2_PUBLIC_URL is not set")

    raw_name = (file_storage.filename or "video.mp4").strip()
    ext = os.path.splitext(raw_name)[1].lower() or ".mp4"
    if ext not in (".mp4", ".mov", ".avi", ".mkv", ".webm"):
        ext = ".mp4"
    key = f"car_videos/{secrets.token_hex(16)}{ext}"

    try:
        file_storage.seek(0)
    except Exception:
        pass
    body = file_storage.read()
    if not body:
        raise RuntimeError("Empty file body")

    client = _r2_client()
    bucket = current_app.config["R2_BUCKET_NAME"]
    ct = _video_content_type_for_ext(ext)
    client.put_object(
        Bucket=bucket,
        Key=key,
        Body=body,
        ContentType=ct,
    )
    return f"{public_base}/{key}"


def _get_car_by_any_id(car_id: str):
    car = Car.query.filter_by(public_id=car_id).first()
    if not car and str(car_id).isdigit():
        try:
            car = Car.query.filter_by(id=int(car_id)).first()
        except Exception:
            car = None
    return car


@bp.route("/api/media/r2/sign-upload", methods=["POST"])
@jwt_required()
def r2_sign_upload():
    """
    Return a presigned PUT URL for uploading one file to R2 (image or video).
    Body: { "filename": "photo.jpg", "content_type": "image/jpeg", "asset": "image" | "video" } (optional).
    Response: { "upload_url": "<presigned PUT URL>", "key": "<object key>", "public_url": "<optional public URL>" }.
    """
    if not _r2_configured():
        return jsonify({"message": "R2 storage is not configured"}), 503

    try:
        current_user = get_current_user()
        if not current_user:
            return jsonify({"message": "User not found"}), 404

        data = request.get_json(silent=True) or {}
        asset = (data.get("asset") or "image").strip().lower()
        raw_name = (data.get("filename") or data.get("name") or "").strip()
        if not raw_name or "/" in raw_name or "\\" in raw_name:
            raw_name = "image.jpg" if asset != "video" else "clip.mp4"
        ext = os.path.splitext(raw_name)[1].lower()

        if asset == "video":
            if ext not in {".mp4", ".mov", ".avi", ".mkv", ".webm"}:
                ext = ".mp4"
            key = f"car_videos/{secrets.token_hex(8)}{ext}"
            default_ct = _video_content_type_for_ext(ext)
            content_type = (data.get("content_type") or default_ct).strip() or default_ct
        else:
            if ext not in {".jpg", ".jpeg", ".png", ".gif", ".webp", ".heic", ".heif"}:
                ext = ".jpg"
            key = f"car_photos/{secrets.token_hex(8)}{ext}"
            content_type = (data.get("content_type") or "image/jpeg").strip() or "image/jpeg"

        client = _r2_client()
        bucket = current_app.config["R2_BUCKET_NAME"]

        presigned_url = client.generate_presigned_url(
            "put_object",
            Params={"Bucket": bucket, "Key": key, "ContentType": content_type},
            ExpiresIn=900,
        )

        out = {"upload_url": presigned_url, "key": key}
        public_base = (current_app.config.get("R2_PUBLIC_URL") or "").strip()
        if public_base:
            out["public_url"] = f"{public_base.rstrip('/')}/{key}"
        return jsonify(out), 200
    except Exception as e:
        current_app.logger.warning("R2 sign-upload failed: %s", e)
        return jsonify({"message": "Failed to generate upload URL"}), 500


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

        # Listing owners already passed auth above. Honor skip_blur=1 from the app for normal
        # uploads (no automatic plate blur). Explicit blur uses /process-car-images or /blur-image.
        skip_param = (request.args.get("skip_blur") or "").strip().lower()
        requested_skip = skip_param in ("1", "true", "yes", "y", "on")
        skip_blur = bool(requested_skip)

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
    """Attach images by relative paths (uploads/...) or full URLs (e.g. R2 public URL)."""
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
        paths = data.get("paths") or data.get("urls") or []
        if not isinstance(paths, list) or not paths:
            return jsonify({"message": "No image paths or URLs provided"}), 400

        attached = []
        upload_root = os.path.abspath(os.path.join(current_app.root_path, "static", "uploads"))
        for rel in paths:
            try:
                rel_str = str(rel or "").strip().lstrip("/").replace("\\", "/")
                # Full URL (e.g. R2 public URL): store as-is
                if rel_str.lower().startswith("http://") or rel_str.lower().startswith("https://"):
                    ci = CarImage(car_id=car.id, image_url=rel_str, is_primary=len(car.images) == 0)
                    db.session.add(ci)
                    attached.append(ci)
                    continue
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
        rejected = []

        for f in files:
            if not f or not f.filename:
                continue
            # Some mobile pickers provide filenames without extension.
            # Infer a safe extension from MIME type so validation can pass.
            if "." not in f.filename:
                mt = (getattr(f, "mimetype", "") or "").lower()
                inferred = ""
                if "mp4" in mt:
                    inferred = ".mp4"
                elif "quicktime" in mt or "mov" in mt:
                    inferred = ".mov"
                elif "webm" in mt:
                    inferred = ".webm"
                elif "x-matroska" in mt or "mkv" in mt:
                    inferred = ".mkv"
                elif "avi" in mt:
                    inferred = ".avi"
                if inferred:
                    f.filename = f"{f.filename}{inferred}"
            is_valid, msg = validate_file_upload(
                f,
                max_size_mb=100,
                allowed_extensions=current_app.config["ALLOWED_VIDEO_EXTENSIONS"],
            )
            if not is_valid:
                rejected.append({"filename": f.filename, "reason": msg})
                continue

            if _r2_ready_for_public_object_urls():
                try:
                    stored_url = _upload_video_file_to_r2(f)
                except Exception as e:
                    current_app.logger.exception("R2 video upload failed: %s", e)
                    rejected.append(
                        {"filename": f.filename, "reason": f"R2 upload failed: {e!s}"}
                    )
                    continue
                car_video = CarVideo(car_id=car.id, video_url=stored_url)
            else:
                filename = generate_secure_filename(f.filename)
                file_path = os.path.join(
                    current_app.config["UPLOAD_FOLDER"], "car_videos", filename
                )
                os.makedirs(os.path.dirname(file_path), exist_ok=True)
                f.save(file_path)
                car_video = CarVideo(
                    car_id=car.id, video_url=f"uploads/car_videos/{filename}"
                )

            db.session.add(car_video)
            uploaded_videos.append(car_video.to_dict())

        if not uploaded_videos:
            db.session.rollback()
            detail = rejected[0]["reason"] if rejected else "No valid videos uploaded"
            return jsonify({"message": detail, "videos": [], "rejected": rejected}), 400

        db.session.commit()
        log_user_action(current_user, "upload_videos", "car", car.public_id)

        return jsonify(
            {
                "message": f"{len(uploaded_videos)} videos uploaded successfully",
                "videos": uploaded_videos,
                "rejected": rejected,
            }
        ), 201
    except Exception:
        db.session.rollback()
        return jsonify({"message": "Failed to upload videos"}), 500

