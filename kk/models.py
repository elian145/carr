from datetime import datetime, timezone
from flask_sqlalchemy import SQLAlchemy
from flask_bcrypt import Bcrypt
from flask_jwt_extended import create_access_token, create_refresh_token
import uuid
import os

db = SQLAlchemy()
bcrypt = Bcrypt()

# Association tables for many-to-many relationships
user_favorites = db.Table('user_favorites',
    db.Column('user_id', db.Integer, db.ForeignKey('user.id'), primary_key=True),
    db.Column('car_id', db.Integer, db.ForeignKey('car.id'), primary_key=True),
    db.Column('created_at', db.DateTime, default=datetime.utcnow)
)

user_viewed_listings = db.Table('user_viewed_listings',
    db.Column('user_id', db.Integer, db.ForeignKey('user.id'), primary_key=True),
    db.Column('car_id', db.Integer, db.ForeignKey('car.id'), primary_key=True),
    db.Column('viewed_at', db.DateTime, default=datetime.utcnow)
)

class User(db.Model):
    __tablename__ = 'user'
    
    id = db.Column(db.Integer, primary_key=True)
    public_id = db.Column(db.String(50), unique=True, default=lambda: str(uuid.uuid4()))
    username = db.Column(db.String(80), unique=True, nullable=False, index=True)
    email = db.Column(db.String(120), unique=True, nullable=True, index=True)  # Made optional
    password = db.Column(db.String(120), nullable=True)  # Legacy field - deprecated, kept for compatibility
    password_hash = db.Column(db.String(128), nullable=False)
    phone_number = db.Column(db.String(20), unique=True, nullable=False, index=True)  # Made required and unique
    first_name = db.Column(db.String(50), nullable=False)
    last_name = db.Column(db.String(50), nullable=False)
    profile_picture = db.Column(db.String(200), nullable=True)
    is_verified = db.Column(db.Boolean, default=False)
    # Phone verification (OTP) - stored as hash, never plaintext
    phone_verification_code_hash = db.Column(db.Text, nullable=True)
    phone_verification_expires_at = db.Column(db.DateTime, nullable=True)
    phone_verification_attempts = db.Column(db.Integer, default=0)
    phone_verification_last_sent_at = db.Column(db.DateTime, nullable=True)
    phone_verification_locked_until = db.Column(db.DateTime, nullable=True)
    is_active = db.Column(db.Boolean, default=True)
    is_admin = db.Column(db.Boolean, default=False)
    created_at = db.Column(db.DateTime, default=datetime.utcnow)
    updated_at = db.Column(db.DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)
    last_login = db.Column(db.DateTime, nullable=True)
    
    # Relationships
    cars = db.relationship('Car', backref='seller', lazy=True, cascade='all, delete-orphan')
    sent_messages = db.relationship('Message', foreign_keys='Message.sender_id', backref='sender', lazy=True)
    received_messages = db.relationship('Message', foreign_keys='Message.receiver_id', backref='receiver', lazy=True)
    notifications = db.relationship('Notification', backref='user', lazy=True, cascade='all, delete-orphan')
    favorites = db.relationship('Car', secondary=user_favorites, backref='favorited_by_users', lazy='dynamic')
    viewed_listings = db.relationship('Car', secondary=user_viewed_listings, backref='viewed_by_users', lazy='dynamic')
    user_actions = db.relationship('UserAction', backref='user', lazy=True, cascade='all, delete-orphan')
    
    # Firebase token for push notifications
    firebase_token = db.Column(db.Text, nullable=True)
    
    def set_password(self, password):
        """Hash and set password"""
        self.password_hash = bcrypt.generate_password_hash(password).decode('utf-8')
    
    def check_password(self, password):
        """Check if provided password matches hash"""
        return bcrypt.check_password_hash(self.password_hash, password)
    
    def generate_tokens(self):
        """Generate access and refresh tokens"""
        access_token = create_access_token(identity=self.public_id)
        refresh_token = create_refresh_token(identity=self.public_id)
        return access_token, refresh_token
    
    def to_dict(self, include_private=False):
        """Convert user to dictionary"""
        data = {
            'id': self.public_id,
            'username': self.username,
            'phone_number': self.phone_number,
            'first_name': self.first_name,
            'last_name': self.last_name,
            'profile_picture': self.profile_picture,
            'is_verified': self.is_verified,
            'is_active': self.is_active,
            'created_at': self.created_at.isoformat() if self.created_at else None,
            'last_login': self.last_login.isoformat() if self.last_login else None
        }
        
        # Only include email if it exists
        if self.email:
            data['email'] = self.email
        
        if include_private:
            data.update({
                'is_admin': self.is_admin,
                'updated_at': self.updated_at.isoformat() if self.updated_at else None
            })
        
        return data
    
    def __repr__(self):
        return f'<User {self.username}>'

