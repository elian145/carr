import sqlite3
import os
from app import app, db, Car

# Path to the instance database
db_path = os.path.join('instance', 'cars.db')

if os.path.exists(db_path):
    print(f"Database found at: {db_path}")
    print(f"File size: {os.path.getsize(db_path)} bytes")
    
    # Connect to the database
    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()
    
    # Check what tables exist
    cursor.execute("SELECT name FROM sqlite_master WHERE type='table';")
    tables = cursor.fetchall()
    print(f"\nTables in database: {[table[0] for table in tables]}")
    
    # Check car table
    if ('car',) in tables:
        cursor.execute("SELECT COUNT(*) FROM car")
        count = cursor.fetchone()[0]
        print(f"\nTotal cars in database: {count}")
        
        if count > 0:
            cursor.execute("SELECT id, title, brand FROM car")
            cars = cursor.fetchall()
            print("\nCars in database:")
            for car in cars:
                print(f"- ID: {car[0]}, Title: {car[1]}, Brand: '{car[2]}'")
    
    conn.close()
else:
    print(f"Database not found at: {db_path}")
    print("Available files in instance folder:")
    if os.path.exists('instance'):
        for file in os.listdir('instance'):
            print(f"- {file}")

with app.app_context():
    # Set all cars to active
    updated = Car.query.update({Car.status: 'active'})
    db.session.commit()
    print(f"Set {updated} cars to 'active'.")
    cars = Car.query.all()
    if not cars:
        print('No cars found in the database.')
    else:
        for car in cars:
            print(f'ID: {car.id}, Title: {car.title}, Status: {car.status}') 