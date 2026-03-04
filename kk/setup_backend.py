#!/usr/bin/env python3
"""
Backend Setup Script for Car Listings App
This script sets up the complete backend system with database initialization,
admin user creation, and sample data.
"""

import os
import sys
import secrets
import string
from datetime import datetime
from flask import Flask
from flask_migrate import init, migrate, upgrade
from config import config

def generate_secret_key():
    """Generate a secure secret key"""
    return ''.join(secrets.choice(string.ascii_letters + string.digits) for _ in range(32))

def create_app():
    """Create Flask app instance"""
    app = Flask(__name__)
    app.config.from_object(config['development'])
    
    # Initialize extensions
    from models import db
    from flask_bcrypt import Bcrypt
    from flask_jwt_extended import JWTManager
    from flask_mail import Mail
    from flask_socketio import SocketIO
    
    db.init_app(app)
    bcrypt = Bcrypt(app)
    jwt = JWTManager(app)
    mail = Mail(app)
    # Keep dev-friendly defaults, but allow restricting via env (comma-separated).
    raw = (os.environ.get('CORS_ORIGINS') or '').strip()
    origins = [o.strip() for o in raw.split(',') if o.strip()] if raw else "*"
    socketio = SocketIO(app, cors_allowed_origins=origins)
    
    return app

def init_database(app):
    """Initialize database with tables"""
    print("Initializing database...")
    
    with app.app_context():
        from models import db
        # Create all tables
        db.create_all()
        print("✓ Database tables created")

def create_admin_user(app):
    """Create admin user"""
    print("Creating admin user...")
    
    with app.app_context():
        from models import User, db
        # Check if admin already exists
        admin = User.query.filter_by(username='admin').first()
        if admin:
            print("✓ Admin user already exists")
            return admin
        
        # Create admin user
        admin = User(
            username='admin',
            email='admin@carlistings.com',
            first_name='Admin',
            last_name='User',
            is_admin=True,
            is_verified=True,
            is_active=True
        )
        admin_password = (os.environ.get('ADMIN_PASSWORD') or '').strip() or generate_secret_key()
        admin.set_password(admin_password)
        
        db.session.add(admin)
        db.session.commit()
        
        print("✓ Admin user created")
        print("  Username: admin")
        print(f"  Password: {admin_password}")
        print("  Email: admin@carlistings.com")
        
        return admin

def create_sample_users(app):
    """Create sample users"""
    print("Creating sample users...")
    
    with app.app_context():
        from models import User, db
        sample_users = [
            {
                'username': 'john_doe',
                'email': 'john@example.com',
                'first_name': 'John',
                'last_name': 'Doe',
                'phone_number': '+1234567890'
            },
            {
                'username': 'jane_smith',
                'email': 'jane@example.com',
                'first_name': 'Jane',
                'last_name': 'Smith',
                'phone_number': '+1234567891'
            },
            {
                'username': 'mike_wilson',
                'email': 'mike@example.com',
                'first_name': 'Mike',
                'last_name': 'Wilson',
                'phone_number': '+1234567892'
            }
        ]
        
        created_users = []
        for user_data in sample_users:
            # Check if user already exists
            existing_user = User.query.filter_by(username=user_data['username']).first()
            if existing_user:
                created_users.append(existing_user)
                continue
            
            user = User(**user_data)
            sample_password = (os.environ.get('SAMPLE_USER_PASSWORD') or '').strip() or generate_secret_key()
            user.set_password(sample_password)
            user.is_verified = True
            
            db.session.add(user)
            created_users.append(user)
        
        db.session.commit()
        print(f"✓ Created {len(created_users)} sample users")
        return created_users

