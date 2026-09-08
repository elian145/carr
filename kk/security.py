"""
Security utilities and middleware for the car listing app
"""

import os
import re
import threading
import time
from functools import wraps
from flask import request, jsonify, current_app
from flask_jwt_extended import get_jwt_identity, get_jwt
from sqlalchemy import func, update
from .models import User, UserAction, db
from datetime import datetime, timedelta
from werkzeug.utils import secure_filename as _secure_filename

# D-04: the only User columns `atomic_increment_attempts()` is allowed to
# touch. Keeps a caller from ever passing an attacker-influenced or
# otherwise arbitrary column name into a dynamic UPDATE.
_ATTEMPT_COUNTER_FIELDS = frozenset(
    {
        "phone_verification_attempts",
        "dealer_email_verification_attempts",
        "email_change_attempts",
    }
)


def atomic_increment_attempts(user: User, field_name: str) -> int:
    """
    Atomically increment a User attempt-counter column and return the
    resulting value.

    D-04: replaces the previous Python-side
    ``attempts = int(getattr(user, field, 0) or 0) + 1; user.field = attempts``
    read-modify-write, which could lose an increment when two requests
    against the same account raced (e.g. concurrent wrong-OTP submissions
    partially bypassing the attempt/lockout threshold).

    Uses a single SQL UPDATE expression --
    ``SET field = COALESCE(field, 0) + 1 WHERE id = :id`` -- so the
    increment itself can never be lost to a race, then reloads only that
    one attribute (`db.session.refresh(..., attribute_names=[field_name])`)
    within the *same, not-yet-committed* transaction. That refresh is a
    plain read-your-own-write and always sees this statement's own result
    regardless of isolation level, so it is enough to obtain the true
    post-increment value the caller's lockout-threshold check depends on --
    no ``RETURNING`` (Postgres-only concern for older SQLite libraries,
    unnecessary here) and no row lock beyond the implicit one any UPDATE
    already takes for the rest of its own transaction.

    Does NOT commit and does NOT itself decide any lockout behavior --
    callers keep their existing threshold/lockout/reset logic and existing
    single `db.session.commit()` exactly as before; only how ``attempts``
    is computed changes.

    Raises ``ValueError`` for any ``field_name`` outside the fixed
    allow-list of known attempt-counter columns, so this helper can never
    be turned into a generic "UPDATE any column" primitive.
    """
    if field_name not in _ATTEMPT_COUNTER_FIELDS:
        raise ValueError(f"atomic_increment_attempts: unsupported field {field_name!r}")

    column = getattr(User, field_name)
    db.session.execute(
        update(User)
        .where(User.id == user.id)
        .values(**{field_name: func.coalesce(column, 0) + 1})
    )
    db.session.refresh(user, attribute_names=[field_name])
    return int(getattr(user, field_name) or 0)


def _client_ip() -> str:
    """
    Client IP for rate limiting.

    Use Werkzeug/ProxyFix-adjusted ``request.remote_addr`` only.
    Never trust client-supplied ``X-Forwarded-For`` (attackers can rotate it
    to bypass OTP/login limits). Production enables ProxyFix with ``x_for=1``
    so remote_addr is the real client behind one trusted hop.
    """
    return (request.remote_addr or "unknown").strip() or "unknown"


def _redis_client():
    try:
        import os

        url = (os.environ.get("REDIS_URL") or "").strip()
        if not url:
            return None
        import redis  # type: ignore

        return redis.Redis.from_url(url, decode_responses=True)
    except Exception:
        return None


# Fallback in-process storage (dev only). Not safe across processes/replicas.
rate_limit_storage: dict[str, list[float]] = {}


def _rate_limit_key(per_ip: bool, window_s: int) -> str:
    identifier = None
    if per_ip:
        identifier = _client_ip()
    else:
        try:
            user_id = get_jwt_identity()
            identifier = f"user:{user_id}" if user_id else _client_ip()
        except Exception:
            identifier = _client_ip()
    route = (request.endpoint or request.path or "unknown").replace(" ", "_")
    return f"rl:{route}:{identifier}:{window_s}"


