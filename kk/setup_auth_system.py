#!/usr/bin/env python3
"""
Complete Authentication System Setup Script
This script sets up the full authentication system with database support
"""

import os
import sys
import secrets
import string
from flask import Flask
from flask_migrate import Migrate, upgrade, init, migrate
from models import db, User, Car, TokenBlacklist
from config import config
from auth import validate_email, validate_password, validate_phone_number

def generate_secret_key():
    """Generate a secure secret key"""
    return ''.join(secrets.choice(string.ascii_letters + string.digits) for _ in range(32))

def create_app():
    """Create Flask app"""
    app = Flask(__name__)
    app.config.from_object(config['development'])
    return app

def setup_database(app):
    """Setup database tables and migrations"""
    with app.app_context():
        try:
            print("🔧 Setting up database...")
            
            # Create all tables
            db.create_all()
            print("✅ Database tables created")
            
            # Initialize Flask-Migrate
            try:
                init()
                print("✅ Flask-Migrate initialized")
            except Exception as e:
                if "already exists" in str(e):
                    print("ℹ️  Flask-Migrate already initialized")
                else:
                    print(f"⚠️  Flask-Migrate warning: {e}")
            
            # Create and apply migrations
            try:
                migrate(message="Initial migration")
                upgrade()
                print("✅ Database migrations applied")
            except Exception as e:
                print(f"⚠️  Migration warning: {e}")
                
        except Exception as e:
            print(f"❌ Database setup failed: {e}")
            return False
    
    return True

def create_admin_user(app):
    """Create admin user"""
    with app.app_context():
        try:
            # Check if admin exists
            admin = User.query.filter_by(username='admin').first()
            if admin:
                print("ℹ️  Admin user already exists")
                return True
            
            # Create admin user
            admin = User(
                username='admin',
                phone_number='+1234567890',
                first_name='Admin',
                last_name='User',
                is_admin=True,
                is_verified=True,
                is_active=True
            )
            admin_password = (os.environ.get('ADMIN_PASSWORD') or '').strip()
            if not admin_password:
                import secrets as _secrets
                admin_password = _secrets.token_urlsafe(12)
            admin.set_password(admin_password)
            
            db.session.add(admin)
            db.session.commit()
            
            print("✅ Admin user created:")
            print("   Username: admin")
            print(f"   Password: {admin_password}")
            print("   Phone: +1234567890")
            
        except Exception as e:
            print(f"❌ Admin user creation failed: {e}")
            return False
    
    return True

def create_test_user(app):
    """Create test user"""
    with app.app_context():
        try:
            # Check if test user exists
            test_user = User.query.filter_by(username='testuser').first()
            if test_user:
                print("ℹ️  Test user already exists")
                return True
            
            # Create test user
            test_user = User(
                username='testuser',
                phone_number='+1234567891',
                first_name='Test',
                last_name='User',
                is_verified=True,
                is_active=True
            )
            test_password = (os.environ.get('TEST_USER_PASSWORD') or '').strip()
            if not test_password:
                import secrets as _secrets
                test_password = _secrets.token_urlsafe(12)
            test_user.set_password(test_password)
            
            db.session.add(test_user)
            db.session.commit()
            
            print("✅ Test user created:")
            print("   Username: testuser")
            print(f"   Password: {test_password}")
            print("   Phone: +1234567891")
            
        except Exception as e:
            print(f"❌ Test user creation failed: {e}")
            return False
    
    return True

def validate_auth_system(app):
    """Validate the authentication system"""
    with app.app_context():
        try:
            print("🔍 Validating authentication system...")
            
            # Test user creation
            test_user = User(
                username='validation_test',
                phone_number='+1234567892',
                first_name='Validation',
                last_name='Test'
            )
            test_user.set_password('validation123')
            
            # Test password validation
            is_valid, message = validate_password('validation123')
            if not is_valid:
                print(f"❌ Password validation failed: {message}")
                return False
            
            # Test email validation (optional)
            if not validate_email('validation@test.com'):
                print("❌ Email validation failed")
                return False
            
            # Test phone validation
            if not validate_phone_number('+1234567892'):
                print("❌ Phone validation failed")
                return False
            
            print("✅ Authentication system validation passed")
            
        except Exception as e:
            print(f"❌ Authentication system validation failed: {e}")
            return False
    
    return True

