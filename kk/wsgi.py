"""
WSGI entrypoint for production servers (gunicorn/uwsgi).
Do not call eventlet.monkey_patch() here: with gthread/sync worker it breaks
gunicorn's main loop. Eventlet worker is only used when REDIS_URL is set (see
gunicorn.conf.py); use sync/gthread on Render when Redis is not configured.
"""
from __future__ import annotations

from .app_factory import create_app

# gunicorn "kk.wsgi:app"
app, _socketio, _jwt, _migrate, _mail = create_app()

