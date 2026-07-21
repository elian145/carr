"""
Retired legacy API entrypoint.

Use `kk.wsgi:app` / `kk.app_factory.create_app()` instead.
"""

raise RuntimeError(
    "kk.api is retired. Use `kk.wsgi:app` (Gunicorn) or "
    "`python -m kk.app_new` for local development."
)