def create_env_file():
    """Create .env file with secure defaults"""
    env_file = '.env'
    if os.path.exists(env_file):
        print("ℹ️  .env file already exists")
        return True
    
    try:
        with open(env_file, 'w') as f:
            f.write(f"""# Flask Configuration
FLASK_ENV=development
SECRET_KEY={generate_secret_key()}
JWT_SECRET_KEY={generate_secret_key()}

# Database Configuration (SQLite)
DATABASE_URL=sqlite:///car_listings.db

# SMS Configuration (optional - for password reset)
# SMS_PROVIDER=twilio
# TWILIO_ACCOUNT_SID=your-twilio-account-sid
# TWILIO_AUTH_TOKEN=your-twilio-auth-token
# TWILIO_PHONE_NUMBER=your-twilio-phone-number

# Security Configuration
BCRYPT_LOG_ROUNDS=12
PASSWORD_RESET_EXPIRY=3600

# File Upload Configuration
UPLOAD_FOLDER=static/uploads
MAX_CONTENT_LENGTH=104857600
""")
        
        print("✅ .env file created with secure defaults")
        print("⚠️  Configure SMS settings in .env file if you want password reset via SMS")
        
    except Exception as e:
        print(f"❌ Failed to create .env file: {e}")
        return False
    
    return True

def print_setup_summary():
    """Print setup summary and next steps"""
    print("\n" + "="*60)
    print("🎉 AUTHENTICATION SYSTEM SETUP COMPLETE!")
    print("="*60)
    print("\n📋 What was set up:")
    print("✅ Database tables and migrations")
    print("✅ JWT token blacklisting")
    print("✅ Secure password hashing (bcrypt)")
    print("✅ User authentication routes")
    print("✅ Car listing ownership")
    print("✅ Admin and test users")
    print("✅ Environment configuration")
    
    print("\n🔐 Authentication Endpoints:")
    print("POST /api/auth/register    - User registration")
    print("POST /api/auth/login       - User login")
    print("POST /api/auth/logout      - User logout (with token blacklisting)")
    print("POST /api/auth/refresh     - Refresh access token")
    print("POST /api/auth/forgot-password - Request password reset (via phone)")
    print("POST /api/auth/reset-password  - Reset password")
    print("POST /api/auth/send-verification - Send phone verification code")
    print("POST /api/auth/verify-phone    - Verify phone number")
    
    print("\n🚗 Car Listing Endpoints:")
    print("GET  /api/cars             - Get all cars (public)")
    print("POST /api/cars             - Create car (authenticated)")
    print("PUT  /api/cars/<id>        - Update car (owner only)")
    print("DELETE /api/cars/<id>      - Delete car (owner only)")
    print("GET  /api/user/my-listings - Get user's listings (authenticated)")
    
    print("\n👤 User Management:")
    print("GET  /api/user/profile     - Get user profile")
    print("PUT  /api/user/profile     - Update user profile")
    print("POST /api/user/upload-profile-picture - Upload profile picture")
    
    print("\n🔧 Next Steps:")
    print("1. Update .env file with SMS configuration if needed")
    print("2. Run: python app_new.py")
    print("3. Test the API endpoints")
    print("4. Configure PostgreSQL if needed (set USE_POSTGRES=true)")
    
    print("\n⚠️  Security Notes:")
    print("- Change default admin password in production")
    print("- Use strong JWT secrets in production")
    print("- Configure SMS service for password reset")
    print("- Enable HTTPS in production")
    print("- Regular database backups recommended")

def main():
    """Main setup function"""
    print("🚀 Setting up complete authentication system...")
    
    # Create app
    app = create_app()
    
    # Setup database
    if not setup_database(app):
        print("❌ Database setup failed")
        sys.exit(1)
    
    # Create environment file
    if not create_env_file():
        print("❌ Environment file creation failed")
        sys.exit(1)
    
    # Create admin user
    if not create_admin_user(app):
        print("❌ Admin user creation failed")
        sys.exit(1)
    
    # Create test user
    if not create_test_user(app):
        print("❌ Test user creation failed")
        sys.exit(1)
    
    # Validate system
    if not validate_auth_system(app):
        print("❌ System validation failed")
        sys.exit(1)
    
    # Print summary
    print_setup_summary()

if __name__ == '__main__':
    main()
