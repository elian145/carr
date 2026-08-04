from __future__ import annotations

import json
import os
import hashlib
import hmac
import re
from datetime import datetime, timedelta
import secrets

from flask import Blueprint, jsonify, request, current_app
from flask_jwt_extended import jwt_required
from sqlalchemy import or_
from sqlalchemy.orm import selectinload

from ..auth import get_current_user, log_user_action, validate_user_input
from ..models import (
    Car,
    DealerApplication,
    DealerDecision,
    DealerProfile,
    Notification,
    User,
    db,
    user_viewed_listings,
)
from ..security import generate_secure_filename, validate_file_upload
from ..security import validate_input_sanitization
from ..time_utils import utcnow
from .media import _r2_configured, _r2_public_base

bp = Blueprint("user", __name__)


@bp.route("/api/user/notifications", methods=["GET"])
@jwt_required()
def user_notifications():
    """Return only the authenticated user's persisted notifications."""
    current_user = get_current_user()
    if not current_user:
        return jsonify({"message": "User not found"}), 404

    page = max(1, request.args.get("page", 1, type=int))
    per_page = min(50, max(1, request.args.get("per_page", 20, type=int)))
    unread_only = (request.args.get("unread_only") or "").strip().lower() in {
        "1",
        "true",
        "yes",
    }
    notification_type = (request.args.get("type") or "").strip()

    query = Notification.query.filter_by(user_id=current_user.id)
    if unread_only:
        query = query.filter(Notification.is_read.is_(False))
    if notification_type:
        query = query.filter(Notification.notification_type == notification_type)
    pagination = query.order_by(Notification.created_at.desc()).paginate(
        page=page,
        per_page=per_page,
        error_out=False,
    )
    unread_count = Notification.query.filter_by(
        user_id=current_user.id,
        is_read=False,
    ).count()
    return jsonify(
        {
            "notifications": [item.to_dict() for item in pagination.items],
            "unread_count": unread_count,
            "pagination": {
                "page": pagination.page,
                "per_page": pagination.per_page,
                "total": pagination.total,
                "pages": pagination.pages,
                "has_next": pagination.has_next,
                "has_prev": pagination.has_prev,
            },
        }
    ), 200


@bp.route("/api/user/notifications/<notification_public_id>/read", methods=["PATCH"])
@jwt_required()
def mark_user_notification_read(notification_public_id: str):
    """Mark one owned notification read without exposing other users' rows."""
    current_user = get_current_user()
    if not current_user:
        return jsonify({"message": "User not found"}), 404
    notification = Notification.query.filter_by(
        public_id=(notification_public_id or "").strip(),
        user_id=current_user.id,
    ).first()
    if not notification:
        return jsonify({"message": "Notification not found"}), 404
    if not notification.is_read:
        notification.is_read = True
        db.session.commit()
    return jsonify({"notification": notification.to_dict()}), 200


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


def _normalize_dealer_phone(value) -> str:
    digits = "".join(ch for ch in str(value or "") if ch.isdigit())
    if digits.startswith("964") and len(digits) >= 12:
        digits = digits[3:]
    if len(digits) > 11:
        digits = digits[-11:]
    return digits


def _hash_dealer_phone_code(phone_digits: str, code: str) -> str:
    key = (current_app.config.get("SECRET_KEY") or "").encode("utf-8")
    message = f"dealer-phone:{phone_digits}:{code}".encode("utf-8")
    return hmac.new(key, msg=message, digestmod=hashlib.sha256).hexdigest()


def _hash_contact_phone_code(phone_digits: str, code: str) -> str:
    key = (current_app.config.get("SECRET_KEY") or "").encode("utf-8")
    message = f"contact-phone:{phone_digits}:{code}".encode("utf-8")
    return hmac.new(key, msg=message, digestmod=hashlib.sha256).hexdigest()


DEALERSHIP_EMAIL_MAX = 5
_EMAIL_RE = re.compile(r"^[^@\s]+@[^@\s]+\.[^@\s]+$")


def _normalize_dealer_email(value) -> str:
    return ("" if value is None else str(value)).strip().lower()


def _is_valid_dealer_email(value: str) -> bool:
    email = _normalize_dealer_email(value)
    if not email or len(email) > 120 or email.endswith("@phone.local"):
        return False
    return bool(_EMAIL_RE.match(email))


def _clean_email_list(value) -> list[str]:
    if value is None:
        return []
    items = list(value) if isinstance(value, (list, tuple, set)) else [value]
    out: list[str] = []
    seen: set[str] = set()
    for item in items:
        email = _normalize_dealer_email(item)
        if not email or email in seen:
            continue
        seen.add(email)
        out.append(email)
        if len(out) >= DEALERSHIP_EMAIL_MAX:
            break
    return out


def _hash_dealer_email_code(email: str, code: str) -> str:
    key = (current_app.config.get("SECRET_KEY") or "").encode("utf-8")
    message = f"dealer-email:{email}:{code}".encode("utf-8")
    return hmac.new(key, msg=message, digestmod=hashlib.sha256).hexdigest()


def _verified_dealer_emails(user: User) -> list[str]:
    raw = getattr(user, "dealership_verified_emails", None)
    verified = raw if isinstance(raw, list) else []
    output: list[str] = []
    for value in verified:
        email = _normalize_dealer_email(value)
        if email and email not in output:
            output.append(email)
    return output


def _is_dev_email_payload() -> bool:
    return bool(current_app.config.get("DEBUG")) or (
        os.environ.get("APP_ENV") or ""
    ).strip().lower() == "development"


