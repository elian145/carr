"""
Retired legacy entrypoint.

Use `kk.wsgi:app` / `kk.app_factory.create_app()` instead.
"""

raise RuntimeError(
    "kk.app_legacy is retired. Use `kk.wsgi:app` (Gunicorn) or "
    "`python -m kk.app_new` for local development."
)
