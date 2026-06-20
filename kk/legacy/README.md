# Legacy backend (do not use in production)

This directory contains the pre-factory Flask monolith (`app.py`, ~3000 lines).

**Production must use** `kk/app_factory.py` via `kk.wsgi:app` or `create_app()`.

The legacy module contains insecure development defaults (hardcoded secrets, demo seed routes). It is kept for reference and guarded from loading when `APP_ENV=production`.
