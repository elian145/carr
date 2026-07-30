from __future__ import annotations

import hashlib
import hmac
import os
import secrets
import time
from datetime import datetime, timedelta

import requests
from flask import Blueprint, current_app, jsonify, request
from flask_mail import Message
from flask_jwt_extended import (
    create_access_token,
    create_refresh_token,
    decode_token,
    get_jwt,
    get_jwt_identity,
    jwt_required,
)
from sqlalchemy import func, inspect
from sqlalchemy.exc import IntegrityError

from ..auth import (
    create_email_verification_token,
    create_password_reset_token,
    get_current_user,
    log_user_action,
    validate_password,
    validate_user_input,
    verify_email_verification_token,
    verify_password_reset_token,
)
from ..extensions import mail
from ..models import (
    AdminAccount,
    DealerApplication,
    DealerDecision,
    EmailVerification,
    Message,
    PasswordReset,
    TokenBlacklist,
    User,
    db,
)
from ..security import check_rate_limit, rate_limit, validate_input_sanitization

bp = Blueprint("auth", __name__)


_EMAIL_SIGNUP_GONE = {
    "message": "Email signup is no longer supported. Use phone OTP instead.",
    "code": "email_signup_removed",
}


@bp.route("/auth/confirm-signup", methods=["GET"])
def confirm_signup_redirect():
    """Email signup removed — phone OTP only."""
    return jsonify(_EMAIL_SIGNUP_GONE), 410


# Configurable via RATE_LIMIT_SEND_OTP. Production default is strict; dev/testing default is relaxed.
def _send_otp_max_requests() -> int:
    explicit = (os.environ.get("RATE_LIMIT_SEND_OTP") or "").strip()
    if explicit:
        try:
            return max(1, int(explicit))
        except ValueError:
            pass
    from ..config import get_app_env

    return 3 if get_app_env() == "production" else 30


def _signup_max_requests() -> int:
    """
    Per-IP limit for POST /api/auth/signup.

    Must stay aligned with /api/auth/register (5/hour). The previous 1000/hour
    value effectively disabled abuse protection on the primary mobile signup path.
    Override with RATE_LIMIT_SIGNUP only for controlled load tests.
    """
    explicit = (os.environ.get("RATE_LIMIT_SIGNUP") or "").strip()
    if explicit:
        try:
            return max(1, int(explicit))
        except ValueError:
            pass
    return 5


_SEND_OTP_MAX_REQUESTS = _send_otp_max_requests()
_SEND_OTP_WINDOW_MINUTES = 10
_SIGNUP_MAX_REQUESTS = _signup_max_requests()
_SIGNUP_WINDOW_MINUTES = 60


def _normalize_phone(raw_phone: str) -> str:
    digits = "".join(ch for ch in (raw_phone or "") if ch.isdigit())
    if not digits:
        return ""
    if digits.startswith("964") and len(digits) >= 12:
        digits = digits[3:]
    if len(digits) > 11:
        digits = digits[-11:]
    return digits


def _to_bool(value) -> bool:
    if isinstance(value, bool):
        return value
    if value is None:
        return False
    return str(value).strip().lower() in {"1", "true", "yes", "on"}


def _apply_dealer_profile(
    user: User,
    *,
    is_dealer_requested: bool,
    dealership_name: str | None = None,
    dealership_phone: str | None = None,
    dealership_location: str | None = None,
) -> None:
    """Apply dealer profile request without auto-approving dealer role."""
    if is_dealer_requested:
        from ..time_utils import utcnow

        user.account_type = "user"
        user.dealer_status = "pending"
        user.dealership_name = (dealership_name or "").strip() or None
        user.dealership_phone = (dealership_phone or "").strip() or None
        user.dealership_location = (dealership_location or "").strip() or None
        application = getattr(user, "dealer_application", None)
        if application is None:
            application = DealerApplication(
                user=user,
                status="submitted",
                dealership_name=user.dealership_name,
                dealership_phone=user.dealership_phone,
                dealership_phones=[user.dealership_phone] if user.dealership_phone else [],
                dealership_location=user.dealership_location,
                submitted_at=utcnow(),
            )
            application.decisions.append(
                DealerDecision(
                    decision="submitted",
                    application_snapshot=application.snapshot(),
                )
            )
    elif not getattr(user, "dealer_status", None):
        user.account_type = "user"
        user.dealer_status = "none"


def _hash_phone_verification_code(phone_digits: str, code: str) -> str:
    # Bind the code to the phone number and SECRET_KEY.
    # This prevents storing OTPs in plaintext and prevents cross-phone reuse.
    key = (current_app.config.get("SECRET_KEY") or "").encode("utf-8")
    msg = f"{phone_digits}:{code}".encode("utf-8")
    return hmac.new(key, msg=msg, digestmod=hashlib.sha256).hexdigest()


def _redis_client():
    url = (os.environ.get("REDIS_URL") or "").strip()
    if not url:
        return None
    try:
        import redis  # type: ignore

        return redis.Redis.from_url(url, decode_responses=True)
    except Exception:
        return None


def _generate_unique_username(prefix: str = "u") -> str:
    # Best-effort unique username generator.
    for _ in range(5):
        candidate = f"{prefix}_{secrets.token_hex(4)}".lower()
        if not User.query.filter_by(username=candidate).first():
            return candidate
    return f"{prefix}_{secrets.token_hex(8)}".lower()


def _get_active_user_by_phone(phone_digits: str) -> User | None:
    return User.query.filter_by(phone_number=phone_digits, is_active=True).first()


def _is_dealer_account(user: User) -> bool:
    account_type = (getattr(user, "account_type", None) or "user").strip().lower()
    dealer_status = (getattr(user, "dealer_status", None) or "none").strip().lower()
    if account_type == "dealer":
        return True
    if dealer_status in (
        "draft",
        "pending",
        "submitted",
        "under_review",
        "needs_changes",
        "approved",
        "rejected",
    ):
        return True
    return False


def _personal_account_exists_response():
    return jsonify({
        "message": "This phone number is registered to a personal account. Please use personal login.",
        "code": "personal_account_exists",
    }), 409


def _dealer_account_exists_response():
    return jsonify({
        "message": "This phone number is registered to a dealer account. Please use dealer login.",
        "code": "dealer_account_exists",
    }), 409


def _reject_dealer_flow_for_personal(user: User | None, *, purpose: str):
    """Block dealer auth when the phone belongs to an established personal account."""
    if purpose != "dealer" or user is None or _is_dealer_account(user):
        return None
    if getattr(user, "is_verified", False):
        return _personal_account_exists_response()
    return None


def _reject_personal_flow_for_dealer(user: User | None, *, purpose: str):
    """Block personal auth when the phone belongs to an established dealer account."""
    if purpose == "dealer" or user is None or not _is_dealer_account(user):
        return None
    if getattr(user, "is_verified", False):
        return _dealer_account_exists_response()
    return None