def create_sample_cars(app, users):
    """Create sample car listings"""
    print("Creating sample car listings...")
    
    with app.app_context():
        from models import Car, db
        sample_cars = [
            {
                'brand': 'Toyota',
                'model': 'Camry',
                'year': 2020,
                'mileage': 25000,
                'engine_type': 'Gas',
                'transmission': 'Automatic',
                'drive_type': 'FWD',
                'condition': 'Used',
                'body_type': 'Sedan',
                'price': 25000.0,
                'location': 'New York, NY',
                'description': 'Well-maintained Toyota Camry with low mileage. Single owner, no accidents.',
                'color': 'Silver',
                'fuel_economy': '28 MPG'
            },
            {
                'brand': 'Honda',
                'model': 'Civic',
                'year': 2019,
                'mileage': 35000,
                'engine_type': 'Gas',
                'transmission': 'Manual',
                'drive_type': 'FWD',
                'condition': 'Used',
                'body_type': 'Sedan',
                'price': 22000.0,
                'location': 'Los Angeles, CA',
                'description': 'Sporty Honda Civic with manual transmission. Great fuel economy.',
                'color': 'Blue',
                'fuel_economy': '32 MPG'
            },
            {
                'brand': 'BMW',
                'model': 'X5',
                'year': 2021,
                'mileage': 15000,
                'engine_type': 'Gas',
                'transmission': 'Automatic',
                'drive_type': 'AWD',
                'condition': 'Used',
                'body_type': 'SUV',
                'price': 55000.0,
                'location': 'Miami, FL',
                'description': 'Luxury BMW X5 with all-wheel drive. Premium features and low mileage.',
                'color': 'Black',
                'fuel_economy': '22 MPG'
            },
            {
                'brand': 'Tesla',
                'model': 'Model 3',
                'year': 2022,
                'mileage': 8000,
                'engine_type': 'Electric',
                'transmission': 'Automatic',
                'drive_type': 'RWD',
                'condition': 'Used',
                'body_type': 'Sedan',
                'price': 45000.0,
                'location': 'San Francisco, CA',
                'description': 'Tesla Model 3 with autopilot. Very low mileage and excellent condition.',
                'color': 'White',
                'fuel_economy': '130 MPGe'
            },
            {
                'brand': 'Ford',
                'model': 'F-150',
                'year': 2020,
                'mileage': 40000,
                'engine_type': 'Gas',
                'transmission': 'Automatic',
                'drive_type': '4WD',
                'condition': 'Used',
                'body_type': 'Pickup',
                'price': 35000.0,
                'location': 'Dallas, TX',
                'description': 'Reliable Ford F-150 pickup truck. Perfect for work or recreation.',
                'color': 'Red',
                'fuel_economy': '20 MPG'
            }
        ]
        
        created_cars = []
        for i, car_data in enumerate(sample_cars):
            # Check if car already exists
            existing_car = Car.query.filter_by(
                brand=car_data['brand'],
                model=car_data['model'],
                year=car_data['year']
            ).first()
            
            if existing_car:
                created_cars.append(existing_car)
                continue
            
            # Assign to a user (cycle through users)
            seller = users[i % len(users)]
            
            car = Car(
                seller_id=seller.id,
                **car_data
            )
            
            db.session.add(car)
            created_cars.append(car)
        
        db.session.commit()
        print(f"✓ Created {len(created_cars)} sample car listings")
        return created_cars

def create_sample_images(app, cars):
    """Create sample car images"""
    print("Creating sample car images...")
    
    with app.app_context():
        from models import CarImage, db
        # Create placeholder image records
        for car in cars:
            # Check if car already has images
            if CarImage.query.filter_by(car_id=car.id).first():
                continue
            
            # Create primary image
            primary_image = CarImage(
                car_id=car.id,
                image_url='uploads/car_photos/placeholder.jpg',
                is_primary=True,
                order=0
            )
            db.session.add(primary_image)
            
            # Create additional images
            for i in range(1, 4):
                additional_image = CarImage(
                    car_id=car.id,
                    image_url=f'uploads/car_photos/placeholder_{i}.jpg',
                    is_primary=False,
                    order=i
                )
                db.session.add(additional_image)
        
        db.session.commit()
        print("✓ Created sample car images")

