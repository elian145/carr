from functools import wraps
from flask import request, jsonify, current_app
from flask_jwt_extended import jwt_required, get_jwt_identity, get_jwt
from .models import User, db, PasswordReset, EmailVerification
from datetime import datetime, timedelta
import secrets
import re

from sqlalchemy import String as _SAString, type_coerce as _sa_type_coerce, update

from .reset_token_crypto import (
    HASH_PREFIX as _RESET_HASH_PREFIX,
    hash_reset_token,
    legacy_plaintext_enabled,
    tokens_equal,
)

def validate_email(email):
    """Validate email format"""
    pattern = r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$'
    return re.match(pattern, email) is not None

def validate_password(password):
    """Validate password strength"""
    if len(password) < 8:
        return False, "Password must be at least 8 characters long"
    
    if not re.search(r'[A-Z]', password):
        return False, "Password must contain at least one uppercase letter"
    
    if not re.search(r'[a-z]', password):
        return False, "Password must contain at least one lowercase letter"
    
    if not re.search(r'\d', password):
        return False, "Password must contain at least one number"
    
    if not re.search(r'[!@#$%^&*(),.?":{}|<>]', password):
        return False, "Password must contain at least one special character"
    
    return True, "Password is valid"

def validate_phone_number(phone):
    """Validate phone number format"""
    # Remove all non-digit characters
    digits = re.sub(r'\D', '', phone)
    
    # Check if it's a valid length (7-15 digits)
    if len(digits) < 7 or len(digits) > 15:
        return False
    
    return True

def request_has_admin_privileges(user=None) -> bool:
    """True only for an AdminAccount-scoped dashboard admin JWT session.

    Batch 1 / 1B: ``User.is_admin`` alone never grants elevated access on
    admin APIs or on user-facing ownership/moderation bypasses. Requires:
    - ``user.is_admin``
    - JWT ``account_scope=admin`` (not phone-OTP)
    - an active ``AdminAccount`` principal for ``user``
    """
    if user is None:
        user = get_current_user()
    if not user or not getattr(user, "is_admin", False):
        return False
    try:
        claims = get_jwt() or {}
    except Exception:
        return False
    if claims.get("account_scope") != "admin":
        return False
    if claims.get("auth_method") == "phone_otp":
        return False
    from .models import AdminAccount

    return (
        AdminAccount.query.filter_by(
            principal_user_id=user.id,
            is_active=True,
        ).first()
        is not None
    )


def admin_required(f):
    """Decorator to require admin privileges.

    SEC-005 / ADM-1: ``User.is_admin`` alone is not enough. Admin APIs require
    a request that satisfies ``request_has_admin_privileges`` (AdminAccount
    dashboard JWT). Pure mobile phone-OTP / mobile password tokens never
    satisfy this gate, even when the underlying ``User.is_admin`` flag is true.
    """
    @wraps(f)
    @jwt_required()
    def decorated_function(*args, **kwargs):
        current_user = get_current_user()
        if not request_has_admin_privileges(current_user):
            return jsonify({'message': 'Admin privileges required'}), 403
        return f(*args, **kwargs)
    return decorated_function

def get_current_user():
    """Get current user from JWT token"""
    try:
        current_user_id = get_jwt_identity()
        if not current_user_id:
            return None

        ident = str(current_user_id).strip()
        user = User.query.filter_by(public_id=ident).first()
        if not user and ident.startswith("user:"):
            try:
                uid = int(ident.split(":", 1)[1])
                user = User.query.filter_by(id=uid).first()
            except Exception:
                user = None
        if not user and ident.isdigit():
            try:
                user = User.query.filter_by(id=int(ident)).first()
            except Exception:
                user = None
        if not user or not user.is_active:
            return None

        return user
    except Exception as e:
        current_app.logger.error(f"Error getting current user: {str(e)}")
        return None


