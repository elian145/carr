from __future__ import annotations

import os
import re
from dotenv import load_dotenv
from flask import Flask
from flask_cors import CORS
from werkzeug.middleware.proxy_fix import ProxyFix

from .config import config, get_app_env, validate_required_secrets
from .extensions import db, jwt, mail, migrate, socketio
from .legacy_schema import ensure_minimal_schema_compat
from .logging_utils import configure_logging, install_api_error_handlers, install_request_id_and_access_log
from .monitoring import init_monitoring
from .routes import register_blueprints
from .routes.auth import init_jwt_callbacks
from .socketio_handlers import register_socketio_handlers


def _parse_cors_origins() -> list[str]:
    raw = (os.environ.get("CORS_ORIGINS") or "").strip()
    if not raw:
        return []
    return [o.strip() for o in raw.split(",") if o.strip()]

def _socketio_async_mode(env_name: str) -> str | None:
    """
    Socket.IO async mode selection.

    - Dev default: threading (no extra deps)
    - Production: eventlet if available (best for many concurrent sockets)

    Override with:
    - SOCKETIO_ASYNC_MODE=eventlet|gevent|threading
    """
    raw = (os.environ.get("SOCKETIO_ASYNC_MODE") or "").strip().lower()
    if raw:
        return raw
    if env_name == "production":
        return "eventlet"
    return "threading"

def _socketio_message_queue_url(env_name: str) -> str | None:
    """
    Return a Redis URL to use as Socket.IO message queue in production,
    or None to disable.

    Multiple Gunicorn workers require a message queue for broadcasts to
    reach all clients.
    """
    raw = (os.environ.get("SOCKETIO_MESSAGE_QUEUE") or "").strip()
    if raw:
        return raw
    if env_name == "production":
        # Default to REDIS_URL in production when present.
        r = (os.environ.get("REDIS_URL") or "").strip()
        return r or None
    return None


def _detect_worker_count() -> int | None:
    """
    Best-effort detection of a multi-worker server.

    This is used only for emitting warnings about Socket.IO scaling when no message queue is configured.
    """
    for key in ("WEB_CONCURRENCY", "GUNICORN_WORKERS", "WORKERS"):
        raw = (os.environ.get(key) or "").strip()
        if not raw:
            continue
        try:
            n = int(raw)
            return n if n > 0 else None
        except Exception:
            continue

    cmd = (os.environ.get("GUNICORN_CMD_ARGS") or "").strip()
    if cmd:
        m = re.search(r"(?:--workers|-w)\s+(\d+)", cmd)
        if m:
            try:
                n = int(m.group(1))
                return n if n > 0 else None
            except Exception:
                return None
    return None