def _phone_otp_create_if_missing(data: dict) -> bool:
    purpose = (data.get("purpose") or "").strip().lower()
    if purpose == "login":
        return False
    if purpose == "signup":
        return True
    if "create_if_missing" in data:
        return _to_bool(data.get("create_if_missing"))
    return True


def _resolve_user_for_phone_otp(
    phone_digits: str,
    *,
    create_if_missing: bool,
    username: str | None = None,
    first_name: str | None = None,
    last_name: str | None = None,
    password: str | None = None,
    is_dealer_requested: bool = False,
    dealership_name: str | None = None,
    dealership_phone: str | None = None,
    dealership_location: str | None = None,
) -> User:
    if create_if_missing:
        return _get_or_create_user_for_phone(
            phone_digits,
            username=username,
            first_name=first_name,
            last_name=last_name,
            password=password,
            is_dealer_requested=is_dealer_requested,
            dealership_name=dealership_name,
            dealership_phone=dealership_phone,
            dealership_location=dealership_location,
        )
    user = _get_active_user_by_phone(phone_digits)
    if not user:
        raise ValueError("account_not_found")
    return user


def _get_or_create_user_for_phone(
    phone_digits: str,
    *,
    username: str | None = None,
    first_name: str | None = None,
    last_name: str | None = None,
    password: str | None = None,
    is_dealer_requested: bool = False,
    dealership_name: str | None = None,
    dealership_phone: str | None = None,
    dealership_location: str | None = None,
) -> User:
    user = User.query.filter_by(phone_number=phone_digits).first()
    if user:
        if is_dealer_requested and (getattr(user, "dealer_status", "none") in ("none", "", None)):
            _apply_dealer_profile(
                user,
                is_dealer_requested=True,
                dealership_name=dealership_name,
                dealership_phone=dealership_phone,
                dealership_location=dealership_location,
            )
            db.session.commit()
        return user
    u = (username or "").strip()
    if is_dealer_requested:
        u = ""
    fn = (first_name or "").strip()
    ln = (last_name or "").strip()
    # Signup is phone-only; never accept a client-provided email here.
    e = ""

    # Legacy SQLite compatibility: some old DBs require a non-null, unique email.
    # PRAGMA is SQLite-only; on PostgreSQL it would abort the transaction, so skip it.
    try:
        from sqlalchemy import text

        bind = db.session.get_bind()
        if getattr(bind, "dialect", None) and getattr(bind.dialect, "name", None) == "sqlite":
            row = db.session.execute(text("PRAGMA table_info(user)")).fetchall()
            # (cid, name, type, notnull, dflt_value, pk)
            email_required = any((r[1] == "email" and int(r[3] or 0) == 1) for r in row)
            if email_required:
                e = f"{phone_digits}@phone.local"
    except Exception:
        db.session.rollback()

    if u:
        if User.query.filter_by(username=u).first():
            raise ValueError("Username already exists")
    else:
        prefix = "dealer" if is_dealer_requested else "user"
        u = _generate_unique_username(prefix)

    # Create a minimal user; phone OTP verify will mark is_verified true.
    user = User(
        username=u,
        phone_number=phone_digits,
        first_name=fn or "User",
        last_name=ln,
        email=e or None,
        is_active=True,
        is_verified=False,
        public_id=secrets.token_hex(8),
        account_type="user",
        dealer_status="none",
    )
    _apply_dealer_profile(
        user,
        is_dealer_requested=is_dealer_requested,
        dealership_name=dealership_name,
        dealership_phone=dealership_phone,
        dealership_location=dealership_location,
    )
    # Passwordless phone auth still needs a password hash in the current schema.
    pw = (password or "").strip()
    if pw:
        is_valid, message = validate_password(pw)
        if not is_valid:
            raise ValueError(message)
        user.set_password(pw)
    else:
        user.set_password(secrets.token_urlsafe(18))
    db.session.add(user)
    db.session.commit()
    return user


def init_jwt_callbacks(jwt) -> None:
    @jwt.expired_token_loader
    def expired_token_callback(jwt_header, jwt_payload):
        return jsonify({"message": "Token has expired"}), 401

    @jwt.invalid_token_loader
    def invalid_token_callback(error):
        return jsonify({"message": "Invalid token"}), 401

    @jwt.unauthorized_loader
    def missing_token_callback(error):
        return jsonify({"message": "Authorization token is required"}), 401

    @jwt.token_in_blocklist_loader
    def check_if_token_revoked(jwt_header, jwt_payload):
        """Check if token is blacklisted"""
        jti = str(jwt_payload.get("jti") or "")
        if not jti:
            return False

        # Prefer Redis in production (O(1) lookup, no DB query per request).
        r = _redis_client()
        if r is not None:
            try:
                return bool(r.exists(f"bl:jti:{jti}"))
            except Exception:
                # If Redis is down/misconfigured, fall back to DB.
                pass

        token = TokenBlacklist.query.filter_by(jti=jti).first()
        return token is not None

    @jwt.revoked_token_loader
    def revoked_token_callback(jwt_header, jwt_payload):
        return jsonify({"message": "Token has been revoked"}), 401


@bp.route("/api/auth/register", methods=["POST"])
@rate_limit(max_requests=5, window_minutes=60)  # 5 registrations per hour per IP
def register():
    """User registration endpoint"""
    try:
        data = request.get_json()

        # Sanitize input
        data = validate_input_sanitization(data)

        # Validate input
        errors = validate_user_input(data, ["username", "phone_number", "password", "first_name", "last_name"])
        if errors:
            return jsonify({"message": "Validation failed", "errors": errors}), 400

        # Check if user already exists
        if User.query.filter_by(username=data["username"]).first():
            return jsonify({"message": "Username already exists"}), 400

        if User.query.filter_by(phone_number=data["phone_number"]).first():
            return jsonify({"message": "Phone number already exists"}), 400

        # Create new user (phone signup only — ignore any email in payload)
        user = User(
            username=data["username"],
            phone_number=data["phone_number"],
            first_name=data["first_name"],
            last_name=data["last_name"],
            email=None,
        )
        user.set_password(data["password"])

        db.session.add(user)
        db.session.commit()

        log_user_action(user, "register")

        return jsonify({"message": "User registered successfully.", "user": user.to_dict()}), 201

    except Exception as e:
        current_app.logger.exception("registration failed: %s", e)
        return jsonify({"message": "Registration failed"}), 500


@bp.route("/api/auth/register-request", methods=["POST"])
@rate_limit(max_requests=5, window_minutes=60)
def register_request():
    """Email signup removed — use phone OTP."""
    return jsonify(_EMAIL_SIGNUP_GONE), 410


@bp.route("/api/auth/register-confirm", methods=["POST"])
@rate_limit(max_requests=20, window_minutes=60)
def register_confirm():
    """Email signup removed — use phone OTP."""
    return jsonify(_EMAIL_SIGNUP_GONE), 410