def phone_verification_required_response(user):
    """
    Return (jsonify(...), status_code) when the user must verify their phone first.
    Admins are exempt. Returns None when the user may proceed.
    """
    payload = phone_verification_error_payload(user)
    if payload is None:
        return None
    if payload.get("code") is None:
        return jsonify({"message": payload["message"]}), 404
    return jsonify(payload), 403


def user_phone_verified(user) -> bool:
    """True when the user completed phone OTP (not email-only verification)."""
    if not user:
        return False
    if hasattr(user, "phone_verified"):
        return bool(getattr(user, "phone_verified", False))
    # Pre-migration fallback: legacy is_verified was conflated with phone.
    return bool(getattr(user, "is_verified", False))


def phone_verification_error_payload(user) -> dict | None:
    """Return an error payload dict, or None when the user may proceed."""
    if not user:
        return {"message": "User not found", "code": None}
    # Batch 1B: only a real AdminAccount dashboard session is exempt — not
    # a mobile row that merely has ``User.is_admin=True``.
    if request_has_admin_privileges(user):
        return None
    if not user_phone_verified(user):
        return {
            "message": "Verify your phone number before continuing.",
            "code": "phone_verification_required",
        }
    return None


def create_password_reset_token(user, *, channel: str = "sms"):
    """Create password reset token.

    SMS: 12-digit numeric (harder online guessing than 8-digit).
    Email / other: high-entropy URL-safe opaque token.

    F-29: the RAW token is returned to the caller (to be sent to the user) but is never
    persisted: ``PasswordReset.token`` is a ``HashedResetToken`` column, so the row holds
    only ``h1$`` + HMAC-SHA256(pepper, token). Returned value/format/expiry are unchanged.
    """
    # Delete any existing tokens for this user
    PasswordReset.query.filter_by(user_id=user.id, is_used=False).delete()

    channel_l = (channel or "sms").strip().lower()
    token = None
    if channel_l == "email":
        token = secrets.token_urlsafe(32)
    else:
        # 12-digit numeric for SMS providers; retry on rare uniqueness collisions.
        for _ in range(10):
            candidate = f"{secrets.randbelow(1_000_000_000_000):012d}"
            exists = PasswordReset.query.filter_by(token=candidate, is_used=False).first()
            if not exists:
                token = candidate
                break
        if token is None:
            token = "".join(str(secrets.randbelow(10)) for _ in range(12))
    from .time_utils import utcnow

    expires_at = utcnow() + timedelta(hours=1)

    reset_token = PasswordReset(
        user_id=user.id,
        token=token,
        expires_at=expires_at
    )

    db.session.add(reset_token)
    db.session.commit()

    return token

def create_email_verification_token(user):
    """Create email verification token"""
    # Delete any existing tokens for this user
    EmailVerification.query.filter_by(user_id=user.id, is_used=False).delete()
    
    # Create new token
    token = secrets.token_urlsafe(32)
    from .time_utils import utcnow

    expires_at = utcnow() + timedelta(days=1)
    
    verification_token = EmailVerification(
        user_id=user.id,
        token=token,
        expires_at=expires_at
    )
    
    db.session.add(verification_token)
    db.session.commit()
    
    return token

def _find_legacy_plaintext_row(token):
    """Pre-F-29 rows stored the raw token. REMOVABLE once no such row can still be valid
    (tokens live 1 hour): delete this function, its call below and ``legacy_plaintext_enabled``.
    """
    if not isinstance(token, str) or not token or token.startswith(_RESET_HASH_PREFIX):
        return None
    # type_coerce bypasses HashedResetToken so the raw value is compared as-is.
    row = PasswordReset.query.filter(
        _sa_type_coerce(PasswordReset.token, _SAString()) == token,
        PasswordReset.is_used.is_(False),
    ).first()
    if row is None or not isinstance(row.token, str) or not tokens_equal(row.token, token):
        return None
    return row


