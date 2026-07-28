from __future__ import annotations

import os
import secrets
from datetime import datetime

from flask import Blueprint, current_app, jsonify, request
from flask_jwt_extended import jwt_required
from werkzeug.utils import safe_join

from ..auth import get_current_user, log_user_action, phone_verification_required_response
from ..media_processing import process_and_store_image
from ..models import Car, CarImage, CarVideo, db
from ..security import generate_secure_filename, validate_file_upload, rate_limit

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


_ALLOWED_IMAGE_CONTENT_TYPES = frozenset(
    {
        "image/jpeg",
        "image/jpg",
        "image/png",
        "image/gif",
        "image/webp",
        "image/heic",
        "image/heif",
    }
)
_ALLOWED_VIDEO_CONTENT_TYPES = frozenset(
    {
        "video/mp4",
        "video/quicktime",
        "video/webm",
        "video/x-matroska",
        "video/x-msvideo",
    }
)
_R2_IMAGE_MAX_BYTES = 25 * 1024 * 1024
_R2_VIDEO_MAX_BYTES = 200 * 1024 * 1024


def _normalize_signed_content_type(raw: str, *, asset: str, default_ct: str) -> str | None:
    ct = (raw or default_ct).strip().lower().split(";")[0].strip()
    allowed = (
        _ALLOWED_VIDEO_CONTENT_TYPES if asset == "video" else _ALLOWED_IMAGE_CONTENT_TYPES
    )
    if ct not in allowed:
        return None
    if ct == "image/jpg":
        return "image/jpeg"
    return ct


def _allowed_attach_media_url(url: str) -> bool:
    """Only allow HTTPS objects under our R2 public base + known key prefixes."""
    u = (url or "").strip()
    if not u.lower().startswith("https://"):
        return False
    public_base = _r2_public_base()
    if not public_base:
        return False
    prefix = public_base.rstrip("/") + "/"
    if not u.startswith(prefix):
        return False
    key = u[len(prefix) :]
    return key.startswith("car_photos/") or key.startswith("car_videos/")


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


def _normalize_car_image_kind(raw) -> str:
    """Return 'damage' or 'listing' for stored CarImage.kind."""
    s = (str(raw or "")).strip().lower()
    return "damage" if s == "damage" else "listing"


def _count_listing_images(car: Car) -> int:
    try:
        return sum(
            1
            for img in car.images
            if _normalize_car_image_kind(getattr(img, "kind", None)) == "listing"
        )
    except Exception:
        return 0


def _pick_primary_listing_url(car: Car):
    """Prefer primary among listing photos; never use damage-only rows as hero."""
    try:
        for img in car.images:
            if (
                getattr(img, "is_primary", False)
                and _normalize_car_image_kind(getattr(img, "kind", None)) == "listing"
            ):
                return img.image_url
        for img in car.images:
            if _normalize_car_image_kind(getattr(img, "kind", None)) == "listing":
                return img.image_url
        return None
    except Exception:
        return None


def _normalize_image_match_key(url: str) -> str:
    """Normalize stored or client image refs for fuzzy equality checks."""
    from urllib.parse import urlparse

    s = (url or "").strip().replace("\\", "/")
    if not s:
        return ""
    if "?" in s:
        s = s.split("?", 1)[0]
    lower = s.lower()
    if lower.startswith("http://") or lower.startswith("https://"):
        s = urlparse(s).path.lstrip("/")
    if s.startswith("/"):
        s = s[1:]
    if s.startswith("static/"):
        s = s[len("static/") :]
    return s.lower()


def _find_listing_image_by_ref(car: Car, image_ref: str):
    """Return a listing CarImage row matching a client path or URL."""
    key = _normalize_image_match_key(image_ref)
    if not key:
        return None
    basename = os.path.basename(key)
    for img in car.images:
        if _normalize_car_image_kind(getattr(img, "kind", None)) != "listing":
            continue
        stored = _normalize_image_match_key(getattr(img, "image_url", "") or "")
        if not stored:
            continue
        if stored == key or stored.endswith("/" + key) or key.endswith("/" + stored):
            return img
        if basename and os.path.basename(stored) == basename:
            return img
    return None


