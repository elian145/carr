"""
Security utilities and middleware for the car listing app
"""

import re
import time
from functools import wraps
from flask import request, jsonify, current_app
from flask_jwt_extended import get_jwt_identity, get_jwt
from .models import User, UserAction, db
from datetime import datetime, timedelta

# Rate limiting storage (in production, use Redis)
rate_limit_storage = {}

def rate_limit(max_requests=10, window_minutes=60, per_ip=True):
    """
    Rate limiting decorator
    """
    def decorator(f):
        @wraps(f)
        def decorated_function(*args, **kwargs):
            # Get identifier (IP or user ID)
            if per_ip:
                identifier = request.remote_addr
            else:
                # Try to get user ID from JWT
                try:
                    user_id = get_jwt_identity()
                    identifier = f"user_{user_id}" if user_id else request.remote_addr
                except:
                    identifier = request.remote_addr
            
            # Get current time
            now = time.time()
            window_start = now - (window_minutes * 60)
            
            # Clean old entries
            if identifier in rate_limit_storage:
                rate_limit_storage[identifier] = [
                    req_time for req_time in rate_limit_storage[identifier]
                    if req_time > window_start
                ]
            else:
                rate_limit_storage[identifier] = []
            
            # Check rate limit
            if len(rate_limit_storage[identifier]) >= max_requests:
                return jsonify({
                    'message': f'Rate limit exceeded. Maximum {max_requests} requests per {window_minutes} minutes.',
                    'retry_after': window_minutes * 60
                }), 429
            
            # Add current request
            rate_limit_storage[identifier].append(now)
            
            return f(*args, **kwargs)
        return decorated_function
    return decorator

def validate_input_sanitization(data):
    """
    Validate and sanitize input data to prevent XSS and injection attacks
    """
    if isinstance(data, dict):
        return {key: validate_input_sanitization(value) for key, value in data.items()}
    elif isinstance(data, list):
        return [validate_input_sanitization(item) for item in data]
    elif isinstance(data, str):
        # Remove potentially dangerous characters
        sanitized = data.strip()
        # Remove script tags and other dangerous HTML
        sanitized = re.sub(r'<script.*?</script>', '', sanitized, flags=re.IGNORECASE | re.DOTALL)
        sanitized = re.sub(r'<.*?>', '', sanitized)  # Remove all HTML tags
        return sanitized
    else:
        return data

def validate_file_upload_security(file, allowed_extensions=None, max_size_mb=10):
    """
    Enhanced file upload security validation
    """
    if not file or not file.filename:
        return False, "No file provided"
    
    # Check file extension
    if allowed_extensions:
        file_ext = file.filename.rsplit('.', 1)[1].lower() if '.' in file.filename else ''
        if file_ext not in allowed_extensions:
            return False, f"File type not allowed. Allowed: {', '.join(allowed_extensions)}"
    
    # Check file size
    file.seek(0, 2)  # Seek to end
    file_size = file.tell()
    file.seek(0)  # Reset to beginning
    
    max_size_bytes = max_size_mb * 1024 * 1024
    if file_size > max_size_bytes:
        return False, f"File too large. Maximum size: {max_size_mb}MB"
    
    # Check for suspicious file names
    filename = file.filename.lower()
    suspicious_patterns = ['..', '/', '\\', '<', '>', ':', '"', '|', '?', '*']
    if any(pattern in filename for pattern in suspicious_patterns):
        return False, "Invalid file name"
    
    return True, "File is valid"

def log_security_event(user_id, event_type, details=None, ip_address=None):
    """
    Log security-related events
    """
    try:
        action = UserAction(
            user_id=user_id,
            action_type=f"security_{event_type}",
            target_type="security",
            action_metadata={
                'details': details,
                'ip_address': ip_address or request.remote_addr,
                'user_agent': request.headers.get('User-Agent'),
                'timestamp': datetime.utcnow().isoformat()
            }
        )
        
        db.session.add(action)
        db.session.commit()
    except Exception as e:
        current_app.logger.error(f"Failed to log security event: {str(e)}")