def _scrub_legacy_row(row, token):
    """Rewrite a legacy plaintext row to its hashed form so the plaintext is gone from the DB
    (and so ``PasswordReset.query.filter_by(token=<raw>)`` in the reset route now finds it)."""
    from sqlalchemy import literal

    db.session.execute(
        update(PasswordReset)
        .where(PasswordReset.id == row.id)
        .values(token=literal(hash_reset_token(token), _SAString()))
    )
    db.session.commit()
    # Reload the instance so it no longer carries the stale plaintext attribute.
    db.session.refresh(row)


def verify_password_reset_token(token):
    """Verify password reset token (raw token in, user out; lookup is by hash)."""
    expected = hash_reset_token(token)
    # ``filter_by(token=token)`` binds hash_reset_token(token) via HashedResetToken.
    reset_token = PasswordReset.query.filter_by(token=token, is_used=False).first()
    if reset_token is not None and not tokens_equal(str(reset_token.token), expected):
        reset_token = None  # defence in depth: constant-time confirmation of the DB match

    if reset_token is None and legacy_plaintext_enabled():
        legacy = _find_legacy_plaintext_row(token)
        if legacy is not None:
            _scrub_legacy_row(legacy, token)
            reset_token = legacy

    if not reset_token:
        return None, "Invalid or expired token"

    if reset_token.is_expired():
        reset_token.is_used = True
        db.session.commit()
        return None, "Token has expired"

    # Models.PasswordReset does not define a relationship attribute; resolve the
    # user explicitly via user_id so this works across all DBs.
    user = User.query.get(reset_token.user_id)
    if not user:
        return None, "Invalid or expired token"
    return user, None


def invalidate_password_reset_tokens(user_id):
    """Mark every still-unused reset token of ``user_id`` as used (e.g. after a password change).

    Keyed by ``user_id`` only, so it also covers legacy plaintext rows (pre-F-29, still in the
    table until they expire) and rows that were never presented to ``verify_password_reset_token``.
    Call it in the SAME transaction as the password write; the caller commits. A reset token
    created afterwards (``create_password_reset_token``) is unaffected and works normally.
    """
    PasswordReset.query.filter_by(user_id=user_id, is_used=False).update(
        {"is_used": True}, synchronize_session=False
    )


def consume_password_reset_token(token, user_id):
    """Atomically claim ``token`` (single use): ``UPDATE ... SET is_used = true WHERE is_used = false``.

    Returns True only for the one caller whose UPDATE flips the row. Concurrent redeemers (or a
    password change that already invalidated the row) get rowcount 0 -> False, because the
    database re-evaluates the ``is_used`` predicate after the competing transaction commits
    (PostgreSQL READ COMMITTED row lock; SQLite serialises writers). Does not commit: call it in
    the same transaction as the password write so a failed claim can be rolled back with it.
    """
    result = db.session.execute(
        update(PasswordReset)
        .where(
            PasswordReset.token == token,  # HashedResetToken hashes the bound raw value
            PasswordReset.user_id == user_id,
            PasswordReset.is_used.is_(False),
        )
        .values(is_used=True)
        .execution_options(synchronize_session=False)
    )
    return result.rowcount == 1

def verify_email_verification_token(token):
    """Verify email verification token (raw token in; lookup is by HMAC hash, F-29 follow-up)."""
    # ``filter_by(token=token)`` binds the hashed value via HashedEmailVerificationToken.
    verification_token = EmailVerification.query.filter_by(token=token, is_used=False).first()
    if (
        verification_token is None
        and legacy_plaintext_enabled()
        and isinstance(token, str)
        and token
        and not token.startswith(_RESET_HASH_PREFIX)
    ):
        # Rows created before this change hold the plaintext token (<= 1 day lifetime).
        # type_coerce bypasses the hashing type so the raw value is compared as stored.
        legacy = EmailVerification.query.filter(
            _sa_type_coerce(EmailVerification.token, _SAString()) == token,
            EmailVerification.is_used.is_(False),
        ).first()
        if legacy is not None and tokens_equal(str(legacy.token), token):
            verification_token = legacy
    
    if not verification_token:
        return None, "Invalid or expired token"
    
    if verification_token.is_expired():
        verification_token.is_used = True
        db.session.commit()
        return None, "Token has expired"

    user = User.query.get(verification_token.user_id)
    if not user:
        return None, "Invalid or expired token"
    verification_token.is_used = True
    db.session.commit()
    return user, None

