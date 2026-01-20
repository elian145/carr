from flask import Flask, request, jsonify, send_from_directory, render_template, url_for
from flask_sqlalchemy import SQLAlchemy
from flask_migrate import Migrate
from flask_jwt_extended import JWTManager, create_access_token, create_refresh_token, jwt_required, get_jwt_identity, get_jwt
from flask_cors import CORS
from flask_mail import Mail, Message
from flask_socketio import SocketIO, emit, join_room, leave_room
from werkzeug.utils import secure_filename
from .config import config
from .models import *
from .auth import *
from .security import rate_limit, validate_input_sanitization, secure_headers
import pathlib
import os
import json
import logging
import requests
from datetime import datetime, timedelta
import base64
import secrets
from functools import wraps
import time
import hashlib
import threading
from dotenv import load_dotenv

# Initialize Flask app
app = Flask(__name__)
load_dotenv()  # Load environment variables from .env if present
# Also load optional env.local next to the kk app
try:
    load_dotenv(os.path.join(os.path.dirname(__file__), 'env.local'), override=False)  # type: ignore
except Exception:
    pass
app.config.from_object(config['development'])
# Prefer explicit DB via env, else root-level instance, else kk/instance
env_db = (os.getenv('DB_PATH') or '').strip()
kk_cars_db = os.path.join(app.root_path, 'instance', 'cars.db')
root_level_db = os.path.abspath(os.path.join(app.root_path, '..', 'instance', 'car_listings_dev.db'))
kk_level_db = os.path.join(app.root_path, 'instance', 'car_listings_dev.db')
if env_db:
	db_path = env_db
elif os.path.isfile(kk_cars_db):
	# Prefer populated kk/instance/cars.db if present
	db_path = kk_cars_db
elif os.path.isfile(root_level_db):
	db_path = root_level_db
else:
	db_path = kk_level_db
os.makedirs(os.path.dirname(db_path), exist_ok=True)
app.config['SQLALCHEMY_DATABASE_URI'] = f"sqlite:///{db_path}"

# Initialize extensions
db.init_app(app)
migrate = Migrate(app, db)
jwt = JWTManager(app)
mail = Mail(app)
socketio = SocketIO(app, cors_allowed_origins="*", async_mode='threading')
CORS(app)

# Ensure minimal schema compatibility for legacy SQLite DBs (SQLite-only)
try:
	with app.app_context():
		from sqlalchemy import text
		conn = db.engine.connect()
		def _cols(table: str):
			return {row[1] for row in conn.execute(text(f'PRAGMA table_info({table})'))}
		try:
			car_cols = _cols('car')
			def _add_car(col: str, typ: str):
				if col not in car_cols:
					conn.execute(text(f'ALTER TABLE car ADD COLUMN {col} {typ}'))
					car_cols.add(col)
			# Fields required by the current models/API
			_add_car('public_id', 'VARCHAR(50)')
			_add_car('seller_id', 'INTEGER')
			# Core descriptive fields
			for col, typ in (
				('brand', 'TEXT'),
				('model', 'TEXT'),
				('year', 'INTEGER DEFAULT 0'),
				('mileage', 'INTEGER DEFAULT 0'),
				('engine_type', 'TEXT'),
				('transmission', 'TEXT'),
				('drive_type', 'TEXT'),
				('condition', 'TEXT'),
				('body_type', 'TEXT'),
				('status', "TEXT DEFAULT 'active'"),
			):
				_add_car(col, typ)
			# Pricing and location
			for col, typ in (
				('price', 'FLOAT DEFAULT 0'),
				('currency', "TEXT DEFAULT 'USD'"),
				('location', 'TEXT'),
				('seating', 'INTEGER DEFAULT 5'),
				('latitude', 'FLOAT'),
				('longitude', 'FLOAT'),
			):
				_add_car(col, typ)
			# Additional details
			for col, typ in (
				('description', 'TEXT'),
				('color', 'TEXT'),
				('fuel_economy', 'TEXT'),
				('vin', 'TEXT'),
			):
				_add_car(col, typ)
			# Status/meta
			for col, typ in (
				('is_active', 'BOOLEAN DEFAULT 1'),
				('is_featured', 'BOOLEAN DEFAULT 0'),
				('views_count', 'INTEGER DEFAULT 0'),
				('created_at', 'DATETIME'),
				('updated_at', 'DATETIME'),
			):
				_add_car(col, typ)
			_add_car('title', 'TEXT DEFAULT ""')
			_add_car('title_status', "TEXT DEFAULT 'active'")
			_add_car('trim', "TEXT DEFAULT 'base'")
			_add_car('fuel_type', "TEXT DEFAULT 'gasoline'")
			# AI fields (no-op if already added)
			for col, typ in (
				('ai_analyzed','BOOLEAN DEFAULT 0'),
				('ai_detected_brand','VARCHAR(50)'),
				('ai_detected_model','VARCHAR(50)'),
				('ai_detected_color','VARCHAR(20)'),
				('ai_detected_body_type','VARCHAR(20)'),
				('ai_detected_condition','VARCHAR(20)'),
				('ai_confidence_score','FLOAT'),
				('ai_analysis_timestamp','DATETIME'),
				('license_plates_blurred','BOOLEAN DEFAULT 0'),
			):
				_add_car(col, typ)
			conn.commit()
			# Ensure seller_id is populated (fallback to first user or create demo)
			if 'seller_id' in car_cols:
				has_null = conn.execute(text("SELECT EXISTS(SELECT 1 FROM car WHERE seller_id IS NULL)")).fetchone()[0]
				if has_null:
					# Get a user id or create one
					row = conn.execute(text("SELECT id FROM user LIMIT 1")).fetchone()
					uid = row[0] if row else None
					if uid is None:
						# Create minimal user row
						conn.execute(text("INSERT INTO user (username, password, phone_number, first_name, last_name, is_active, created_at, updated_at) VALUES ('demo','password','07000000003','Demo','User',1,datetime('now'),datetime('now'))"))
						uid = conn.execute(text("SELECT id FROM user ORDER BY id DESC LIMIT 1")).fetchone()[0]
					conn.execute(text("UPDATE car SET seller_id=:uid WHERE seller_id IS NULL"), {'uid': uid})
					conn.commit()
			# User table legacy columns
			user_cols = _cols('user')
			if 'password' not in user_cols:
				conn.execute(text('ALTER TABLE user ADD COLUMN password TEXT'))
				user_cols.add('password')
			if 'password_hash' not in user_cols:
				conn.execute(text('ALTER TABLE user ADD COLUMN password_hash TEXT'))
				user_cols.add('password_hash')
			if 'public_id' not in user_cols:
				conn.execute(text('ALTER TABLE user ADD COLUMN public_id VARCHAR(50)'))
				user_cols.add('public_id')
			conn.commit()
			# Car image table columns
			ci_cols = _cols('car_image')
			def _add_ci(col: str, typ: str):
				if col not in ci_cols:
					conn.execute(text(f'ALTER TABLE car_image ADD COLUMN {col} {typ}'))
					ci_cols.add(col)
			for col, typ in (
				('is_primary', 'BOOLEAN DEFAULT 0'),
				('"order"', 'INTEGER DEFAULT 0'),
				('created_at', 'DATETIME'),
			):
				_add_ci(col, typ)
			conn.commit()
			# Car video table columns
			cv_cols = _cols('car_video')
			def _add_cv(col: str, typ: str):
				if col not in cv_cols:
					conn.execute(text(f'ALTER TABLE car_video ADD COLUMN {col} {typ}'))
					cv_cols.add(col)
			for col, typ in (
				('thumbnail_url', 'TEXT'),
				('duration', 'INTEGER'),
				('"order"', 'INTEGER DEFAULT 0'),
				('created_at', 'DATETIME'),
			):
				_add_cv(col, typ)
			conn.commit()
		finally:
			conn.close()
except Exception:
	# Best-effort; do not block app startup
	pass
# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Create upload directories
# Always resolve uploads under the kk app root so files land in kk/static/uploads/...
app.config['UPLOAD_FOLDER'] = os.path.join(app.root_path, 'static', 'uploads')
os.makedirs(os.path.join(app.config['UPLOAD_FOLDER'], 'car_photos'), exist_ok=True)
os.makedirs(os.path.join(app.config['UPLOAD_FOLDER'], 'car_videos'), exist_ok=True)
os.makedirs(os.path.join(app.config['UPLOAD_FOLDER'], 'profile_pictures'), exist_ok=True)

# -------- Watermarkly Blur API integration (single source of truth) --------
# Notes:
# - API key is read from env var WATERMARKLY_API_KEY (trial or live works the same).
# - We POST raw bytes with Content-Type: application/octet-stream (no multipart).
# - Region failover: try EU first, fallback to US.
# - Rate-limit: if 429, sleep briefly (0.1s) and retry once.
# - Deduplication: in-memory cache by SHA-256 of input to avoid paying twice for identical images.
# - Place for future monthly quota enforcement is marked below.
WATERMARKLY_EU = "https://blur-api-eu1.watermarkly.com/blur/"
WATERMARKLY_US = "https://blur-api-us1.watermarkly.com/blur/"
_recent_cache_lock = threading.Lock()
_recent_cache = {}  # sha256 -> {'ts': unix_time, 'bytes': blurred_bytes, 'content_type': str}
_recent_cache_max = 200
_recent_cache_ttl_seconds = 60 * 60  # 1 hour window for dedupe

def _prune_recent_cache() -> None:
    now = time.time()
    to_del = []
    for k, v in list(_recent_cache.items()):
        if (now - v.get('ts', 0)) > _recent_cache_ttl_seconds:
            to_del.append(k)
    for k in to_del:
        _recent_cache.pop(k, None)
    # Trim if too large
    if len(_recent_cache) > _recent_cache_max:
        # remove oldest entries
        items = sorted(_recent_cache.items(), key=lambda kv: kv[1].get('ts', 0))
        for k, _ in items[: max(0, len(_recent_cache) - _recent_cache_max)]:
            _recent_cache.pop(k, None)