def _rate_limit_response(max_requests: int, window_minutes: int, retry_after: int):
    return (
        jsonify(
            {
                "message": (
                    f"Rate limit exceeded. Maximum {max_requests} requests "
                    f"per {window_minutes} minutes."
                ),
                "retry_after": max(0, int(retry_after)),
            }
        ),
        429,
    )


def _allow_inmemory_rate_limits() -> bool:
    env = (os.environ.get("APP_ENV") or os.environ.get("FLASK_ENV") or "").strip().lower()
    if env in ("development", "testing", "test"):
        return True
    return (os.environ.get("ALLOW_INMEMORY_RATE_LIMITS") or "").strip().lower() in (
        "1",
        "true",
        "yes",
        "on",
    )


def _rate_limit_unavailable_response():
    return (
        jsonify(
            {
                "message": "Rate limiter temporarily unavailable. Please try again shortly.",
                "code": "rate_limiter_unavailable",
            }
        ),
        503,
    )


def check_rate_limit(max_requests=10, window_minutes=60, per_ip=True):
    """
    Return a Flask (response, status) tuple when rate-limited, else None.
    """
    env = (os.environ.get("APP_ENV") or "").strip().lower()
    if env == "testing" or bool(current_app.config.get("TESTING")):
        return None

    window_s = int(window_minutes * 60)
    key = _rate_limit_key(per_ip=per_ip, window_s=window_s)
    allow_memory = _allow_inmemory_rate_limits()

    r = _redis_client()
    if r is not None:
        try:
            n = r.incr(key)
            if n == 1:
                r.expire(key, window_s)
            if n > int(max_requests):
                ttl = r.ttl(key)
                retry_after = max(0, int(ttl) if ttl is not None else window_s)
                return _rate_limit_response(max_requests, window_minutes, retry_after)
            return None
        except Exception:
            # Production without escape hatch: do not silently weaken limits via memory.
            if not allow_memory:
                return _rate_limit_unavailable_response()

    elif not allow_memory:
        return _rate_limit_unavailable_response()

    now = time.time()
    window_start = now - window_s
    times = rate_limit_storage.get(key, [])
    times = [t for t in times if t > window_start]
    if len(times) >= max_requests:
        oldest = min(times) if times else now
        retry_after = max(1, int(window_s - (now - oldest)))
        return _rate_limit_response(max_requests, window_minutes, retry_after)
    times.append(now)
    rate_limit_storage[key] = times
    return None


def rate_limit(max_requests=10, window_minutes=60, per_ip=True):
    """
    Rate limiting decorator
    """
    def decorator(f):
        @wraps(f)
        def decorated_function(*args, **kwargs):
            limited = check_rate_limit(
                max_requests=max_requests,
                window_minutes=window_minutes,
                per_ip=per_ip,
            )
            if limited is not None:
                return limited
            return f(*args, **kwargs)
        return decorated_function
    return decorator


# Fallback in-process storage (dev/test only) for check_global_daily_budget:
# key -> (count, window_start_epoch_seconds). Mirrors `rate_limit_storage`
# above (not safe across processes/replicas) but uses a fixed-window counter
# (reset once `window_s` has elapsed since `window_start`) to mirror the
# Redis INCR + EXPIRE-on-first-increment semantics used in production.
#
# Unlike `rate_limit_storage` (left untouched), this compound
# read-check-increment-write sequence is explicitly protected by
# `_global_budget_storage_lock` below -- not the GIL -- because a lost
# update here would let concurrent threads jointly exceed `max_calls` in a
# single process (the GIL only guarantees individual bytecode atomicity,
# not atomicity across the multi-statement sequence below).
_global_budget_storage: dict[str, tuple[int, float]] = {}
_global_budget_storage_lock = threading.Lock()