def log_user_action(user, action_type, target_type=None, target_id=None, metadata=None):
    """Log user action for analytics"""
    try:
        from .models import UserAction
        
        action = UserAction(
            user_id=user.id,
            action_type=action_type,
            target_type=target_type,
            target_id=target_id,
            action_metadata=metadata,
        )

        db.session.add(action)
        db.session.commit()
    except Exception as e:
        db.session.rollback()
        current_app.logger.error(f"Error logging user action: {str(e)}")

_AUDIT_REDACT_KEY = re.compile(
    r"(e[-_]?mail|phone|mobile|password|passwd|token|secret|otp|address|authorization|"
    r"cookie|session|national|passport|card|iban)",
    re.IGNORECASE,
)
_AUDIT_MAX_STR = 200
_AUDIT_MAX_ITEMS = 25
_AUDIT_MAX_DEPTH = 3
_AUDIT_MAX_JSON = 4000


def audit_safe_metadata(value, _depth=0):
    """Bound and de-identify metadata before it enters the append-only audit table.

    ``admin_audit_log`` rows can never be edited or deleted, so whatever lands
    there stays for good. Raw request bodies / free text must therefore not be
    stored unbounded: values under personal-data-looking keys are redacted,
    strings are truncated, containers are capped in size and depth, and the whole
    document is capped (replaced by a key list if still too large).
    """
    import json

    if _depth == 0:
        out = audit_safe_metadata(value, 1)
        try:
            if len(json.dumps(out, default=str)) > _AUDIT_MAX_JSON:
                keys = sorted(out.keys()) if isinstance(out, dict) else []
                return {"_truncated": True, "keys": [str(k)[:60] for k in keys[:_AUDIT_MAX_ITEMS]]}
        except (TypeError, ValueError):
            return {"_unserializable": True}
        return out
    if value is None or isinstance(value, (bool, int, float)):
        return value
    if isinstance(value, str):
        return value if len(value) <= _AUDIT_MAX_STR else value[:_AUDIT_MAX_STR] + "...[truncated]"
    if _depth >= _AUDIT_MAX_DEPTH + 1:
        return "[nested]"
    if isinstance(value, dict):
        cleaned = {}
        for i, (k, v) in enumerate(value.items()):
            if i >= _AUDIT_MAX_ITEMS:
                cleaned["_more_keys"] = len(value) - _AUDIT_MAX_ITEMS
                break
            key = str(k)[:60]
            cleaned[key] = "[redacted]" if _AUDIT_REDACT_KEY.search(key) else audit_safe_metadata(v, _depth + 1)
        return cleaned
    if isinstance(value, (list, tuple, set)):
        items = list(value)
        cleaned = [audit_safe_metadata(v, _depth + 1) for v in items[:_AUDIT_MAX_ITEMS]]
        if len(items) > _AUDIT_MAX_ITEMS:
            cleaned.append(f"[+{len(items) - _AUDIT_MAX_ITEMS} more]")
        return cleaned
    return str(value)[:_AUDIT_MAX_STR]


def log_admin_action(admin_user, action_type, target_type=None, target_id=None, metadata=None):
    """Record an administrator action (F-17).

    Writes the durable, append-only ``AdminAuditLog`` row (survives deletion of
    the admin / target user) and also the legacy ``UserAction`` row that
    existing admin UI/tests read. Failures are logged, never raised.
    """
    try:
        from .models import AdminAuditLog, UserAction

        db.session.add(
            AdminAuditLog(
                admin_user_id=getattr(admin_user, "id", None),
                admin_username=(getattr(admin_user, "username", None) or None),
                action_type=action_type,
                target_type=target_type,
                target_id=target_id,
                action_metadata=audit_safe_metadata(metadata) if metadata is not None else None,
            )
        )
        if getattr(admin_user, "id", None) is not None:
            db.session.add(
                UserAction(
                    user_id=admin_user.id,
                    action_type=action_type,
                    target_type=target_type,
                    target_id=target_id,
                    action_metadata=metadata,
                )
            )
        db.session.commit()
    except Exception as e:
        db.session.rollback()
        current_app.logger.error(f"Error logging admin action: {str(e)}")