@bp.route("/api/auth/login", methods=["POST"])
@rate_limit(max_requests=10, window_minutes=15)  # 10 login attempts per 15 minutes per IP
def login():
    """User login endpoint"""
    try:
        data = request.get_json()

        if not data.get("username") or not data.get("password"):
            return jsonify({"message": "Phone/username and password are required"}), 400

        # Dashboard credentials are intentionally separate from mobile accounts.
        # Deleting a mobile User must not remove the principal used by admin APIs.
        from sqlalchemy import or_

        ident = data["username"]
        account_scope = str(data.get("account_scope") or "").strip().lower()
        admin_account = None
        if account_scope == "admin":
            admin_account = AdminAccount.query.filter(
                or_(
                    AdminAccount.email == ident,
                    AdminAccount.phone_number == ident,
                    AdminAccount.username == ident,
                )
            ).first()
            if not admin_account or not admin_account.check_password(data["password"]):
                return jsonify({"message": "Invalid credentials"}), 401
            user = admin_account.principal
            if (
                not admin_account.is_active
                or not user
                or not user.is_active
                or not user.is_admin
            ):
                return jsonify({"message": "Admin account is deactivated"}), 401
        else:
            # Mobile password login is phone/username only (no email).
            user = User.query.filter(
                or_(User.phone_number == ident, User.username == ident)
            ).first()
            if user and AdminAccount.query.filter_by(principal_user_id=user.id).first():
                return jsonify({"message": "Invalid credentials"}), 401

        if account_scope != "admin" and (
            not user or not user.check_password(data["password"])
        ):
            return jsonify({"message": "Invalid credentials"}), 401

        if not user.is_active:
            return jsonify({"message": "Account is deactivated"}), 401

        # Ensure user has a public_id for JWT identity compatibility
        if not getattr(user, "public_id", None):
            try:
                user.public_id = secrets.token_hex(8)
                db.session.commit()
            except Exception:
                db.session.rollback()

        # Update last login
        from ..time_utils import utcnow

        user.last_login = utcnow()
        if admin_account is not None:
            admin_account.last_login = user.last_login
        db.session.commit()

        identity = getattr(user, "public_id", None) or f"user:{user.id}"
        access_token = create_access_token(identity=identity)
        refresh_token = create_refresh_token(identity=identity)

        log_user_action(user, "login")

        return (
            jsonify(
                {
                    "message": "Login successful",
                    "token": access_token,  # mobile compatibility
                    "access_token": access_token,
                    "refresh_token": refresh_token,
                    "user": user.to_dict(),
                }
            ),
            200,
        )

    except Exception as e:
        current_app.logger.exception("login failed: %s", e)
        return jsonify({"message": "Login failed"}), 500


@bp.route("/api/auth/refresh", methods=["POST"])
@jwt_required(refresh=True)
def refresh():
    """Refresh access token (rotating refresh tokens)."""
    try:
        jwt_payload = get_jwt()
        current_user_id = get_jwt_identity()
        user = User.query.filter_by(public_id=current_user_id).first()

        if not user or not user.is_active:
            return jsonify({"message": "User not found or inactive"}), 401

        # Rotate refresh tokens: revoke the current refresh token jti.
        jti = str(jwt_payload.get("jti") or "")
        exp = int(jwt_payload.get("exp") or 0)
        from ..time_utils import utcnow

        expires_at = datetime.fromtimestamp(exp) if exp else utcnow() + timedelta(days=30)

        if jti:
            blacklisted_token = TokenBlacklist(
                jti=jti,
                token_type="refresh",
                user_id=user.id,
                expires_at=expires_at,
            )
            try:
                db.session.add(blacklisted_token)
                db.session.commit()
            except Exception:
                db.session.rollback()
                # If two refresh requests race, treat as revoked.
                return jsonify({"message": "Token has been revoked"}), 401

            # Redis mirror (best-effort)
            r = _redis_client()
            if r is not None:
                try:
                    ttl = max(1, exp - int(time.time())) if exp else 3600
                    r.setex(f"bl:jti:{jti}", ttl, "1")
                except Exception:
                    pass

        new_access_token = create_access_token(identity=user.public_id)
        new_refresh_token = create_refresh_token(identity=user.public_id)

        return jsonify({"access_token": new_access_token, "refresh_token": new_refresh_token}), 200

    except Exception:
        return jsonify({"message": "Token refresh failed"}), 500


@bp.route("/api/auth/logout", methods=["POST"])
@jwt_required()
def logout():
    """User logout endpoint"""
    try:
        current_user = get_current_user()
        if current_user:
            log_user_action(current_user, "logout")
            try:
                current_user.firebase_token = None
            except Exception:
                pass

        # Blacklist the current token
        jti = get_jwt()["jti"]
        token_type = get_jwt()["type"]
        expires_at = datetime.fromtimestamp(get_jwt()["exp"])

        blacklisted_token = TokenBlacklist(
            jti=jti,
            token_type=token_type,
            user_id=current_user.id if current_user else None,
            expires_at=expires_at,
        )

        db.session.add(blacklisted_token)
        db.session.commit()

        # Best-effort Redis mirror for fast blocklist checks
        r = _redis_client()
        if r is not None:
            try:
                exp = int(get_jwt().get("exp") or 0)
                ttl = max(1, exp - int(time.time())) if exp else 3600
                r.setex(f"bl:jti:{jti}", ttl, "1")
            except Exception:
                pass

        # Optional: revoke refresh token provided by client (same user only).
        data = request.get_json(silent=True) or {}
        raw_refresh = str(data.get("refresh_token") or data.get("refreshToken") or "").strip()
        if raw_refresh:
            try:
                decoded = decode_token(raw_refresh)
                # Ensure it's a refresh token and belongs to the same identity.
                if decoded.get("type") == "refresh" and decoded.get("sub") == get_jwt_identity():
                    rjti = str(decoded.get("jti") or "")
                    rexp = int(decoded.get("exp") or 0)
                    from ..time_utils import utcnow

                    rexpires_at = datetime.fromtimestamp(rexp) if rexp else utcnow() + timedelta(days=30)
                    if rjti:
                        bt = TokenBlacklist(
                            jti=rjti,
                            token_type="refresh",
                            user_id=current_user.id if current_user else None,
                            expires_at=rexpires_at,
                        )
                        try:
                            db.session.add(bt)
                            db.session.commit()
                        except Exception:
                            db.session.rollback()
                        rr = _redis_client()
                        if rr is not None:
                            try:
                                ttl = max(1, rexp - int(time.time())) if rexp else 3600
                                rr.setex(f"bl:jti:{rjti}", ttl, "1")
                            except Exception:
                                pass
            except Exception:
                # Ignore invalid refresh token input
                pass

        return jsonify({"message": "Logout successful"}), 200

    except Exception:
        return jsonify({"message": "Logout failed"}), 500


