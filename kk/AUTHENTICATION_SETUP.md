# Car Listing App - Authentication System Setup

## 🎉 Complete Authentication System Implementation

Your car listing app now has a comprehensive authentication system with full database support, security features, and user management capabilities.

## ✅ What's Been Implemented

### 1. Database Support
- **SQLite** (default) for development
- **PostgreSQL** support for production
- Database migrations with Flask-Migrate
- Proper foreign key relationships

### 2. User Model & Authentication
- Complete User model with all required fields:
  - `id`, `name` (first_name + last_name), `phone_number` (unique, required)
  - `hashed_password` (bcrypt), `created_at`
  - Additional fields: `username`, `email` (optional), `is_verified`, `is_active`, `is_admin`
- Secure password hashing with bcrypt
- JWT-based authentication with access and refresh tokens
- Token blacklisting for secure logout

### 3. Authentication Routes
- `POST /api/auth/register` - User registration with validation
- `POST /api/auth/login` - User login with JWT tokens
- `POST /api/auth/logout` - Secure logout with token blacklisting
- `POST /api/auth/refresh` - Token refresh
- `POST /api/auth/forgot-password` - Password reset request (via phone)
- `POST /api/auth/reset-password` - Reset password
- `POST /api/auth/send-verification` - Send phone verification code
- `POST /api/auth/verify-phone` - Verify phone number

### 4. Protected Car Listing Routes
- `GET /api/cars` - Get all cars (public)
- `POST /api/cars` - Create car listing (authenticated)
- `GET /api/cars/<id>` - Get specific car (public)
- `PUT /api/cars/<id>` - Update car (owner only)
- `DELETE /api/cars/<id>` - Delete car (owner only)
- `GET /api/user/my-listings` - Get user's listings (authenticated)

### 5. Security Features
- Rate limiting on authentication endpoints
- Input sanitization and validation
- JWT token blacklisting
- Password strength validation
- Phone number validation (required)
- Security headers
- Audit logging
- Suspicious activity detection

### 6. User Management
- `GET /api/user/profile` - Get user profile
- `PUT /api/user/profile` - Update user profile
- `POST /api/user/upload-profile-picture` - Upload profile picture
- `GET /api/user/favorites` - Get user's favorite cars
- `POST /api/cars/<id>/favorite` - Toggle favorite status

## 🚀 Quick Setup

### 1. Run the Setup Script
```bash
cd kk
python setup_auth_system.py
```

This will:
- Create database tables
- Set up migrations
- Create admin user (admin/admin123)
- Create test user (testuser/test123)
- Generate secure .env file

### 2. Start the Server
```bash
python app_new.py
```

### 3. Test the System
```bash
python test_auth_system.py
```

## 🔧 Configuration

### Environment Variables
Copy `env_example.txt` to `.env` and configure:

```env
# Database (SQLite by default)
DATABASE_URL=sqlite:///car_listings.db

# For PostgreSQL
USE_POSTGRES=true
POSTGRES_HOST=localhost
POSTGRES_PORT=5432
POSTGRES_DB=car_listings
POSTGRES_USER=postgres
POSTGRES_PASSWORD=your-password

# Security
SECRET_KEY=your-secret-key
JWT_SECRET_KEY=your-jwt-secret

# SMS (for password reset - optional)
SMS_PROVIDER=twilio
TWILIO_ACCOUNT_SID=your-twilio-account-sid
TWILIO_AUTH_TOKEN=your-twilio-auth-token
TWILIO_PHONE_NUMBER=your-twilio-phone-number
```

## 📊 Database Schema

### Users Table
```sql
CREATE TABLE user (
    id INTEGER PRIMARY KEY,
    public_id VARCHAR(50) UNIQUE,
    username VARCHAR(80) UNIQUE NOT NULL,
    email VARCHAR(120) UNIQUE,
    password_hash VARCHAR(128) NOT NULL,
    phone_number VARCHAR(20) UNIQUE NOT NULL,
    first_name VARCHAR(50) NOT NULL,
    last_name VARCHAR(50) NOT NULL,
    profile_picture VARCHAR(200),
    is_verified BOOLEAN DEFAULT FALSE,
    is_active BOOLEAN DEFAULT TRUE,
    is_admin BOOLEAN DEFAULT FALSE,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    last_login DATETIME
);
```

