from __future__ import annotations

import hashlib
import hmac
import secrets
from datetime import datetime, timedelta

from flask import Blueprint, current_app, jsonify, request
from flask_jwt_extended import (
    create_access_token,
    create_refresh_token,
    get_jwt,
    get_jwt_identity,
    jwt_required,
)

from ..auth import (
    create_password_reset_token,
    get_current_user,
    log_user_action,
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
        jti = jwt_payload["jti"]
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

    except Exception:
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
        user.last_login = datetime.utcnow()
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
        return jsonify({"message": "Login failed", "error": str(e)}), 500


@bp.route("/api/auth/refresh", methods=["POST"])
@jwt_required(refresh=True)
def refresh():
    """Refresh access token"""
    try:
        current_user_id = get_jwt_identity()
        user = User.query.filter_by(public_id=current_user_id).first()

        if not user or not user.is_active:
            return jsonify({"message": "User not found or inactive"}), 401

        new_access_token = create_access_token(identity=user.public_id)

        return jsonify({"access_token": new_access_token}), 200

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

        return jsonify({"message": "Logout successful"}), 200

    except Exception:
        return jsonify({"message": "Logout failed"}), 500


@bp.route("/api/auth/forgot-password", methods=["POST"])
def forgot_password():
    """Forgot password endpoint"""
    try:
        data = request.get_json()
        phone_number = data.get("phone_number")

        if not phone_number:
            return jsonify({"message": "Phone number is required"}), 400

        user = User.query.filter_by(phone_number=phone_number).first()
        if not user:
            return jsonify({"message": "If the phone number exists, a reset code has been sent"}), 200

        token = create_password_reset_token(user)

        from ..sms_service import send_password_reset_sms

        send_password_reset_sms(phone_number, token)

        return jsonify({"message": "If the phone number exists, a reset code has been sent"}), 200

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

        now = datetime.utcnow()
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

        user = User.query.filter_by(phone_number=phone_digits).first()
        if not user:
            return jsonify({"message": "User not found"}), 404

        if user.is_verified:
            return jsonify({"message": "Phone number is already verified"}), 200

        now = datetime.utcnow()
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


@bp.route("/api/auth/signup", methods=["POST"])
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
    except Exception:
        db.session.rollback()
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