def check_global_daily_budget(name: str, max_calls: int, window_minutes: int = 1440):
    """
    BE-19: atomically claim one unit of a GLOBAL (cross-user) daily budget
    for an expensive/external-cost operation identified by ``name``.

    This is deliberately separate from ``check_rate_limit``/``rate_limit``
    above, which throttle request *frequency* per-user or per-IP. This
    bounds the aggregate number of calls to something with a real external
    cost (e.g. an LLM API) across ALL users combined, for a single shared
    window -- so N accounts each under their own per-user rate limit still
    cannot drive unbounded aggregate spend.

    Returns ``None`` when the call is permitted -- in which case one unit of
    budget has ALREADY been claimed for this call. Returns a Flask
    ``(response, status)`` tuple when the call must be rejected, either
    because the daily budget is exhausted or because the backend is
    unavailable and must fail closed (see below); callers should return
    this value as-is.

    Counting semantics (intentional): the unit is claimed BEFORE the
    caller performs the actual expensive work, and is never refunded if
    that work later fails (e.g. the upstream API errors out). For a
    spend-protection circuit breaker, conservative/no-refund counting under
    concurrency is preferred over risking overshoot past the configured
    cap -- a slightly early trip is an acceptable cost of guaranteeing the
    cap is never exceeded.

    Concurrency: uses the same single atomic ``INCR`` (+ ``EXPIRE`` only on
    the first increment) primitive as ``check_rate_limit`` -- never a
    read-then-write/GET-then-SET sequence -- so concurrent requests racing
    against the same window can never jointly exceed ``max_calls`` by more
    than the one increment each already performed atomically. The dev/test
    in-process fallback (see below) is likewise concurrency-safe: its
    compound read/window-check/increment/write is done under an explicit
    ``_global_budget_storage_lock`` (a real ``threading.Lock``, not the
    GIL) covering the whole sequence, not just the individual dict ops.

    Fail-closed semantics (H-06, matching ``check_rate_limit`` /
    ``reset_password``'s inline per-account guard): if Redis is unavailable
    or raises, production requests are rejected (503) unless the explicit
    ``ALLOW_INMEMORY_RATE_LIMITS`` escape hatch (or a development/testing
    ``APP_ENV``) is set, via the existing ``_allow_inmemory_rate_limits()``
    helper -- in which case an in-process fallback counter is used instead
    (not safe across multiple processes/replicas; dev/test only).

    Unlike ``check_rate_limit``, this does NOT unconditionally bypass
    enforcement just because ``current_app.config['TESTING']`` is set --
    callers that need a genuine, testable spend cap (e.g. BE-19) must be
    able to exercise real enforcement under pytest.
    """
    window_s = max(1, int(window_minutes * 60))
    key = f"budget:{name}:{window_s}"
    allow_memory = _allow_inmemory_rate_limits()

    r = _redis_client()
    if r is not None:
        try:
            n = r.incr(key)
            if n == 1:
                r.expire(key, window_s)
            if n > int(max_calls):
                ttl = r.ttl(key)
                retry_after = max(0, int(ttl) if ttl is not None else window_s)
                return _budget_exhausted_response(max_calls, window_minutes, retry_after)
            return None
        except Exception:
            # Production without escape hatch: do not silently weaken the
            # budget cap via an in-process (per-worker, resettable-on-deploy)
            # counter.
            if not allow_memory:
                return _rate_limit_unavailable_response()
    elif not allow_memory:
        return _rate_limit_unavailable_response()

    # Dev/test in-process fallback only (matches `rate_limit_storage` above).
    # Fixed-window counter: reset once `window_s` has elapsed since the
    # window started, mirroring Redis EXPIRE-on-first-increment. The entire
    # read -> window-check -> increment -> write sequence is done under a
    # single lock acquisition so concurrent threads in this process can
    # never jointly exceed `max_calls` via a lost update.
    with _global_budget_storage_lock:
        now = time.time()
        count, window_start = _global_budget_storage.get(key, (0, now))
        if now - window_start >= window_s:
            count, window_start = 0, now
        count += 1
        _global_budget_storage[key] = (count, window_start)
        exceeded = count > int(max_calls)

    if exceeded:
        retry_after = max(1, int(window_s - (now - window_start)))
        return _budget_exhausted_response(max_calls, window_minutes, retry_after)
    return None