def check_suspicious_activity(user_id, action_type):
    """
    Check for suspicious user activity patterns
    """
    try:
        # Check for rapid successive actions
        recent_actions = UserAction.query.filter(
            UserAction.user_id == user_id,
            UserAction.action_type == action_type,
            UserAction.created_at >= datetime.utcnow() - timedelta(minutes=5)
        ).count()
        
        if recent_actions > 20:  # More than 20 actions in 5 minutes
            log_security_event(user_id, "suspicious_rapid_activity", {
                'action_type': action_type,
                'count': recent_actions
            })
            return True, "Suspicious rapid activity detected"
        
        return False, None
    except Exception as e:
        current_app.logger.error(f"Failed to check suspicious activity: {str(e)}")
        return False, None

def validate_jwt_payload(jwt_payload):
    """
    Validate JWT payload for security
    """
    required_fields = ['sub', 'exp', 'iat', 'jti']
    
    for field in required_fields:
        if field not in jwt_payload:
            return False, f"Missing required JWT field: {field}"
    
    # Check token age
    iat = jwt_payload.get('iat')
    if iat:
        token_age = time.time() - iat
        if token_age > 86400:  # 24 hours
            return False, "Token too old"
    
    return True, "JWT payload is valid"

def secure_headers():
    """
    Add security headers to responses
    """
    def decorator(f):
        @wraps(f)
        def decorated_function(*args, **kwargs):
            response = f(*args, **kwargs)
            
            if hasattr(response, 'headers'):
                # Add security headers
                response.headers['X-Content-Type-Options'] = 'nosniff'
                response.headers['X-Frame-Options'] = 'DENY'
                response.headers['X-XSS-Protection'] = '1; mode=block'
                response.headers['Strict-Transport-Security'] = 'max-age=31536000; includeSubDomains'
                response.headers['Content-Security-Policy'] = "default-src 'self'"
            
            return response
        return decorated_function
    return decorator

def validate_csrf_token():
    """
    Validate CSRF token for state-changing operations
    """
    def decorator(f):
        @wraps(f)
        def decorated_function(*args, **kwargs):
            # Skip CSRF for GET requests
            if request.method == 'GET':
                return f(*args, **kwargs)
            
            # Check for CSRF token in headers
            csrf_token = request.headers.get('X-CSRF-Token')
            if not csrf_token:
                return jsonify({'message': 'CSRF token required'}), 403
            
            # In a real implementation, you would validate the CSRF token
            # against a stored token or session
            
            return f(*args, **kwargs)
        return decorated_function
    return decorator

def audit_log(action_type, target_type=None, target_id=None, metadata=None):
    """
    Create audit log entry
    """
    def decorator(f):
        @wraps(f)
        def decorated_function(*args, **kwargs):
            try:
                # Get current user
                user_id = get_jwt_identity()
                if user_id:
                    user = User.query.filter_by(public_id=user_id).first()
                    if user:
                        log_user_action(user, action_type, target_type, target_id, metadata)
            except Exception as e:
                current_app.logger.error(f"Failed to create audit log: {str(e)}")
            
            return f(*args, **kwargs)
        return decorated_function
    return decorator

def validate_ownership(resource_type, resource_id_field='id'):
    """
    Validate that the current user owns the resource
    """
    def decorator(f):
        @wraps(f)
        def decorated_function(*args, **kwargs):
            try:
                current_user_id = get_jwt_identity()
                if not current_user_id:
                    return jsonify({'message': 'Authentication required'}), 401
                
                user = User.query.filter_by(public_id=current_user_id).first()
                if not user:
                    return jsonify({'message': 'User not found'}), 404
                
                # Get resource ID from kwargs
                resource_id = kwargs.get(resource_id_field)
                if not resource_id:
                    return jsonify({'message': 'Resource ID required'}), 400
                
                # Check ownership based on resource type
                if resource_type == 'car':
                    from .models import Car
                    resource = Car.query.filter_by(public_id=resource_id).first()
                    if not resource:
                        return jsonify({'message': 'Car not found'}), 404
                    if resource.seller_id != user.id and not user.is_admin:
                        return jsonify({'message': 'Not authorized to access this resource'}), 403
                
                # Add user to kwargs for use in the decorated function
                kwargs['current_user'] = user
                kwargs['resource'] = resource
                
            except Exception as e:
                current_app.logger.error(f"Ownership validation error: {str(e)}")
                return jsonify({'message': 'Authorization check failed'}), 500
            
            return f(*args, **kwargs)
        return decorated_function
    return decorator