@bp.route("/api/auth/change-password", methods=["POST"])
@jwt_required()
def change_password():
    """Change password for the authenticated user (current + new password)."""
    try:
        current_user = get_current_user()
        if not current_user:
            return jsonify({"message": "User not found"}), 404

        data = request.get_json(silent=True) or {}
        data = validate_input_sanitization(data)
        current = (data.get("current_password") or data.get("current") or "").strip()
        new_pass = (data.get("new_password") or data.get("password") or "").strip()

        if not current:
            return jsonify({"message": "Current password is required"}), 400
        if not new_pass:
            return jsonify({"message": "New password is required"}), 400

        if not current_user.check_password(current):
            return jsonify({"message": "Current password is incorrect"}), 400

        is_valid, message = validate_password(new_pass)
        if not is_valid:
            return jsonify({"message": message}), 400

        from ..time_utils import utcnow
        current_user.set_password(new_pass)
        current_user.updated_at = utcnow()
        db.session.commit()
        log_user_action(current_user, "password_change")
        return jsonify({"message": "Password changed successfully"}), 200
    except Exception:
        return jsonify({"message": "Failed to change password"}), 500


def _scrub_user_listings_on_delete(user_id: int) -> None:
    """Deactivate and scrub listing PII/media when hard-delete falls back to anonymize."""
    from ..models import Car

    cars = Car.query.filter_by(seller_id=user_id).all()
    for car in cars:
        car.is_active = False
        car.status = "hidden"
        car.description = None
        car.vin = None
        car.location = None
        for img in list(car.images or []):
            db.session.delete(img)
        for vid in list(car.videos or []):
            db.session.delete(vid)


@bp.route("/api/auth/delete-account", methods=["POST", "DELETE"])
@jwt_required()
@rate_limit(max_requests=5, window_minutes=60, per_ip=False)
def delete_account():
    """Permanently delete the authenticated user's account and all related data."""
    try:
        current_user = get_current_user()
        if not current_user:
            return jsonify({"message": "Unauthorized"}), 401
        if AdminAccount.query.filter_by(principal_user_id=current_user.id).first():
            return jsonify({"message": "Dashboard admin accounts cannot be deleted"}), 403

        data = request.get_json(silent=True) or {}
        password = (data.get("password") or data.get("current_password") or "").strip()

        # Always require password confirmation so a stolen JWT alone cannot wipe an account.
        if not password:
            return jsonify({"message": "Password is required to delete your account"}), 400
        if not current_user.check_password(password):
            return jsonify({"message": "Incorrect password"}), 400

        user_id = current_user.id
        bind = db.session.get_bind()
        table_names = set()
        try:
            if bind is not None:
                table_names = set(inspect(bind).get_table_names())
        except Exception:
            table_names = set()

        # Remove many-to-many associations so FK constraints don't block user delete.
        current_user.favorites = []
        current_user.viewed_listings = []

        if "message" in table_names:
            Message.query.filter(
                (Message.sender_id == user_id) | (Message.receiver_id == user_id),
            ).delete(synchronize_session=False)

        if "token_blacklist" in table_names:
            TokenBlacklist.query.filter_by(user_id=user_id).delete()

        if "password_reset" in table_names:
            PasswordReset.query.filter_by(user_id=user_id).delete()
        if "email_verification" in table_names:
            EmailVerification.query.filter_by(user_id=user_id).delete()

        if "saved_search" in table_names:
            from ..models import SavedSearch

            SavedSearch.query.filter_by(user_id=user_id).delete(synchronize_session=False)

        log_user_action(current_user, "account_deleted")

        try:
            db.session.delete(current_user)
            db.session.commit()
            return jsonify({"message": "Account deleted successfully"}), 200
        except Exception as hard_delete_error:
            # Fallback: anonymize/deactivate and scrub listings so PII/media are not left public.
            db.session.rollback()
            suffix = secrets.token_hex(4)
            from ..time_utils import utcnow

            # Re-load user after rollback
            current_user = db.session.get(User, user_id)
            if not current_user:
                return jsonify({"message": "Account deleted successfully"}), 200

            # Re-apply association clears after rollback
            current_user.favorites = []
            current_user.viewed_listings = []
            if "message" in table_names:
                Message.query.filter(
                    (Message.sender_id == user_id) | (Message.receiver_id == user_id),
                ).delete(synchronize_session=False)
            if "saved_search" in table_names:
                from ..models import SavedSearch

                SavedSearch.query.filter_by(user_id=user_id).delete(
                    synchronize_session=False
                )
            try:
                _scrub_user_listings_on_delete(user_id)
            except Exception as scrub_err:
                current_app.logger.warning(
                    "Listing scrub failed during anonymize for user_id=%s: %s",
                    user_id,
                    scrub_err,
                )

            current_user.username = f"deleted_{suffix}"
            current_user.phone_number = f"del_{int(time.time())}_{suffix}"[:20]
            current_user.email = None
            current_user.first_name = "Deleted"
            current_user.last_name = "User"
            current_user.is_active = False
            current_user.is_verified = False
            try:
                current_user.phone_verified = False
            except Exception:
                pass
            current_user.firebase_token = None
            current_user.set_password(secrets.token_urlsafe(24))
            current_user.updated_at = utcnow()
            db.session.commit()
            current_app.logger.warning(
                "Hard delete failed for user_id=%s; account anonymized instead: %s",
                user_id,
                str(hard_delete_error),
            )
            return jsonify({"message": "Account removed successfully"}), 200
    except Exception as e:
        db.session.rollback()
        current_app.logger.exception("delete_account failed: %s", e)
        return jsonify({"message": "Failed to delete account"}), 500


@bp.route("/api/auth/forgot-password", methods=["POST"])
@rate_limit(max_requests=5, window_minutes=15)  # 5 requests per 15 min per IP
def forgot_password():
    """Forgot password via SMS only."""
    try:
        data = request.get_json(silent=True) or {}
        data = validate_input_sanitization(data)
        raw_phone = (data.get("phone_number") or data.get("phone") or "").strip()
        phone_digits = _normalize_phone(raw_phone)

        if not phone_digits:
            return jsonify({"message": "Phone number is required"}), 400

        user = User.query.filter_by(phone_number=phone_digits).first()

        # Prevent account enumeration: always return 200.
        if not user:
            current_app.logger.info(
                "[FORGOT-PASSWORD] No account found for this phone; no SMS sent (still return 200)."
            )
            return jsonify({"message": "If the account exists, a reset code has been sent"}), 200

        dest_phone = getattr(user, "phone_number", None) or phone_digits
        token = create_password_reset_token(user, channel="sms")

        from ..sms_service import send_password_reset_sms

        sms_sent = bool(send_password_reset_sms(dest_phone, token))
        if not sms_sent:
            current_app.logger.warning(
                "[FORGOT-PASSWORD] SMS send failed for phone=%s*** (provider config/number format?)",
                str(dest_phone)[:4],
            )

        # Dev convenience for local testing with SMS_PROVIDER=console.
        # Never expose reset tokens in production.
        env_name = (os.environ.get("APP_ENV") or os.environ.get("FLASK_ENV") or "").strip().lower()
        sms_provider = (os.environ.get("SMS_PROVIDER") or "console").strip().lower()
        if env_name in ("development", "testing") and sms_provider == "console" and sms_sent:
            return jsonify(
                {"message": "If the account exists, a reset code has been sent", "dev_code": token}
            ), 200

        return jsonify({"message": "If the account exists, a reset code has been sent"}), 200

    except Exception:
        return jsonify({"message": "Password reset request failed"}), 500