def _set_primary_listing_image(car: Car, image_ref: str):
    """Mark one listing photo as primary; clear primary on other listing photos."""
    target = _find_listing_image_by_ref(car, image_ref)
    if not target:
        return None
    for img in car.images:
        if _normalize_car_image_kind(getattr(img, "kind", None)) != "listing":
            continue
        img.is_primary = img.id == target.id
    return target.image_url


@bp.route("/api/cars/<car_id>/images/primary", methods=["PUT"])
@jwt_required()
def set_car_primary_image(car_id: str):
    """Set which listing photo is the cover / primary image."""
    try:
        current_user = get_current_user()
        verify_err = phone_verification_required_response(current_user)
        if verify_err:
            return verify_err

        car = _get_car_by_any_id(car_id)
        if not car:
            return jsonify({"message": "Car not found"}), 404

        if car.seller_id != current_user.id and not current_user.is_admin:
            return jsonify({"message": "Not authorized to update images for this listing"}), 403

        data = request.get_json(silent=True) or {}
        image_ref = (
            data.get("image_url")
            or data.get("path")
            or data.get("url")
            or ""
        )
        image_ref = str(image_ref).strip()
        if not image_ref:
            return jsonify({"message": "image_url is required"}), 400

        primary_url = _set_primary_listing_image(car, image_ref)
        if not primary_url:
            return jsonify({"message": "Image not found on this listing"}), 404

        db.session.commit()
        log_user_action(current_user, "set_primary_image", "car", car.public_id)

        return jsonify({"message": "Primary image updated", "image_url": primary_url}), 200
    except Exception:
        db.session.rollback()
        return jsonify({"message": "Failed to set primary image"}), 500


@bp.route("/api/cars/<car_id>/images/layout", methods=["PUT"])
@jwt_required()
def update_car_image_layout(car_id: str):
    """Persist ordering and non-destructive vertical crop metadata."""
    try:
        current_user = get_current_user()
        car = _get_car_by_any_id(car_id)
        if not car:
            return jsonify({"message": "Car not found"}), 404
        if car.seller_id != current_user.id and not current_user.is_admin:
            return jsonify({"message": "Not authorized to update images for this listing"}), 403

        data = request.get_json(silent=True) or {}
        rows = data.get("images")
        if not isinstance(rows, list):
            return jsonify({"message": "images must be a list"}), 400

        by_id = {img.id: img for img in car.images}
        updated = []
        requested_primary = None
        for index, raw in enumerate(rows):
            if not isinstance(raw, dict):
                return jsonify({"message": "Each image layout must be an object"}), 400
            try:
                image_id = int(raw.get("id"))
            except (TypeError, ValueError):
                return jsonify({"message": "Each image layout requires a valid id"}), 400
            image = by_id.get(image_id)
            if image is None:
                return jsonify({"message": f"Image {image_id} is not on this listing"}), 400

            focus = raw.get("focus_y")
            if focus is None or focus == "":
                image.focus_y = None
            else:
                try:
                    focus = float(focus)
                except (TypeError, ValueError):
                    return jsonify({"message": "focus_y must be between 0 and 1"}), 400
                if not 0.0 <= focus <= 1.0:
                    return jsonify({"message": "focus_y must be between 0 and 1"}), 400
                image.focus_y = focus

            for field in ("image_width", "image_height"):
                value = raw.get(field)
                if value is not None:
                    try:
                        value = int(value)
                    except (TypeError, ValueError):
                        return jsonify({"message": f"{field} must be a positive integer"}), 400
                    if value <= 0:
                        return jsonify({"message": f"{field} must be a positive integer"}), 400
                    setattr(image, field, value)

            image.order = int(raw.get("order", index))
            if raw.get("is_primary") is True and _normalize_car_image_kind(image.kind) == "listing":
                requested_primary = image.id
            updated.append(image)

        if requested_primary is not None:
            for image in car.images:
                if _normalize_car_image_kind(image.kind) == "listing":
                    image.is_primary = image.id == requested_primary

        db.session.commit()
        return jsonify({"images": [image.to_dict() for image in updated]}), 200
    except Exception:
        db.session.rollback()
        return jsonify({"message": "Failed to update image layout"}), 500


