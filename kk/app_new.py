from flask import Flask, request, jsonify, send_from_directory, render_template, url_for
from flask_sqlalchemy import SQLAlchemy
from flask_migrate import Migrate
from flask_jwt_extended import JWTManager, create_access_token, create_refresh_token, jwt_required, get_jwt_identity, get_jwt
from flask_cors import CORS
from flask_mail import Mail, Message
from flask_socketio import SocketIO, emit, join_room, leave_room
from werkzeug.utils import secure_filename
from config import config
from models import *
from auth import *
from security import rate_limit, validate_input_sanitization, secure_headers
import pathlib
import os
import json
import logging
from datetime import datetime, timedelta
import secrets
from functools import wraps

# Initialize Flask app
app = Flask(__name__)
app.config.from_object(config['development'])
# Force SQLite DB to live under the app's instance directory, regardless of CWD
instance_db_abs = os.path.join(app.root_path, 'instance', 'car_listings_dev.db')
os.makedirs(os.path.dirname(instance_db_abs), exist_ok=True)
app.config['SQLALCHEMY_DATABASE_URI'] = f"sqlite:///{instance_db_abs}"

# Initialize extensions
db.init_app(app)
migrate = Migrate(app, db)
jwt = JWTManager(app)
mail = Mail(app)
socketio = SocketIO(app, cors_allowed_origins="*", async_mode='threading')
CORS(app)

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Create upload directories
os.makedirs(os.path.join(app.config['UPLOAD_FOLDER'], 'car_photos'), exist_ok=True)
os.makedirs(os.path.join(app.config['UPLOAD_FOLDER'], 'car_videos'), exist_ok=True)
os.makedirs(os.path.join(app.config['UPLOAD_FOLDER'], 'profile_pictures'), exist_ok=True)

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
        
        # Update last login
        user.last_login = datetime.utcnow()
        db.session.commit()
        
        # Generate tokens
        access_token, refresh_token = user.generate_tokens()
        
        # Log user action
        log_user_action(user, 'login')
        
        return jsonify({
            'message': 'Login successful',
            'access_token': access_token,
            'refresh_token': refresh_token,
            'user': user.to_dict()
        }), 200
        
    except Exception as e:
        logger.error(f"Login error: {str(e)}")
        return jsonify({'message': 'Login failed'}), 500

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
            image_list = [img.image_url for img in car.images] if car.images else []
            primary_rel = image_list[0] if image_list else ''
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
            image_list = [img.image_url for img in c.images] if c.images else []
            primary_rel = image_list[0] if image_list else ''
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
        data = request.get_json() or {}
        username = (data.get('username') or '').strip()
        phone = (data.get('phone') or data.get('phone_number') or '').strip()
        password = (data.get('password') or '').strip()
        first_name = (data.get('first_name') or 'User').strip()
        last_name = (data.get('last_name') or 'Demo').strip()
        if not username:
            username = phone or f"user_{secrets.token_hex(3)}"
        if not phone:
            phone = f"070{secrets.randbelow(10**8):08d}"
        if not password:
            password = 'password123'

        # Check existing
        if User.query.filter((User.username == username) | (User.phone_number == phone)).first():
            return jsonify({'message': 'User already exists'}), 400

        user = User(
            username=username,
            phone_number=phone,
            first_name=first_name,
            last_name=last_name,
            email=None,
        )
        user.set_password(password)
        db.session.add(user)
        db.session.commit()
        return jsonify({'message': 'Signup successful'}), 201
    except Exception as e:
        logger.error(f"Compat signup error: {str(e)}")
        db.session.rollback()
        return jsonify({'message': 'Signup failed'}), 500

@app.route('/api/auth/login', methods=['POST'])
def compat_login_legacy():
    try:
        data = request.get_json() or {}
        username = (data.get('username') or '').strip()
        password = (data.get('password') or '').strip()
        if not username or not password:
            return jsonify({'message': 'Username and password required'}), 400
        user = User.query.filter((User.username == username) | (User.phone_number == username)).first()
        if not user or not user.check_password(password):
            return jsonify({'message': 'Invalid credentials'}), 401
        if not user.is_active:
            return jsonify({'message': 'Account is deactivated'}), 401
        user.last_login = datetime.utcnow()
        db.session.commit()
        access_token, _ = user.generate_tokens()
        # Mobile client expects 'token'
        return jsonify({'token': access_token}), 200
    except Exception as e:
        logger.error(f"Compat login error: {str(e)}")
        return jsonify({'message': 'Login failed'}), 500

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
        if db.session.query(Car).count() == 0:
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
                    db.session.add(CarImage(car_id=car.id, image_url=f'car_photos/{fname}', is_primary=(order == 0), order=order))
                    order += 1
                created += 1
            db.session.commit()

        total = db.session.query(Car).count()
        return jsonify({'message': 'seed_ok', 'created': created, 'total': total}), 200
    except Exception as e:
        logger.error(f"Dev seed error: {str(e)}")
        db.session.rollback()
        return jsonify({'message': 'seed_failed'}), 500

