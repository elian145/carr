from flask import Flask, jsonify, request, g
from flask_sqlalchemy import SQLAlchemy
from datetime import datetime
import os
from sqlalchemy import and_

# Setup Flask app
BASE_DIR = os.path.abspath(os.path.dirname(__file__))
DB_PATH = os.path.join(BASE_DIR, 'instance', 'cars.db')

app = Flask(__name__)
app.config['SQLALCHEMY_DATABASE_URI'] = f'sqlite:///{DB_PATH}'
app.config['SQLALCHEMY_TRACK_MODIFICATIONS'] = False

db = SQLAlchemy(app)

# Your Car model
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
    cylinder_count = db.Column(db.Integer, nullable=True)
    engine_size = db.Column(db.Float, nullable=True)
    import_country = db.Column(db.String(50), nullable=True)
    body_type = db.Column(db.String(20), nullable=False)
    seating = db.Column(db.Integer, nullable=False)
    drive_type = db.Column(db.String(20), nullable=False)
    license_plate_type = db.Column(db.String(20), nullable=True)
    city = db.Column(db.String(50), nullable=True)
    status = db.Column(db.String(20), nullable=False, default='pending_payment')

# Favorite model (if not already defined)
class Favorite(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    user_id = db.Column(db.Integer, nullable=False)
    car_id = db.Column(db.Integer, nullable=False)
    created_at = db.Column(db.DateTime, nullable=False, default=datetime.utcnow)

# Chat endpoints for mobile
class Conversation(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    car_id = db.Column(db.Integer, nullable=False)
    buyer_id = db.Column(db.Integer, nullable=False)
    seller_id = db.Column(db.Integer, nullable=False)
    created_at = db.Column(db.DateTime, nullable=False, default=datetime.utcnow)
    updated_at = db.Column(db.DateTime, nullable=False, default=datetime.utcnow)

class Message(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    conversation_id = db.Column(db.Integer, nullable=False)
    sender_id = db.Column(db.Integer, nullable=False)
    content = db.Column(db.Text, nullable=False)
    is_read = db.Column(db.Boolean, default=False)
    created_at = db.Column(db.DateTime, nullable=False, default=datetime.utcnow)

# Dummy user_id for demo (replace with real auth in production)
USER_ID = 1

# Route to get all cars
@app.route('/cars', methods=['GET', 'POST'])
def cars():
    if request.method == 'GET':
        # Filtering
        query = Car.query.filter_by(status="active")
        brand = request.args.get('brand')
        model = request.args.get('model')
        min_price = request.args.get('min_price', type=float)
        max_price = request.args.get('max_price', type=float)
        min_year = request.args.get('min_year', type=int)
        max_year = request.args.get('max_year', type=int)
        city = request.args.get('city')
        condition = request.args.get('condition')
        transmission = request.args.get('transmission')
        fuel_type = request.args.get('fuel_type')
        body_type = request.args.get('body_type')
        # Add more filters as needed
        if brand:
            query = query.filter(Car.brand == brand)
        if model:
            query = query.filter(Car.model == model)
        if min_price is not None:
            query = query.filter(Car.price >= min_price)
        if max_price is not None:
            query = query.filter(Car.price <= max_price)
        if min_year is not None:
            query = query.filter(Car.year >= min_year)
        if max_year is not None:
            query = query.filter(Car.year <= max_year)
        if city:
            query = query.filter(Car.city == city)
        if condition:
            query = query.filter(Car.condition == condition)
        if transmission:
            query = query.filter(Car.transmission == transmission)
        if fuel_type:
            query = query.filter(Car.fuel_type == fuel_type)
        if body_type:
            query = query.filter(Car.body_type == body_type)
        cars = query.order_by(Car.created_at.desc()).all()
        result = []
        for car in cars:
            result.append({
                "id": car.id,
                "title": car.title,
                "brand": car.brand,
                "model": car.model,
                "trim": car.trim,
                "year": car.year,
                "price": car.price,
                "mileage": car.mileage,
                "condition": car.condition,
                "transmission": car.transmission,
                "fuel_type": car.fuel_type,
                "color": car.color,
                "image_url": car.image_url,
                "city": car.city,
                "status": car.status
            })
        return jsonify(result)
    elif request.method == 'POST':
        data = request.get_json()
        required_fields = [
            'title', 'brand', 'model', 'trim', 'year', 'mileage', 'condition',
            'transmission', 'fuel_type', 'color', 'body_type', 'seating', 'drive_type', 'title_status'
        ]
        missing = [f for f in required_fields if not data.get(f)]
        if missing:
            return jsonify({'error': f'Missing required fields: {", ".join(missing)}'}), 400
        car = Car(
            title=data['title'],
            brand=data['brand'],
            model=data['model'],
            trim=data['trim'],
            year=data['year'],
            price=data.get('price'),
            mileage=data['mileage'],
            condition=data['condition'],
            transmission=data['transmission'],
            fuel_type=data['fuel_type'],
            color=data['color'],
            image_url=data.get('image_url'),
            cylinder_count=data.get('cylinder_count'),
            engine_size=data.get('engine_size'),
            import_country=data.get('import_country'),
            body_type=data['body_type'],
            seating=data['seating'],
            drive_type=data['drive_type'],
            license_plate_type=data.get('license_plate_type'),
            city=data.get('city'),
            title_status=data['title_status'],
            damaged_parts=data.get('damaged_parts'),
            status='active',
        )
        db.session.add(car)
        db.session.commit()
        return jsonify({
            "id": car.id,
            "title": car.title,
            "brand": car.brand,
            "model": car.model,
            "trim": car.trim,
            "year": car.year,
            "price": car.price,
            "mileage": car.mileage,
            "condition": car.condition,
            "transmission": car.transmission,
            "fuel_type": car.fuel_type,
            "color": car.color,
            "image_url": car.image_url,
            "city": car.city,
            "status": car.status
        }), 201

# Route to get car by ID
@app.route('/cars/<int:car_id>', methods=['GET'])
def get_car_by_id(car_id):
    car = Car.query.get_or_404(car_id)
    return jsonify({
        "id": car.id,
        "title": car.title,
        "brand": car.brand,
        "model": car.model,
        "trim": car.trim,
        "year": car.year,
        "price": car.price,
        "mileage": car.mileage,
        "condition": car.condition,
        "transmission": car.transmission,
        "fuel_type": car.fuel_type,
        "color": car.color,
        "image_url": car.image_url,
        "city": car.city,
        "status": car.status
    })

@app.route('/cars/<int:car_id>', methods=['PUT'])
def update_car(car_id):
    car = Car.query.get_or_404(car_id)
    data = request.get_json()
    required_fields = [
        'title', 'brand', 'model', 'trim', 'year', 'mileage', 'condition',
        'transmission', 'fuel_type', 'color', 'body_type', 'seating', 'drive_type', 'title_status'
    ]
    missing = [f for f in required_fields if not data.get(f)]
    if missing:
        return jsonify({'error': f'Missing required fields: {", ".join(missing)}'}), 400
    car.title = data['title']
    car.brand = data['brand']
    car.model = data['model']
    car.trim = data['trim']
    car.year = data['year']
    car.price = data.get('price')
    car.mileage = data['mileage']
    car.condition = data['condition']
    car.transmission = data['transmission']
    car.fuel_type = data['fuel_type']
    car.color = data['color']
    car.image_url = data.get('image_url')
    car.cylinder_count = data.get('cylinder_count')
    car.engine_size = data.get('engine_size')
    car.import_country = data.get('import_country')
    car.body_type = data['body_type']
    car.seating = data['seating']
    car.drive_type = data['drive_type']
    car.license_plate_type = data.get('license_plate_type')
    car.city = data.get('city')
    car.title_status = data['title_status']
    car.damaged_parts = data.get('damaged_parts')
    db.session.commit()
    return jsonify({
        "id": car.id,
        "title": car.title,
        "brand": car.brand,
        "model": car.model,
        "trim": car.trim,
        "year": car.year,
        "price": car.price,
        "mileage": car.mileage,
        "condition": car.condition,
        "transmission": car.transmission,
        "fuel_type": car.fuel_type,
        "color": car.color,
        "image_url": car.image_url,
        "city": car.city,
        "status": car.status
    })

# GET /api/favorites - list of favorited cars for user
@app.route('/api/favorites', methods=['GET'])
def api_favorites():
    favorites = Favorite.query.filter_by(user_id=USER_ID).all()
    car_ids = [fav.car_id for fav in favorites]
    cars = Car.query.filter(Car.id.in_(car_ids)).all()
    result = []
    for car in cars:
        result.append({
            "id": car.id,
            "title": car.title,
            "brand": car.brand,
            "model": car.model,
            "trim": car.trim,
            "year": car.year,
            "price": car.price,
            "mileage": car.mileage,
            "condition": car.condition,
            "transmission": car.transmission,
            "fuel_type": car.fuel_type,
            "color": car.color,
            "image_url": car.image_url,
            "city": car.city,
            "status": car.status
        })
    return jsonify(result)

# POST /api/favorite/<car_id> - toggle favorite
@app.route('/api/favorite/<int:car_id>', methods=['POST'])
def api_toggle_favorite(car_id):
    fav = Favorite.query.filter_by(user_id=USER_ID, car_id=car_id).first()
    if fav:
        db.session.delete(fav)
        db.session.commit()
        return jsonify({'favorited': False})
    else:
        new_fav = Favorite(user_id=USER_ID, car_id=car_id)
        db.session.add(new_fav)
        db.session.commit()
        return jsonify({'favorited': True})

@app.route('/api/chats', methods=['GET'])
def api_chats():
    conversations = Conversation.query.filter((Conversation.buyer_id == USER_ID) | (Conversation.seller_id == USER_ID)).order_by(Conversation.updated_at.desc()).all()
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

@app.route('/api/chats/<int:conversation_id>/messages', methods=['GET'])
def api_chat_messages(conversation_id):
    messages = Message.query.filter_by(conversation_id=conversation_id).order_by(Message.created_at.asc()).all()
    result = []
    for msg in messages:
        result.append({
            'id': msg.id,
            'sender_id': msg.sender_id,
            'content': msg.content,
            'is_read': msg.is_read,
            'created_at': msg.created_at.isoformat(),
        })
    return jsonify(result)

@app.route('/api/chats/<int:conversation_id>/send', methods=['POST'])
def api_send_message(conversation_id):
    data = request.get_json()
    content = data.get('content')
    if not content:
        return jsonify({'error': 'Message content required'}), 400
    msg = Message(conversation_id=conversation_id, sender_id=USER_ID, content=content)
    db.session.add(msg)
    db.session.commit()
    return jsonify({'success': True, 'message_id': msg.id})

class Payment(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    payment_id = db.Column(db.String(100), unique=True, nullable=False)
    car_id = db.Column(db.Integer, nullable=True)
    user_id = db.Column(db.Integer, nullable=False)
    amount = db.Column(db.Float, nullable=False)
    currency = db.Column(db.String(3), default='USD')
    status = db.Column(db.String(20), default='pending')
    payment_method = db.Column(db.String(50), default='fib')
    payment_type = db.Column(db.String(20), default='listing_fee')
    transaction_reference = db.Column(db.String(100), nullable=True)
    created_at = db.Column(db.DateTime, nullable=False, default=datetime.utcnow)
    updated_at = db.Column(db.DateTime, nullable=False, default=datetime.utcnow)

@app.route('/api/payments', methods=['GET'])
def api_payments():
    payments = Payment.query.filter_by(user_id=USER_ID).order_by(Payment.created_at.desc()).all()
    result = []
    for p in payments:
        result.append({
            'id': p.id,
            'payment_id': p.payment_id,
            'car_id': p.car_id,
            'amount': p.amount,
            'currency': p.currency,
            'status': p.status,
            'payment_method': p.payment_method,
            'payment_type': p.payment_type,
            'transaction_reference': p.transaction_reference,
            'created_at': p.created_at.isoformat(),
            'updated_at': p.updated_at.isoformat(),
        })
    return jsonify(result)

@app.route('/api/payment/status/<payment_id>', methods=['GET'])
def api_payment_status(payment_id):
    p = Payment.query.filter_by(payment_id=payment_id).first_or_404()
    return jsonify({
        'id': p.id,
        'payment_id': p.payment_id,
        'car_id': p.car_id,
        'amount': p.amount,
        'currency': p.currency,
        'status': p.status,
        'payment_method': p.payment_method,
        'payment_type': p.payment_type,
        'transaction_reference': p.transaction_reference,
        'created_at': p.created_at.isoformat(),
        'updated_at': p.updated_at.isoformat(),
    })

@app.route('/api/payment/initiate', methods=['POST'])
def api_payment_initiate():
    data = request.get_json()
    amount = data.get('amount')
    car_id = data.get('car_id')
    if not amount or not car_id:
        return jsonify({'error': 'amount and car_id required'}), 400
    import uuid
    payment = Payment(
        payment_id=str(uuid.uuid4()),
        car_id=car_id,
        user_id=USER_ID,
        amount=amount,
        status='pending',
        payment_type='listing_fee',
    )
    db.session.add(payment)
    db.session.commit()
    return jsonify({'success': True, 'payment_id': payment.payment_id})

@app.route('/api/user', methods=['GET'])
def api_user():
    # Dummy user info for user_id=1
    return jsonify({
        'id': 1,
        'username': 'demo_user',
        'email': 'demo@example.com',
        'created_at': '2024-01-01T00:00:00',
    })

@app.route('/api/my_listings', methods=['GET'])
def api_my_listings():
    cars = Car.query.filter_by(user_id=USER_ID).order_by(Car.created_at.desc()).all()
    result = []
    for car in cars:
        result.append({
            "id": car.id,
            "title": car.title,
            "brand": car.brand,
            "model": car.model,
            "trim": car.trim,
            "year": car.year,
            "price": car.price,
            "mileage": car.mileage,
            "condition": car.condition,
            "transmission": car.transmission,
            "fuel_type": car.fuel_type,
            "color": car.color,
            "image_url": car.image_url,
            "city": car.city,
            "status": car.status
        })
    return jsonify(result)

if __name__ == '__main__':
    app.run(debug=True)