def _budget_exhausted_response(max_calls: int, window_minutes: int, retry_after: int):
    return (
        jsonify(
            {
                "error": (
                    f"This AI feature has reached its shared daily budget "
                    f"({max_calls} calls per {window_minutes} minutes). "
                    "Please try again later."
                ),
                "code": "ai_budget_exhausted",
                "configured": True,
                "retry_after": max(0, int(retry_after)),
            }
        ),
        503,
    )


def validate_input_sanitization(data):
    """
    Best-effort input cleanup.

    IMPORTANT:
    - Do NOT destructively strip all HTML tags (it corrupts user data).
    - Do NOT modify secrets (passwords, tokens, OTP codes); only trim whitespace.
    - This does not replace proper validation (length/format) per-field.
    """

    def _is_secret_key(k: str) -> bool:
        k = (k or "").strip().lower()
        return any(
            s in k
            for s in (
                "password",
                "token",
                "refresh_token",
                "access_token",
                "otp",
                "code",
                "verification",
            )
        )

    def _clean_str(s: str, *, secret: bool) -> str:
        if s is None:
            return s
        out = str(s).strip()
        if secret:
            return out
        # Remove script blocks (most dangerous) but keep normal text intact.
        out = re.sub(r"<script.*?</script>", "", out, flags=re.IGNORECASE | re.DOTALL)
        # Remove null bytes / other non-printing control chars that commonly break parsers/logging.
        out = re.sub(r"[\x00-\x08\x0b\x0c\x0e-\x1f]", "", out)
        return out

    if isinstance(data, dict):
        cleaned = {}
        for key, value in data.items():
            k = str(key)
            secret = _is_secret_key(k)
            if isinstance(value, str):
                cleaned[key] = _clean_str(value, secret=secret)
            else:
                cleaned[key] = validate_input_sanitization(value)
        return cleaned
    if isinstance(data, list):
        return [validate_input_sanitization(item) for item in data]
    if isinstance(data, str):
        return _clean_str(data, secret=False)
    return data

def _is_jpeg(h: bytes) -> bool:
    return len(h) >= 3 and h[:3] == b"\xff\xd8\xff"


def _is_png(h: bytes) -> bool:
    return len(h) >= 8 and h[:8] == b"\x89PNG\r\n\x1a\n"


def _is_gif(h: bytes) -> bool:
    return len(h) >= 6 and (h[:6] == b"GIF87a" or h[:6] == b"GIF89a")


def _is_webp(h: bytes) -> bool:
    return len(h) >= 12 and h[:4] == b"RIFF" and h[8:12] == b"WEBP"


def _ftyp_brand(h: bytes) -> str:
    # ISO-BMFF brand in ftyp box: size(4) + 'ftyp'(4) + major_brand(4)
    if len(h) >= 12 and h[4:8] == b"ftyp":
        try:
            return h[8:12].decode("ascii", errors="ignore")
        except Exception:
            return ""
    return ""


def _is_heic_or_heif(h: bytes) -> bool:
    b = _ftyp_brand(h)
    return b in ("heic", "heix", "hevc", "hevx", "mif1", "msf1", "heif")


def _is_mp4(h: bytes) -> bool:
    b = _ftyp_brand(h)
    return b in ("isom", "iso2", "mp41", "mp42", "avc1", "dash")


def _is_mov(h: bytes) -> bool:
    return _ftyp_brand(h) == "qt  "


def _is_avi(h: bytes) -> bool:
    return len(h) >= 12 and h[:4] == b"RIFF" and h[8:12] == b"AVI "