def validate_user_input(data, required_fields=None):
    """Validate user input data"""
    errors = []
    
    if required_fields:
        for field in required_fields:
            if field not in data or not data[field]:
                errors.append(f"{field} is required")
    
    # Validate phone number if present (now required for authentication)
    if 'phone_number' in data and data['phone_number']:
        if not validate_phone_number(data['phone_number']):
            errors.append("Invalid phone number format")
    
    # Validate email if present (now optional)
    if 'email' in data and data['email']:
        if not validate_email(data['email']):
            errors.append("Invalid email format")
    
    # Validate password if present
    if 'password' in data and data['password']:
        is_valid, message = validate_password(data['password'])
        if not is_valid:
            errors.append(message)
    
    # Validate username if present
    if 'username' in data and data['username']:
        username = data['username']
        if len(username) < 3 or len(username) > 20:
            errors.append("Username must be between 3 and 20 characters")
        if not re.match(r'^[a-zA-Z0-9_]+$', username):
            errors.append("Username can only contain letters, numbers, and underscores")
    
    return errors

def sanitize_input(data):
    """Sanitize user input to reduce XSS / control-character injection (S-11).

    Delegates to [validate_input_sanitization], which strips script blocks and
    non-printing controls while preserving normal multilingual text and secrets.
    """
    from .security import validate_input_sanitization

    return validate_input_sanitization(data)

def rate_limit_check(user_id, action, limit=10, window_minutes=60):
    """Check if user has exceeded rate limit for an action"""
    try:
        from .models import UserAction
        from datetime import timedelta
        from .time_utils import utcnow
        
        window_start = utcnow() - timedelta(minutes=window_minutes)
        
        recent_actions = UserAction.query.filter(
            UserAction.user_id == user_id,
            UserAction.action_type == action,
            UserAction.created_at >= window_start
        ).count()
        
        return recent_actions < limit
    except Exception as e:
        current_app.logger.error(f"Error checking rate limit: {str(e)}")
        # H-06: do not silently allow unlimited actions when the DB check
        # itself fails. Preserve the previous lenient behavior only in
        # development/testing (or the explicit ALLOW_INMEMORY_RATE_LIMITS
        # escape hatch); fail closed (deny) everywhere else.
        from .security import _allow_inmemory_rate_limits

        return _allow_inmemory_rate_limits()

def generate_secure_filename(filename):
    """Generate secure filename for uploads"""
    import os
    from werkzeug.utils import secure_filename
    
    # Get file extension
    _, ext = os.path.splitext(filename)
    
    # Generate secure filename with timestamp
    from .time_utils import utcnow

    timestamp = utcnow().strftime('%Y%m%d_%H%M%S')
    random_string = secrets.token_hex(8)
    
    return f"{timestamp}_{random_string}{ext}"

def allowed_file(filename, allowed_extensions):
    """Check if file extension is allowed"""
    return '.' in filename and \
           filename.rsplit('.', 1)[1].lower() in allowed_extensions

def validate_file_upload(file, max_size_mb=10, allowed_extensions=None):
    """Validate file upload"""
    if not file or not file.filename:
        return False, "No file selected"
    
    if not allowed_file(file.filename, allowed_extensions or []):
        return False, f"File type not allowed. Allowed types: {', '.join(allowed_extensions)}"
    
    # Check file size
    file.seek(0, 2)  # Seek to end
    file_size = file.tell()
    file.seek(0)  # Reset to beginning
    
    max_size_bytes = max_size_mb * 1024 * 1024
    if file_size > max_size_bytes:
        return False, f"File too large. Maximum size: {max_size_mb}MB"
    
    return True, "File is valid"
