"""
Legacy entrypoint wrapper.

The canonical backend is `kk/app_new.py`. This module remains to avoid breaking
older imports/scripts; it forwards to the legacy implementation archived under
`kk/legacy/app.py`.
"""

import os

from .config import get_app_env

# SECURITY: never allow the legacy backend in production.
env = get_app_env()
if env == "production":
    raise RuntimeError(
        "Refusing to import legacy backend in production. "
        "Use `kk/app_new.py` (canonical) or `kk/app_factory.create_app()` instead."
    )

# Explicit opt-in for local development only.
allow = (os.environ.get("ALLOW_LEGACY_BACKEND") or "").strip().lower() in ("1", "true", "yes", "on")
if not allow:
    raise RuntimeError(
        "Legacy backend import is disabled by default. "
        "If you truly need it for local/dev only, set ALLOW_LEGACY_BACKEND=true and APP_ENV=development."
    )

from .legacy.app import *  # noqa: F401,F403,E402

