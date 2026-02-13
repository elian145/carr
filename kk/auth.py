from functools import wraps
from flask import request, jsonify, current_app
from flask_jwt_extended import jwt_required, get_jwt_identity, get_jwt
from .models import User, db, PasswordReset, EmailVerification
from datetime import datetime, timedelta
import secrets
import re

def validate_email(email):
    """Validate email format"""
    pattern = r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$'
    return re.match(pattern, email) is not None

def validate_password(password):
    """Validate password strength"""
    if len(password) < 8:
        return False, "Password must be at least 8 characters long"
    
    if not re.search(r'[A-Z]', password):
        return False, "Password must contain at least one uppercase letter"
    
    if not re.search(r'[a-z]', password):
        return False, "Password must contain at least one lowercase letter"
    
    if not re.search(r'\d', password):
        return False, "Password must contain at least one number"
    
    if not re.search(r'[!@#$%^&*(),.?":{}|<>]', password):
        return False, "Password must contain at least one special character"
    
    return True, "Password is valid"

def validate_phone_number(phone):
    """Validate phone number format"""
    # Remove all non-digit characters
    digits = re.sub(r'\D', '', phone)
    
    # Check if it's a valid length (7-15 digits)
    if len(digits) < 7 or len(digits) > 15:
        return False
    
    return True

def admin_required(f):
    """Decorator to require admin privileges"""
    @wraps(f)
    @jwt_required()
    def decorated_function(*args, **kwargs):
        current_user = get_current_user()
        if not current_user or not current_user.is_admin:
            return jsonify({'message': 'Admin privileges required'}), 403
        return f(*args, **kwargs)
    return decorated_function

def get_current_user():
    """Get current user from JWT token"""
    try:
        current_user_id = get_jwt_identity()
        if not current_user_id:
            return None
        
        user = User.query.filter_by(public_id=current_user_id).first()
        if not user or not user.is_active:
            return None
        
        return user
    except Exception as e:
        current_app.logger.error(f"Error getting current user: {str(e)}")
        return None

def create_password_reset_token(user):
    """Create password reset token"""
    # Delete any existing tokens for this user
    PasswordReset.query.filter_by(user_id=user.id, is_used=False).delete()
    
    # Create new token
    token = secrets.token_urlsafe(32)
    from .time_utils import utcnow

    expires_at = utcnow() + timedelta(hours=1)
    
    reset_token = PasswordReset(
        user_id=user.id,
        token=token,
        expires_at=expires_at
    )
    
    db.session.add(reset_token)
    db.session.commit()
    
    return token

def create_email_verification_token(user):
    """Create email verification token"""
    # Delete any existing tokens for this user
    EmailVerification.query.filter_by(user_id=user.id, is_used=False).delete()
    
    # Create new token
    token = secrets.token_urlsafe(32)
    from .time_utils import utcnow

    expires_at = utcnow() + timedelta(days=1)
    
    verification_token = EmailVerification(
        user_id=user.id,
        token=token,
        expires_at=expires_at
    )
    
    db.session.add(verification_token)
    db.session.commit()
    
    return token

def verify_password_reset_token(token):
    """Verify password reset token"""
    reset_token = PasswordReset.query.filter_by(token=token, is_used=False).first()
    
    if not reset_token:
        return None, "Invalid or expired token"
    
    if reset_token.is_expired():
        reset_token.is_used = True
        db.session.commit()
        return None, "Token has expired"
    
    return reset_token.user, None

def verify_email_verification_token(token):
    """Verify email verification token"""
    verification_token = EmailVerification.query.filter_by(token=token, is_used=False).first()
    
    if not verification_token:
        return None, "Invalid or expired token"
    
    if verification_token.is_expired():
        verification_token.is_used = True
        db.session.commit()
        return None, "Token has expired"
    
    return verification_token.user, None

def log_user_action(user, action_type, target_type=None, target_id=None, metadata=None):
    """Log user action for analytics"""
    try:
        from .models import UserAction
        
        action = UserAction(
            user_id=user.id,
            action_type=action_type,
            target_type=target_type,
            target_id=target_id,
            metadata=metadata
        )
        
        db.session.add(action)
        db.session.commit()
    except Exception as e:
        current_app.logger.error(f"Error logging user action: {str(e)}")

def validate_user_input(data, required_fields=None):
    """Validate user input data"""
    errors = []
    
    if required_fields:
        for field in required_fields:
            if field not in data or not data[field]:
                errors.append(f"{field} is required")
    
    # Validate phone number if present (now required for authentication)
    if 'phone_number' in data and data['phone_number']:
        if not validate_phone_number(data['phone_number']):
            errors.append("Invalid phone number format")
    
    # Validate email if present (now optional)
    if 'email' in data and data['email']:
        if not validate_email(data['email']):
            errors.append("Invalid email format")
    
    # Validate password if present
    if 'password' in data and data['password']:
        is_valid, message = validate_password(data['password'])
        if not is_valid:
            errors.append(message)
    
    # Validate username if present
    if 'username' in data and data['username']:
        username = data['username']
        if len(username) < 3 or len(username) > 20:
            errors.append("Username must be between 3 and 20 characters")
        if not re.match(r'^[a-zA-Z0-9_]+$', username):
            errors.append("Username can only contain letters, numbers, and underscores")
    
    return errors

def sanitize_input(data):
    """Sanitize user input to prevent XSS"""
    if isinstance(data, dict):
        return {key: sanitize_input(value) for key, value in data.items()}
    elif isinstance(data, list):
        return [sanitize_input(item) for item in data]
    elif isinstance(data, str):
        # Remove potentially dangerous characters
        return data.strip()
    else:
        return data

def rate_limit_check(user_id, action, limit=10, window_minutes=60):
    """Check if user has exceeded rate limit for an action"""
    try:
        from .models import UserAction
        from datetime import timedelta
        from .time_utils import utcnow
        
        window_start = utcnow() - timedelta(minutes=window_minutes)
        
        recent_actions = UserAction.query.filter(
            UserAction.user_id == user_id,
            UserAction.action_type == action,
            UserAction.created_at >= window_start
        ).count()
        
        return recent_actions < limit
    except Exception as e:
        current_app.logger.error(f"Error checking rate limit: {str(e)}")
        return True  # Allow action if check fails

def generate_secure_filename(filename):
    """Generate secure filename for uploads"""
    import os
    from werkzeug.utils import secure_filename
    
    # Get file extension
    _, ext = os.path.splitext(filename)
    
    # Generate secure filename with timestamp
    from .time_utils import utcnow

    timestamp = utcnow().strftime('%Y%m%d_%H%M%S')
    random_string = secrets.token_hex(8)
    
    return f"{timestamp}_{random_string}{ext}"

def allowed_file(filename, allowed_extensions):
    """Check if file extension is allowed"""
    return '.' in filename and \
           filename.rsplit('.', 1)[1].lower() in allowed_extensions

def validate_file_upload(file, max_size_mb=10, allowed_extensions=None):
    """Validate file upload"""
    if not file or not file.filename:
        return False, "No file selected"
    
    if not allowed_file(file.filename, allowed_extensions or []):
        return False, f"File type not allowed. Allowed types: {', '.join(allowed_extensions)}"
    
    # Check file size
    file.seek(0, 2)  # Seek to end
    file_size = file.tell()
    file.seek(0)  # Reset to beginning
    
    max_size_bytes = max_size_mb * 1024 * 1024
    if file_size > max_size_bytes:
        return False, f"File too large. Maximum size: {max_size_mb}MB"
    
    return True, "File is valid"