@app.route('/api/cars/<car_id>', methods=['GET'])
def get_car(car_id):
    """Get single car by ID"""
    try:
        car = Car.query.filter_by(public_id=car_id, is_active=True).first()
        if not car:
            return jsonify({'message': 'Car not found'}), 404
        
        # Increment view count
        car.increment_views()
        
        # Log view action if user is authenticated
        current_user = get_current_user()
        if current_user:
            log_user_action(current_user, 'view_listing', 'car', car.public_id)
        
        return jsonify({
            'car': car.to_dict()
        }), 200
        
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
        
        data = request.get_json()
        
        # Validate required fields
        required_fields = ['brand', 'model', 'year', 'mileage', 'engine_type', 
                          'transmission', 'drive_type', 'condition', 'body_type', 'price', 'location']
        
        errors = validate_user_input(data, required_fields)
        if errors:
            return jsonify({'message': 'Validation failed', 'errors': errors}), 400
        
        # Create car
        car = Car(
            seller_id=current_user.id,
            brand=data['brand'],
            model=data['model'],
            year=data['year'],
            mileage=data['mileage'],
            engine_type=data['engine_type'],
            transmission=data['transmission'],
            drive_type=data['drive_type'],
            condition=data['condition'],
            body_type=data['body_type'],
            price=data['price'],
            location=data['location'],
            description=data.get('description'),
            color=data.get('color'),
            fuel_economy=data.get('fuel_economy'),
            vin=data.get('vin'),
            currency=data.get('currency', 'USD')
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
        logger.error(f"Create car error: {str(e)}")
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

# File Upload Routes
@app.route('/api/cars/<car_id>/images', methods=['POST'])
@jwt_required()
def upload_car_images(car_id):
    """Upload car images"""
    try:
        current_user = get_current_user()
        if not current_user:
            return jsonify({'message': 'User not found'}), 404
        
        car = Car.query.filter_by(public_id=car_id).first()
        if not car:
            return jsonify({'message': 'Car not found'}), 404
        
        # Check ownership
        if car.seller_id != current_user.id and not current_user.is_admin:
            return jsonify({'message': 'Not authorized to upload images for this listing'}), 403
        
        if 'files' not in request.files:
            return jsonify({'message': 'No files provided'}), 400
        
        files = request.files.getlist('files')
        uploaded_images = []
        
        for file in files:
            if file.filename:
                # Validate file
                is_valid, message = validate_file_upload(
                    file, 
                    max_size_mb=10, 
                    allowed_extensions=app.config['ALLOWED_EXTENSIONS']
                )
                
                if not is_valid:
                    continue  # Skip invalid files
                
                # Generate secure filename
                filename = generate_secure_filename(file.filename)
                file_path = os.path.join(app.config['UPLOAD_FOLDER'], 'car_photos', filename)
                
                # Save file
                file.save(file_path)
                
                # Create image record
                car_image = CarImage(
                    car_id=car.id,
                    image_url=f"uploads/car_photos/{filename}",
                    is_primary=len(car.images) == 0  # First image is primary
                )
                
                db.session.add(car_image)
                uploaded_images.append(car_image.to_dict())
        
        db.session.commit()
        
        # Log user action
        log_user_action(current_user, 'upload_images', 'car', car.public_id)
        
        return jsonify({
            'message': f'{len(uploaded_images)} images uploaded successfully',
            'images': uploaded_images
        }), 200
        
    except Exception as e:
        logger.error(f"Upload car images error: {str(e)}")
        return jsonify({'message': 'Failed to upload images'}), 500

@app.route('/api/cars/<car_id>/videos', methods=['POST'])
@jwt_required()
def upload_car_videos(car_id):
    """Upload car videos"""
    try:
        current_user = get_current_user()
        if not current_user:
            return jsonify({'message': 'User not found'}), 404
        
        car = Car.query.filter_by(public_id=car_id).first()
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
        }), 200
        
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
    return send_from_directory('static', filename)

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