@bp.route("/api/auth/reset-password", methods=["POST"])
@rate_limit(max_requests=10, window_minutes=15)  # 10 attempts per 15 min per IP
def reset_password():
    """Reset password endpoint"""
    token = None  # for logging in case of unexpected errors
    try:
        data = request.get_json(silent=True) or {}
        token = data.get("token")
        new_password = data.get("password")

        if not token or not new_password:
            return jsonify({"message": "Token and new password are required"}), 400

        is_valid, message = validate_password(new_password)
        if not is_valid:
            return jsonify({"message": message}), 400

        user, error = verify_password_reset_token(token)
        if not user:
            return jsonify({"message": error}), 400

        # Per-account limit (in addition to IP decorator) to slow SMS code guessing.
        try:
            from ..security import _redis_client

            r = _redis_client()
            if r is not None:
                ukey = f"rl:reset_password:user:{user.id}:900"
                n = int(r.incr(ukey) or 0)
                if n == 1:
                    r.expire(ukey, 900)
                if n > 5:
                    return (
                        jsonify(
                            {
                                "message": "Too many reset attempts. Try again later.",
                                "retry_after": max(0, int(r.ttl(ukey) or 0)),
                            }
                        ),
                        429,
                    )
        except Exception:
            pass

        user.set_password(new_password)

        reset_token = PasswordReset.query.filter_by(token=token).first()
        if reset_token:
            reset_token.is_used = True

        db.session.commit()

        log_user_action(user, "password_reset")

        return jsonify({"message": "Password reset successful"}), 200

    except Exception as e:
        # Log without including the raw token value for safety.
        token_len = len(str(token)) if token is not None else 0
        current_app.logger.exception(
            "[RESET-PASSWORD] Unexpected error (token_len=%s): %s", token_len, str(e)
        )
        return jsonify({"message": "Password reset failed"}), 500


@bp.route("/api/auth/send-email-verification", methods=["POST"])
@jwt_required()
@rate_limit(max_requests=5, window_minutes=15)
def send_email_verification():
    """Send email verification link to the current user's email."""
    try:
        current_user = get_current_user()
        if not current_user:
            return jsonify({"message": "Unauthorized"}), 401
        user_email = (getattr(current_user, "email", None) or "").strip().lower()
        if not user_email or user_email.endswith("@phone.local"):
            return jsonify({"message": "No email address to verify"}), 400
        token = create_email_verification_token(current_user)
        if _send_email_verification_email(user_email, token):
            return jsonify({"message": "Verification email sent. Check your inbox and spam."}), 200
        return jsonify({"message": "Failed to send verification email. Try again later."}), 500
    except Exception:
        return jsonify({"message": "Failed to send verification email"}), 500


@bp.route("/api/auth/verify-email", methods=["POST"])
@rate_limit(max_requests=10, window_minutes=15)
def verify_email():
    """Verify email using token from the verification email link or code."""
    try:
        data = request.get_json(silent=True) or {}
        token = (data.get("token") or "").strip()
        if not token:
            return jsonify({"message": "Token is required"}), 400
        user, error = verify_email_verification_token(token)
        if not user:
            return jsonify({"message": error or "Invalid or expired token"}), 400
        user.is_verified = True
        db.session.commit()
        log_user_action(user, "email_verified")
        return jsonify({"message": "Email verified successfully"}), 200
    except Exception:
        return jsonify({"message": "Email verification failed"}), 500


@bp.route("/api/auth/verify-phone", methods=["POST"])
@rate_limit(max_requests=20, window_minutes=15)
def verify_phone():
    """Phone verification endpoint"""
    try:
        data = request.get_json(silent=True) or {}
        data = validate_input_sanitization(data)
        raw_phone = (data.get("phone_number") or data.get("phone") or "").strip()
        verification_code = str(data.get("verification_code") or "").strip()

        phone_digits = _normalize_phone(raw_phone)
        if not phone_digits or not verification_code:
            return jsonify({"message": "Phone number and verification code are required"}), 400

        user = User.query.filter_by(phone_number=phone_digits).first()
        if not user:
            return jsonify({"message": "User not found"}), 404

        if bool(getattr(user, "phone_verified", False)):
            return jsonify({"message": "Phone number verified successfully"}), 200

        if len(verification_code) != 6 or not verification_code.isdigit():
            return jsonify({"message": "Invalid or expired verification code"}), 400

        from ..time_utils import utcnow

        now = utcnow()
        locked_until = getattr(user, "phone_verification_locked_until", None)
        if locked_until and locked_until > now:
            return jsonify({"message": "Too many attempts. Please try again later."}), 429

        expires_at = getattr(user, "phone_verification_expires_at", None)
        code_hash = getattr(user, "phone_verification_code_hash", None)
        if not expires_at or not code_hash or expires_at <= now:
            # Clear stale state so the next send starts clean.
            user.phone_verification_code_hash = None
            user.phone_verification_expires_at = None
            user.phone_verification_attempts = 0
            db.session.commit()
            return jsonify({"message": "Invalid or expired verification code"}), 400

        expected = _hash_phone_verification_code(phone_digits, verification_code)
        if not hmac.compare_digest(code_hash, expected):
            attempts = int(getattr(user, "phone_verification_attempts", 0) or 0) + 1
            user.phone_verification_attempts = attempts
            if attempts >= 5:
                user.phone_verification_locked_until = now + timedelta(minutes=15)
                user.phone_verification_code_hash = None
                user.phone_verification_expires_at = None
                user.phone_verification_attempts = 0
            db.session.commit()
            return jsonify({"message": "Invalid or expired verification code"}), 400

        user.is_verified = True
        user.phone_verified = True
        user.phone_verification_code_hash = None
        user.phone_verification_expires_at = None
        user.phone_verification_attempts = 0
        user.phone_verification_locked_until = None
        db.session.commit()
        log_user_action(user, "phone_verified")
        return jsonify({"message": "Phone number verified successfully"}), 200

    except Exception:
        return jsonify({"message": "Phone verification failed"}), 500


@bp.route("/api/auth/send_otp", methods=["POST"])
@rate_limit(max_requests=_SEND_OTP_MAX_REQUESTS, window_minutes=_SEND_OTP_WINDOW_MINUTES)
def send_otp_legacy():
    """Legacy alias: same as send-verification, accepts 'phone' or 'phone_number'."""
    return send_phone_verification()