class Car(db.Model):
    __tablename__ = 'car'
    
    id = db.Column(db.Integer, primary_key=True)
    public_id = db.Column(db.String(50), unique=True, default=lambda: str(uuid.uuid4()))
    seller_id = db.Column(db.Integer, db.ForeignKey('user.id'), nullable=False)
    
    # Basic car information
    title = db.Column(db.String(200), nullable=False, default='')  # Some legacy DBs require NOT NULL
    title_status = db.Column(db.String(20), nullable=False, default='active')
    brand = db.Column(db.String(50), nullable=False, index=True)
    model = db.Column(db.String(50), nullable=False, index=True)
    trim = db.Column(db.String(50), nullable=False, default='base')
    year = db.Column(db.Integer, nullable=False, index=True)
    mileage = db.Column(db.Integer, nullable=False)
    engine_type = db.Column(db.String(50), nullable=False)  # Gas, Diesel, Electric, Hybrid
    fuel_type = db.Column(db.String(20), nullable=False, default='gasoline')
    transmission = db.Column(db.String(20), nullable=False)  # Manual, Automatic, CVT
    drive_type = db.Column(db.String(20), nullable=False)  # FWD, RWD, AWD, 4WD
    condition = db.Column(db.String(20), nullable=False)  # New, Used, Certified
    body_type = db.Column(db.String(30), nullable=False)  # Sedan, SUV, Hatchback, etc.
    status = db.Column(db.String(20), nullable=False, default='active')
    
    # Pricing and location
    price = db.Column(db.Float, nullable=False, index=True)
    currency = db.Column(db.String(3), default='USD')
    location = db.Column(db.String(100), nullable=False, index=True)
    seating = db.Column(db.Integer, nullable=False, default=5)
    latitude = db.Column(db.Float, nullable=True)
    longitude = db.Column(db.Float, nullable=True)
    
    # Additional details
    description = db.Column(db.Text, nullable=True)
    color = db.Column(db.String(30), nullable=True)
    fuel_economy = db.Column(db.String(20), nullable=True)  # MPG or L/100km
    vin = db.Column(db.String(17), nullable=True, unique=True)
    
    # Status and metadata
    is_active = db.Column(db.Boolean, default=True, index=True)
    is_featured = db.Column(db.Boolean, default=False)
    views_count = db.Column(db.Integer, default=0)
    created_at = db.Column(db.DateTime, default=datetime.utcnow, index=True)
    updated_at = db.Column(db.DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)
    
    # AI Analysis fields
    ai_analyzed = db.Column(db.Boolean, default=False)
    ai_detected_brand = db.Column(db.String(50), nullable=True)
    ai_detected_model = db.Column(db.String(50), nullable=True)
    ai_detected_color = db.Column(db.String(20), nullable=True)
    ai_detected_body_type = db.Column(db.String(20), nullable=True)
    ai_detected_condition = db.Column(db.String(20), nullable=True)
    ai_confidence_score = db.Column(db.Float, nullable=True)
    ai_analysis_timestamp = db.Column(db.DateTime, nullable=True)
    
    # Relationships
    images = db.relationship('CarImage', backref='car', lazy=True, cascade='all, delete-orphan')
    videos = db.relationship('CarVideo', backref='car', lazy=True, cascade='all, delete-orphan')
    messages = db.relationship('Message', backref='car', lazy=True)
    
    def to_dict(self, include_private=False):
        """Convert car to dictionary"""
        data = {
            'id': self.public_id,
            'brand': self.brand,
            'model': self.model,
            'year': self.year,
            'mileage': self.mileage,
            'engine_type': self.engine_type,
            'transmission': self.transmission,
            'drive_type': self.drive_type,
            'condition': self.condition,
            'body_type': self.body_type,
            'price': self.price,
            'currency': self.currency,
            'location': self.location,
            'description': self.description,
            'color': self.color,
            'fuel_economy': self.fuel_economy,
            'is_active': self.is_active,
            'is_featured': self.is_featured,
            'views_count': self.views_count,
            'created_at': self.created_at.isoformat() if self.created_at else None,
            'updated_at': self.updated_at.isoformat() if self.updated_at else None,
            'images': [img.to_dict() for img in self.images],
            'videos': [video.to_dict() for video in self.videos],
            'seller': self.seller.to_dict() if self.seller else None,
            # AI Analysis fields
            'ai_analyzed': self.ai_analyzed,
            'ai_detected_brand': self.ai_detected_brand,
            'ai_detected_model': self.ai_detected_model,
            'ai_detected_color': self.ai_detected_color,
            'ai_detected_body_type': self.ai_detected_body_type,
            'ai_detected_condition': self.ai_detected_condition,
            'ai_confidence_score': self.ai_confidence_score,
            'ai_analysis_timestamp': self.ai_analysis_timestamp.isoformat() if self.ai_analysis_timestamp else None
        }
        
        if include_private:
            data.update({
                'vin': self.vin,
                'latitude': self.latitude,
                'longitude': self.longitude
            })
        
        return data
    
    def increment_views(self, commit: bool = False):
        """Increment view count (caller controls commit)."""
        try:
            self.views_count = int(self.views_count or 0) + 1
        except Exception:
            self.views_count = 1
        if commit:
            db.session.commit()
    
    def __repr__(self):
        return f'<Car {self.brand} {self.model} {self.year}>'

