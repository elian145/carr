import os
from datetime import timedelta
from dotenv import load_dotenv

load_dotenv()

_DEV_SECRET_FALLBACK = "dev-only-insecure-secret"
_DEV_JWT_SECRET_FALLBACK = "dev-only-insecure-jwt-secret"

def get_app_env() -> str:
    """
    Determine the runtime environment.

    Preferred: APP_ENV=development|production|testing
    Fallbacks: FLASK_ENV (legacy), then production.
    """
    env = (os.environ.get("APP_ENV") or os.environ.get("FLASK_ENV") or "").strip().lower()
    # SECURITY: default to production if unset, so accidental deploys
    # don't run with DEBUG=True, permissive CORS, and dev secrets.
    return env or "production"

def validate_required_secrets(env: str | None = None) -> None:
    """
    Fail fast outside development/testing if critical secrets are missing.
    """
    env_name = (env or get_app_env()).strip().lower()
    if env_name in ("development", "testing"):
        return
    missing: list[str] = []
    for key in ('SECRET_KEY', 'JWT_SECRET_KEY', 'DATABASE_URL'):
        if not (os.environ.get(key) or '').strip():
            missing.append(key)
    if missing:
        raise RuntimeError(
            "Missing required environment variables for production: "
            + ", ".join(missing)
            + ". Set them (and restart) before running with APP_ENV=production."
        )
    # Also reject the known-insecure dev fallbacks if they were explicitly set.
    if (os.environ.get("SECRET_KEY") or "").strip() == _DEV_SECRET_FALLBACK:
        raise RuntimeError("SECRET_KEY is set to an insecure dev fallback; set a strong production secret.")
    if (os.environ.get("JWT_SECRET_KEY") or "").strip() == _DEV_JWT_SECRET_FALLBACK:
        raise RuntimeError("JWT_SECRET_KEY is set to an insecure dev fallback; set a strong production secret.")
    validate_upload_persistence(env_name)
    validate_chat_media_persistence(env_name)
    validate_redis_required(env_name)


def _env_flag(name: str) -> bool:
    return (os.environ.get(name) or "").strip().lower() in ("1", "true", "yes", "on")


def _r2_credentials_present() -> bool:
    account = (os.environ.get("R2_ACCOUNT_ID") or "").strip()
    bucket = (os.environ.get("R2_BUCKET_NAME") or "").strip()
    access = (
        (os.environ.get("R2_ACCESS_KEY_ID") or "").strip()
        or (os.environ.get("AWS_ACCESS_KEY_ID") or "").strip()
    )
    secret = (
        (os.environ.get("R2_SECRET_ACCESS_KEY") or "").strip()
        or (os.environ.get("AWS_SECRET_ACCESS_KEY") or "").strip()
    )
    return bool(account and bucket and access and secret)


def _r2_public_url_present() -> bool:
    return bool((os.environ.get("R2_PUBLIC_URL") or "").strip())


def _r2_chat_credentials_present() -> bool:
    """True when the PRIVATE chat-media R2 bucket (C-10) is fully configured."""
    return bool(
        (os.environ.get("R2_ACCOUNT_ID") or "").strip()
        and (os.environ.get("R2_CHAT_BUCKET_NAME") or "").strip()
        and (os.environ.get("R2_CHAT_ACCESS_KEY_ID") or "").strip()
        and (os.environ.get("R2_CHAT_SECRET_ACCESS_KEY") or "").strip()
    )


def _r2_chat_credentials_partial() -> bool:
    """True when some but not all chat-media R2 vars are set (misconfiguration).

    A partial configuration would silently fall back to the unauthenticated
    local-disk path for new chat uploads while looking configured — this is
    exactly the failure mode C-10 exists to prevent, so it must fail loudly
    in production instead.
    """
    chat_specific = (
        (os.environ.get("R2_CHAT_BUCKET_NAME") or "").strip(),
        (os.environ.get("R2_CHAT_ACCESS_KEY_ID") or "").strip(),
        (os.environ.get("R2_CHAT_SECRET_ACCESS_KEY") or "").strip(),
    )
    if not any(chat_specific):
        return False
    return not _r2_chat_credentials_present()


def chat_media_storage_mode() -> str:
    """
    Report how new chat media will be stored (C-10).

    - ``r2_private``: dedicated private R2 bucket configured (R2_CHAT_*)
    - ``r2_chat_incomplete``: some R2_CHAT_* vars set but not all
    - ``disk``: local fallback under kk/static/chat_* (NOT private/authorized)
    """
    if _r2_chat_credentials_present():
        return "r2_private"
    if _r2_chat_credentials_partial():
        return "r2_chat_incomplete"
    return "disk"