@bp.route("/api/auth/send-verification", methods=["POST"])
@rate_limit(max_requests=_SEND_OTP_MAX_REQUESTS, window_minutes=_SEND_OTP_WINDOW_MINUTES)
def send_phone_verification():
    """Send phone verification code"""
    try:
        db.session.rollback()
        data = request.get_json(silent=True) or {}
        data = validate_input_sanitization(data)
        raw_phone = (data.get("phone_number") or data.get("phone") or "").strip()

        phone_digits = _normalize_phone(raw_phone)
        if not phone_digits:
            return jsonify({"message": "Phone number is required"}), 400

        is_dealer_requested = _to_bool(data.get("is_dealer"))
        dealership_name = (data.get("dealership_name") or "").strip()
        dealership_phone = (data.get("dealership_phone") or "").strip()
        dealership_location = (data.get("dealership_location") or "").strip()
        if is_dealer_requested:
            if not dealership_name:
                return jsonify({"message": "Dealership name is required for dealer accounts"}), 400
            if not dealership_phone:
                return jsonify({"message": "Dealership phone is required for dealer accounts"}), 400
            if not dealership_location:
                return jsonify({"message": "Dealership location is required for dealer accounts"}), 400

        # For legacy signup flow: get or create user so we can send OTP to any phone.
        user = User.query.filter_by(phone_number=phone_digits).first()
        if not user:
            try:
                user = _get_or_create_user_for_phone(
                    phone_digits,
                    is_dealer_requested=is_dealer_requested,
                    dealership_name=dealership_name or None,
                    dealership_phone=dealership_phone or None,
                    dealership_location=dealership_location or None,
                )
            except ValueError as e:
                return jsonify({"message": str(e)}), 400
            except IntegrityError:
                db.session.rollback()
                return jsonify({"message": "Account already exists. Please log in."}), 400

        if user.is_verified:
            return jsonify({"message": "Phone number is already verified"}), 200

        from ..time_utils import utcnow

        now = utcnow()
        locked_until = getattr(user, "phone_verification_locked_until", None)
        if locked_until and locked_until > now:
            return jsonify({"message": "Too many attempts. Please try again later."}), 429

        last_sent = getattr(user, "phone_verification_last_sent_at", None)
        if last_sent and (now - last_sent).total_seconds() < 60:
            return jsonify({"message": "Please wait before requesting another code"}), 429

        verification_code = f"{secrets.randbelow(1_000_000):06d}"
        user.phone_verification_code_hash = _hash_phone_verification_code(phone_digits, verification_code)
        user.phone_verification_expires_at = now + timedelta(minutes=10)
        user.phone_verification_attempts = 0
        user.phone_verification_last_sent_at = now
        user.phone_verification_locked_until = None
        db.session.commit()

        from ..sms_service import send_verification_sms_result

        sms_sent, sms_detail = send_verification_sms_result(
            phone_digits, verification_code
        )
        if not sms_sent:
            # Do not leave a potentially valid code in DB if SMS failed.
            user.phone_verification_code_hash = None
            user.phone_verification_expires_at = None
            user.phone_verification_attempts = 0
            user.phone_verification_locked_until = None
            db.session.commit()
            err_msg = "Failed to send verification code"
            current_app.logger.error(
                "send-verification SMS failed provider=%s detail=%s",
                (os.environ.get("SMS_PROVIDER") or "console").strip().lower(),
                sms_detail or "unknown",
            )
            # Legacy client expects 200 with sent: false and error (and optional dev_code in dev).
            payload = {"sent": False, "error": err_msg, "message": err_msg}
            if sms_detail:
                payload["detail"] = sms_detail
            if current_app.config.get("DEBUG") or (os.environ.get("APP_ENV") or "").strip().lower() == "development":
                payload["dev_code"] = verification_code
            return jsonify(payload), 200

        # Legacy client expects sent: true on success.
        return jsonify({"message": "Verification code sent successfully", "sent": True}), 200

    except Exception as e:
        db.session.rollback()
        current_app.logger.exception("send_phone_verification failed: %s", e)
        msg = "Failed to send verification code"
        if current_app.config.get("DEBUG") or (os.environ.get("APP_ENV") or "").strip().lower() == "development":
            msg = f"{msg}: {str(e)}"
        return jsonify({"message": msg}), 500


# --- Phone OTP auth endpoints ---

@bp.route("/api/auth/phone/start", methods=["POST"])
def phone_start():
    """Start phone OTP login/signup (passwordless)."""
    try:
        data = request.get_json(silent=True) or {}
        data = validate_input_sanitization(data)
        raw_phone = (data.get("phone_number") or data.get("phone") or "").strip()
        is_dealer_requested = _to_bool(data.get("is_dealer"))
        dealership_name = (data.get("dealership_name") or "").strip()
        dealership_phone = (data.get("dealership_phone") or "").strip()
        dealership_location = (data.get("dealership_location") or "").strip()
        phone_digits = _normalize_phone(raw_phone)
        if not phone_digits:
            return jsonify({"message": "Phone number is required"}), 400
        if is_dealer_requested:
            if not dealership_name:
                return jsonify({"message": "Dealership name is required for dealer accounts"}), 400
            if not dealership_phone:
                return jsonify({"message": "Dealership phone is required for dealer accounts"}), 400
            if not dealership_location:
                return jsonify({"message": "Dealership location is required for dealer accounts"}), 400

        create_if_missing = _phone_otp_create_if_missing(data)
        purpose = (data.get("purpose") or "").strip().lower()
        existing = _get_active_user_by_phone(phone_digits)
        personal_conflict = _reject_dealer_flow_for_personal(existing, purpose=purpose)
        if personal_conflict is not None:
            return personal_conflict
        dealer_conflict = _reject_personal_flow_for_dealer(existing, purpose=purpose)
        if dealer_conflict is not None:
            return dealer_conflict
        if not create_if_missing and not existing:
            return jsonify({
                "message": "No account found with this phone number. Please sign up first.",
                "code": "account_not_found",
            }), 404

        limited = check_rate_limit(
            max_requests=_SEND_OTP_MAX_REQUESTS,
            window_minutes=_SEND_OTP_WINDOW_MINUTES,
        )
        if limited is not None:
            return limited

        try:
            user = _resolve_user_for_phone_otp(
                phone_digits,
                create_if_missing=create_if_missing,
                username=(data.get("username") or None),
                first_name=(data.get("first_name") or data.get("firstName") or None),
                last_name=(data.get("last_name") or data.get("lastName") or None),
                password=(data.get("password") or None),
                is_dealer_requested=is_dealer_requested,
                dealership_name=dealership_name or None,
                dealership_phone=dealership_phone or None,
                dealership_location=dealership_location or None,
            )
        except ValueError as e:
            if str(e) == "account_not_found":
                return jsonify({
                    "message": "No account found with this phone number. Please sign up first.",
                    "code": "account_not_found",
                }), 404
            current_app.logger.info("phone_start validation error: %s", str(e))
            return jsonify({"message": "Invalid input"}), 400
        if user.is_verified:
            # Still allow OTP for login, but treat as normal flow.
            pass

        from ..time_utils import utcnow

        now = utcnow()
        locked_until = getattr(user, "phone_verification_locked_until", None)
        if locked_until and locked_until > now:
            return jsonify({"message": "Too many attempts. Please try again later."}), 429

        last_sent = getattr(user, "phone_verification_last_sent_at", None)
        if last_sent and (now - last_sent).total_seconds() < 60:
            return jsonify({"message": "Please wait before requesting another code"}), 429

        verification_code = f"{secrets.randbelow(1_000_000):06d}"
        user.phone_verification_code_hash = _hash_phone_verification_code(phone_digits, verification_code)
        user.phone_verification_expires_at = now + timedelta(minutes=10)
        user.phone_verification_attempts = 0
        user.phone_verification_last_sent_at = now
        user.phone_verification_locked_until = None
        db.session.commit()

        from ..sms_service import send_verification_sms_result

        sms_sent, sms_detail = send_verification_sms_result(
            phone_digits, verification_code
        )
        if not sms_sent:
            user.phone_verification_code_hash = None
            user.phone_verification_expires_at = None
            user.phone_verification_attempts = 0
            user.phone_verification_locked_until = None
            db.session.commit()
            current_app.logger.error(
                "phone_start SMS failed provider=%s detail=%s",
                (os.environ.get("SMS_PROVIDER") or "console").strip().lower(),
                sms_detail or "unknown",
            )
            payload = {
                "message": "Failed to send verification code",
                "code": "sms_send_failed",
            }
            if sms_detail:
                payload["detail"] = sms_detail
            return jsonify(payload), 500

        # Dev convenience: when using console SMS provider, return the OTP in development/testing only.
        # Never include the OTP in production responses.
        env_name = (os.environ.get("APP_ENV") or "").strip().lower()
        sms_provider = (os.environ.get("SMS_PROVIDER") or "console").strip().lower()
        if env_name in ("development", "testing") and sms_provider == "console":
            return jsonify({"message": "OTP sent", "dev_code": verification_code}), 200
        return jsonify({"message": "OTP sent"}), 200
    except Exception:
        current_app.logger.exception("phone_start failed")
        return jsonify({"message": "Failed to start phone verification"}), 500