@bp.route("/api/media/r2/sign-upload", methods=["POST"])
@jwt_required()
@rate_limit(max_requests=60, window_minutes=60, per_ip=False)
def r2_sign_upload():
    """
    Return a presigned PUT URL for uploading one file to R2 (image or video).
    Body: { "filename": "photo.jpg", "content_type": "image/jpeg", "asset": "image" | "video" } (optional).
    Response: { "upload_url": "<presigned PUT URL>", "key": "<object key>", "public_url": "<optional public URL>" }.
    """
    try:
        current_user = get_current_user()
        verify_err = phone_verification_required_response(current_user)
        if verify_err:
            return verify_err
    except Exception:
        return jsonify({"message": "Unauthorized"}), 401

    if not _r2_configured():
        return jsonify({"message": "R2 storage is not configured"}), 503

    try:
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
            max_bytes = _R2_VIDEO_MAX_BYTES
        else:
            if ext not in {".jpg", ".jpeg", ".png", ".gif", ".webp", ".heic", ".heif"}:
                ext = ".jpg"
            key = f"car_photos/{secrets.token_hex(8)}{ext}"
            default_ct = "image/jpeg"
            max_bytes = _R2_IMAGE_MAX_BYTES

        content_type = _normalize_signed_content_type(
            data.get("content_type") or "",
            asset=asset,
            default_ct=default_ct,
        )
        if not content_type:
            return jsonify({"message": "Unsupported content_type for this asset"}), 400

        client = _r2_client()
        bucket = current_app.config["R2_BUCKET_NAME"]
        put_params = {
            "Bucket": bucket,
            "Key": key,
            "ContentType": content_type,
        }
        raw_len = data.get("content_length")
        if raw_len is None:
            raw_len = data.get("size")
        if raw_len is not None:
            try:
                claimed = int(raw_len)
            except (TypeError, ValueError):
                return jsonify({"message": "Invalid content_length"}), 400
            if claimed < 1 or claimed > max_bytes:
                return jsonify(
                    {
                        "message": f"content_length must be between 1 and {max_bytes} bytes",
                    }
                ), 400
            put_params["ContentLength"] = claimed

        presigned_url = client.generate_presigned_url(
            "put_object",
            Params=put_params,
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
@rate_limit(max_requests=60, window_minutes=60, per_ip=False)
def upload_car_images(car_id: str):
    """Upload car images (accepts 'files' or 'images') and save them."""
    try:
        current_user = get_current_user()
        verify_err = phone_verification_required_response(current_user)
        if verify_err:
            return verify_err

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
        skip_reasons = []

        # Listing owners already passed auth above. Honor skip_blur=1 from the app for normal
        # uploads (no automatic plate blur). Explicit blur uses /process-car-images or /blur-image.
        skip_param = (request.args.get("skip_blur") or "").strip().lower()
        requested_skip = skip_param in ("1", "true", "yes", "y", "on")
        skip_blur = bool(requested_skip)
        upload_kind = _normalize_car_image_kind(request.args.get("kind"))

        for fs in incoming_files:
            if not fs or not fs.filename:
                skip_reasons.append("Missing filename")
                continue

            is_valid, msg = validate_file_upload(
                fs,
                max_size_mb=25,
                allowed_extensions=current_app.config["ALLOWED_EXTENSIONS"],
            )
            if not is_valid:
                skip_reasons.append(msg or "Invalid file")
                continue

            rel_path, _b64 = process_and_store_image(fs, inline_base64=False, skip_blur=skip_blur)
            listing_n = _count_listing_images(car)
            is_primary = upload_kind == "listing" and listing_n == 0
            car_image = CarImage(
                car_id=car.id,
                image_url=rel_path,
                is_primary=is_primary,
                kind=upload_kind,
            )
            db.session.add(car_image)
            uploaded_images.append(car_image.to_dict())

        db.session.commit()

        if not uploaded_images:
            detail = skip_reasons[0] if skip_reasons else "file type/size"
            return jsonify({"message": f"No valid images were uploaded ({detail})."}), 400

        log_user_action(current_user, "upload_images", "car", car.public_id)

        try:
            primary = _pick_primary_listing_url(car)
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
    except Exception as e:
        db.session.rollback()
        current_app.logger.exception("upload_car_images failed: %s", e)
        err = str(e).strip()
        lower = err.lower()
        if any(
            token in lower
            for token in (
                "too long",
                "stringdatarighttruncation",
                "value too long",
                "varying(200)",
            )
        ):
            return (
                jsonify(
                    {
                        "message": "Image URL is too long for the database. Please try again after the latest update."
                    }
                ),
                500,
            )
        if any(
            token in lower
            for token in (
                "r2",
                "upload_folder",
                "persistence",
                "s3",
                "bucket",
                "storage",
            )
        ):
            return (
                jsonify(
                    {
                        "message": "Image storage is temporarily unavailable. Please try again later."
                    }
                ),
                503,
            )
        return jsonify({"message": "Failed to upload images"}), 500


@bp.route("/api/cars/<car_id>/images/attach", methods=["POST"])
@jwt_required()
def attach_car_images(car_id: str):
    """Attach images by relative paths (uploads/...) or full URLs (e.g. R2 public URL)."""
    try:
        current_user = get_current_user()
        verify_err = phone_verification_required_response(current_user)
        if verify_err:
            return verify_err

        car = _get_car_by_any_id(car_id)
        if not car:
            return jsonify({"message": "Car not found"}), 404

        if car.seller_id != current_user.id and not current_user.is_admin:
            return jsonify({"message": "Not authorized to attach images for this listing"}), 403

        data = request.get_json(silent=True) or {}
        paths = data.get("paths") or data.get("urls") or []
        if not isinstance(paths, list) or not paths:
            return jsonify({"message": "No image paths or URLs provided"}), 400

        attach_kind = _normalize_car_image_kind(data.get("kind"))

        attached = []
        upload_root = os.path.abspath(os.path.join(current_app.root_path, "static", "uploads"))
        for rel in paths:
            try:
                rel_str = str(rel or "").strip().lstrip("/").replace("\\", "/")
                # Full URL (e.g. R2 public URL): store as-is
                if rel_str.lower().startswith("http://") or rel_str.lower().startswith("https://"):
                    if not _allowed_attach_media_url(rel_str):
                        continue
                    listing_n = _count_listing_images(car)
                    is_primary = attach_kind == "listing" and listing_n == 0
                    ci = CarImage(
                        car_id=car.id,
                        image_url=rel_str,
                        is_primary=is_primary,
                        kind=attach_kind,
                    )
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
                listing_n = _count_listing_images(car)
                is_primary = attach_kind == "listing" and listing_n == 0
                ci = CarImage(
                    car_id=car.id,
                    image_url=rel_str,
                    is_primary=is_primary,
                    kind=attach_kind,
                )
                db.session.add(ci)
                attached.append(ci)
            except Exception:
                continue

        db.session.commit()

        try:
            primary = _pick_primary_listing_url(car)
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
@rate_limit(max_requests=20, window_minutes=60, per_ip=False)
def upload_car_videos(car_id: str):
    """Upload car videos"""
    try:
        current_user = get_current_user()
        verify_err = phone_verification_required_response(current_user)
        if verify_err:
            return verify_err

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

