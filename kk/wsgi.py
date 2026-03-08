"""
WSGI entrypoint for production servers (gunicorn/uwsgi).
When using eventlet worker, monkey_patch() must run before any other imports.
"""
from __future__ import annotations

import os
if os.environ.get("SOCKETIO_ASYNC_MODE", "").strip().lower() == "eventlet":
    import eventlet
    eventlet.monkey_patch()

from .app_factory import create_app

# gunicorn "kk.wsgi:app"
app, _socketio, _jwt, _migrate, _mail = create_app()