def _persistent_upload_folder_configured() -> bool:
    """True when UPLOAD_FOLDER is an absolute path (Render disk / Docker volume)."""
    raw = (os.environ.get("UPLOAD_FOLDER") or "").strip()
    if not raw:
        return False
    # Production hosts are Linux; treat POSIX absolute paths as persistent even when
    # this helper runs on Windows (dev machines / CI).
    if raw.startswith("/"):
        return True
    return os.path.isabs(raw)


def upload_persistence_mode() -> str:
    """
    Report how listing media will survive redeploys.

    - ``r2``: Cloudflare R2 credentials + public URL configured
    - ``disk``: absolute UPLOAD_FOLDER (persistent volume)
    - ``r2_incomplete``: R2 credentials without R2_PUBLIC_URL (not publicly durable)
    - ``ephemeral``: default local path under the container (lost on redeploy)
    """
    if _r2_credentials_present() and _r2_public_url_present():
        return "r2"
    if _r2_credentials_present() and not _r2_public_url_present():
        return "r2_incomplete"
    if _persistent_upload_folder_configured():
        return "disk"
    return "ephemeral"


def validate_upload_persistence(env: str | None = None) -> None:
    """
    Fail fast in production when uploads would vanish on redeploy.

    Escape hatch: ALLOW_EPHEMERAL_UPLOADS=1 (emergency only; not for store launch).
    """
    env_name = (env or get_app_env()).strip().lower()
    if env_name in ("development", "testing", "test"):
        return
    if _env_flag("ALLOW_EPHEMERAL_UPLOADS"):
        return
    mode = upload_persistence_mode()
    if mode == "r2" or mode == "disk":
        return
    if mode == "r2_incomplete":
        raise RuntimeError(
            "R2 credentials are set but R2_PUBLIC_URL is missing. "
            "Set R2_PUBLIC_URL (e.g. https://pub-….r2.dev) so listing photos "
            "are publicly reachable after upload, or unset R2_* and use "
            "UPLOAD_FOLDER=/data/uploads on a persistent disk."
        )
    raise RuntimeError(
        "Production uploads would be ephemeral (lost on every Render/Docker redeploy). "
        "Configure Cloudflare R2 (R2_ACCOUNT_ID, R2_BUCKET_NAME, R2_ACCESS_KEY_ID, "
        "R2_SECRET_ACCESS_KEY, R2_PUBLIC_URL) or set UPLOAD_FOLDER to an absolute "
        "persistent path (e.g. /data/uploads). "
        "See kk/docs/UPLOAD_PERSISTENCE.md."
    )


def validate_chat_media_persistence(env: str | None = None) -> None:
    """
    Fail fast in production unless the PRIVATE chat-media R2 bucket (C-10)
    is fully configured.

    Chat media has no safe non-R2 fallback: the local-disk fallback used
    when R2_CHAT_* isn't set is served WITHOUT authentication (see the
    static-file route in kk/routes/misc.py), so anything less than a
    complete R2_CHAT_* configuration would leave new chat uploads publicly
    reachable in production — exactly what C-10 exists to prevent. Both a
    *partial* R2_CHAT_* configuration and a *fully absent* one are
    therefore rejected; only a fully-configured private bucket boots
    production.

    Escape hatch: ALLOW_EPHEMERAL_UPLOADS=1 (shared with the listing-media
    escape hatch; emergency only, not for store launch).
    """
    env_name = (env or get_app_env()).strip().lower()
    if env_name in ("development", "testing", "test"):
        return
    if _env_flag("ALLOW_EPHEMERAL_UPLOADS"):
        return
    mode = chat_media_storage_mode()
    if mode == "r2_private":
        return
    if mode == "r2_chat_incomplete":
        raise RuntimeError(
            "Chat-media R2 configuration is incomplete (C-10): "
            "R2_ACCOUNT_ID, R2_CHAT_BUCKET_NAME, R2_CHAT_ACCESS_KEY_ID, and "
            "R2_CHAT_SECRET_ACCESS_KEY must all be set together for private "
            "chat-media storage. A partial configuration would silently "
            "fall back to the unauthenticated local-disk path for new chat "
            "uploads."
        )
    # mode == "disk": no R2_CHAT_* configured at all.
    raise RuntimeError(
        "Chat-media R2 configuration is missing (C-10): R2_ACCOUNT_ID, "
        "R2_CHAT_BUCKET_NAME, R2_CHAT_ACCESS_KEY_ID, and "
        "R2_CHAT_SECRET_ACCESS_KEY must all be set in production for "
        "private chat-media storage. Without them, new chat uploads would "
        "silently fall back to the unauthenticated local-disk path — "
        "exactly what C-10 is designed to prevent."
    )


