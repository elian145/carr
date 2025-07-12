import sqlite3
import os
from datetime import datetime

# Path to the instance database
db_path = os.path.join('instance', 'cars.db')

# Test car data
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
    }
]

# Connect to the database
conn = sqlite3.connect(db_path)
cursor = conn.cursor()

# Clear existing cars
cursor.execute("DELETE FROM car")
print("Cleared existing cars")

# Add test cars
for car_data in test_cars:
    cursor.execute("""
        INSERT INTO car (
            title, brand, model, trim, price, year, mileage, transmission, 
            fuel_type, color, body_type, seating, drive_type, title_status, 
            condition, city, created_at, user_id
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    """, (
        car_data['title'], car_data['brand'], car_data['model'], car_data['trim'],
        car_data['price'], car_data['year'], car_data['mileage'], car_data['transmission'],
        car_data['fuel_type'], car_data['color'], car_data['body_type'], car_data['seating'],
        car_data['drive_type'], car_data['title_status'], car_data['condition'], car_data['city'],
        datetime.now(), 1
    ))

conn.commit()
print(f"Added {len(test_cars)} test cars")

# Verify the data
cursor.execute("SELECT id, title, brand FROM car")
cars = cursor.fetchall()
print(f"\nTotal cars in database: {len(cars)}")
for car in cars:
    print(f"- ID: {car[0]}, Title: {car[1]}, Brand: '{car[2]}'")

conn.close()
print("\nDatabase updated successfully!") 