def _verified_dealer_phone_digits(user: User) -> list[str]:
    raw = getattr(user, "dealership_verified_phones", None)
    verified = raw if isinstance(raw, list) else []
    output: list[str] = []
    for value in verified:
        normalized = _normalize_dealer_phone(value)
        if normalized and normalized not in output:
            output.append(normalized)
    account_phone = _normalize_dealer_phone(getattr(user, "phone_number", None))
    if bool(getattr(user, "is_verified", False)) and account_phone:
        if account_phone not in output:
            output.append(account_phone)
    return output


def _verified_contact_phone_digits(user: User) -> list[str]:
    raw = getattr(user, "contact_verified_phones", None)
    verified = raw if isinstance(raw, list) else []
    output: list[str] = []
    for value in verified:
        normalized = _normalize_dealer_phone(value)
        if normalized and normalized not in output:
            output.append(normalized)
    account_phone = _normalize_dealer_phone(getattr(user, "phone_number", None))
    # Account phone is always acceptable for listing contact without extra OTP.
    if account_phone and account_phone not in output:
        output.append(account_phone)
    return output


LISTING_CONTACT_PHONE_MAX = 3


def parse_listing_contact_phones(data: dict | None) -> list[str]:
    """Normalize contact_phones / contact_phone from a request body (max 3)."""
    data = data or {}
    phones = _clean_phone_list(data.get("contact_phones"))
    if not phones:
        single = (data.get("contact_phone") or "").strip()
        if single:
            phones = [single]
    out: list[str] = []
    seen: set[str] = set()
    for phone in phones:
        digits = _normalize_dealer_phone(phone)
        if len(digits) not in {10, 11}:
            continue
        if digits in seen:
            continue
        seen.add(digits)
        out.append(f"+964{digits}")
        if len(out) >= LISTING_CONTACT_PHONE_MAX:
            break
    return out


def assert_listing_phones_verified(user: User, phones: list[str]) -> str | None:
    """Return an error message if any phone is not OTP-proven for this user."""
    verified = set(_verified_contact_phone_digits(user))
    for phone in phones:
        digits = _normalize_dealer_phone(phone)
        if digits not in verified:
            return "Verify each contact phone with a code before publishing"
    return None


def _clean_document_urls(value) -> list[str]:
    if not isinstance(value, (list, tuple, set)):
        return []
    urls = [str(item).strip() for item in value if str(item).strip()]
    if len(urls) > 10:
        raise ValueError("A maximum of 10 verification documents is allowed")
    if any(len(url) > 2048 or not url.lower().startswith("https://") for url in urls):
        raise ValueError("Verification document links must use HTTPS")
    return urls


def _save_dealer_application(user: User, data: dict) -> DealerApplication:
    """Create/update the current application while retaining immutable decisions."""
    if not user.is_verified:
        raise ValueError("Verify your phone or email before applying as a dealer")

    application = user.dealer_application
    previous_status = application.status if application else None
    if previous_status == "approved":
        raise ValueError("This dealer account is already approved")
    if previous_status in {"submitted", "under_review"}:
        raise ValueError("Your dealer application is already being reviewed")

    dealership_name = (data.get("dealership_name") or "").strip()
    phones = _clean_phone_list(data.get("dealership_phones"))
    dealership_phone = (
        phones[0] if phones else (data.get("dealership_phone") or "").strip()
    )
    dealership_location = (data.get("dealership_location") or "").strip()
    if not dealership_name:
        raise ValueError("Dealership name is required")
    if not dealership_phone:
        raise ValueError("Dealership phone is required")
    if not dealership_location:
        raise ValueError("Dealership location is required")

    submit = _to_bool(data.get("submit", True))
    if submit and (
        application is None or not application.verification_photo_filename
    ):
        raise ValueError("A dealership verification photo is required")
    next_status = "submitted" if submit else "draft"
    now = utcnow()
    if application is None:
        application = DealerApplication(
            user=user,
            dealership_name=dealership_name,
            dealership_phone=dealership_phone,
            dealership_location=dealership_location,
        )
        db.session.add(application)

    application.status = next_status
    application.dealership_name = dealership_name
    application.dealership_phone = dealership_phone
    application.dealership_phones = phones or [dealership_phone]
    application.dealership_location = dealership_location
    application.dealership_description = (
        (data.get("dealership_description") or "").strip() or None
    )
    application.business_registration_number = (
        (data.get("business_registration_number") or "").strip() or None
    )
    application.document_urls = _clean_document_urls(data.get("document_urls"))
    application.review_reason = None
    application.reviewed_at = None
    application.updated_at = now
    if submit:
        application.submitted_at = now

    # Keep old clients and existing public serializers working during migration.
    user.account_type = "user"
    user.dealer_status = "pending" if submit else "none"
    user.dealership_name = dealership_name
    user.dealership_phone = dealership_phone
    user.dealership_phones = application.dealership_phones
    user.dealership_location = dealership_location
    user.dealership_description = application.dealership_description
    user.updated_at = now

    db.session.flush()
    event = (
        "resubmitted"
        if previous_status in {"needs_changes", "rejected"}
        else ("submitted" if submit else "draft")
    )
    db.session.add(
        DealerDecision(
            application=application,
            decision=event,
            application_snapshot=application.snapshot(),
        )
    )
    if submit:
        db.session.add(
            Notification(
                user_id=user.id,
                title="Dealer application submitted",
                message="Your dealership details were received and are ready for review.",
                notification_type="dealer_application",
                data={"application_id": application.public_id, "status": next_status},
            )
        )
    return application


@bp.route("/api/user/dealer-application", methods=["GET"])
@jwt_required()
def get_dealer_application():
    current_user = get_current_user()
    if not current_user:
        return jsonify({"message": "User not found"}), 404
    application = current_user.dealer_application
    return jsonify(
        {
            "application": (
                application.to_dict(include_decisions=True) if application else None
            )
        }
    ), 200