def _is_ebml(h: bytes) -> bool:
    # WebM/MKV are EBML containers.
    return len(h) >= 4 and h[:4] == b"\x1a\x45\xdf\xa3"


def _is_wav(h: bytes) -> bool:
    return len(h) >= 12 and h[:4] == b"RIFF" and h[8:12] == b"WAVE"


def _is_ogg(h: bytes) -> bool:
    return len(h) >= 4 and h[:4] == b"OggS"


def _is_mp3(h: bytes) -> bool:
    if len(h) >= 3 and h[:3] == b"ID3":
        return True
    # Raw MPEG audio frame sync: 11 set bits (0xFFE.....) covers layers used by mp3.
    return len(h) >= 2 and h[0] == 0xFF and (h[1] & 0xE0) == 0xE0


def _is_amr(h: bytes) -> bool:
    # AMR-NB: "#!AMR\n"; AMR-WB: "#!AMR-WB\n".
    return len(h) >= 5 and h[:5] == b"#!AMR"


def _is_m4a_or_aac(h: bytes) -> bool:
    brand = _ftyp_brand(h)
    if brand in ("M4A ", "M4B ", "mp42", "isom", "iso2", "mp41"):
        return True
    # Raw ADTS AAC frame sync (12 set bits: 0xFFF...).
    return len(h) >= 2 and h[0] == 0xFF and (h[1] & 0xF6) == 0xF0


def _is_3gp(h: bytes) -> bool:
    brand = _ftyp_brand(h)
    return brand.startswith("3gp") or brand.startswith("3g2")


def sniff_bytes(header: bytes, ext: str) -> bool:
    """
    Return True if ``header`` (the first bytes of a file) matches the
    expected magic-byte signature for ``ext``.

    ``ext`` may be given with or without a leading dot (e.g. ``"jpg"`` or
    ``".jpg"``) and is compared case-insensitively.

    Extracted from ``validate_file_upload_security()`` (H-03 follow-up) so
    upload paths that never go through a Werkzeug ``FileStorage`` — e.g.
    chat attachments, which read the whole body into memory before handing
    it to R2 — can reuse the exact same signature checks used by the
    already-validated listing-media multipart uploads.

    Behavior-preserving for every extension the original inline check
    covered (image + video): unrecognized extensions default to ``True``
    (not rejected — size/extension checks elsewhere still apply), and image
    extensions fall back to "any known image signature" to tolerate mobile
    pipelines that transcode HEIC -> JPEG bytes but keep the original
    filename extension.

    Adds new coverage (not previously checked anywhere) for the audio
    extensions accepted by chat voice messages: m4a/aac, mp3, wav, ogg,
    amr, 3gp. webm audio reuses the existing EBML (WebM/MKV) container
    check, since it's the same container format as webm video.
    """
    ext = (ext or "").strip().lower().lstrip(".")

    ok = True
    is_any_known_image = (
        _is_jpeg(header)
        or _is_png(header)
        or _is_gif(header)
        or _is_webp(header)
        or _is_heic_or_heif(header)
    )
    if ext in ("jpg", "jpeg"):
        ok = _is_jpeg(header)
    elif ext == "png":
        ok = _is_png(header)
    elif ext == "gif":
        ok = _is_gif(header)
    elif ext == "webp":
        ok = _is_webp(header)
    elif ext in ("heic", "heif"):
        ok = _is_heic_or_heif(header)
    elif ext == "mp4":
        ok = _is_mp4(header)
    elif ext == "mov":
        ok = _is_mov(header)
    elif ext == "avi":
        ok = _is_avi(header)
    elif ext in ("mkv", "webm"):
        ok = _is_ebml(header)
    elif ext == "wav":
        ok = _is_wav(header)
    elif ext == "ogg":
        ok = _is_ogg(header)
    elif ext == "mp3":
        ok = _is_mp3(header)
    elif ext == "amr":
        ok = _is_amr(header)
    elif ext in ("m4a", "aac"):
        ok = _is_m4a_or_aac(header)
    elif ext == "3gp":
        ok = _is_3gp(header)

    # Mobile/OS pipelines sometimes transcode images but keep the original
    # file extension (e.g. HEIC -> JPEG bytes). Accept any known image
    # binary for image extensions while still rejecting non-image payloads.
    if not ok and ext in ("jpg", "jpeg", "png", "gif", "webp", "heic", "heif"):
        ok = is_any_known_image

    return ok