def create_sample_messages(app, users, cars):
    """Create sample chat messages"""
    print("Creating sample chat messages...")
    
    with app.app_context():
        from models import Message, db
        sample_messages = [
            {
                'content': 'Hi! Is this car still available?',
                'car_id': cars[0].id,
                'sender_id': users[1].id,
                'receiver_id': users[0].id
            },
            {
                'content': 'Yes, it is! Would you like to schedule a test drive?',
                'car_id': cars[0].id,
                'sender_id': users[0].id,
                'receiver_id': users[1].id
            },
            {
                'content': 'What\'s the lowest price you would accept?',
                'car_id': cars[1].id,
                'sender_id': users[2].id,
                'receiver_id': users[1].id
            }
        ]
        
        for message_data in sample_messages:
            # Check if message already exists
            existing_message = Message.query.filter_by(
                content=message_data['content'],
                car_id=message_data['car_id']
            ).first()
            
            if existing_message:
                continue
            
            message = Message(**message_data)
            db.session.add(message)
        
        db.session.commit()
        print("✓ Created sample chat messages")

def create_sample_notifications(app, users):
    """Create sample notifications"""
    print("Creating sample notifications...")
    
    with app.app_context():
        from models import Notification, db
        sample_notifications = [
            {
                'user_id': users[0].id,
                'title': 'New Message',
                'message': 'You have a new message about your Toyota Camry listing',
                'notification_type': 'message'
            },
            {
                'user_id': users[1].id,
                'title': 'Car Added to Favorites',
                'message': 'Someone added your Honda Civic to their favorites',
                'notification_type': 'favorite'
            }
        ]
        
        for notification_data in sample_notifications:
            notification = Notification(**notification_data)
            db.session.add(notification)
        
        db.session.commit()
        print("✓ Created sample notifications")

def create_env_file():
    """Create .env file with default configuration"""
    print("Creating .env file...")
    
    env_content = f"""# Flask Configuration
SECRET_KEY={generate_secret_key()}
JWT_SECRET_KEY={generate_secret_key()}

# Database Configuration
DATABASE_URL=sqlite:///car_listings.db
DEV_DATABASE_URL=sqlite:///car_listings_dev.db

# Email Configuration (Update with your email settings)
MAIL_SERVER=smtp.gmail.com
MAIL_PORT=587
MAIL_USE_TLS=true
MAIL_USERNAME=your-email@gmail.com
MAIL_PASSWORD=your-app-password
MAIL_DEFAULT_SENDER=your-email@gmail.com

# Redis Configuration (optional)
REDIS_URL=redis://localhost:6379/0

# Firebase Configuration (for push notifications)
FIREBASE_SERVER_KEY=your-firebase-server-key
FIREBASE_PROJECT_ID=your-firebase-project-id

# Environment
FLASK_ENV=development
"""
    
    with open('.env', 'w') as f:
        f.write(env_content)
    
    print("✓ Created .env file")
    print("  Please update the email and Firebase configuration in .env")

def main():
    """Main setup function"""
    print("🚗 Car Listings Backend Setup")
    print("=" * 40)
    
    # Create Flask app
    app = create_app()
    
    try:
        # Initialize database
        init_database(app)
        
        # Create admin user
        admin = create_admin_user(app)
        
        # Create sample users
        users = create_sample_users(app)
        
        # Get all users including admin within the same session
        with app.app_context():
            from models import User, db
            all_users = User.query.all()
        
        # Create sample cars
        cars = create_sample_cars(app, all_users)
        
        # Get fresh car objects for images
        with app.app_context():
            from models import Car, db
            cars = Car.query.all()
        
        # Create sample images
        create_sample_images(app, cars)
        
        # Get fresh objects for messages and notifications
        with app.app_context():
            from models import User, Car, db
            all_users = User.query.all()
            cars = Car.query.all()
        
        # Create sample messages
        create_sample_messages(app, all_users, cars)
        
        # Create sample notifications
        create_sample_notifications(app, all_users)
        
        # Create .env file
        create_env_file()
        
        print("\n" + "=" * 40)
        print("✅ Backend setup completed successfully!")
        print("\nNext steps:")
        print("1. Update .env file with your email and Firebase configuration")
        print("2. Install dependencies: pip install -r requirements.txt")
        print("3. Run the backend: python app_new.py")
        print("4. Access admin panel at: http://localhost:5000/api/admin/dashboard")
        print("\nAdmin credentials:")
        print("  Username: admin")
        print("  Password: (printed when created; or set via ADMIN_PASSWORD env var)")
        print("  Email: admin@carlistings.com")
        
    except Exception as e:
        print(f"\n❌ Setup failed: {str(e)}")
        sys.exit(1)

if __name__ == '__main__':
    main()
