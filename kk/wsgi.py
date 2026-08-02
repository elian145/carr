"""
WSGI entrypoint for production servers (gunicorn/uwsgi).
Do not call eventlet.monkey_patch() here: that must run before other imports
(gunicorn's eventlet/gevent worker does it). Default production setup is
gthread + Socket.IO threading. Opt into eventlet only with SOCKETIO_ASYNC_MODE
and a Redis message queue (see gunicorn.conf.py).
"""
from __future__ import annotations

from .app_factory import create_app

# gunicorn "kk.wsgi:app"
app, _socketio, _jwt, _migrate, _mail = create_app()