@bp.route("/api/user/dealer-application", methods=["PUT", "POST"])
@jwt_required()
def save_dealer_application():
    try:
        current_user = get_current_user()
        if not current_user:
            return jsonify({"message": "User not found"}), 404
        data = validate_input_sanitization(request.get_json(silent=True) or {})
        application = _save_dealer_application(current_user, data)
        db.session.commit()
        log_user_action(
            current_user,
            "dealer_application_submit"
            if application.status == "submitted"
            else "dealer_application_draft",
            target_type="dealer_application",
            target_id=application.public_id,
            metadata={"status": application.status},
        )
        return jsonify(
            {
                "message": (
                    "Dealer application submitted"
                    if application.status == "submitted"
                    else "Dealer application draft saved"
                ),
                "application": application.to_dict(include_decisions=True),
                "user": current_user.to_dict(include_private=True),
            }
        ), 200
    except ValueError as exc:
        db.session.rollback()
        return jsonify({"message": str(exc)}), 400
    except Exception as exc:
        db.session.rollback()
        current_app.logger.exception("save_dealer_application failed: %s", exc)
        return jsonify({"message": "Failed to save dealer application"}), 500


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


@bp.route("/api/user/recently-viewed", methods=["POST"])
@jwt_required()
def record_recently_viewed():
    """Record that the user viewed a listing (for Recently viewed screen)."""
    try:
        from ..view_history import record_user_listing_view

        current_user = get_current_user()
        if not current_user:
            return jsonify({"message": "User not found"}), 404

        data = validate_input_sanitization(request.get_json(silent=True) or {})
        listing_id = str(
            data.get("listing_id") or data.get("listingId") or data.get("car_id") or ""
        ).strip()
        if not listing_id:
            return jsonify({"message": "listing_id required"}), 400

        car, _is_first = record_user_listing_view(current_user, listing_id)
        if not car:
            return jsonify({"message": "Listing not found"}), 404

        return jsonify({"success": True, "car_id": car.public_id}), 200
    except Exception:
        db.session.rollback()
        return jsonify({"message": "Failed to record view"}), 500


@bp.route("/api/user/recently-viewed", methods=["DELETE"])
@jwt_required()
def clear_recently_viewed():
    """Clear all recently viewed listings for the current user."""
    try:
        from ..view_history import clear_user_listing_views

        current_user = get_current_user()
        if not current_user:
            return jsonify({"message": "User not found"}), 404

        clear_user_listing_views(current_user)
        return jsonify({"success": True, "message": "Recently viewed cleared"}), 200
    except Exception:
        db.session.rollback()
        return jsonify({"message": "Failed to clear recently viewed"}), 500


@bp.route("/api/user/recently-viewed/<listing_id>", methods=["DELETE"])
@jwt_required()
def delete_recently_viewed_one(listing_id: str):
    """Remove one listing from recently viewed."""
    try:
        from ..view_history import delete_user_listing_view

        current_user = get_current_user()
        if not current_user:
            return jsonify({"message": "User not found"}), 404

        lid = (listing_id or "").strip()
        if not lid:
            return jsonify({"message": "listing_id required"}), 400

        if not delete_user_listing_view(current_user, lid):
            return jsonify({"message": "Listing not found"}), 404

        return jsonify({"success": True}), 200
    except Exception:
        db.session.rollback()
        return jsonify({"message": "Failed to remove recently viewed listing"}), 500


