"""
Security utilities and middleware for the car listing app
"""

import os
import re
import time
from functools import wraps
from flask import request, jsonify, current_app
from flask_jwt_extended import get_jwt_identity, get_jwt
from .models import User, UserAction, db
from datetime import datetime, timedelta
from werkzeug.utils import secure_filename as _secure_filename

def _client_ip() -> str:
    # Respect proxy headers (best-effort). In production, ensure your reverse proxy
    # overwrites/sets X-Forwarded-For correctly.
    xff = (request.headers.get("X-Forwarded-For") or "").split(",")[0].strip()
    return xff or (request.remote_addr or "unknown")


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

def rate_limit(max_requests=10, window_minutes=60, per_ip=True):
    """
    Rate limiting decorator
    """
    def decorator(f):
        @wraps(f)
        def decorated_function(*args, **kwargs):
            # Tests should not be flaky due to global in-process rate limit state.
            env = (os.environ.get("APP_ENV") or "").strip().lower()
            if env == "testing" or bool(current_app.config.get("TESTING")):
                return f(*args, **kwargs)

            # Identifier: IP (default) or user id (if requested).
            identifier = None
            if per_ip:
                identifier = _client_ip()
            else:
                try:
                    user_id = get_jwt_identity()
                    identifier = f"user:{user_id}" if user_id else _client_ip()
                except Exception:
                    identifier = _client_ip()

            window_s = int(window_minutes * 60)
            # Bucket by route+identifier so different endpoints don't share a single counter.
            route = (request.endpoint or request.path or "unknown").replace(" ", "_")
            key = f"rl:{route}:{identifier}:{window_s}"

            r = _redis_client()
            if r is not None:
                try:
                    # Atomic-ish: INCR then set expiry if new.
                    n = r.incr(key)
                    if n == 1:
                        r.expire(key, window_s)
                    if n > int(max_requests):
                        ttl = r.ttl(key)
                        return (
                            jsonify(
                                {
                                    "message": f"Rate limit exceeded. Maximum {max_requests} requests per {window_minutes} minutes.",
                                    "retry_after": max(0, int(ttl) if ttl is not None else window_s),
                                }
                            ),
                            429,
                        )
                    return f(*args, **kwargs)
                except Exception:
                    # Fall through to in-memory on any redis error.
                    pass

            # In-memory fallback (dev only)
            now = time.time()
            window_start = now - window_s
            times = rate_limit_storage.get(key, [])
            times = [t for t in times if t > window_start]
            if len(times) >= max_requests:
                return (
                    jsonify(
                        {
                            "message": f"Rate limit exceeded. Maximum {max_requests} requests per {window_minutes} minutes.",
                            "retry_after": window_s,
                        }
                    ),
                    429,
                )
            times.append(now)
            rate_limit_storage[key] = times
            return f(*args, **kwargs)
        return decorated_function
    return decorator

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

        ok = True
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

        if not ok:
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
    Validate CSRF token for state-changing operations
    """
    def decorator(f):
        @wraps(f)
        def decorated_function(*args, **kwargs):
            # Skip CSRF for GET requests
            if request.method == 'GET':
                return f(*args, **kwargs)
            
            # Check for CSRF token in headers
            csrf_token = request.headers.get('X-CSRF-Token')
            if not csrf_token:
                return jsonify({'message': 'CSRF token required'}), 403
            
            # In a real implementation, you would validate the CSRF token
            # against a stored token or session
            
            return f(*args, **kwargs)
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