@bp.route("/api/auth/phone/verify", methods=["POST"])
@rate_limit(max_requests=10, window_minutes=15)
def phone_verify():
    """Verify phone OTP and issue tokens."""
    try:
        data = request.get_json(silent=True) or {}
        data = validate_input_sanitization(data)
        raw_phone = (data.get("phone_number") or data.get("phone") or "").strip()
        code = str(data.get("code") or data.get("verification_code") or "").strip()
        is_dealer_requested = _to_bool(data.get("is_dealer"))
        dealership_name = (data.get("dealership_name") or "").strip()
        dealership_phone = (data.get("dealership_phone") or "").strip()
        dealership_location = (data.get("dealership_location") or "").strip()
        phone_digits = _normalize_phone(raw_phone)
        if not phone_digits or not code:
            return jsonify({"message": "Phone number and code are required"}), 400
        if is_dealer_requested:
            if not dealership_name:
                return jsonify({"message": "Dealership name is required for dealer accounts"}), 400
            if not dealership_phone:
                return jsonify({"message": "Dealership phone is required for dealer accounts"}), 400
            if not dealership_location:
                return jsonify({"message": "Dealership location is required for dealer accounts"}), 400
        if len(code) != 6 or not code.isdigit():
            return jsonify({"message": "Invalid or expired verification code"}), 400

        create_if_missing = _phone_otp_create_if_missing(data)
        purpose = (data.get("purpose") or "").strip().lower()
        try:
            user = _resolve_user_for_phone_otp(
                phone_digits,
                create_if_missing=create_if_missing,
                username=(data.get("username") or None),
                first_name=(data.get("first_name") or data.get("firstName") or None),
                last_name=(data.get("last_name") or data.get("lastName") or None),
                password=(data.get("password") or None),
                is_dealer_requested=is_dealer_requested,
                dealership_name=dealership_name or None,
                dealership_phone=dealership_phone or None,
                dealership_location=dealership_location or None,
            )
        except ValueError as e:
            if str(e) == "account_not_found":
                return jsonify({
                    "message": "No account found with this phone number. Please sign up first.",
                    "code": "account_not_found",
                }), 404
            current_app.logger.info("phone_verify validation error: %s", str(e))
            return jsonify({"message": "Invalid input"}), 400

        personal_conflict = _reject_dealer_flow_for_personal(user, purpose=purpose)
        if personal_conflict is not None:
            return personal_conflict
        dealer_conflict = _reject_personal_flow_for_dealer(user, purpose=purpose)
        if dealer_conflict is not None:
            return dealer_conflict

        from ..time_utils import utcnow

        now = utcnow()
        locked_until = getattr(user, "phone_verification_locked_until", None)
        if locked_until and locked_until > now:
            return jsonify({"message": "Too many attempts. Please try again later."}), 429

        expires_at = getattr(user, "phone_verification_expires_at", None)
        code_hash = getattr(user, "phone_verification_code_hash", None)
        if not expires_at or not code_hash or expires_at <= now:
            return jsonify({"message": "Invalid or expired verification code"}), 400

        expected = _hash_phone_verification_code(phone_digits, code)
        if not hmac.compare_digest(code_hash, expected):
            attempts = int(getattr(user, "phone_verification_attempts", 0) or 0) + 1
            user.phone_verification_attempts = attempts
            if attempts >= 5:
                user.phone_verification_locked_until = now + timedelta(minutes=15)
                user.phone_verification_code_hash = None
                user.phone_verification_expires_at = None
                user.phone_verification_attempts = 0
            db.session.commit()
            return jsonify({"message": "Invalid or expired verification code"}), 400

        user.is_verified = True
        user.phone_verified = True
        user.phone_verification_code_hash = None
        user.phone_verification_expires_at = None
        user.phone_verification_attempts = 0
        user.phone_verification_locked_until = None
        user.last_login = now
        db.session.commit()

        identity = getattr(user, "public_id", None) or f"user:{user.id}"
        access_token = create_access_token(identity=identity)
        refresh_token = create_refresh_token(identity=identity)
        log_user_action(user, "login_phone")
        return jsonify({"access_token": access_token, "refresh_token": refresh_token, "user": user.to_dict()}), 200
    except Exception:
        return jsonify({"message": "Phone verification failed"}), 500


