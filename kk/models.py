from datetime import datetime, timezone
from flask_sqlalchemy import SQLAlchemy
from flask_bcrypt import Bcrypt
from flask_jwt_extended import create_access_token, create_refresh_token
import uuid
import os

db = SQLAlchemy()
bcrypt = Bcrypt()

# Use a single UTC helper (avoids deprecated datetime.utcnow()).
from .time_utils import utcnow

# Association tables for many-to-many relationships
user_favorites = db.Table('user_favorites',
    db.Column('user_id', db.Integer, db.ForeignKey('user.id'), primary_key=True),
    db.Column('car_id', db.Integer, db.ForeignKey('car.id'), primary_key=True),
    db.Column('created_at', db.DateTime, default=utcnow),
    db.Column('price_at_favorite', db.Float, nullable=True),
)

user_viewed_listings = db.Table('user_viewed_listings',
    db.Column('user_id', db.Integer, db.ForeignKey('user.id'), primary_key=True),
    db.Column('car_id', db.Integer, db.ForeignKey('car.id'), primary_key=True),
    db.Column('viewed_at', db.DateTime, default=utcnow)
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
    # Phone OTP completed. Gated actions (listings, media, chat) require this —
    # email verification alone must not unlock them (see phone_verification_error_payload).
    phone_verified = db.Column(db.Boolean, default=False, nullable=False)
    # Phone verification (OTP) - stored as hash, never plaintext
    phone_verification_code_hash = db.Column(db.Text, nullable=True)
    phone_verification_expires_at = db.Column(db.DateTime, nullable=True)
    phone_verification_attempts = db.Column(db.Integer, default=0)
    phone_verification_last_sent_at = db.Column(db.DateTime, nullable=True)
    phone_verification_locked_until = db.Column(db.DateTime, nullable=True)
    is_active = db.Column(db.Boolean, default=True)
    is_admin = db.Column(db.Boolean, default=False)
    # Admin panel role when is_admin: super_admin | moderator | support | marketing
    # Null + is_admin=True is treated as super_admin (legacy admins).
    admin_role = db.Column(db.String(32), nullable=True)
    account_type = db.Column(db.String(20), nullable=False, default="user")  # user | dealer
    dealer_status = db.Column(db.String(20), nullable=False, default="none")  # none | pending | approved | rejected
    # Ops flag: highlight approved dealers in browse/home (optional).
    is_featured_dealer = db.Column(db.Boolean, default=False, nullable=False)
    dealership_name = db.Column(db.String(120), nullable=True)
    dealership_phone = db.Column(db.String(20), nullable=True)
    # JSON list: ["+9647....", "0750....", ...]
    # Keep `dealership_phone` as a single primary number for backwards compatibility.
    dealership_phones = db.Column(db.JSON, nullable=True)
    # Canonical digit-only phone values that completed the dealer SMS challenge.
    dealership_verified_phones = db.Column(db.JSON, nullable=True)
    # Digit-only phones OTP-proven for listing contact (any authenticated user).
    contact_verified_phones = db.Column(db.JSON, nullable=True)
    # JSON list of public dealership contact emails (verified before save).
    dealership_emails = db.Column(db.JSON, nullable=True)
    # Lowercased emails that completed the dealer email OTP challenge.
    dealership_verified_emails = db.Column(db.JSON, nullable=True)
    dealer_email_verification_code_hash = db.Column(db.String(128), nullable=True)
    dealer_email_verification_expires_at = db.Column(db.DateTime, nullable=True)
    dealer_email_verification_attempts = db.Column(db.Integer, nullable=True)
    dealer_email_verification_last_sent_at = db.Column(db.DateTime, nullable=True)
    dealer_email_verification_locked_until = db.Column(db.DateTime, nullable=True)
    dealership_location = db.Column(db.String(200), nullable=True)
    dealership_description = db.Column(db.Text, nullable=True)
    dealership_cover_picture = db.Column(db.String(200), nullable=True)
    dealership_latitude = db.Column(db.Float, nullable=True)
    dealership_longitude = db.Column(db.Float, nullable=True)
    # JSON map: { "mon": "9:00 AM - 6:00 PM", ... }
    dealership_opening_hours = db.Column(db.JSON, nullable=True)
    created_at = db.Column(db.DateTime, default=utcnow)
    updated_at = db.Column(db.DateTime, default=utcnow, onupdate=utcnow)
    last_login = db.Column(db.DateTime, nullable=True)
    
    # Relationships
    cars = db.relationship('Car', backref='seller', lazy=True, cascade='all, delete-orphan')
    sent_messages = db.relationship('Message', foreign_keys='Message.sender_id', backref='sender', lazy=True)
    received_messages = db.relationship('Message', foreign_keys='Message.receiver_id', backref='receiver', lazy=True)
    notifications = db.relationship('Notification', backref='user', lazy=True, cascade='all, delete-orphan')
    favorites = db.relationship('Car', secondary=user_favorites, backref='favorited_by_users', lazy='dynamic')
    viewed_listings = db.relationship('Car', secondary=user_viewed_listings, backref='viewed_by_users', lazy='dynamic')
    user_actions = db.relationship('UserAction', backref='user', lazy=True, cascade='all, delete-orphan')
    dealer_application = db.relationship(
        'DealerApplication',
        foreign_keys='DealerApplication.user_id',
        back_populates='user',
        uselist=False,
        cascade='all, delete-orphan',
    )
    dealer_profile = db.relationship(
        'DealerProfile',
        back_populates='user',
        uselist=False,
        cascade='all, delete-orphan',
    )
    
    # Firebase token for push notifications
    firebase_token = db.Column(db.Text, nullable=True)
    
    def set_password(self, password):
        """Hash and set password"""
        hashed = bcrypt.generate_password_hash(password).decode('utf-8')
        self.password_hash = hashed
        # Legacy compatibility: some existing SQLite schemas still have a NOT NULL
        # constraint on the deprecated `password` column. Store the same bcrypt hash
        # there to avoid insert failures while keeping plaintext out of the DB.
        try:
            self.password = hashed
        except Exception:
            # If the column doesn't exist in a different schema, ignore.
            pass
    
    def check_password(self, password):
        """Check if provided password matches hash. Supports legacy DBs where only password column exists."""
        try:
            h = getattr(self, "password_hash", None)
            if h:
                return bcrypt.check_password_hash(h, password)
            p = getattr(self, "password", None)
            if p:
                return bcrypt.check_password_hash(p, password)
        except Exception:
            pass
        return False
    
    def generate_tokens(self):
        """Generate access and refresh tokens"""
        access_token = create_access_token(identity=self.public_id)
        refresh_token = create_refresh_token(identity=self.public_id)
        return access_token, refresh_token
    
    def to_dict(self, include_private=False):
        """Convert user to dictionary"""
        phones = getattr(self, "dealership_phones", None)
        if isinstance(phones, list):
            phones_out = [str(x).strip() for x in phones if str(x).strip()]
        else:
            phones_out = []
        if not phones_out and self.dealership_phone:
            phones_out = [str(self.dealership_phone).strip()]
        verified_phones = getattr(self, "dealership_verified_phones", None)
        if isinstance(verified_phones, list):
            verified_phones_out = [
                str(x).strip() for x in verified_phones if str(x).strip()
            ]
        else:
            verified_phones_out = []
        contact_verified = getattr(self, "contact_verified_phones", None)
        if isinstance(contact_verified, list):
            contact_verified_out = [
                str(x).strip() for x in contact_verified if str(x).strip()
            ]
        else:
            contact_verified_out = []
        emails = getattr(self, "dealership_emails", None)
        if isinstance(emails, list):
            emails_out = [str(x).strip() for x in emails if str(x).strip()]
        else:
            emails_out = []
        verified_emails = getattr(self, "dealership_verified_emails", None)
        if isinstance(verified_emails, list):
            verified_emails_out = [
                str(x).strip().lower() for x in verified_emails if str(x).strip()
            ]
        else:
            verified_emails_out = []

        data = {
            'id': self.public_id,
            'username': self.username,
            'phone_number': self.phone_number,
            'first_name': self.first_name,
            'last_name': self.last_name,
            'profile_picture': self.profile_picture,
            'is_verified': bool(getattr(self, "phone_verified", False)),
            'phone_verified': bool(getattr(self, "phone_verified", False)),
            'email_verified': bool(self.is_verified),
            'is_active': self.is_active,
            'account_type': self.account_type or "user",
            'dealer_status': self.dealer_status or "none",
            'dealership_name': self.dealership_name,
            'dealership_phone': self.dealership_phone,
            'dealership_phones': phones_out,
            'dealership_verified_phones': verified_phones_out,
            'contact_verified_phones': contact_verified_out,
            'dealership_emails': emails_out,
            'dealership_verified_emails': verified_emails_out,
            'dealership_location': self.dealership_location,
            'dealership_description': self.dealership_description,
            'dealership_cover_picture': self.dealership_cover_picture,
            'dealership_latitude': self.dealership_latitude,
            'dealership_longitude': self.dealership_longitude,
            'dealership_opening_hours': self.dealership_opening_hours,
            'is_featured_dealer': bool(getattr(self, "is_featured_dealer", False)),
            'created_at': self.created_at.isoformat() if self.created_at else None,
            'last_login': self.last_login.isoformat() if self.last_login else None
        }

        # Only include email if it exists and isn't an internal placeholder.
        # Phone OTP flows may create a stable placeholder email for legacy DB schemas.
        if self.email and not str(self.email).lower().endswith("@phone.local"):
            data['email'] = self.email
        
        if include_private:
            data.update({
                'is_admin': self.is_admin,
                'updated_at': self.updated_at.isoformat() if self.updated_at else None
            })
            application = getattr(self, "dealer_application", None)
            if application is not None:
                data["dealer_application"] = application.to_dict()
                data["dealer_application_status"] = application.status
            profile = getattr(self, "dealer_profile", None)
            if profile is not None:
                data["dealer_profile"] = profile.to_dict()
            if self.is_admin:
                from .admin_roles import normalize_admin_role, permissions_for_role

                role = normalize_admin_role(self)
                data['admin_role'] = role
                data['permissions'] = permissions_for_role(role)
            else:
                data['admin_role'] = None
                data['permissions'] = []
        
        return data
    
    def __repr__(self):
        return f'<User {self.username}>'


class AdminAccount(db.Model):
    """Dashboard credentials backed by a dedicated admin-only User principal."""

    __tablename__ = "admin_account"

    id = db.Column(db.Integer, primary_key=True)
    public_id = db.Column(db.String(50), unique=True, nullable=False, default=lambda: str(uuid.uuid4()))
    principal_user_id = db.Column(
        db.Integer,
        db.ForeignKey("user.id", ondelete="RESTRICT"),
        unique=True,
        nullable=False,
        index=True,
    )
    origin_user_public_id = db.Column(db.String(50), nullable=True, index=True)
    username = db.Column(db.String(80), unique=True, nullable=False, index=True)
    email = db.Column(db.String(120), unique=True, nullable=True, index=True)
    phone_number = db.Column(db.String(20), unique=True, nullable=True, index=True)
    password_hash = db.Column(db.String(128), nullable=False)
    is_active = db.Column(db.Boolean, nullable=False, default=True)
    admin_role = db.Column(db.String(32), nullable=False, default="super_admin")
    created_at = db.Column(db.DateTime, nullable=False, default=utcnow)
    updated_at = db.Column(db.DateTime, nullable=False, default=utcnow, onupdate=utcnow)
    last_login = db.Column(db.DateTime, nullable=True)

    principal = db.relationship("User", foreign_keys=[principal_user_id], lazy="joined")

    def set_password(self, password):
        self.password_hash = bcrypt.generate_password_hash(password).decode("utf-8")

    def check_password(self, password):
        try:
            return bool(self.password_hash) and bcrypt.check_password_hash(self.password_hash, password)
        except Exception:
            return False

    def __repr__(self):
        return f"<AdminAccount {self.username}>"


class PendingSignup(db.Model):
    """
    Pending email-based signup that must be confirmed before creating a real User.

    We intentionally keep this minimal and independent of the main User schema so
    we can evolve signup without breaking existing accounts.
    """
    __tablename__ = "pending_signup"

    id = db.Column(db.Integer, primary_key=True)
    email = db.Column(db.String(120), nullable=False, index=True)
    username = db.Column(db.String(80), nullable=False)
    password_hash = db.Column(db.String(128), nullable=False)
    first_name = db.Column(db.String(50), nullable=False)
    last_name = db.Column(db.String(50), nullable=False)
    phone_number = db.Column(db.String(20), nullable=True)
    is_dealer_requested = db.Column(db.Boolean, default=False, nullable=False)
    dealership_name = db.Column(db.String(120), nullable=True)
    dealership_phone = db.Column(db.String(20), nullable=True)
    dealership_location = db.Column(db.String(200), nullable=True)
    token = db.Column(db.String(64), unique=True, nullable=False, index=True)
    created_at = db.Column(db.DateTime, default=utcnow, nullable=False)
    expires_at = db.Column(db.DateTime, nullable=False)
    is_used = db.Column(db.Boolean, default=False, nullable=False)


class DealerApplication(db.Model):
    """Current dealer application. Decisions preserve its immutable review history."""

    __tablename__ = "dealer_application"

    VALID_STATUSES = frozenset(
        {"draft", "submitted", "under_review", "needs_changes", "approved", "rejected"}
    )

    id = db.Column(db.Integer, primary_key=True)
    public_id = db.Column(
        db.String(50), unique=True, nullable=False, default=lambda: str(uuid.uuid4())
    )
    user_id = db.Column(db.Integer, db.ForeignKey("user.id"), unique=True, nullable=False)
    status = db.Column(db.String(20), nullable=False, default="draft", index=True)
    dealership_name = db.Column(db.String(120), nullable=False)
    dealership_phone = db.Column(db.String(20), nullable=False)
    dealership_phones = db.Column(db.JSON, nullable=True)
    dealership_location = db.Column(db.String(200), nullable=False)
    dealership_description = db.Column(db.Text, nullable=True)
    business_registration_number = db.Column(db.String(120), nullable=True)
    document_urls = db.Column(db.JSON, nullable=True)
    verification_photo_filename = db.Column(db.String(255), nullable=True)
    review_reason = db.Column(db.Text, nullable=True)
    submitted_at = db.Column(db.DateTime, nullable=True)
    reviewed_at = db.Column(db.DateTime, nullable=True)
    created_at = db.Column(db.DateTime, default=utcnow, nullable=False)
    updated_at = db.Column(db.DateTime, default=utcnow, onupdate=utcnow, nullable=False)

    user = db.relationship("User", foreign_keys=[user_id], back_populates="dealer_application")
    decisions = db.relationship(
        "DealerDecision",
        back_populates="application",
        cascade="all, delete-orphan",
        order_by="DealerDecision.created_at.desc()",
    )

    def snapshot(self):
        return {
            "dealership_name": self.dealership_name,
            "dealership_phone": self.dealership_phone,
            "dealership_phones": self.dealership_phones or [],
            "dealership_location": self.dealership_location,
            "dealership_description": self.dealership_description,
            "business_registration_number": self.business_registration_number,
            "document_urls": self.document_urls or [],
            "has_verification_photo": bool(self.verification_photo_filename),
        }

    def to_dict(self, include_decisions=False):
        data = {
            "id": self.public_id,
            "status": self.status,
            **self.snapshot(),
            "review_reason": self.review_reason,
            "submitted_at": self.submitted_at.isoformat() if self.submitted_at else None,
            "reviewed_at": self.reviewed_at.isoformat() if self.reviewed_at else None,
            "created_at": self.created_at.isoformat() if self.created_at else None,
            "updated_at": self.updated_at.isoformat() if self.updated_at else None,
        }
        if include_decisions:
            data["decisions"] = [decision.to_dict() for decision in self.decisions]
        return data


class DealerProfile(db.Model):
    """Approved public dealership data, independent from application review state."""

    __tablename__ = "dealer_profile"

    id = db.Column(db.Integer, primary_key=True)
    public_id = db.Column(
        db.String(50), unique=True, nullable=False, default=lambda: str(uuid.uuid4())
    )
    user_id = db.Column(db.Integer, db.ForeignKey("user.id"), unique=True, nullable=False)
    dealership_name = db.Column(db.String(120), nullable=False)
    dealership_phone = db.Column(db.String(20), nullable=False)
    dealership_phones = db.Column(db.JSON, nullable=True)
    dealership_emails = db.Column(db.JSON, nullable=True)
    dealership_verified_emails = db.Column(db.JSON, nullable=True)
    dealership_location = db.Column(db.String(200), nullable=False)
    dealership_description = db.Column(db.Text, nullable=True)
    dealership_cover_picture = db.Column(db.String(200), nullable=True)
    dealership_latitude = db.Column(db.Float, nullable=True)
    dealership_longitude = db.Column(db.Float, nullable=True)
    dealership_opening_hours = db.Column(db.JSON, nullable=True)
    is_featured = db.Column(db.Boolean, default=False, nullable=False)
    created_at = db.Column(db.DateTime, default=utcnow, nullable=False)
    updated_at = db.Column(db.DateTime, default=utcnow, onupdate=utcnow, nullable=False)

    user = db.relationship("User", back_populates="dealer_profile")

    def to_dict(self):
        emails = self.dealership_emails or []
        if not isinstance(emails, list):
            emails = []
        verified_emails = self.dealership_verified_emails or []
        if not isinstance(verified_emails, list):
            verified_emails = []
        return {
            "id": self.public_id,
            "dealership_name": self.dealership_name,
            "dealership_phone": self.dealership_phone,
            "dealership_phones": self.dealership_phones or [],
            "dealership_emails": [str(x).strip() for x in emails if str(x).strip()],
            "dealership_verified_emails": [
                str(x).strip().lower() for x in verified_emails if str(x).strip()
            ],
            "dealership_location": self.dealership_location,
            "dealership_description": self.dealership_description,
            "dealership_cover_picture": self.dealership_cover_picture,
            "dealership_latitude": self.dealership_latitude,
            "dealership_longitude": self.dealership_longitude,
            "dealership_opening_hours": self.dealership_opening_hours,
            "is_featured_dealer": bool(self.is_featured),
            "created_at": self.created_at.isoformat() if self.created_at else None,
            "updated_at": self.updated_at.isoformat() if self.updated_at else None,
        }


class DealerDecision(db.Model):
    """Immutable audit event for a dealer application transition."""

    __tablename__ = "dealer_decision"

    id = db.Column(db.Integer, primary_key=True)
    public_id = db.Column(
        db.String(50), unique=True, nullable=False, default=lambda: str(uuid.uuid4())
    )
    application_id = db.Column(
        db.Integer, db.ForeignKey("dealer_application.id"), nullable=False, index=True
    )
    reviewer_id = db.Column(db.Integer, db.ForeignKey("user.id"), nullable=True)
    decision = db.Column(db.String(20), nullable=False)
    reason = db.Column(db.Text, nullable=True)
    application_snapshot = db.Column(db.JSON, nullable=False, default=dict)
    created_at = db.Column(db.DateTime, default=utcnow, nullable=False, index=True)

    application = db.relationship("DealerApplication", back_populates="decisions")
    reviewer = db.relationship("User", foreign_keys=[reviewer_id])

    def to_dict(self):
        return {
            "id": self.public_id,
            "decision": self.decision,
            "reason": self.reason,
            "application_snapshot": self.application_snapshot or {},
            "reviewer": (
                {
                    "id": self.reviewer.public_id,
                    "username": self.reviewer.username,
                }
                if self.reviewer
                else None
            ),
            "created_at": self.created_at.isoformat() if self.created_at else None,
        }


class Car(db.Model):
    __tablename__ = 'car'
    __table_args__ = (
        # Composite indexes for public browse / filter / seller inventory (H-04).
        db.Index("ix_car_active_status_created_at", "is_active", "status", "created_at"),
        db.Index("ix_car_active_brand_price", "is_active", "brand", "price"),
        db.Index("ix_car_active_location_created_at", "is_active", "location", "created_at"),
        db.Index("ix_car_active_year_price", "is_active", "year", "price"),
        db.Index("ix_car_active_featured_created_at", "is_active", "is_featured", "created_at"),
        db.Index("ix_car_seller_active_created_at", "seller_id", "is_active", "created_at"),
    )
    
    id = db.Column(db.Integer, primary_key=True)
    public_id = db.Column(db.String(50), unique=True, default=lambda: str(uuid.uuid4()))
    seller_id = db.Column(db.Integer, db.ForeignKey('user.id'), nullable=False)
    
    # Basic car information
    title = db.Column(db.String(200), nullable=False, default='')  # Some legacy DBs require NOT NULL
    title_status = db.Column(db.String(20), nullable=False, default='clean')
    damaged_parts = db.Column(db.Integer, nullable=True)
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
    status = db.Column(db.String(20), nullable=False, default='active', index=True)
    
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
    vin = db.Column(db.String(17), nullable=True)
    engine_size = db.Column(db.Float, nullable=True)  # liters
    cylinder_count = db.Column(db.Integer, nullable=True)
    # Market / homologation region (e.g. us, gcc, eu); see app filter `region_specs`.
    region_specs = db.Column(db.String(20), nullable=True, index=True)
    # License plate metadata (optional)
    plate_type = db.Column(db.String(20), nullable=True, index=True)
    plate_city = db.Column(db.String(50), nullable=True, index=True)
    # Listing contact numbers (primary + list, max 3 client-side).
    contact_phone = db.Column(db.String(20), nullable=True)
    contact_phones = db.Column(db.JSON, nullable=True)
    
    # Status and metadata
    is_active = db.Column(db.Boolean, default=True, index=True)
    is_featured = db.Column(db.Boolean, default=False)
    views_count = db.Column(db.Integer, default=0)
    created_at = db.Column(db.DateTime, default=utcnow, index=True)
    updated_at = db.Column(db.DateTime, default=utcnow, onupdate=utcnow)
    
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
        """Convert car to dictionary. id is public_id when set, else numeric id so detail link works."""
        data = {
            'id': self.public_id if getattr(self, "public_id", None) else str(self.id),
            'title': getattr(self, "title", None) or f"{self.brand} {self.model} {self.year}".strip(),
            'brand': self.brand,
            'model': self.model,
            'trim': getattr(self, "trim", None) or "",
            'year': self.year,
            'mileage': self.mileage,
            'engine_type': self.engine_type,
            'fuel_type': getattr(self, "fuel_type", None),
            'transmission': self.transmission,
            'drive_type': self.drive_type,
            'condition': self.condition,
            'body_type': self.body_type,
            'title_status': getattr(self, "title_status", None),
            'damaged_parts': self.damaged_parts,
            'status': getattr(self, "status", None),
            'price': self.price,
            'currency': self.currency,
            'location': self.location,
            'seating': getattr(self, "seating", None),
            'description': self.description,
            'color': self.color,
            'fuel_economy': self.fuel_economy,
            'vin': getattr(self, "vin", None),
            'engine_size': getattr(self, "engine_size", None),
            'cylinder_count': getattr(self, "cylinder_count", None),
            'cylinders': getattr(self, "cylinder_count", None),  # alias for app
            'region_specs': getattr(self, "region_specs", None),
            'plate_type': getattr(self, "plate_type", None),
            'plateType': getattr(self, "plate_type", None),
            'plate_city': getattr(self, "plate_city", None),
            'plateCity': getattr(self, "plate_city", None),
            'contact_phone': getattr(self, "contact_phone", None),
            'contact_phones': (
                list(getattr(self, "contact_phones", None) or [])
                if isinstance(getattr(self, "contact_phones", None), list)
                else (
                    [getattr(self, "contact_phone")]
                    if getattr(self, "contact_phone", None)
                    else []
                )
            ),
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
    # Full R2/CDN HTTPS URLs exceed VARCHAR(200); keep aligned with car_video.video_url.
    image_url = db.Column(db.String(2048), nullable=False)
    is_primary = db.Column(db.Boolean, default=False)
    order = db.Column(db.Integer, default=0)
    # "listing" = normal gallery photos; "damage" = crash / damage disclosure (not in main carousel).
    kind = db.Column(db.String(20), nullable=False, default="listing")
    # Normalized vertical focal point used by cover-fit clients. Null = automatic.
    focus_y = db.Column(db.Float, nullable=True)
    image_width = db.Column(db.Integer, nullable=True)
    image_height = db.Column(db.Integer, nullable=True)
    created_at = db.Column(db.DateTime, default=utcnow)
    
    def to_dict(self):
        return {
            'id': self.id,
            'image_url': self.image_url,
            'is_primary': self.is_primary,
            'order': self.order,
            'kind': getattr(self, "kind", None) or "listing",
            'focus_y': self.focus_y,
            'image_width': self.image_width,
            'image_height': self.image_height,
        }
    
    def __repr__(self):
        return f'<CarImage {self.image_url}>'

class CarVideo(db.Model):
    __tablename__ = 'car_video'
    
    id = db.Column(db.Integer, primary_key=True)
    car_id = db.Column(db.Integer, db.ForeignKey('car.id'), nullable=False)
    # Full R2/CDN URLs can exceed 200 chars
    video_url = db.Column(db.String(2048), nullable=False)
    thumbnail_url = db.Column(db.String(2048), nullable=True)
    duration = db.Column(db.Integer, nullable=True)  # Duration in seconds
    order = db.Column(db.Integer, default=0)
    created_at = db.Column(db.DateTime, default=utcnow)
    
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
    car_id = db.Column(db.Integer, db.ForeignKey('car.id'), nullable=False, unique=True, index=True)
    views = db.Column(db.Integer, default=0)
    messages = db.Column(db.Integer, default=0)
    calls = db.Column(db.Integer, default=0)
    shares = db.Column(db.Integer, default=0)
    favorites = db.Column(db.Integer, default=0)
    created_at = db.Column(db.DateTime, default=utcnow)
    updated_at = db.Column(db.DateTime, default=utcnow, onupdate=utcnow)
    
    # Relationship
    car = db.relationship('Car', backref='analytics')
    
    def to_dict(self):
        # Get image URL using the same logic as the my_listings endpoint
        def first_image_rel_path(car):
            if car and car.images:
                path = car.images[0].image_url or ''
                return path[8:] if path.startswith('uploads/') else path
            # Car model does not store a direct `image_url` field; keep empty when no images.
            return ''
        
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
        self.updated_at = utcnow()
        db.session.commit()
    
    def increment_messages(self):
        self.messages += 1
        self.updated_at = utcnow()
        db.session.commit()
    
    def increment_calls(self):
        self.calls += 1
        self.updated_at = utcnow()
        db.session.commit()
    
    def increment_shares(self):
        self.shares += 1
        self.updated_at = utcnow()
        db.session.commit()
    
    def increment_favorites(self):
        self.favorites += 1
        self.updated_at = utcnow()
        db.session.commit()
    
    def __repr__(self):
        return f'<ListingAnalytics car_id={self.car_id} views={self.views}>'

class Message(db.Model):
    __tablename__ = 'message'
    
    id = db.Column(db.Integer, primary_key=True)
    public_id = db.Column(db.String(50), unique=True, default=lambda: str(uuid.uuid4()))
    sender_id = db.Column(db.Integer, db.ForeignKey('user.id'), nullable=False, index=True)
    receiver_id = db.Column(db.Integer, db.ForeignKey('user.id'), nullable=False, index=True)
    car_id = db.Column(db.Integer, db.ForeignKey('car.id'), nullable=True, index=True)
    reply_to_id = db.Column(db.Integer, db.ForeignKey('message.id'), nullable=True, index=True)
    content = db.Column(db.Text, nullable=False)
    message_type = db.Column(db.String(20), default='text')  # text, image, file
    attachment_url = db.Column(db.Text, nullable=True)
    attachments = db.Column(db.JSON, nullable=True)
    listing_preview = db.Column(db.JSON, nullable=True)
    is_read = db.Column(db.Boolean, default=False, index=True)
    is_deleted = db.Column(db.Boolean, default=False, index=True)
    edited_at = db.Column(db.DateTime, nullable=True)
    created_at = db.Column(db.DateTime, default=utcnow, index=True)

    reply_to = db.relationship(
        "Message",
        remote_side=[id],
        foreign_keys=[reply_to_id],
        lazy="joined",
    )

    __table_args__ = (
        db.Index("ix_message_receiver_is_read_created_at", "receiver_id", "is_read", "created_at"),
        db.Index("ix_message_car_created_at", "car_id", "created_at"),
        db.Index("ix_message_sender_created_at", "sender_id", "created_at"),
    )
    
    def _reply_preview(self):
        parent = self.reply_to
        if parent is None and self.reply_to_id:
            parent = db.session.get(Message, self.reply_to_id)
        if not parent:
            return None
        if parent.is_deleted:
            content = "This message was deleted"
        elif parent.content:
            content = parent.content
        elif parent.listing_preview:
            content = "[Listing]"
        elif parent.attachments:
            content = f"[{len(parent.attachments)} attachments]"
        elif parent.attachment_url:
            content = "[Attachment]"
        else:
            content = ""
        return {
            'id': parent.public_id,
            'sender_id': parent.sender.public_id if parent.sender else None,
            'sender_name': f"{parent.sender.first_name} {parent.sender.last_name}" if parent.sender else None,
            'content': content,
            'message_type': parent.message_type,
            'is_deleted': parent.is_deleted,
        }

    def to_dict(self):
        reply_parent = self.reply_to
        if reply_parent is None and self.reply_to_id:
            reply_parent = db.session.get(Message, self.reply_to_id)
        return {
            'id': self.public_id,
            'sender_id': self.sender.public_id if self.sender else None,
            'receiver_id': self.receiver.public_id if self.receiver else None,
            'car_id': self.car.public_id if self.car else None,
            'reply_to_message_id': reply_parent.public_id if reply_parent else None,
            'reply_to_message': self._reply_preview(),
            'content': "This message was deleted" if self.is_deleted else self.content,
            'message_type': self.message_type,
            'attachment_url': None if self.is_deleted else self.attachment_url,
            'attachments': [] if self.is_deleted else self.attachments,
            'listing_preview': None if self.is_deleted else self.listing_preview,
            'is_read': self.is_read,
            'is_deleted': self.is_deleted,
            'edited_at': self.edited_at.isoformat() if self.edited_at else None,
            'created_at': self.created_at.isoformat() if self.created_at else None,
            'sender_name': f"{self.sender.first_name} {self.sender.last_name}".strip() if self.sender else None,
            'sender_username': self.sender.username if self.sender else None,
            'receiver_name': f"{self.receiver.first_name} {self.receiver.last_name}".strip() if self.receiver else None,
            'receiver_username': self.receiver.username if self.receiver else None,
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
    created_at = db.Column(db.DateTime, default=utcnow, index=True)
    
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


class ScheduledNotification(db.Model):
    """Admin-scheduled broadcast to be delivered at scheduled_at."""

    __tablename__ = "scheduled_notification"

    id = db.Column(db.Integer, primary_key=True)
    title = db.Column(db.String(200), nullable=False)
    message = db.Column(db.Text, nullable=False)
    audience = db.Column(db.String(20), nullable=False, default="all")
    target_user_public_id = db.Column(db.String(50), nullable=True)
    notification_type = db.Column(db.String(50), nullable=False, default="admin")
    send_push = db.Column(db.Boolean, nullable=False, default=True)
    scheduled_at = db.Column(db.DateTime, nullable=False, index=True)
    status = db.Column(
        db.String(20), nullable=False, default="pending", index=True
    )  # pending | sending | sent | cancelled | failed
    result = db.Column(db.JSON, nullable=True)
    error_message = db.Column(db.Text, nullable=True)
    created_by_user_id = db.Column(db.Integer, db.ForeignKey("user.id"), nullable=True)
    created_at = db.Column(db.DateTime, default=utcnow)
    updated_at = db.Column(db.DateTime, default=utcnow, onupdate=utcnow)
    sent_at = db.Column(db.DateTime, nullable=True)

    def to_admin_dict(self):
        return {
            "id": self.id,
            "title": self.title,
            "message": self.message,
            "audience": self.audience,
            "target_user_id": self.target_user_public_id,
            "notification_type": self.notification_type,
            "send_push": bool(self.send_push),
            "scheduled_at": self.scheduled_at.isoformat() if self.scheduled_at else None,
            "status": self.status,
            "result": self.result,
            "error_message": self.error_message,
            "created_at": self.created_at.isoformat() if self.created_at else None,
            "updated_at": self.updated_at.isoformat() if self.updated_at else None,
            "sent_at": self.sent_at.isoformat() if self.sent_at else None,
        }

    def __repr__(self):
        return f"<ScheduledNotification {self.id} {self.status}>"


class UserAction(db.Model):
    __tablename__ = 'user_action'
    
    id = db.Column(db.Integer, primary_key=True)
    user_id = db.Column(db.Integer, db.ForeignKey('user.id'), nullable=False)
    action_type = db.Column(db.String(50), nullable=False)  # view_listing, contact_seller, edit_listing, etc.
    target_type = db.Column(db.String(50), nullable=True)  # car, user, message, etc.
    target_id = db.Column(db.String(50), nullable=True)
    action_metadata = db.Column(db.JSON, nullable=True)
    created_at = db.Column(db.DateTime, default=utcnow, index=True)
    
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
    created_at = db.Column(db.DateTime, default=utcnow)
    
    def is_expired(self):
        return utcnow() > self.expires_at
    
    def __repr__(self):
        return f'<PasswordReset {self.token}>'

class EmailVerification(db.Model):
    __tablename__ = 'email_verification'
    
    id = db.Column(db.Integer, primary_key=True)
    user_id = db.Column(db.Integer, db.ForeignKey('user.id'), nullable=False)
    token = db.Column(db.String(100), unique=True, nullable=False)
    expires_at = db.Column(db.DateTime, nullable=False)
    is_used = db.Column(db.Boolean, default=False)
    created_at = db.Column(db.DateTime, default=utcnow)
    
    def is_expired(self):
        return utcnow() > self.expires_at
    
    def __repr__(self):
        return f'<EmailVerification {self.token}>'

class SavedSearch(db.Model):
    __tablename__ = 'saved_search'

    id = db.Column(db.Integer, primary_key=True)
    public_id = db.Column(db.String(50), unique=True, default=lambda: str(uuid.uuid4()), index=True)
    user_id = db.Column(db.Integer, db.ForeignKey('user.id'), nullable=False, index=True)
    name = db.Column(db.String(200), nullable=False, default='')
    filters = db.Column(db.JSON, nullable=False, default=dict)
    notify = db.Column(db.Boolean, default=True, nullable=False)
    auto_saved = db.Column(db.Boolean, default=False, nullable=False)
    created_at = db.Column(db.DateTime, default=utcnow, index=True)
    updated_at = db.Column(db.DateTime, default=utcnow, onupdate=utcnow)

    user = db.relationship('User', backref=db.backref('saved_searches', lazy='dynamic'))

    def to_dict(self):
        return {
            'id': self.public_id,
            'name': self.name or '',
            'filters': self.filters if isinstance(self.filters, dict) else {},
            'notify': bool(self.notify),
            'auto_saved': bool(self.auto_saved),
            'created_at': self.created_at.isoformat() if self.created_at else None,
            'updated_at': self.updated_at.isoformat() if self.updated_at else None,
        }

    def __repr__(self):
        return f'<SavedSearch user={self.user_id} name={self.name!r}>'


class SavedSearchAlert(db.Model):
    """Records that a saved search already triggered an alert for a listing (dedupe)."""
    __tablename__ = 'saved_search_alert'

    id = db.Column(db.Integer, primary_key=True)
    saved_search_id = db.Column(db.Integer, db.ForeignKey('saved_search.id'), nullable=False, index=True)
    car_id = db.Column(db.Integer, db.ForeignKey('car.id'), nullable=False, index=True)
    created_at = db.Column(db.DateTime, default=utcnow)

    __table_args__ = (
        db.UniqueConstraint('saved_search_id', 'car_id', name='uq_saved_search_alert'),
    )

    def __repr__(self):
        return f'<SavedSearchAlert search={self.saved_search_id} car={self.car_id}>'


class BlockedUser(db.Model):
    __tablename__ = 'blocked_user'

    id = db.Column(db.Integer, primary_key=True)
    blocker_id = db.Column(db.Integer, db.ForeignKey('user.id'), nullable=False, index=True)
    blocked_id = db.Column(db.Integer, db.ForeignKey('user.id'), nullable=False, index=True)
    created_at = db.Column(db.DateTime, default=utcnow)

    __table_args__ = (
        db.UniqueConstraint('blocker_id', 'blocked_id', name='uq_blocked_user'),
    )

    def __repr__(self):
        return f'<BlockedUser blocker={self.blocker_id} blocked={self.blocked_id}>'


class UserReport(db.Model):
    __tablename__ = 'user_report'

    id = db.Column(db.Integer, primary_key=True)
    reporter_id = db.Column(db.Integer, db.ForeignKey('user.id'), nullable=False, index=True)
    reported_id = db.Column(db.Integer, db.ForeignKey('user.id'), nullable=False, index=True)
    reason = db.Column(db.String(200), nullable=False)
    details = db.Column(db.Text, nullable=True)
    status = db.Column(db.String(20), default='pending')  # pending, reviewed, resolved, dismissed
    admin_notes = db.Column(db.Text, nullable=True)
    created_at = db.Column(db.DateTime, default=utcnow)
    resolved_at = db.Column(db.DateTime, nullable=True)

    reporter = db.relationship('User', foreign_keys=[reporter_id])
    reported = db.relationship('User', foreign_keys=[reported_id])

    def to_admin_dict(self) -> dict:
        reporter = self.reporter
        reported = self.reported
        return {
            'id': self.id,
            'type': 'user',
            'reason': self.reason,
            'details': self.details,
            'status': self.status,
            'admin_notes': self.admin_notes,
            'created_at': self.created_at.isoformat() if self.created_at else None,
            'resolved_at': self.resolved_at.isoformat() if self.resolved_at else None,
            'reporter': {
                'id': reporter.public_id if reporter else None,
                'username': reporter.username if reporter else None,
            },
            'reported_user': {
                'id': reported.public_id if reported else None,
                'username': reported.username if reported else None,
                'account_type': getattr(reported, 'account_type', None) if reported else None,
            },
        }

    def __repr__(self):
        return f'<UserReport reporter={self.reporter_id} reported={self.reported_id}>'


class ListingReport(db.Model):
    __tablename__ = 'listing_report'

    id = db.Column(db.Integer, primary_key=True)
    reporter_id = db.Column(db.Integer, db.ForeignKey('user.id'), nullable=False, index=True)
    car_id = db.Column(db.Integer, db.ForeignKey('car.id'), nullable=False, index=True)
    reason = db.Column(db.String(200), nullable=False)
    details = db.Column(db.Text, nullable=True)
    status = db.Column(db.String(20), default='pending')  # pending, reviewed, resolved, dismissed
    admin_notes = db.Column(db.Text, nullable=True)
    created_at = db.Column(db.DateTime, default=utcnow)
    resolved_at = db.Column(db.DateTime, nullable=True)

    reporter = db.relationship('User', foreign_keys=[reporter_id])
    car = db.relationship('Car', foreign_keys=[car_id])

    def to_admin_dict(self) -> dict:
        reporter = self.reporter
        car = self.car
        # Prefer relationship (eager-loadable); avoid per-row User.query.get N+1.
        seller = getattr(car, "seller", None) if car is not None else None
        listing_id = None
        if car:
            listing_id = car.public_id if getattr(car, 'public_id', None) else str(car.id)
        return {
            'id': self.id,
            'type': 'listing',
            'reason': self.reason,
            'details': self.details,
            'status': self.status,
            'admin_notes': self.admin_notes,
            'created_at': self.created_at.isoformat() if self.created_at else None,
            'resolved_at': self.resolved_at.isoformat() if self.resolved_at else None,
            'reporter': {
                'id': reporter.public_id if reporter else None,
                'username': reporter.username if reporter else None,
            },
            'listing': {
                'id': listing_id,
                'title': car.title if car else None,
                'brand': car.brand if car else None,
                'model': car.model if car else None,
            },
            'seller': {
                'id': seller.public_id if seller else None,
                'username': seller.username if seller else None,
            },
        }

    def __repr__(self):
        return f'<ListingReport reporter={self.reporter_id} car={self.car_id}>'


class TokenBlacklist(db.Model):
    __tablename__ = 'token_blacklist'
    
    id = db.Column(db.Integer, primary_key=True)
    jti = db.Column(db.String(36), nullable=False, unique=True, index=True)  # JWT ID
    token_type = db.Column(db.String(10), nullable=False)  # 'access' or 'refresh'
    user_id = db.Column(db.Integer, db.ForeignKey('user.id'), nullable=True)
    revoked_at = db.Column(db.DateTime, nullable=False, default=utcnow)
    expires_at = db.Column(db.DateTime, nullable=False)
    
    def __repr__(self):
        return f'<TokenBlacklist {self.jti}>'


class AppSetting(db.Model):
    """Key/value JSON settings editable from the admin dashboard."""

    __tablename__ = "app_setting"

    id = db.Column(db.Integer, primary_key=True)
    key = db.Column(db.String(64), unique=True, nullable=False, index=True)
    value = db.Column(db.JSON, nullable=False, default=dict)
    updated_at = db.Column(db.DateTime, default=utcnow, onupdate=utcnow)

    def to_dict(self):
        return {
            "key": self.key,
            "value": self.value if isinstance(self.value, dict) else {},
            "updated_at": self.updated_at.isoformat() if self.updated_at else None,
        }

    def __repr__(self):
        return f"<AppSetting {self.key}>"


class CatalogBrand(db.Model):
    """Vehicle make for admin-managed catalog (mirrors Flutter car_catalog.json)."""

    __tablename__ = "catalog_brand"

    id = db.Column(db.Integer, primary_key=True)
    name = db.Column(db.String(120), unique=True, nullable=False, index=True)
    is_active = db.Column(db.Boolean, default=True, nullable=False)
    sort_order = db.Column(db.Integer, default=0, nullable=False)
    created_at = db.Column(db.DateTime, default=utcnow)
    updated_at = db.Column(db.DateTime, default=utcnow, onupdate=utcnow)

    models = db.relationship(
        "CatalogVehicleModel",
        back_populates="brand",
        cascade="all, delete-orphan",
        lazy="dynamic",
    )

    def to_dict(self, include_model_count: bool = False):
        data = {
            "id": self.id,
            "name": self.name,
            "is_active": bool(self.is_active),
            "sort_order": int(self.sort_order or 0),
            "created_at": self.created_at.isoformat() if self.created_at else None,
            "updated_at": self.updated_at.isoformat() if self.updated_at else None,
        }
        if include_model_count:
            data["model_count"] = self.models.count()
            data["active_model_count"] = self.models.filter_by(is_active=True).count()
        return data

    def __repr__(self):
        return f"<CatalogBrand {self.name}>"


class CatalogVehicleModel(db.Model):
    """Vehicle model belonging to a catalog brand."""

    __tablename__ = "catalog_vehicle_model"
    __table_args__ = (
        db.UniqueConstraint("brand_id", "name", name="uq_catalog_model_brand_name"),
    )

    id = db.Column(db.Integer, primary_key=True)
    brand_id = db.Column(db.Integer, db.ForeignKey("catalog_brand.id"), nullable=False, index=True)
    name = db.Column(db.String(120), nullable=False, index=True)
    is_active = db.Column(db.Boolean, default=True, nullable=False)
    sort_order = db.Column(db.Integer, default=0, nullable=False)
    created_at = db.Column(db.DateTime, default=utcnow)
    updated_at = db.Column(db.DateTime, default=utcnow, onupdate=utcnow)

    brand = db.relationship("CatalogBrand", back_populates="models")
    trims = db.relationship(
        "CatalogTrim",
        back_populates="model",
        cascade="all, delete-orphan",
        lazy="dynamic",
    )

    def to_dict(self, include_trim_count: bool = False):
        data = {
            "id": self.id,
            "brand_id": self.brand_id,
            "brand_name": self.brand.name if self.brand else None,
            "name": self.name,
            "is_active": bool(self.is_active),
            "sort_order": int(self.sort_order or 0),
            "created_at": self.created_at.isoformat() if self.created_at else None,
            "updated_at": self.updated_at.isoformat() if self.updated_at else None,
        }
        if include_trim_count:
            data["trim_count"] = self.trims.count()
        return data

    def __repr__(self):
        return f"<CatalogVehicleModel {self.name}>"


class CatalogTrim(db.Model):
    """Optional trim level for a catalog model."""

    __tablename__ = "catalog_trim"
    __table_args__ = (
        db.UniqueConstraint("model_id", "name", name="uq_catalog_trim_model_name"),
    )

    id = db.Column(db.Integer, primary_key=True)
    model_id = db.Column(
        db.Integer, db.ForeignKey("catalog_vehicle_model.id"), nullable=False, index=True
    )
    name = db.Column(db.String(120), nullable=False)
    is_active = db.Column(db.Boolean, default=True, nullable=False)
    sort_order = db.Column(db.Integer, default=0, nullable=False)
    created_at = db.Column(db.DateTime, default=utcnow)
    updated_at = db.Column(db.DateTime, default=utcnow, onupdate=utcnow)

    model = db.relationship("CatalogVehicleModel", back_populates="trims")

    def to_dict(self):
        return {
            "id": self.id,
            "model_id": self.model_id,
            "name": self.name,
            "is_active": bool(self.is_active),
            "sort_order": int(self.sort_order or 0),
            "brand_name": self.model.brand.name if self.model and self.model.brand else None,
            "model_name": self.model.name if self.model else None,
        }

    def __repr__(self):
        return f"<CatalogTrim {self.name}>"


class CatalogBodyType(db.Model):
    """Body type options for listings / filters."""

    __tablename__ = "catalog_body_type"

    id = db.Column(db.Integer, primary_key=True)
    name = db.Column(db.String(80), unique=True, nullable=False, index=True)
    is_active = db.Column(db.Boolean, default=True, nullable=False)
    sort_order = db.Column(db.Integer, default=0, nullable=False)
    created_at = db.Column(db.DateTime, default=utcnow)
    updated_at = db.Column(db.DateTime, default=utcnow, onupdate=utcnow)

    def to_dict(self):
        return {
            "id": self.id,
            "name": self.name,
            "is_active": bool(self.is_active),
            "sort_order": int(self.sort_order or 0),
            "created_at": self.created_at.isoformat() if self.created_at else None,
            "updated_at": self.updated_at.isoformat() if self.updated_at else None,
        }

    def __repr__(self):
        return f"<CatalogBodyType {self.name}>"