def _watermarkly_blur_bytes(img_bytes: bytes) -> tuple:
    """
    Send image bytes to Watermarkly Blur API. Returns (blurred_bytes, content_type).
    Raises RuntimeError on failure.
    """
    api_key = (os.getenv("WATERMARKLY_API_KEY") or "").strip()
    if not api_key:
        # DEV fallback: locally blur a plate-like region if no API key is configured.
        # This helps during emulator testing without external dependencies.
        try:
            from io import BytesIO
            try:
                from PIL import Image, ImageFilter  # type: ignore
            except Exception as e:
                raise RuntimeError("WATERMARKLY_API_KEY is not configured and Pillow is not installed") from e

            img = Image.open(BytesIO(img_bytes)).convert("RGB")
            w, h = img.size
            # Heuristic plate box: centered, bottom 20% area, 60% width
            box_w = int(max(60, w * 0.6))
            box_h = int(max(30, h * 0.18))
            left = max(0, (w - box_w) // 2)
            top = max(0, int(h * 0.72))
            right = min(w, left + box_w)
            bottom = min(h, top + box_h)

            region = img.crop((left, top, right, bottom)).filter(ImageFilter.GaussianBlur(radius=18))
            img.paste(region, (left, top))

            out = BytesIO()
            img.save(out, format="JPEG", quality=90)
            return out.getvalue(), "image/jpeg"
        except Exception as e:
            raise RuntimeError("Local blur fallback failed and WATERMARKLY_API_KEY is not configured") from e

    headers = {
        "x-api-key": api_key,
        "Content-Type": "application/octet-stream",
    }

    def _try(url: str) -> requests.Response:
        r = requests.post(url, headers=headers, data=img_bytes, timeout=90)
        if r.status_code == 429:
            time.sleep(0.1)
            r = requests.post(url, headers=headers, data=img_bytes, timeout=90)
        return r

    # Try EU, then US
    r = None
    try:
        r = _try(WATERMARKLY_EU)
        if r.status_code >= 500 or r.status_code in (403,):
            # Hard failures: fallback to US
            r = _try(WATERMARKLY_US)
    except Exception:
        # Network error: try US
        r = _try(WATERMARKLY_US)

    # If key invalid/forbidden, fall back to local blur in dev so uploads still work
    if r is not None and r.status_code == 403:
        try:
            from io import BytesIO  # type: ignore
            from PIL import Image, ImageFilter  # type: ignore
            img = Image.open(BytesIO(img_bytes)).convert("RGB")
            w, h = img.size
            box_w = int(max(60, w * 0.6))
            box_h = int(max(30, h * 0.18))
            left = max(0, (w - box_w) // 2)
            top = max(0, int(h * 0.72))
            right = min(w, left + box_w)
            bottom = min(h, top + box_h)
            region = img.crop((left, top, right, bottom)).filter(ImageFilter.GaussianBlur(radius=18))
            img.paste(region, (left, top))
            out = BytesIO()
            img.save(out, format="JPEG", quality=90)
            return out.getvalue(), "image/jpeg"
        except Exception:
            # if local fallback fails, fall through to error handling below
            pass

    if not r or r.status_code != 200 or not r.content:
        msg = None
        try:
            msg = r.json().get("message") if r is not None else None
        except Exception:
            msg = (r.text[:300] if (r is not None and hasattr(r, "text")) else None)
        raise RuntimeError(f"Watermarkly blur failed ({getattr(r,'status_code', 'no_status')}): {msg or 'no details'}")

    ct = (r.headers.get("Content-Type") or "").split(";", 1)[0].strip() or "image/jpeg"
    return r.content, ct

def _get_sha256(data: bytes) -> str:
    h = hashlib.sha256()
    h.update(data)
    return h.hexdigest()

# ------------------------------ Public endpoint ------------------------------
@app.route('/api/blur-license-plate', methods=['POST'])
def blur_license_plate_endpoint():
    """
    Accepts multipart/form-data image (field: 'image' preferred; also accepts 'file'/'upload').
    Returns blurred image as binary with appropriate content-type.

    This endpoint NEVER calls Watermarkly from the client; only server-to-server.
    """
    try:
        # Accept common field names
        fs = None
        for key in ('image', 'file', 'upload', 'photo'):
            if key in request.files:
                fs = request.files.get(key)
                break
        if not fs or not fs.filename:
            return jsonify({"error": "No image uploaded. Use form field 'image'."}), 400

        img_bytes = fs.read()
        if not img_bytes:
            return jsonify({"error": "Empty upload"}), 400

        # Monthly quota placeholder: enforce limits here.
        # Example: check a persistent counter keyed by YYYY-MM and user/account ID.
        # If over limit, return 429 with a clear message.
        # def check_monthly_quota(user_id) -> bool: ...
        # if not check_monthly_quota(current_user_id): return 429

        # Deduplication: return cached response if we have seen this exact image recently
        digest = _get_sha256(img_bytes)
        with _recent_cache_lock:
            _prune_recent_cache()
            cached = _recent_cache.get(digest)
        if cached and cached.get('bytes'):
            resp = app.response_class(cached['bytes'])
            resp.headers['Content-Type'] = cached.get('content_type') or 'image/jpeg'
            return resp, 200

        # Call Watermarkly
        blurred, content_type = _watermarkly_blur_bytes(img_bytes)

        # Cache result for dedupe
        with _recent_cache_lock:
            _recent_cache[digest] = {'ts': time.time(), 'bytes': blurred, 'content_type': content_type}
            _prune_recent_cache()

        resp = app.response_class(blurred)
        resp.headers['Content-Type'] = content_type
        return resp, 200
    except RuntimeError as e:
        logger.error(f"/api/blur-license-plate runtime error: {e}")
        # Map common upstream errors to client-friendly codes
        msg = str(e)
        if "429" in msg or "rate limit" in msg.lower():
            return jsonify({"error": "rate_limited", "message": msg}), 429
        if "403" in msg:
            return jsonify({"error": "forbidden", "message": msg}), 403
        return jsonify({"error": "processing_failed", "message": msg}), 502
    except Exception as e:
        logger.exception(f"/api/blur-license-plate error: {e}")
        return jsonify({"error": "internal_error"}), 500

# JWT error handlers
@jwt.expired_token_loader
def expired_token_callback(jwt_header, jwt_payload):
    return jsonify({'message': 'Token has expired'}), 401

@jwt.invalid_token_loader
def invalid_token_callback(error):
    return jsonify({'message': 'Invalid token'}), 401

@jwt.unauthorized_loader
def missing_token_callback(error):
    return jsonify({'message': 'Authorization token is required'}), 401

# JWT Blacklist callbacks
@jwt.token_in_blocklist_loader
def check_if_token_revoked(jwt_header, jwt_payload):
    """Check if token is blacklisted"""
    jti = jwt_payload['jti']
    token = TokenBlacklist.query.filter_by(jti=jti).first()
    return token is not None

@jwt.revoked_token_loader
def revoked_token_callback(jwt_header, jwt_payload):
    return jsonify({'message': 'Token has been revoked'}), 401

# Authentication Routes
@app.route('/api/auth/register', methods=['POST'])
@rate_limit(max_requests=5, window_minutes=60)  # 5 registrations per hour per IP
def register():
    """User registration endpoint"""
    try:
        data = request.get_json()
        
        # Sanitize input
        data = validate_input_sanitization(data)
        
        # Validate input
        errors = validate_user_input(data, ['username', 'phone_number', 'password', 'first_name', 'last_name'])
        if errors:
            return jsonify({'message': 'Validation failed', 'errors': errors}), 400
        
        # Check if user already exists
        if User.query.filter_by(username=data['username']).first():
            return jsonify({'message': 'Username already exists'}), 400
        
        if User.query.filter_by(phone_number=data['phone_number']).first():
            return jsonify({'message': 'Phone number already exists'}), 400
        
        # Create new user
        user = User(
            username=data['username'],
            phone_number=data['phone_number'],
            first_name=data['first_name'],
            last_name=data['last_name'],
            email=data.get('email')  # Email is now optional
        )
        user.set_password(data['password'])
        
        db.session.add(user)
        db.session.commit()
        
        # Log user action
        log_user_action(user, 'register')
        
        return jsonify({
            'message': 'User registered successfully.',
            'user': user.to_dict()
        }), 201
        
    except Exception as e:
        logger.error(f"Registration error: {str(e)}")
        return jsonify({'message': 'Registration failed'}), 500

@app.route('/api/auth/login', methods=['POST'])
@rate_limit(max_requests=10, window_minutes=15)  # 10 login attempts per 15 minutes per IP
def login():
    """User login endpoint"""
    try:
        data = request.get_json()
        
        if not data.get('username') or not data.get('password'):
            return jsonify({'message': 'Email/phone and password are required'}), 400
        
        # Find user by email or phone number only (no username)
        user = User.query.filter(
            (User.email == data['username']) | (User.phone_number == data['username'])
        ).first()
        
        if not user or not user.check_password(data['password']):
            return jsonify({'message': 'Invalid credentials'}), 401
        
        if not user.is_active:
            return jsonify({'message': 'Account is deactivated'}), 401
        
        # Ensure user has a public_id for JWT identity compatibility
        if not getattr(user, 'public_id', None):
            try:
                user.public_id = secrets.token_hex(8)
                db.session.commit()
            except Exception:
                db.session.rollback()
        
        # Update last login
        user.last_login = datetime.utcnow()
        db.session.commit()
        
        # Generate tokens (ensure non-null identity)
        try:
            identity = getattr(user, 'public_id', None)
            if not identity:
                identity = f"user:{user.id}"
            access_token = create_access_token(identity=identity)
            refresh_token = create_refresh_token(identity=identity)
        except Exception as e:
            logger.error(f"Token generation error: {e}")
            return jsonify({'message': 'Login failed'}), 500
        
        # Log user action
        log_user_action(user, 'login')
        
        return jsonify({
            'message': 'Login successful',
            'token': access_token,  # Use 'token' for mobile app compatibility
            'access_token': access_token,
            'refresh_token': refresh_token,
            'user': user.to_dict()
        }), 200
        
    except Exception as e:
        import traceback
        error_details = traceback.format_exc()
        logger.error(f"Login error: {str(e)}\n{error_details}")
        return jsonify({'message': 'Login failed', 'error': str(e)}), 500

@app.route('/api/auth/refresh', methods=['POST'])
@jwt_required(refresh=True)
def refresh():
    """Refresh access token"""
    try:
        current_user_id = get_jwt_identity()
        user = User.query.filter_by(public_id=current_user_id).first()
        
        if not user or not user.is_active:
            return jsonify({'message': 'User not found or inactive'}), 401
        
        new_access_token = create_access_token(identity=user.public_id)
        
        return jsonify({
            'access_token': new_access_token
        }), 200
        
    except Exception as e:
        logger.error(f"Token refresh error: {str(e)}")
        return jsonify({'message': 'Token refresh failed'}), 500

@app.route('/api/auth/logout', methods=['POST'])
@jwt_required()
def logout():
    """User logout endpoint"""
    try:
        current_user = get_current_user()
        if current_user:
            log_user_action(current_user, 'logout')
        
        # Blacklist the current token
        jti = get_jwt()['jti']
        token_type = get_jwt()['type']
        expires_at = datetime.fromtimestamp(get_jwt()['exp'])
        
        blacklisted_token = TokenBlacklist(
            jti=jti,
            token_type=token_type,
            user_id=current_user.id,
            expires_at=expires_at
        )
        
        db.session.add(blacklisted_token)
        db.session.commit()
        
        return jsonify({'message': 'Logout successful'}), 200
        
    except Exception as e:
        logger.error(f"Logout error: {str(e)}")
        return jsonify({'message': 'Logout failed'}), 500

@app.route('/api/auth/forgot-password', methods=['POST'])
def forgot_password():
    """Forgot password endpoint"""
    try:
        data = request.get_json()
        phone_number = data.get('phone_number')
        
        if not phone_number:
            return jsonify({'message': 'Phone number is required'}), 400
        
        user = User.query.filter_by(phone_number=phone_number).first()
        if not user:
            # Don't reveal if phone number exists
            return jsonify({'message': 'If the phone number exists, a reset code has been sent'}), 200
        
        # Create password reset token
        token = create_password_reset_token(user)
        
        # Send reset code via SMS
        from sms_service import send_password_reset_sms
        sms_sent = send_password_reset_sms(phone_number, token)
        
        if not sms_sent:
            logger.warning(f"Failed to send SMS to {phone_number}, but token created: {token}")
        
        return jsonify({'message': 'If the phone number exists, a reset code has been sent'}), 200
        
    except Exception as e:
        logger.error(f"Forgot password error: {str(e)}")
        return jsonify({'message': 'Password reset request failed'}), 500

@app.route('/api/auth/reset-password', methods=['POST'])
def reset_password():
    """Reset password endpoint"""
    try:
        data = request.get_json()
        token = data.get('token')
        new_password = data.get('password')
        
        if not token or not new_password:
            return jsonify({'message': 'Token and new password are required'}), 400
        
        # Validate password
        is_valid, message = validate_password(new_password)
        if not is_valid:
            return jsonify({'message': message}), 400
        
        # Verify token
        user, error = verify_password_reset_token(token)
        if not user:
            return jsonify({'message': error}), 400
        
        # Update password
        user.set_password(new_password)
        
        # Mark token as used
        reset_token = PasswordReset.query.filter_by(token=token).first()
        if reset_token:
            reset_token.is_used = True
        
        db.session.commit()
        
        # Log user action
        log_user_action(user, 'password_reset')
        
        return jsonify({'message': 'Password reset successful'}), 200
        
    except Exception as e:
        logger.error(f"Reset password error: {str(e)}")
        return jsonify({'message': 'Password reset failed'}), 500

@app.route('/api/auth/verify-phone', methods=['POST'])
def verify_phone():
    """Phone verification endpoint"""
    try:
        data = request.get_json()
        phone_number = data.get('phone_number')
        verification_code = data.get('verification_code')
        
        if not phone_number or not verification_code:
            return jsonify({'message': 'Phone number and verification code are required'}), 400
        
        # Find user by phone number
        user = User.query.filter_by(phone_number=phone_number).first()
        if not user:
            return jsonify({'message': 'User not found'}), 404
        
        # For now, accept any 6-digit code (in production, validate against stored code)
        if len(verification_code) == 6 and verification_code.isdigit():
            user.is_verified = True
            db.session.commit()
            
            # Log user action
            log_user_action(user, 'phone_verified')
            
            return jsonify({'message': 'Phone number verified successfully'}), 200
        else:
            return jsonify({'message': 'Invalid verification code'}), 400
        
    except Exception as e:
        logger.error(f"Phone verification error: {str(e)}")
        return jsonify({'message': 'Phone verification failed'}), 500

@app.route('/api/auth/send-verification', methods=['POST'])
def send_phone_verification():
    """Send phone verification code"""
    try:
        data = request.get_json()
        phone_number = data.get('phone_number')
        
        if not phone_number:
            return jsonify({'message': 'Phone number is required'}), 400
        
        # Find user by phone number
        user = User.query.filter_by(phone_number=phone_number).first()
        if not user:
            return jsonify({'message': 'User not found'}), 404
        
        # Generate verification code (6 digits)
        import random
        verification_code = str(random.randint(100000, 999999))
        
        # Send verification code via SMS
        from sms_service import send_verification_sms
        sms_sent = send_verification_sms(phone_number, verification_code)
        
        if not sms_sent:
            logger.warning(f"Failed to send verification SMS to {phone_number}")
            return jsonify({'message': 'Failed to send verification code'}), 500
        
        # Store verification code (in production, store in database with expiration)
        # For now, just log it
        logger.info(f"Verification code for {phone_number}: {verification_code}")
        
        return jsonify({'message': 'Verification code sent successfully'}), 200
        
    except Exception as e:
        logger.error(f"Send verification error: {str(e)}")
        return jsonify({'message': 'Failed to send verification code'}), 500

# User Profile Routes
@app.route('/api/user/profile', methods=['GET'])
@jwt_required()
def get_profile():
    """Get user profile"""
    try:
        current_user = get_current_user()
        if not current_user:
            return jsonify({'message': 'User not found'}), 404
        
        return jsonify({
            'user': current_user.to_dict(include_private=True)
        }), 200
        
    except Exception as e:
        logger.error(f"Get profile error: {str(e)}")
        return jsonify({'message': 'Failed to get profile'}), 500

@app.route('/api/user/profile', methods=['PUT'])
@jwt_required()
def update_profile():
    """Update user profile"""
    try:
        current_user = get_current_user()
        if not current_user:
            return jsonify({'message': 'User not found'}), 404
        
        data = request.get_json()
        
        # Validate input
        errors = validate_user_input(data)
        if errors:
            return jsonify({'message': 'Validation failed', 'errors': errors}), 400
        
        # Update fields
        if 'first_name' in data:
            current_user.first_name = data['first_name']
        if 'last_name' in data:
            current_user.last_name = data['last_name']
        if 'phone_number' in data:
            current_user.phone_number = data['phone_number']
        if 'email' in data and data['email'] != current_user.email:
            # Check if email is already taken
            if User.query.filter_by(email=data['email']).first():
                return jsonify({'message': 'Email already exists'}), 400
            current_user.email = data['email']
            current_user.is_verified = False  # Require re-verification
        
        current_user.updated_at = datetime.utcnow()
        db.session.commit()
        
        # Log user action
        log_user_action(current_user, 'profile_update')
        
        return jsonify({
            'message': 'Profile updated successfully',
            'user': current_user.to_dict(include_private=True)
        }), 200
        
    except Exception as e:
        logger.error(f"Update profile error: {str(e)}")
        return jsonify({'message': 'Failed to update profile'}), 500

@app.route('/api/user/upload-profile-picture', methods=['POST'])
@jwt_required()
def upload_profile_picture():
    """Upload profile picture"""
    try:
        current_user = get_current_user()
        if not current_user:
            return jsonify({'message': 'User not found'}), 404
        
        if 'file' not in request.files:
            return jsonify({'message': 'No file provided'}), 400
        
        file = request.files['file']
        
        # Validate file
        is_valid, message = validate_file_upload(
            file, 
            max_size_mb=5, 
            allowed_extensions=app.config['ALLOWED_EXTENSIONS']
        )
        
        if not is_valid:
            return jsonify({'message': message}), 400
        
        # Generate secure filename
        filename = generate_secure_filename(file.filename)
        file_path = os.path.join(app.config['UPLOAD_FOLDER'], 'profile_pictures', filename)
        
        # Save file
        file.save(file_path)
        
        # Update user profile picture
        current_user.profile_picture = f"uploads/profile_pictures/{filename}"
        current_user.updated_at = datetime.utcnow()
        db.session.commit()
        
        # Log user action
        log_user_action(current_user, 'profile_picture_upload')
        
        return jsonify({
            'message': 'Profile picture uploaded successfully',
            'profile_picture': current_user.profile_picture
        }), 200
        
    except Exception as e:
        logger.error(f"Upload profile picture error: {str(e)}")
        return jsonify({'message': 'Failed to upload profile picture'}), 500

# Car Listing Routes
@app.route('/api/cars', methods=['GET'])
def get_cars():
    """Get all cars with filtering and pagination"""
    try:
        page = request.args.get('page', 1, type=int)
        per_page = request.args.get('per_page', 20, type=int)
        
        # Filtering parameters
        brand = request.args.get('brand')
        model = request.args.get('model')
        year_min = request.args.get('year_min', type=int)
        year_max = request.args.get('year_max', type=int)
        price_min = request.args.get('price_min', type=float)
        price_max = request.args.get('price_max', type=float)
        location = request.args.get('location')
        condition = request.args.get('condition')
        body_type = request.args.get('body_type')
        transmission = request.args.get('transmission')
        drive_type = request.args.get('drive_type')
        engine_type = request.args.get('engine_type')
        
        # Build query
        query = Car.query.filter_by(is_active=True)
        
        if brand:
            query = query.filter(Car.brand.ilike(f'%{brand}%'))
        if model:
            query = query.filter(Car.model.ilike(f'%{model}%'))
        if year_min:
            query = query.filter(Car.year >= year_min)
        if year_max:
            query = query.filter(Car.year <= year_max)
        if price_min:
            query = query.filter(Car.price >= price_min)
        if price_max:
            query = query.filter(Car.price <= price_max)
        if location:
            query = query.filter(Car.location.ilike(f'%{location}%'))
        if condition:
            query = query.filter(Car.condition == condition)
        if body_type:
            query = query.filter(Car.body_type == body_type)
        if transmission:
            query = query.filter(Car.transmission == transmission)
        if drive_type:
            query = query.filter(Car.drive_type == drive_type)
        if engine_type:
            query = query.filter(Car.engine_type == engine_type)
        
        # Order by featured first, then by creation date
        query = query.order_by(Car.is_featured.desc(), Car.created_at.desc())
        
        # Paginate
        pagination = query.paginate(
            page=page, 
            per_page=per_page, 
            error_out=False
        )
        
        # Include compatibility fields expected by the mobile client:
        # - image_url: primary image relative path
        # - images: list of relative paths
        cars = []
        static_root = os.path.join(app.root_path, 'static')
        def _exists(rel: str) -> bool:
            try:
                if not rel:
                    return False
                p = os.path.join(static_root, rel.lstrip('/')).replace('\\', '/')
                return os.path.isfile(p)
            except Exception:
                return False
        def _resolve(rel: str) -> str:
            """
            Resolve stored image path to an existing file.
            If DB stored 'uploads/<name>', try 'uploads/car_photos/<name>' as a fallback.
            """
            try:
                if not rel:
                    return ''
                norm = rel.lstrip('/').replace('\\', '/')
                if _exists(norm):
                    return norm
                base = os.path.basename(norm)
                alt = os.path.join('uploads', 'car_photos', base).replace('\\', '/')
                if _exists(alt):
                    return alt
                return ''
            except Exception:
                return ''
        for c in pagination.items:
            d = c.to_dict()
            raw_list = [img.image_url for img in c.images] if c.images else []
            # Keep only files that actually exist under static/ (with fallback resolution)
            image_list = [r for r in (_resolve(rel) for rel in raw_list) if r]
            primary_rel = image_list[0] if image_list else ''
            # Fallback to placeholder if nothing exists
            if not primary_rel and not image_list and _exists('uploads/car_photos/placeholder.jpg'):
                primary_rel = 'uploads/car_photos/placeholder.jpg'
            d['image_url'] = primary_rel
            d['images'] = image_list
            cars.append(d)
        
        return jsonify({
            'cars': cars,
            'pagination': {
                'page': page,
                'per_page': per_page,
                'total': pagination.total,
                'pages': pagination.pages,
                'has_next': pagination.has_next,
                'has_prev': pagination.has_prev
            }
        }), 200
        
    except Exception as e:
        logger.error(f"Get cars error: {str(e)}")
        return jsonify({'message': 'Failed to get cars', 'error': str(e)}), 500

# Alias routes compatible with older mobile client expectations
@app.route('/cars', methods=['GET'])
def get_cars_alias():
    """Compatibility alias: returns a bare list of cars, and supports ?id=<public_id>."""
    try:
        car_id = request.args.get('id')
        if car_id:
            car = None
            try:
                # Accept numeric database id
                if car_id.isdigit():
                    car = Car.query.filter_by(id=int(car_id), is_active=True).first()
            except Exception:
                pass
            if car is None:
                # Fallback to public_id
                car = Car.query.filter_by(public_id=car_id, is_active=True).first()
            if not car:
                return jsonify({'message': 'Car not found'}), 404
            # Match client expectation: return a single object with image_url/images/videos fields
            d = car.to_dict()
            # Ensure numeric id for mobile client
            d['id'] = car.id
            static_root = os.path.join(app.root_path, 'static')
            def _exists(rel: str) -> bool:
                try:
                    if not rel:
                        return False
                    p = os.path.join(static_root, rel.lstrip('/')).replace('\\', '/')
                    return os.path.isfile(p)
                except Exception:
                    return False
            def _resolve(rel: str) -> str:
                try:
                    if not rel:
                        return ''
                    norm = rel.lstrip('/').replace('\\', '/')
                    if _exists(norm):
                        return norm
                    base = os.path.basename(norm)
                    alt = os.path.join('uploads', 'car_photos', base).replace('\\', '/')
                    if _exists(alt):
                        return alt
                    return ''
                except Exception:
                    return ''
            image_list = [r for r in (_resolve(img.image_url) for img in car.images) if r] if car.images else []
            primary_rel = image_list[0] if image_list else ('uploads/car_photos/placeholder.jpg' if _exists('uploads/car_photos/placeholder.jpg') else '')
            d['image_url'] = primary_rel
            d['images'] = image_list
            d['videos'] = [v.video_url for v in car.videos] if car.videos else []
            if not d.get('title'):
                d['title'] = f"{(car.brand or '').title()} {(car.model or '').title()} {car.year or ''}".strip()
            return jsonify(d), 200

        # Mirror filters from /api/cars
        page = request.args.get('page', 1, type=int)
        per_page = request.args.get('per_page', 20, type=int)
        brand = request.args.get('brand')
        model = request.args.get('model')
        year_min = request.args.get('year_min', type=int)
        year_max = request.args.get('year_max', type=int)
        price_min = request.args.get('price_min', type=float)
        price_max = request.args.get('price_max', type=float)
        location = request.args.get('location')
        condition = request.args.get('condition')
        body_type = request.args.get('body_type')
        transmission = request.args.get('transmission')
        drive_type = request.args.get('drive_type')
        engine_type = request.args.get('engine_type')

        query = Car.query.filter_by(is_active=True)
        if brand:
            query = query.filter(Car.brand.ilike(f'%{brand}%'))
        if model:
            query = query.filter(Car.model.ilike(f'%{model}%'))
        if year_min:
            query = query.filter(Car.year >= year_min)
        if year_max:
            query = query.filter(Car.year <= year_max)
        if price_min:
            query = query.filter(Car.price >= price_min)
        if price_max:
            query = query.filter(Car.price <= price_max)
        if location:
            query = query.filter(Car.location.ilike(f'%{location}%'))
        if condition:
            query = query.filter(Car.condition == condition)
        if body_type:
            query = query.filter(Car.body_type == body_type)
        if transmission:
            query = query.filter(Car.transmission == transmission)
        if drive_type:
            query = query.filter(Car.drive_type == drive_type)
        if engine_type:
            query = query.filter(Car.engine_type == engine_type)

        query = query.order_by(Car.is_featured.desc(), Car.created_at.desc())
        pagination = query.paginate(page=page, per_page=per_page, error_out=False)
        cars = []
        for c in pagination.items:
            d = c.to_dict()
            # Ensure numeric id for mobile client
            d['id'] = c.id
            # Compute compatibility fields expected by mobile client
            static_root = os.path.join(app.root_path, 'static')
            def _exists(rel: str) -> bool:
                try:
                    if not rel:
                        return False
                    p = os.path.join(static_root, rel.lstrip('/')).replace('\\', '/')
                    return os.path.isfile(p)
                except Exception:
                    return False
            def _resolve(rel: str) -> str:
                try:
                    if not rel:
                        return ''
                    norm = rel.lstrip('/').replace('\\', '/')
                    if _exists(norm):
                        return norm
                    base = os.path.basename(norm)
                    alt = os.path.join('uploads', 'car_photos', base).replace('\\', '/')
                    if _exists(alt):
                        return alt
                    return ''
                except Exception:
                    return ''
            image_list = [r for r in (_resolve(img.image_url) for img in c.images) if r] if c.images else []
            primary_rel = image_list[0] if image_list else ('uploads/car_photos/placeholder.jpg' if _exists('uploads/car_photos/placeholder.jpg') else '')
            d['image_url'] = primary_rel  # relative path only
            d['images'] = image_list      # list of relative paths
            d['videos'] = [v.video_url for v in c.videos] if c.videos else []
            # Provide a title if missing
            if not d.get('title'):
                d['title'] = f"{(c.brand or '').title()} {(c.model or '').title()} {c.year or ''}".strip()
            cars.append(d)
        # Return bare list as expected by client
        return jsonify(cars), 200
    except Exception as e:
        logger.error(f"Get cars alias error: {str(e)}")
        return jsonify({'message': 'Failed to get cars', 'error': str(e)}), 500

# Compatibility auth endpoints for the mobile client
@app.route('/api/auth/send_otp', methods=['POST'])
def compat_send_otp():
    try:
        data = request.get_json(silent=True) or {}
        phone = data.get('phone') or data.get('phone_number') or ''
        # In development, return a fixed code
        return jsonify({'dev_code': '000000', 'phone': phone}), 200
    except Exception:
        return jsonify({'dev_code': '000000'}), 200

@app.route('/api/auth/signup', methods=['POST'])
def compat_signup():
    try:
        data = request.get_json(silent=True) or {}
        logger.info(f"Signup request: {data}")
        
        raw_username = (data.get('username') or '').strip()
        raw_phone = (data.get('phone') or data.get('phone_number') or '').strip()
        email = (data.get('email') or '').strip()
        password = (data.get('password') or '').strip()
        first_name = (data.get('first_name') or 'User').strip()
        last_name = (data.get('last_name') or 'Demo').strip()
        
        # Normalize phone to digits only (keep last 11 if country code included)
        phone_digits = ''.join(ch for ch in raw_phone if ch.isdigit())
        if len(phone_digits) > 11:
            phone_digits = phone_digits[-11:]
        # Choose username preferring email, then provided, then phone
        username = (email or raw_username or phone_digits or f"user_{secrets.token_hex(3)}").lower()
        if not phone_digits:
            phone_digits = f"070{secrets.randbelow(10**8):08d}"
        if not password:
            password = 'password123'

        logger.info(f"Processing signup: username={username}, phone={phone_digits}, email={email}")

        # If a user exists by email/username/phone, upsert: ensure password and fields, then return 200
        from sqlalchemy import or_
        filters = [User.username == username]
        if email:
            filters.append(User.email == email)
        filters.append(User.phone_number == phone_digits)
        existing = User.query.filter(or_(*filters)).first()
        if existing:
            logger.info(f"Existing user found, updating: {existing.username}")
            if password:
                existing.set_password(password)
            # Update fields if missing
            if email and not existing.email:
                existing.email = email
            if first_name and not existing.first_name:
                existing.first_name = first_name
            if last_name and not existing.last_name:
                existing.last_name = last_name
            existing.is_active = True
            db.session.commit()
            return jsonify({'message': 'Signup successful', 'user': existing.to_dict()}), 200

        # Create fresh user
        logger.info(f"Creating new user: {username}")
        user = User(
            username=username,
            phone_number=phone_digits,
            first_name=first_name,
            last_name=last_name,
            email=email if email else '',
            is_active=True,
        )
        user.set_password(password)
        # Keep old password field updated for backward compatibility
        user.password = password  
        db.session.add(user)
        db.session.commit()
        logger.info(f"User created successfully: {user.public_id}")
        return jsonify({'message': 'Signup successful', 'user': user.to_dict()}), 201
    except Exception as e:
        import traceback
        error_details = traceback.format_exc()
        logger.error(f"Compat signup error: {str(e)}\n{error_details}")
        db.session.rollback()
        # Return user-friendly error messages
        error_str = str(e)
        if 'UNIQUE constraint failed: user.email' in error_str or 'UNIQUE constraint failed: user.username' in error_str:
            return jsonify({'message': 'Email or username already exists'}), 400
        elif 'UNIQUE constraint failed: user.phone_number' in error_str:
            return jsonify({'message': 'Phone number already exists'}), 400
        else:
            return jsonify({'message': 'Signup failed. Please try again.'}), 500


# Development seed endpoint
@app.route('/dev/seed', methods=['POST', 'GET'])
def dev_seed():
    if not app.config.get('DEBUG', False):
        return jsonify({'message': 'Not available'}), 404
    try:
        # Ensure a demo user exists
        user = User.query.filter_by(username='demo').first()
        if not user:
            user = User(
                username='demo',
                phone_number='07000000000',
                first_name='Demo',
                last_name='User',
                email=None,
            )
            user.set_password('password123')
            db.session.add(user)
            db.session.commit()

        # Pick a few images from static uploads
        photos_dir = os.path.join('kk', 'static', 'uploads', 'car_photos')
        if not os.path.isdir(photos_dir):
            photos_dir = os.path.join('static', 'uploads', 'car_photos')
        image_files = []
        try:
            for name in os.listdir(photos_dir):
                if name.lower().endswith(('.jpg', '.jpeg', '.png', '.webp')):
                    image_files.append(name)
        except Exception:
            pass
        image_files = sorted(image_files)[:8]

        # Create a few sample cars if table is empty
        created = 0
        total_before = db.session.query(Car).count()
        if total_before == 0:
            samples = [
                {
                    'brand': 'bmw', 'model': '3 series', 'year': 2019, 'mileage': 45000,
                    'engine_type': 'gasoline', 'transmission': 'automatic', 'drive_type': 'rwd',
                    'condition': 'used', 'body_type': 'sedan', 'price': 21000.0, 'location': 'baghdad'
                },
                {
                    'brand': 'toyota', 'model': 'camry', 'year': 2021, 'mileage': 30000,
                    'engine_type': 'gasoline', 'transmission': 'automatic', 'drive_type': 'fwd',
                    'condition': 'used', 'body_type': 'sedan', 'price': 24000.0, 'location': 'erbil'
                },
                {
                    'brand': 'mercedes-benz', 'model': 'c-class', 'year': 2020, 'mileage': 22000,
                    'engine_type': 'gasoline', 'transmission': 'automatic', 'drive_type': 'rwd',
                    'condition': 'used', 'body_type': 'sedan', 'price': 32000.0, 'location': 'basra'
                }
            ]
            for s in samples:
                car = Car(
                    seller_id=user.id,
                    brand=s['brand'], model=s['model'], year=s['year'], mileage=s['mileage'],
                    engine_type=s['engine_type'], transmission=s['transmission'], drive_type=s['drive_type'],
                    condition=s['condition'], body_type=s['body_type'], price=s['price'], location=s['location']
                )
                db.session.add(car)
                db.session.flush()
                # attach up to 3 images
                rels = image_files[:3] if image_files else []
                order = 0
                for fname in rels:
                    # Store under uploads/ so client URL builder and server existence checks align
                    db.session.add(CarImage(
                        car_id=car.id,
                        image_url=f'uploads/car_photos/{fname}',
                        is_primary=(order == 0),
                        order=order
                    ))
                    order += 1
                created += 1
            db.session.commit()

        # Ensure cars have images: attach up to 3 images to cars missing images
        attached = 0
        if image_files:
            try:
                cars = Car.query.order_by(Car.created_at.asc()).all()
                for car in cars:
                    try:
                        if not getattr(car, 'images', None) or len(car.images) == 0:
                            order = 0
                            for fname in image_files[:3]:
                                db.session.add(CarImage(
                                    car_id=car.id,
                                    image_url=f'uploads/car_photos/{fname}',
                                    is_primary=(order == 0),
                                    order=order
                                ))
                                order += 1
                            attached += order
                    except Exception:
                        continue
                db.session.commit()
            except Exception:
                db.session.rollback()

        total = db.session.query(Car).count()
        return jsonify({'message': 'seed_ok', 'created': created, 'images_attached': attached, 'total': total}), 200
    except Exception as e:
        logger.error(f"Dev seed error: {str(e)}")
        db.session.rollback()
        return jsonify({'message': 'seed_failed'}), 500

@app.route('/api/cars/<car_id>', methods=['GET'])
def get_car(car_id):
    """Get single car by ID"""
    try:
        # Accept either public_id (UUID string) or numeric database id
        car = Car.query.filter_by(public_id=car_id, is_active=True).first()
        if not car and car_id.isdigit():
            car = Car.query.filter_by(id=int(car_id), is_active=True).first()
        if not car:
            return jsonify({'message': 'Car not found'}), 404
        
        # Increment view count
        car.increment_views()
        
        # Log view action if user is authenticated
        current_user = get_current_user()
        if current_user:
            log_user_action(current_user, 'view_listing', 'car', car.public_id)
        
        # Normalize response for mobile client compatibility
        car_dict = car.to_dict()
        # Attach primary and image list (relative paths under static/), filter to existing files
        static_root = os.path.join(app.root_path, 'static')
        def _exists(rel: str) -> bool:
            try:
                if not rel:
                    return False
                p = os.path.join(static_root, rel.lstrip('/')).replace('\\', '/')
                return os.path.isfile(p)
            except Exception:
                return False
        raw_list = [img.image_url for img in car.images] if car.images else []
        def _resolve(rel: str) -> str:
            try:
                if not rel:
                    return ''
                norm = rel.lstrip('/').replace('\\', '/')
                if _exists(norm):
                    return norm
                base = os.path.basename(norm)
                alt = os.path.join('uploads', 'car_photos', base).replace('\\', '/')
                if _exists(alt):
                    return alt
                return ''
            except Exception:
                return ''
        image_list = [r for r in (_resolve(rel) for rel in raw_list) if r]
        primary_rel = image_list[0] if image_list else ''
        if not primary_rel and _exists('uploads/car_photos/placeholder.jpg'):
            primary_rel = 'uploads/car_photos/placeholder.jpg'
        car_dict['image_url'] = primary_rel
        car_dict['images'] = image_list
        # Provide 'city' alias expected by the app (mapped from location)
        if not car_dict.get('city') and car_dict.get('location'):
            car_dict['city'] = car_dict['location']
        return jsonify({'car': car_dict}), 200
        
    except Exception as e:
        logger.error(f"Get car error: {str(e)}")
        return jsonify({'message': 'Failed to get car'}), 500

@app.route('/api/cars', methods=['POST'])
@jwt_required()
def create_car():
    """Create new car listing"""
    try:
        current_user = get_current_user()
        if not current_user:
            return jsonify({'message': 'User not found'}), 404

        raw = request.get_json(silent=True) or {}

        def _s(val, default=''):
            return (val if isinstance(val, str) else str(val or '')).strip() or default

        def _i(val, default=0):
            try:
                return int(val)
            except Exception:
                try:
                    return int(float(val))
                except Exception:
                    return default

        def _f(val, default=0.0):
            try:
                return float(val)
            except Exception:
                return default

        # Gentle normalization with sensible defaults to avoid 500s from legacy payloads
        brand = _s(raw.get('brand'), 'unknown')
        model = _s(raw.get('model'), '')
        year = _i(raw.get('year'), 0)
        mileage = _i(raw.get('mileage'), 0)
        engine_type = _s(raw.get('engine_type'), 'gasoline')
        fuel_type = _s(raw.get('fuel_type'), engine_type or 'gasoline')
        transmission = _s(raw.get('transmission'), 'automatic')
        drive_type = _s(raw.get('drive_type'), 'fwd')
        condition = _s(raw.get('condition'), 'used')
        body_type = _s(raw.get('body_type'), 'sedan')
        price = _f(raw.get('price'), 0.0)
        location = _s(raw.get('location'), '')
        description = _s(raw.get('description'), None) or None
        color = _s(raw.get('color'), 'white')
        fuel_economy = _s(raw.get('fuel_economy'), None) or None
        vin = _s(raw.get('vin'), None) or None
        currency = _s(raw.get('currency'), 'USD')[:3] or 'USD'
        trim = _s(raw.get('trim'), 'base')
        seating = _i(raw.get('seating'), 5)
        status = _s(raw.get('status'), 'active')

        # Minimal required sanity check
        if not brand or not model:
            return jsonify({'message': 'Validation failed', 'errors': {'brand/model': 'required'}}), 400

        car = Car(
            seller_id=current_user.id,
            title=(f"{brand.title()} {model.title()} {year or ''}".strip() or f"{brand.title()} {model.title()}").strip(),
            title_status='active',
            trim=trim,
            brand=brand,
            model=model,
            year=year,
            mileage=mileage,
            engine_type=engine_type,
            fuel_type=fuel_type,
            transmission=transmission,
            drive_type=drive_type,
            condition=condition,
            body_type=body_type,
            price=price,
            location=location,
            seating=seating,
            status=status,
            description=description,
            color=color,
            fuel_economy=fuel_economy,
            vin=vin,
            currency=currency
        )
        
        db.session.add(car)
        db.session.commit()

        # Log user action
        log_user_action(current_user, 'create_listing', 'car', car.public_id)
        
        return jsonify({
            'message': 'Car listing created successfully',
            'car': car.to_dict()
        }), 201
        
    except Exception as e:
        import traceback
        logger.error(f"Create car error: {str(e)}\n{traceback.format_exc()}")
        # Return a more informative error for debugging on dev builds
        return jsonify({'message': 'Failed to create car listing'}), 500

@app.route('/api/cars/<car_id>', methods=['PUT'])
@jwt_required()
def update_car(car_id):
    """Update car listing"""
    try:
        current_user = get_current_user()
        if not current_user:
            return jsonify({'message': 'User not found'}), 404
        
        car = Car.query.filter_by(public_id=car_id).first()
        if not car:
            return jsonify({'message': 'Car not found'}), 404
        
        # Check ownership
        if car.seller_id != current_user.id and not current_user.is_admin:
            return jsonify({'message': 'Not authorized to update this listing'}), 403
        
        data = request.get_json()
        
        # Update fields
        updatable_fields = ['brand', 'model', 'year', 'mileage', 'engine_type', 
                           'transmission', 'drive_type', 'condition', 'body_type', 
                           'price', 'location', 'description', 'color', 'fuel_economy', 'vin']
        
        for field in updatable_fields:
            if field in data:
                setattr(car, field, data[field])
        
        car.updated_at = datetime.utcnow()
        db.session.commit()
        
        # Log user action
        log_user_action(current_user, 'update_listing', 'car', car.public_id)
        
        return jsonify({
            'message': 'Car listing updated successfully',
            'car': car.to_dict()
        }), 200
        
    except Exception as e:
        logger.error(f"Update car error: {str(e)}")
        return jsonify({'message': 'Failed to update car listing'}), 500

@app.route('/api/cars/<car_id>', methods=['DELETE'])
@jwt_required()
def delete_car(car_id):
    """Delete car listing"""
    try:
        current_user = get_current_user()
        if not current_user:
            return jsonify({'message': 'User not found'}), 404
        
        car = Car.query.filter_by(public_id=car_id).first()
        if not car:
            return jsonify({'message': 'Car not found'}), 404
        
        # Check ownership
        if car.seller_id != current_user.id and not current_user.is_admin:
            return jsonify({'message': 'Not authorized to delete this listing'}), 403
        
        # Soft delete
        car.is_active = False
        car.updated_at = datetime.utcnow()
        db.session.commit()
        
        # Log user action
        log_user_action(current_user, 'delete_listing', 'car', car.public_id)
        
        return jsonify({'message': 'Car listing deleted successfully'}), 200
        
    except Exception as e:
        logger.error(f"Delete car error: {str(e)}")
        return jsonify({'message': 'Failed to delete car listing'}), 500

@app.route('/api/user/my-listings', methods=['GET'])
@jwt_required()
def get_my_listings():
    """Get current user's car listings"""
    try:
        current_user = get_current_user()
        if not current_user:
            return jsonify({'message': 'User not found'}), 404
        
        # Get pagination parameters
        page = request.args.get('page', 1, type=int)
        per_page = min(request.args.get('per_page', 10, type=int), 50)
        
        # Get user's cars with pagination
        pagination = Car.query.filter_by(seller_id=current_user.id).order_by(Car.created_at.desc()).paginate(
            page=page, 
            per_page=per_page, 
            error_out=False
        )
        
        cars = [car.to_dict(include_private=True) for car in pagination.items]
        
        return jsonify({
            'cars': cars,
            'pagination': {
                'page': page,
                'per_page': per_page,
                'total': pagination.total,
                'pages': pagination.pages,
                'has_next': pagination.has_next,
                'has_prev': pagination.has_prev
            }
        }), 200
        
    except Exception as e:
        logger.error(f"Get my listings error: {str(e)}")
        return jsonify({'message': 'Failed to get your listings'}), 500

# Compatibility alias for legacy mobile client expecting /api/my_listings
@app.route('/api/my_listings', methods=['GET'])
@jwt_required()
def compat_my_listings():
    try:
        current_user = get_current_user()
        if not current_user:
            return jsonify({'error': 'Unauthorized'}), 401

        cars = Car.query.filter_by(seller_id=current_user.id).order_by(Car.created_at.desc()).all()
        result = []
        for car in cars:
            # Build legacy-friendly shape: flat car dict with primary image_url and images list
            static_root = os.path.join(app.root_path, 'static')
            def _exists(rel: str) -> bool:
                try:
                    if not rel:
                        return False
                    p = os.path.join(static_root, rel.lstrip('/')).replace('\\', '/')
                    return os.path.isfile(p)
                except Exception:
                    return False
            def _resolve(rel: str) -> str:
                try:
                    if not rel:
                        return ''
                    norm = rel.lstrip('/').replace('\\', '/')
                    if _exists(norm):
                        return norm
                    base = os.path.basename(norm)
                    alt = os.path.join('uploads', 'car_photos', base).replace('\\', '/')
                    if _exists(alt):
                        return alt
                    return ''
                except Exception:
                    return ''
            image_list = [r for r in (_resolve(img.image_url) for img in car.images) if r] if car.images else []
            primary_rel = image_list[0] if image_list else ('uploads/car_photos/placeholder.jpg' if _exists('uploads/car_photos/placeholder.jpg') else '')
            result.append({
                "id": car.id,
                "title": (getattr(car, 'title', None) or f"{(car.brand or '').title()} {(car.model or '').title()} {car.year or ''}".strip()),
                "brand": car.brand,
                "model": car.model,
                "trim": getattr(car, 'trim', None),
                "year": car.year,
                "price": car.price,
                "mileage": car.mileage,
                "condition": car.condition,
                "transmission": car.transmission,
                "fuel_type": getattr(car, 'fuel_type', None) or car.engine_type,
                "color": car.color,
                "image_url": primary_rel,
                "images": image_list,
                "city": getattr(car, 'location', None) or getattr(car, 'city', None),
                "status": car.is_active and 'active' or 'inactive',
            })
        return jsonify(result), 200
    except Exception as e:
        logger.error(f"compat_my_listings error: {str(e)}")
        return jsonify({'error': 'Failed to get listings'}), 500

# File Upload Routes
@app.route('/api/cars/<car_id>/images', methods=['POST'])
@jwt_required()
def upload_car_images(car_id):
    """Upload car images (accepts 'files' or 'images'); blurs license plates before saving."""
    try:
        current_user = get_current_user()
        if not current_user:
            return jsonify({'message': 'User not found'}), 404

        # Accept both public_id (UUID) and numeric database id for compatibility with older clients
        car = Car.query.filter_by(public_id=car_id).first()
        if not car and str(car_id).isdigit():
            car = Car.query.filter_by(id=int(car_id)).first()
        if not car:
            return jsonify({'message': 'Car not found'}), 404

        # Check ownership
        if car.seller_id != current_user.id and not current_user.is_admin:
            return jsonify({'message': 'Not authorized to upload images for this listing'}), 403

        # Accept multiple common field names from different clients
        incoming_files = []
        for key in ('files', 'images', 'image', 'upload', 'file', 'photo', 'photos'):
            if key in request.files:
                incoming_files.extend(request.files.getlist(key))
        if not incoming_files:
            return jsonify({'message': 'No image files provided'}), 400

        uploaded_images = []
        skip_blur = request.args.get('skip_blur') == '1'

        for fs in incoming_files:
            if fs and fs.filename:
                # Validate file
                is_valid, _ = validate_file_upload(
                    fs,
                    max_size_mb=25,
                    allowed_extensions=app.config['ALLOWED_EXTENSIONS']
                )
                if not is_valid:
                    continue  # Skip invalid files, we'll error if none saved

                if skip_blur:
                    # Fast path: store file as provided (assumed already blurred by client)
                    filename = generate_secure_filename(fs.filename)
                    final_rel = os.path.join('uploads', 'car_photos', filename).replace('\\', '/')
                    final_abs = os.path.join(app.root_path, 'static', final_rel)
                    os.makedirs(os.path.dirname(final_abs), exist_ok=True)
                    fs.save(final_abs)
                    rel_path = final_rel
                else:
                    # Process with license-plate blur (supports mode=strict/auto/speed via query params)
                    rel_path, _ = _process_and_store_image(fs, False)

                # Create image record (store relative path under static)
                car_image = CarImage(
                    car_id=car.id,
                    image_url=rel_path,
                    is_primary=len(car.images) == 0  # First image is primary
                )
                db.session.add(car_image)
                uploaded_images.append(car_image.to_dict())

        db.session.commit()

        if not uploaded_images:
            return jsonify({'message': 'No valid images were uploaded (file type/size).'}), 400

        # Mark listing as having blurred plates (best-effort)
        try:
            car.license_plates_blurred = True
            db.session.commit()
        except Exception:
            db.session.rollback()

        # Log user action
        log_user_action(current_user, 'upload_images', 'car', car.public_id)

        # Determine new primary (first image for this car)
        try:
            primary = next((img.image_url for img in car.images if getattr(img, 'is_primary', False)), None)
            if not primary and car.images:
                primary = car.images[0].image_url
        except Exception:
            primary = None

        return jsonify({
            'message': f"{len(uploaded_images)} images uploaded successfully",
            'images': [ci for ci in uploaded_images],
            'image_url': primary or (uploaded_images[0]['image_url'] if uploaded_images else '')
        }), 201

    except Exception as e:
        logger.error(f"Upload car images error: {str(e)}")
        return jsonify({'message': 'Failed to upload images'}), 500

@app.route('/api/cars/<car_id>/images/attach', methods=['POST'])
@jwt_required()
def attach_car_images(car_id):
    """Attach already-processed images by relative paths without re-uploading/saving files."""
    try:
        current_user = get_current_user()
        if not current_user:
            return jsonify({'message': 'User not found'}), 404

        # Accept both public_id and numeric id
        car = Car.query.filter_by(public_id=car_id).first()
        if not car and str(car_id).isdigit():
            car = Car.query.filter_by(id=int(car_id)).first()
        if not car:
            return jsonify({'message': 'Car not found'}), 404

        if car.seller_id != current_user.id and not current_user.is_admin:
            return jsonify({'message': 'Not authorized to attach images for this listing'}), 403

        data = request.get_json(silent=True) or {}
        paths = data.get('paths') or []
        if not isinstance(paths, list) or not paths:
            return jsonify({'message': 'No image paths provided'}), 400

        attached = []
        for rel in paths:
            try:
                rel_str = str(rel)
                # normalize and ensure it stays under static/
                if rel_str.startswith('/'):
                    rel_str = rel_str[1:]
                if not rel_str.lower().startswith('uploads/'):
                    continue
                abs_path = os.path.join(app.root_path, 'static', rel_str).replace('\\', '/')
                if not os.path.isfile(abs_path):
                    continue
                ci = CarImage(
                    car_id=car.id,
                    image_url=rel_str,
                    is_primary=len(car.images) == 0
                )
                db.session.add(ci)
                attached.append(ci)
            except Exception:
                continue

        db.session.commit()

        # Mark listing as having blurred plates
        try:
            if attached:
                car.license_plates_blurred = True
                db.session.commit()
        except Exception:
            db.session.rollback()

        # Determine primary
        try:
            primary = next((img.image_url for img in car.images if getattr(img, 'is_primary', False)), None)
            if not primary and car.images:
                primary = car.images[0].image_url
        except Exception:
            primary = None

        return jsonify({
            'message': f"{len(attached)} images attached successfully",
            'images': [ci.to_dict() for ci in attached],
            'image_url': primary or ((attached[0].image_url) if attached else '')
        }), 201
    except Exception as e:
        logger.error(f"Attach car images error: {str(e)}")
        db.session.rollback()
        return jsonify({'message': 'Failed to attach images'}), 500
@app.route('/api/cars/<car_id>/videos', methods=['POST'])
@jwt_required()
def upload_car_videos(car_id):
    """Upload car videos"""
    try:
        current_user = get_current_user()
        if not current_user:
            return jsonify({'message': 'User not found'}), 404
        
        # Accept both public_id and numeric id
        car = Car.query.filter_by(public_id=car_id).first()
        if not car and str(car_id).isdigit():
            car = Car.query.filter_by(id=int(car_id)).first()
        if not car:
            return jsonify({'message': 'Car not found'}), 404
        
        # Check ownership
        if car.seller_id != current_user.id and not current_user.is_admin:
            return jsonify({'message': 'Not authorized to upload videos for this listing'}), 403
        
        if 'files' not in request.files:
            return jsonify({'message': 'No files provided'}), 400
        
        files = request.files.getlist('files')
        uploaded_videos = []
        
        for file in files:
            if file.filename:
                # Validate file
                is_valid, message = validate_file_upload(
                    file, 
                    max_size_mb=100, 
                    allowed_extensions=app.config['ALLOWED_VIDEO_EXTENSIONS']
                )
                
                if not is_valid:
                    continue  # Skip invalid files
                
                # Generate secure filename
                filename = generate_secure_filename(file.filename)
                file_path = os.path.join(app.config['UPLOAD_FOLDER'], 'car_videos', filename)
                
                # Save file
                file.save(file_path)
                
                # Create video record
                car_video = CarVideo(
                    car_id=car.id,
                    video_url=f"uploads/car_videos/{filename}"
                )
                
                db.session.add(car_video)
                uploaded_videos.append(car_video.to_dict())
        
        db.session.commit()
        
        # Log user action
        log_user_action(current_user, 'upload_videos', 'car', car.public_id)
        
        return jsonify({
            'message': f'{len(uploaded_videos)} videos uploaded successfully',
            'videos': uploaded_videos
        }), 201
        
    except Exception as e:
        logger.error(f"Upload car videos error: {str(e)}")
        return jsonify({'message': 'Failed to upload videos'}), 500

# Favorites Routes
@app.route('/api/user/favorites', methods=['GET'])
@jwt_required()
def get_favorites():
    """Get user's favorite cars"""
    try:
        current_user = get_current_user()
        if not current_user:
            return jsonify({'message': 'User not found'}), 404
        
        page = request.args.get('page', 1, type=int)
        per_page = request.args.get('per_page', 20, type=int)
        
        pagination = current_user.favorites.paginate(
            page=page, 
            per_page=per_page, 
            error_out=False
        )
        
        cars = [car.to_dict() for car in pagination.items]
        
        return jsonify({
            'cars': cars,
            'pagination': {
                'page': page,
                'per_page': per_page,
                'total': pagination.total,
                'pages': pagination.pages,
                'has_next': pagination.has_next,
                'has_prev': pagination.has_prev
            }
        }), 200
        
    except Exception as e:
        logger.error(f"Get favorites error: {str(e)}")
        return jsonify({'message': 'Failed to get favorites'}), 500

@app.route('/api/cars/<car_id>/favorite', methods=['POST'])
@jwt_required()
def toggle_favorite(car_id):
    """Toggle favorite status for a car"""
    try:
        current_user = get_current_user()
        if not current_user:
            return jsonify({'message': 'User not found'}), 404
        
        car = Car.query.filter_by(public_id=car_id, is_active=True).first()
        if not car:
            return jsonify({'message': 'Car not found'}), 404
        
        # Check if already favorited
        if current_user.favorites.filter_by(id=car.id).first():
            # Remove from favorites
            current_user.favorites.remove(car)
            action = 'removed'
        else:
            # Add to favorites
            current_user.favorites.append(car)
            action = 'added'
        
        db.session.commit()
        
        # Log user action
        log_user_action(current_user, f'favorite_{action}', 'car', car.public_id)
        
        return jsonify({
            'message': f'Car {action} from favorites',
            'is_favorited': action == 'added'
        }), 200
        
    except Exception as e:
        logger.error(f"Toggle favorite error: {str(e)}")
        return jsonify({'message': 'Failed to toggle favorite'}), 500

# Static file serving
@app.route('/static/<path:filename>')
def static_files(filename):
	"""Serve static files"""
	try:
		# Normal path — serve from the kk app's static directory
		static_dir = os.path.join(app.root_path, 'static')
		return send_from_directory(static_dir, filename)
	except Exception:
		# Fallback for mistakenly double-prefixed paths like 'uploads/uploads/...'
		try:
			if filename.startswith('uploads/uploads/'):
				fixed = filename[len('uploads/'):]
				static_dir = os.path.join(app.root_path, 'static')
				return send_from_directory(static_dir, fixed)
		except Exception:
			pass
		raise

# AI and image processing endpoints (compat with mobile app)
@app.route('/api/analyze-car-image', methods=['POST'])
@jwt_required()
def analyze_car_image():
    try:
        current_user = get_current_user()
        if not current_user:
            return jsonify({'error': 'User not found'}), 404

        if 'image' not in request.files:
            return jsonify({'error': 'No image file provided'}), 400

        file = request.files['image']
        if not file.filename:
            return jsonify({'error': 'No image file selected'}), 400

        # Save to temp area
        filename = generate_secure_filename(file.filename)
        timestamp = datetime.utcnow().strftime('%Y%m%d_%H%M%S')
        temp_rel = f"temp/ai_{timestamp}_{filename}"
        temp_abs = os.path.join(app.config['UPLOAD_FOLDER'], temp_rel)
        os.makedirs(os.path.dirname(temp_abs), exist_ok=True)
        file.save(temp_abs)

        try:
            from .ai_service import car_analysis_service
            analysis_result = car_analysis_service.analyze_car_image(temp_abs)
        finally:
            try:
                os.remove(temp_abs)
            except Exception:
                pass

        if isinstance(analysis_result, dict) and analysis_result.get('error'):
            return jsonify({'error': analysis_result['error']}), 500

        return jsonify({'success': True, 'analysis': analysis_result}), 200
    except Exception as e:
        logger.error(f"analyze_car_image error: {e}")
        return jsonify({'error': 'Failed to analyze car image'}), 500


def _process_and_store_image(file_storage, inline_base64: bool):
    filename = generate_secure_filename(file_storage.filename)
    timestamp = datetime.utcnow().strftime('%Y%m%d_%H%M%S')
    temp_rel = f"temp/processed_{timestamp}_{filename}"
    temp_abs = os.path.join(app.config['UPLOAD_FOLDER'], temp_rel)
    os.makedirs(os.path.dirname(temp_abs), exist_ok=True)
    file_storage.save(temp_abs)

    try:
        b64 = None
        final_filename = f"processed_{timestamp}_{filename}"
        # Prepare target path; extension will be updated from Content-Type
        final_rel = os.path.join('uploads', 'car_photos', final_filename).replace('\\', '/')
        final_abs = os.path.join(app.root_path, 'static', final_rel)
        os.makedirs(os.path.dirname(final_abs), exist_ok=True)

        # Watermarkly Blur API (binary POST with x-api-key)
        with open(temp_abs, 'rb') as fp:
            original_bytes = fp.read()
        # Deduplication re-use within this runtime if same bytes encountered
        digest = _get_sha256(original_bytes)
        blurred_bytes = None
        content_type = None
        with _recent_cache_lock:
            _prune_recent_cache()
            cached = _recent_cache.get(digest)
        if cached and cached.get('bytes'):
            blurred_bytes = cached['bytes']
            content_type = cached.get('content_type') or 'image/jpeg'
        else:
            # Try Watermarkly; on any failure (403, network, PIL issues), store the original
            try:
                blurred_bytes, content_type = _watermarkly_blur_bytes(original_bytes)
                with _recent_cache_lock:
                    _recent_cache[digest] = {'ts': time.time(), 'bytes': blurred_bytes, 'content_type': content_type}
                    _prune_recent_cache()
            except Exception:
                blurred_bytes = original_bytes
                # Prefer incoming mimetype if provided
                content_type = (getattr(file_storage, 'mimetype', None) or '').split(';', 1)[0].strip() or 'image/jpeg'

        # Map Content-Type to correct extension
        ct = (content_type or '').lower().split(';', 1)[0].strip()
        def _ext_for(mime: str) -> str:
            if mime in ('image/jpeg', 'image/jpg'): return '.jpg'
            if mime == 'image/png': return '.png'
            if mime == 'image/webp': return '.webp'
            return os.path.splitext(final_filename)[1] or '.jpg'
        chosen_ext = _ext_for(ct)
        root, _old = os.path.splitext(final_filename)
        final_filename = f"{root}{chosen_ext}"
        final_rel = os.path.join('uploads', 'car_photos', final_filename).replace('\\', '/')
        final_abs = os.path.join(app.root_path, 'static', final_rel)
        os.makedirs(os.path.dirname(final_abs), exist_ok=True)

        with open(final_abs, 'wb') as out:
            out.write(blurred_bytes)

        if inline_base64:
            with open(final_abs, 'rb') as f:
                encoded = base64.b64encode(f.read()).decode('utf-8')
            mime = ct or 'image/jpeg'
            b64 = f"data:{mime};base64,{encoded}"
        return final_rel, b64
    finally:
        # Clean up temporary files best-effort
        try:
            if temp_abs and os.path.exists(temp_abs):
                os.remove(temp_abs)
        except Exception:
            pass




@app.route('/api/process-car-images-test', methods=['POST'])
def process_car_images_test():
    try:
        files = request.files.getlist('images')
        if not files:
            return jsonify({'error': 'No image files provided'}), 400
        want_b64 = request.args.get('inline_base64') == '1'
        processed = []
        processed_b64 = []
        for fs in files:
            if not fs or not fs.filename:
                continue
            rel, b64 = _process_and_store_image(fs, want_b64)
            processed.append(rel)
            if want_b64 and b64:
                processed_b64.append(b64)
        return jsonify({'success': True, 'processed_images': processed, 'processed_images_base64': processed_b64}), 200
    except Exception as e:
        logger.error(f"process_car_images_test error: {e}")
        return jsonify({'error': 'Failed to process car images'}), 500


@app.route('/api/process-car-images', methods=['POST'])
@jwt_required()
def process_car_images():
    try:
        current_user = get_current_user()
        if not current_user:
            return jsonify({'error': 'User not found'}), 404
        files = request.files.getlist('images')
        if not files:
            return jsonify({'error': 'No image files provided'}), 400
        processed = []
        for fs in files:
            if not fs or not fs.filename:
                continue
            rel, _ = _process_and_store_image(fs, False)
            processed.append(rel)
        return jsonify({'success': True, 'processed_images': processed}), 200
    except Exception as e:
        logger.error(f"process_car_images error: {e}")
        return jsonify({'error': 'Failed to process car images'}), 500

# Email functions
def send_verification_email(user, token):
    """Send email verification email"""
    try:
        verification_url = f"{request.host_url}verify-email?token={token}"
        
        msg = Message(
            subject='Verify Your Email - Car Listings',
            recipients=[user.email],
            html=f"""
            <h2>Welcome to Car Listings!</h2>
            <p>Hi {user.first_name},</p>
            <p>Please click the link below to verify your email address:</p>
            <a href="{verification_url}">Verify Email</a>
            <p>If you didn't create an account, please ignore this email.</p>
            """
        )
        
        mail.send(msg)
        logger.info(f"Verification email sent to {user.email}")
        
    except Exception as e:
        logger.error(f"Failed to send verification email: {str(e)}")
        raise

def send_password_reset_email(user, token):
    """Send password reset email"""
    try:
        reset_url = f"{request.host_url}reset-password?token={token}"
        
        msg = Message(
            subject='Password Reset - Car Listings',
            recipients=[user.email],
            html=f"""
            <h2>Password Reset Request</h2>
            <p>Hi {user.first_name},</p>
            <p>You requested a password reset. Click the link below to reset your password:</p>
            <a href="{reset_url}">Reset Password</a>
            <p>This link will expire in 1 hour.</p>
            <p>If you didn't request this, please ignore this email.</p>
            """
        )
        
        mail.send(msg)
        logger.info(f"Password reset email sent to {user.email}")
        
    except Exception as e:
        logger.error(f"Failed to send password reset email: {str(e)}")
        raise

# Compatibility endpoint for profile: /api/auth/me
@app.route('/api/auth/me', methods=['GET'])
@jwt_required()
def compat_auth_me():
    try:
        current_user = get_current_user()
        if not current_user:
            return jsonify({'message': 'Unauthorized'}), 401
        # Flatten fields at top-level to match legacy client expectations
        return jsonify(current_user.to_dict(include_private=True)), 200
    except Exception as e:
        logger.error(f"compat_auth_me error: {str(e)}")
        return jsonify({'message': 'Failed to get profile'}), 500

# WebSocket events for real-time chat
@socketio.on('connect')
@jwt_required()
def handle_connect():
    """Handle client connection"""
    try:
        current_user = get_current_user()
        if not current_user:
            return False
        
        # Join user's personal room
        join_room(f"user_{current_user.public_id}")
        
        emit('connected', {'message': 'Connected successfully'})
        logger.info(f"User {current_user.username} connected")
        
    except Exception as e:
        logger.error(f"Connection error: {str(e)}")
        return False

@socketio.on('disconnect')
def handle_disconnect():
    """Handle client disconnection"""
    logger.info('Client disconnected')

@socketio.on('join_chat')
@jwt_required()
def handle_join_chat(data):
    """Join a chat room"""
    try:
        current_user = get_current_user()
        if not current_user:
            return
        
        car_id = data.get('car_id')
        if not car_id:
            return
        
        # Verify car exists
        car = Car.query.filter_by(public_id=car_id, is_active=True).first()
        if not car:
            return
        
        # Join chat room
        room = f"chat_{car_id}"
        join_room(room)
        
        emit('joined_chat', {'car_id': car_id, 'room': room})
        logger.info(f"User {current_user.username} joined chat for car {car_id}")
        
    except Exception as e:
        logger.error(f"Join chat error: {str(e)}")

@socketio.on('send_message')
@jwt_required()
def handle_send_message(data):
    """Send a message in chat"""
    try:
        current_user = get_current_user()
        if not current_user:
            return
        
        car_id = data.get('car_id')
        content = data.get('content')
        receiver_id = data.get('receiver_id')
        
        if not car_id or not content:
            return
        
        # Verify car exists
        car = Car.query.filter_by(public_id=car_id, is_active=True).first()
        if not car:
            return
        
        # Determine receiver (car seller or message receiver)
        if receiver_id:
            receiver = User.query.filter_by(public_id=receiver_id).first()
        else:
            receiver = car.seller
        
        if not receiver:
            return
        
        # Create message
        message = Message(
            sender_id=current_user.id,
            receiver_id=receiver.id,
            car_id=car.id,
            content=content,
            message_type='text'
        )
        
        db.session.add(message)
        db.session.commit()
        
        # Emit to chat room
        room = f"chat_{car_id}"
        emit('new_message', message.to_dict(), room=room)
        
        # Emit to receiver's personal room
        emit('new_message', message.to_dict(), room=f"user_{receiver.public_id}")
        
        # Create notification
        create_notification(
            receiver,
            'New Message',
            f'You have a new message from {current_user.first_name} {current_user.last_name}',
            'message',
            {'car_id': car_id, 'sender_id': current_user.public_id}
        )
        
        # Log user action
        log_user_action(current_user, 'send_message', 'message', message.public_id)
        
        logger.info(f"Message sent from {current_user.username} to {receiver.username}")
        
    except Exception as e:
        logger.error(f"Send message error: {str(e)}")

def create_notification(user, title, message, notification_type, data=None):
    """Create a notification for a user"""
    try:
        notification = Notification(
            user_id=user.id,
            title=title,
            message=message,
            notification_type=notification_type,
            data=data
        )
        
        db.session.add(notification)
        db.session.commit()
        
        # Emit to user's personal room
        socketio.emit('new_notification', notification.to_dict(), room=f"user_{user.public_id}")
        
        # Send push notification if Firebase token exists
        if user.firebase_token:
            send_push_notification(user.firebase_token, title, message, data)
        
    except Exception as e:
        logger.error(f"Create notification error: {str(e)}")

def send_push_notification(token, title, message, data=None):
    """Send push notification via Firebase"""
    try:
        import requests
        
        if not app.config.get('FIREBASE_SERVER_KEY'):
            return
        
        url = 'https://fcm.googleapis.com/fcm/send'
        headers = {
            'Authorization': f'key={app.config["FIREBASE_SERVER_KEY"]}',
            'Content-Type': 'application/json'
        }
        
        payload = {
            'to': token,
            'notification': {
                'title': title,
                'body': message
            },
            'data': data or {}
        }
        
        response = requests.post(url, headers=headers, json=payload)
        
        if response.status_code == 200:
            logger.info(f"Push notification sent successfully")
        else:
            logger.error(f"Push notification failed: {response.text}")
            
    except Exception as e:
        logger.error(f"Send push notification error: {str(e)}")

# Error handlers
@app.errorhandler(404)
def not_found(error):
    return jsonify({'message': 'Resource not found'}), 404

@app.errorhandler(500)
def internal_error(error):
    db.session.rollback()
    return jsonify({'message': 'Internal server error'}), 500

# Database initialization is handled at process start below for Flask 3 compatibility

# Lightweight health check for connectivity/monitoring
@app.route('/health', methods=['GET'])
def health():
    return jsonify({'status': 'ok'}), 200

# Debug info (safe to keep in development only)
@app.route('/debug/info', methods=['GET'])
def debug_info():
    try:
        cwd = os.getcwd()
        root_path = app.root_path
        uri = app.config.get('SQLALCHEMY_DATABASE_URI')
        try:
            from sqlalchemy import inspect
            db_file = db.engine.url.database
        except Exception:
            db_file = None
        root_db = str(pathlib.Path(root_path).parent.joinpath('car_listings_dev.db'))
        kk_db = str(pathlib.Path(root_path).joinpath('car_listings_dev.db'))
        return jsonify({
            'cwd': cwd,
            'app_root': root_path,
            'db_uri': uri,
            'db_file': db_file,
            'root_db_exists': os.path.exists(root_db),
            'kk_db_exists': os.path.exists(kk_db),
            'root_db': root_db,
            'kk_db': kk_db,
        }), 200
    except Exception as e:
        return jsonify({'error': str(e)}), 500

# Development-only reset and seed
@app.route('/dev/reinit', methods=['POST', 'GET'])
def dev_reinit():
    try:
        with app.app_context():
            db.drop_all()
            db.create_all()
            # Create demo user
            user = User(
                username='demo',
                email='demo@example.com',
                phone_number='07000000001',
                first_name='Demo',
                last_name='User'
            )
            user.set_password('password123')
            db.session.add(user)
            db.session.flush()
            # Add a couple cars
            sample_cars = [
                dict(brand='toyota', model='camry', year=2020, mileage=25000, engine_type='gasoline', transmission='automatic', drive_type='fwd', condition='used', body_type='sedan', price=21000.0, location='baghdad'),
                dict(brand='bmw', model='x5', year=2021, mileage=15000, engine_type='gasoline', transmission='automatic', drive_type='awd', condition='used', body_type='suv', price=55000.0, location='erbil'),
            ]
            for s in sample_cars:
                db.session.add(Car(seller_id=user.id, **s))
            db.session.commit()
        return jsonify({'status': 'reinit_ok'}), 200
    except Exception as e:
        db.session.rollback()
        return jsonify({'status': 'reinit_failed', 'error': str(e)}), 500

if __name__ == '__main__':
    with app.app_context():
        db.create_all()
    
    # Allow overriding port via environment and disable reloader to avoid duplicate processes
    port = int(os.environ.get('PORT', '5000'))
    socketio.run(
        app,
        debug=True,
        host='0.0.0.0',
        port=port,
        allow_unsafe_werkzeug=True,
        use_reloader=False,
    )
