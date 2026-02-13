from .auth import bp as auth_bp
from .analytics import bp as analytics_bp
from .ai import bp as ai_bp
from .admin import bp as admin_bp
from .cars import bp as cars_bp
from .chat import bp as chat_bp
from .favorites import bp as favorites_bp
from .jobs import bp as jobs_bp
from .media import bp as media_bp
from .user import bp as user_bp
from .misc import bp as misc_bp


def register_blueprints(app) -> None:
    app.register_blueprint(auth_bp)
    app.register_blueprint(analytics_bp)
    app.register_blueprint(ai_bp)
    app.register_blueprint(admin_bp)
    app.register_blueprint(cars_bp)
    app.register_blueprint(chat_bp)
    app.register_blueprint(favorites_bp)
    app.register_blueprint(jobs_bp)
    app.register_blueprint(media_bp)
    app.register_blueprint(user_bp)
    app.register_blueprint(misc_bp)