def validate_redis_required(env: str | None = None) -> None:
    """
    Fail fast in production when Redis is missing or unreachable.

    Shared Redis is required for correct rate limits (and useful for JWT
    blocklist / Socket.IO / Celery) across Gunicorn workers. Without it,
    each process keeps an in-memory limiter that attackers can bypass.

    Escape hatch: ALLOW_INMEMORY_RATE_LIMITS=1 (emergency only).
    """
    env_name = (env or get_app_env()).strip().lower()
    if env_name in ("development", "testing", "test"):
        return
    if _env_flag("ALLOW_INMEMORY_RATE_LIMITS"):
        return
    url = (os.environ.get("REDIS_URL") or "").strip()
    if not url:
        raise RuntimeError(
            "REDIS_URL is required in production for shared rate limiting across "
            "workers. Provision Redis (e.g. Render Key Value) and set REDIS_URL, "
            "or set ALLOW_INMEMORY_RATE_LIMITS=1 for an emergency-only escape hatch."
        )
    try:
        import redis  # type: ignore

        client = redis.Redis.from_url(
            url,
            socket_connect_timeout=3,
            socket_timeout=3,
            decode_responses=True,
        )
        if not client.ping():
            raise RuntimeError("PING returned falsy")
    except Exception as exc:
        raise RuntimeError(
            "REDIS_URL is set but Redis is unreachable (needed for production "
            f"rate limits). Check the URL / network / Redis service. Detail: {exc}"
        ) from exc


def _access_token_expires() -> timedelta:
    """
    Access JWT lifetime. Default 30 minutes (audit H-03: 15–60).

    Override with JWT_ACCESS_TOKEN_MINUTES (clamped to 15–60).
    """
    raw = (os.environ.get("JWT_ACCESS_TOKEN_MINUTES") or "30").strip()
    try:
        minutes = int(raw)
    except ValueError:
        minutes = 30
    minutes = max(15, min(60, minutes))
    return timedelta(minutes=minutes)


def _refresh_token_expires() -> timedelta:
    raw = (os.environ.get("JWT_REFRESH_TOKEN_DAYS") or "30").strip()
    try:
        days = int(raw)
    except ValueError:
        days = 30
    days = max(1, min(90, days))
    return timedelta(days=days)


