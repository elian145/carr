from __future__ import annotations

import os
from dotenv import load_dotenv
from flask import Flask
from flask_cors import CORS

from .config import config, get_app_env, validate_required_secrets
from .extensions import db, jwt, mail, migrate, socketio
from .legacy_schema import ensure_minimal_schema_compat
from .routes import register_blueprints
from .routes.auth import init_jwt_callbacks


def _parse_cors_origins() -> list[str]:
    raw = (os.environ.get("CORS_ORIGINS") or "").strip()
    if not raw:
        return []
    return [o.strip() for o in raw.split(",") if o.strip()]


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

    # Respect DATABASE_URL for production-scale deployments (Postgres, etc.)
    database_url = (os.getenv("DATABASE_URL") or "").strip()
    env_db = (os.getenv("DB_PATH") or "").strip()
    kk_cars_db = os.path.join(app.root_path, "instance", "cars.db")
    root_level_db = os.path.abspath(os.path.join(app.root_path, "..", "instance", "car_listings_dev.db"))
    kk_level_db = os.path.join(app.root_path, "instance", "car_listings_dev.db")

    if database_url:
        app.config["SQLALCHEMY_DATABASE_URI"] = database_url
    elif env_db:
        db_path = env_db
    elif os.path.isfile(kk_cars_db):
        db_path = kk_cars_db
    elif os.path.isfile(root_level_db):
        db_path = root_level_db
    else:
        db_path = kk_level_db

    if not database_url:
        os.makedirs(os.path.dirname(db_path), exist_ok=True)
        app.config["SQLALCHEMY_DATABASE_URI"] = f"sqlite:///{db_path}"

    db.init_app(app)
    migrate.init_app(app, db)
    jwt.init_app(app)
    mail.init_app(app)

    cors_origins = _parse_cors_origins()
    if env_name == "production":
        socketio.init_app(app, cors_allowed_origins=cors_origins)
        if cors_origins:
            CORS(app, origins=cors_origins)
    else:
        socketio.init_app(app, cors_allowed_origins=cors_origins or "*")
        CORS(app, origins=cors_origins or "*")

    # Minimal schema compatibility for legacy DBs (SQLite-only)
    ensure_minimal_schema_compat(app, db)

    # Create upload directories under kk/static/uploads/...
    app.config["UPLOAD_FOLDER"] = os.path.join(app.root_path, "static", "uploads")
    os.makedirs(os.path.join(app.config["UPLOAD_FOLDER"], "car_photos"), exist_ok=True)
    os.makedirs(os.path.join(app.config["UPLOAD_FOLDER"], "car_videos"), exist_ok=True)
    os.makedirs(os.path.join(app.config["UPLOAD_FOLDER"], "profile_pictures"), exist_ok=True)

    init_jwt_callbacks(jwt)
    register_blueprints(app)

    return app, socketio, jwt, migrate, mail

