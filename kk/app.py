import os
from flask import Flask, render_template, request, redirect, url_for, flash, jsonify, send_from_directory, abort, session, request as flask_request
from flask_sqlalchemy import SQLAlchemy
from werkzeug.utils import secure_filename
from datetime import datetime, timedelta
from flask_login import LoginManager, UserMixin, login_user, login_required, logout_user, current_user
from flask_migrate import Migrate
from werkzeug.security import generate_password_hash, check_password_hash
import json
import requests
import uuid
import hashlib
import hmac
import base64
from urllib.parse import urlencode
from flask_dance.contrib.google import make_google_blueprint, google
from flask_dance.consumer import oauth_authorized
from oauthlib.oauth2.rfc6749.errors import TokenExpiredError

# Absolute path for the database
BASE_DIR = os.path.abspath(os.path.dirname(__file__))
DB_PATH = os.path.join(BASE_DIR, 'instance', 'cars.db')

app = Flask(__name__)
app.config['SECRET_KEY'] = 'your-secret-key'
app.config['SQLALCHEMY_DATABASE_URI'] = f'sqlite:///{DB_PATH}'
app.config['UPLOAD_FOLDER'] = 'static/uploads'
app.config['MAX_CONTENT_LENGTH'] = 16 * 1024 * 1024  # 16MB max file size
ALLOWED_EXTENSIONS = {'png', 'jpg', 'jpeg', 'gif'}
app.config['PERMANENT_SESSION_LIFETIME'] = timedelta(days=30)

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

# Ensure upload folder exists
os.makedirs(app.config['UPLOAD_FOLDER'], exist_ok=True)

class User(UserMixin, db.Model):
    id = db.Column(db.Integer, primary_key=True)
    username = db.Column(db.String(80), unique=True, nullable=False)
    email = db.Column(db.String(120), unique=True, nullable=False)
    password = db.Column(db.String(120), nullable=False)
    created_at = db.Column(db.DateTime, nullable=False, default=datetime.utcnow)

@login_manager.user_loader
def load_user(user_id):
    return User.query.get(int(user_id))

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
    images = db.relationship('CarImage', backref='car', lazy=True, cascade='all, delete-orphan')
    favorited_by = db.relationship('Favorite', back_populates='car', lazy=True, cascade='all, delete-orphan')
    status = db.Column(db.String(20), nullable=False, default='pending_payment')  # pending_payment, active, etc.

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
            os.remove(os.path.join(app.config['UPLOAD_FOLDER'], image.image_url.split('/')[-1]))
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

@app.route('/search')
def search():
    query = request.args.get('query', '')
    def sanitize_numeric(val, typ):
        if val in (None, '', 'any', 'Undefined'):
            return None
        try:
            return typ(val)
        except Exception:
            return None

    min_price = sanitize_numeric(request.args.get('min_price'), float)
    max_price = sanitize_numeric(request.args.get('max_price'), float)
    min_year = sanitize_numeric(request.args.get('min_year'), int)
    max_year = sanitize_numeric(request.args.get('max_year'), int)
    min_mileage = sanitize_numeric(request.args.get('min_mileage'), int)
    max_mileage = sanitize_numeric(request.args.get('max_mileage'), int)
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

    if min_price is not None and min_price != 'any':
        car_query = car_query.filter(Car.price >= min_price)
    if max_price is not None and max_price != 'any':
        car_query = car_query.filter(Car.price <= max_price)
    if min_year is not None and min_year != 'any':
        car_query = car_query.filter(Car.year >= min_year)
    if max_year is not None and max_year != 'any':
        car_query = car_query.filter(Car.year <= max_year)
    if min_mileage is not None and min_mileage != 'any' and min_mileage != 0:
        car_query = car_query.filter(Car.mileage >= min_mileage)
    if max_mileage is not None and max_mileage != 'any' and max_mileage != 0:
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
        if sort_by == 'price_asc':
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

@app.route('/static/uploads/car_brand_logos/<filename>')
def serve_brand_logo(filename):
    return send_from_directory('static/uploads/car_brand_logos', filename)

if __name__ == '__main__':
    with app.app_context():
        try:
            # Drop all tables and recreate them
            db.drop_all()
            db.create_all()
            
            # Populate car models
            populate_car_models()
            print("Database initialized successfully!")
        except Exception as e:
            print(f"Error initializing database: {str(e)}")
            raise e
    
    app.run(host='0.0.0.0', port=5000, debug=True) 