class CarImage(db.Model):
    __tablename__ = 'car_image'
    
    id = db.Column(db.Integer, primary_key=True)
    car_id = db.Column(db.Integer, db.ForeignKey('car.id'), nullable=False)
    image_url = db.Column(db.String(200), nullable=False)
    is_primary = db.Column(db.Boolean, default=False)
    order = db.Column(db.Integer, default=0)
    created_at = db.Column(db.DateTime, default=datetime.utcnow)
    
    def to_dict(self):
        return {
            'id': self.id,
            'image_url': self.image_url,
            'is_primary': self.is_primary,
            'order': self.order
        }
    
    def __repr__(self):
        return f'<CarImage {self.image_url}>'

class CarVideo(db.Model):
    __tablename__ = 'car_video'
    
    id = db.Column(db.Integer, primary_key=True)
    car_id = db.Column(db.Integer, db.ForeignKey('car.id'), nullable=False)
    video_url = db.Column(db.String(200), nullable=False)
    thumbnail_url = db.Column(db.String(200), nullable=True)
    duration = db.Column(db.Integer, nullable=True)  # Duration in seconds
    order = db.Column(db.Integer, default=0)
    created_at = db.Column(db.DateTime, default=datetime.utcnow)
    
    def to_dict(self):
        return {
            'id': self.id,
            'video_url': self.video_url,
            'thumbnail_url': self.thumbnail_url,
            'duration': self.duration,
            'order': self.order
        }
    
    def __repr__(self):
        return f'<CarVideo {self.video_url}>'

