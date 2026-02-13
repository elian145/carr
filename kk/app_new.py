"""
DEPRECATED (kept for local dev compatibility)

This project used to register most API routes directly in this module.
All canonical API routes now live in blueprints under `kk/routes/` and are
registered via `kk/app_factory.py`.

Production entrypoints:
- WSGI: `kk.wsgi:app` (Gunicorn / uWSGI)
- ASGI/WebSocket: run Socket.IO using this module only in development.
"""

from __future__ import annotations

import os

# Dev runner default: if user didn't set APP_ENV, assume development so local runs
# don't accidentally boot in "production" and crash due to missing secrets.
os.environ.setdefault("APP_ENV", "development")

from .app_factory import create_app
from .config import get_app_env

app, socketio, _jwt, _migrate, _mail = create_app()


def _port() -> int:
    try:
        # Keep legacy local dev default for proxy/start scripts.
        return int(os.environ.get("PORT") or "5000")
    except Exception:
        return 5000


if __name__ == "__main__":
    # SECURITY: prevent accidental production runs of this dev runner.
    if get_app_env() == "production":
        raise RuntimeError("Do not run `kk.app_new` in production. Use `kk.wsgi:app`.")

    socketio.run(
        app,
        host=os.environ.get("HOST") or "0.0.0.0",
        port=_port(),
        debug=(os.environ.get("FLASK_DEBUG") or "").strip().lower() in ("1", "true", "yes", "on"),
        allow_unsafe_werkzeug=True,
    )

