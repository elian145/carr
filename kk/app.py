import os
import base64
import sys
import traceback
from flask import Flask, render_template, request, redirect, url_for, flash, jsonify, send_from_directory, abort, session, request as flask_request, Response
from flask_sqlalchemy import SQLAlchemy
from werkzeug.utils import secure_filename
from datetime import datetime, timedelta
import time
import random
from flask_login import LoginManager, UserMixin, login_user, login_required, logout_user, current_user
from flask_migrate import Migrate
from werkzeug.security import generate_password_hash, check_password_hash
import json
import requests
import uuid
import hashlib
import hmac
import base64
import secrets
from urllib.parse import urlencode
from flask_jwt_extended import JWTManager, create_access_token, get_jwt_identity, verify_jwt_in_request, jwt_required
from .auth import generate_secure_filename

# Optional Twilio import for SMS delivery; fallback to dev mode if unavailable
try:
    from twilio.rest import Client as TwilioClient
except Exception:
    TwilioClient = None
from flask_dance.contrib.google import make_google_blueprint, google
from flask_dance.consumer import oauth_authorized
from oauthlib.oauth2.rfc6749.errors import TokenExpiredError
try:
    # Optional: load environment variables from .env if present
    from dotenv import load_dotenv  # type: ignore
    load_dotenv()
except Exception:
    pass

# Absolute path for the database
BASE_DIR = os.path.abspath(os.path.dirname(__file__))
DB_PATH = os.path.join(BASE_DIR, 'instance', 'cars.db')

app = Flask(__name__)
app.config['SECRET_KEY'] = 'your-secret-key'
app.config['PROPAGATE_EXCEPTIONS'] = True
app.config['DEBUG'] = True
# Database configuration: Force use of cars.db to avoid schema mismatch
db_url = f'sqlite:///{DB_PATH}'
app.config['SQLALCHEMY_DATABASE_URI'] = db_url
app.config['SQLALCHEMY_TRACK_MODIFICATIONS'] = False
engine_opts = {
    'pool_pre_ping': True,
    'pool_recycle': 1800,
}
if db_url.startswith('postgresql'):
    # Reasonable defaults; override via env if needed
    pool_size = int(os.environ.get('DB_POOL_SIZE', '5'))
    max_overflow = int(os.environ.get('DB_MAX_OVERFLOW', '10'))
    pool_timeout = int(os.environ.get('DB_POOL_TIMEOUT', '30'))
    engine_opts.update({'pool_size': pool_size, 'max_overflow': max_overflow, 'pool_timeout': pool_timeout})
app.config['SQLALCHEMY_ENGINE_OPTIONS'] = engine_opts
app.config['UPLOAD_FOLDER'] = os.path.join(app.root_path, 'static', 'uploads')
app.config['MAX_CONTENT_LENGTH'] = 100 * 1024 * 1024  # 100MB max file size for videos
ALLOWED_EXTENSIONS = {'png', 'jpg', 'jpeg', 'gif', 'webp'}
ALLOWED_VIDEO_EXTENSIONS = {'mp4', 'mov', 'avi', 'mkv', 'webm'}
app.config['PERMANENT_SESSION_LIFETIME'] = timedelta(days=30)
app.config['JWT_SECRET_KEY'] = os.environ.get('JWT_SECRET_KEY', app.config['SECRET_KEY'])
app.config['JSON_AS_ASCII'] = False  # allow non-ASCII and large payloads safely

# Increase Werkzeug dev server timeout to reduce closed connections on slow model work
try:
    from werkzeug.serving import WSGIRequestHandler
    _srv_to = int(os.environ.get('FLASK_SERVER_TIMEOUT', '120'))
    WSGIRequestHandler.timeout = _srv_to
    print(f"[SERVER] WSGIRequestHandler timeout set to {_srv_to}s")
except Exception as _e:
    try:
        print(f"[SERVER] Could not set WSGIRequestHandler timeout: {_e}")
    except Exception:
        pass

# Google OAuth config (replace with your credentials)
app.config['GOOGLE_OAUTH_CLIENT_ID'] = os.environ.get('GOOGLE_OAUTH_CLIENT_ID', 'your-google-client-id')
app.config['GOOGLE_OAUTH_CLIENT_SECRET'] = os.environ.get('GOOGLE_OAUTH_CLIENT_SECRET', 'your-google-client-secret')
google_bp = make_google_blueprint(
    client_id=app.config['GOOGLE_OAUTH_CLIENT_ID'],
    client_secret=app.config['GOOGLE_OAUTH_CLIENT_SECRET'],
    scope=[
        "https://www.googleapis.com/auth/userinfo.email",
        "https://www.googleapis.com/auth/userinfo.profile",
        "openid"
    ]
    # Do not set redirect_url here, use Flask-Dance default
)
app.register_blueprint(google_bp, url_prefix="/login")

db = SQLAlchemy(app)
migrate = Migrate(app, db)
login_manager = LoginManager()
login_manager.init_app(app)
login_manager.login_view = 'login'

jwt = JWTManager(app)

# Ensure upload folder exists (absolute path)
os.makedirs(app.config['UPLOAD_FOLDER'], exist_ok=True)

class User(UserMixin, db.Model):
    id = db.Column(db.Integer, primary_key=True)
    username = db.Column(db.String(80), unique=True, nullable=False)
    email = db.Column(db.String(120), unique=True, nullable=False)
    password = db.Column(db.String(120), nullable=False)
    first_name = db.Column(db.String(80), nullable=True)
    last_name = db.Column(db.String(80), nullable=True)
    phone_number = db.Column(db.String(20), nullable=True)
    profile_picture = db.Column(db.String(200), nullable=True)
    created_at = db.Column(db.DateTime, nullable=False, default=datetime.utcnow)

@login_manager.user_loader
def load_user(user_id):
    return User.query.get(int(user_id))

# Simple in-memory token store for emulator/mobile API
TOKENS: dict[str, int] = {}

# Simple in-memory phone OTP store and user->phone mapping (for demo/dev)
PHONE_OTPS: dict[str, dict] = {}
USER_PHONES: dict[int, str] = {}

def _normalize_phone(raw: str) -> str:
    """Return E.164-like string: keep digits and leading '+'. If no '+', prefix '+'"""
    s = str(raw or '').strip()
    # Keep digits and '+'
    kept = []
    for ch in s:
        if ch.isdigit() or ch == '+':
            kept.append(ch)
    if not kept:
        return ''
    if kept[0] != '+':
        # ensure starts with '+' and only digits after
        digits = ''.join(ch for ch in kept if ch.isdigit())
        return f'+{digits}' if digits else ''
    # already has '+': ensure only digits after
    return '+' + ''.join(ch for ch in kept[1:] if ch.isdigit())

def get_api_user():
    """Return a User from JWT Bearer token if present; fallback to legacy token or current_user."""
    # Prefer JWT tokens
    try:
        verify_jwt_in_request(optional=True)
        identity = get_jwt_identity()
        if identity:
            return User.query.get(int(identity))
        else:
            # Debug: no identity even though we attempted verification
            try:
                ah = flask_request.headers.get('Authorization', '')
                print('[AUTH DEBUG] No JWT identity. has_header=', bool(ah), ' bearer_prefix=', ah.startswith('Bearer '), ' sample=', ah[:32])
            except Exception:
                pass
    except Exception as e:
        try:
            print('[AUTH DEBUG] JWT verify error:', str(e))
        except Exception:
            pass
    # Legacy in-memory token support
    try:
        auth = flask_request.headers.get('Authorization', '')
        if auth.startswith('Bearer '):
            token = auth[7:]
            uid = TOKENS.get(token)
            if uid:
                return User.query.get(uid)
            else:
                # Debug: legacy token not found
                try:
                    print('[AUTH DEBUG] Legacy token not found in TOKENS map. sample=', token[:16])
                except Exception:
                    pass
    except Exception:
        pass
    # Fallback to session-based auth
    if current_user.is_authenticated:
        return current_user
    return None

# Mobile auth endpoints (token-based) for emulator
@app.route('/api/auth/signup', methods=['POST'])
def api_auth_signup_mobile():
    data = request.get_json() or {}
    username = str(data.get('username', '')).strip()
    password = str(data.get('password', ''))
    auth_type = str(data.get('auth_type', 'email')).strip()
    
    if not username or not password:
        return jsonify({'error': 'username and password required'}), 400
    
    user_email = None
    phone = None
    
    if auth_type == 'email':
        email = str(data.get('email', '')).strip()
        if not email or '@' not in email:
            return jsonify({'error': 'Valid email required for email authentication'}), 400
        user_email = email
    elif auth_type == 'phone':
        phone_raw = str(data.get('phone', ''))
        otp_code = str(data.get('otp_code', ''))
        phone = _normalize_phone(phone_raw)
        if not phone or not otp_code:
            return jsonify({'error': 'phone and otp_code required for phone authentication'}), 400
        # Verify OTP
        entry = PHONE_OTPS.get(phone)
        if not entry or entry.get('code') != otp_code or entry.get('expires_at') < datetime.utcnow():
            return jsonify({'error': 'Invalid or expired verification code'}), 400
        # Generate placeholder email from phone
        digits_only = ''.join(ch for ch in phone if ch.isdigit())
        user_email = f"{digits_only}@phone.local"
    else:
        return jsonify({'error': 'Invalid auth_type. Must be "email" or "phone"'}), 400
    
    # Check for existing user with same username or email
    existing_user = User.query.filter((User.username == username) | (User.email == user_email)).first()
    if existing_user:
        return jsonify({'error': 'Username or email already exists'}), 409
    
    user = User(username=username, email=user_email, password=generate_password_hash(password))
    db.session.add(user)
    db.session.commit()
    
    # Map phone to user if phone auth was used
    if phone:
        USER_PHONES[user.id] = phone
        # Consume OTP
        PHONE_OTPS.pop(phone, None)
    
    token = create_access_token(identity=str(user.id), expires_delta=timedelta(days=30))
    return jsonify({
        'token': token, 
        'user': {
            'id': user.id, 
            'username': user.username, 
            'email': user.email, 
            'phone': phone or '',
            'profile_picture': getattr(user, 'profile_picture', '')
        }
    })

@app.route('/api/auth/login', methods=['POST'])
def api_auth_login_mobile():
    data = request.get_json() or {}
    email_or_phone = str(data.get('username', '')).strip()  # Keep 'username' key for compatibility
    password = str(data.get('password', ''))
    if not email_or_phone or not password:
        return jsonify({'error': 'email/phone and password required'}), 400
    
    # Try to find user by email first, then by phone number
    user = User.query.filter_by(email=email_or_phone).first()
    if not user:
        # Try to find by phone number from USER_PHONES
        for user_id, phone in USER_PHONES.items():
            if phone == email_or_phone:
                user = User.query.get(user_id)
                break
    
    if not user or not check_password_hash(user.password, password):
        return jsonify({'error': 'Invalid credentials'}), 401
    token = create_access_token(identity=str(user.id), expires_delta=timedelta(days=30))
    # Include phone if known
    phone = USER_PHONES.get(user.id, '')
    return jsonify({
        'token': token, 
        'user': {
            'id': user.id, 
            'username': user.username, 
            'email': user.email, 
            'phone': phone,
            'profile_picture': getattr(user, 'profile_picture', '')
        }
    })

@app.route('/api/auth/me', methods=['GET'])
def api_auth_me_mobile():
    user = get_api_user()
    if not user:
        return jsonify({'error': 'Unauthorized'}), 401
    phone = ''
    try:
        phone = getattr(user, 'phone', None) or ''
    except Exception:
        phone = ''
    if not phone:
        phone = USER_PHONES.get(user.id, '')
    return jsonify({
        'id': user.id, 
        'username': user.username, 
        'email': user.email, 
        'phone': phone,
        'profile_picture': getattr(user, 'profile_picture', '')
    })

# Send OTP to phone (dev/demo: returns code in response; replace with SMS integration)
@app.route('/api/auth/send_otp', methods=['POST'])
def api_auth_send_otp():
    data = request.get_json() or {}
    phone_raw = str(data.get('phone', ''))
    phone = _normalize_phone(phone_raw)
    if not phone:
        return jsonify({'error': 'phone required'}), 400
    code = f"{random.randint(100000, 999999)}"
    PHONE_OTPS[phone] = {
        'code': code,
        'expires_at': datetime.utcnow() + timedelta(minutes=10)
    }
    # Send via provider
    body = f"Your verification code is {code}"
    sent, err = _send_sms(phone, body)
    if sent:
        return jsonify({'sent': True})
    return jsonify({'sent': False, 'error': err, 'dev_code': code})

def _send_sms(phone: str, body: str) -> tuple[bool, str]:
    provider = os.environ.get('SMS_PROVIDER', 'twilio').strip().lower()
    try:
        if provider == 'twilio':
            sid = os.environ.get('TWILIO_ACCOUNT_SID')
            token = os.environ.get('TWILIO_AUTH_TOKEN')
            from_number = os.environ.get('TWILIO_FROM_NUMBER')
            if TwilioClient and sid and token and from_number:
                client = TwilioClient(sid, token)
                client.messages.create(to=phone, from_=from_number, body=body)
                return True, ''
            return False, 'Twilio not configured'
        elif provider == 'infobip':
            # Infobip SMS over HTTP
            base_url = os.environ.get('INFOBIP_BASE_URL', '').rstrip('/')
            api_key = os.environ.get('INFOBIP_API_KEY', '')
            sender = os.environ.get('INFOBIP_SENDER', '')
            if not (base_url and api_key):
                return False, 'Infobip not configured (INFOBIP_BASE_URL, INFOBIP_API_KEY)'
            url = f"{base_url}/sms/2/text/advanced"
            headers = {
                'Authorization': f"App {api_key}",
                'Content-Type': 'application/json'
            }
            msg = {
                'destinations': [{'to': phone}],
                'text': body,
            }
            if sender:
                msg['from'] = sender
            payload = {'messages': [msg]}
            resp = requests.post(url, headers=headers, json=payload, timeout=15)
            if 200 <= resp.status_code < 300:
                return True, ''
            return False, f'Infobip {resp.status_code}: {resp.text[:200]}'
        elif provider == 'custom':
            url = os.environ.get('CUSTOM_SMS_URL', '').strip()
            if not url:
                return False, 'CUSTOM_SMS_URL not set'
            method = os.environ.get('CUSTOM_SMS_METHOD', 'POST').upper()
            to_param = os.environ.get('CUSTOM_SMS_TO_PARAM', 'to')
            msg_param = os.environ.get('CUSTOM_SMS_MSG_PARAM', 'message')
            extra_json = os.environ.get('CUSTOM_SMS_EXTRA_JSON', '')
            try:
                extra = json.loads(extra_json) if extra_json else {}
            except Exception:
                extra = {}
            payload = {**extra, to_param: phone, msg_param: body}
            if method == 'GET':
                resp = requests.get(url, params=payload, timeout=10)
            else:
                resp = requests.post(url, data=payload, timeout=10)
            if 200 <= resp.status_code < 300:
                return True, ''
            return False, f'Gateway {resp.status_code}: {resp.text[:200]}'
        else:
            return False, f'Unknown SMS_PROVIDER {provider}'
    except Exception as e:
        return False, str(e)