@bp.route("/api/user/recently-viewed", methods=["GET"])
@jwt_required()
def recently_viewed():
    """Listings the user recently viewed (newest first)."""
    try:
        from .cars import _with_media_compat

        current_user = get_current_user()
        if not current_user:
            return jsonify({"message": "User not found"}), 404

        page = max(1, request.args.get("page", 1, type=int))
        per_page = min(50, max(1, request.args.get("per_page", 20, type=int)))

        q = (
            db.session.query(Car, user_viewed_listings.c.viewed_at)
            .join(user_viewed_listings, user_viewed_listings.c.car_id == Car.id)
            .filter(
                user_viewed_listings.c.user_id == current_user.id,
                Car.is_active.is_(True),
            )
            .order_by(user_viewed_listings.c.viewed_at.desc())
        )
        pagination = q.paginate(page=page, per_page=per_page, error_out=False)

        cars = []
        for car, viewed_at in pagination.items:
            d = _with_media_compat(car)
            if viewed_at is not None:
                try:
                    d["viewed_at"] = viewed_at.isoformat()
                except Exception:
                    d["viewed_at"] = str(viewed_at)
            if not d.get("city") and d.get("location"):
                d["city"] = d["location"]
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
        return jsonify({"message": "Failed to get recently viewed listings"}), 500


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
            new_digits = _normalize_dealer_phone(data.get("phone_number"))
            old_digits = _normalize_dealer_phone(getattr(current_user, "phone_number", None))
            if new_digits and new_digits != old_digits:
                if len(new_digits) < 7:
                    return jsonify({"message": "Enter a valid phone number"}), 400
                existing_phone = User.query.filter_by(phone_number=new_digits).first()
                if existing_phone and existing_phone.id != current_user.id:
                    return jsonify({"message": "Phone number already exists"}), 400
                code = str(
                    data.get("verification_code")
                    or data.get("phone_verification_code")
                    or ""
                ).strip()
                if not code or len(code) != 6 or not code.isdigit():
                    return (
                        jsonify(
                            {
                                "message": "Verify the new phone number with an SMS code before changing it.",
                                "code": "phone_change_verification_required",
                            }
                        ),
                        400,
                    )
                now = utcnow()
                locked_until = getattr(current_user, "phone_verification_locked_until", None)
                if locked_until and locked_until > now:
                    return jsonify({"message": "Too many attempts. Please try again later."}), 429
                expires_at = getattr(current_user, "phone_verification_expires_at", None)
                code_hash = getattr(current_user, "phone_verification_code_hash", None)
                if not expires_at or not code_hash or expires_at <= now:
                    return jsonify({"message": "Invalid or expired verification code"}), 400
                key = (current_app.config.get("SECRET_KEY") or "").encode("utf-8")
                expected = hmac.new(
                    key,
                    msg=f"{new_digits}:{code}".encode("utf-8"),
                    digestmod=hashlib.sha256,
                ).hexdigest()
                if not hmac.compare_digest(code_hash, expected):
                    attempts = int(getattr(current_user, "phone_verification_attempts", 0) or 0) + 1
                    current_user.phone_verification_attempts = attempts
                    if attempts >= 5:
                        current_user.phone_verification_locked_until = now + timedelta(minutes=15)
                        current_user.phone_verification_code_hash = None
                        current_user.phone_verification_expires_at = None
                        current_user.phone_verification_attempts = 0
                    db.session.commit()
                    return jsonify({"message": "Invalid or expired verification code"}), 400
                current_user.phone_number = new_digits
                current_user.phone_verified = True
                current_user.is_verified = True
                current_user.phone_verification_code_hash = None
                current_user.phone_verification_expires_at = None
                current_user.phone_verification_attempts = 0
                current_user.phone_verification_locked_until = None
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

        # Backwards-compatible dealer request flow for older mobile clients.
        if _to_bool(data.get("is_dealer")):
            _save_dealer_application(current_user, data)
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

    except ValueError as exc:
        db.session.rollback()
        return jsonify({"message": str(exc)}), 400
    except Exception:
        db.session.rollback()
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
                from ..r2_ops import r2_put_bytes

                public_base = _r2_public_base()

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

                r2_put_bytes(
                    key=key,
                    body=body,
                    content_type=file.mimetype or "image/jpeg",
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


@bp.route("/api/user/upload-dealer-verification-photo", methods=["POST"])
@jwt_required()
def upload_dealer_verification_photo():
    """Store a dealership photo privately for dealer-application review."""
    try:
        current_user = get_current_user()
        if not current_user:
            return jsonify({"message": "User not found"}), 404

        application = current_user.dealer_application
        if application is None:
            return jsonify({"message": "Save the dealer application first"}), 400
        if application.status in {"submitted", "under_review", "approved"}:
            return jsonify(
                {"message": "This dealer application cannot currently be changed"}
            ), 400
        if "file" not in request.files:
            return jsonify({"message": "No file provided"}), 400

        file = request.files["file"]
        allowed = {"jpg", "jpeg", "png", "webp", "heic", "heif"}
        is_valid, message = validate_file_upload(
            file,
            max_size_mb=8,
            allowed_extensions=allowed,
        )
        if not is_valid:
            return jsonify({"message": message}), 400

        safe_name = generate_secure_filename(file.filename)
        extension = os.path.splitext(safe_name)[1].lower() or ".jpg"
        filename = f"{secrets.token_hex(24)}{extension}"
        folder = os.path.join(
            current_app.config["PRIVATE_UPLOAD_FOLDER"],
            "dealer_verification",
        )
        os.makedirs(folder, exist_ok=True)
        file.save(os.path.join(folder, filename))

        previous = application.verification_photo_filename
        application.verification_photo_filename = filename
        application.updated_at = utcnow()
        db.session.commit()

        if previous and previous != filename:
            try:
                os.remove(os.path.join(folder, os.path.basename(previous)))
            except OSError:
                pass

        log_user_action(
            current_user,
            "dealer_verification_photo_upload",
            target_type="dealer_application",
            target_id=application.public_id,
        )
        return jsonify(
            {
                "message": "Dealership verification photo uploaded",
                "has_verification_photo": True,
            }
        ), 200
    except Exception as e:
        db.session.rollback()
        current_app.logger.exception(
            "upload_dealer_verification_photo failed: %s",
            e,
        )
        return jsonify({"message": "Failed to upload verification photo"}), 500


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
                from ..r2_ops import r2_put_bytes

                public_base = _r2_public_base()

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

                r2_put_bytes(
                    key=key,
                    body=body,
                    content_type=file.mimetype or "image/jpeg",
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
        if current_user.dealer_profile:
            current_user.dealer_profile.dealership_cover_picture = cover_url
            current_user.dealer_profile.updated_at = utcnow()
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


def _public_dealer_search_dict(user: User) -> dict:
    """Minimal fields for directory search (no personal phone / email)."""
    profile = user.dealer_profile
    return {
        "id": user.public_id,
        "dealership_name": (
            (profile.dealership_name if profile else user.dealership_name) or ""
        ).strip(),
        "dealership_location": (
            (profile.dealership_location if profile else user.dealership_location) or ""
        ).strip(),
        "profile_picture": user.profile_picture,
        "dealership_cover_picture": (
            profile.dealership_cover_picture if profile else user.dealership_cover_picture
        ),
    }


@bp.route("/api/dealers", methods=["GET"])
def list_dealers():
    """Public directory of approved dealerships; optional name/location search."""
    try:
        q_raw = (request.args.get("q") or "").strip()
        try:
            page = max(1, int(request.args.get("page") or 1))
        except (TypeError, ValueError):
            page = 1
        try:
            per_page = int(request.args.get("per_page") or 20)
        except (TypeError, ValueError):
            per_page = 20
        per_page = max(1, min(per_page, 50))

        query = User.query.filter(
            User.account_type == "dealer",
            User.dealer_status == "approved",
            User.is_active.is_(True),
            User.dealership_name.isnot(None),
            User.dealership_name != "",
        )

        if q_raw:
            pattern = f"%{q_raw}%"
            query = query.filter(
                or_(
                    User.dealership_name.ilike(pattern),
                    User.dealership_location.ilike(pattern),
                )
            )

        total = query.count()
        rows = (
            query.order_by(User.dealership_name.asc(), User.public_id.asc())
            .offset((page - 1) * per_page)
            .limit(per_page)
            .all()
        )
        dealers = [_public_dealer_search_dict(u) for u in rows]
        return (
            jsonify(
                {
                    "dealers": dealers,
                    "pagination": {
                        "page": page,
                        "per_page": per_page,
                        "total": total,
                        "has_next": page * per_page < total,
                    },
                }
            ),
            200,
        )
    except Exception as e:
        current_app.logger.exception("list_dealers failed: %s", e)
        return jsonify({"message": "Failed to list dealerships"}), 500


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
            Car.query.filter(
                Car.seller_id == dealer.id,
                Car.is_active.is_(True),
            )
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

        dealer_data = dealer.to_dict()
        if dealer.dealer_profile:
            dealer_data.update(dealer.dealer_profile.to_dict())
            dealer_data["id"] = dealer.public_id
            dealer_data["account_type"] = "dealer"
            dealer_data["dealer_status"] = "approved"
        # Public contact uses verified dealership emails only (not account login email).
        dealer_data.pop("email", None)
        emails = dealer_data.get("dealership_emails")
        if not isinstance(emails, list):
            emails = []
        dealer_data["dealership_emails"] = [
            str(x).strip() for x in emails if str(x).strip()
        ]
        dealer_data.pop("dealership_verified_emails", None)
        return jsonify({"dealer": dealer_data, "listings": listing_dicts, "stats": stats}), 200
    except Exception as e:
        current_app.logger.exception("dealer_profile failed: %s", e)
        return jsonify({"message": "Failed to load dealer profile"}), 500


@bp.route("/api/user/dealer-phone/send-verification", methods=["POST"])
@jwt_required()
def send_dealer_phone_verification():
    """Send an ownership code for a dealership contact number."""
    current_user = get_current_user()
    if not current_user:
        return jsonify({"message": "User not found"}), 404
    if (current_user.account_type or "").strip().lower() != "dealer":
        return jsonify({"message": "Only dealers can verify dealership phones"}), 403

    data = validate_input_sanitization(request.get_json(silent=True) or {})
    raw_phone = (data.get("phone_number") or data.get("phone") or "").strip()
    phone_digits = _normalize_dealer_phone(raw_phone)
    if len(phone_digits) not in {10, 11}:
        return jsonify({"message": "Enter a valid phone number"}), 400

    verified = _verified_dealer_phone_digits(current_user)
    if phone_digits in verified:
        current_user.dealership_verified_phones = verified
        db.session.commit()
        return jsonify({"message": "Phone number is already verified", "verified": True}), 200

    now = utcnow()
    locked_until = getattr(current_user, "phone_verification_locked_until", None)
    if locked_until and locked_until > now:
        return jsonify({"message": "Too many attempts. Please try again later."}), 429
    last_sent = getattr(current_user, "phone_verification_last_sent_at", None)
    if last_sent and (now - last_sent).total_seconds() < 60:
        return jsonify({"message": "Please wait before requesting another code"}), 429

    code = f"{secrets.randbelow(1_000_000):06d}"
    current_user.phone_verification_code_hash = _hash_dealer_phone_code(
        phone_digits,
        code,
    )
    current_user.phone_verification_expires_at = now + timedelta(minutes=10)
    current_user.phone_verification_attempts = 0
    current_user.phone_verification_last_sent_at = now
    current_user.phone_verification_locked_until = None
    db.session.commit()

    from ..sms_service import send_verification_sms_result

    sms_sent, sms_detail = send_verification_sms_result(phone_digits, code)
    if not sms_sent:
        current_user.phone_verification_code_hash = None
        current_user.phone_verification_expires_at = None
        current_user.phone_verification_attempts = 0
        db.session.commit()
        payload = {
            "message": "Failed to send verification code",
            "sent": False,
            "code": "sms_send_failed",
        }
        if sms_detail:
            payload["detail"] = sms_detail
        if current_app.config.get("DEBUG") or (
            os.environ.get("APP_ENV") or ""
        ).strip().lower() == "development":
            payload["dev_code"] = code
        return jsonify(payload), 502

    payload = {"message": "Verification code sent", "sent": True}
    if current_app.config.get("DEBUG") or (
        os.environ.get("APP_ENV") or ""
    ).strip().lower() == "development":
        payload["dev_code"] = code
    return jsonify(payload), 200


@bp.route("/api/user/dealer-phone/verify", methods=["POST"])
@jwt_required()
def verify_dealer_phone():
    """Confirm a dealership contact number and persist ownership."""
    current_user = get_current_user()
    if not current_user:
        return jsonify({"message": "User not found"}), 404
    if (current_user.account_type or "").strip().lower() != "dealer":
        return jsonify({"message": "Only dealers can verify dealership phones"}), 403

    data = validate_input_sanitization(request.get_json(silent=True) or {})
    raw_phone = (data.get("phone_number") or data.get("phone") or "").strip()
    code = str(data.get("verification_code") or data.get("code") or "").strip()
    phone_digits = _normalize_dealer_phone(raw_phone)
    if len(phone_digits) not in {10, 11} or len(code) != 6 or not code.isdigit():
        return jsonify({"message": "Phone number and a six-digit code are required"}), 400

    verified = _verified_dealer_phone_digits(current_user)
    if phone_digits in verified:
        current_user.dealership_verified_phones = verified
        db.session.commit()
        return jsonify(
            {
                "message": "Phone number verified successfully",
                "verified_phone": phone_digits,
                "dealership_verified_phones": verified,
            }
        ), 200

    now = utcnow()
    locked_until = getattr(current_user, "phone_verification_locked_until", None)
    if locked_until and locked_until > now:
        return jsonify({"message": "Too many attempts. Please try again later."}), 429
    expires_at = getattr(current_user, "phone_verification_expires_at", None)
    code_hash = getattr(current_user, "phone_verification_code_hash", None)
    if not expires_at or not code_hash or expires_at <= now:
        current_user.phone_verification_code_hash = None
        current_user.phone_verification_expires_at = None
        current_user.phone_verification_attempts = 0
        db.session.commit()
        return jsonify({"message": "Invalid or expired verification code"}), 400

    expected = _hash_dealer_phone_code(phone_digits, code)
    if not hmac.compare_digest(code_hash, expected):
        attempts = int(getattr(current_user, "phone_verification_attempts", 0) or 0) + 1
        current_user.phone_verification_attempts = attempts
        if attempts >= 5:
            current_user.phone_verification_locked_until = now + timedelta(minutes=15)
            current_user.phone_verification_code_hash = None
            current_user.phone_verification_expires_at = None
            current_user.phone_verification_attempts = 0
        db.session.commit()
        return jsonify({"message": "Invalid or expired verification code"}), 400

    verified.append(phone_digits)
    current_user.dealership_verified_phones = verified
    current_user.phone_verification_code_hash = None
    current_user.phone_verification_expires_at = None
    current_user.phone_verification_attempts = 0
    current_user.phone_verification_locked_until = None
    db.session.commit()
    log_user_action(current_user, "dealer_phone_verified")
    return jsonify(
        {
            "message": "Phone number verified successfully",
            "verified_phone": phone_digits,
            "dealership_verified_phones": verified,
        }
    ), 200


@bp.route("/api/user/dealer-email/send-verification", methods=["POST"])
@jwt_required()
def send_dealer_email_verification():
    """Send an ownership code for a dealership contact email."""
    current_user = get_current_user()
    if not current_user:
        return jsonify({"message": "User not found"}), 404
    if (current_user.account_type or "").strip().lower() != "dealer":
        return jsonify({"message": "Only dealers can verify dealership emails"}), 403

    data = validate_input_sanitization(request.get_json(silent=True) or {})
    email = _normalize_dealer_email(data.get("email") or data.get("email_address") or "")
    if not _is_valid_dealer_email(email):
        return jsonify({"message": "Enter a valid email address"}), 400

    verified = _verified_dealer_emails(current_user)
    if email in verified:
        current_user.dealership_verified_emails = verified
        db.session.commit()
        return jsonify({"message": "Email is already verified", "verified": True}), 200

    now = utcnow()
    locked_until = getattr(current_user, "dealer_email_verification_locked_until", None)
    if locked_until and locked_until > now:
        return jsonify({"message": "Too many attempts. Please try again later."}), 429
    last_sent = getattr(current_user, "dealer_email_verification_last_sent_at", None)
    if last_sent and (now - last_sent).total_seconds() < 60:
        return jsonify({"message": "Please wait before requesting another code"}), 429

    code = f"{secrets.randbelow(1_000_000):06d}"
    current_user.dealer_email_verification_code_hash = _hash_dealer_email_code(email, code)
    current_user.dealer_email_verification_expires_at = now + timedelta(minutes=10)
    current_user.dealer_email_verification_attempts = 0
    current_user.dealer_email_verification_last_sent_at = now
    current_user.dealer_email_verification_locked_until = None
    db.session.commit()

    from ..email_service import send_dealer_email_verification_code

    mail_sent = send_dealer_email_verification_code(email, code)
    if not mail_sent:
        if _is_dev_email_payload():
            # Keep the OTP so local clients can verify with `dev_code`.
            payload = {
                "message": "Verification code ready (email not configured)",
                "sent": False,
                "code": "email_send_failed",
                "dev_code": code,
            }
            return jsonify(payload), 200
        current_user.dealer_email_verification_code_hash = None
        current_user.dealer_email_verification_expires_at = None
        current_user.dealer_email_verification_attempts = 0
        db.session.commit()
        return jsonify(
            {
                "message": "Failed to send verification code",
                "sent": False,
                "code": "email_send_failed",
            }
        ), 502

    payload = {"message": "Verification code sent", "sent": True}
    if _is_dev_email_payload():
        payload["dev_code"] = code
    return jsonify(payload), 200


@bp.route("/api/user/dealer-email/verify", methods=["POST"])
@jwt_required()
def verify_dealer_email():
    """Confirm a dealership contact email and persist ownership."""
    current_user = get_current_user()
    if not current_user:
        return jsonify({"message": "User not found"}), 404
    if (current_user.account_type or "").strip().lower() != "dealer":
        return jsonify({"message": "Only dealers can verify dealership emails"}), 403

    data = validate_input_sanitization(request.get_json(silent=True) or {})
    email = _normalize_dealer_email(data.get("email") or data.get("email_address") or "")
    code = str(data.get("verification_code") or data.get("code") or "").strip()
    if not _is_valid_dealer_email(email) or len(code) != 6 or not code.isdigit():
        return jsonify({"message": "Email and a six-digit code are required"}), 400

    verified = _verified_dealer_emails(current_user)
    if email in verified:
        current_user.dealership_verified_emails = verified
        db.session.commit()
        return jsonify(
            {
                "message": "Email verified successfully",
                "verified_email": email,
                "dealership_verified_emails": verified,
            }
        ), 200

    now = utcnow()
    locked_until = getattr(current_user, "dealer_email_verification_locked_until", None)
    if locked_until and locked_until > now:
        return jsonify({"message": "Too many attempts. Please try again later."}), 429
    expires_at = getattr(current_user, "dealer_email_verification_expires_at", None)
    code_hash = getattr(current_user, "dealer_email_verification_code_hash", None)
    if not expires_at or not code_hash or expires_at <= now:
        current_user.dealer_email_verification_code_hash = None
        current_user.dealer_email_verification_expires_at = None
        current_user.dealer_email_verification_attempts = 0
        db.session.commit()
        return jsonify({"message": "Invalid or expired verification code"}), 400

    expected = _hash_dealer_email_code(email, code)
    if not hmac.compare_digest(code_hash, expected):
        attempts = int(
            getattr(current_user, "dealer_email_verification_attempts", 0) or 0
        ) + 1
        current_user.dealer_email_verification_attempts = attempts
        if attempts >= 5:
            current_user.dealer_email_verification_locked_until = now + timedelta(
                minutes=15
            )
            current_user.dealer_email_verification_code_hash = None
            current_user.dealer_email_verification_expires_at = None
            current_user.dealer_email_verification_attempts = 0
        db.session.commit()
        return jsonify({"message": "Invalid or expired verification code"}), 400

    verified.append(email)
    current_user.dealership_verified_emails = verified
    current_user.dealer_email_verification_code_hash = None
    current_user.dealer_email_verification_expires_at = None
    current_user.dealer_email_verification_attempts = 0
    current_user.dealer_email_verification_locked_until = None
    db.session.commit()
    log_user_action(current_user, "dealer_email_verified")
    return jsonify(
        {
            "message": "Email verified successfully",
            "verified_email": email,
            "dealership_verified_emails": verified,
        }
    ), 200


@bp.route("/api/user/contact-phone/send-verification", methods=["POST"])
@jwt_required()
def send_contact_phone_verification():
    """Send an ownership code for a listing contact number."""
    current_user = get_current_user()
    if not current_user:
        return jsonify({"message": "User not found"}), 404

    data = validate_input_sanitization(request.get_json(silent=True) or {})
    raw_phone = (data.get("phone_number") or data.get("phone") or "").strip()
    phone_digits = _normalize_dealer_phone(raw_phone)
    if len(phone_digits) not in {10, 11}:
        return jsonify({"message": "Enter a valid phone number"}), 400

    verified = _verified_contact_phone_digits(current_user)
    if phone_digits in verified:
        return jsonify({"message": "Phone number is already verified", "verified": True}), 200

    now = utcnow()
    locked_until = getattr(current_user, "phone_verification_locked_until", None)
    if locked_until and locked_until > now:
        return jsonify({"message": "Too many attempts. Please try again later."}), 429
    last_sent = getattr(current_user, "phone_verification_last_sent_at", None)
    if last_sent and (now - last_sent).total_seconds() < 60:
        return jsonify({"message": "Please wait before requesting another code"}), 429

    code = f"{secrets.randbelow(1_000_000):06d}"
    current_user.phone_verification_code_hash = _hash_contact_phone_code(
        phone_digits,
        code,
    )
    current_user.phone_verification_expires_at = now + timedelta(minutes=10)
    current_user.phone_verification_attempts = 0
    current_user.phone_verification_last_sent_at = now
    current_user.phone_verification_locked_until = None
    db.session.commit()

    from ..sms_service import send_verification_sms_result

    sms_sent, sms_detail = send_verification_sms_result(phone_digits, code)
    if not sms_sent:
        current_user.phone_verification_code_hash = None
        current_user.phone_verification_expires_at = None
        current_user.phone_verification_attempts = 0
        db.session.commit()
        payload = {
            "message": "Failed to send verification code",
            "sent": False,
            "code": "sms_send_failed",
        }
        if sms_detail:
            payload["detail"] = sms_detail
        if current_app.config.get("DEBUG") or (
            os.environ.get("APP_ENV") or ""
        ).strip().lower() == "development":
            payload["dev_code"] = code
        return jsonify(payload), 502

    payload = {"message": "Verification code sent", "sent": True}
    if current_app.config.get("DEBUG") or (
        os.environ.get("APP_ENV") or ""
    ).strip().lower() == "development":
        payload["dev_code"] = code
    return jsonify(payload), 200


@bp.route("/api/user/contact-phone/verify", methods=["POST"])
@jwt_required()
def verify_contact_phone():
    """Confirm a listing contact number and persist ownership on the user."""
    current_user = get_current_user()
    if not current_user:
        return jsonify({"message": "User not found"}), 404

    data = validate_input_sanitization(request.get_json(silent=True) or {})
    raw_phone = (data.get("phone_number") or data.get("phone") or "").strip()
    code = str(data.get("verification_code") or data.get("code") or "").strip()
    phone_digits = _normalize_dealer_phone(raw_phone)
    if len(phone_digits) not in {10, 11} or len(code) != 6 or not code.isdigit():
        return jsonify({"message": "Phone number and a six-digit code are required"}), 400

    verified = _verified_contact_phone_digits(current_user)
    if phone_digits in verified:
        return jsonify(
            {
                "message": "Phone number verified successfully",
                "verified_phone": phone_digits,
                "contact_verified_phones": verified,
            }
        ), 200

    now = utcnow()
    locked_until = getattr(current_user, "phone_verification_locked_until", None)
    if locked_until and locked_until > now:
        return jsonify({"message": "Too many attempts. Please try again later."}), 429
    expires_at = getattr(current_user, "phone_verification_expires_at", None)
    code_hash = getattr(current_user, "phone_verification_code_hash", None)
    if not expires_at or not code_hash or expires_at <= now:
        current_user.phone_verification_code_hash = None
        current_user.phone_verification_expires_at = None
        current_user.phone_verification_attempts = 0
        db.session.commit()
        return jsonify({"message": "Invalid or expired verification code"}), 400

    expected = _hash_contact_phone_code(phone_digits, code)
    if not hmac.compare_digest(code_hash, expected):
        attempts = int(getattr(current_user, "phone_verification_attempts", 0) or 0) + 1
        current_user.phone_verification_attempts = attempts
        if attempts >= 5:
            current_user.phone_verification_locked_until = now + timedelta(minutes=15)
            current_user.phone_verification_code_hash = None
            current_user.phone_verification_expires_at = None
            current_user.phone_verification_attempts = 0
        db.session.commit()
        return jsonify({"message": "Invalid or expired verification code"}), 400

    stored = getattr(current_user, "contact_verified_phones", None)
    stored_list = [str(x).strip() for x in stored] if isinstance(stored, list) else []
    if phone_digits not in stored_list:
        stored_list.append(phone_digits)
    current_user.contact_verified_phones = stored_list
    current_user.phone_verification_code_hash = None
    current_user.phone_verification_expires_at = None
    current_user.phone_verification_attempts = 0
    current_user.phone_verification_locked_until = None
    db.session.commit()
    log_user_action(current_user, "contact_phone_verified")
    return jsonify(
        {
            "message": "Phone number verified successfully",
            "verified_phone": phone_digits,
            "contact_verified_phones": _verified_contact_phone_digits(current_user),
        }
    ), 200


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
            normalized_phones = [
                _normalize_dealer_phone(phone) for phone in phones
            ]
            if any(len(phone) not in {10, 11} for phone in normalized_phones):
                return jsonify({"message": "Enter valid dealership phone numbers"}), 400
            verified_phones = set(_verified_dealer_phone_digits(current_user))
            unverified = [
                phones[index]
                for index, phone in enumerate(normalized_phones)
                if phone not in verified_phones
            ]
            if unverified:
                return jsonify(
                    {
                        "message": "Verify every dealership phone before saving",
                        "code": "dealer_phone_verification_required",
                        "unverified_phones": unverified,
                    }
                ), 400
            try:
                current_user.dealership_phones = phones
                current_user.dealership_verified_phones = list(
                    dict.fromkeys(normalized_phones)
                )
            except Exception:
                # If column doesn't exist, fall back to single phone.
                pass
            current_user.dealership_phone = phones[0]

        # Legacy single-field update. Do NOT overwrite an explicit phones list.
        if "dealership_phone" in data and "dealership_phones" not in data:
            v = (data.get("dealership_phone") or "").strip()
            if not v:
                return jsonify({"message": "Dealership phone is required"}), 400
            normalized_phone = _normalize_dealer_phone(v)
            if normalized_phone not in _verified_dealer_phone_digits(current_user):
                return jsonify(
                    {
                        "message": "Verify the dealership phone before saving",
                        "code": "dealer_phone_verification_required",
                        "unverified_phones": [v],
                    }
                ), 400
            current_user.dealership_phone = v
            # Keep list in sync when caller only sends the legacy field.
            try:
                current_user.dealership_phones = _clean_phone_list([v])
                current_user.dealership_verified_phones = [normalized_phone]
            except Exception:
                pass

        if "dealership_emails" in data:
            emails = _clean_email_list(data.get("dealership_emails"))
            if any(not _is_valid_dealer_email(email) for email in emails):
                return jsonify({"message": "Enter valid dealership email addresses"}), 400
            verified_emails = set(_verified_dealer_emails(current_user))
            unverified = [email for email in emails if email not in verified_emails]
            if unverified:
                return jsonify(
                    {
                        "message": "Verify every dealership email before saving",
                        "code": "dealer_email_verification_required",
                        "unverified_emails": unverified,
                    }
                ), 400
            current_user.dealership_emails = emails
            current_user.dealership_verified_emails = list(dict.fromkeys(emails))

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

        profile = current_user.dealer_profile
        if profile is None:
            profile = DealerProfile(
                user=current_user,
                dealership_name=current_user.dealership_name,
                dealership_phone=current_user.dealership_phone,
                dealership_location=current_user.dealership_location,
            )
            db.session.add(profile)
        profile.dealership_name = current_user.dealership_name
        profile.dealership_phone = current_user.dealership_phone
        profile.dealership_phones = current_user.dealership_phones
        profile.dealership_emails = getattr(current_user, "dealership_emails", None)
        profile.dealership_verified_emails = getattr(
            current_user, "dealership_verified_emails", None
        )
        profile.dealership_location = current_user.dealership_location
        profile.dealership_description = current_user.dealership_description
        profile.dealership_cover_picture = current_user.dealership_cover_picture
        profile.dealership_latitude = current_user.dealership_latitude
        profile.dealership_longitude = current_user.dealership_longitude
        profile.dealership_opening_hours = current_user.dealership_opening_hours
        profile.is_featured = bool(current_user.is_featured_dealer)
        profile.updated_at = utcnow()
        current_user.updated_at = utcnow()
        db.session.commit()
        log_user_action(current_user, "dealer_profile_update")

        return jsonify({"message": "Dealer page updated", "user": current_user.to_dict(include_private=True)}), 200
    except Exception as e:
        db.session.rollback()
        current_app.logger.exception("update_dealer_profile failed: %s", e)
        return jsonify({"message": "Failed to update dealer page"}), 500

