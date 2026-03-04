"""
Legacy entrypoint wrapper.

Archived implementation lives in `kk/legacy/api.py`.
Prefer `kk/app_new.py` for the canonical backend.
"""

import os

from .config import get_app_env

# SECURITY: never allow the legacy backend API module in production.
env = get_app_env()
if env == "production":
    raise RuntimeError(
        "Refusing to import legacy API module in production. "
        "Use `kk/app_new.py` (canonical) or the blueprint-based app factory instead."
    )

# Explicit opt-in for local development only.
allow = (os.environ.get("ALLOW_LEGACY_BACKEND") or "").strip().lower() in ("1", "true", "yes", "on")
if not allow:
    raise RuntimeError(
        "Legacy API import is disabled by default. "
        "If you truly need it for local/dev only, set ALLOW_LEGACY_BACKEND=true and APP_ENV=development."
    )

from .legacy.api import *  # noqa: F401,F403,E402

