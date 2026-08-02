"""
WSGI entrypoint for production servers (gunicorn/uwsgi).
Do not call eventlet.monkey_patch() here. Default production setup is
gthread + Socket.IO threading (see gunicorn.conf.py / app_factory).
Eventlet requires SOCKETIO_ALLOW_EVENTLET=1 and is not recommended.
"""
from __future__ import annotations

from .app_factory import create_app

# gunicorn "kk.wsgi:app"
app, _socketio, _jwt, _migrate, _mail = create_app()