@bp.route("/api/auth/signup", methods=["POST"])
@rate_limit(max_requests=_SIGNUP_MAX_REQUESTS, window_minutes=_SIGNUP_WINDOW_MINUTES)
def compat_signup():
    """
    Compatibility signup endpoint for mobile client.
    Supports legacy phone flow: when otp_code + phone are sent, verify OTP and complete signup (update user, return tokens).
    """
    try:
        data = request.get_json(silent=True) or {}
        data = validate_input_sanitization(data)

        raw_username = (data.get("username") or "").strip()
        raw_phone = (data.get("phone") or data.get("phone_number") or "").strip()
        password = (data.get("password") or "").strip()
        first_name = (data.get("first_name") or "User").strip()
        last_name = (data.get("last_name") or "Demo").strip()
        otp_code = (data.get("otp_code") or "").strip()
        is_dealer_requested = _to_bool(data.get("is_dealer"))
        dealership_name = (data.get("dealership_name") or "").strip()
        dealership_phone = (data.get("dealership_phone") or "").strip()
        dealership_location = (data.get("dealership_location") or "").strip()

        phone_digits = _normalize_phone(raw_phone)

        # Legacy phone signup: user already received OTP via send_otp; verify code and complete account.
        if otp_code and phone_digits:
            user = User.query.filter_by(phone_number=phone_digits).first()
            if not user:
                return jsonify({"message": "User not found. Request a new code."}), 404
            if not password:
                return jsonify({"message": "Password is required"}), 400
            if is_dealer_requested:
                if not dealership_name:
                    return jsonify({"message": "Dealership name is required for dealer accounts"}), 400
                if not dealership_phone:
                    return jsonify({"message": "Dealership phone is required for dealer accounts"}), 400
                if not dealership_location:
                    return jsonify({"message": "Dealership location is required for dealer accounts"}), 400
            is_valid, msg = validate_password(password)
            if not is_valid:
                return jsonify({"message": msg}), 400
            from ..time_utils import utcnow
            now = utcnow()
            code_hash = getattr(user, "phone_verification_code_hash", None)
            expires_at = getattr(user, "phone_verification_expires_at", None)
            if not code_hash or not expires_at or expires_at <= now:
                user.phone_verification_code_hash = None
                user.phone_verification_expires_at = None
                db.session.commit()
                return jsonify({"message": "Invalid or expired code. Request a new one."}), 400
            if len(otp_code) != 6 or not otp_code.isdigit():
                return jsonify({"message": "Invalid verification code"}), 400
            expected = _hash_phone_verification_code(phone_digits, otp_code)
            if not hmac.compare_digest(code_hash, expected):
                return jsonify({"message": "Invalid or expired verification code"}), 400
            if is_dealer_requested:
                new_u = _generate_unique_username("dealer")
                for _ in range(12):
                    existing = User.query.filter(func.lower(User.username) == new_u.lower()).first()
                    if existing is None or existing.id == user.id:
                        break
                    new_u = _generate_unique_username("dealer")
                user.username = new_u
            else:
                username = (
                    raw_username
                    or getattr(user, "username", "")
                    or f"user_{secrets.token_hex(3)}"
                ).strip().lower()
                if username and username != (getattr(user, "username") or ""):
                    existing = User.query.filter(func.lower(User.username) == username.lower()).first()
                    if existing and existing.id != user.id:
                        return jsonify({"message": "Username already exists"}), 400
                    user.username = username
            user.first_name = first_name or user.first_name or "User"
            user.last_name = last_name or user.last_name or ""
            user.set_password(password)
            user.is_verified = True
            user.phone_verified = True
            _apply_dealer_profile(
                user,
                is_dealer_requested=is_dealer_requested,
                dealership_name=dealership_name or None,
                dealership_phone=dealership_phone or None,
                dealership_location=dealership_location or None,
            )
            user.phone_verification_code_hash = None
            user.phone_verification_expires_at = None
            user.phone_verification_attempts = 0
            user.phone_verification_locked_until = None
            db.session.commit()
            log_user_action(user, "phone_verified")
            identity = getattr(user, "public_id", None) or f"user:{user.id}"
            access_token = create_access_token(identity=identity)
            refresh_token = create_refresh_token(identity=identity)
            return jsonify({
                "message": "Signup successful",
                "token": access_token,
                "access_token": access_token,
                "refresh_token": refresh_token,
                "user": user.to_dict(),
            }), 201

        if not phone_digits:
            phone_digits = f"070{secrets.randbelow(10**8):08d}"
        if is_dealer_requested:
            username = _generate_unique_username("dealer")
            while User.query.filter(func.lower(User.username) == username.lower()).first():
                username = _generate_unique_username("dealer")
        else:
            username = (
                raw_username
                or phone_digits
                or f"user_{secrets.token_hex(3)}"
            ).lower()
        if not password:
            return jsonify({"message": "Password is required"}), 400
        if is_dealer_requested:
            if not dealership_name:
                return jsonify({"message": "Dealership name is required for dealer accounts"}), 400
            if not dealership_phone:
                return jsonify({"message": "Dealership phone is required for dealer accounts"}), 400
            if not dealership_location:
                return jsonify({"message": "Dealership location is required for dealer accounts"}), 400
        is_valid, message = validate_password(password)
        if not is_valid:
            return jsonify({"message": message}), 400

        existing_phone = User.query.filter_by(phone_number=phone_digits).first()
        if existing_phone:
            return jsonify({"message": "Phone number already exists"}), 400

        existing_username = User.query.filter(func.lower(User.username) == username.lower()).first()
        if existing_username:
            return jsonify({"message": "Username already exists"}), 400

        user = User(
            username=username,
            phone_number=phone_digits,
            first_name=first_name,
            last_name=last_name,
            # Signup is phone-only; keep email NULL (empty string would collide on UNIQUE).
            email=None,
            is_active=True,
            public_id=secrets.token_hex(8),
            account_type="user",
            dealer_status="none",
        )
        _apply_dealer_profile(
            user,
            is_dealer_requested=is_dealer_requested,
            dealership_name=dealership_name or None,
            dealership_phone=dealership_phone or None,
            dealership_location=dealership_location or None,
        )
        user.set_password(password)
        db.session.add(user)
        db.session.commit()

        identity = user.public_id
        access_token = create_access_token(identity=identity)
        refresh_token = create_refresh_token(identity=identity)
        return (
            jsonify(
                {
                    "message": "Signup successful",
                    "token": access_token,
                    "access_token": access_token,
                    "refresh_token": refresh_token,
                    "user": user.to_dict(),
                }
            ),
            201,
        )
    except IntegrityError:
        db.session.rollback()
        # Unique constraint collisions, schema issues, etc. Return a safe message.
        current_app.logger.warning(
            "compat_signup integrity error",
            extra={
                "username": (raw_username or "")[:120],
                "phone_digits": (phone_digits or "")[:32],
            },
            exc_info=True,
        )
        return jsonify({"message": "Account already exists. Please log in."}), 409

    except Exception as e:
        db.session.rollback()
        current_app.logger.exception(
            "compat_signup failed: %s",
            e,
            extra={
                "username": (raw_username or "")[:120],
                "phone_digits": (phone_digits or "")[:32],
            },
        )
        # During active testing, always surface the underlying error message so
        # the mobile client can display it and we can debug quickly.
        return jsonify({"message": f"Signup failed: {str(e)}"}), 500


@bp.route("/api/auth/me", methods=["GET"])
@jwt_required()
def compat_auth_me():
    try:
        current_user = get_current_user()
        if not current_user:
            return jsonify({"message": "Unauthorized"}), 401
        return jsonify(current_user.to_dict(include_private=True)), 200
    except Exception:
        return jsonify({"message": "Failed to get profile"}), 500

