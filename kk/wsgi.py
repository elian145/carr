"""
WSGI entrypoint for production servers (gunicorn/uwsgi).

This entrypoint uses the canonical Flask application factory.
"""

from __future__ import annotations

from .app_factory import create_app

# gunicorn "kk.wsgi:app"
app, _socketio, _jwt, _migrate, _mail = create_app()