def create_app():
    app = Flask(__name__)

    load_dotenv()
    try:
        load_dotenv(os.path.join(os.path.dirname(__file__), "env.local"), override=False)  # type: ignore
    except Exception:
        pass

    env_name = get_app_env()
    app.config.from_object(config.get(env_name, config["development"]))
    validate_required_secrets(env_name)

    configure_logging(app)
    install_request_id_and_access_log(app)
    install_api_error_handlers(app)
    init_monitoring(app)

    # Production hygiene warnings (do not block startup).
    if env_name == "production":
        if not (os.environ.get("REDIS_URL") or "").strip():
            app.logger.warning(
                "REDIS_URL is not set. For best production reliability (rate limits, "
                "token revocation coordination, Socket.IO multi-worker broadcasts, Celery), "
                "configure Redis and set REDIS_URL."
            )
        if not (os.environ.get("CORS_ORIGINS") or "").strip():
            app.logger.info(
                "CORS_ORIGINS is not set. This is fine for mobile-only clients, "
                "but browser clients will be blocked by CORS unless you set an allowlist."
            )

    # DB selection
    #
    # Best-state principle:
    # - Production: explicit DATABASE_URL (Postgres recommended)
    # - Development: deterministic sqlite path under repo-root /instance
    # - Legacy sqlite (kk/instance/cars.db): only when explicitly enabled
    database_url = (os.getenv("DATABASE_URL") or "").strip()
    env_db = (os.getenv("DB_PATH") or "").strip()

    repo_root = os.path.abspath(os.path.join(app.root_path, ".."))
    canonical_dev_db = os.path.join(repo_root, "instance", "car_listings_dev.db")
    legacy_cars_db = os.path.join(app.root_path, "instance", "cars.db")

    db_path = None
    using_legacy_db = False

    if database_url:
        # Honor explicit DB URL (Postgres, etc.)
        app.config["SQLALCHEMY_DATABASE_URI"] = database_url
    elif env_db:
        db_path = env_db
    elif env_name in ("development", "testing"):
        # Only use legacy DB when explicitly requested.
        use_legacy = (os.getenv("USE_LEGACY_CARS_DB") or "").strip().lower() in ("1", "true", "yes", "on")
        if use_legacy and os.path.isfile(legacy_cars_db):
            db_path = legacy_cars_db
            using_legacy_db = True
        else:
            db_path = canonical_dev_db
    else:
        # Non-dev environments: keep whatever Config selected (usually DATABASE_URL or sqlite:///car_listings.db).
        # If it's sqlite, it may be relative; leave it unchanged here.
        db_path = None

    if not database_url and db_path:
        os.makedirs(os.path.dirname(db_path), exist_ok=True)
        app.config["SQLALCHEMY_DATABASE_URI"] = f"sqlite:///{db_path}"

    db.init_app(app)
    migrate.init_app(app, db)
    jwt.init_app(app)
    mail.init_app(app)

    cors_origins = _parse_cors_origins()
    sio_mq = _socketio_message_queue_url(env_name)
    sio_async = _socketio_async_mode(env_name)
    if env_name == "production":
        # When running behind a reverse proxy (Cloudflare/Nginx/etc), trust one hop of
        # X-Forwarded-* so URL generation, request.remote_addr, and scheme work correctly.
        # Configure your proxy to overwrite these headers.
        app.wsgi_app = ProxyFix(app.wsgi_app, x_for=1, x_proto=1, x_host=1, x_port=1, x_prefix=1)  # type: ignore
        socketio.init_app(
            app,
            cors_allowed_origins=cors_origins,
            message_queue=sio_mq,
            async_mode=sio_async,
        )
        if not sio_mq:
            workers = _detect_worker_count()
            if workers and workers > 1:
                app.logger.warning(
                    "Socket.IO message queue is not configured, but multiple workers detected (workers=%s). "
                    "Realtime broadcasts and room state will NOT work correctly across workers. "
                    "Set SOCKETIO_MESSAGE_QUEUE=redis://... (or REDIS_URL) before scaling workers.",
                    workers,
                )
        if cors_origins:
            CORS(app, origins=cors_origins)
    else:
        socketio.init_app(
            app,
            cors_allowed_origins=cors_origins or "*",
            message_queue=sio_mq,
            async_mode=sio_async,
        )
        CORS(app, origins=cors_origins or "*")

    # If the SQLite DB file is brand new, it has no tables and the API will 500.
    # In development/testing, auto-create tables to make local boot reliable.
    # In production, require migrations to be applied explicitly.
    try:
        with app.app_context():
            from sqlalchemy import inspect
            from flask import current_app
            import sys

            insp = inspect(db.engine)
            has_user = insp.has_table("user")
            has_car = insp.has_table("car")
            has_alembic_version = insp.has_table("alembic_version")
            auto_migrate = (os.getenv("AUTO_MIGRATE") or "1").strip().lower() not in ("0", "false", "no", "off")
            # Avoid re-entrant migrations when the developer is explicitly running `flask db ...`.
            argv = [a.lower() for a in sys.argv if isinstance(a, str)]
            running_flask_db_cmd = any(a.endswith("flask") or a.endswith("flask.exe") for a in argv[:1]) and "db" in argv[1:3]
            if running_flask_db_cmd:
                auto_migrate = False

            alembic_version_set = False
            if has_alembic_version:
                try:
                    from sqlalchemy import text

                    with db.engine.connect() as conn:
                        row = conn.execute(text("SELECT version_num FROM alembic_version LIMIT 1")).fetchone()
                        alembic_version_set = bool(row and row[0])
                except Exception:
                    alembic_version_set = False

            if not (has_user and has_car):
                if env_name in ("development", "testing"):
                    if auto_migrate:
                        try:
                            from flask_migrate import upgrade as fm_upgrade

                            fm_upgrade()
                        except Exception:
                            # Fallback for dev if migrations are misconfigured.
                            db.create_all()
                    else:
                        db.create_all()
                else:
                    raise RuntimeError(
                        "Database schema is not initialized (missing core tables). "
                        "Run migrations (flask db upgrade) before starting with APP_ENV=production."
                    )
            else:
                # If tables exist but alembic isn't tracking versions yet, baseline to the last
                # known revision so we can apply the latest hardening migrations in dev.
                if env_name in ("development", "testing") and auto_migrate:
                    try:
                        from flask_migrate import stamp as fm_stamp, upgrade as fm_upgrade

                        if (not has_alembic_version) or (not alembic_version_set):
                            # Baseline to the revision right before our latest hardening migration.
                            fm_stamp(revision="7c9a1d2f4a0b")
                        fm_upgrade()
                    except Exception:
                        # Never brick local dev due to migration issues.
                        current_app.logger.exception("auto_migrate failed (dev-only)")
    except Exception:
        # Do not prevent startup in dev if something went wrong; requests will surface errors.
        if env_name == "production":
            raise

    # Minimal schema compatibility for legacy DBs (SQLite-only).
    # In development/testing with SQLite, always run so existing DBs get missing
    # columns (views_count, password_hash, etc.) and keep local testing working.
    uri = (app.config.get("SQLALCHEMY_DATABASE_URI") or "").strip().lower()
    use_compat = (
        using_legacy_db
        or (os.getenv("ENABLE_LEGACY_SCHEMA_COMPAT") or "").strip().lower() in ("1", "true", "yes", "on")
        or (env_name in ("development", "testing") and "sqlite" in uri)
    )
    if use_compat:
        ensure_minimal_schema_compat(app, db)

    # Create upload directories under kk/static/uploads/...
    app.config["UPLOAD_FOLDER"] = os.path.join(app.root_path, "static", "uploads")
    os.makedirs(os.path.join(app.config["UPLOAD_FOLDER"], "car_photos"), exist_ok=True)
    os.makedirs(os.path.join(app.config["UPLOAD_FOLDER"], "car_videos"), exist_ok=True)
    os.makedirs(os.path.join(app.config["UPLOAD_FOLDER"], "profile_pictures"), exist_ok=True)

    init_jwt_callbacks(jwt)
    register_blueprints(app)
    register_socketio_handlers(socketio)

    @app.after_request
    def _security_headers(response):
        # Minimal safe headers for APIs and static content.
        try:
            response.headers.setdefault("X-Content-Type-Options", "nosniff")
            response.headers.setdefault("X-Frame-Options", "DENY")
            response.headers.setdefault("Referrer-Policy", "no-referrer")
            response.headers.setdefault("Permissions-Policy", "geolocation=(), microphone=(), camera=()")
            if env_name == "production":
                # Only meaningful over HTTPS; safe to set in prod behind TLS termination.
                response.headers.setdefault(
                    "Strict-Transport-Security",
                    "max-age=31536000; includeSubDomains",
                )
        except Exception:
            pass
        return response

    return app, socketio, jwt, migrate, mail

