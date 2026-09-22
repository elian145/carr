from __future__ import annotations

import hashlib
import hmac
import os
import secrets
import time
from datetime import datetime, timedelta, timezone

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
    verify_email_verification_token,
    verify_password_reset_token,
)
from ..extensions import mail
from ..localization import current_request_locale, translate
from ..models import (
    AdminAccount,
    BlockedUser,
    DealerApplication,
    DealerDecision,
    EmailVerification,
    PasswordReset,
    TokenBlacklist,
    User,
    db,
)
from ..config import dev_debug_response_fields_enabled
from ..security import (
    atomic_increment_attempts,
    check_account_login_throttle,
    check_rate_limit,
    rate_limit,
    record_account_login_failure,
    reset_account_login_failures,
    validate_input_sanitization,
)

bp = Blueprint("auth", __name__)


_EMAIL_SIGNUP_GONE = {
    "message": "Email signup is no longer supported. Use phone OTP instead.",
    "code": "email_signup_removed",
}

_DIRECT_SIGNUP_GONE = {
    "message": "Direct registration is no longer supported. Verify your phone with a code instead.",
    "code": "direct_signup_removed",
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


# --- Google Play reviewer OTP bypass ----------------------------------------
#
# Google Play review requires a login that (a) never expires and (b) never
# depends on receiving a real SMS. Real phone-OTP login cannot satisfy
# either, so a single, narrowly-scoped account gets a fixed, operator-chosen
# phone number + code instead, gated behind THREE separate environment
# variables (never hardcoded, never committed):
#
#   GOOGLE_REVIEW_LOGIN_ENABLED  - master on/off switch (default: off)
#   GOOGLE_REVIEW_PHONE          - the exact phone number this applies to
#   GOOGLE_REVIEW_OTP            - the fixed code accepted for that phone
#
# GOOGLE_REVIEW_PHONE format gotcha: the mobile login screen always sends
# "+964" + exactly the 10 digits typed into its phone field, and
# `_normalize_phone()` below strips that "964" back off before any
# comparison happens. So GOOGLE_REVIEW_PHONE must be set to EXACTLY those
# 10 digits (no leading 0, no "+964") -- the same 10 digits the reviewer
# types into the app. Setting it to the 11-digit "0XXXXXXXXXX" local
# format instead (what you'd read off a SIM) normalizes to a different
# string and the bypass below will never match.
#
# Design invariants enforced below (see phone_start()/phone_verify()):
#   * The bypass only ever matches when the incoming phone number, after the
#     SAME normalization every other phone number goes through, equals
#     GOOGLE_REVIEW_PHONE exactly -- it can never apply to any other user's
#     phone number, and a wrong code against THIS phone still fails.
#   * GOOGLE_REVIEW_OTP is compared with `hmac.compare_digest` (constant
#     time), the same primitive used for real OTP hashes elsewhere in this
#     file.
#   * Disabling GOOGLE_REVIEW_LOGIN_ENABLED (or leaving either variable
#     unset) fully disables this code path -- both helpers below fail
#     closed to False/"" when misconfigured.
#   * Neither the request endpoint nor the verify endpoint ever reveals
#     that a given phone number is the reviewer account: /phone/start
#     returns the exact same success response as a real send, and a wrong
#     code on /phone/verify returns the exact same generic invalid-code
#     response as any other account.
#   * This path never reads or writes `phone_verification_code_hash` /
#     `_expires_at` / `_attempts` / `_locked_until` for the reviewer's
#     phone number, so it can never be blocked by (or interact with) the
#     real per-user OTP lockout -- the reviewer cannot become permanently
#     locked out.
def _google_review_login_enabled() -> bool:
    return _to_bool(os.environ.get("GOOGLE_REVIEW_LOGIN_ENABLED"))


def _google_review_phone_digits() -> str:
    raw = (os.environ.get("GOOGLE_REVIEW_PHONE") or "").strip()
    if not raw:
        return ""
    return _normalize_phone(raw)


def _google_review_otp_code() -> str:
    return (os.environ.get("GOOGLE_REVIEW_OTP") or "").strip()


def _is_google_review_phone(phone_digits: str) -> bool:
    """True only when review login is enabled, GOOGLE_REVIEW_PHONE is
    configured, and `phone_digits` (already normalized by the caller)
    matches it exactly."""
    if not phone_digits or not _google_review_login_enabled():
        return False
    review_phone = _google_review_phone_digits()
    return bool(review_phone) and phone_digits == review_phone


def _google_review_otp_matches(code: str) -> bool:
    review_otp = _google_review_otp_code()
    if not review_otp or not code:
        return False
    return hmac.compare_digest(code, review_otp)


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


# --- OTP policy -------------------------------------------------------------
# These mirror the values already used by phone/start and phone/verify, so the
# signup path enforces the same policy as the rest of the OTP surface.
_OTP_MAX_ATTEMPTS = 5
_OTP_LOCKOUT_MINUTES = 15
_OTP_RESEND_COOLDOWN_SECONDS = 60


class OtpError(Exception):
    """An OTP could not be consumed. Carries a client-safe response payload."""

    def __init__(self, message: str, code: str, status: int):
        super().__init__(message)
        self.message = message
        self.code = code
        self.status = status

    def response(self):
        return jsonify({"message": self.message, "code": self.code}), self.status


def _invalid_credentials_response(user: "User | None" = None):
    """Localized generic 401 for a failed login (MI-03).

    Only the human-readable message text varies by locale (Accept-Language
    header, then the resolved account's own ``User.locale`` when one was
    resolved) -- the machine-readable shape (401 status, single generic
    ``message`` key, no ``code``) is unchanged. This keeps the M-09
    "identical response whether the account is wrong, throttled, or the
    password was wrong" guarantee intact for every locale.
    """
    locale = current_request_locale(getattr(user, "locale", None) if user else None)
    return jsonify({"message": translate("invalid_credentials", locale)}), 401


def _consume_phone_otp(user: User, phone_digits: str, code: str) -> None:
    """
    Verify a phone OTP for ``user`` and clear it on success.

    Enforced server-side, regardless of what the client sends:
      * lockout for `_OTP_LOCKOUT_MINUTES` after `_OTP_MAX_ATTEMPTS` wrong codes,
      * expiry via `phone_verification_expires_at`,
      * constant-time comparison against the HMAC-stored code.

    Failed attempts are committed before raising so the counter survives the
    caller's error handling. Raises `OtpError`, whose message never reveals
    whether the code was wrong, expired, or never issued.
    """
    from ..time_utils import utcnow

    now = utcnow()

    locked_until = getattr(user, "phone_verification_locked_until", None)
    if locked_until and locked_until > now:
        raise OtpError("Too many attempts. Please try again later.", "otp_locked", 429)

    code_hash = getattr(user, "phone_verification_code_hash", None)
    expires_at = getattr(user, "phone_verification_expires_at", None)
    if not code_hash or not expires_at or expires_at <= now:
        # Expired or never issued: drop stale material so the client must re-request.
        user.phone_verification_code_hash = None
        user.phone_verification_expires_at = None
        db.session.commit()
        raise OtpError("Invalid or expired verification code.", "otp_invalid", 400)

    if len(code) != 6 or not code.isdigit():
        raise OtpError("Invalid or expired verification code.", "otp_invalid", 400)

    expected = _hash_phone_verification_code(phone_digits, code)
    if not hmac.compare_digest(code_hash, expected):
        attempts = atomic_increment_attempts(user, "phone_verification_attempts")
        if attempts >= _OTP_MAX_ATTEMPTS:
            user.phone_verification_locked_until = now + timedelta(
                minutes=_OTP_LOCKOUT_MINUTES
            )
            user.phone_verification_code_hash = None
            user.phone_verification_expires_at = None
            user.phone_verification_attempts = 0
            db.session.commit()
            raise OtpError(
                "Too many attempts. Please try again later.", "otp_locked", 429
            )
        db.session.commit()
        raise OtpError("Invalid or expired verification code.", "otp_invalid", 400)

    user.phone_verification_code_hash = None
    user.phone_verification_expires_at = None
    user.phone_verification_attempts = 0
    user.phone_verification_locked_until = None


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


def _deactivated_account_otp_response(phone_digits: str, code: str):
    """CarNet V1 fix 4: if `phone_digits` belongs to an existing but
    deactivated/banned account whose stored OTP genuinely matches `code`,
    return the deactivated-account error to use in `phone_verify()` instead
    of letting it fall through to the generic "Invalid or expired
    verification code" (or "No account found") response.

    `phone_start()` happily issues a real OTP for a deactivated account's
    phone number (via `_get_or_create_user_for_phone()`, which does not
    filter on `is_active`) so that requesting a code looks identical
    whether or not the account is active -- no enumeration signal there.
    But `phone_verify()`'s user lookup *is* `is_active`-filtered, so a
    deactivated user who then submits that perfectly valid code was
    previously told it was simply wrong/expired, which is misleading and
    indistinguishable from a typo.

    This is only ever reachable by someone who already possesses a live,
    correct code for this exact phone number -- i.e. someone with control
    of the phone the SMS was sent to -- so it cannot be used to probe
    arbitrary phone numbers for account existence: a wrong code, an
    expired code, or a phone number with no account at all all still fall
    through (return None) to the caller's existing generic branches,
    completely unchanged.
    """
    user = User.query.filter_by(phone_number=phone_digits, is_active=False).first()
    if not user:
        return None

    from ..time_utils import utcnow

    now = utcnow()
    locked_until = getattr(user, "phone_verification_locked_until", None)
    if locked_until and locked_until > now:
        # Same lockout enforcement as the active-account path -- this branch
        # must not become an easier brute-force target than normal login.
        return jsonify({"message": "Too many attempts. Please try again later."}), 429

    expires_at = getattr(user, "phone_verification_expires_at", None)
    code_hash = getattr(user, "phone_verification_code_hash", None)
    if not expires_at or not code_hash or expires_at <= now:
        return None

    expected = _hash_phone_verification_code(phone_digits, code)
    if not hmac.compare_digest(code_hash, expected):
        attempts = atomic_increment_attempts(user, "phone_verification_attempts")
        if attempts >= 5:
            user.phone_verification_locked_until = now + timedelta(minutes=15)
            user.phone_verification_code_hash = None
            user.phone_verification_expires_at = None
            user.phone_verification_attempts = 0
        db.session.commit()
        return None

    # Correct code for a deactivated account -- consume it (no replay) and
    # report the real reason login cannot proceed.
    user.phone_verification_code_hash = None
    user.phone_verification_expires_at = None
    user.phone_verification_attempts = 0
    user.phone_verification_locked_until = None
    db.session.commit()
    return jsonify(
        {
            "message": "This account has been deactivated. Contact support for assistance.",
            "code": "account_deactivated",
        }
    ), 403


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
        """Check if a token is blacklisted, or belongs to a now-inactive
        (banned/deactivated) user, or was issued before the user's most
        recent password change/reset (H-01/H-02).

        This is the single chokepoint every @jwt_required() route passes
        through, including the handful of routes that don't separately
        call get_current_user() -- so the is_active/cutoff checks below
        close those routes automatically, with no per-route changes.
        """
        jti = str(jwt_payload.get("jti") or "")

        if jti:
            # Prefer Redis in production (O(1) lookup, no DB query per request).
            r = _redis_client()
            if r is not None:
                try:
                    if r.exists(f"bl:jti:{jti}"):
                        return True
                except Exception:
                    # If Redis is down/misconfigured, fall back to DB.
                    r = None
            if r is None:
                token = TokenBlacklist.query.filter_by(jti=jti).first()
                if token is not None:
                    return True

        # H-01/H-02: even when this specific JTI was never individually
        # blacklisted, reject it if the user is now inactive, or if it was
        # issued (JWT `iat`) strictly before the user's tokens_invalid_before
        # cutoff. Resolve the same way get_current_user() does.
        user = _resolve_user_by_jwt_identity(jwt_payload.get("sub"))
        if user is None:
            # Unknown identity: not this loader's job -- get_current_user()/
            # the route itself already treats a missing user as
            # unauthenticated. Preserve existing behavior here.
            return False

        if not user.is_active:
            return True

        cutoff = user.tokens_invalid_before
        if cutoff is not None:
            iat = jwt_payload.get("iat")
            if iat is not None:
                issued_at = datetime.fromtimestamp(int(iat), tz=timezone.utc).replace(
                    tzinfo=None
                )
                if issued_at < cutoff:
                    return True

        return False

    @jwt.revoked_token_loader
    def revoked_token_callback(jwt_header, jwt_payload):
        return jsonify({"message": "Token has been revoked"}), 401


@bp.route("/api/auth/register", methods=["POST"])
@rate_limit(max_requests=5, window_minutes=60)  # 5 registrations per hour per IP
def register():
    """Retired: created accounts without proving phone ownership. Use /api/auth/signup."""
    return jsonify(_DIRECT_SIGNUP_GONE), 410


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


def _resolve_user_by_jwt_identity(identity) -> User | None:
    """Resolve a User from a JWT identity (public_id, user:{id}, or numeric id)."""
    if not identity:
        return None
    ident = str(identity).strip()
    user = User.query.filter_by(public_id=ident).first()
    if not user and ident.startswith("user:"):
        try:
            user = User.query.filter_by(id=int(ident.split(":", 1)[1])).first()
        except Exception:
            user = None
    if not user and ident.isdigit():
        try:
            user = User.query.filter_by(id=int(ident)).first()
        except Exception:
            user = None
    return user


def _ensure_user_public_id(user: User) -> str:
    """Guarantee a stable public_id for JWT identity (never issue user:{id} for new tokens)."""
    if getattr(user, "public_id", None):
        return str(user.public_id)
    user.public_id = secrets.token_hex(8)
    try:
        db.session.commit()
    except Exception:
        db.session.rollback()
        if not getattr(user, "public_id", None):
            user.public_id = secrets.token_hex(8)
            db.session.commit()
    return str(user.public_id)


def _access_token_for_user(user: User) -> str:
    identity = _ensure_user_public_id(user)
    claims = {}
    if getattr(user, "is_admin", False):
        claims["is_admin"] = True
        claims["account_scope"] = "admin"
    if claims:
        return create_access_token(identity=identity, additional_claims=claims)
    return create_access_token(identity=identity)


def _refresh_token_for_user(user: User) -> str:
    identity = _ensure_user_public_id(user)
    claims = {}
    if getattr(user, "is_admin", False):
        claims["is_admin"] = True
        claims["account_scope"] = "admin"
    if claims:
        return create_refresh_token(identity=identity, additional_claims=claims)
    return create_refresh_token(identity=identity)


def _account_login_lock_identifier(*, admin_account=None, user=None):
    """
    M-09: canonical, scope-prefixed identifier for the account-level
    login-failure throttle -- derived from the ALREADY-RESOLVED account row,
    never from the raw, client-submitted ``username`` field. This means
    whichever equivalent identifier (phone vs. username for ``User``; email
    vs. phone vs. username for ``AdminAccount``) the client used to reach
    the SAME row, the SAME throttle bucket is used -- an attacker who knows
    both a target's phone number and username cannot double their effective
    attempt budget by alternating between them.

    The ``admin:``/``user:`` prefix keeps the two account spaces from ever
    colliding on an identical raw string (e.g. a mobile ``User.username``
    that happens to equal an unrelated ``AdminAccount.username``).

    Returns ``None`` when no account was resolved: unknown identifiers are
    never throttled at the account level -- there is no real account to
    protect, and doing so would create a new signal distinguishing "unknown"
    from "known but not yet throttled" (an enumeration risk this fix must
    not introduce). Unknown identifiers remain governed solely by the
    existing per-IP ``@rate_limit`` decorator, unchanged.
    """
    if admin_account is not None:
        canonical = (
            admin_account.email
            or admin_account.phone_number
            or admin_account.username
            or f"id:{admin_account.id}"
        )
        return f"admin:{canonical}"
    if user is not None:
        canonical = user.phone_number or user.username or f"id:{user.id}"
        return f"user:{canonical}"
    return None


@bp.route("/api/auth/login", methods=["POST"])
@rate_limit(max_requests=10, window_minutes=15)  # 10 login attempts per 15 minutes per IP
def login():
    """User login endpoint"""
    try:
        data = request.get_json(silent=True) or {}

        if not data.get("username") or not data.get("password"):
            return jsonify({"message": "Phone/username and password are required"}), 400

        # Dashboard credentials are intentionally separate from mobile accounts.
        # Deleting a mobile User must not remove the principal used by admin APIs.
        from sqlalchemy import or_

        ident = data["username"]
        account_scope = str(data.get("account_scope") or "").strip().lower()
        admin_account = None
        user = None

        if account_scope == "admin":
            admin_account = AdminAccount.query.filter(
                or_(
                    AdminAccount.email == ident,
                    AdminAccount.phone_number == ident,
                    AdminAccount.username == ident,
                )
            ).first()
        else:
            # Mobile password login is phone/username only (no email).
            user = User.query.filter(
                or_(User.phone_number == ident, User.username == ident)
            ).first()
            if user and AdminAccount.query.filter_by(principal_user_id=user.id).first():
                return _invalid_credentials_response(user)

        # M-09: account-keyed failed-login throttle -- independent of, and in
        # addition to, the existing per-IP @rate_limit above. Checked BEFORE
        # any password verification so a temporarily-throttled account never
        # runs bcrypt at all (see kk/security.py::check_account_login_throttle
        # for the full design note, thresholds, and fail-closed policy).
        account_login_key = _account_login_lock_identifier(
            admin_account=admin_account,
            user=user if account_scope != "admin" else None,
        )
        if account_login_key is not None:
            locked, throttle_error = check_account_login_throttle(account_login_key)
            if throttle_error is not None:
                # H-06 policy: Redis required but unavailable in production
                # -> fail closed, exactly like the per-IP limiter above.
                return throttle_error
            if locked:
                # Same generic response as a wrong password: an
                # unauthenticated caller must not be able to distinguish
                # "wrong password" from "this account is temporarily
                # throttled" (no code/message/remaining-attempts leak).
                return _invalid_credentials_response(user)

        if account_scope == "admin":
            password_ok = bool(admin_account) and admin_account.check_password(
                data["password"]
            )
        else:
            password_ok = bool(user) and user.check_password(data["password"])

        if not password_ok:
            # Only a genuinely-failed password check against a resolved
            # account increments the throttle (never malformed requests,
            # never unknown identifiers, never successful logins).
            if account_login_key is not None:
                record_account_login_failure(account_login_key)
            return _invalid_credentials_response(user)

        # Correct password: clear any accumulated failures/throttle for this
        # account so a legitimate user's earlier typos never linger.
        if account_login_key is not None:
            reset_account_login_failures(account_login_key)

        if account_scope == "admin":
            user = admin_account.principal
            if (
                not admin_account.is_active
                or not user
                or not user.is_active
                or not user.is_admin
            ):
                return jsonify({"message": "Admin account is deactivated"}), 401

        if not user.is_active:
            return jsonify({"message": "Account is deactivated"}), 401

        # Update last login
        from ..time_utils import utcnow

        _ensure_user_public_id(user)
        user.last_login = utcnow()
        if admin_account is not None:
            admin_account.last_login = user.last_login
        db.session.commit()

        access_token = _access_token_for_user(user)
        refresh_token = _refresh_token_for_user(user)

        log_user_action(user, "login")

        return (
            jsonify(
                {
                    "message": "Login successful",
                    "token": access_token,  # mobile compatibility
                    "access_token": access_token,
                    "refresh_token": refresh_token,
                    "user": user.to_dict(include_private=True),
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
        user = _resolve_user_by_jwt_identity(get_jwt_identity())

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

        new_access_token = _access_token_for_user(user)
        new_refresh_token = _refresh_token_for_user(user)

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

    except Exception as e:
        db.session.rollback()
        current_app.logger.exception("logout failed: %s", e)
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
        # Floor to whole seconds: JWT `iat` is an integer unix timestamp, so
        # a token minted in this same wall-clock second (even a moment
        # *after* this change, e.g. a fresh post-change login racing this
        # request) would otherwise compare as "before" a microsecond-precise
        # cutoff and be spuriously revoked. Flooring means any token from an
        # earlier second is still correctly revoked, and the only accepted
        # trade-off is a <1s grace window right at the boundary -- see
        # test_token_revocation.py tests E/L.
        now = utcnow().replace(microsecond=0)
        current_user.set_password(new_pass)
        current_user.updated_at = now
        # H-01: revoke every access/refresh token issued before this moment
        # (same commit as the password update -- no separate transaction).
        current_user.tokens_invalid_before = now
        db.session.commit()
        log_user_action(current_user, "password_change")
        return jsonify({"message": "Password changed successfully"}), 200
    except Exception as e:
        db.session.rollback()
        current_app.logger.exception("change_password failed: %s", e)
        return jsonify({"message": "Failed to change password"}), 500


def _delete_and_scrub_user_listings(user_id: int, table_names: set[str]) -> list[str]:
    """Deactivate every listing owned by ``user_id`` and permanently remove
    its personal data, as part of the *same* transaction that goes on to
    delete the ``User`` row itself.

    D-01 revisit (see migration ``h1i2j3k4l5m6_d01r_car_seller_set_null.py``):
    ``car.seller_id`` is ``ON DELETE SET NULL``, not ``RESTRICT`` -- the DB
    nulls it automatically the instant the user row is deleted, so this
    function does NOT need to (and must not) touch ``seller_id`` itself,
    delete the ``Car`` row, or delete rows that already survive de-identified
    via their own SET NULL FK (``Message``, ``ListingReport``). Deleting the
    listing row outright would orphan the *surviving* counterpart's chat
    history for it (``GET /api/chat/<car_id>/messages`` looks the car up by
    id) -- exactly what D-01 exists to prevent.

    What this *does* remove, because it is personal/identifying data of the
    account being deleted:
    - Photos/videos: both the ``CarImage``/``CarVideo`` DB rows (cascade-safe
      either way) and, best-effort, the underlying object-storage file --
      returned here so the caller can clean those up *after* the whole
      deletion commits (mirrors ``kk/routes/media.py``'s commit-then-clean
      -storage ordering).
    - Free-text ``description`` and ``vin`` (may contain a name/phone/etc).
    - ``contact_phone`` / ``contact_phones`` (the seller's own numbers).
    - Exact ``latitude``/``longitude`` (already treated as owner/admin-only
      in ``Car.to_dict()`` -- H-05).

    Deliberately left alone: ``location`` (free-text city/area, not exact,
    and is NOT NULL at the DB level), and the car's own spec fields
    (brand/model/year/price/...) plus aggregate analytics -- none of that is
    personal data about the seller, and the listing is deactivated
    (``is_active=False``, ``status='hidden'``) so none of it is shown to
    anyone once scrubbed.
    """
    if "car" not in table_names:
        return []
    from ..models import Car
    from ..time_utils import utcnow

    media_urls: list[str] = []
    cars = Car.query.filter_by(seller_id=user_id).all()
    for car in cars:
        for img in list(car.images or []):
            if img.image_url:
                media_urls.append(img.image_url)
            db.session.delete(img)
        for vid in list(car.videos or []):
            if vid.video_url:
                media_urls.append(vid.video_url)
            db.session.delete(vid)
        car.is_active = False
        car.status = "hidden"
        car.description = None
        car.vin = None
        car.contact_phone = None
        car.contact_phones = None
        car.latitude = None
        car.longitude = None
        car.updated_at = utcnow()
    return media_urls


def _scrub_dealer_application_snapshot(snapshot):
    """Return a copy of a `DealerApplication.snapshot()` JSON blob with every
    personal/contact/document field redacted.

    Used both on the live `DealerApplication.snapshot()`-shaped dict (n/a --
    the live row's own columns are scrubbed directly, see below) and on every
    historical `DealerDecision.application_snapshot` for that application:
    each decision stores a *copy* of the applicant's contact/business data
    at the time of that review event (see `DealerApplication.snapshot()` /
    `_save_dealer_application()` / `_review_dealer_application()`), so
    leaving those JSON blobs untouched would let the exact same PII we just
    scrubbed off the live row keep surviving inside the audit history.

    Kept as-is: `dealership_name` (business name, not personal to an
    individual -- matches what stays on the live row) and
    `has_verification_photo` (already just a boolean, never the photo
    itself).
    """
    if not isinstance(snapshot, dict):
        return snapshot
    scrubbed = dict(snapshot)
    if "dealership_phone" in scrubbed:
        scrubbed["dealership_phone"] = ""
    if "dealership_phones" in scrubbed:
        scrubbed["dealership_phones"] = []
    if "dealership_location" in scrubbed:
        scrubbed["dealership_location"] = ""
    if "dealership_description" in scrubbed:
        scrubbed["dealership_description"] = None
    if "business_registration_number" in scrubbed:
        scrubbed["business_registration_number"] = None
    if "document_urls" in scrubbed:
        scrubbed["document_urls"] = []
    return scrubbed


def _scrub_dealer_records_for_deletion(
    user_id: int, table_names: set[str]
) -> tuple[list[str], list[str]]:
    """De-identify/remove dealer application + dealer profile personal data,
    as part of the *same* transaction that goes on to delete the ``User``
    row (called from delete_account() alongside
    ``_delete_and_scrub_user_listings``).

    Data Safety audit follow-up (dealer accounts): unlike a ``Car`` listing
    (D-01), neither ``DealerApplication`` nor ``DealerProfile`` is ever
    reachable through any *public* route once the owning ``User`` row is
    gone. ``GET /api/dealers`` and ``GET /api/dealers/<id>`` both require a
    live, ``is_active`` ``User`` row with ``account_type == "dealer"`` /
    ``dealer_status == "approved"`` (see kk/routes/user.py::list_dealers() /
    dealer_profile()) -- there is no route that looks a dealer up by
    ``DealerProfile.public_id`` / ``DealerApplication.public_id`` directly.
    So unlike a listing (which stays browsable/chat-linked after the seller
    is gone), these rows have no surviving *public* purpose once the account
    is deleted -- personal/contact data left on them would just be orphaned
    PII sitting in the database, unreachable but not actually erased.

    What survives, for trust & safety / fraud audit purposes (mirrors the
    D-01 treatment of listing reports/messages):
    - The ``DealerApplication`` row itself: ``status``, ``dealership_name``
      (business name, not personal to an individual),
      ``submitted_at``/``reviewed_at``, ``review_reason`` (the *admin
      reviewer's* own words, not the applicant's data), and its full
      ``DealerDecision`` history (decision/reviewer/reason/created_at) -- so
      "this account applied as a dealer and was approved/rejected on this
      date, for this reason" remains auditable after the account is gone.

    What is removed/de-identified, because it is personal/contact data of
    the account being deleted, with no documented fraud/security/legal need
    for it to survive the account (grep of the codebase shows no feature
    ever reads these fields back to cross-check a *new* application against
    a previous one -- if such a fraud workflow is built later, it should
    define its own narrow, documented retention for exactly what it needs):
    - ``DealerApplication.dealership_phone``/``dealership_phones`` and
      ``dealership_location`` (contact details) are reset to ``""``/``[]``
      -- both columns are ``NOT NULL`` at the DB level, so an empty string
      is the redaction marker (never real data past this point).
    - ``dealership_description`` and ``business_registration_number`` are
      cleared to ``None`` (both nullable).
    - ``document_urls``: any R2/local-hosted object is best-effort deleted
      from storage (foreign/third-party URLs are safely skipped -- see
      ``_storage_key_from_url()``), then the column is cleared to ``[]``.
    - ``verification_photo_filename``: the private local file under
      ``PRIVATE_UPLOAD_FOLDER/dealer_verification/`` is best-effort deleted,
      then the column is cleared to ``None``.
    - Every historical ``DealerDecision.application_snapshot`` for that
      application is scrubbed the same way in place (see
      ``_scrub_dealer_application_snapshot()``) -- otherwise the exact same
      contact/document data would silently keep surviving inside the JSON
      audit blob even after the live application row is cleaned.
    - The ``DealerProfile`` row is deleted outright (not merely
      de-identified): it is the live, publicly-displayed mirror of an
      approved dealer's contact info, and per the above is never
      independently browsable once the account is gone, so keeping an
      emptied-out shell around serves no purpose. Its
      ``dealership_cover_picture`` storage object is queued for best-effort
      deletion by the caller.

    Returns ``(pending_media_urls, verification_photo_filenames)``:
    - ``pending_media_urls``: R2/local object URLs (dealer cover picture +
      any R2/local-hosted ``document_urls``) for the caller to merge into
      its own post-commit ``_delete_media_storage_object()`` cleanup list.
    - ``verification_photo_filenames``: bare filenames under
      ``PRIVATE_UPLOAD_FOLDER/dealer_verification/`` for the caller to
      best-effort delete after commit via
      ``_delete_dealer_verification_file()`` (not a URL -- a different,
      private-only storage layout, see
      ``kk/routes/user.py::upload_dealer_verification_photo()``).
    """
    media_urls: list[str] = []
    verification_files: list[str] = []

    if "dealer_application" in table_names:
        from ..time_utils import utcnow

        application = DealerApplication.query.filter_by(user_id=user_id).first()
        if application is not None:
            for doc_url in application.document_urls or []:
                if doc_url:
                    media_urls.append(doc_url)
            if application.verification_photo_filename:
                verification_files.append(application.verification_photo_filename)

            if "dealer_decision" in table_names:
                decisions = DealerDecision.query.filter_by(
                    application_id=application.id
                ).all()
                for decision in decisions:
                    decision.application_snapshot = _scrub_dealer_application_snapshot(
                        decision.application_snapshot
                    )

            application.dealership_phone = ""
            application.dealership_phones = []
            application.dealership_location = ""
            application.dealership_description = None
            application.business_registration_number = None
            application.document_urls = []
            application.verification_photo_filename = None
            application.updated_at = utcnow()

    if "dealer_profile" in table_names:
        from ..models import DealerProfile

        profile = DealerProfile.query.filter_by(user_id=user_id).first()
        if profile is not None:
            if profile.dealership_cover_picture:
                media_urls.append(profile.dealership_cover_picture)
            db.session.delete(profile)

    return media_urls, verification_files


def _delete_dealer_verification_file(filename: str) -> None:
    """Best-effort delete of a private dealer-verification photo from local
    disk (mirrors ``kk/routes/media.py::_delete_media_storage_object()``'s
    fail-safe posture -- an already-missing file or a filesystem hiccup must
    never raise, since this always runs *after* the DB delete already
    committed).

    Not folded into ``_delete_media_storage_object()`` because verification
    photos are stored by bare filename under
    ``PRIVATE_UPLOAD_FOLDER/dealer_verification/`` (private disk, never R2,
    never a public ``uploads/...`` URL -- see
    ``kk/routes/user.py::upload_dealer_verification_photo()``), a different
    layout than every other media type that helper already understands.
    """
    name = (filename or "").strip()
    if not name:
        return
    try:
        folder = os.path.join(
            current_app.config["PRIVATE_UPLOAD_FOLDER"], "dealer_verification"
        )
        path = os.path.join(folder, os.path.basename(name))
        if os.path.isfile(path):
            os.remove(path)
    except OSError as e:
        current_app.logger.warning(
            "delete_account: failed to delete dealer verification photo "
            "(best-effort): %s",
            e,
        )


def _hash_delete_account_code(phone_digits: str, code: str) -> str:
    """Namespaced so a signup OTP can never be replayed as a deletion code."""
    return _hash_phone_verification_code(f"delete-account:{phone_digits}", code)


@bp.route("/api/auth/delete-account/send-code", methods=["POST"])
@jwt_required()
@rate_limit(max_requests=5, window_minutes=60, per_ip=False)
def delete_account_send_code():
    """SMS a confirmation code for account deletion.

    Phone-OTP accounts have a server-generated password they can never type, so
    proving control of the account phone is the only workable confirmation.
    """
    try:
        current_user = get_current_user()
        if not current_user:
            return jsonify({"message": "Unauthorized"}), 401
        if AdminAccount.query.filter_by(principal_user_id=current_user.id).first():
            return jsonify({"message": "Dashboard admin accounts cannot be deleted"}), 403

        phone_digits = _normalize_phone(getattr(current_user, "phone_number", "") or "")
        if not phone_digits:
            return jsonify({"message": "No phone number on this account"}), 400

        from ..time_utils import utcnow

        now = utcnow()
        locked_until = getattr(current_user, "phone_verification_locked_until", None)
        if locked_until and locked_until > now:
            return jsonify({"message": "Too many attempts. Please try again later."}), 429

        last_sent = getattr(current_user, "phone_verification_last_sent_at", None)
        if last_sent and (now - last_sent).total_seconds() < 60:
            return jsonify({"message": "Please wait before requesting another code"}), 429

        code = f"{secrets.randbelow(1_000_000):06d}"
        current_user.phone_verification_code_hash = _hash_delete_account_code(
            phone_digits, code
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
            current_user.phone_verification_last_sent_at = None
            db.session.commit()
            current_app.logger.error(
                "delete-account SMS failed provider=%s detail=%s",
                (os.environ.get("SMS_PROVIDER") or "console").strip().lower(),
                sms_detail or "unknown",
            )
            payload = {"sent": False, "message": "Failed to send confirmation code"}
            if dev_debug_response_fields_enabled():
                payload["dev_code"] = code
            return jsonify(payload), 502

        payload = {"sent": True, "message": "Confirmation code sent"}
        if dev_debug_response_fields_enabled():
            payload["dev_code"] = code
        return jsonify(payload), 200
    except Exception as e:
        db.session.rollback()
        current_app.logger.exception("delete_account_send_code failed: %s", e)
        return jsonify({"message": "Failed to send confirmation code"}), 500


def _verify_delete_account_code(user: User, code: str) -> str | None:
    """Validate a deletion code with attempt lockout. Returns an error message or None."""
    if len(code) != 6 or not code.isdigit():
        return "Invalid or expired confirmation code"

    from ..time_utils import utcnow

    now = utcnow()
    locked_until = getattr(user, "phone_verification_locked_until", None)
    if locked_until and locked_until > now:
        return "Too many attempts. Please try again later."

    expires_at = getattr(user, "phone_verification_expires_at", None)
    code_hash = getattr(user, "phone_verification_code_hash", None)
    if not expires_at or not code_hash or expires_at <= now:
        return "Invalid or expired confirmation code"

    phone_digits = _normalize_phone(getattr(user, "phone_number", "") or "")
    expected = _hash_delete_account_code(phone_digits, code)
    if not hmac.compare_digest(code_hash, expected):
        attempts = atomic_increment_attempts(user, "phone_verification_attempts")
        if attempts >= 5:
            user.phone_verification_locked_until = now + timedelta(minutes=15)
            user.phone_verification_code_hash = None
            user.phone_verification_expires_at = None
            user.phone_verification_attempts = 0
        db.session.commit()
        return "Invalid or expired confirmation code"

    # Single-use: burn the code before the delete runs.
    user.phone_verification_code_hash = None
    user.phone_verification_expires_at = None
    user.phone_verification_attempts = 0
    db.session.commit()
    return None


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
        code = (data.get("code") or data.get("verification_code") or "").strip()

        # Require a second factor so a stolen JWT alone cannot wipe an account.
        # Phone-OTP accounts never chose a password, so an SMS code is accepted too.
        if not password and not code:
            return jsonify(
                {"message": "A confirmation code is required to delete your account"}
            ), 400
        if code:
            code_error = _verify_delete_account_code(current_user, code)
            if code_error:
                status = 429 if code_error.startswith("Too many") else 400
                return jsonify({"message": code_error}), status
        elif not current_user.check_password(password):
            return jsonify({"message": "Incorrect password"}), 400

        user_id = current_user.id
        username_for_log = current_user.username
        # Captured now (before the User row is deleted/expired below) so the
        # storage object can be cleaned up best-effort after commit, same as
        # each listing's photos/videos in `_delete_and_scrub_user_listings`.
        # NOT `dealership_cover_picture`: `User.dealership_cover_picture`
        # itself is not queued here because it is the *same* underlying
        # object as `DealerProfile.dealership_cover_picture` (copied
        # verbatim on approval -- see
        # kk/routes/admin.py::_review_dealer_application()`), which
        # `_scrub_dealer_records_for_deletion()` already queues for
        # best-effort deletion exactly once when it deletes the
        # `DealerProfile` row below -- queuing it a second time here would
        # just be a redundant (harmless, but pointless) storage delete call.
        profile_picture_url = current_user.profile_picture
        bind = db.session.get_bind()
        table_names = set()
        try:
            if bind is not None:
                table_names = set(inspect(bind).get_table_names())
        except Exception:
            table_names = set()

        # Everything from here to the single db.session.commit() below is
        # one transaction: if anything raises, the outer `except` rolls
        # ALL of it back, so a failure never leaves a half-deleted account
        # (some rows gone, User row still present) -- see the module-level
        # note on _delete_and_scrub_user_listings() for why listings
        # themselves are deactivated/scrubbed in place rather than deleted.
        #
        # Remove many-to-many associations so FK constraints don't block user delete.
        current_user.favorites = []
        current_user.viewed_listings = []

        # D-01: do NOT bulk-delete Message / UserReport / ListingReport here.
        # Conversation history and trust & safety reports survive account
        # deletion, de-identified via ON DELETE SET NULL on their
        # user/listing FKs. Dealer records are handled explicitly below by
        # _scrub_dealer_records_for_deletion() -- their audit trail
        # (DealerApplication/DealerDecision) survives with every
        # personal/contact/document field scrubbed, and DealerProfile (the
        # live public-page mirror) is deleted outright; see that function's
        # docstring for why it is not a simple SET-NULL-and-done case like
        # the FKs below. Group-A child rows (blocks, tokens, saved
        # searches) are still cleaned explicitly too.

        if "blocked_user" in table_names:
            BlockedUser.query.filter(
                (BlockedUser.blocker_id == user_id) | (BlockedUser.blocked_id == user_id),
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

        # Deactivate + strip personal data from every listing this user
        # owns (photos/videos, description, VIN, contact numbers, exact
        # coordinates). Does NOT delete the Car row or touch seller_id --
        # the DB nulls that itself (ON DELETE SET NULL) the instant the
        # User row below is deleted, which is also what makes the final
        # hard delete possible at all (no more RESTRICT to violate).
        pending_media_urls = _delete_and_scrub_user_listings(user_id, table_names)
        if profile_picture_url:
            pending_media_urls.append(profile_picture_url)

        # Data Safety audit follow-up: scrub the dealer application's
        # personal/contact/document fields (+ their historical
        # DealerDecision.application_snapshot copies) and delete the
        # DealerProfile row outright -- see that function's docstring for
        # the full rationale (mirrors the listing scrub above: DB rows that
        # legitimately need to survive keep only their non-personal audit
        # value, everything personal is removed in the same transaction).
        dealer_media_urls, dealer_verification_files = _scrub_dealer_records_for_deletion(
            user_id, table_names
        )
        pending_media_urls.extend(dealer_media_urls)

        # Chat-list grouping fix: stamp every message this user sent or
        # received with their own (about-to-be-gone) id, *before* the
        # DB's `ON DELETE SET NULL` on sender_id/receiver_id fires below.
        # `deleted_counterpart_marker` has no FK, so it survives the
        # delete untouched; kk/routes/chat.py::list_chats() uses it to
        # keep collapsing this user's messages into one conversation row
        # per car, without merging them with some *other* deleted
        # user's messages about the same car.
        if "message" in table_names:
            from ..models import Message as _ChatMessage

            _ChatMessage.query.filter(
                (_ChatMessage.sender_id == user_id)
                | (_ChatMessage.receiver_id == user_id),
            ).update(
                {"deleted_counterpart_marker": user_id}, synchronize_session=False
            )

        # Not a DB-persisted audit row: UserAction.user_id is itself
        # ON DELETE CASCADE, so any row logged here would just be deleted
        # again a few lines down along with everything else this user
        # owns -- an app-log line is the only thing that actually survives.
        current_app.logger.info(
            "account_deleted user_id=%s username=%s", user_id, username_for_log
        )

        db.session.delete(current_user)
        db.session.commit()

        # Best-effort: delete listing media + the user's own profile picture
        # from storage now that the DB delete has committed (mirrors
        # kk/routes/media.py::delete_car_image()'s commit-then-clean
        # -storage ordering, so a storage-backend hiccup can never block,
        # or partially undo, the account delete itself).
        if pending_media_urls:
            from .media import _delete_media_storage_object

            for url in pending_media_urls:
                try:
                    _delete_media_storage_object(url)
                except Exception as media_err:
                    current_app.logger.warning(
                        "delete_account: best-effort media cleanup failed for "
                        "user_id=%s (url length=%d): %s",
                        user_id,
                        len(url or ""),
                        media_err,
                    )

        # Same best-effort, post-commit ordering for the private dealer
        # verification photo (different storage layout -- see
        # _delete_dealer_verification_file()).
        for filename in dealer_verification_files:
            _delete_dealer_verification_file(filename)

        return jsonify({"message": "Account deleted successfully"}), 200
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

        reset_locale = current_request_locale(getattr(user, "locale", None))
        sms_sent = bool(send_password_reset_sms(dest_phone, token, locale=reset_locale))
        if not sms_sent:
            # M-02: do NOT return a distinct status/body for SMS-delivery
            # failure -- a response that differs only for existing accounts
            # (e.g. a prior 503/"sms_send_failed") lets an attacker enumerate
            # accounts during any SMS provider outage/misconfiguration. Log
            # for ops visibility (no OTP/token/password values) and fall
            # through to the exact same generic 200 response used below for
            # the unknown-phone and successful-send cases.
            current_app.logger.warning(
                "[FORGOT-PASSWORD] SMS send failed for phone=%s*** (provider config/number "
                "format?); responding with generic success to avoid account-existence leak.",
                str(dest_phone)[:4],
            )

        # Dev convenience for local testing only (M-01: SMS_PROVIDER is not
        # part of this gate). Never expose reset tokens in production.
        if dev_debug_response_fields_enabled():
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
            from ..security import (
                _allow_inmemory_rate_limits,
                _rate_limit_unavailable_response,
                _redis_client,
            )

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
            elif not _allow_inmemory_rate_limits():
                # H-06: Redis is required for this per-account guard in
                # production -- fail closed instead of silently skipping it.
                return _rate_limit_unavailable_response()
        except Exception:
            # H-06: a Redis error (timeout, connection drop, etc.) must not
            # silently disable this brute-force guard in production. In
            # development/testing (or with the explicit
            # ALLOW_INMEMORY_RATE_LIMITS escape hatch), preserve the prior
            # best-effort behavior of allowing the request through.
            if not _allow_inmemory_rate_limits():
                return _rate_limit_unavailable_response()

        from ..time_utils import utcnow

        user.set_password(new_password)
        # H-01: revoke every access/refresh token issued before this moment
        # (same commit as the password update and reset-token consumption --
        # no separate transaction). Floored to whole seconds -- see
        # change_password() for why.
        user.tokens_invalid_before = utcnow().replace(microsecond=0)

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


def _send_email_verification_email(user_email: str, token: str) -> bool:
    from ..email_service import send_account_email_verification

    return bool(send_account_email_verification(user_email, token))


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
    except Exception as e:
        db.session.rollback()
        current_app.logger.exception("verify_email failed: %s", e)
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
            attempts = atomic_increment_attempts(user, "phone_verification_attempts")
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

    except Exception as e:
        db.session.rollback()
        current_app.logger.exception("verify_phone failed: %s", e)
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
                # Only surface the known validation cases; never echo str(e) blindly.
                current_app.logger.info("send-verification validation error: %s", str(e))
                if "username" in str(e).lower():
                    return jsonify({"message": "Username already exists"}), 400
                return jsonify({"message": "Invalid input"}), 400
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
        if last_sent and (now - last_sent).total_seconds() < _OTP_RESEND_COOLDOWN_SECONDS:
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
            if dev_debug_response_fields_enabled():
                # Provider error text is an internal detail; dev/debug only.
                if sms_detail:
                    payload["detail"] = sms_detail
                payload["dev_code"] = verification_code
            return jsonify(payload), 200

        # Legacy client expects sent: true on success.
        return jsonify({"message": "Verification code sent successfully", "sent": True}), 200

    except Exception as e:
        db.session.rollback()
        current_app.logger.exception("send_phone_verification failed: %s", e)
        return jsonify({"message": "Failed to send verification code"}), 500


# --- Phone OTP auth endpoints ---

def _google_review_phone_start_response():
    """Response for a `/phone/start` request against the Google Play
    reviewer phone number.

    Provisions the dedicated review account on first use, through the
    exact same `_get_or_create_user_for_phone()` helper every other phone
    number uses (idempotent -- looked up by phone number first, so this
    never creates a duplicate row for an existing account). Deliberately
    does NOT generate a random code, write `phone_verification_code_hash`
    / `_expires_at` / `_locked_until`, or call the SMS provider -- the
    paired bypass in `phone_verify()` checks the fixed `GOOGLE_REVIEW_OTP`
    value directly and never consults that per-user OTP state, so this
    account can never end up locked out by real OTP attempts either.

    Returns the exact same 200 `{"message": "OTP sent"}` shape a real
    successful send returns, and -- unlike the real path -- never includes
    a `dev_code` field, so nothing here can ever expose the reviewer's
    fixed OTP through the debug echo path, and no observer can distinguish
    this response from an ordinary successful send.
    """
    try:
        _get_or_create_user_for_phone(_google_review_phone_digits())
    except Exception:
        current_app.logger.exception("Failed to provision Google review account")
    return jsonify({"message": "OTP sent"}), 200


@bp.route("/api/auth/phone/start", methods=["POST"])
@rate_limit(max_requests=_SEND_OTP_MAX_REQUESTS, window_minutes=_SEND_OTP_WINDOW_MINUTES)
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

        if _is_google_review_phone(phone_digits):
            # Google Play reviewer bypass: identical success response to a
            # real send, no SMS, no signal that this phone number is
            # special. See the module-level comment above
            # `_is_google_review_phone` for the full design invariants.
            return _google_review_phone_start_response()

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
        if last_sent and (now - last_sent).total_seconds() < _OTP_RESEND_COOLDOWN_SECONDS:
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
            if sms_detail and dev_debug_response_fields_enabled():
                # Provider error text is an internal detail; dev/debug only.
                payload["detail"] = sms_detail
            return jsonify(payload), 500

        # Dev convenience only (M-01: SMS_PROVIDER is not part of this gate).
        # Never include the OTP in production responses.
        if dev_debug_response_fields_enabled():
            return jsonify({"message": "OTP sent", "dev_code": verification_code}), 200
        return jsonify({"message": "OTP sent"}), 200
    except Exception:
        current_app.logger.exception("phone_start failed")
        return jsonify({"message": "Failed to start phone verification"}), 500


def _google_review_login_success_response():
    """Authenticates the Google Play reviewer account through the exact
    same account/session/JWT issuance path as a real, successful phone-OTP
    verification.

    Provisions the account on first use (idempotent -- same
    `_get_or_create_user_for_phone()` lookup-by-phone-first helper every
    other phone number uses, so this can never create a duplicate row),
    marks it verified so it has full ordinary-user access during Play
    review, and returns the identical `{access_token, refresh_token,
    user}` shape `phone_verify()` returns for any other successful
    verification. Never reads or writes this phone's
    `phone_verification_code_hash` / `_expires_at` / `_attempts` /
    `_locked_until` -- entirely independent of the real per-user OTP state.
    """
    from ..time_utils import utcnow

    phone_digits = _google_review_phone_digits()
    user = _get_or_create_user_for_phone(phone_digits)

    if not user.is_active:
        # Should never happen for the dedicated review account, but stay
        # consistent with the real deactivated-account response rather
        # than silently issuing tokens for a deactivated row.
        return jsonify({
            "message": "This account has been deactivated. Contact support for assistance.",
            "code": "account_deactivated",
        }), 403

    if not user.is_verified or not user.phone_verified:
        user.is_verified = True
        user.phone_verified = True

    first_login = user.last_login is None
    user.last_login = utcnow()
    db.session.commit()

    access_token = _access_token_for_user(user)
    refresh_token = _refresh_token_for_user(user)
    if first_login:
        log_user_action(user, "signup")
    log_user_action(user, "login_phone")
    return jsonify({
        "access_token": access_token,
        "refresh_token": refresh_token,
        "user": user.to_dict(include_private=True),
    }), 200


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

        if _is_google_review_phone(phone_digits):
            # Google Play reviewer bypass -- ONLY reachable when the phone
            # number matches GOOGLE_REVIEW_PHONE exactly and the feature is
            # enabled (see `_is_google_review_phone`). A wrong code against
            # this exact phone number gets the SAME generic response as any
            # other wrong/expired code -- this never touches, and is never
            # blocked by, the real per-user OTP hash/lockout state for this
            # phone, so the reviewer cannot become permanently locked out.
            if _google_review_otp_matches(code):
                return _google_review_login_success_response()
            return jsonify({"message": "Invalid or expired verification code"}), 400

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
        # Do not create users here — phone/start owns creation and OTP storage.
        # Creating before OTP validation left unverified orphan rows on bad codes.
        user = _get_active_user_by_phone(phone_digits)
        if not user:
            # A deactivated account with a genuinely correct, live code gets
            # a real "account deactivated" answer instead of being folded
            # into the generic branches below (see docstring for why this
            # can't be used to enumerate arbitrary numbers).
            deactivated_response = _deactivated_account_otp_response(phone_digits, code)
            if deactivated_response is not None:
                return deactivated_response
            if not create_if_missing:
                return jsonify({
                    "message": "No account found with this phone number. Please sign up first.",
                    "code": "account_not_found",
                }), 404
            return jsonify({"message": "Invalid or expired verification code"}), 400

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
            attempts = atomic_increment_attempts(user, "phone_verification_attempts")
            if attempts >= 5:
                user.phone_verification_locked_until = now + timedelta(minutes=15)
                user.phone_verification_code_hash = None
                user.phone_verification_expires_at = None
                user.phone_verification_attempts = 0
            db.session.commit()
            return jsonify({"message": "Invalid or expired verification code"}), 400

        if is_dealer_requested:
            _apply_dealer_profile(
                user,
                is_dealer_requested=True,
                dealership_name=dealership_name or None,
                dealership_phone=dealership_phone or None,
                dealership_location=dealership_location or None,
            )

        user.is_verified = True
        user.phone_verified = True
        user.phone_verification_code_hash = None
        user.phone_verification_expires_at = None
        user.phone_verification_attempts = 0
        user.phone_verification_locked_until = None
        first_login = user.last_login is None
        user.last_login = now
        db.session.commit()

        access_token = _access_token_for_user(user)
        refresh_token = _refresh_token_for_user(user)
        if first_login:
            log_user_action(user, "signup")
        log_user_action(user, "login_phone")
        return jsonify({"access_token": access_token, "refresh_token": refresh_token, "user": user.to_dict(include_private=True)}), 200
    except Exception as e:
        db.session.rollback()
        current_app.logger.exception("phone_verify failed: %s", e)
        return jsonify({"message": "Phone verification failed"}), 500


@bp.route("/api/auth/signup", methods=["POST"])
@rate_limit(max_requests=_SIGNUP_MAX_REQUESTS, window_minutes=_SIGNUP_WINDOW_MINUTES)
def compat_signup():
    """
    Compatibility signup endpoint for mobile client.

    Phone + OTP are mandatory: the client must first request a code via
    /api/auth/send_otp (or /api/auth/phone/start), then post it here as
    `otp_code`. There is deliberately no branch that creates an authenticated
    account without a verified code.
    """
    # Bound before the try so the error handlers can log them even if request
    # parsing itself fails.
    raw_username = ""
    phone_digits = ""
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

        # A verified phone is the only way to reach an authenticated account here.
        # Never invent a phone number, and never fall through to a password-only path.
        if not phone_digits:
            return jsonify({
                "message": "Phone number is required",
                "code": "phone_required",
            }), 400
        if not otp_code:
            return jsonify({
                "message": "Verification code is required. Request a code and try again.",
                "code": "otp_required",
            }), 400

        user = User.query.filter_by(phone_number=phone_digits).first()
        if not user:
            return jsonify({
                "message": "User not found. Request a new code.",
                "code": "user_not_found",
            }), 404
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

        # Enforces lockout, expiry and constant-time comparison, and clears the
        # code on success. Raises OtpError, handled below.
        _consume_phone_otp(user, phone_digits, otp_code)

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
        db.session.commit()
        log_user_action(user, "phone_verified")
        access_token = _access_token_for_user(user)
        refresh_token = _refresh_token_for_user(user)
        return jsonify({
            "message": "Signup successful",
            "token": access_token,
            "access_token": access_token,
            "refresh_token": refresh_token,
            "user": user.to_dict(include_private=True),
        }), 201

    except OtpError as e:
        # _consume_phone_otp already committed the attempt counter; do not roll back.
        return e.response()

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
        # The exception text may carry SQL, schema or driver internals. It is
        # logged above with a request id; the client only ever sees this.
        return jsonify({
            "message": "Signup failed. Please try again.",
            "code": "signup_failed",
        }), 500


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

