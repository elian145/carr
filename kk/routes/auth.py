from __future__ import annotations

import hashlib
import hmac
import os
import secrets
import time
from datetime import datetime, timedelta

from flask import Blueprint, current_app, jsonify, request
from flask_jwt_extended import (
    create_access_token,
    create_refresh_token,
    decode_token,
    get_jwt,
    get_jwt_identity,
    jwt_required,
)
from sqlalchemy.exc import IntegrityError

from ..auth import (
    create_password_reset_token,
    get_current_user,
    log_user_action,
    validate_email,
    validate_password,
    validate_user_input,
    verify_password_reset_token,
)
from ..models import PasswordReset, TokenBlacklist, User, db
from ..security import rate_limit, validate_input_sanitization

bp = Blueprint("auth", __name__)


def _normalize_phone(raw_phone: str) -> str:
    digits = "".join(ch for ch in (raw_phone or "") if ch.isdigit())
    # Legacy clients commonly send Iraqi numbers; keep the last 11 digits
    # to match the existing compat signup normalization.
    if len(digits) > 11:
        digits = digits[-11:]
    return digits


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


def _get_or_create_user_for_phone(
    phone_digits: str,
    *,
    username: str | None = None,
    first_name: str | None = None,
    last_name: str | None = None,
    email: str | None = None,
    password: str | None = None,
) -> User:
    user = User.query.filter_by(phone_number=phone_digits).first()
    if user:
        return user
    u = (username or "").strip()
    e = (email or "").strip().lower()
    fn = (first_name or "").strip()
    ln = (last_name or "").strip()

    # Legacy SQLite compatibility: some old DBs require a non-null, unique email.
    # If no email was provided, derive a stable placeholder from the phone number.
    # We treat this as internal-only (client should not rely on it).
    if not e:
        try:
            from sqlalchemy import text

            row = db.session.execute(text("PRAGMA table_info(user)")).fetchall()
            # (cid, name, type, notnull, dflt_value, pk)
            email_required = any((r[1] == "email" and int(r[3] or 0) == 1) for r in row)
            if email_required:
                e = f"{phone_digits}@phone.local"
        except Exception:
            pass

    if e:
        if not validate_email(e):
            raise ValueError("Invalid email")
        if User.query.filter_by(email=e).first():
            raise ValueError("Email already exists")

    if u:
        if User.query.filter_by(username=u).first():
            raise ValueError("Username already exists")
    else:
        u = _generate_unique_username("user")

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

        # Create new user
        user = User(
            username=data["username"],
            phone_number=data["phone_number"],
            first_name=data["first_name"],
            last_name=data["last_name"],
            email=data.get("email"),  # Email is optional
        )
        user.set_password(data["password"])

        db.session.add(user)
        db.session.commit()

        log_user_action(user, "register")

        return jsonify({"message": "User registered successfully.", "user": user.to_dict()}), 201

    except Exception as e:
        current_app.logger.exception("registration failed: %s", e)
        return jsonify({"message": "Registration failed"}), 500


@bp.route("/api/auth/login", methods=["POST"])
@rate_limit(max_requests=10, window_minutes=15)  # 10 login attempts per 15 minutes per IP
def login():
    """User login endpoint"""
    try:
        data = request.get_json()

        if not data.get("username") or not data.get("password"):
            return jsonify({"message": "Email/phone and password are required"}), 400

        # Find user by email, phone number, or username (support legacy clients)
        from sqlalchemy import or_

        ident = data["username"]
        user = User.query.filter(or_(User.email == ident, User.phone_number == ident, User.username == ident)).first()

        if not user or not user.check_password(data["password"]):
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


@bp.route("/api/auth/forgot-password", methods=["POST"])
def forgot_password():
    """Forgot password endpoint"""
    try:
        data = request.get_json(silent=True) or {}
        data = validate_input_sanitization(data)
        raw_phone = (data.get("phone_number") or data.get("phone") or "").strip()
        email = (data.get("email") or "").strip().lower()

        phone_digits = _normalize_phone(raw_phone)
        user = None
        if phone_digits:
            user = User.query.filter_by(phone_number=phone_digits).first()
        elif email:
            user = User.query.filter_by(email=email).first()
        else:
            return jsonify({"message": "Phone number or email is required"}), 400

        # Prevent account enumeration: always return 200.
        if not user:
            return jsonify({"message": "If the account exists, a reset code has been sent"}), 200

        token = create_password_reset_token(user)

        # Prefer SMS if we have a phone number on record.
        dest_phone = phone_digits or (getattr(user, "phone_number", None) or "")
        if dest_phone:
            from ..sms_service import send_password_reset_sms

            send_password_reset_sms(dest_phone, token)

        return jsonify({"message": "If the account exists, a reset code has been sent"}), 200

    except Exception:
        return jsonify({"message": "Password reset request failed"}), 500


@bp.route("/api/auth/reset-password", methods=["POST"])
def reset_password():
    """Reset password endpoint"""
    try:
        data = request.get_json()
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

        user.set_password(new_password)

        reset_token = PasswordReset.query.filter_by(token=token).first()
        if reset_token:
            reset_token.is_used = True

        db.session.commit()

        log_user_action(user, "password_reset")

        return jsonify({"message": "Password reset successful"}), 200

    except Exception:
        return jsonify({"message": "Password reset failed"}), 500


@bp.route("/api/auth/verify-phone", methods=["POST"])
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

        if user.is_verified:
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
        user.phone_verification_code_hash = None
        user.phone_verification_expires_at = None
        user.phone_verification_attempts = 0
        user.phone_verification_locked_until = None
        db.session.commit()
        log_user_action(user, "phone_verified")
        return jsonify({"message": "Phone number verified successfully"}), 200

    except Exception:
        return jsonify({"message": "Phone verification failed"}), 500


