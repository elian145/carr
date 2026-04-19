from __future__ import annotations

import json
import os
from datetime import datetime
import secrets

from flask import Blueprint, jsonify, request, current_app
from flask_jwt_extended import jwt_required
from sqlalchemy.orm import selectinload

from ..auth import get_current_user, log_user_action, validate_user_input
from ..models import Car, User, db
from ..security import generate_secure_filename, validate_file_upload
from ..security import validate_input_sanitization
from ..time_utils import utcnow
from .media import _r2_configured, _r2_client, _r2_public_base

bp = Blueprint("user", __name__)


def _to_bool(value) -> bool:
    if isinstance(value, bool):
        return value
    if value is None:
        return False
    return str(value).strip().lower() in {"1", "true", "yes", "on"}


def _clean_phone_list(value) -> list[str]:
    """
    Accepts list/tuple/set of phones or a single string; returns cleaned list.
    This is intentionally lenient (phone formats vary by country).
    """
    if value is None:
        return []
    items = []
    if isinstance(value, (list, tuple, set)):
        items = list(value)
    else:
        items = [value]
    out: list[str] = []
    for x in items:
        s = ("" if x is None else str(x)).strip()
        if not s:
            continue
        out.append(s)
    # Deduplicate while preserving order
    seen = set()
    deduped: list[str] = []
    for p in out:
        if p in seen:
            continue
        seen.add(p)
        deduped.append(p)
    return deduped


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
            phones = _clean_phone_list(data.get("dealership_phones"))
            dealership_phone = (phones[0] if phones else (data.get("dealership_phone") or "")).strip()
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
            try:
                current_user.dealership_phones = phones or ([dealership_phone] if dealership_phone else None)
            except Exception:
                # Older schemas may not have this column; ignore in that case.
                pass
            current_user.dealership_location = dealership_location
        elif "is_dealer" in data and not _to_bool(data.get("is_dealer")):
            if (current_user.dealer_status or "none") == "none":
                current_user.account_type = "user"
                current_user.dealer_status = "none"
                current_user.dealership_name = None
                current_user.dealership_phone = None
                try:
                    current_user.dealership_phones = None
                except Exception:
                    pass
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

        # Prefer Cloudflare R2 when configured; otherwise fall back to local uploads/
        profile_url = None
        try:
            if _r2_configured() and _r2_public_base():
                public_base = _r2_public_base()
                client = _r2_client()
                bucket = current_app.config["R2_BUCKET_NAME"]

                raw_name = (file.filename or "avatar.jpg").strip()
                ext = os.path.splitext(raw_name)[1].lower() or ".jpg"
                if ext not in {".jpg", ".jpeg", ".png", ".webp", ".gif", ".heic", ".heif"}:
                    ext = ".jpg"
                key = f"profile_pictures/{secrets.token_hex(16)}{ext}"

                try:
                    file.stream.seek(0)
                except Exception:
                    try:
                        file.seek(0)
                    except Exception:
                        pass
                body = file.read()
                if not body:
                    return jsonify({"message": "Empty file body"}), 400

                client.put_object(
                    Bucket=bucket,
                    Key=key,
                    Body=body,
                    ContentType=file.mimetype or "image/jpeg",
                )
                profile_url = f"{public_base}/{key}"
        except Exception as e:
            current_app.logger.exception("R2 profile picture upload failed, falling back to local: %s", e)

        if not profile_url:
            filename = generate_secure_filename(file.filename)
            upload_folder = current_app.config["UPLOAD_FOLDER"]
            file_path = os.path.join(upload_folder, "profile_pictures", filename)
            try:
                os.makedirs(os.path.dirname(file_path), exist_ok=True)
            except Exception:
                pass
            file.save(file_path)
            profile_url = f"uploads/profile_pictures/{filename}"

        current_user.profile_picture = profile_url
        current_user.updated_at = utcnow()
        db.session.commit()

        log_user_action(current_user, "profile_picture_upload")

        return jsonify({"message": "Profile picture uploaded successfully", "profile_picture": current_user.profile_picture}), 200

    except Exception:
        return jsonify({"message": "Failed to upload profile picture"}), 500


@bp.route("/api/user/upload-dealer-cover", methods=["POST"])
@jwt_required()
def upload_dealer_cover():
    """Upload dealership cover image shown at top of dealer page."""
    try:
        current_user = get_current_user()
        if not current_user:
            return jsonify({"message": "User not found"}), 404
        if (current_user.account_type or "").strip().lower() != "dealer":
            return jsonify({"message": "Only dealers can upload a dealership cover"}), 403

        if "file" not in request.files:
            return jsonify({"message": "No file provided"}), 400

        file = request.files["file"]
        is_valid, message = validate_file_upload(
            file, max_size_mb=8, allowed_extensions=current_app.config["ALLOWED_EXTENSIONS"]
        )
        if not is_valid:
            return jsonify({"message": message}), 400

        cover_url = None
        try:
            if _r2_configured() and _r2_public_base():
                public_base = _r2_public_base()
                client = _r2_client()
                bucket = current_app.config["R2_BUCKET_NAME"]

                raw_name = (file.filename or "cover.jpg").strip()
                ext = os.path.splitext(raw_name)[1].lower() or ".jpg"
                if ext not in {".jpg", ".jpeg", ".png", ".webp", ".gif", ".heic", ".heif"}:
                    ext = ".jpg"
                key = f"dealer_covers/{secrets.token_hex(16)}{ext}"

                try:
                    file.stream.seek(0)
                except Exception:
                    try:
                        file.seek(0)
                    except Exception:
                        pass
                body = file.read()
                if not body:
                    return jsonify({"message": "Empty file body"}), 400

                client.put_object(
                    Bucket=bucket,
                    Key=key,
                    Body=body,
                    ContentType=file.mimetype or "image/jpeg",
                )
                cover_url = f"{public_base}/{key}"
        except Exception as e:
            current_app.logger.exception("R2 dealer cover upload failed, falling back to local: %s", e)

        if not cover_url:
            filename = generate_secure_filename(file.filename)
            upload_folder = current_app.config["UPLOAD_FOLDER"]
            file_path = os.path.join(upload_folder, "dealer_covers", filename)
            try:
                os.makedirs(os.path.dirname(file_path), exist_ok=True)
            except Exception:
                pass
            file.save(file_path)
            cover_url = f"uploads/dealer_covers/{filename}"

        current_user.dealership_cover_picture = cover_url
        current_user.updated_at = utcnow()
        db.session.commit()
        log_user_action(current_user, "dealer_cover_upload")

        return (
            jsonify(
                {
                    "message": "Dealer cover uploaded successfully",
                    "dealership_cover_picture": current_user.dealership_cover_picture,
                }
            ),
            200,
        )
    except Exception as e:
        current_app.logger.exception("upload_dealer_cover failed: %s", e)
        return jsonify({"message": "Failed to upload dealer cover"}), 500


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


