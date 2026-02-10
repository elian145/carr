from .auth import bp as auth_bp
from .favorites import bp as favorites_bp
from .user import bp as user_bp
from .misc import bp as misc_bp


def register_blueprints(app) -> None:
    app.register_blueprint(auth_bp)
    app.register_blueprint(favorites_bp)
    app.register_blueprint(user_bp)
    app.register_blueprint(misc_bp)

