"""
Retired legacy entrypoint.

Production and development must use `kk.wsgi:app` / `kk.app_factory.create_app()`.
The old monolith under `kk/legacy/` was removed (H-11); see `kk/legacy/README.md`.
"""

raise RuntimeError(
    "kk.app is retired. Use `kk.wsgi:app` (Gunicorn) or "
    "`python -m kk.app_new` for local development."
)