class Car(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    title = db.Column(db.String(100), nullable=False)
    title_status = db.Column(db.String(20), nullable=False, default='clean')
    damaged_parts = db.Column(db.Integer, nullable=True)
    brand = db.Column(db.String(50), nullable=False)
    model = db.Column(db.String(50), nullable=False)
    trim = db.Column(db.String(50), nullable=False)
    year = db.Column(db.Integer, nullable=False)
    price = db.Column(db.Float, nullable=True)
    mileage = db.Column(db.Integer, nullable=False)
    condition = db.Column(db.String(20), nullable=False)
    transmission = db.Column(db.String(20), nullable=False)
    fuel_type = db.Column(db.String(20), nullable=False)
    color = db.Column(db.String(30), nullable=False)
    image_url = db.Column(db.String(200), nullable=True)
    created_at = db.Column(db.DateTime, nullable=False, default=datetime.utcnow)
    user_id = db.Column(db.Integer, db.ForeignKey('user.id'), nullable=True)
    user = db.relationship('User', backref=db.backref('cars', lazy=True))
    cylinder_count = db.Column(db.Integer, nullable=True)
    engine_size = db.Column(db.Float, nullable=True)  # in liters
    import_country = db.Column(db.String(50), nullable=True)  # Import country of origin
    body_type = db.Column(db.String(20), nullable=False)
    seating = db.Column(db.Integer, nullable=False)
    drive_type = db.Column(db.String(20), nullable=False)
    license_plate_type = db.Column(db.String(20), nullable=True)  # private, temporary, commercial, taxi
    city = db.Column(db.String(50), nullable=True)  # City in Iraq
    contact_phone = db.Column(db.String(20), nullable=True)  # WhatsApp/contact phone for seller
    images = db.relationship('CarImage', backref='car', lazy=True, cascade='all, delete-orphan')
    videos = db.relationship('CarVideo', backref='car', lazy=True, cascade='all, delete-orphan')
    favorited_by = db.relationship('Favorite', back_populates='car', lazy=True, cascade='all, delete-orphan')
    status = db.Column(db.String(20), nullable=False, default='pending_payment')  # pending_payment, active, etc.
    is_quick_sell = db.Column(db.Boolean, default=False)

class CarModel(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    brand = db.Column(db.String(50), nullable=False)
    model = db.Column(db.String(50), nullable=False)
    trim = db.Column(db.String(50), nullable=True)

    def __repr__(self):
        return f'<CarModel {self.brand} {self.model}>'

class CarImage(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    car_id = db.Column(db.Integer, db.ForeignKey('car.id'), nullable=False)
    image_url = db.Column(db.String(200), nullable=False)

class CarVideo(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    car_id = db.Column(db.Integer, db.ForeignKey('car.id'), nullable=False)
    video_url = db.Column(db.String(200), nullable=False)
    created_at = db.Column(db.DateTime, nullable=False, default=datetime.utcnow)

class Favorite(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    user_id = db.Column(db.Integer, db.ForeignKey('user.id'), nullable=False)
    car_id = db.Column(db.Integer, db.ForeignKey('car.id'), nullable=False)
    created_at = db.Column(db.DateTime, nullable=False, default=datetime.utcnow)
    user = db.relationship('User', backref=db.backref('favorites', lazy=True, cascade='all, delete-orphan'))
    car = db.relationship('Car', back_populates='favorited_by')

class Conversation(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    car_id = db.Column(db.Integer, db.ForeignKey('car.id'), nullable=False)
    buyer_id = db.Column(db.Integer, db.ForeignKey('user.id'), nullable=False)
    seller_id = db.Column(db.Integer, db.ForeignKey('user.id'), nullable=False)
    created_at = db.Column(db.DateTime, nullable=False, default=datetime.utcnow)
    updated_at = db.Column(db.DateTime, nullable=False, default=datetime.utcnow, onupdate=datetime.utcnow)
    
    # Relationships
    car = db.relationship('Car', backref=db.backref('conversations', lazy=True, cascade='all, delete-orphan'))
    buyer = db.relationship('User', foreign_keys=[buyer_id], backref=db.backref('buyer_conversations', lazy=True))
    seller = db.relationship('User', foreign_keys=[seller_id], backref=db.backref('seller_conversations', lazy=True))
    messages = db.relationship('Message', backref='conversation', lazy=True, cascade='all, delete-orphan', order_by='Message.created_at')

class Message(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    conversation_id = db.Column(db.Integer, db.ForeignKey('conversation.id'), nullable=False)
    sender_id = db.Column(db.Integer, db.ForeignKey('user.id'), nullable=False)
    content = db.Column(db.Text, nullable=False)
    is_read = db.Column(db.Boolean, default=False)
    created_at = db.Column(db.DateTime, nullable=False, default=datetime.utcnow)
    
    # Relationships
    sender = db.relationship('User', backref=db.backref('sent_messages', lazy=True))

class Payment(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    payment_id = db.Column(db.String(100), unique=True, nullable=False)  # FIB payment ID
    car_id = db.Column(db.Integer, db.ForeignKey('car.id'), nullable=True)  # Optional, for listing fees
    user_id = db.Column(db.Integer, db.ForeignKey('user.id'), nullable=False)  # User paying the fee
    amount = db.Column(db.Float, nullable=False)
    currency = db.Column(db.String(3), default='USD')
    status = db.Column(db.String(20), default='pending')  # pending, completed, failed, cancelled
    payment_method = db.Column(db.String(50), default='fib')  # fib, bank_transfer, etc.
    payment_type = db.Column(db.String(20), default='listing_fee')  # listing_fee, purchase, etc.
    transaction_reference = db.Column(db.String(100), nullable=True)
    created_at = db.Column(db.DateTime, nullable=False, default=datetime.utcnow)
    updated_at = db.Column(db.DateTime, nullable=False, default=datetime.utcnow, onupdate=datetime.utcnow)
    
    # Relationships
    car = db.relationship('Car', backref='payments')
    user = db.relationship('User', backref='payments')

class PaymentTransaction(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    payment_id = db.Column(db.Integer, db.ForeignKey('payment.id'), nullable=False)
    transaction_type = db.Column(db.String(20), nullable=False)  # init, callback, webhook
    fib_transaction_id = db.Column(db.String(100), nullable=True)
    amount = db.Column(db.Float, nullable=False)
    status = db.Column(db.String(20), nullable=False)
    response_data = db.Column(db.Text, nullable=True)  # JSON response from FIB
    created_at = db.Column(db.DateTime, nullable=False, default=datetime.utcnow)
    
    payment = db.relationship('Payment', backref='transactions')

def allowed_file(filename):
    return '.' in filename and filename.rsplit('.', 1)[1].lower() in ALLOWED_EXTENSIONS

def allowed_video_file(filename):
    return '.' in filename and filename.rsplit('.', 1)[1].lower() in ALLOWED_VIDEO_EXTENSIONS

def _process_and_store_image(file_storage, inline_base64: bool):
    """Process an uploaded image by blurring license plates, store it under uploads, and optionally return base64.

    Returns tuple (relative_path_under_static, base64_data_or_None)
    Example relative path: 'uploads/car_photos/processed_YYYYMMDD_HHMMSS_xxx.jpg'
    """
    # Generate a secure filename and save to a temp location first
    filename = generate_secure_filename(file_storage.filename)
    timestamp = datetime.utcnow().strftime('%Y%m%d_%H%M%S')
    temp_rel = f"temp/processed_{timestamp}_{filename}"
    temp_abs = os.path.join(app.config['UPLOAD_FOLDER'], temp_rel)
    os.makedirs(os.path.dirname(temp_abs), exist_ok=True)
    file_storage.save(temp_abs)

    try:
        # Blur license plates using the AI service
        from .ai_service import car_analysis_service  # local import to avoid heavy import at module load
        processed_abs = car_analysis_service._blur_license_plates(temp_abs)

        # Move/copy processed file to final destination under uploads/car_photos
        final_filename = f"processed_{timestamp}_{filename}"
        # Relative path stored in DB/returned to client
        final_rel = os.path.join('uploads', 'car_photos', final_filename).replace('\\', '/')
        # Absolute filesystem path under static/uploads (do NOT duplicate 'uploads')
        final_abs = os.path.join(app.config['UPLOAD_FOLDER'], 'car_photos', final_filename)
        os.makedirs(os.path.dirname(final_abs), exist_ok=True)

        import shutil
        shutil.copy2(processed_abs, final_abs)

        b64_data = None
        if inline_base64:
            try:
                with open(final_abs, 'rb') as f:
                    encoded = base64.b64encode(f.read()).decode('utf-8')
                ext = os.path.splitext(final_filename)[1].lower().lstrip('.')
                mime = 'image/jpeg' if ext in ('jpg', 'jpeg') else ('image/png' if ext == 'png' else ('image/webp' if ext == 'webp' else 'image/*'))
                b64_data = f"data:{mime};base64,{encoded}"
            except Exception as _e:
                try:
                    print(f"inline base64 encode failed: {_e}")
                except Exception:
                    pass

        return final_rel, b64_data
    finally:
        # Clean up temporary files
        for p in (temp_abs, processed_abs if 'processed_abs' in locals() else None):
            try:
                if p and os.path.exists(p):
                    os.remove(p)
            except Exception:
                pass

@app.route('/')
def home():
    # Only show active cars
    cars = Car.query.filter_by(status='active').order_by(Car.created_at.desc()).all()
    print(f"[DEBUG] Found {len(cars)} active cars:")
    for car in cars:
        print(f"[DEBUG] Car ID: {car.id}, Title: {car.title}, Status: {car.status}")
    current_year = datetime.now().year
    sort_by = request.args.get('sort_by', 'recent')
    favorited_ids = set()
    if current_user.is_authenticated:
        favorited_ids = set(fav.car_id for fav in Favorite.query.filter_by(user_id=current_user.id).all())
    return render_template('home.html', cars=cars, current_year=current_year, sort_by=sort_by, favorited_ids=favorited_ids)

@app.route('/add', methods=['GET', 'POST'])
@login_required
def add_car():
    if request.method == 'POST':
        form_data = request.form
        required_fields = [
            'brand', 'model', 'trim', 'year', 'mileage', 'transmission', 
            'fuel_type', 'color', 'body_type', 'seating', 'drive_type', 
            'title_status', 'condition'
        ]
        missing_fields = [field.replace('_', ' ').title() for field in required_fields if not form_data.get(field)]
        if missing_fields:
            flash(f'The following fields are required: {", ".join(missing_fields)}', 'danger')
            return render_template('add_car.html', current_year=datetime.now().year, car=form_data)
        brand = form_data.get('brand')
        if brand:
            brand = brand.strip().lower().replace(' ', '-')
        model = form_data.get('model')
        trim = form_data.get('trim')
        price_str = form_data.get('price', '').strip()
        price = float(price_str) if price_str else None
        year = form_data.get('year', type=int)
        mileage = form_data.get('mileage', type=int)
        title_status = form_data.get('title_status')
        damaged_parts = form_data.get('damaged_parts', type=int)
        transmission = form_data.get('transmission')
        fuel_type = form_data.get('fuel_type')
        color = form_data.get('color')
        cylinder_count = form_data.get('cylinder_count', type=int)
        engine_size = form_data.get('engine_size', type=float)
        import_country = form_data.get('import_country')
        body_type = form_data.get('body_type')
        seating = form_data.get('seating', type=int)
        drive_type = form_data.get('drive_type')
        license_plate_type = form_data.get('license_plate_type')
        city = form_data.get('city')
        condition = form_data.get('condition')
        title = f"{brand.replace('-', ' ').title()} {model}"
        car = Car(
            title=title,
            brand=brand,
            model=model,
            trim=trim,
            year=year,
            mileage=mileage,
            price=price,
            title_status=title_status,
            damaged_parts=damaged_parts,
            transmission=transmission,
            fuel_type=fuel_type,
            color=color,
            cylinder_count=cylinder_count,
            engine_size=engine_size,
            import_country=import_country,
            body_type=body_type,
            seating=seating,
            drive_type=drive_type,
            license_plate_type=license_plate_type,
            city=city,
            condition=condition,
            is_quick_sell=bool(form_data.get('is_quick_sell', False)),
            user_id=current_user.id,
            status='pending_payment'
        )
        db.session.add(car)
        db.session.commit()
        # Handle image uploads
        images = request.files.getlist('image')
        if images and images[0].filename:
            for image in images:
                if image and allowed_file(image.filename):
                    filename = secure_filename(image.filename)
                    timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
                    filename = f"{timestamp}_{filename}"
                    image_path = os.path.join(app.config['UPLOAD_FOLDER'], 'car_photos', filename)
                    os.makedirs(os.path.dirname(image_path), exist_ok=True)
                    image.save(image_path)
                    car_image = CarImage(
                        car_id=car.id,
                        image_url=f"uploads/car_photos/{filename}"
                    )
                    db.session.add(car_image)
            db.session.commit()
        else:
            flash('At least one image is required.', 'danger')
            db.session.delete(car)
            db.session.commit()
            return render_template('add_car.html', current_year=datetime.now().year, car=form_data)
        
        # Handle video uploads (optional)
        videos = request.files.getlist('video')
        if videos and videos[0].filename:
            for video in videos:
                if video and allowed_video_file(video.filename):
                    filename = secure_filename(video.filename)
                    timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
                    filename = f"{timestamp}_{filename}"
                    video_path = os.path.join(app.config['UPLOAD_FOLDER'], 'car_videos', filename)
                    os.makedirs(os.path.dirname(video_path), exist_ok=True)
                    video.save(video_path)
                    car_video = CarVideo(
                        car_id=car.id,
                        video_url=f"uploads/car_videos/{filename}"
                    )
                    db.session.add(car_video)
            db.session.commit()
        # Create a payment record for this car
        payment = Payment(
            payment_id=str(uuid.uuid4()),
            user_id=current_user.id,
            car_id=car.id,
            amount=LISTING_FEE_CONFIG['amount'],
            currency=LISTING_FEE_CONFIG['currency'],
            payment_type='listing_fee',
            status='pending'
        )
        db.session.add(payment)
        db.session.commit()
        # Redirect to payment gateway for this payment
        return redirect(url_for('payment_gateway', payment_id=payment.id))
    return render_template('add_car.html', current_year=datetime.now().year, car={})

@app.route('/car/<int:car_id>')
def car_detail(car_id):
    car = Car.query.get_or_404(car_id)
    if car.status != 'active' and (not current_user.is_authenticated or car.user_id != current_user.id):
        flash('This listing is not available.', 'warning')
        return redirect(url_for('home'))
    # Fetch other listings, excluding the current one, order by most recent
    other_cars = Car.query.filter(Car.id != car_id, Car.status == 'active').order_by(Car.created_at.desc()).limit(6).all()
    # Fetch similar listings (same brand and model, not current)
    similar_cars = Car.query.filter(
        Car.id != car_id,
        Car.brand == car.brand,
        Car.model == car.model,
        Car.status == 'active'
    ).order_by(Car.created_at.desc()).limit(6).all()
    favorited = False
    if current_user.is_authenticated:
        favorited = db.session.query(Favorite).filter_by(user_id=current_user.id, car_id=car.id).first() is not None
    return render_template('car_detail.html', car=car, other_cars=other_cars, similar_cars=similar_cars, favorited=favorited)

@app.route('/delete/<int:car_id>', methods=['POST'])
def delete_car(car_id):
    car = Car.query.get_or_404(car_id)
    # Delete all image files for this car
    for image in car.images:
        try:
            # image.image_url like 'uploads/car_photos/filename.jpg' → store under static/uploads
            rel = image.image_url
            if rel.startswith('uploads/'):
                rel = rel[8:]
            file_path = os.path.join(app.config['UPLOAD_FOLDER'], rel)
            if os.path.exists(file_path):
                os.remove(file_path)
        except Exception:
            pass
    db.session.delete(car)
    db.session.commit()
    flash('Car listing deleted successfully!', 'success')
    return redirect(url_for('home'))

@app.route('/api/models/<brand>')
def get_models(brand):
    models = CarModel.query.filter_by(brand=brand).all()
    return jsonify([model.model for model in models])

@app.route('/api/trims/<brand>/<model>')
def get_trims(brand, model):
    # Model designations (engine variants) for different brands and models
    trim_levels = {
        'mercedes-benz': {
            'A-Class': ['A180', 'A200', 'A220', 'A250', 'A35 AMG', 'A45 AMG', 'A45 S AMG', 'AMG Line', 'Progressive', 'Premium', 'Premium Plus'],
            'B-Class': ['B180', 'B200', 'B220', 'B250', 'AMG Line', 'Progressive', 'Premium', 'Premium Plus'],
            'C-Class': ['C180', 'C200', 'C220d', 'C250', 'C300', 'C350e', 'C43 AMG', 'C63 AMG', 'C63 S AMG', 'AMG Line', 'Progressive', 'Premium', 'Premium Plus'],
            'CLA': ['CLA180', 'CLA200', 'CLA220', 'CLA250', 'CLA35 AMG', 'CLA45 AMG', 'CLA45 S AMG', 'AMG Line', 'Progressive', 'Premium', 'Premium Plus'],
            'CLS': ['CLS300', 'CLS350', 'CLS450', 'CLS53 AMG', 'CLS63 AMG', 'AMG Line', 'Progressive', 'Premium', 'Premium Plus'],
            'E-Class': ['E200', 'E220d', 'E250', 'E300', 'E350e', 'E400', 'E43 AMG', 'E53 AMG', 'E63 AMG', 'E63 S AMG', 'AMG Line', 'Progressive', 'Premium', 'Premium Plus'],
            'G-Class': ['G350d', 'G400d', 'G500', 'G63 AMG', 'G65 AMG', 'AMG Line', 'Progressive', 'Premium', 'Premium Plus'],
            'GLA': ['GLA180', 'GLA200', 'GLA220', 'GLA250', 'GLA35 AMG', 'GLA45 AMG', 'AMG Line', 'Progressive', 'Premium', 'Premium Plus'],
            'GLB': ['GLB180', 'GLB200', 'GLB220', 'GLB250', 'GLB35 AMG', 'AMG Line', 'Progressive', 'Premium', 'Premium Plus'],
            'GLC': ['GLC200', 'GLC220d', 'GLC250', 'GLC300', 'GLC350e', 'GLC43 AMG', 'GLC63 AMG', 'AMG Line', 'Progressive', 'Premium', 'Premium Plus'],
            'GLE': ['GLE300d', 'GLE350', 'GLE400d', 'GLE450', 'GLE53 AMG', 'GLE63 AMG', 'GLE63 S AMG', 'AMG Line', 'Progressive', 'Premium', 'Premium Plus'],
            'GLS': ['GLS350d', 'GLS400d', 'GLS450', 'GLS580', 'GLS63 AMG', 'AMG Line', 'Progressive', 'Premium', 'Premium Plus'],
            'S-Class': ['S350d', 'S400d', 'S450', 'S500', 'S560', 'S63 AMG', 'S65 AMG', 'S680', 'Maybach S560', 'Maybach S650', 'AMG Line', 'Progressive', 'Premium', 'Premium Plus'],
            'SL': ['SL55 AMG', 'SL63 AMG', 'AMG Line', 'Progressive', 'Premium', 'Premium Plus'],
            'SLC': ['SLC180', 'SLC200', 'SLC300', 'SLC43 AMG', 'AMG Line', 'Progressive', 'Premium', 'Premium Plus'],
            'V-Class': ['V200', 'V220d', 'V250', 'V300d', 'AMG Line', 'Progressive', 'Premium', 'Premium Plus'],
            'AMG GT': ['AMG GT', 'AMG GT C', 'AMG GT R', 'AMG GT Black Series', 'AMG GT 63', 'AMG GT 63 S', 'AMG Line', 'Progressive', 'Premium', 'Premium Plus'],
            'EQS': ['EQS 450+', 'EQS 580', 'EQS 53 AMG', 'AMG Line', 'Progressive', 'Premium', 'Premium Plus'],
            'EQE': ['EQE 300', 'EQE 350', 'EQE 500', 'EQE 53 AMG', 'AMG Line', 'Progressive', 'Premium', 'Premium Plus'],
            'EQB': ['EQB 250+', 'EQB 300', 'EQB 350', 'AMG Line', 'Progressive', 'Premium', 'Premium Plus'],
            'EQA': ['EQA 250', 'EQA 300', 'EQA 350', 'AMG Line', 'Progressive', 'Premium', 'Premium Plus'],
            'AMG GT 4-Door': ['AMG GT 43', 'AMG GT 53', 'AMG GT 63', 'AMG GT 63 S', 'AMG Line', 'Progressive', 'Premium', 'Premium Plus'],
            'Sprinter': ['Cargo Van', 'Passenger Van', 'Crew Van', 'AMG Line', 'Progressive', 'Premium', 'Premium Plus'],
            'Metris': ['Cargo Van', 'Passenger Van', 'AMG Line', 'Progressive', 'Premium', 'Premium Plus'],
            'EQV': ['300', 'AMG Line', 'Progressive', 'Premium', 'Premium Plus'],
            'EQC': ['300', '400', 'AMG Line', 'Progressive', 'Premium', 'Premium Plus'],
            'G-Class': ['G 350', 'G 400', 'G 500', 'G 63 AMG', 'G 65 AMG', 'AMG Line', 'Progressive', 'Premium', 'Premium Plus'],
            'GLE Coupe': ['GLE 350', 'GLE 450', 'GLE 53 AMG', 'GLE 63 AMG', 'AMG Line', 'Progressive', 'Premium', 'Premium Plus'],
            'GLS': ['GLS 450', 'GLS 580', 'GLS 63 AMG', 'AMG Line', 'Progressive', 'Premium', 'Premium Plus'],
            'Maybach': ['S 580', 'S 680', 'GLS 600', 'AMG Line', 'Progressive', 'Premium', 'Premium Plus'],
            'AMG GT Black Series': ['Base', 'AMG Line', 'Progressive', 'Premium', 'Premium Plus'],
            'AMG GT 63 S E': ['Base', 'AMG Line', 'Progressive', 'Premium', 'Premium Plus']
        },
        'bmw': {
            '1 Series': ['116i', '118i', '120i', 'M135i', 'M140i', 'Sport', 'M Sport', 'xLine', 'M Performance'],
            '2 Series': ['218i', '220i', '220d', 'M235i', 'M240i', 'M2', 'M2 Competition', 'Sport', 'M Sport', 'xLine', 'M Performance'],
            '3 Series': ['318i', '320i', '330i', '330e', 'M340i', 'M3', 'M3 Competition', 'Sport', 'M Sport', 'xLine', 'M Performance'],
            '4 Series': ['420i', '430i', '440i', 'M440i', 'M4', 'M4 Competition', 'Sport', 'M Sport', 'xLine', 'M Performance'],
            '5 Series': ['520i', '520d', '530i', '530d', '530e', '540i', 'M550i', 'M5', 'M5 Competition', 'Sport', 'M Sport', 'xLine', 'M Performance'],
            '6 Series': ['630i', '640i', 'M6', 'M6 Competition', 'Sport', 'M Sport', 'xLine', 'M Performance'],
            '7 Series': ['730d', '740i', '740d', '750i', 'M760i', 'Alpina B7', 'Sport', 'M Sport', 'xLine', 'M Performance'],
            '8 Series': ['840i', '850i', 'M8', 'M8 Competition', 'Sport', 'M Sport', 'xLine', 'M Performance'],
            'X1': ['sDrive18i', 'sDrive20i', 'xDrive25i', 'xDrive25e', 'Sport', 'M Sport', 'xLine', 'M Performance'],
            'X2': ['sDrive20i', 'xDrive25i', 'M35i', 'Sport', 'M Sport', 'xLine', 'M Performance'],
            'X3': ['xDrive20i', 'xDrive20d', 'xDrive30i', 'xDrive30e', 'M40i', 'X3 M', 'X3 M Competition', 'Sport', 'M Sport', 'xLine', 'M Performance'],
            'X4': ['xDrive20i', 'xDrive30i', 'M40i', 'X4 M', 'X4 M Competition', 'Sport', 'M Sport', 'xLine', 'M Performance'],
            'X5': ['xDrive40i', 'xDrive45e', 'xDrive50i', 'M50i', 'X5 M', 'X5 M Competition', 'Sport', 'M Sport', 'xLine', 'M Performance'],
            'X6': ['xDrive40i', 'xDrive50i', 'M50i', 'X6 M', 'X6 M Competition', 'Sport', 'M Sport', 'xLine', 'M Performance'],
            'X7': ['xDrive40i', 'xDrive50i', 'M50i', 'Sport', 'M Sport', 'xLine', 'M Performance'],
            'Z4': ['sDrive20i', 'sDrive30i', 'M40i', 'Sport', 'M Sport', 'xLine', 'M Performance'],
            'i3': ['i3', 'i3s', 'Sport', 'M Sport', 'xLine', 'M Performance'],
            'i4': ['eDrive40', 'M50', 'Sport', 'M Sport', 'xLine', 'M Performance'],
            'iX': ['xDrive40', 'xDrive50', 'M60', 'Sport', 'M Sport', 'xLine', 'M Performance'],
            'M2': ['M2', 'M2 Competition', 'Sport', 'M Sport', 'xLine', 'M Performance'],
            'M3': ['M3', 'M3 Competition', 'Sport', 'M Sport', 'xLine', 'M Performance'],
            'M4': ['M4', 'M4 Competition', 'Sport', 'M Sport', 'xLine', 'M Performance'],
            'M5': ['M5', 'M5 Competition', 'Sport', 'M Sport', 'xLine', 'M Performance'],
            'M8': ['M8', 'M8 Competition', 'Sport', 'M Sport', 'xLine', 'M Performance'],
            'i7': ['xDrive60', 'M70', 'Sport', 'M Sport', 'xLine', 'M Performance'],
            'X3 M': ['X3 M', 'X3 M Competition', 'Sport', 'M Sport', 'xLine', 'M Performance'],
            'X4 M': ['X4 M', 'X4 M Competition', 'Sport', 'M Sport', 'xLine', 'M Performance'],
            'X5 M': ['X5 M', 'X5 M Competition', 'Sport', 'M Sport', 'xLine', 'M Performance'],
            'X6 M': ['X6 M', 'X6 M Competition', 'Sport', 'M Sport', 'xLine', 'M Performance'],
            'i5': ['eDrive40', 'xDrive40', 'M60', 'Sport', 'M Sport', 'xLine', 'M Performance'],
            'iX1': ['xDrive30', 'Sport', 'M Sport', 'xLine', 'M Performance'],
            'iX3': ['xDrive30', 'Sport', 'M Sport', 'xLine', 'M Performance'],
            'XM': ['Base', 'Label Red', 'Sport', 'M Sport', 'xLine', 'M Performance']
        },
        'audi': {
            'A3': ['30 TDI', '35 TFSI', '40 TFSI', 'S3', 'RS3', 'Sport', 'S line', 'Black Edition', 'Vorsprung'],
            'A4': ['30 TDI', '35 TDI', '40 TDI', '40 TFSI', '45 TFSI', 'S4', 'RS4', 'Sport', 'S line', 'Black Edition', 'Vorsprung'],
            'A5': ['35 TDI', '40 TDI', '40 TFSI', '45 TFSI', 'S5', 'RS5', 'Sport', 'S line', 'Black Edition', 'Vorsprung'],
            'A6': ['40 TDI', '45 TDI', '45 TFSI', '50 TDI', '55 TFSI', 'S6', 'RS6', 'Sport', 'S line', 'Black Edition', 'Vorsprung'],
            'A7': ['40 TDI', '45 TDI', '45 TFSI', '50 TDI', '55 TFSI', 'S7', 'RS7', 'Sport', 'S line', 'Black Edition', 'Vorsprung'],
            'A8': ['50 TDI', '55 TFSI', '60 TFSI', 'S8', 'Sport', 'S line', 'Black Edition', 'Vorsprung'],
            'Q3': ['30 TDI', '35 TFSI', '40 TFSI', 'RS Q3', 'Sport', 'S line', 'Black Edition', 'Vorsprung'],
            'Q5': ['40 TDI', '45 TDI', '45 TFSI', '50 TDI', '55 TFSI', 'SQ5', 'RS Q5', 'Sport', 'S line', 'Black Edition', 'Vorsprung'],
            'Q7': ['45 TDI', '50 TDI', '55 TFSI', 'SQ7', 'RS Q7', 'Sport', 'S line', 'Black Edition', 'Vorsprung'],
            'Q8': ['50 TDI', '55 TFSI', 'SQ8', 'RS Q8', 'Sport', 'S line', 'Black Edition', 'Vorsprung'],
            'e-tron': ['50', '55', 'S', 'Sport', 'S line', 'Black Edition', 'Vorsprung'],
            'e-tron GT': ['e-tron GT', 'RS e-tron GT', 'Sport', 'S line', 'Black Edition', 'Vorsprung'],
            'TT': ['40 TFSI', '45 TFSI', 'TTS', 'TT RS', 'Sport', 'S line', 'Black Edition', 'Vorsprung'],
            'R8': ['R8', 'R8 Spyder', 'R8 V10', 'R8 V10 Spyder', 'Sport', 'S line', 'Black Edition', 'Vorsprung'],
            'RS3': ['RS3', 'RS3 Sportback', 'Sport', 'S line', 'Black Edition', 'Vorsprung'],
            'RS4': ['RS4', 'RS4 Avant', 'Sport', 'S line', 'Black Edition', 'Vorsprung'],
            'RS5': ['RS5', 'RS5 Sportback', 'RS5 Coupe', 'Sport', 'S line', 'Black Edition', 'Vorsprung'],
            'RS6': ['RS6', 'RS6 Avant', 'Sport', 'S line', 'Black Edition', 'Vorsprung'],
            'RS7': ['RS7', 'RS7 Sportback', 'Sport', 'S line', 'Black Edition', 'Vorsprung'],
            'RS Q8': ['RS Q8', 'Sport', 'S line', 'Black Edition', 'Vorsprung'],
            'Q4 e-tron': ['35', '40', '45', '50', 'Sport', 'S line', 'Black Edition', 'Vorsprung'],
            'Q5 e-tron': ['40', '50', 'Sport', 'S line', 'Black Edition', 'Vorsprung'],
            'A1': ['30 TFSI', '35 TFSI', '40 TFSI', 'Sport', 'S line', 'Black Edition', 'Vorsprung'],
            'A2': ['e-tron', 'Sport', 'S line', 'Black Edition', 'Vorsprung'],
            'A3 Sportback e-tron': ['Base', 'Sport', 'S line', 'Black Edition', 'Vorsprung'],
            'Q2': ['30 TFSI', '35 TFSI', '40 TFSI', 'Sport', 'S line', 'Black Edition', 'Vorsprung'],
            'Q3 Sportback': ['35 TFSI', '40 TFSI', '45 TFSI', 'Sport', 'S line', 'Black Edition', 'Vorsprung'],
            'Q7': ['45 TFSI', '55 TFSI', 'SQ7', 'Sport', 'S line', 'Black Edition', 'Vorsprung'],
            'Q8': ['45 TFSI', '55 TFSI', 'SQ8', 'RS Q8', 'Sport', 'S line', 'Black Edition', 'Vorsprung'],
            'e-tron S': ['Base', 'Sport', 'S line', 'Black Edition', 'Vorsprung'],
            'e-tron S Sportback': ['Base', 'Sport', 'S line', 'Black Edition', 'Vorsprung']
        },
        'toyota': {
            '4Runner': ['SR5', 'TRD Off-Road', 'TRD Pro', 'Limited', 'Platinum', 'Nightshade', 'Trail Special Edition', 'SR5 Premium', 'TRD Sport'],
            '86': ['GT', 'GT Black', 'GR86', 'Limited', 'Premium', 'Special Edition'],
            'Avalon': ['XLE', 'XSE', 'Limited', 'Touring', 'Nightshade', 'Platinum', 'TRD'],
            'Aygo': ['X', 'X-Cite', 'X-Play', 'Special Edition'],
            'Auris': ['Icon', 'Design', 'Excel', 'Special Edition'],
            'C-HR': ['Icon', 'Design', 'Excel', 'Special Edition'],
            'Camry': ['L', 'LE', 'SE', 'XLE', 'XSE', 'TRD', 'Nightshade', 'Platinum', 'Hybrid LE', 'Hybrid SE', 'Hybrid XLE', 'Hybrid XSE'],
            'Camry Hybrid': ['LE', 'SE', 'XLE', 'XSE', 'Special Edition'],
            'Corolla': ['L', 'LE', 'SE', 'XLE', 'XSE', 'Nightshade', 'Apex', 'GR Corolla', 'Hybrid LE', 'Hybrid SE', 'Hybrid XLE'],
            'Corolla Cross': ['L', 'LE', 'XLE', 'Special Edition'],
            'Corolla Hybrid': ['LE', 'SE', 'XLE', 'Special Edition'],
            'Crown': ['XLE', 'Limited', 'Platinum', 'Nightshade', 'Special Edition'],
            'GR86': ['Base', 'Premium', 'Limited', 'Special Edition'],
            'GR Corolla': ['Core', 'Circuit', 'Morizo', 'Premium', 'Special Edition'],
            'GR Supra': ['2.0', '3.0', '3.0 Premium', 'A91-MT', 'A91-CF', 'Special Edition'],
            'Highlander': ['L', 'LE', 'XLE', 'Limited', 'Platinum', 'Hybrid LE', 'Hybrid XLE', 'Hybrid Limited', 'Hybrid Platinum', 'Nightshade'],
            'Highlander Hybrid': ['LE', 'XLE', 'Limited', 'Platinum', 'Special Edition'],
            'Land Cruiser': ['GX', 'VX', 'VX-R', 'Special Edition'],
            'Mirai': ['XLE', 'Limited', 'Special Edition'],
            'Prius': ['L', 'LE', 'XLE', 'Limited', 'Nightshade', 'Special Edition'],
            'Prius c': ['One', 'Two', 'Three', 'Four', 'Special Edition'],
            'Prius v': ['Two', 'Three', 'Four', 'Five', 'Special Edition'],
            'RAV4': ['LE', 'XLE', 'XLE Premium', 'Adventure', 'TRD Off-Road', 'Limited', 'Platinum', 'Prime XSE', 'Prime SE', 'Nightshade'],
            'RAV4 Hybrid': ['LE', 'XLE', 'Limited', 'Platinum', 'Special Edition'],
            'Sequoia': ['SR5', 'Limited', 'Platinum', 'TRD Pro', 'Special Edition'],
            'Sienna': ['LE', 'XLE', 'Limited', 'Platinum', 'Special Edition'],
            'Supra': ['2.0', '3.0', '3.0 Premium', 'A91-MT', 'A91-CF', 'Special Edition'],
            'Tacoma': ['SR', 'SR5', 'TRD Sport', 'TRD Off-Road', 'Limited', 'TRD Pro', 'Special Edition'],
            'Tundra': ['SR', 'SR5', 'Limited', 'Platinum', 'TRD Pro', 'Capstone', 'Nightshade'],
            'Venza': ['LE', 'XLE', 'Limited', 'Special Edition'],
            'Yaris': ['L', 'LE', 'XLE', 'Nightshade', 'Special Edition'],
            'Yaris iA': ['L', 'LE', 'XLE', 'Special Edition'],
            'Century': ['Standard', 'Special Edition'],
            'GR Corolla': ['Core', 'Circuit', 'Morizo', 'Premium', 'Special Edition']
        },
        'volkswagen': {
            'Arteon': ['SE', 'SEL', 'SEL R-Line', 'SEL Premium R-Line', 'Sport', 'Exclusive', 'First Edition'],
            'Atlas': ['S', 'SE', 'SEL', 'R-Line', 'SEL Premium', 'SEL Premium R-Line', 'Cross Sport', 'Nightshade'],
            'Atlas Cross Sport': ['S', 'SE', 'SEL', 'R-Line', 'SEL Premium', 'SEL Premium R-Line', 'Nightshade'],
            'Golf': ['S', 'SE', 'SEL', 'R', 'GTI', 'GTI Autobahn', 'R-Line', 'Sport', 'Exclusive'],
            'Golf GTI': ['S', 'SE', 'Autobahn', 'Sport', 'Exclusive', 'First Edition'],
            'Golf R': ['Base', 'Special Edition', 'First Edition'],
            'ID.4': ['Pro', 'Pro S', 'AWD Pro', 'AWD Pro S', 'First Edition', 'Special Edition'],
            'ID.5': ['Pro', 'Pro S', 'Sport', 'Exclusive'],
            'Jetta': ['S', 'SE', 'SEL', 'GLI', 'GLI Autobahn', 'Sport', 'Exclusive'],
            'Jetta GLI': ['S', 'Autobahn', 'Sport', 'Exclusive'],
            'Passat': ['S', 'SE', 'SEL', 'R-Line', 'GT', 'Limited Edition', 'Sport', 'Exclusive'],
            'Taos': ['S', 'SE', 'SEL', 'SEL R-Line', 'Sport', 'Exclusive'],
            'Tiguan': ['S', 'SE', 'SEL', 'R-Line', 'SEL Premium', 'SEL Premium R-Line', 'Sport', 'Exclusive'],
            'Tiguan R': ['Base', 'Sport', 'Exclusive'],
            'Tiguan Allspace': ['S', 'SE', 'SEL', 'R-Line', 'SEL Premium', 'SEL Premium R-Line', 'Sport', 'Exclusive'],
            'T-Roc': ['S', 'SE', 'SEL', 'R-Line', 'Sport', 'Exclusive'],
            'T-Roc R': ['Base', 'Sport', 'Exclusive'],
            'T-Cross': ['S', 'SE', 'SEL', 'R-Line', 'Sport', 'Exclusive'],
            'Virtus': ['Comfortline', 'Highline', 'GT', 'Special Edition'],
            'Polo': ['Trendline', 'Comfortline', 'Highline', 'GT', 'Special Edition'],
            'Virtus GT': ['Base', 'Special Edition'],
            'Virtus GTS': ['Base', 'Special Edition'],
            'Virtus Highline': ['Base', 'Special Edition'],
            'Virtus Comfortline': ['Base', 'Special Edition'],
            'Virtus Trendline': ['Base', 'Special Edition'],
            'Arteon': ['SE', 'SEL', 'SEL R-Line', 'Sport', 'Exclusive'],
            'Atlas Cross Sport': ['S', 'SE', 'SEL', 'SEL R-Line', 'Sport', 'Exclusive'],
            'Golf Alltrack': ['S', 'SE', 'SEL', 'Sport', 'Exclusive'],
            'Golf SportWagen': ['S', 'SE', 'SEL', 'Sport', 'Exclusive']
        },
        'honda': {
            'Accord': ['LX', 'Sport', 'EX', 'EX-L', 'Touring', 'Sport 2.0T', 'Hybrid', 'Special Edition'],
            'Accord Hybrid': ['Sport', 'EX-L', 'Touring', 'Special Edition'],
            'Civic': ['LX', 'Sport', 'EX', 'EX-L', 'Touring', 'Type R', 'Si', 'Sport Touring', 'Special Edition'],
            'CR-V': ['LX', 'EX', 'EX-L', 'Touring', 'Hybrid', 'Hybrid EX', 'Hybrid EX-L', 'Hybrid Touring', 'Special Edition'],
            'HR-V': ['LX', 'Sport', 'EX', 'EX-L', 'Touring', 'Special Edition'],
            'Insight': ['LX', 'EX', 'Touring', 'Special Edition'],
            'Odyssey': ['LX', 'EX', 'EX-L', 'Touring', 'Elite', 'Special Edition'],
            'Passport': ['Sport', 'EX-L', 'TrailSport', 'Elite', 'Special Edition'],
            'Pilot': ['LX', 'EX', 'EX-L', 'Touring', 'Elite', 'Black Edition', 'TrailSport', 'Special Edition'],
            'Ridgeline': ['Sport', 'RTL', 'RTL-E', 'Black Edition', 'Special Edition'],
            'Clarity': ['Base', 'Touring', 'Special Edition'],
            'Clarity Fuel Cell': ['Base', 'Special Edition'],
            'Fit': ['LX', 'Sport', 'EX', 'EX-L', 'Special Edition'],
            'Prelude': ['Base', 'Si', 'Special Edition'],
            'S2000': ['Base', 'Special Edition'],
            'NSX': ['Base', 'Type S', 'Special Edition'],
            'Element': ['LX', 'EX', 'Special Edition'],
            'Crosstour': ['EX', 'EX-L', 'Special Edition'],
            'CR-Z': ['Base', 'EX', 'Special Edition'],
            'Integra': ['Base', 'Type S', 'Special Edition'],
            'Legend': ['Base', 'Special Edition'],
            'S660': ['Base', 'Special Edition'],
            'ZR-V': ['LX', 'EX', 'Special Edition'],
            'e:N1': ['Base', 'Special Edition'],
            'e:N2': ['Base', 'Special Edition'],
            'e:NS1': ['Base', 'Special Edition'],
            'e:NP1': ['Base', 'Special Edition']
        },
        'nissan': {
            '370Z': ['Sport', 'Touring', 'Nismo', 'Special Edition'],
            'Altima': ['S', 'SV', 'SR', 'SL', 'Platinum', 'Special Edition'],
            'Ariya': ['Engage', 'Venture+', 'Evolve+', 'Premiere', 'Special Edition'],
            'Frontier': ['S', 'SV', 'Pro-4X', 'Pro-X', 'SL', 'Special Edition'],
            'GT-R': ['Premium', 'NISMO', 'Special Edition'],
            'Kicks': ['S', 'SV', 'SR', 'Special Edition'],
            'Leaf': ['S', 'SV', 'SV Plus', 'SL Plus', 'Special Edition'],
            'Maxima': ['S', 'SV', 'SL', 'Platinum', 'Special Edition'],
            'Murano': ['S', 'SV', 'SL', 'Platinum', 'Special Edition'],
            'Pathfinder': ['S', 'SV', 'SL', 'Platinum', 'Special Edition'],
            'Rogue': ['S', 'SV', 'SL', 'Platinum', 'Special Edition'],
            'Rogue Sport': ['S', 'SV', 'SL', 'Special Edition'],
            'Sentra': ['S', 'SV', 'SR', 'SL', 'Special Edition']
        },
        'ford': {
            'Bronco': ['Base', 'Big Bend', 'Black Diamond', 'Outer Banks', 'Badlands', 'Wildtrak', 'Special Edition'],
            'Bronco Sport': ['Base', 'Big Bend', 'Outer Banks', 'Badlands', 'Special Edition'],
            'Escape': ['S', 'SE', 'SEL', 'Titanium', 'Special Edition'],
            'Edge': ['SE', 'SEL', 'ST-Line', 'ST', 'Titanium', 'Special Edition'],
            'Expedition': ['XLT', 'Limited', 'Platinum', 'Timberline', 'Special Edition'],
            'Explorer': ['XLT', 'Limited', 'Platinum', 'ST', 'Timberline', 'Special Edition'],
            'F-150': ['XL', 'XLT', 'Lariat', 'King Ranch', 'Platinum', 'Limited', 'Raptor', 'Tremor', 'Lightning', 'Special Edition'],
            'F-150 Lightning': ['Pro', 'XLT', 'Lariat', 'Platinum', 'Special Edition'],
            'Mach-E': ['Select', 'Premium', 'California Route 1', 'GT', 'Special Edition'],
            'Maverick': ['XL', 'XLT', 'Lariat', 'Special Edition']
        },
        'chevrolet': {
            'Blazer': ['1LT', '2LT', '3LT', 'RS', 'Premier', 'Special Edition'],
            'Bolt EV': ['LT', 'Premier', 'Special Edition'],
            'Bolt EUV': ['LT', 'Premier', 'Special Edition'],
            'Camaro': ['1LS', '1LT', '2LT', '3LT', '1SS', '2SS', 'ZL1', 'ZL1 1LE', 'Special Edition'],
            'Colorado': ['WT', 'LT', 'Z71', 'ZR2', 'Special Edition'],
            'Corvette': ['1LT', '2LT', '3LT', 'Z06', 'Special Edition'],
            'Equinox': ['L', 'LS', 'LT', 'RS', 'Premier', 'Special Edition'],
            'Malibu': ['L', 'LS', 'RS', 'LT', 'Premier', 'Special Edition'],
            'Silverado': ['WT', 'Custom', 'LT', 'RST', 'High Country', 'Z71', 'Special Edition'],
            'Suburban': ['LS', 'LT', 'RST', 'Premier', 'High Country', 'Z71', 'Special Edition']
        },
        'hyundai': {
            'Elantra': ['SE', 'SEL', 'Limited', 'N Line', 'Special Edition'],
            'Elantra Hybrid': ['Blue', 'SEL', 'Limited', 'Special Edition'],
            'Ioniq 5': ['SE', 'SEL', 'Limited', 'Special Edition'],
            'Ioniq 6': ['SE', 'SEL', 'Limited', 'Special Edition'],
            'Kona': ['SE', 'SEL', 'Limited', 'N Line', 'Special Edition'],
            'Kona Electric': ['SE', 'SEL', 'Limited', 'Special Edition'],
            'Nexo': ['Blue', 'Limited', 'Special Edition'],
            'Palisade': ['SE', 'SEL', 'Limited', 'Calligraphy', 'Special Edition'],
            'Santa Cruz': ['SE', 'SEL', 'Limited', 'Special Edition'],
            'Santa Fe': ['SE', 'SEL', 'Limited', 'Calligraphy', 'Special Edition'],
            'Sonata': ['SE', 'SEL', 'Limited', 'N Line', 'Special Edition'],
            'Sonata Hybrid': ['Blue', 'SEL', 'Limited', 'Special Edition']
        },
        'kia': {
            'Carnival': ['LX', 'EX', 'SX', 'SX Prestige', 'Special Edition'],
            'EV6': ['Light', 'Wind', 'GT-Line', 'GT', 'Special Edition'],
            'Forte': ['FE', 'LX', 'GT-Line', 'GT', 'Special Edition'],
            'K5': ['LX', 'LXS', 'GT-Line', 'GT', 'Special Edition'],
            'Rio': ['LX', 'S', 'EX', 'Special Edition'],
            'Seltos': ['LX', 'S', 'EX', 'SX', 'Special Edition'],
            'Sorento': ['LX', 'S', 'EX', 'SX', 'SX Prestige', 'X-Line', 'Special Edition'],
            'Soul': ['LX', 'S', 'EX', 'GT-Line', 'Special Edition'],
            'Soul EV': ['Light', 'Wind', 'GT-Line', 'Special Edition'],
            'Sportage': ['LX', 'EX', 'SX', 'SX Prestige', 'X-Line', 'X-Pro', 'Special Edition']
        },
        'lexus': {
            'ES': ['250', '300h', '350', 'F Sport', 'Luxury', 'Special Edition'],
            'GX': ['460', 'Luxury', 'Special Edition'],
            'IS': ['300', '350', '500', 'F Sport', 'Luxury', 'Special Edition'],
            'LC': ['500', '500h', 'F Sport', 'Special Edition'],
            'LS': ['500', '500h', 'F Sport', 'Special Edition'],
            'LX': ['600', 'Luxury', 'Special Edition'],
            'NX': ['250', '350', '350h', '450h+', 'F Sport', 'Luxury', 'Special Edition'],
            'RC': ['300', '350', '500', 'F Sport', 'Luxury', 'Special Edition'],
            'RC F': ['Base', 'Track Edition', 'Special Edition'],
            'RX': ['350', '350L', '450h', '450hL', 'F Sport', 'Luxury', 'Special Edition'],
            'RZ': ['450e', '450e Luxury', 'Special Edition'],
            'UX': ['200', '250h', 'F Sport', 'Special Edition'],
            'GS': ['300', '350', 'F Sport', 'Special Edition'],
            'CT': ['200h', 'F Sport', 'Special Edition'],
            'HS': ['250h', 'Special Edition'],
            'IS F': ['Base', 'Special Edition'],
            'LFA': ['Base', 'Special Edition'],
            'SC': ['Base', 'Special Edition']
        },
        'porsche': {
            '911': ['Carrera', 'Carrera S', 'Carrera 4', 'Carrera 4S', 'Targa 4', 'Targa 4S', 'Turbo', 'Turbo S', 'GT3', 'GT3 RS', 'Special Edition'],
            'Cayenne': ['Base', 'S', 'GTS', 'Turbo', 'Turbo S', 'Special Edition'],
            'Macan': ['Base', 'S', 'GTS', 'Turbo', 'Special Edition'],
            'Panamera': ['Base', '4', '4S', 'GTS', 'Turbo', 'Turbo S', 'Special Edition'],
            'Taycan': ['4', '4S', 'Turbo', 'Turbo S', 'GTS', 'Special Edition']
        },
        'acura': {
            'ILX': ['Base', 'Premium', 'A-Spec'],
            'MDX': ['Base', 'Technology', 'A-Spec', 'Advance'],
            'RDX': ['Base', 'Technology', 'A-Spec', 'Advance'],
            'TLX': ['Base', 'Technology', 'A-Spec', 'Advance', 'Type S'],
            'NSX': ['Base', 'Type S']
        },
        'infiniti': {
            'Q50': ['Pure', 'Luxe', 'Sport', 'Red Sport 400'],
            'Q60': ['Pure', 'Luxe', 'Sport', 'Red Sport 400'],
            'QX50': ['Pure', 'Luxe', 'Essential', 'Sensory', 'Autograph'],
            'QX60': ['Pure', 'Luxe', 'Sensory', 'Autograph'],
            'QX80': ['Luxe', 'Premium Select', 'Sensory']
        },
        'tesla': {
            'Model S': ['Long Range', 'Plaid'],
            'Model 3': ['Standard Range Plus', 'Long Range', 'Performance'],
            'Model X': ['Long Range', 'Plaid'],
            'Model Y': ['Long Range', 'Performance'],
            'Roadster': ['Base'],
            'Cybertruck': ['Single Motor', 'Dual Motor', 'Tri Motor']
        },
        'genesis': {
            'G70': ['2.0T', '3.3T', 'Sport'],
            'G80': ['2.5T', '3.5T', 'Sport'],
            'G90': ['3.3T', '5.0 Ultimate'],
            'GV70': ['2.5T', '3.5T'],
            'GV80': ['2.5T', '3.5T']
        },
        'ram': {
            '1500': ['Tradesman', 'Big Horn', 'Laramie', 'Rebel', 'Limited'],
            '2500': ['Tradesman', 'Big Horn', 'Laramie', 'Power Wagon', 'Limited'],
            '3500': ['Tradesman', 'Big Horn', 'Laramie', 'Limited'],
            'ProMaster': ['1500', '2500', '3500']
        },
        'gmc': {
            'Sierra': ['Base', 'SLE', 'SLT', 'Denali'],
            'Canyon': ['Base', 'SLE', 'SLT', 'Denali'],
            'Yukon': ['SLE', 'SLT', 'Denali'],
            'Acadia': ['SL', 'SLE', 'SLT', 'Denali'],
            'Terrain': ['SL', 'SLE', 'SLT', 'Denali']
        },
        'buick': {
            'Encore': ['Preferred', 'Sport Touring', 'Essence'],
            'Enclave': ['Preferred', 'Essence', 'Premium', 'Avenir'],
            'Envision': ['Preferred', 'Essence', 'Avenir'],
            'Regal': ['Base', 'Preferred', 'Essence', 'Avenir'],
            'LaCrosse': ['Base', 'Preferred', 'Essence', 'Avenir']
        },
        'cadillac': {
            'CT4': ['Luxury', 'Premium Luxury', 'Sport', 'V-Series'],
            'CT5': ['Luxury', 'Premium Luxury', 'Sport', 'V-Series'],
            'Escalade': ['Luxury', 'Premium Luxury', 'Sport', 'Platinum'],
            'XT4': ['Luxury', 'Premium Luxury', 'Sport'],
            'XT5': ['Luxury', 'Premium Luxury', 'Sport'],
            'XT6': ['Luxury', 'Premium Luxury', 'Sport', 'Platinum']
        },
        'lincoln': {
            'Aviator': ['Standard', 'Reserve', 'Black Label'],
            'Corsair': ['Standard', 'Reserve', 'Grand Touring'],
            'Nautilus': ['Standard', 'Reserve', 'Black Label'],
            'Navigator': ['Standard', 'Reserve', 'Black Label'],
            'MKZ': ['Standard', 'Reserve', 'Black Label']
        },
        'peugeot': {
            '208': ['Active', 'Allure', 'GT'],
            '308': ['Active', 'Allure', 'GT'],
            '508': ['Active', 'Allure', 'GT'],
            '2008': ['Active', 'Allure', 'GT'],
            '3008': ['Active', 'Allure', 'GT'],
            '5008': ['Active', 'Allure', 'GT']
        },
        'citroen': {
            'C3': ['Feel', 'Shine', 'Shine Plus'],
            'C4': ['Feel', 'Shine', 'Shine Plus'],
            'C5 Aircross': ['Feel', 'Shine', 'Shine Plus'],
            'Berlingo': ['Feel', 'Shine', 'Shine Plus']
        },
        'chery': {
            'Tiggo 2': ['Comfort', 'Luxury'],
            'Tiggo 4': ['Comfort', 'Luxury'],
            'Tiggo 7': ['Comfort', 'Luxury'],
            'Arrizo 5': ['Comfort', 'Luxury']
        },
        'byd': {
            'Han': ['EV', 'DM'],
            'Tang': ['EV', 'DM'],
            'Song': ['EV', 'DM'],
            'Qin': ['EV', 'DM'],
            'Yuan': ['EV', 'DM']
        },
        'great-wall': {
            'Haval H6': ['Base', 'Deluxe'],
            'Wingle 7': ['Base', 'Deluxe'],
            'Poer': ['Base', 'Deluxe']
        },
        'faw': {
            'Bestune T77': ['Comfort', 'Deluxe'],
            'Hongqi H9': ['Comfort', 'Deluxe'],
            'Junpai A50': ['Comfort', 'Deluxe']
        },
        'roewe': {
            'RX5': ['Base', 'Deluxe'],
            'i5': ['Base', 'Deluxe'],
            'Ei5': ['Base', 'Deluxe']
        },
        'polestar': {
            'Polestar 1': ['Base'],
            'Polestar 2': ['Long Range', 'Performance'],
            'Polestar 3': ['Base']
        },
        'rivian': {
            'R1T': ['Explore', 'Adventure'],
            'R1S': ['Explore', 'Adventure']
        },
        'lucid': {
            'Air': ['Pure', 'Touring', 'Grand Touring', 'Dream Edition'],
            'Gravity': ['Pure', 'Touring', 'Grand Touring']
        },
        'dacia': {
            'Sandero': ['Access', 'Essential', 'Comfort'],
            'Duster': ['Access', 'Essential', 'Comfort'],
            'Logan': ['Access', 'Essential', 'Comfort']
        },
        'seat': {
            'Ibiza': ['Reference', 'Style', 'FR'],
            'Leon': ['Reference', 'Style', 'FR'],
            'Ateca': ['Reference', 'Style', 'FR'],
            'Arona': ['Reference', 'Style', 'FR']
        },
        'skoda': {
            'Octavia': ['Active', 'Ambition', 'Style'],
            'Superb': ['Active', 'Ambition', 'Style'],
            'Kodiaq': ['Active', 'Ambition', 'Style'],
            'Kamiq': ['Active', 'Ambition', 'Style']
        },
        'proton': {
            'Saga': ['Standard', 'Premium'],
            'Persona': ['Standard', 'Premium'],
            'X70': ['Standard', 'Premium']
        },
        'perodua': {
            'Myvi': ['G', 'X', 'H', 'AV'],
            'Axia': ['E', 'G', 'SE', 'AV'],
            'Bezza': ['G', 'X', 'Premium']
        },
        'tata': {
            'Tiago': ['XE', 'XM', 'XT', 'XZ'],
            'Nexon': ['XE', 'XM', 'XT', 'XZ'],
            'Harrier': ['XE', 'XM', 'XT', 'XZ']
        },
        'mahindra': {
            'XUV700': ['MX', 'AX3', 'AX5', 'AX7'],
            'Scorpio': ['S3', 'S5', 'S7', 'S9', 'S11'],
            'Thar': ['AX', 'LX']
        },
        'lada': {
            'Vesta': ['Classic', 'Comfort', 'Luxe'],
            'Granta': ['Classic', 'Comfort', 'Luxe'],
            'Niva': ['Classic', 'Comfort', 'Luxe']
        },
        'zaz': {
            'Sens': ['Base'],
            'Vida': ['Base']
        },
        'daewoo': {
            'Lanos': ['S', 'SE', 'SX'],
            'Nubira': ['SX', 'CDX'],
            'Matiz': ['S', 'SE', 'SX']
        },
        'ssangyong': {
            'Tivoli': ['SE', 'ELX', 'Ultimate'],
            'Rexton': ['SE', 'ELX', 'Ultimate'],
            'Korando': ['SE', 'ELX', 'Ultimate']
        },
        'changan': {
            'CS35': ['Comfort', 'Luxury'],
            'CS55': ['Comfort', 'Luxury'],
            'Eado': ['Comfort', 'Luxury']
        },
        'haval': {
            'H2': ['Standard', 'Deluxe'],
            'H6': ['Standard', 'Deluxe'],
            'H9': ['Standard', 'Deluxe']
        },
        'wuling': {
            'Hongguang': ['Base', 'Deluxe'],
            'Victory': ['Base', 'Deluxe']
        },
        'baojun': {
            '510': ['Base', 'Deluxe'],
            '530': ['Base', 'Deluxe'],
            'RS-5': ['Base', 'Deluxe']
        },
        'nio': {
            'ES6': ['Standard', 'Performance'],
            'ES8': ['Standard', 'Performance'],
            'EC6': ['Standard', 'Performance'],
            'ET7': ['Standard', 'Performance']
        },
        'xpeng': {
            'P7': ['Standard', 'Performance'],
            'G3': ['Standard', 'Performance'],
            'G9': ['Standard', 'Performance']
        },
        'li-auto': {
            'Li ONE': ['Base', 'Pro'],
            'L9': ['Base', 'Pro']
        },
        'vinfast': {
            'Lux A2.0': ['Standard', 'Plus'],
            'Lux SA2.0': ['Standard', 'Plus'],
            'VF e34': ['Standard', 'Plus']
        }
    }
    
    # Get trims for the specified brand and model, or return empty list if not found
    return jsonify(trim_levels.get(brand, {}).get(model, []))

def populate_car_models():
    # Common car models by brand, ordered from most famous to least famous
    car_models = {
        # Tier 1: Global Luxury & Premium Brands
        'mercedes-benz': [
            'A-Class', 'B-Class', 'C-Class', 'CLA', 'CLS', 'E-Class', 'S-Class',
            'GLA', 'GLB', 'GLC', 'GLE', 'GLS', 'G-Class', 'AMG GT', 'EQC',
            'SL', 'SLC', 'V-Class', 'Sprinter', 'Metris', 'AMG GT 4-Door',
            'EQS', 'EQE', 'EQB', 'EQA'
        ],
        'bmw': [
            '1 Series', '2 Series', '3 Series', '4 Series', '5 Series', '6 Series',
            '7 Series', '8 Series', 'X1', 'X2', 'X3', 'X4', 'X5', 'X6', 'X7',
            'Z4', 'i3', 'i4', 'i7', 'iX', 'M2', 'M3', 'M4', 'M5', 'M8',
            'X3 M', 'X4 M', 'X5 M', 'X6 M'
        ],
        'audi': [
            'A3', 'A4', 'A5', 'A6', 'A7', 'A8', 'Q3', 'Q5', 'Q7', 'Q8',
            'e-tron', 'e-tron GT', 'RS3', 'RS4', 'RS5', 'RS6', 'RS7', 'RS Q8',
            'S3', 'S4', 'S5', 'S6', 'S7', 'S8', 'SQ5', 'SQ7', 'SQ8',
            'TT', 'R8', 'Q4 e-tron', 'Q5 e-tron'
        ],
        'toyota': [
            '4Runner', 'Alphard', 'Avalon', 'Belta', 'bZ3', 'bZ4X', 'Camry',
            'Celica', 'C-HR', 'Coaster', 'Corolla', 'Corolla Cross', 'Crown',
            'Dyna', 'Etios', 'FJ Cruiser', 'Grand Highlander', 'GR Supra', 'GR86',
            'HiAce', 'Highlander', 'Hilux', 'Land Cruiser', 'Land Cruiser Prado',
            'Land Cruiser 70', 'LiteAce', 'Mega Cruiser', 'Mirai', 'MR2', 'Noah',
            'Paseo', 'Platz', 'Previa', 'Prius', 'Prius Prime', 'ProAce',
            'ProAce City', 'RAV4', 'RAV4 Prime', 'Raize', 'Rush', 'Sequoia',
            'Sienna', 'Soarer', 'Stout', 'Supra', 'Tacoma', 'T100', 'Tundra',
            'TownAce', 'Urban Cruiser', 'Vellfire', 'Venza', 'Vios', 'Voxy',
            'Yaris', 'Yaris iA', 'Century', 'GR Corolla'
        ],
        'volkswagen': [
            'Arteon', 'Atlas', 'Atlas Cross Sport', 'Golf', 'Golf GTI', 'Golf R',
            'ID.4', 'ID.Buzz', 'Jetta', 'Passat', 'Taos', 'Tiguan', 'Tiguan Allspace',
            'T-Roc', 'T-Cross', 'Virtus', 'Polo', 'Virtus GT', 'Virtus GTS',
            'Virtus Highline', 'Virtus Comfortline', 'Virtus Trendline'
        ],
        'honda': [
            'Accord', 'Civic', 'CR-V', 'HR-V', 'Insight', 'Odyssey', 'Passport',
            'Pilot', 'Ridgeline', 'Clarity', 'Fit', 'Prelude', 'S2000', 'NSX',
            'Element', 'Crosstour', 'CR-Z', 'Integra', 'Legend', 'S660', 'ZR-V',
            'e:N1', 'e:N2', 'e:NS1', 'e:NP1'
        ],
        'nissan': [
            '370Z', 'Altima', 'Ariya', 'Frontier', 'GT-R', 'Kicks', 'Leaf',
            'Maxima', 'Murano', 'NV200', 'NV Cargo', 'NV Passenger', 'Pathfinder',
            'Rogue', 'Sentra', 'Titan', 'Titan XD', 'Versa', 'Z', 'Armada',
            'Juke', 'X-Trail', 'Sylphy', 'Teana', 'Skyline', 'Fairlady Z'
        ],
        'ford': [
            'Bronco', 'Bronco Sport', 'EcoSport', 'Edge', 'Escape', 'Expedition',
            'Explorer', 'F-150', 'F-250', 'F-350', 'F-450', 'F-550', 'F-650',
            'F-750', 'Fiesta', 'Focus', 'Fusion', 'GT', 'Mach-E', 'Maverick',
            'Mustang', 'Mustang Mach 1', 'Ranger', 'Super Duty', 'Transit',
            'Transit Connect', 'Transit Custom'
        ],
        'chevrolet': [
            'Blazer', 'Bolt EV', 'Bolt EUV', 'Camaro', 'Colorado', 'Corvette',
            'Equinox', 'Express', 'Malibu', 'Silverado', 'Silverado HD', 'Sonic',
            'Spark', 'Suburban', 'Tahoe', 'Trailblazer', 'Traverse', 'Trax',
            'Volt', 'SS', 'Impala', 'Cruze', 'Avalanche', 'HHR', 'Cobalt', 'Aveo'
        ],
        'hyundai': [
            'Accent', 'Elantra', 'Ioniq', 'Ioniq 5', 'Ioniq 6', 'Kona',
            'Kona Electric', 'Nexo', 'Palisade', 'Santa Cruz', 'Santa Fe',
            'Sonata', 'Tucson', 'Veloster', 'Venue', 'Genesis', 'Genesis G70',
            'Genesis G80', 'Genesis G90', 'Genesis GV60', 'Genesis GV70',
            'Genesis GV80', 'Starex', 'Starex H-1', 'Terracan'
        ],
        'kia': [
            'Carnival', 'EV6', 'Forte', 'K5', 'K8', 'K9', 'Niro', 'Niro EV',
            'Niro PHEV', 'Rio', 'Sedona', 'Seltos', 'Sorento', 'Soul',
            'Sportage', 'Stinger', 'Telluride', 'Mohave', 'Bongo', 'Bongo EV',
            'Carens', 'Cerato', 'K3', 'K7', 'Magentis', 'Opirus', 'Picanto',
            'Pride', 'Quoris', 'Ray', 'Sephia', 'Shuma', 'Sorento Prime'
        ],
        'volvo': [
            'C40', 'S60', 'S90', 'V60', 'V90', 'XC40', 'XC60', 'XC90',
            'XC90 Recharge', 'XC60 Recharge', 'XC40 Recharge', 'C40 Recharge',
            'S60 Recharge', 'S90 Recharge', 'V60 Recharge', 'V90 Recharge',
            'EX90', 'EX30', 'EM90'
        ],
        'lexus': [
            'ES', 'GS', 'GX', 'IS', 'LC', 'LS', 'LX', 'NX', 'RC', 'RX',
            'RZ', 'UX', 'LFA', 'SC', 'CT', 'HS', 'IS F', 'RC F', 'GS F',
            'LC 500', 'LC 500h', 'LS 500', 'LS 500h', 'NX 350h', 'NX 450h+',
            'RX 350h', 'RX 450h+', 'RZ 450e'
        ],
        'porsche': [
            '911', '718 Boxster', '718 Cayman', 'Cayenne', 'Macan', 'Panamera',
            'Taycan', 'Carrera', 'Carrera S', 'Carrera 4', 'Carrera 4S',
            'Turbo', 'Turbo S', 'GT3', 'GT3 RS', 'GT2 RS', 'Targa', 'Speedster',
            'Cayenne Coupe', 'Macan T', 'Macan S', 'Macan GTS', 'Macan Turbo',
            'Taycan 4S', 'Taycan Turbo', 'Taycan Turbo S', 'Taycan 4 Cross Turismo',
            'Taycan Turbo Cross Turismo', 'Taycan Turbo S Cross Turismo'
        ],
        'jaguar': [
            'E-Pace', 'F-Pace', 'F-Type', 'I-Pace', 'XE', 'XF', 'XJ',
            'XK', 'F-Type R', 'F-Type SVR', 'F-Pace SVR', 'XE SV Project 8',
            'XJ220', 'XK120', 'XK140', 'XK150', 'Mark 1', 'Mark 2', 'S-Type',
            'X-Type', 'XJ6', 'XJ8', 'XJ12', 'XJS', 'XJR', 'XKR', 'XFR',
            'XKR-S', 'XJR-S', 'XJR-15'
        ],
        'land-rover': [
            'Defender', 'Discovery', 'Discovery Sport', 'Range Rover',
            'Range Rover Evoque', 'Range Rover Sport', 'Range Rover Velar',
            'Defender 90', 'Defender 110', 'Defender 130', 'Discovery 4',
            'Discovery 5', 'Freelander', 'Range Rover Classic', 'Range Rover P38',
            'Range Rover L322', 'Range Rover L405', 'Range Rover Sport L320',
            'Range Rover Sport L494', 'Range Rover Sport L461'
        ],
        'mini': [
            'Cooper', 'Cooper S', 'Cooper SE', 'Cooper JCW', 'Countryman',
            'Countryman S', 'Countryman JCW', 'Clubman', 'Clubman S',
            'Clubman JCW', 'Paceman', 'Coupe', 'Roadster', 'John Cooper Works',
            'Mini One', 'Mini One D', 'Mini Cooper D', 'Mini Cooper SD',
            'Mini Cooper SE', 'Mini Cooper SE Countryman', 'Mini Cooper SE Clubman'
        ],
        'smart': [
            'Fortwo', 'Forfour', 'EQ Fortwo', 'EQ Forfour', 'Fortwo Electric Drive',
            'Forfour Electric Drive', 'EQ Fortwo Cabrio', 'EQ Forfour Brabus',
            'Fortwo Brabus', 'Forfour Brabus', 'Fortwo Cabrio', 'Forfour Prime',
            'Fortwo Prime', 'Fortwo Pulse', 'Forfour Pulse', 'Fortwo Passion',
            'Forfour Passion', 'Fortwo Pure', 'Forfour Pure'
        ],
        'subaru': [
            'Ascent', 'BRZ', 'Crosstrek', 'Forester', 'Impreza', 'Legacy',
            'Outback', 'Solterra', 'WRX', 'WRX STI', 'Baja', 'Justy', 'Loyale',
            'SVX', 'Tribeca', 'Vivio', 'XT', 'XV', 'Levorg', 'Exiga',
            'Dias Wagon', 'Pleo', 'R1', 'R2', 'Sambar', 'Stella', 'Trezia'
        ],
        'mazda': [
            'Mazda2', 'Mazda3', 'Mazda6', 'CX-3', 'CX-30', 'CX-5', 'CX-7',
            'CX-9', 'CX-50', 'CX-60', 'CX-70', 'CX-80', 'CX-90', 'MX-5 Miata',
            'MX-30', 'RX-7', 'RX-8', 'MPV', 'B-Series', 'BT-50', 'Tribute',
            'Premacy', 'Verisa', 'Atenza', 'Axela', 'Demio', 'Roadster',
            'Savanna', 'Cosmo', 'Eunos', 'Xedos'
        ],
        'mitsubishi': [
            'Eclipse Cross', 'Mirage', 'Outlander', 'Outlander Sport', 'Pajero',
            'Pajero Sport', 'L200', 'Lancer', 'Lancer Evolution', 'Galant',
            'Diamante', '3000GT', 'Starion', 'Cordia', 'Tredia', 'Sigma',
            'Debonair', 'FTO', 'GTO', 'i-MiEV', 'ASX', 'RVR', 'Space Star',
            'Space Wagon', 'Space Runner', 'Space Gear', 'Delica', 'Minica',
            'Colt', 'Carisma'
        ],
        'suzuki': [
            'Swift', 'Vitara', 'Jimny', 'S-Cross', 'Across', 'Baleno', 'Celerio',
            'Ciaz', 'Ertiga', 'Ignis', 'Jimny Sierra', 'XL6', 'XL7', 'Alto',
            'Alto Lapin', 'Alto Works', 'Cappuccino', 'Cervo', 'Cultus', 'Every',
            'Fronte', 'Grand Vitara', 'Hustler', 'Jimny Wide', 'Kizashi',
            'Landy', 'Lapin', 'MR Wagon', 'Palette', 'Solio', 'Spacia',
            'Splash', 'Twin', 'Wagon R', 'X-90'
        ]
    }

    # Add models to database
    for brand, models in car_models.items():
        for model in models:
            existing_model = CarModel.query.filter_by(brand=brand, model=model).first()
            if not existing_model:
                car_model = CarModel(brand=brand, model=model)
                db.session.add(car_model)
    
    db.session.commit()

def seed_example_listings(count: int = 100):
    """Create example users and car listings for testing.
    Safe to call multiple times; it will only top up to the requested count.
    """
    # Ensure a demo user exists
    demo = User.query.filter_by(username='demo').first()
    if not demo:
        demo = User(
            username='demo',
            email='demo@example.com',
            password=generate_password_hash('demo1234')
        )
        db.session.add(demo)
        db.session.commit()

    # Basic option pools
    conditions = ['new', 'used']
    transmissions = ['automatic', 'manual']
    fuel_types = ['gasoline', 'diesel', 'electric', 'hybrid']
    colors = ['black', 'white', 'silver', 'gray', 'red', 'blue', 'green', 'orange']
    body_types = ['sedan', 'suv', 'hatchback', 'coupe', 'wagon', 'pickup', 'van', 'minivan']
    drive_types = ['fwd', 'rwd', 'awd', '4wd']
    license_plate_types = ['private', 'temporary', 'commercial', 'taxi']
    cities = ['baghdad', 'basra', 'erbil', 'najaf', 'karbala', 'kirkuk', 'sulaymaniyah', 'dohuk']

    # Pull available (brand, model) pairs from CarModel table
    model_rows = CarModel.query.all()
    if not model_rows:
        populate_car_models()
        model_rows = CarModel.query.all()

    # Current number of cars
    current_total = Car.query.count()
    to_create = max(0, count - current_total)
    if to_create == 0:
        return

    new_cars: list[Car] = []
    for i in range(to_create):
        cm = random.choice(model_rows)
        brand = cm.brand
        model = cm.model
        # Simple trim fallback
        trim = 'Base'

        year = random.randint(datetime.now().year - 20, datetime.now().year)
        mileage = random.randint(0, 220_000)
        price = random.choice([None, random.randint(1500, 120000)])
        transmission = random.choice(transmissions)
        fuel_type = random.choice(fuel_types)
        color = random.choice(colors)
        condition = random.choice(conditions)
        body_type = random.choice(body_types)
        seating = random.choice([2, 4, 5, 7, 8])
        drive_type = random.choice(drive_types)
        license_plate_type = random.choice(license_plate_types)
        city = random.choice(cities)
        cylinder_count = random.choice([3, 4, 6, 8, 10, 12])
        engine_size = round(random.uniform(1.0, 6.0), 1)
        import_country = random.choice(['us', 'gcc', 'iraq', 'canada', 'eu'])

        title = f"{brand.replace('-', ' ').title()} {model} {trim}"
        created_offset_days = random.randint(0, 120)

        car = Car(
            title=title,
            brand=brand,
            model=model,
            trim=trim,
            year=year,
            mileage=mileage,
            price=price,
            title_status='clean',
            damaged_parts=None,
            transmission=transmission,
            fuel_type=fuel_type,
            color=color,
            cylinder_count=cylinder_count,
            engine_size=engine_size,
            import_country=import_country,
            body_type=body_type,
            seating=seating,
            drive_type=drive_type,
            license_plate_type=license_plate_type,
            city=city,
            condition=condition,
            user_id=demo.id,
            status='active',
            created_at=datetime.utcnow() - timedelta(days=created_offset_days)
        )
        new_cars.append(car)

    db.session.bulk_save_objects(new_cars)
    db.session.commit()

@app.route('/search')
def search():
    query = request.args.get('query', '')
    current_year = datetime.now().year
    def sanitize_numeric(val, typ):
        if val in (None, '', 'any', 'Undefined'):
            return None
        try:
            return typ(val)
        except Exception:
            return None

    # Support both legacy range params and new single-value params
    price_exact = sanitize_numeric(request.args.get('price'), float)
    year_exact = sanitize_numeric(request.args.get('year'), int)
    mileage_exact = sanitize_numeric(request.args.get('mileage'), int)

    min_price = sanitize_numeric(request.args.get('min_price'), float)
    max_price = sanitize_numeric(request.args.get('max_price'), float)
    min_year = sanitize_numeric(request.args.get('min_year'), int)
    max_year = sanitize_numeric(request.args.get('max_year'), int)
    min_mileage = sanitize_numeric(request.args.get('min_mileage'), int)
    max_mileage = sanitize_numeric(request.args.get('max_mileage'), int)
    # Number of damaged parts for damaged title filtering (Flutter app support)
    damaged_parts = sanitize_numeric(request.args.get('damaged_parts'), int)
    damaged_parts = sanitize_numeric(request.args.get('damaged_parts'), int)
    cylinder_count = sanitize_numeric(request.args.get('cylinder_count'), int)
    engine_size = sanitize_numeric(request.args.get('engine_size'), float)

    brand = request.args.get('brand', '')
    model = request.args.get('model', '')
    trim = request.args.get('trim', '')
    transmission = request.args.get('transmission', '')
    fuel_type = request.args.get('fuel_type', '')
    title_status = request.args.get('title_status', '')
    condition = request.args.get('condition', '')
    sort_by = request.args.get('sort_by', '')
    color = request.args.get('color', '')
    import_country = request.args.get('import_country', '')
    license_plate_type = request.args.get('license_plate_type', '')
    city = request.args.get('city', '')

    car_query = Car.query

    if query:
        car_query = car_query.filter(
            db.or_(
                Car.title.ilike(f'%{query}%'),
                Car.brand.ilike(f'%{query}%'),
                Car.model.ilike(f'%{query}%'),
                Car.trim.ilike(f'%{query}%')
            )
        )

    # Apply exact filters if provided; fall back to ranges
    if price_exact is not None:
        car_query = car_query.filter(Car.price == price_exact)
    elif min_price is not None and min_price != 'any':
        car_query = car_query.filter(Car.price >= min_price)
    if price_exact is None and max_price is not None and max_price != 'any':
        car_query = car_query.filter(Car.price <= max_price)
    if year_exact is not None:
        car_query = car_query.filter(Car.year == year_exact)
    elif min_year is not None and min_year != 'any':
        car_query = car_query.filter(Car.year >= min_year)
    if year_exact is None and max_year is not None and max_year != 'any':
        car_query = car_query.filter(Car.year <= max_year)
    if mileage_exact is not None:
        car_query = car_query.filter(Car.mileage == mileage_exact)
    elif min_mileage is not None and min_mileage != 'any' and min_mileage != 0:
        car_query = car_query.filter(Car.mileage >= min_mileage)
    if mileage_exact is None and max_mileage is not None and max_mileage != 'any' and max_mileage != 0:
        car_query = car_query.filter(Car.mileage <= max_mileage)
    if brand and brand != 'any':
        car_query = car_query.filter(Car.brand.ilike(f'%{brand}%'))
    if model and model != 'any':
        car_query = car_query.filter(Car.model == model)
    if trim and trim != 'any':
        car_query = car_query.filter(Car.trim == trim)
    if transmission and transmission != 'any':
        car_query = car_query.filter(Car.transmission == transmission)
    if fuel_type and fuel_type != 'any':
        car_query = car_query.filter(Car.fuel_type == fuel_type)
    if title_status and title_status != 'any':
        car_query = car_query.filter(Car.title_status == title_status)
        # If specifically filtering damaged titles, allow narrowing by number of parts
        if title_status == 'damaged' and damaged_parts is not None and damaged_parts != 'any':
            car_query = car_query.filter(Car.damaged_parts == damaged_parts)
        if title_status == 'damaged' and damaged_parts is not None and damaged_parts != 'any':
            car_query = car_query.filter(Car.damaged_parts == damaged_parts)
    if condition and condition != 'any':
        car_query = car_query.filter(Car.condition == condition)
    if color and color != 'any':
        car_query = car_query.filter(Car.color == color)
    if cylinder_count and cylinder_count != 'any':
        car_query = car_query.filter(Car.cylinder_count == cylinder_count)
    if engine_size is not None and engine_size != 'any':
        car_query = car_query.filter(Car.engine_size == float(engine_size))
    if import_country and import_country != 'any':
        car_query = car_query.filter(Car.import_country == import_country)
    if license_plate_type and license_plate_type != 'any':
        car_query = car_query.filter(Car.license_plate_type == license_plate_type)
    if city and city != 'any':
        car_query = car_query.filter(Car.city == city)

    # Apply sorting
    if sort_by and sort_by != 'any':
        if sort_by == 'newest':
            car_query = car_query.order_by(Car.created_at.desc())
        elif sort_by == 'price_asc':
            car_query = car_query.order_by(Car.price.asc())
        elif sort_by == 'price_desc':
            car_query = car_query.order_by(Car.price.desc())
        elif sort_by == 'year_desc':
            car_query = car_query.order_by(Car.year.desc())
        elif sort_by == 'year_asc':
            car_query = car_query.order_by(Car.year.asc())
        elif sort_by == 'mileage_asc':
            car_query = car_query.order_by(Car.mileage.asc())
        elif sort_by == 'mileage_desc':
            car_query = car_query.order_by(Car.mileage.desc())
    else:
        car_query = car_query.order_by(Car.created_at.desc())

    cars = car_query.all()

    return render_template('home.html',
                         cars=cars,
                         query=query,
                         current_year=current_year,
                         price_exact=price_exact,
                         year_exact=year_exact,
                         mileage_exact=mileage_exact,
                         min_price=min_price,
                         max_price=max_price,
                         min_year=min_year,
                         max_year=max_year,
                         min_mileage=min_mileage,
                         max_mileage=max_mileage,
                         brand=brand,
                         model=model,
                         trim=trim,
                         transmission=transmission,
                         fuel_type=fuel_type,
                         title_status=title_status,
                         damaged_parts=damaged_parts,
                         condition=condition,
                         sort_by=sort_by,
                         color=color,
                         brands=get_brands(),
                         models=get_models(brand) if brand else [],
                         trims=get_trims(brand, model) if brand and model else [],
                         import_country=import_country)

@app.route('/cars', methods=['GET', 'POST'])
def api_cars():
    """JSON API for listings used by the Flutter app.
    Mirrors the filtering logic of the /search route, but returns JSON.
    """
    # Create a new car listing (used by emulator/mobile Add Listing)
    if request.method == 'POST':
        try:
            # Require authentication via web session or Bearer token
            api_user = get_api_user()
            if not api_user:
                return jsonify({'error': 'Authentication required'}), 401
            data = request.get_json() or {}
            required_fields = [
                'title', 'brand', 'model', 'trim', 'year', 'mileage', 'condition',
                'transmission', 'fuel_type', 'color', 'body_type', 'seating', 'drive_type', 'title_status'
            ]
            missing = [f for f in required_fields if not data.get(f)]
            if missing:
                return jsonify({'error': f"Missing required fields: {', '.join(missing)}"}), 400

            car = Car(
                title=data['title'],
                brand=str(data['brand']),
                model=str(data['model']),
                trim=str(data['trim']),
                year=int(data['year']),
                price=(float(data['price']) if data.get('price') not in (None, '', 'any') else None),
                mileage=int(data['mileage']),
                condition=str(data['condition']).lower(),
                transmission=str(data['transmission']).lower(),
                fuel_type=str(data['fuel_type']).lower(),
                color=str(data['color']).lower(),
                image_url=(data.get('image_url') or ''),
                cylinder_count=(int(data['cylinder_count']) if data.get('cylinder_count') else None),
                engine_size=(float(data['engine_size']) if data.get('engine_size') else None),
                import_country=(str(data['import_country']).lower() if data.get('import_country') else None),
                body_type=str(data['body_type']).lower(),
                seating=int(data['seating']),
                drive_type=str(data['drive_type']).lower(),
                license_plate_type=(str(data['license_plate_type']).lower() if data.get('license_plate_type') else None),
                city=(str(data['city']).lower() if data.get('city') else None),
                contact_phone=(str(data['contact_phone']).strip() if data.get('contact_phone') else None),
                title_status=str(data['title_status']).lower(),
                damaged_parts=(int(data['damaged_parts']) if data.get('damaged_parts') else None),
                is_quick_sell=bool(data.get('is_quick_sell', False)),
                status='active',  # Activate immediately for emulator UX
                user_id=api_user.id
            )
            db.session.add(car)
            db.session.commit()

            def first_image_rel_path(new_car: Car) -> str:
                if new_car.images:
                    path = new_car.images[0].image_url or ''
                    return path[8:] if path.startswith('uploads/') else path
                return (new_car.image_url or '').lstrip('/')

            return jsonify({
                'id': car.id,
                'title': car.title,
                'brand': car.brand,
                'model': car.model,
                'trim': car.trim,
                'year': car.year,
                'price': car.price,
                'mileage': car.mileage,
                'title_status': car.title_status,
                'damaged_parts': car.damaged_parts,
                'condition': car.condition,
                'transmission': car.transmission,
                'fuel_type': car.fuel_type,
                'color': car.color,
                'body_type': car.body_type,
                'seating': car.seating,
                'drive_type': car.drive_type,
                'cylinder_count': car.cylinder_count,
                'engine_size': car.engine_size,
                'import_country': car.import_country,
                'license_plate_type': car.license_plate_type,
                'city': car.city,
                'contact_phone': car.contact_phone,
                'image_url': first_image_rel_path(car),
                'status': car.status,
            }), 201
        except Exception as e:
            db.session.rollback()
            return jsonify({'error': str(e)}), 500
    # Safety net: if database is empty, seed some examples so the app always shows data
    if Car.query.count() == 0:
        try:
            populate_car_models()
            seed_example_listings(100)
        except Exception:
            pass
    def sanitize_numeric(val, typ):
        if val in (None, '', 'any', 'Undefined'):
            return None
        try:
            return typ(val)
        except Exception:
            return None

    price_exact = sanitize_numeric(request.args.get('price'), float)
    year_exact = sanitize_numeric(request.args.get('year'), int)
    mileage_exact = sanitize_numeric(request.args.get('mileage'), int)

    min_price = sanitize_numeric(request.args.get('min_price'), float)
    max_price = sanitize_numeric(request.args.get('max_price'), float)
    min_year = sanitize_numeric(request.args.get('min_year'), int)
    max_year = sanitize_numeric(request.args.get('max_year'), int)
    min_mileage = sanitize_numeric(request.args.get('min_mileage'), int)
    max_mileage = sanitize_numeric(request.args.get('max_mileage'), int)

    query_id = sanitize_numeric(request.args.get('id'), int)
    brand = request.args.get('brand', '')
    model = request.args.get('model', '')
    trim = request.args.get('trim', '')
    transmission = request.args.get('transmission', '')
    fuel_type = request.args.get('fuel_type', '')
    title_status = request.args.get('title_status', '')
    condition = request.args.get('condition', '')
    sort_by = request.args.get('sort_by', '')
    color = request.args.get('color', '')
    import_country = request.args.get('import_country', '')
    license_plate_type = request.args.get('license_plate_type', '')
    city = request.args.get('city', '')
    drive_type = request.args.get('drive_type', '')
    seating = sanitize_numeric(request.args.get('seating'), int)
    cylinder_count = sanitize_numeric(request.args.get('cylinder_count'), int)

    # For emulator/dev experience, include newly submitted listings that are pending payment
    car_query = Car.query.filter(Car.status.in_(['active', 'pending_payment']))
    if query_id is not None:
        car_query = car_query.filter(Car.id == query_id)

    if price_exact is not None:
        car_query = car_query.filter(Car.price == price_exact)
    elif min_price is not None and min_price != 'any':
        car_query = car_query.filter(Car.price >= min_price)
    if price_exact is None and max_price is not None and max_price != 'any':
        car_query = car_query.filter(Car.price <= max_price)
    if year_exact is not None:
        car_query = car_query.filter(Car.year == year_exact)
    elif min_year is not None and min_year != 'any':
        car_query = car_query.filter(Car.year >= min_year)
    if year_exact is None and max_year is not None and max_year != 'any':
        car_query = car_query.filter(Car.year <= max_year)
    if mileage_exact is not None:
        car_query = car_query.filter(Car.mileage == mileage_exact)
    elif min_mileage is not None and min_mileage != 'any' and min_mileage != 0:
        car_query = car_query.filter(Car.mileage >= min_mileage)
    if mileage_exact is None and max_mileage is not None and max_mileage != 'any' and max_mileage != 0:
        car_query = car_query.filter(Car.mileage <= max_mileage)
    if brand and brand != 'any':
        car_query = car_query.filter(Car.brand.ilike(f'%{brand}%'))
    if model and model != 'any':
        car_query = car_query.filter(Car.model == model)
    if trim and trim != 'any':
        car_query = car_query.filter(Car.trim == trim)
    if transmission and transmission != 'any':
        car_query = car_query.filter(Car.transmission == transmission)
    if fuel_type and fuel_type != 'any':
        car_query = car_query.filter(Car.fuel_type == fuel_type)
    if title_status and title_status != 'any':
        car_query = car_query.filter(Car.title_status == title_status)
    if condition and condition != 'any':
        car_query = car_query.filter(Car.condition == condition)
    if color and color != 'any':
        car_query = car_query.filter(Car.color == color)
    if import_country and import_country != 'any':
        car_query = car_query.filter(Car.import_country == import_country)
    if license_plate_type and license_plate_type != 'any':
        car_query = car_query.filter(Car.license_plate_type == license_plate_type)
    if city and city != 'any':
        car_query = car_query.filter(Car.city == city)
    if drive_type and drive_type != 'any':
        car_query = car_query.filter(Car.drive_type == drive_type)
    if seating is not None and seating != 'any':
        car_query = car_query.filter(Car.seating == seating)
    if cylinder_count is not None and cylinder_count != 'any':
        car_query = car_query.filter(Car.cylinder_count == cylinder_count)

    if sort_by and sort_by != 'any':
        if sort_by == 'newest':
            car_query = car_query.order_by(Car.created_at.desc())
        elif sort_by == 'price_asc':
            # Handle NULL prices by putting them last, then sort ascending
            car_query = car_query.order_by(Car.price.is_(None), Car.price.asc())
        elif sort_by == 'price_desc':
            # Handle NULL prices by putting them last, then sort descending
            car_query = car_query.order_by(Car.price.is_(None), Car.price.desc())
        elif sort_by == 'year_desc':
            # Handle NULL years by putting them last, then sort descending
            car_query = car_query.order_by(Car.year.is_(None), Car.year.desc())
        elif sort_by == 'year_asc':
            # Handle NULL years by putting them last, then sort ascending
            car_query = car_query.order_by(Car.year.is_(None), Car.year.asc())
        elif sort_by == 'mileage_asc':
            # Handle NULL mileage by putting them last, then sort ascending
            car_query = car_query.order_by(Car.mileage.is_(None), Car.mileage.asc())
        elif sort_by == 'mileage_desc':
            # Handle NULL mileage by putting them last, then sort descending
            car_query = car_query.order_by(Car.mileage.is_(None), Car.mileage.desc())
    else:
        car_query = car_query.order_by(Car.created_at.desc())

    cars = car_query.all()

    def first_image_rel_path(car: Car) -> str:
        # Prefer first CarImage if present; strip leading 'uploads/' for Flutter
        if car.images:
            path = car.images[0].image_url or ''  # e.g., 'uploads/car_photos/file.jpg'
            return path[8:] if path.startswith('uploads/') else path
        # Fallback to car.image_url (assume already relative under uploads)
        return (car.image_url or '').lstrip('/')

    def images_rel_paths(car: Car):
        out = []
        for im in car.images:
            p = (im.image_url or '')
            out.append(p[8:] if p.startswith('uploads/') else p)
        return out

    def videos_rel_paths(car: Car):
        out = []
        for v in car.videos:
            p = (v.video_url or '')
            out.append(p[8:] if p.startswith('uploads/') else p)
        return out

    payload = [{
        'id': c.id,
        'title': c.title,
        'brand': c.brand,
        'model': c.model,
        'trim': c.trim,
        'year': c.year,
        'price': c.price,
        'mileage': c.mileage,
        'title_status': c.title_status,
        'damaged_parts': c.damaged_parts,
        'condition': c.condition,
        'transmission': c.transmission,
        'fuel_type': c.fuel_type,
        'color': c.color,
        'body_type': c.body_type,
        'seating': c.seating,
        'drive_type': c.drive_type,
        'cylinder_count': c.cylinder_count,
        'engine_size': c.engine_size,
        'import_country': c.import_country,
        'license_plate_type': c.license_plate_type,
        'city': c.city,
        'contact_phone': c.contact_phone,
        'image_url': first_image_rel_path(c),  # Flutter builds /static/uploads/{image_url}
        'images': images_rel_paths(c),
        'videos': videos_rel_paths(c),
    } for c in cars]

    return jsonify(payload)

@app.route('/api/cars/<int:car_id>/images', methods=['POST'])
def upload_car_images(car_id):
    """Upload one or more images for a specific car (used by the Flutter app).
    Expects multipart/form-data with one or more 'image' files.
    Returns JSON with uploaded relative paths.
    """
    car = Car.query.get_or_404(car_id)
    # Only the owner (from token or session) can upload images; if listing has no owner yet,
    # let the first authenticated uploader claim it.
    api_user = get_api_user()
    if not api_user:
        return jsonify({'error': 'Unauthorized'}), 401
    try:
        if getattr(car, 'user_id', None) in (None, 0) and getattr(car, 'seller_id', None) in (None, 0):
            car.user_id = api_user.id
            db.session.commit()
    except Exception:
        db.session.rollback()
    if getattr(car, 'user_id', None) not in (api_user.id,) and getattr(car, 'seller_id', None) not in (api_user.id, None):
        return jsonify({'error': 'Not authorized to upload images for this listing'}), 403
    try:
        # Accept multiple common field names and array-style keys
        files = []
        for key in ('image', 'images', 'file', 'files', 'photo', 'photos', 'file[]', 'images[]', 'photos[]'):
            files.extend(request.files.getlist(key))
        # Fallback: include any remaining file objects
        if not files and request.files:
            try:
                for _k in request.files.keys():
                    files.extend(request.files.getlist(_k))
            except Exception:
                pass
        if not files:
            return jsonify({'error': 'No image files provided'}), 400

        saved_paths = []
        for file in files:
            if file and allowed_file(file.filename):
                # Process with license plate blur and store to uploads path
                rel_path, _ = _process_and_store_image(file, False)
                car_image = CarImage(car_id=car.id, image_url=rel_path)
                db.session.add(car_image)
                saved_paths.append(rel_path)

        # Set primary image to the first uploaded (ensures immediate display in listings)
        if saved_paths:
            # Store trimmed so API consistency: DB holds relative-under-uploads path without prefix
            first_trimmed = saved_paths[0][8:] if saved_paths[0].startswith('uploads/') else saved_paths[0]
            car.image_url = first_trimmed

        db.session.commit()

        # Return paths without the leading 'uploads/' to match the /cars JSON API
        trimmed = [p[8:] if p.startswith('uploads/') else p for p in saved_paths]
        return jsonify({'uploaded': trimmed, 'images': trimmed, 'image_url': car.image_url or ''}), 201
    except Exception as e:
        db.session.rollback()
        return jsonify({'error': str(e)}), 500

@app.route('/api/cars/<int:car_id>/videos', methods=['POST'])
def upload_car_videos(car_id):
    """Upload one or more videos for a specific car (used by the Flutter app).
    Expects multipart/form-data with one or more 'video' files.
    Returns JSON with uploaded relative paths.
    """
    car = Car.query.get_or_404(car_id)
    # Only the owner (from token or session) can upload videos
    api_user = get_api_user()
    if not api_user or car.user_id != api_user.id:
        return jsonify({'error': 'Unauthorized'}), 403
    try:
        files = request.files.getlist('video')  # supports repeated 'video' fields
        if not files:
            return jsonify({'error': 'No video files provided'}), 400

        saved_paths = []
        for file in files:
            if file and allowed_video_file(file.filename):
                filename = secure_filename(file.filename)
                timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
                filename = f"{timestamp}_{filename}"
                target_path = os.path.join(app.config['UPLOAD_FOLDER'], 'car_videos', filename)
                os.makedirs(os.path.dirname(target_path), exist_ok=True)
                file.save(target_path)

                rel_path = f"uploads/car_videos/{filename}"
                car_video = CarVideo(car_id=car.id, video_url=rel_path)
                db.session.add(car_video)
                saved_paths.append(rel_path)

        db.session.commit()

        # Return paths without the leading 'uploads/' to match the /cars JSON API
        trimmed = [p[8:] if p.startswith('uploads/') else p for p in saved_paths]
        return jsonify({'uploaded': trimmed}), 201
    except Exception as e:
        db.session.rollback()
        return jsonify({'error': str(e)}), 500

# -----------------------
# JSON APIs scoped to current user (web session); emulator should use kk/api.py token endpoints
# -----------------------

@app.route('/api/favorites', methods=['GET'])
def api_favorites():
    # Support both token-based (mobile) and session-based auth
    api_user = get_api_user()
    if not api_user:
        return jsonify({'error': 'Unauthorized'}), 401
    favs = Favorite.query.filter_by(user_id=api_user.id).all()
    cars = [fav.car for fav in favs]

    def first_image_rel_path(c: Car) -> str:
        if c.images:
            path = c.images[0].image_url or ''
            return path[8:] if path.startswith('uploads/') else path
        return (c.image_url or '').lstrip('/')

    payload = [{
        'id': c.id,
        'title': c.title,
        'brand': c.brand,
        'model': c.model,
        'trim': c.trim,
        'year': c.year,
        'price': c.price,
        'mileage': c.mileage,
        'condition': c.condition,
        'transmission': c.transmission,
        'fuel_type': c.fuel_type,
        'color': c.color,
        'image_url': first_image_rel_path(c),
        'city': c.city,
        'status': c.status
    } for c in cars]
    return jsonify(payload)

@app.route('/api/favorite/<int:car_id>', methods=['POST'])
def api_toggle_favorite(car_id):
    # Support both token-based (mobile) and session-based auth
    api_user = get_api_user()
    if not api_user:
        return jsonify({'error': 'Unauthorized'}), 401
    car = Car.query.get_or_404(car_id)
    favorite = Favorite.query.filter_by(user_id=api_user.id, car_id=car_id).first()
    if favorite:
        db.session.delete(favorite)
        db.session.commit()
        return jsonify({'favorited': False})
    else:
        new_fav = Favorite(user_id=api_user.id, car_id=car.id)
        db.session.add(new_fav)
        db.session.commit()
        return jsonify({'favorited': True})

@app.route('/api/my_listings', methods=['GET'])
def api_my_listings():
    # Support both token-based (mobile) and session-based auth
    api_user = get_api_user()
    if not api_user:
        return jsonify({'error': 'Unauthorized'}), 401
    cars = Car.query.filter_by(user_id=api_user.id).order_by(Car.created_at.desc()).all()

    def first_image_rel_path(c: Car) -> str:
        if c.images:
            path = c.images[0].image_url or ''
            return path[8:] if path.startswith('uploads/') else path
        return (c.image_url or '').lstrip('/')

    def images_rel_paths(c: Car):
        out = []
        for im in c.images:
            p = (im.image_url or '')
            out.append(p[8:] if p.startswith('uploads/') else p)
        return out

    result = [{
        'id': c.id,
        'title': c.title,
        'brand': c.brand,
        'model': c.model,
        'trim': c.trim,
        'year': c.year,
        'price': c.price,
        'mileage': c.mileage,
        'condition': c.condition,
        'transmission': c.transmission,
        'fuel_type': c.fuel_type,
        'color': c.color,
        'image_url': first_image_rel_path(c),
        'images': images_rel_paths(c),  # Add images array for scrollable functionality
        'city': c.city,
        'status': c.status
    } for c in cars]
    return jsonify(result)

@app.route('/api/cars', methods=['GET'])
def api_cars_list():
    """Public cars list with simple pagination and filtering used by the Flutter app.
    Responds with { cars: [...], pagination: { has_next: bool } }
    """
    try:
        page = int(request.args.get('page', 1))
        per_page = int(request.args.get('per_page', 20))

        query = Car.query
        # Optional filters
        brand = request.args.get('brand')
        model = request.args.get('model')
        if brand:
            query = query.filter(Car.brand == brand)
        if model:
            query = query.filter(Car.model == model)
        if request.args.get('year_min'):
            query = query.filter(Car.year >= int(request.args.get('year_min')))
        if request.args.get('year_max'):
            query = query.filter(Car.year <= int(request.args.get('year_max')))
        if request.args.get('price_min'):
            query = query.filter(Car.price >= float(request.args.get('price_min')))
        if request.args.get('price_max'):
            query = query.filter(Car.price <= float(request.args.get('price_max')))
        if request.args.get('location'):
            query = query.filter(Car.city == request.args.get('location'))

        query = query.order_by(Car.created_at.desc())
        items = query.limit(per_page + 1).offset((page - 1) * per_page).all()
        has_next = len(items) > per_page
        cars = items[:per_page]

        def first_image_rel_path(c: Car) -> str:
            """
            Resolve the first image path for a car, normalizing to a relative path that exists
            under static/uploads. Some historical rows store values like 'uploads/xyz.png' or
            plain 'xyz.png'. We also fallback to car_photos if the stored path doesn't exist.
            """
            import os as _os
            rel = ''
            if c.images and len(c.images) > 0:
                path = c.images[0].image_url or ''
                rel = path[8:] if path.startswith('uploads/') else path.lstrip('/')
            else:
                rel = (c.image_url or '').lstrip('/')
                if rel.startswith('uploads/'):
                    rel = rel[8:]
            # If we have a candidate, ensure it exists; otherwise fallback to car_photos/<basename>
            if rel:
                abs_path = _os.path.join(app.config['UPLOAD_FOLDER'], rel)
                if not _os.path.isfile(abs_path):
                    # Try under uploads/car_photos with same basename
                    base = _os.path.basename(rel)
                    rel_candidate = _os.path.join('uploads', 'car_photos', base).replace('\\', '/')
                    abs_candidate = _os.path.join(app.config['UPLOAD_FOLDER'], rel_candidate.replace('uploads/', ''))
                    # Note: app.config['UPLOAD_FOLDER'] already points to static/uploads
                    # rel without leading 'uploads/' pairs with '/static/uploads/' on the client
                    if not _os.path.isfile(abs_candidate):
                        # As a last resort, leave rel empty to avoid broken URLs
                        rel = ''
                    else:
                        # Keep 'uploads/...' prefix so mobile prefixes with /static/
                        rel = rel_candidate
                else:
                    # If stored rel had no 'uploads/' prefix, keep as-is; client handles both
                    pass
            return f"{rel}?v={int(time.time())}" if rel else ''

        def images_rel_paths(c: Car):
            """
            Normalize each image path and only include ones that exist on disk.
            """
            import os as _os
            out = []
            for im in c.images:
                p = (im.image_url or '')
                rel = p[8:] if p.startswith('uploads/') else p.lstrip('/')
                if not rel:
                    continue
                abs_path = _os.path.join(app.config['UPLOAD_FOLDER'], rel)
                if not _os.path.isfile(abs_path):
                    base = _os.path.basename(rel)
                    rel_candidate = _os.path.join('uploads', 'car_photos', base).replace('\\', '/')
                    abs_candidate = _os.path.join(app.config['UPLOAD_FOLDER'], rel_candidate.replace('uploads/', ''))
                    if _os.path.isfile(abs_candidate):
                        rel = rel_candidate
                    else:
                        continue
                out.append(f"{rel}?v={int(time.time())}")
            return out

        data = [{
            'id': c.id,
            'title': c.title,
            'brand': c.brand,
            'model': c.model,
            'trim': getattr(c, 'trim', None),
            'year': c.year,
            'price': c.price,
            'mileage': c.mileage,
            'condition': getattr(c, 'condition', None),
            'transmission': getattr(c, 'transmission', None),
            'fuel_type': getattr(c, 'fuel_type', None),
            'color': getattr(c, 'color', None),
            'image_url': first_image_rel_path(c),
            'images': images_rel_paths(c),
            'city': c.city,
            'status': getattr(c, 'status', None)
        } for c in cars]

        return jsonify({'cars': data, 'pagination': {'has_next': has_next}})
    except Exception as e:
        return jsonify({'error': str(e)}), 500

@app.route('/api/cars/<int:car_id>', methods=['GET'])
def api_get_car(car_id: int):
    """Public car detail used by the Flutter app."""
    c = Car.query.get_or_404(car_id)

    def images_rel_paths(car: Car):
        out = []
        for im in car.images:
            p = (im.image_url or '')
            rel = p[8:] if p.startswith('uploads/') else p
            if rel:
                out.append(f"{rel}?v={int(time.time())}")
        return out

    result = {
        'car': {
            'id': c.id,
            'title': c.title,
            'brand': c.brand,
            'model': c.model,
            'trim': getattr(c, 'trim', None),
            'year': c.year,
            'price': c.price,
            'mileage': c.mileage,
            'condition': getattr(c, 'condition', None),
            'transmission': getattr(c, 'transmission', None),
            'fuel_type': getattr(c, 'fuel_type', None),
            'color': getattr(c, 'color', None),
            'city': c.city,
            # Extended specs expected by the mobile app
            'body_type': getattr(c, 'body_type', None),
            'drive_type': getattr(c, 'drive_type', None),
            'seating': getattr(c, 'seating', None),
            'cylinder_count': getattr(c, 'cylinder_count', None),
            'engine_size': getattr(c, 'engine_size', None),
            'title_status': getattr(c, 'title_status', None),
            'damaged_parts': getattr(c, 'damaged_parts', None),
            'contact_phone': getattr(c, 'contact_phone', None),
            'image_url': (lambda rel: f"{rel}?v={int(time.time())}" if rel else '')((c.image_url or '').lstrip('/')),
            'images': images_rel_paths(c),
        }
    }
    return jsonify(result)

@app.route('/api/cars', methods=['POST'])
@jwt_required()
def api_create_car():
    """Create a new car listing. Expects JSON body from the Flutter app."""
    try:
        user = get_api_user()
        if not user:
            return jsonify({'error': 'Unauthorized'}), 401
        data = request.get_json() or {}
        # Minimal set expected from the client; add sane defaults for the rest so DB constraints pass
        required_fields = ['brand', 'model', 'year', 'mileage', 'price']
        missing = [f for f in required_fields if data.get(f) in (None, '')]
        if missing:
            return jsonify({'message': 'Validation failed', 'errors': {f: 'required' for f in missing}}), 400

        # Normalize/derive fields to match the Car model defined in this file
        def _as_int(v, d=0):
            try:
                return int(v)
            except Exception:
                return d

        def _as_float(v, d=None):
            try:
                return float(v)
            except Exception:
                return d

        title = (data.get('title') or f"{str(data.get('brand') or '').title()} {data.get('model') or ''} {data.get('trim') or ''}").strip()
        car = Car(
            user_id=user.id,
            title=title if title else 'Car Listing',
            title_status=str(data.get('title_status') or 'clean').lower(),
            damaged_parts=_as_int(data.get('damaged_parts')) if data.get('damaged_parts') not in (None, '') else None,
            brand=str(data.get('brand')),
            model=str(data.get('model')),
            trim=str(data.get('trim') or 'Base'),
            year=_as_int(data.get('year')),
            price=_as_float(data.get('price')),
            mileage=_as_int(data.get('mileage')),
            condition=str(data.get('condition') or 'used').lower(),
            transmission=str(data.get('transmission') or 'automatic').lower(),
            fuel_type=str((data.get('engine_type') or data.get('fuel_type') or 'gasoline')).lower(),
            color=str(data.get('color') or 'black').lower(),
            body_type=str(data.get('body_type') or 'sedan').lower(),
            seating=_as_int(data.get('seating') or 5, 5),
            drive_type=str(data.get('drive_type') or 'fwd').lower(),
            cylinder_count=_as_int(data.get('cylinder_count')) if data.get('cylinder_count') not in (None, '') else None,
            engine_size=_as_float(data.get('engine_size')) if data.get('engine_size') not in (None, '') else None,
            import_country=(str(data.get('import_country')).lower() if data.get('import_country') else None),
            license_plate_type=(str(data.get('license_plate_type')).lower() if data.get('license_plate_type') else None),
            city=str((data.get('location') or data.get('city') or 'baghdad')).lower(),
            contact_phone=str(data.get('contact_phone') or '').strip(),
            is_quick_sell=bool(data.get('is_quick_sell', False)),
            status='active'
        )
        db.session.add(car)
        db.session.commit()

        # Minimal response structure expected by the app
        response = {
            'message': 'Car listing created successfully',
            'car': {
                'id': car.id,
                'title': car.title,
                'brand': car.brand,
                'model': car.model,
                'year': car.year,
                'price': car.price,
                'mileage': car.mileage,
                'city': car.city,
                'images': [],
                'image_url': (car.image_url or '').lstrip('/'),
            }
        }
        return jsonify(response), 201
    except Exception as e:
        db.session.rollback()
        return jsonify({'message': 'Failed to create car listing', 'error': str(e)}), 500

@app.route('/api/cars/<int:car_id>', methods=['PUT'])
@jwt_required()
def api_update_car(car_id: int):
    try:
        user = get_api_user()
        if not user:
            return jsonify({'error': 'Unauthorized'}), 401
        car = Car.query.get_or_404(car_id)
        if getattr(car, 'user_id', None) not in (None, user.id) and getattr(car, 'seller_id', None) not in (None, user.id):
            return jsonify({'message': 'Not authorized to update this listing'}), 403
        data = request.get_json() or {}
        for key in ['brand','model','year','mileage','transmission','condition','body_type','fuel_type','price','city','color','description']:
            if key in data:
                setattr(car, key, data[key])
        db.session.commit()
        return jsonify({'message': 'Car listing updated successfully'})
    except Exception as e:
        return jsonify({'message': 'Failed to update car listing', 'error': str(e)}), 500

@app.route('/api/cars/<int:car_id>', methods=['DELETE'])
@jwt_required()
def api_delete_car(car_id: int):
    try:
        user = get_api_user()
        if not user:
            return jsonify({'error': 'Unauthorized'}), 401
        car = Car.query.get_or_404(car_id)
        if getattr(car, 'user_id', None) not in (None, user.id) and getattr(car, 'seller_id', None) not in (None, user.id):
            return jsonify({'message': 'Not authorized to delete this listing'}), 403
        db.session.delete(car)
        db.session.commit()
        return jsonify({'message': 'Car listing deleted successfully'})
    except Exception as e:
        return jsonify({'message': 'Failed to delete car listing', 'error': str(e)}), 500

@app.route('/api/chats', methods=['GET'])
@login_required
def api_chats():
    conversations = Conversation.query.filter(
        db.or_(
            Conversation.buyer_id == current_user.id,
            Conversation.seller_id == current_user.id
        )
    ).order_by(Conversation.updated_at.desc()).all()

    result = []
    for conv in conversations:
        result.append({
            'id': conv.id,
            'car_id': conv.car_id,
            'buyer_id': conv.buyer_id,
            'seller_id': conv.seller_id,
            'created_at': conv.created_at.isoformat(),
            'updated_at': conv.updated_at.isoformat(),
        })
    return jsonify(result)

@app.route('/api/user', methods=['GET'])
@login_required
def api_user():
    return jsonify({
        'id': current_user.id,
        'username': current_user.username,
        'email': current_user.email,
        'created_at': current_user.created_at.isoformat() if current_user.created_at else None,
    })

@app.route('/api/user/profile', methods=['GET', 'PUT'])
@jwt_required()
def profile():
    """Get or update user profile"""
    if request.method == 'GET':
        # Return current user profile
        user = get_api_user()
        return jsonify({
            'user': {
                'id': user.id,
                'username': user.username,
                'email': user.email,
                'first_name': getattr(user, 'first_name', ''),
                'last_name': getattr(user, 'last_name', ''),
                'phone_number': getattr(user, 'phone_number', ''),
                'profile_picture': getattr(user, 'profile_picture', ''),
                'created_at': user.created_at.isoformat() if user.created_at else None,
            }
        }), 200
    
    elif request.method == 'PUT':
        # Update user profile
        try:
            user = get_api_user()
            data = request.get_json()
            if not data:
                return jsonify({'message': 'No data provided'}), 400
            
            # Update fields if provided
            if 'first_name' in data:
                user.first_name = data['first_name']
            if 'last_name' in data:
                user.last_name = data['last_name']
            if 'phone_number' in data:
                user.phone_number = data['phone_number']
            if 'username' in data:
                user.username = data['username']
            if 'email' in data and data['email'] != user.email:
                # Check if email is already taken
                existing_user = User.query.filter_by(email=data['email']).first()
                if existing_user and existing_user.id != user.id:
                    return jsonify({'message': 'Email already exists'}), 400
                user.email = data['email']
            
            db.session.commit()
            
            return jsonify({
                'message': 'Profile updated successfully',
                'user': {
                    'id': user.id,
                    'username': user.username,
                    'email': user.email,
                    'first_name': getattr(user, 'first_name', ''),
                    'last_name': getattr(user, 'last_name', ''),
                    'phone_number': getattr(user, 'phone_number', ''),
                    'profile_picture': getattr(user, 'profile_picture', ''),
                }
            }), 200
            
        except Exception as e:
            print(f"Update profile error: {str(e)}")
            return jsonify({'message': 'Failed to update profile'}), 500

@app.route('/api/user/upload-profile-picture', methods=['POST'])
@jwt_required()
def upload_profile_picture():
    """Upload profile picture"""
    try:
        if 'file' not in request.files:
            return jsonify({'message': 'No file provided'}), 400
        
        file = request.files['file']
        if file.filename == '':
            return jsonify({'message': 'No file selected'}), 400
        
        # Generate secure filename
        filename = secure_filename(file.filename)
        if not filename:
            return jsonify({'message': 'Invalid filename'}), 400
        
        # Create upload directory if it doesn't exist
        upload_dir = os.path.join(app.root_path, 'static', 'uploads', 'profile_pictures')
        os.makedirs(upload_dir, exist_ok=True)
        
        # Save file
        file_path = os.path.join(upload_dir, filename)
        file.save(file_path)
        
        # Update user profile picture
        user = get_api_user()
        user.profile_picture = f"uploads/profile_pictures/{filename}"
        db.session.commit()
        
        return jsonify({
            'message': 'Profile picture uploaded successfully',
            'profile_picture': user.profile_picture
        }), 200
        
    except Exception as e:
        print(f"Upload profile picture error: {str(e)}")
        return jsonify({'message': 'Failed to upload profile picture'}), 500

# Analytics endpoints
@app.route('/api/analytics/listings', methods=['GET'])
@login_required
def get_listings_analytics():
    """Get analytics for all user's listings"""
    try:
        from models import ListingAnalytics
        
        # Get all cars owned by current user
        user_cars = Car.query.filter_by(user_id=current_user.id).all()
        car_ids = [car.id for car in user_cars]
        
        # Get analytics for these cars
        analytics = ListingAnalytics.query.filter(ListingAnalytics.car_id.in_(car_ids)).all()
        
        # Create analytics for cars that don't have analytics yet
        existing_car_ids = [a.car_id for a in analytics]
        for car in user_cars:
            if car.id not in existing_car_ids:
                new_analytics = ListingAnalytics(car_id=car.id)
                db.session.add(new_analytics)
        
        db.session.commit()
        
        # Get updated analytics
        analytics = ListingAnalytics.query.filter(ListingAnalytics.car_id.in_(car_ids)).all()
        
        return jsonify([a.to_dict() for a in analytics])
        
    except Exception as e:
        return jsonify({'error': str(e)}), 500

@app.route('/api/analytics/listings/<int:car_id>', methods=['GET'])
@login_required
def get_listing_analytics(car_id):
    """Get analytics for a specific listing"""
    try:
        from models import ListingAnalytics
        
        # Verify the car belongs to current user
        car = Car.query.filter_by(id=car_id, user_id=current_user.id).first()
        if not car:
            return jsonify({'error': 'Listing not found'}), 404
        
        # Get or create analytics for this car
        analytics = ListingAnalytics.query.filter_by(car_id=car_id).first()
        if not analytics:
            analytics = ListingAnalytics(car_id=car_id)
            db.session.add(analytics)
            db.session.commit()
        
        return jsonify(analytics.to_dict())
        
    except Exception as e:
        return jsonify({'error': str(e)}), 500

@app.route('/api/analytics/track/view', methods=['POST'])
@login_required
def track_view():
    """Track a view for a listing"""
    try:
        from models import ListingAnalytics
        
        data = request.get_json()
        car_id = data.get('listing_id')
        
        if not car_id:
            return jsonify({'error': 'listing_id required'}), 400
        
        # Verify the car belongs to current user
        car = Car.query.filter_by(id=car_id, user_id=current_user.id).first()
        if not car:
            return jsonify({'error': 'Listing not found'}), 404
        
        # Get or create analytics
        analytics = ListingAnalytics.query.filter_by(car_id=car_id).first()
        if not analytics:
            analytics = ListingAnalytics(car_id=car_id)
            db.session.add(analytics)
        
        analytics.increment_views()
        
        return jsonify({'success': True})
        
    except Exception as e:
        return jsonify({'error': str(e)}), 500

@app.route('/api/analytics/track/message', methods=['POST'])
@login_required
def track_message():
    """Track a message for a listing"""
    try:
        from models import ListingAnalytics
        
        data = request.get_json()
        car_id = data.get('listing_id')
        
        if not car_id:
            return jsonify({'error': 'listing_id required'}), 400
        
        # Verify the car belongs to current user
        car = Car.query.filter_by(id=car_id, user_id=current_user.id).first()
        if not car:
            return jsonify({'error': 'Listing not found'}), 404
        
        # Get or create analytics
        analytics = ListingAnalytics.query.filter_by(car_id=car_id).first()
        if not analytics:
            analytics = ListingAnalytics(car_id=car_id)
            db.session.add(analytics)
        
        analytics.increment_messages()
        
        return jsonify({'success': True})
        
    except Exception as e:
        return jsonify({'error': str(e)}), 500

@app.route('/api/analytics/track/call', methods=['POST'])
@login_required
def track_call():
    """Track a call for a listing"""
    try:
        from models import ListingAnalytics
        
        data = request.get_json()
        car_id = data.get('listing_id')
        
        if not car_id:
            return jsonify({'error': 'listing_id required'}), 400
        
        # Verify the car belongs to current user
        car = Car.query.filter_by(id=car_id, user_id=current_user.id).first()
        if not car:
            return jsonify({'error': 'Listing not found'}), 404
        
        # Get or create analytics
        analytics = ListingAnalytics.query.filter_by(car_id=car_id).first()
        if not analytics:
            analytics = ListingAnalytics(car_id=car_id)
            db.session.add(analytics)
        
        analytics.increment_calls()
        
        return jsonify({'success': True})
        
    except Exception as e:
        return jsonify({'error': str(e)}), 500

@app.route('/api/analytics/track/share', methods=['POST'])
@login_required
def track_share():
    """Track a share for a listing"""
    try:
        from models import ListingAnalytics
        
        data = request.get_json()
        car_id = data.get('listing_id')
        
        if not car_id:
            return jsonify({'error': 'listing_id required'}), 400
        
        # Verify the car belongs to current user
        car = Car.query.filter_by(id=car_id, user_id=current_user.id).first()
        if not car:
            return jsonify({'error': 'Listing not found'}), 404
        
        # Get or create analytics
        analytics = ListingAnalytics.query.filter_by(car_id=car_id).first()
        if not analytics:
            analytics = ListingAnalytics(car_id=car_id)
            db.session.add(analytics)
        
        analytics.increment_shares()
        
        return jsonify({'success': True})
        
    except Exception as e:
        return jsonify({'error': str(e)}), 500

@app.route('/api/analytics/track/favorite', methods=['POST'])
@login_required
def track_favorite():
    """Track a favorite for a listing"""
    try:
        from models import ListingAnalytics
        
        data = request.get_json()
        car_id = data.get('listing_id')
        
        if not car_id:
            return jsonify({'error': 'listing_id required'}), 400
        
        # Verify the car belongs to current user
        car = Car.query.filter_by(id=car_id, user_id=current_user.id).first()
        if not car:
            return jsonify({'error': 'Listing not found'}), 404
        
        # Get or create analytics
        analytics = ListingAnalytics.query.filter_by(car_id=car_id).first()
        if not analytics:
            analytics = ListingAnalytics(car_id=car_id)
            db.session.add(analytics)
        
        analytics.increment_favorites()
        
        return jsonify({'success': True})
        
    except Exception as e:
        return jsonify({'error': str(e)}), 500

@app.route('/dev/seed')
def dev_seed():
    """Development helper: top up listings to the requested total count.
    Usage: /dev/seed?count=200
    """
    try:
        target = int(request.args.get('count', '200'))
    except Exception:
        target = 200
    # Ensure car models exist
    if CarModel.query.count() == 0:
        populate_car_models()
    # Top up to target
    seed_example_listings(target)
    return jsonify({
        'ok': True,
        'target': target,
        'total': Car.query.count()
    })

@app.route('/signup', methods=['GET', 'POST'])
def signup():
    if request.method == 'POST':
        username = request.form['username']
        email = request.form['email']
        password = request.form['password']
        if User.query.filter((User.username == username) | (User.email == email)).first():
            flash('Username or email already exists.', 'danger')
            return render_template('signup.html')
        hashed_password = generate_password_hash(password)
        user = User(username=username, email=email, password=hashed_password)
        db.session.add(user)
        db.session.commit()
        flash('Account created! Please log in.', 'success')
        return redirect(url_for('login'))
    return render_template('signup.html')

@app.route('/login', methods=['GET', 'POST'])
def login():
    if request.method == 'POST':
        username = request.form['username']
        password = request.form['password']
        user = User.query.filter_by(username=username).first()
        if user and check_password_hash(user.password, password):
            login_user(user)
            session.permanent = True  # Keep user logged in
            flash('Logged in successfully!', 'success')
            return redirect(url_for('home'))
        else:
            flash('Invalid username or password.', 'danger')
    return render_template('login.html')

@app.route('/logout')
@login_required
def logout():
    logout_user()
    flash('Logged out successfully.', 'success')
    return redirect(url_for('login'))

@app.route('/favorite/<int:car_id>', methods=['POST'])
@login_required
def toggle_favorite(car_id):
    car = Car.query.get_or_404(car_id)
    favorite = Favorite.query.filter_by(user_id=current_user.id, car_id=car_id).first()
    if favorite:
        db.session.delete(favorite)
        db.session.commit()
        return jsonify({'favorited': False})
    else:
        new_fav = Favorite(user_id=current_user.id, car_id=car_id)
        db.session.add(new_fav)
        db.session.commit()
        return jsonify({'favorited': True})

@app.route('/favorites')
@login_required
def favorites():
    favs = Favorite.query.filter_by(user_id=current_user.id).all()
    cars = [fav.car for fav in favs]
    return render_template('favorites.html', cars=cars)

# Chat Routes
@app.route('/chat')
@login_required
def chat_list():
    """Show all conversations for the current user"""
    # Get conversations where user is either buyer or seller
    conversations = Conversation.query.filter(
        db.or_(
            Conversation.buyer_id == current_user.id,
            Conversation.seller_id == current_user.id
        )
    ).order_by(Conversation.updated_at.desc()).all()
    
    return render_template('chat_list.html', conversations=conversations)

@app.route('/chat/<int:car_id>')
@login_required
def start_chat(car_id):
    """Start a new conversation or redirect to existing one"""
    car = Car.query.get_or_404(car_id)
    
    # Check if user is trying to chat with their own car
    if car.user_id == current_user.id:
        flash('You cannot start a conversation with your own listing.', 'warning')
        return redirect(url_for('car_detail', car_id=car_id))
    
    # Check if conversation already exists
    existing_conversation = Conversation.query.filter_by(
        car_id=car_id,
        buyer_id=current_user.id,
        seller_id=car.user_id
    ).first()
    
    if existing_conversation:
        return redirect(url_for('chat_conversation', conversation_id=existing_conversation.id))
    
    # Create new conversation
    conversation = Conversation(
        car_id=car_id,
        buyer_id=current_user.id,
        seller_id=car.user_id
    )
    db.session.add(conversation)
    db.session.commit()
    
    return redirect(url_for('chat_conversation', conversation_id=conversation.id))

@app.route('/chat/conversation/<int:conversation_id>')
@login_required
def chat_conversation(conversation_id):
    """Show a specific conversation"""
    conversation = Conversation.query.get_or_404(conversation_id)
    
    # Check if user is part of this conversation
    if conversation.buyer_id != current_user.id and conversation.seller_id != current_user.id:
        flash('You do not have access to this conversation.', 'danger')
        return redirect(url_for('chat_list'))
    
    # Mark messages as read
    unread_messages = Message.query.filter_by(
        conversation_id=conversation_id,
        is_read=False
    ).filter(Message.sender_id != current_user.id).all()
    
    for message in unread_messages:
        message.is_read = True
    db.session.commit()
    
    return render_template('chat_conversation.html', conversation=conversation)

@app.route('/api/chat/<int:conversation_id>/messages')
@login_required
def get_messages(conversation_id):
    """API endpoint to get messages for a conversation"""
    conversation = Conversation.query.get_or_404(conversation_id)
    
    # Check if user is part of this conversation
    if conversation.buyer_id != current_user.id and conversation.seller_id != current_user.id:
        return jsonify({'error': 'Unauthorized'}), 403
    
    messages = Message.query.filter_by(conversation_id=conversation_id).all()
    
    return jsonify([{
        'id': msg.id,
        'content': msg.content,
        'sender_id': msg.sender_id,
        'sender_name': msg.sender.username,
        'is_read': msg.is_read,
        'created_at': msg.created_at.isoformat(),
        'is_own_message': msg.sender_id == current_user.id
    } for msg in messages])

@app.route('/api/chat/<int:conversation_id>/send', methods=['POST'])
@login_required
def send_message(conversation_id):
    """API endpoint to send a message"""
    conversation = Conversation.query.get_or_404(conversation_id)
    
    # Check if user is part of this conversation
    if conversation.buyer_id != current_user.id and conversation.seller_id != current_user.id:
        return jsonify({'error': 'Unauthorized'}), 403
    
    data = request.get_json()
    content = data.get('content', '').strip()
    
    if not content:
        return jsonify({'error': 'Message content is required'}), 400
    
    # Create new message
    message = Message(
        conversation_id=conversation_id,
        sender_id=current_user.id,
        content=content
    )
    db.session.add(message)
    
    # Update conversation timestamp
    conversation.updated_at = datetime.utcnow()
    
    db.session.commit()
    
    return jsonify({
        'id': message.id,
        'content': message.content,
        'sender_id': message.sender_id,
        'sender_name': message.sender.username,
        'is_read': message.is_read,
        'created_at': message.created_at.isoformat(),
        'is_own_message': True
    })

@app.route('/api/chat/unread_count')
@login_required
def get_unread_count():
    """Get unread message count for current user"""
    unread_count = Message.query.join(Conversation).filter(
        db.or_(
            Conversation.buyer_id == current_user.id,
            Conversation.seller_id == current_user.id
        ),
        Message.sender_id != current_user.id,
        Message.is_read == False
    ).count()
    
    return jsonify({'unread_count': unread_count})

# FIB Payment Configuration
FIB_CONFIG = {
    'merchant_id': os.environ.get('FIB_MERCHANT_ID', 'your_merchant_id'),
    'api_key': os.environ.get('FIB_API_KEY', 'your_api_key'),
    'secret_key': os.environ.get('FIB_SECRET_KEY', 'your_secret_key'),
    'base_url': os.environ.get('FIB_BASE_URL', 'https://api.fib.com'),  # Replace with actual FIB API URL
    'callback_url': os.environ.get('FIB_CALLBACK_URL', 'https://yourdomain.com/payment/callback'),
    'return_url': os.environ.get('FIB_RETURN_URL', 'https://yourdomain.com/payment/return')
}

# Listing Fee Configuration
LISTING_FEE_CONFIG = {
    'amount': 50.0,  # $50 listing fee
    'currency': 'USD',
    'description': 'Car Listing Fee'
}

def generate_fib_signature(data, secret_key):
    """Generate FIB API signature"""
    # Sort the data by keys
    sorted_data = dict(sorted(data.items()))
    
    # Create query string
    query_string = urlencode(sorted_data)
    
    # Create signature
    signature = hmac.new(
        secret_key.encode('utf-8'),
        query_string.encode('utf-8'),
        hashlib.sha256
    ).hexdigest()
    
    return signature

def create_fib_payment_request(payment):
    """Create payment request for FIB API"""
    if payment.payment_type == 'listing_fee':
        description = f"Listing fee for car listing"
    else:
        description = f"Payment for {payment.car.brand} {payment.car.model}" if payment.car else "Payment"
    
    payment_data = {
        'merchant_id': FIB_CONFIG['merchant_id'],
        'amount': str(payment.amount),
        'currency': payment.currency,
        'order_id': payment.payment_id,
        'description': description,
        'customer_email': payment.user.email,
        'customer_name': payment.user.username,
        'customer_phone': payment.user.phone if hasattr(payment.user, 'phone') else '',
        'callback_url': FIB_CONFIG['callback_url'],
        'return_url': FIB_CONFIG['return_url'],
        'timestamp': str(int(datetime.utcnow().timestamp()))
    }
    
    # Generate signature
    signature = generate_fib_signature(payment_data, FIB_CONFIG['secret_key'])
    payment_data['signature'] = signature
    
    return payment_data

@app.route('/payment/listing_fee', methods=['GET', 'POST'])
@login_required
def listing_fee_payment():
    """Handle listing fee payment"""
    if request.method == 'POST':
        # Create payment record for listing fee
        payment = Payment(
            payment_id=str(uuid.uuid4()),
            user_id=current_user.id,
            amount=LISTING_FEE_CONFIG['amount'],
            currency=LISTING_FEE_CONFIG['currency'],
            payment_type='listing_fee'
        )
        
        db.session.add(payment)
        db.session.commit()
        
        # Create FIB payment request
        fib_request_data = create_fib_payment_request(payment)
        
        # Log the transaction
        transaction = PaymentTransaction(
            payment_id=payment.id,
            transaction_type='init',
            amount=payment.amount,
            status='pending',
            response_data=json.dumps(fib_request_data)
        )
        db.session.add(transaction)
        db.session.commit()
        
        # Redirect to payment gateway
        return render_template('payment_gateway.html', 
                             payment=payment, 
                             fib_data=fib_request_data,
                             payment_type='listing_fee')
    
    return render_template('listing_fee_payment.html')

@app.route('/payment/gateway/<int:payment_id>', methods=['GET', 'POST'])
@login_required
def payment_gateway(payment_id):
    """Payment gateway page (simulated FIB interface)"""
    payment = Payment.query.get_or_404(payment_id)
    
    # Verify user is the one making the payment
    if payment.user_id != current_user.id:
        flash('Unauthorized access to payment.', 'danger')
        return redirect(url_for('home'))
    
    if request.method == 'POST':
        action = request.form.get('action')
        
        if action == 'complete':
            # Simulate successful payment
            payment.status = 'completed'
            payment.transaction_reference = f"FIB_{uuid.uuid4().hex[:16].upper()}"
            
            # Log successful transaction
            transaction = PaymentTransaction(
                payment_id=payment.id,
                transaction_type='callback',
                fib_transaction_id=payment.transaction_reference,
                amount=payment.amount,
                status='completed',
                response_data=json.dumps({'status': 'success', 'transaction_id': payment.transaction_reference})
            )
            db.session.add(transaction)
            db.session.commit()
            
            if payment.payment_type == 'listing_fee':
                # If this payment is tied to a car listing, activate it so it appears in search
                if payment.car_id:
                    car = Car.query.get(payment.car_id)
                    if car and car.status != 'active':
                        car.status = 'active'
                        db.session.commit()
                        flash('Listing fee paid successfully! Your listing is now live.', 'success')
                        return redirect(url_for('car_detail', car_id=car.id))
                # Fallback for standalone listing-fee payments without a car attached
                flash('Listing fee paid successfully! You can now add your car listing.', 'success')
                return redirect(url_for('add_car'))
            else:
                flash('Payment completed successfully!', 'success')
                return redirect(url_for('payment_success', payment_id=payment.id))
        
        elif action == 'cancel':
            # Simulate cancelled payment
            payment.status = 'cancelled'
            
            # Log cancelled transaction
            transaction = PaymentTransaction(
                payment_id=payment.id,
                transaction_type='callback',
                amount=payment.amount,
                status='cancelled',
                response_data=json.dumps({'status': 'cancelled'})
            )
            db.session.add(transaction)
            db.session.commit()
            
            flash('Payment was cancelled.', 'info')
            return redirect(url_for('payment_cancelled', payment_id=payment.id))
    
    return render_template('payment_gateway.html', payment=payment, payment_type=payment.payment_type)

@app.route('/payment/callback', methods=['POST'])
def payment_callback():
    """FIB payment callback/webhook"""
    try:
        data = request.get_json()
        
        # Verify signature (in real implementation)
        # signature = request.headers.get('X-FIB-Signature')
        # if not verify_fib_signature(data, signature):
        #     return jsonify({'error': 'Invalid signature'}), 400
        
        payment_id = data.get('order_id')
        status = data.get('status')
        transaction_id = data.get('transaction_id')
        
        payment = Payment.query.filter_by(payment_id=payment_id).first()
        if not payment:
            return jsonify({'error': 'Payment not found'}), 404
        
        # Update payment status
        payment.status = status
        if transaction_id:
            payment.transaction_reference = transaction_id
        
        # Log transaction
        transaction = PaymentTransaction(
            payment_id=payment.id,
            transaction_type='webhook',
            fib_transaction_id=transaction_id,
            amount=payment.amount,
            status=status,
            response_data=json.dumps(data)
        )
        db.session.add(transaction)
        # If a listing-fee payment tied to a car is completed via webhook, activate the car
        if payment.payment_type == 'listing_fee' and payment.car_id and status in ('completed', 'success', 'paid'):
            car = Car.query.get(payment.car_id)
            if car and car.status != 'active':
                car.status = 'active'
        db.session.commit()
        
        return jsonify({'status': 'success'})
    
    except Exception as e:
        return jsonify({'error': str(e)}), 500

@app.route('/payment/success/<int:payment_id>')
@login_required
def payment_success(payment_id):
    """Payment success page"""
    payment = Payment.query.get_or_404(payment_id)
    
    if payment.user_id != current_user.id:
        flash('Unauthorized access.', 'danger')
        return redirect(url_for('home'))
    
    return render_template('payment_success.html', payment=payment)

@app.route('/payment/cancelled/<int:payment_id>')
@login_required
def payment_cancelled(payment_id):
    """Payment cancelled page"""
    payment = Payment.query.get_or_404(payment_id)
    
    if payment.user_id != current_user.id:
        flash('Unauthorized access.', 'danger')
        return redirect(url_for('home'))
    
    return render_template('payment_cancelled.html', payment=payment)

@app.route('/payment/history')
@login_required
def payment_history():
    """User's payment history"""
    payments = Payment.query.filter_by(user_id=current_user.id).order_by(Payment.created_at.desc()).all()
    
    return render_template('payment_history.html', payments=payments)

@app.route('/api/payment/status/<int:payment_id>')
@login_required
def payment_status(payment_id):
    """Get payment status via API"""
    payment = Payment.query.get_or_404(payment_id)
    
    if payment.user_id != current_user.id:
        return jsonify({'error': 'Unauthorized'}), 403
    
    return jsonify({
        'payment_id': payment.payment_id,
        'status': payment.status,
        'amount': payment.amount,
        'currency': payment.currency,
        'payment_type': payment.payment_type,
        'created_at': payment.created_at.isoformat(),
        'transaction_reference': payment.transaction_reference
    })

@app.route('/admin/activate_all_cars')
@login_required
def activate_all_cars():
    # Only allow admin user (customize as needed)
    if not current_user.is_authenticated or current_user.username != 'admin':
        flash('Unauthorized.', 'danger')
        return redirect(url_for('home'))
    Car.query.update({Car.status: 'active'})
    db.session.commit()
    flash('All car listings have been activated and are now visible.', 'success')
    return redirect(url_for('home'))

# Move get_brands here so it is defined before search

def get_brands():
    return [
        'bmw', 'mercedes-benz', 'audi', 'toyota', 'honda', 'nissan', 'ford', 
        'chevrolet', 'hyundai', 'kia', 'volkswagen', 'volvo', 'lexus', 'porsche',
        'jaguar', 'land-rover', 'mini', 'smart', 'subaru', 'mazda', 'mitsubishi',
        'suzuki', 'ferrari', 'lamborghini', 'bentley', 'rolls-royce', 'aston-martin',
        'mclaren', 'maserati', 'bugatti', 'pagani', 'koenigsegg', 'alfa-romeo',
        'fiat', 'lancia', 'abarth', 'opel', 'vauxhall', 'peugeot', 'citroen',
        'renault', 'ds', 'seat', 'skoda', 'dacia', 'cadillac', 'buick', 'gmc',
        'chrysler', 'dodge', 'jeep', 'ram', 'lincoln', 'alpina', 'brabus',
        'mansory', 'genesis', 'isuzu', 'datsun', 'ktm', 'jac-motors', 'jac-trucks',
        'byd', 'geely-zgh', 'great-wall-motors', 'chery-automobile', 'baic',
        'gac', 'saic', 'mg', 'bestune', 'hongqi', 'dongfeng-motor', 'faw',
        'faw-jiefang', 'foton', 'leapmotor', 'man', 'iran-khodro'
    ]

# Google login/signup route
@app.route('/google_login')
def google_login():
    try:
        if not google.authorized:
            return redirect(url_for('google.login'))
        resp = google.get("/oauth2/v2/userinfo")
    except TokenExpiredError:
        session.pop('google_oauth_token', None)
        flash("Your Google login session expired. Please log in again.", "warning")
        return redirect(url_for('google.login'))
    if not resp.ok:
        flash("Failed to fetch user info from Google.", "danger")
        return redirect(url_for('login'))
    info = resp.json()
    email = info["email"]
    username = info.get("name", email.split("@")[0])
    user = User.query.filter_by(email=email).first()
    if session.pop('google_oauth_state', None) == 'signup':
        if user:
            flash("An account with this Google email already exists. Please log in instead.", "warning")
            return redirect(url_for('login'))
        # Create a new user
        user = User(username=username, email=email, password="google-oauth")
        db.session.add(user)
        db.session.commit()
        login_user(user)
        flash("Signed up and logged in with Google!", "success")
        return redirect(url_for('home'))
    else:
        if not user:
            # Create a new user
            user = User(username=username, email=email, password="google-oauth")
            db.session.add(user)
            db.session.commit()
        login_user(user)
        flash("Logged in with Google!", "success")
        return redirect(url_for('home'))

@app.route('/google_signup')
def google_signup():
    # Add prompt=select_account and state=signup to force Google account chooser and mark intent
    google_login_url = url_for('google.login')
    return redirect(f"{google_login_url}?prompt=select_account&state=signup")

@oauth_authorized.connect_via(google_bp)
def google_logged_in(blueprint, token):
    # Always redirect to your handler after OAuth
    return redirect(url_for("google_login"))

if __name__ == '__main__':
    with app.app_context():
        try:
            # Ensure instance directory exists
            instance_dir = os.path.join(BASE_DIR, 'instance')
            os.makedirs(instance_dir, exist_ok=True)
            # Always ensure tables exist (safe no-op if already created)
            try:
                db.create_all()
                print("Ensured database tables exist.")
            except Exception as e:
                print(f"Error creating tables: {str(e)}")

            # Seed demo data if empty so the mobile app has content
            try:
                from sqlalchemy import inspect
                inspector = inspect(db.engine)
                # If the 'user' table doesn't exist or there are no cars, seed
                needs_seed = False
                try:
                    needs_seed = (db.session.execute(db.text('SELECT COUNT(*) FROM car')).scalar() or 0) == 0
                except Exception:
                    needs_seed = True
                if needs_seed:
                    populate_car_models()
                    seed_example_listings(100)
                    print("Seeded example listings.")
            except Exception:
                # Best-effort seeding; do not block startup
                pass
        except Exception as e:
            print(f"Error initializing database: {str(e)}")
            raise e

    # Serve static files
    @app.route('/static/<path:filename>')
    def static_files(filename):
        return send_from_directory(os.path.join(app.root_path, 'static'), filename)
    
    # AI Analysis endpoints
    @app.route('/api/analyze-car-image', methods=['POST'])
    @jwt_required()
    def analyze_car_image():
        """Analyze uploaded car image using AI"""
        try:
            current_user = get_current_user()
            if not current_user:
                return jsonify({'error': 'User not found'}), 404
            
            if 'image' not in request.files:
                return jsonify({'error': 'No image file provided'}), 400
            
            file = request.files['image']
            if file.filename == '':
                return jsonify({'error': 'No image file selected'}), 400
            
            if file and allowed_file(file.filename):
                # Save uploaded image temporarily
                filename = secure_filename(file.filename)
                timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
                filename = f"ai_analysis_{timestamp}_{filename}"
                temp_path = os.path.join(app.config['UPLOAD_FOLDER'], 'temp', filename)
                os.makedirs(os.path.dirname(temp_path), exist_ok=True)
                file.save(temp_path)
                
                try:
                    # Import AI service
                    from .ai_service import car_analysis_service
                    
                    # Analyze the image using AI
                    analysis_result = car_analysis_service.analyze_car_image(temp_path)
                    
                    # Clean up temporary file
                    os.remove(temp_path)
                    
                    if 'error' in analysis_result:
                        return jsonify({'error': analysis_result['error']}), 500
                    
                    return jsonify({
                        'success': True,
                        'analysis': analysis_result,
                        'message': 'Car image analyzed successfully'
                    }), 200
                    
                except Exception as e:
                    # Clean up temporary file on error
                    if os.path.exists(temp_path):
                        os.remove(temp_path)
                    raise e
            else:
                return jsonify({'error': 'Invalid file type'}), 400
                
        except Exception as e:
            print(f"Error analyzing car image: {str(e)}")
            return jsonify({'error': 'Failed to analyze car image'}), 500

    @app.route('/api/test-ai', methods=['GET'])
    def test_ai():
        """Test endpoint to verify AI service is working"""
        try:
            from .ai_service import car_analysis_service
            return jsonify({
                'success': True,
                'message': 'AI service is working',
                'service_initialized': car_analysis_service.initialized
            }), 200
        except Exception as e:
            return jsonify({
                'success': False,
                'error': str(e)
            }), 500

    @app.route('/api/process-car-images-test', methods=['POST'])
    def process_car_images_test():
        """Process multiple car images and blur license plates (test version without auth).
        Robust to missing/unknown file extensions and always returns processed entries if possible.
        """
        try:
            files = request.files.getlist('images')
            if not files:
                return jsonify({'error': 'No image files provided'}), 400

            want_b64 = request.args.get('inline_base64') == '1'
            processed_images = []
            processed_images_base64 = []
            summaries = []
            print(f"[BLUR] /api/process-car-images-test start: files={len(files)} want_b64={want_b64}")

            for file in files:
                if not file:
                    continue
                # Derive a safe filename and extension; default to .jpg when unknown
                raw_name = (file.filename or 'upload.jpg')
                name_only, ext = os.path.splitext(raw_name)
                ext_l = (ext.lower().lstrip('.') or 'jpg')
                if ext_l not in ALLOWED_EXTENSIONS:
                    ext_l = 'jpg'
                safe_base = secure_filename(name_only) or 'upload'
                timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
                temp_filename = f"processed_{timestamp}_{safe_base}.{ext_l}"
                temp_path = os.path.join(app.config['UPLOAD_FOLDER'], 'temp', temp_filename)
                os.makedirs(os.path.dirname(temp_path), exist_ok=True)
                try:
                    print(f"[BLUR] Saving upload: name={raw_name} -> {temp_path}")
                    file.save(temp_path)
                    try:
                        sz = os.path.getsize(temp_path)
                        print(f"[BLUR] Saved temp size={sz} bytes")
                    except Exception:
                        pass
                except Exception as e:
                    print(f"[BLUR] Error saving upload {raw_name}: {e}")
                    summaries.append({'file': raw_name, 'status': 'save_error', 'error': str(e)})
                    continue

                try:
                    # Import AI service
                    from .ai_service import car_analysis_service
                    # Process image (blur license plates)
                    print(f"[BLUR] Processing with AI: {temp_path}")
                    strict = (request.args.get('strict') == '1' or request.args.get('strict_blur') == '1')
                    mode = request.args.get('mode', 'auto')
                    # Optional: force OCR-only via debug flag
                    debug_force = request.args.get('debug_force', '')
                    # Always enable debug overlays if requested
                    if debug_force == 'ocr':
                        mode = 'ocr_only_debug'
                    processed_path = car_analysis_service._blur_license_plates(temp_path, strict=strict, mode=mode)
                    print(f"[BLUR] AI processed -> {processed_path}")

                    # Move processed image to permanent location
                    final_filename = f"processed_{timestamp}_{safe_base}.{ext_l}"
                    final_path = os.path.join(app.config['UPLOAD_FOLDER'], 'car_photos', final_filename)
                    os.makedirs(os.path.dirname(final_path), exist_ok=True)

                    import shutil
                    shutil.copy2(processed_path, final_path)

                    # Inline base64 if requested (or always include to help emulator)
                    if True:
                        try:
                            with open(final_path, 'rb') as f:
                                encoded = base64.b64encode(f.read()).decode('utf-8')
                                mime = 'image/jpeg' if ext_l in ['jpg', 'jpeg'] else ('image/png' if ext_l == 'png' else ('image/webp' if ext_l == 'webp' else 'image/*'))
                                processed_images_base64.append(f"data:{mime};base64,{encoded}")
                        except Exception as e:
                            print(f"[BLUR] Error encoding image to base64: {str(e)}")

                    # Clean up temporary files
                    try:
                        if os.path.exists(temp_path):
                            os.remove(temp_path)
                        if processed_path != temp_path and os.path.exists(processed_path):
                            os.remove(processed_path)
                    except Exception:
                        pass

                    processed_images.append(f"uploads/car_photos/{final_filename}")
                    summaries.append({'file': raw_name, 'status': 'processed', 'output': f"uploads/car_photos/{final_filename}"})

                except Exception as e:
                    # Clean up on error and still try to return original saved file
                    print(f"[BLUR] Error processing image {raw_name}: {str(e)}")
                    try:
                        final_filename = f"processed_{timestamp}_{safe_base}.{ext_l}"
                        final_path = os.path.join(app.config['UPLOAD_FOLDER'], 'car_photos', final_filename)
                        os.makedirs(os.path.dirname(final_path), exist_ok=True)
                        import shutil
                        shutil.copy2(temp_path, final_path)
                        processed_images.append(f"uploads/car_photos/{final_filename}")
                        # ALSO include base64 on fallback so client never has to download
                        try:
                            with open(final_path, 'rb') as f:
                                encoded = base64.b64encode(f.read()).decode('utf-8')
                                mime = 'image/jpeg' if ext_l in ['jpg', 'jpeg'] else ('image/png' if ext_l == 'png' else ('image/webp' if ext_l == 'webp' else 'image/*'))
                                processed_images_base64.append(f"data:{mime};base64,{encoded}")
                        except Exception as e3:
                            print(f"[BLUR] Error encoding fallback base64: {e3}")
                        summaries.append({'file': raw_name, 'status': 'fallback_copy', 'output': f"uploads/car_photos/{final_filename}", 'error': str(e)})
                    except Exception as e2:
                        print(f"[BLUR] Error copying fallback image {raw_name}: {e2}")
                        summaries.append({'file': raw_name, 'status': 'fallback_error', 'error': str(e2)})
                    finally:
                        try:
                            if os.path.exists(temp_path):
                                os.remove(temp_path)
                        except Exception:
                            pass

            print(f"[BLUR] Completed: processed={len(processed_images)}")
            sys.stdout.flush()
            result_payload = {
                'success': True,
                'processed_images': processed_images,
                'processed_images_base64': processed_images_base64,
                'summary': summaries,
                'message': f'Processed {len(processed_images)} images successfully'
            }
            body = json.dumps(result_payload, ensure_ascii=False)
            print("[API] Successfully sending JSON response")
            print("[DONE] Response sent successfully")
            sys.stdout.flush()
            return Response(body, status=200, mimetype='application/json')

        except Exception as e:
            try:
                traceback.print_exc()
            except Exception:
                pass
            print(f"[BLUR] Fatal error processing car images: {str(e)}")
            sys.stdout.flush()
            err = {'error': str(e)}
            body = json.dumps(err, ensure_ascii=False)
            return Response(body, status=500, mimetype='application/json')

    @app.route('/api/process-car-images', methods=['POST'])
    @jwt_required()
    def process_car_images():
        """Process multiple car images and blur license plates"""
        try:
            current_user = get_current_user()
            if not current_user:
                return jsonify({'error': 'User not found'}), 404
            
            files = request.files.getlist('images')
            if not files:
                return jsonify({'error': 'No image files provided'}), 400
            
            processed_images = []
            
            for file in files:
                if file and allowed_file(file.filename):
                    # Save uploaded image temporarily
                    filename = secure_filename(file.filename)
                    timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
                    filename = f"processed_{timestamp}_{filename}"
                    temp_path = os.path.join(app.config['UPLOAD_FOLDER'], 'temp', filename)
                    os.makedirs(os.path.dirname(temp_path), exist_ok=True)
                    file.save(temp_path)
                    
                    try:
                        # Import AI service
                        from .ai_service import car_analysis_service
                        
                        # Process image (blur license plates) with optional params
                        strict = (request.args.get('strict') == '1' or request.args.get('strict_blur') == '1')
                        mode = request.args.get('mode', 'auto')
                        debug_force = request.args.get('debug_force', '')
                        if debug_force == 'ocr':
                            mode = 'ocr_only_debug'
                        processed_path = car_analysis_service._blur_license_plates(temp_path, strict=strict, mode=mode)
                        
                        # Move processed image to permanent location
                        final_filename = f"processed_{timestamp}_{secure_filename(file.filename)}"
                        final_path = os.path.join(app.config['UPLOAD_FOLDER'], 'car_photos', final_filename)
                        os.makedirs(os.path.dirname(final_path), exist_ok=True)
                        
                        # Copy processed image to final location
                        import shutil
                        shutil.copy2(processed_path, final_path)
                        
                        # Clean up temporary files
                        os.remove(temp_path)
                        if processed_path != temp_path:
                            os.remove(processed_path)
                        
                        processed_images.append(f"uploads/car_photos/{final_filename}")
                        
                    except Exception as e:
                        # Clean up on error
                        if os.path.exists(temp_path):
                            os.remove(temp_path)
                        print(f"Error processing image {file.filename}: {str(e)}")
                        continue
            
            return jsonify({
                'success': True,
                'processed_images': processed_images,
                'message': f'Processed {len(processed_images)} images successfully'
            }), 200
            
        except Exception as e:
            print(f"Error processing car images: {str(e)}")
            return jsonify({'error': 'Failed to process car images'}), 500
    
    # Run without debug/reloader to avoid mid-request restarts; enable threads for concurrency
    app.run(host='0.0.0.0', port=5000, debug=False, use_reloader=False, threaded=True)
