from app import app, db, Car, CarImage
from datetime import datetime

with app.app_context():
    # Clear existing data
    Car.query.delete()
    db.session.commit()
    
    # Add test cars
    test_cars = [
        {
            'title': 'BMW 850i',
            'brand': 'bmw',
            'model': '850i',
            'trim': 'Sport',
            'price': 45000.0,
            'year': 2020,
            'mileage': 50000,
            'transmission': 'automatic',
            'fuel_type': 'gasoline',
            'color': 'black',
            'body_type': 'coupe',
            'seating': 4,
            'drive_type': 'rwd',
            'title_status': 'clean',
            'condition': 'used',
            'city': 'baghdad'
        },
        {
            'title': 'Toyota Camry',
            'brand': 'toyota',
            'model': 'camry',
            'trim': 'LE',
            'price': 25000.0,
            'year': 2021,
            'mileage': 30000,
            'transmission': 'automatic',
            'fuel_type': 'gasoline',
            'color': 'white',
            'body_type': 'sedan',
            'seating': 5,
            'drive_type': 'fwd',
            'title_status': 'clean',
            'condition': 'used',
            'city': 'erbil'
        },
        {
            'title': 'Mercedes-Benz S-Class',
            'brand': 'mercedes-benz',
            'model': 's-class',
            'trim': 'AMG',
            'price': 120000.0,
            'year': 2022,
            'mileage': 15000,
            'transmission': 'automatic',
            'fuel_type': 'gasoline',
            'color': 'silver',
            'body_type': 'sedan',
            'seating': 5,
            'drive_type': 'awd',
            'title_status': 'clean',
            'condition': 'used',
            'city': 'basra'
        }
    ]
    
    for car_data in test_cars:
        car = Car(
            title=car_data['title'],
            brand=car_data['brand'],
            model=car_data['model'],
            trim=car_data['trim'],
            price=car_data['price'],
            year=car_data['year'],
            mileage=car_data['mileage'],
            transmission=car_data['transmission'],
            fuel_type=car_data['fuel_type'],
            color=car_data['color'],
            body_type=car_data['body_type'],
            seating=car_data['seating'],
            drive_type=car_data['drive_type'],
            title_status=car_data['title_status'],
            condition=car_data['condition'],
            city=car_data['city'],
            user_id=1
        )
        db.session.add(car)
    
    db.session.commit()
    print("Test data added successfully!")
    
    # Verify the data
    cars = Car.query.all()
    print(f"Total cars in database: {len(cars)}")
    for car in cars:
        print(f"- {car.title} (Brand: {car.brand}, Price: ${car.price})") 