class ListingAnalytics(db.Model):
    __tablename__ = 'listing_analytics'
    
    id = db.Column(db.Integer, primary_key=True)
    car_id = db.Column(db.Integer, db.ForeignKey('car.id'), nullable=False)
    views = db.Column(db.Integer, default=0)
    messages = db.Column(db.Integer, default=0)
    calls = db.Column(db.Integer, default=0)
    shares = db.Column(db.Integer, default=0)
    favorites = db.Column(db.Integer, default=0)
    created_at = db.Column(db.DateTime, default=datetime.utcnow)
    updated_at = db.Column(db.DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)
    
    # Relationship
    car = db.relationship('Car', backref='analytics')
    
    def to_dict(self):
        # Get image URL using the same logic as the my_listings endpoint
        def first_image_rel_path(car):
            if car and car.images:
                path = car.images[0].image_url or ''
                return path[8:] if path.startswith('uploads/') else path
            return (car.image_url or '').lstrip('/') if car else ''
        
        return {
            'listing_id': self.car.public_id if self.car else str(self.car_id),
            'title': self.car.title if self.car else '',
            'brand': self.car.brand if self.car else '',
            'model': self.car.model if self.car else '',
            'year': self.car.year if self.car else 0,
            'price': self.car.price if self.car else 0,
            'image_url': first_image_rel_path(self.car),
            'views': self.views,
            'messages': self.messages,
            'calls': self.calls,
            'shares': self.shares,
            'favorites': self.favorites,
            'created_at': self.created_at.isoformat() if self.created_at else None,
            'last_updated': self.updated_at.isoformat() if self.updated_at else None,
        }
    
    def increment_views(self):
        self.views += 1
        self.updated_at = datetime.utcnow()
        db.session.commit()
    
    def increment_messages(self):
        self.messages += 1
        self.updated_at = datetime.utcnow()
        db.session.commit()
    
    def increment_calls(self):
        self.calls += 1
        self.updated_at = datetime.utcnow()
        db.session.commit()
    
    def increment_shares(self):
        self.shares += 1
        self.updated_at = datetime.utcnow()
        db.session.commit()
    
    def increment_favorites(self):
        self.favorites += 1
        self.updated_at = datetime.utcnow()
        db.session.commit()
    
    def __repr__(self):
        return f'<ListingAnalytics car_id={self.car_id} views={self.views}>'

class Message(db.Model):
    __tablename__ = 'message'
    
    id = db.Column(db.Integer, primary_key=True)
    public_id = db.Column(db.String(50), unique=True, default=lambda: str(uuid.uuid4()))
    sender_id = db.Column(db.Integer, db.ForeignKey('user.id'), nullable=False)
    receiver_id = db.Column(db.Integer, db.ForeignKey('user.id'), nullable=False)
    car_id = db.Column(db.Integer, db.ForeignKey('car.id'), nullable=True)
    content = db.Column(db.Text, nullable=False)
    message_type = db.Column(db.String(20), default='text')  # text, image, file
    is_read = db.Column(db.Boolean, default=False)
    created_at = db.Column(db.DateTime, default=datetime.utcnow, index=True)
    
    def to_dict(self):
        return {
            'id': self.public_id,
            'sender_id': self.sender.public_id if self.sender else None,
            'receiver_id': self.receiver.public_id if self.receiver else None,
            'car_id': self.car.public_id if self.car else None,
            'content': self.content,
            'message_type': self.message_type,
            'is_read': self.is_read,
            'created_at': self.created_at.isoformat() if self.created_at else None,
            'sender_name': f"{self.sender.first_name} {self.sender.last_name}" if self.sender else None
        }
    
    def __repr__(self):
        return f'<Message {self.id}>'