### Cars Table (Updated)
```sql
CREATE TABLE car (
    id INTEGER PRIMARY KEY,
    public_id VARCHAR(50) UNIQUE,
    seller_id INTEGER NOT NULL REFERENCES user(id),
    brand VARCHAR(50) NOT NULL,
    model VARCHAR(50) NOT NULL,
    year INTEGER NOT NULL,
    mileage INTEGER NOT NULL,
    engine_type VARCHAR(50) NOT NULL,
    transmission VARCHAR(20) NOT NULL,
    drive_type VARCHAR(20) NOT NULL,
    condition VARCHAR(20) NOT NULL,
    body_type VARCHAR(30) NOT NULL,
    price FLOAT NOT NULL,
    currency VARCHAR(3) DEFAULT 'USD',
    location VARCHAR(100) NOT NULL,
    description TEXT,
    color VARCHAR(30),
    fuel_economy VARCHAR(20),
    vin VARCHAR(17) UNIQUE,
    is_active BOOLEAN DEFAULT TRUE,
    is_featured BOOLEAN DEFAULT FALSE,
    views_count INTEGER DEFAULT 0,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP
);
```

### Token Blacklist Table
```sql
CREATE TABLE token_blacklist (
    id INTEGER PRIMARY KEY,
    jti VARCHAR(36) UNIQUE NOT NULL,
    token_type VARCHAR(10) NOT NULL,
    user_id INTEGER REFERENCES user(id),
    revoked_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    expires_at DATETIME NOT NULL
);
```

## 🔐 Security Features

### Rate Limiting
- Registration: 5 attempts per hour per IP
- Login: 10 attempts per 15 minutes per IP
- Configurable limits for other endpoints

### Password Security
- Minimum 8 characters
- Must contain uppercase, lowercase, number, and special character
- Bcrypt hashing with configurable rounds

### Token Security
- JWT tokens with expiration
- Refresh token rotation
- Token blacklisting on logout
- Secure token validation

### Input Validation
- Phone number validation (required)
- Email format validation (optional)
- XSS protection
- SQL injection prevention
- File upload security

## 📱 API Usage Examples

### Register a User
```bash
curl -X POST http://localhost:5000/api/auth/register \
  -H "Content-Type: application/json" \
  -d '{
    "username": "john_doe",
    "phone_number": "+1234567890",
    "password": "SecurePass123!",
    "first_name": "John",
    "last_name": "Doe"
  }'
```

### Login
```bash
curl -X POST http://localhost:5000/api/auth/login \
  -H "Content-Type: application/json" \
  -d '{
    "username": "john_doe",
    "password": "SecurePass123!"
  }'
```

### Create Car Listing (Authenticated)
```bash
curl -X POST http://localhost:5000/api/cars \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer YOUR_ACCESS_TOKEN" \
  -d '{
    "brand": "Toyota",
    "model": "Camry",
    "year": 2020,
    "mileage": 50000,
    "engine_type": "Gas",
    "transmission": "Automatic",
    "drive_type": "FWD",
    "condition": "Used",
    "body_type": "Sedan",
    "price": 25000,
    "location": "New York, NY",
    "description": "Well maintained car"
  }'
```

### Get My Listings
```bash
curl -X GET http://localhost:5000/api/user/my-listings \
  -H "Authorization: Bearer YOUR_ACCESS_TOKEN"
```

## 🧪 Testing

Run the comprehensive test suite:
```bash
python test_auth_system.py
```

Tests include:
- User registration and validation
- Login and token generation
- Protected endpoint access
- Car listing CRUD operations
- Token refresh and logout
- Rate limiting
- Security headers

## 🚀 Production Deployment

### 1. Database Migration
```bash
# For PostgreSQL
export USE_POSTGRES=true
export POSTGRES_HOST=your-host
export POSTGRES_DB=car_listings
export POSTGRES_USER=your-user
export POSTGRES_PASSWORD=your-password

python migrate_database.py
```

### 2. Environment Configuration
```bash
export FLASK_ENV=production
export SECRET_KEY=your-production-secret-key
export JWT_SECRET_KEY=your-production-jwt-secret
export DATABASE_URL=postgresql://user:pass@host:port/db
```

### 3. Run with Gunicorn
```bash
gunicorn -w 4 -b 0.0.0.0:5000 app_new:app
```

## 🔧 Customization

### Adding New User Fields
1. Update the User model in `models.py`
2. Create a migration: `flask db migrate -m "Add new field"`
3. Apply migration: `flask db upgrade`
4. Update validation in `auth.py`

### Adding New Protected Routes
```python
@app.route('/api/protected-endpoint', methods=['GET'])
@jwt_required()
def protected_endpoint():
    current_user = get_current_user()
    if not current_user:
        return jsonify({'message': 'User not found'}), 404
    
    # Your logic here
    return jsonify({'message': 'Success'})
```

### Custom Rate Limiting
```python
@app.route('/api/custom-endpoint', methods=['POST'])
@rate_limit(max_requests=20, window_minutes=60)
def custom_endpoint():
    # Your logic here
    pass
```

## 📞 Support

The authentication system is now fully implemented and ready for production use. All endpoints are secured, validated, and tested. The system supports both SQLite for development and PostgreSQL for production deployment.

For any issues or questions, refer to the test suite or check the logs for detailed error messages.
