"""
WSGI entrypoint for production servers (gunicorn/uwsgi).
Do not call eventlet.monkey_patch() here. Default production setup is
gthread + Socket.IO threading (see gunicorn.conf.py / app_factory).
Eventlet is not supported (Gunicorn >= 26 removed its worker).
"""
from __future__ import annotations

from .app_factory import create_app

# gunicorn "kk.wsgi:app"
app, _socketio, _jwt, _migrate, _mail = create_app()