class Notification(db.Model):
    __tablename__ = 'notification'
    
    id = db.Column(db.Integer, primary_key=True)
    public_id = db.Column(db.String(50), unique=True, default=lambda: str(uuid.uuid4()))
    user_id = db.Column(db.Integer, db.ForeignKey('user.id'), nullable=False)
    title = db.Column(db.String(200), nullable=False)
    message = db.Column(db.Text, nullable=False)
    notification_type = db.Column(db.String(50), nullable=False)  # message, listing, favorite, etc.
    is_read = db.Column(db.Boolean, default=False)
    data = db.Column(db.JSON, nullable=True)  # Additional data for the notification
    created_at = db.Column(db.DateTime, default=datetime.utcnow, index=True)
    
    def to_dict(self):
        return {
            'id': self.public_id,
            'title': self.title,
            'message': self.message,
            'notification_type': self.notification_type,
            'is_read': self.is_read,
            'data': self.data,
            'created_at': self.created_at.isoformat() if self.created_at else None
        }
    
    def __repr__(self):
        return f'<Notification {self.id}>'

class UserAction(db.Model):
    __tablename__ = 'user_action'
    
    id = db.Column(db.Integer, primary_key=True)
    user_id = db.Column(db.Integer, db.ForeignKey('user.id'), nullable=False)
    action_type = db.Column(db.String(50), nullable=False)  # view_listing, contact_seller, edit_listing, etc.
    target_type = db.Column(db.String(50), nullable=True)  # car, user, message, etc.
    target_id = db.Column(db.String(50), nullable=True)
    action_metadata = db.Column(db.JSON, nullable=True)
    created_at = db.Column(db.DateTime, default=datetime.utcnow, index=True)
    
    def to_dict(self):
        return {
            'id': self.id,
            'action_type': self.action_type,
            'target_type': self.target_type,
            'target_id': self.target_id,
            'action_metadata': self.action_metadata,
            'created_at': self.created_at.isoformat() if self.created_at else None
        }
    
    def __repr__(self):
        return f'<UserAction {self.action_type}>'

class PasswordReset(db.Model):
    __tablename__ = 'password_reset'
    
    id = db.Column(db.Integer, primary_key=True)
    user_id = db.Column(db.Integer, db.ForeignKey('user.id'), nullable=False)
    token = db.Column(db.String(100), unique=True, nullable=False)
    expires_at = db.Column(db.DateTime, nullable=False)
    is_used = db.Column(db.Boolean, default=False)
    created_at = db.Column(db.DateTime, default=datetime.utcnow)
    
    def is_expired(self):
        return datetime.utcnow() > self.expires_at
    
    def __repr__(self):
        return f'<PasswordReset {self.token}>'

class EmailVerification(db.Model):
    __tablename__ = 'email_verification'
    
    id = db.Column(db.Integer, primary_key=True)
    user_id = db.Column(db.Integer, db.ForeignKey('user.id'), nullable=False)
    token = db.Column(db.String(100), unique=True, nullable=False)
    expires_at = db.Column(db.DateTime, nullable=False)
    is_used = db.Column(db.Boolean, default=False)
    created_at = db.Column(db.DateTime, default=datetime.utcnow)
    
    def is_expired(self):
        return datetime.utcnow() > self.expires_at
    
    def __repr__(self):
        return f'<EmailVerification {self.token}>'

class TokenBlacklist(db.Model):
    __tablename__ = 'token_blacklist'
    
    id = db.Column(db.Integer, primary_key=True)
    jti = db.Column(db.String(36), nullable=False, unique=True, index=True)  # JWT ID
    token_type = db.Column(db.String(10), nullable=False)  # 'access' or 'refresh'
    user_id = db.Column(db.Integer, db.ForeignKey('user.id'), nullable=True)
    revoked_at = db.Column(db.DateTime, nullable=False, default=datetime.utcnow)
    expires_at = db.Column(db.DateTime, nullable=False)
    
    def __repr__(self):
        return f'<TokenBlacklist {self.jti}>'
