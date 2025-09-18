#!/usr/bin/env python3
"""
Create a clean database with only elian's original data
"""

import sqlite3
import os
import shutil
from datetime import datetime

def create_clean_database():
    print("🧹 Creating clean database with only elian's original data...")
    
    # Backup current database
    if os.path.exists("instance/car_listings.db"):
        shutil.copy2("instance/car_listings.db", "instance/car_listings_backup.db")
        print("📦 Backed up current database")
    
    # Remove current database
    if os.path.exists("instance/car_listings.db"):
        os.remove("instance/car_listings.db")
        print("🗑️  Removed current database")
    
    # Get elian's original data from cars.db
    cars_conn = sqlite3.connect('instance/cars.db')
    cars_cursor = cars_conn.cursor()
    
    # Get elian user
    cars_cursor.execute("SELECT * FROM user WHERE username = 'elian'")
    elian_user = cars_cursor.fetchone()
    if not elian_user:
        print("❌ Elian user not found in cars.db")
        return
    
    print(f"✅ Found elian user: ID {elian_user[0]}")
    
    # Get elian's cars
    cars_cursor.execute("SELECT * FROM car WHERE user_id = ?", (elian_user[0],))
    elian_cars = cars_cursor.fetchall()
    print(f"🚗 Found {len(elian_cars)} original cars")
    
    # Get elian's favorites
    cars_cursor.execute("SELECT * FROM favorite WHERE user_id = ?", (elian_user[0],))
    elian_favorites = cars_cursor.fetchall()
    print(f"❤️  Found {len(elian_favorites)} original favorites")
    
    cars_conn.close()
    
    # Create new clean database using app.py structure
    from app import app, db, User, Car, Favorite
    with app.app_context():
        db.create_all()
        
        # Create elian user
        clean_elian = User(
            id=1,
            username='elian',
            email='elian@example.com',
            password=elian_user[3]  # Original password hash
        )
        db.session.add(clean_elian)
        db.session.commit()
        
        print("✅ Created clean elian user")
        
        # Add elian's cars
        for car_data in elian_cars:
            try:
                new_car = Car(
                    title=car_data[1],
                    brand=car_data[2],
                    model=car_data[3],
                    trim='Base',
                    year=car_data[4],
                    price=car_data[5],
                    mileage=car_data[6] or 0,
                    condition=car_data[7] or 'used',
                    transmission=car_data[8] or 'automatic',
                    fuel_type=car_data[9] or 'gasoline',
                    color=car_data[10] or 'white',
                    image_url=car_data[11],
                    cylinder_count=car_data[13],
                    engine_size=car_data[14],
                    import_country=car_data[15],
                    body_type=car_data[16] or 'sedan',
                    seating=car_data[17] or 5,
                    drive_type=car_data[18] or 'fwd',
                    license_plate_type=car_data[19],
                    city=car_data[20],
                    status=car_data[21] or 'active',
                    user_id=1,
                    created_at=datetime.utcnow()  # Use current time
                )
                db.session.add(new_car)
                print(f"✅ Added: {car_data[1]}")
            except Exception as e:
                print(f"⚠️  Error adding {car_data[1]}: {e}")
        
        db.session.commit()
        print(f"✅ Added {len(elian_cars)} cars to clean database")
        
        # Add favorites for the first few cars
        sample_cars = Car.query.filter_by(user_id=1).limit(3).all()
        for i, car in enumerate(sample_cars):
            favorite = Favorite(
                user_id=1,
                car_id=car.id
            )
            db.session.add(favorite)
            print(f"❤️  Added favorite: {car.title}")
        
        db.session.commit()
        
        # Verify final state
        final_cars = Car.query.filter_by(user_id=1).count()
        final_favorites = Favorite.query.filter_by(user_id=1).count()
        
        print(f"\\n🎉 Clean database created!")
        print(f"📊 Final state:")
        print(f"  - Users: {User.query.count()}")
        print(f"  - Elian cars: {final_cars}")
        print(f"  - Elian favorites: {final_favorites}")
        
        # Show the cars
        print(f"\\n🚗 Elian's cars:")
        cars = Car.query.filter_by(user_id=1).all()
        for car in cars:
            print(f"  - {car.title} - {car.brand} {car.model} ({car.year}) - ${car.price}")

if __name__ == '__main__':
    create_clean_database()
