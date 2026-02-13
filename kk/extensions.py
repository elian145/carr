from __future__ import annotations

from flask_mail import Mail
from flask_migrate import Migrate
from flask_jwt_extended import JWTManager
from flask_socketio import SocketIO

# SQLAlchemy db is defined in `kk/models.py` to keep models and metadata together.
# Import it from there rather than redefining.
from .models import db

migrate = Migrate()
jwt = JWTManager()
mail = Mail()

# SocketIO can be initialized with `init_app`.
#
# NOTE: do not hardcode `async_mode` here. We select it at `init_app()` time
# based on env/config so dev works without extra deps and production can use
# eventlet/gevent when configured.
socketio = SocketIO()