def validate_file_upload_security(file, allowed_extensions=None, max_size_mb=10):
    """
    Enhanced file upload security validation
    """
    if not file or not file.filename:
        return False, "No file provided"
    
    # Check file extension
    if allowed_extensions:
        file_ext = file.filename.rsplit('.', 1)[1].lower() if '.' in file.filename else ''
        if file_ext not in allowed_extensions:
            return False, f"File type not allowed. Allowed: {', '.join(allowed_extensions)}"
    
    # Check file size
    file.seek(0, 2)  # Seek to end
    file_size = file.tell()
    file.seek(0)  # Reset to beginning
    
    max_size_bytes = max_size_mb * 1024 * 1024
    if file_size > max_size_bytes:
        return False, f"File too large. Maximum size: {max_size_mb}MB"
    
    # Check for suspicious file names
    filename = file.filename.lower()
    suspicious_patterns = ['..', '/', '\\', '<', '>', ':', '"', '|', '?', '*']
    if any(pattern in filename for pattern in suspicious_patterns):
        return False, "Invalid file name"

    # Magic-byte sniffing (best-effort) to catch extension spoofing.
    try:
        ext = file.filename.rsplit(".", 1)[1].lower() if "." in file.filename else ""
        # Read a small header without consuming the stream permanently.
        try:
            pos = file.tell()
        except Exception:
            pos = 0
        try:
            file.seek(0)
            header = file.read(32) or b""
        finally:
            try:
                file.seek(pos)
            except Exception:
                try:
                    file.seek(0)
                except Exception:
                    pass

        if not sniff_bytes(header, ext):
            return False, "File content does not match its extension"
    except Exception:
        # Do not block uploads if sniffing fails unexpectedly; size/ext checks still apply.
        pass
    
    return True, "File is valid"


# Compatibility helpers
def generate_secure_filename(filename: str) -> str:
    """
    Generate a safe filename for storing user uploads.

    Kept for compatibility with routes that previously imported this symbol.
    """
    return _secure_filename(filename)


def validate_file_upload(file, allowed_extensions=None, max_size_mb=10):
    """
    Backwards-compatible alias for file upload validation.
    """
    return validate_file_upload_security(
        file,
        allowed_extensions=allowed_extensions,
        max_size_mb=max_size_mb,
    )

def log_security_event(user_id, event_type, details=None, ip_address=None):
    """
    Log security-related events
    """
    try:
        from .time_utils import utcnow

        action = UserAction(
            user_id=user_id,
            action_type=f"security_{event_type}",
            target_type="security",
            action_metadata={
                'details': details,
                'ip_address': ip_address or request.remote_addr,
                'user_agent': request.headers.get('User-Agent'),
                'timestamp': utcnow().isoformat()
            }
        )
        
        db.session.add(action)
        db.session.commit()
    except Exception as e:
        current_app.logger.error(f"Failed to log security event: {str(e)}")

def check_suspicious_activity(user_id, action_type):
    """
    Check for suspicious user activity patterns
    """
    try:
        # Check for rapid successive actions
        from .time_utils import utcnow

        recent_actions = UserAction.query.filter(
            UserAction.user_id == user_id,
            UserAction.action_type == action_type,
            UserAction.created_at >= utcnow() - timedelta(minutes=5)
        ).count()
        
        if recent_actions > 20:  # More than 20 actions in 5 minutes
            log_security_event(user_id, "suspicious_rapid_activity", {
                'action_type': action_type,
                'count': recent_actions
            })
            return True, "Suspicious rapid activity detected"
        
        return False, None
    except Exception as e:
        current_app.logger.error(f"Failed to check suspicious activity: {str(e)}")
        return False, None

