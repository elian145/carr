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
socketio = SocketIO(async_mode="threading")