class Config:
    # Basic Flask Configuration
    # In production, secrets are REQUIRED (validated via validate_required_secrets()).
    SECRET_KEY = os.environ.get("SECRET_KEY") or _DEV_SECRET_FALLBACK
    
    # Database Configuration
    SQLALCHEMY_DATABASE_URI = os.environ.get('DATABASE_URL') or 'sqlite:///car_listings.db'
    SQLALCHEMY_TRACK_MODIFICATIONS = False
    
    # PostgreSQL Configuration (if using PostgreSQL)
    POSTGRES_HOST = os.environ.get('POSTGRES_HOST', 'localhost')
    POSTGRES_PORT = os.environ.get('POSTGRES_PORT', '5432')
    POSTGRES_DB = os.environ.get('POSTGRES_DB', 'car_listings')
    POSTGRES_USER = os.environ.get('POSTGRES_USER', 'postgres')
    POSTGRES_PASSWORD = os.environ.get('POSTGRES_PASSWORD', '')
    
    # Auto-generate PostgreSQL URL if not provided
    if not os.environ.get('DATABASE_URL') and os.environ.get('USE_POSTGRES', '').lower() == 'true':
        SQLALCHEMY_DATABASE_URI = f'postgresql://{POSTGRES_USER}:{POSTGRES_PASSWORD}@{POSTGRES_HOST}:{POSTGRES_PORT}/{POSTGRES_DB}'
    
    # JWT Configuration
    JWT_SECRET_KEY = os.environ.get("JWT_SECRET_KEY") or _DEV_JWT_SECRET_FALLBACK
    # Short-lived access tokens (15–60 min); mobile/admin refresh rotate long-lived refresh tokens.
    JWT_ACCESS_TOKEN_EXPIRES = _access_token_expires()
    JWT_REFRESH_TOKEN_EXPIRES = _refresh_token_expires()
    JWT_BLACKLIST_ENABLED = True
    JWT_BLACKLIST_TOKEN_CHECKS = ['access', 'refresh']
    
    # File Upload Configuration
    UPLOAD_FOLDER = 'static/uploads'
    MAX_CONTENT_LENGTH = int(
        os.environ.get('MAX_CONTENT_LENGTH') or 250 * 1024 * 1024
    )  # 250MB default, overridable via env
    ALLOWED_EXTENSIONS = {'png', 'jpg', 'jpeg', 'gif', 'webp', 'heic', 'heif'}
    ALLOWED_VIDEO_EXTENSIONS = {'mp4', 'mov', 'avi', 'mkv', 'webm'}
    
    # Email Configuration
    MAIL_SERVER = os.environ.get('MAIL_SERVER') or 'smtp.gmail.com'
    MAIL_PORT = int(os.environ.get('MAIL_PORT') or 587)
    MAIL_USE_TLS = os.environ.get('MAIL_USE_TLS', 'true').lower() in ['true', 'on', '1']
    MAIL_USERNAME = os.environ.get('MAIL_USERNAME')
    MAIL_PASSWORD = os.environ.get('MAIL_PASSWORD')
    MAIL_DEFAULT_SENDER = os.environ.get('MAIL_DEFAULT_SENDER')
    
    # Redis Configuration (for caching and sessions)
    REDIS_URL = os.environ.get('REDIS_URL') or 'redis://localhost:6379/0'
    
    # SocketIO Configuration
    SOCKETIO_ASYNC_MODE = 'threading'
    
    # Security Configuration
    BCRYPT_LOG_ROUNDS = 12
    PASSWORD_RESET_EXPIRY = 3600  # 1 hour
    
    # Pagination
    POSTS_PER_PAGE = 20
    MESSAGES_PER_PAGE = 50
    
    # File Storage (local + optional R2)
    AWS_ACCESS_KEY_ID = os.environ.get('AWS_ACCESS_KEY_ID')
    AWS_SECRET_ACCESS_KEY = os.environ.get('AWS_SECRET_ACCESS_KEY')
    AWS_BUCKET_NAME = os.environ.get('AWS_BUCKET_NAME')
    AWS_REGION = os.environ.get('AWS_REGION', 'us-east-1')
    # Cloudflare R2 (S3-compatible). When set, presigned upload is available.
    R2_ACCOUNT_ID = os.environ.get('R2_ACCOUNT_ID', '').strip()
    R2_ACCESS_KEY_ID = os.environ.get('R2_ACCESS_KEY_ID') or os.environ.get('AWS_ACCESS_KEY_ID')
    R2_SECRET_ACCESS_KEY = os.environ.get('R2_SECRET_ACCESS_KEY') or os.environ.get('AWS_SECRET_ACCESS_KEY')
    R2_BUCKET_NAME = os.environ.get('R2_BUCKET_NAME', '').strip()
    R2_PUBLIC_URL = (os.environ.get('R2_PUBLIC_URL') or '').strip()  # e.g. https://pub-xxx.r2.dev

    # Cloudflare R2 — PRIVATE chat-media bucket (C-10). Never a public URL.
    # Shares R2_ACCOUNT_ID with the listing-media bucket above; uses its own
    # bucket name + credentials so a scoped API token can be limited to only
    # this bucket. There is intentionally no R2_CHAT_PUBLIC_URL — chat objects
    # are only ever reachable via short-lived presigned GET URLs generated by
    # the backend after an authorization check (see Message.to_dict()).
    R2_CHAT_BUCKET_NAME = os.environ.get('R2_CHAT_BUCKET_NAME', '').strip()
    R2_CHAT_ACCESS_KEY_ID = os.environ.get('R2_CHAT_ACCESS_KEY_ID', '').strip()
    R2_CHAT_SECRET_ACCESS_KEY = os.environ.get('R2_CHAT_SECRET_ACCESS_KEY', '').strip()
    
    # Firebase Configuration (for push notifications)
    FIREBASE_SERVER_KEY = os.environ.get('FIREBASE_SERVER_KEY')
    FIREBASE_PROJECT_ID = os.environ.get('FIREBASE_PROJECT_ID')

class DevelopmentConfig(Config):
    DEBUG = True
    # Use instance folder explicitly to avoid stale root DBs and ensure correct schema
    SQLALCHEMY_DATABASE_URI = os.environ.get('DEV_DATABASE_URL') or 'sqlite:///instance/car_listings_dev.db'

class ProductionConfig(Config):
    DEBUG = False
    SQLALCHEMY_DATABASE_URI = os.environ.get('DATABASE_URL') or 'sqlite:///car_listings.db'

class TestingConfig(Config):
    TESTING = True
    SQLALCHEMY_DATABASE_URI = 'sqlite:///:memory:'
    WTF_CSRF_ENABLED = False

config = {
    'development': DevelopmentConfig,
    'production': ProductionConfig,
    'testing': TestingConfig,
    'default': ProductionConfig
}