def validate_jwt_payload(jwt_payload):
    """
    Validate JWT payload for security
    """
    required_fields = ['sub', 'exp', 'iat', 'jti']
    
    for field in required_fields:
        if field not in jwt_payload:
            return False, f"Missing required JWT field: {field}"
    
    # Check token age
    iat = jwt_payload.get('iat')
    if iat:
        token_age = time.time() - iat
        if token_age > 86400:  # 24 hours
            return False, "Token too old"
    
    return True, "JWT payload is valid"

def secure_headers():
    """
    Add security headers to responses
    """
    def decorator(f):
        @wraps(f)
        def decorated_function(*args, **kwargs):
            response = f(*args, **kwargs)
            
            if hasattr(response, 'headers'):
                # Add security headers
                response.headers['X-Content-Type-Options'] = 'nosniff'
                response.headers['X-Frame-Options'] = 'DENY'
                response.headers['X-XSS-Protection'] = '1; mode=block'
                response.headers['Strict-Transport-Security'] = 'max-age=31536000; includeSubDomains'
                response.headers['Content-Security-Policy'] = "default-src 'self'"
            
            return response
        return decorated_function
    return decorator

def validate_csrf_token():
    """
    Intentionally unavailable.

    The API uses Bearer JWTs (mobile + admin cookie). A decorator that only
    checked for a header *presence* without verifying it would be worse than
    no CSRF check. Prefer JWT auth; do not wire this stub onto routes.
    """
    def decorator(f):
        @wraps(f)
        def decorated_function(*args, **kwargs):
            return (
                jsonify(
                    {
                        "message": "CSRF middleware is not enabled for this API",
                        "code": "csrf_not_configured",
                    }
                ),
                501,
            )

        return decorated_function

    return decorator

def audit_log(action_type, target_type=None, target_id=None, metadata=None):
    """
    Create audit log entry
    """
    def decorator(f):
        @wraps(f)
        def decorated_function(*args, **kwargs):
            try:
                # Get current user
                user_id = get_jwt_identity()
                if user_id:
                    user = User.query.filter_by(public_id=user_id).first()
                    if user:
                        log_user_action(user, action_type, target_type, target_id, metadata)
            except Exception as e:
                current_app.logger.error(f"Failed to create audit log: {str(e)}")
            
            return f(*args, **kwargs)
        return decorated_function
    return decorator

def validate_ownership(resource_type, resource_id_field='id'):
    """
    Validate that the current user owns the resource
    """
    def decorator(f):
        @wraps(f)
        def decorated_function(*args, **kwargs):
            try:
                current_user_id = get_jwt_identity()
                if not current_user_id:
                    return jsonify({'message': 'Authentication required'}), 401
                
                user = User.query.filter_by(public_id=current_user_id).first()
                if not user:
                    return jsonify({'message': 'User not found'}), 404
                
                # Get resource ID from kwargs
                resource_id = kwargs.get(resource_id_field)
                if not resource_id:
                    return jsonify({'message': 'Resource ID required'}), 400
                
                # Check ownership based on resource type
                if resource_type == 'car':
                    from .models import Car
                    resource = Car.query.filter_by(public_id=resource_id).first()
                    if not resource:
                        return jsonify({'message': 'Car not found'}), 404
                    if resource.seller_id != user.id and not user.is_admin:
                        return jsonify({'message': 'Not authorized to access this resource'}), 403
                
                # Add user to kwargs for use in the decorated function
                kwargs['current_user'] = user
                kwargs['resource'] = resource
                
            except Exception as e:
                current_app.logger.error(f"Ownership validation error: {str(e)}")
                return jsonify({'message': 'Authorization check failed'}), 500
            
            return f(*args, **kwargs)
        return decorated_function
    return decorator
