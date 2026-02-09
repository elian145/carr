import os
from datetime import timedelta
from dotenv import load_dotenv

load_dotenv()

def get_app_env() -> str:
    """
    Determine the runtime environment.

    Preferred: APP_ENV=development|production|testing
    Fallbacks: FLASK_ENV (legacy), then development.
    """
    env = (os.environ.get('APP_ENV') or os.environ.get('FLASK_ENV') or 'development').strip().lower()
    return env or 'development'

def validate_required_secrets(env: str | None = None) -> None:
    """
    Fail fast in production if critical secrets are missing.
    """
    env_name = (env or get_app_env()).strip().lower()
    if env_name != 'production':
        return
    missing: list[str] = []
    for key in ('SECRET_KEY', 'JWT_SECRET_KEY'):
        if not (os.environ.get(key) or '').strip():
            missing.append(key)
    if missing:
        raise RuntimeError(
            "Missing required environment variables for production: "
            + ", ".join(missing)
            + ". Set them (and restart) before running with APP_ENV=production."
        )

class Config:
    # Basic Flask Configuration
    # In production, secrets are REQUIRED (validated via validate_required_secrets()).
    SECRET_KEY = os.environ.get('SECRET_KEY') or 'dev-only-insecure-secret'
    
    # Database Configuration
    SQLALCHEMY_DATABASE_URI = os.environ.get('DATABASE_URL') or 'sqlite:///car_listings.db'
    SQLALCHEMY_TRACK_MODIFICATIONS = False
    
    # PostgreSQL Configuration (if using PostgreSQL)
    POSTGRES_HOST = os.environ.get('POSTGRES_HOST', 'localhost')
    POSTGRES_PORT = os.environ.get('POSTGRES_PORT', '5432')
    POSTGRES_DB = os.environ.get('POSTGRES_DB', 'car_listings')
    POSTGRES_USER = os.environ.get('POSTGRES_USER', 'postgres')
    POSTGRES_PASSWORD = os.environ.get('POSTGRES_PASSWORD', '')
    
    # Auto-generate PostgreSQL URL if not provided
    if not os.environ.get('DATABASE_URL') and os.environ.get('USE_POSTGRES', '').lower() == 'true':
        SQLALCHEMY_DATABASE_URI = f'postgresql://{POSTGRES_USER}:{POSTGRES_PASSWORD}@{POSTGRES_HOST}:{POSTGRES_PORT}/{POSTGRES_DB}'
    
    # JWT Configuration
    JWT_SECRET_KEY = os.environ.get('JWT_SECRET_KEY') or 'dev-only-insecure-jwt-secret'
    JWT_ACCESS_TOKEN_EXPIRES = timedelta(hours=24)
    JWT_REFRESH_TOKEN_EXPIRES = timedelta(days=30)
    JWT_BLACKLIST_ENABLED = True
    JWT_BLACKLIST_TOKEN_CHECKS = ['access', 'refresh']
    
    # File Upload Configuration
    UPLOAD_FOLDER = 'static/uploads'
    MAX_CONTENT_LENGTH = 100 * 1024 * 1024  # 100MB
    ALLOWED_EXTENSIONS = {'png', 'jpg', 'jpeg', 'gif', 'webp', 'heic', 'heif'}
    ALLOWED_VIDEO_EXTENSIONS = {'mp4', 'mov', 'avi', 'mkv', 'webm'}
    
    # Email Configuration
    MAIL_SERVER = os.environ.get('MAIL_SERVER') or 'smtp.gmail.com'
    MAIL_PORT = int(os.environ.get('MAIL_PORT') or 587)
    MAIL_USE_TLS = os.environ.get('MAIL_USE_TLS', 'true').lower() in ['true', 'on', '1']
    MAIL_USERNAME = os.environ.get('MAIL_USERNAME')
    MAIL_PASSWORD = os.environ.get('MAIL_PASSWORD')
    MAIL_DEFAULT_SENDER = os.environ.get('MAIL_DEFAULT_SENDER')
    
    # Redis Configuration (for caching and sessions)
    REDIS_URL = os.environ.get('REDIS_URL') or 'redis://localhost:6379/0'
    
    # SocketIO Configuration
    SOCKETIO_ASYNC_MODE = 'threading'
    
    # Security Configuration
    BCRYPT_LOG_ROUNDS = 12
    PASSWORD_RESET_EXPIRY = 3600  # 1 hour
    
    # Pagination
    POSTS_PER_PAGE = 20
    MESSAGES_PER_PAGE = 50
    
    # File Storage
    AWS_ACCESS_KEY_ID = os.environ.get('AWS_ACCESS_KEY_ID')
    AWS_SECRET_ACCESS_KEY = os.environ.get('AWS_SECRET_ACCESS_KEY')
    AWS_BUCKET_NAME = os.environ.get('AWS_BUCKET_NAME')
    AWS_REGION = os.environ.get('AWS_REGION', 'us-east-1')
    
    # Firebase Configuration (for push notifications)
    FIREBASE_SERVER_KEY = os.environ.get('FIREBASE_SERVER_KEY')
    FIREBASE_PROJECT_ID = os.environ.get('FIREBASE_PROJECT_ID')

class DevelopmentConfig(Config):
    DEBUG = True
    # Use instance folder explicitly to avoid stale root DBs and ensure correct schema
    SQLALCHEMY_DATABASE_URI = os.environ.get('DEV_DATABASE_URL') or 'sqlite:///instance/car_listings_dev.db'

class ProductionConfig(Config):
    DEBUG = False
    SQLALCHEMY_DATABASE_URI = os.environ.get('DATABASE_URL') or 'sqlite:///car_listings.db'

class TestingConfig(Config):
    TESTING = True
    SQLALCHEMY_DATABASE_URI = 'sqlite:///:memory:'
    WTF_CSRF_ENABLED = False

config = {
    'development': DevelopmentConfig,
    'production': ProductionConfig,
    'testing': TestingConfig,
    'default': DevelopmentConfig
}