@bp.route("/api/auth/send-verification", methods=["POST"])
@rate_limit(max_requests=3, window_minutes=10)  # best-effort (in-memory) throttle per IP
def send_phone_verification():
    """Send phone verification code"""
    try:
        data = request.get_json(silent=True) or {}
        data = validate_input_sanitization(data)
        raw_phone = (data.get("phone_number") or data.get("phone") or "").strip()

        phone_digits = _normalize_phone(raw_phone)
        if not phone_digits:
            return jsonify({"message": "Phone number is required"}), 400

        # For legacy flows, require the user to exist.
        user = User.query.filter_by(phone_number=phone_digits).first()
        if not user:
            return jsonify({"message": "User not found"}), 404

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

        from ..sms_service import send_verification_sms

        sms_sent = send_verification_sms(phone_digits, verification_code)
        if not sms_sent:
            # Do not leave a potentially valid code in DB if SMS failed.
            user.phone_verification_code_hash = None
            user.phone_verification_expires_at = None
            user.phone_verification_attempts = 0
            user.phone_verification_locked_until = None
            db.session.commit()
            return jsonify({"message": "Failed to send verification code"}), 500

        return jsonify({"message": "Verification code sent successfully"}), 200

    except Exception:
        return jsonify({"message": "Failed to send verification code"}), 500


# --- Option D auth endpoints (email+password AND phone OTP as separate options) ---

@bp.route("/api/auth/phone/start", methods=["POST"])
@rate_limit(max_requests=3, window_minutes=10)
def phone_start():
    """Start phone OTP login/signup (passwordless). Auto-creates user on first use."""
    try:
        data = request.get_json(silent=True) or {}
        data = validate_input_sanitization(data)
        raw_phone = (data.get("phone_number") or data.get("phone") or "").strip()
        phone_digits = _normalize_phone(raw_phone)
        if not phone_digits:
            return jsonify({"message": "Phone number is required"}), 400

        try:
            user = _get_or_create_user_for_phone(
                phone_digits,
                username=(data.get("username") or None),
                first_name=(data.get("first_name") or data.get("firstName") or None),
                last_name=(data.get("last_name") or data.get("lastName") or None),
                email=(data.get("email") or None),
                password=(data.get("password") or None),
            )
        except ValueError as e:
            # Avoid leaking account existence details.
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

        from ..sms_service import send_verification_sms

        sms_sent = send_verification_sms(phone_digits, verification_code)
        if not sms_sent:
            user.phone_verification_code_hash = None
            user.phone_verification_expires_at = None
            user.phone_verification_attempts = 0
            user.phone_verification_locked_until = None
            db.session.commit()
            return jsonify({"message": "Failed to send verification code"}), 500

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
        phone_digits = _normalize_phone(raw_phone)
        if not phone_digits or not code:
            return jsonify({"message": "Phone number and code are required"}), 400
        if len(code) != 6 or not code.isdigit():
            return jsonify({"message": "Invalid or expired verification code"}), 400

        try:
            user = _get_or_create_user_for_phone(
                phone_digits,
                username=(data.get("username") or None),
                first_name=(data.get("first_name") or data.get("firstName") or None),
                last_name=(data.get("last_name") or data.get("lastName") or None),
                email=(data.get("email") or None),
                password=(data.get("password") or None),
            )
        except ValueError as e:
            current_app.logger.info("phone_verify validation error: %s", str(e))
            return jsonify({"message": "Invalid input"}), 400

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
@rate_limit(max_requests=5, window_minutes=60)  # 5 signups per hour per IP (compat route)
def compat_signup():
    """
    Compatibility signup endpoint for mobile client.
    """
    try:
        data = request.get_json(silent=True) or {}
        data = validate_input_sanitization(data)

        raw_username = (data.get("username") or "").strip()
        raw_phone = (data.get("phone") or data.get("phone_number") or "").strip()
        email = (data.get("email") or "").strip()
        password = (data.get("password") or "").strip()
        first_name = (data.get("first_name") or "User").strip()
        last_name = (data.get("last_name") or "Demo").strip()

        phone_digits = "".join(ch for ch in raw_phone if ch.isdigit())
        if len(phone_digits) > 11:
            phone_digits = phone_digits[-11:]

        username = (
            raw_username
            or (email.split("@")[0] if email and "@" in email else "")
            or phone_digits
            or f"user_{secrets.token_hex(3)}"
        ).lower()
        if not phone_digits:
            phone_digits = f"070{secrets.randbelow(10**8):08d}"
        if not password:
            return jsonify({"message": "Password is required"}), 400
        is_valid, message = validate_password(password)
        if not is_valid:
            return jsonify({"message": message}), 400

        from sqlalchemy import or_

        filters = [User.username == username]
        if email:
            filters.append(User.email == email)
        filters.append(User.phone_number == phone_digits)
        existing = User.query.filter(or_(*filters)).first()
        if existing:
            # SECURITY: never mutate an existing account via "signup".
            # Direct the user to login or the password reset flow instead.
            return jsonify({"message": "Account already exists. Please log in."}), 409

        user = User(
            username=username,
            phone_number=phone_digits,
            first_name=first_name,
            last_name=last_name,
            # IMPORTANT: keep missing email as NULL (not empty string),
            # otherwise the UNIQUE constraint will treat "" as a real value
            # and block additional users without emails.
            email=email or None,
            is_active=True,
            public_id=secrets.token_hex(8),
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
                "email": (email or "")[:200],
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
                "email": (email or "")[:200],
                "phone_digits": (phone_digits or "")[:32],
            },
        )
        return jsonify({"message": "Signup failed. Please try again."}), 500


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