@bp.route("/api/user/dealer-profile", methods=["PUT"])
@jwt_required()
def update_dealer_profile():
    """Dealer-owned editable fields for the public dealer page."""
    try:
        current_user = get_current_user()
        if not current_user:
            return jsonify({"message": "User not found"}), 404

        if (current_user.account_type or "").strip().lower() != "dealer":
            return jsonify({"message": "Only dealers can edit dealer page"}), 403

        data = request.get_json(silent=True) or {}
        data = validate_input_sanitization(data)

        if "dealership_name" in data:
            v = (data.get("dealership_name") or "").strip()
            if not v:
                return jsonify({"message": "Dealership name is required"}), 400
            current_user.dealership_name = v

        # Accept list of phone numbers (preferred) while keeping dealership_phone in sync.
        if "dealership_phones" in data:
            phones = _clean_phone_list(data.get("dealership_phones"))
            if not phones:
                return jsonify({"message": "At least one dealership phone is required"}), 400
            try:
                current_user.dealership_phones = phones
            except Exception:
                # If column doesn't exist, fall back to single phone.
                pass
            current_user.dealership_phone = phones[0]

        # Legacy single-field update. Do NOT overwrite an explicit phones list.
        if "dealership_phone" in data and "dealership_phones" not in data:
            v = (data.get("dealership_phone") or "").strip()
            if not v:
                return jsonify({"message": "Dealership phone is required"}), 400
            current_user.dealership_phone = v
            # Keep list in sync when caller only sends the legacy field.
            try:
                current_user.dealership_phones = _clean_phone_list([v])
            except Exception:
                pass

        if "dealership_location" in data:
            v = (data.get("dealership_location") or "").strip()
            if not v:
                return jsonify({"message": "Dealership location is required"}), 400
            current_user.dealership_location = v

        if "dealership_description" in data:
            v = (data.get("dealership_description") or "").strip()
            current_user.dealership_description = v or None

        if "dealership_opening_hours" in data or "opening_hours" in data:
            raw = data.get("dealership_opening_hours", None)
            if raw is None and "opening_hours" in data:
                raw = data.get("opening_hours")
            if raw is None:
                current_user.dealership_opening_hours = None
            elif isinstance(raw, str):
                # Accept JSON-encoded strings for compatibility with some clients/dialects.
                try:
                    parsed = json.loads(raw)
                except Exception:
                    parsed = None
                if not isinstance(parsed, dict):
                    return jsonify({"message": "Invalid opening hours format"}), 400
                raw = parsed
            elif not isinstance(raw, dict):
                return jsonify({"message": "Invalid opening hours format"}), 400
            else:
                allowed = {"mon", "tue", "wed", "thu", "fri", "sat", "sun"}
                cleaned: dict[str, str] = {}
                for k, v in raw.items():
                    key = (str(k) or "").strip().lower()
                    if key not in allowed:
                        continue
                    val = ("" if v is None else str(v)).strip()
                    if val:
                        cleaned[key] = val
                current_user.dealership_opening_hours = cleaned or None

        if "dealership_latitude" in data and "dealership_longitude" in data:
            raw_lat = data.get("dealership_latitude")
            raw_lng = data.get("dealership_longitude")
            if raw_lat is None and raw_lng is None:
                current_user.dealership_latitude = None
                current_user.dealership_longitude = None
            else:
                try:
                    lat = float(raw_lat)
                    lng = float(raw_lng)
                except (TypeError, ValueError):
                    return jsonify({"message": "Invalid dealership map coordinates"}), 400
                if not (-90.0 <= lat <= 90.0) or not (-180.0 <= lng <= 180.0):
                    return jsonify({"message": "Map coordinates are out of range"}), 400
                current_user.dealership_latitude = lat
                current_user.dealership_longitude = lng

        current_user.updated_at = utcnow()
        db.session.commit()
        log_user_action(current_user, "dealer_profile_update")

        return jsonify({"message": "Dealer page updated", "user": current_user.to_dict(include_private=True)}), 200
    except Exception as e:
        db.session.rollback()
        current_app.logger.exception("update_dealer_profile failed: %s", e)
        return jsonify({"message": "Failed to update dealer page"}), 500

