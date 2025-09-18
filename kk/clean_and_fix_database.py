#!/usr/bin/env python3
"""
Clean up the database confusion and restore only elian's original data
"""

import sqlite3
import os
import shutil
from datetime import datetime

def clean_and_fix_database():
    print("🧹 Cleaning up database confusion...")
    
    # Backup current databases
    backup_dir = "instance/backup_" + datetime.now().strftime("%Y%m%d_%H%M%S")
    os.makedirs(backup_dir, exist_ok=True)
    
    print(f"📦 Creating backup in {backup_dir}")
    shutil.copy2("instance/cars.db", f"{backup_dir}/cars.db")
    shutil.copy2("instance/car_listings.db", f"{backup_dir}/car_listings.db")
    shutil.copy2("instance/car_listings_dev.db", f"{backup_dir}/car_listings_dev.db")
    
    # Connect to cars.db (original data)
    cars_conn = sqlite3.connect('instance/cars.db')
    cars_cursor = cars_conn.cursor()
    
    # Get elian's original data
    print("📋 Extracting elian's original data...")
    
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
    print(f"🚗 Found {len(elian_cars)} original cars for elian")
    
    # Get elian's favorites
    cars_cursor.execute("SELECT * FROM favorite WHERE user_id = ?", (elian_user[0],))
    elian_favorites = cars_cursor.fetchall()
    print(f"❤️  Found {len(elian_favorites)} original favorites for elian")
    
    cars_conn.close()
    
    # Create clean database
    print("🗑️  Creating clean database...")
    if os.path.exists("instance/car_listings.db"):
        os.remove("instance/car_listings.db")
    
    # Initialize clean database using api.py structure
    from api import app, db, User, Car, Favorite
    with app.app_context():
        db.create_all()
        
        # Create elian user
        clean_elian = User(
            id=1,  # Start with ID 1
            username='elian',
            email='elian@example.com',
            password=elian_user[3]  # Use original password hash
        )
        db.session.add(clean_elian)
        db.session.commit()
        
        print("✅ Created clean elian user")
        
        # Add elian's cars
        for car_data in elian_cars:
            new_car = Car(
                title=car_data[1],
                brand=car_data[2],
                model=car_data[3],
                trim='Base',  # Default trim
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
                user_id=1,  # elian's new ID
                created_at=datetime.fromisoformat(car_data[12]) if car_data[12] and isinstance(car_data[12], str) and 'T' in str(car_data[12]) else datetime.utcnow()
            )
            db.session.add(new_car)
        
        db.session.commit()
        print(f"✅ Added {len(elian_cars)} cars to clean database")
        
        # Add elian's favorites (need to map old car IDs to new ones)
        # For now, just add a few sample favorites
        sample_cars = Car.query.filter_by(user_id=1).limit(3).all()
        for i, car in enumerate(sample_cars):
            if i < len(elian_favorites):
                new_fav = Favorite(
                    user_id=1,
                    car_id=car.id
                )
                db.session.add(new_fav)
        
        db.session.commit()
        print(f"✅ Added {min(len(elian_favorites), len(sample_cars))} favorites to clean database")
        
        # Verify final state
        final_cars = Car.query.filter_by(user_id=1).count()
        final_favorites = Favorite.query.filter_by(user_id=1).count()
        
        print(f"\\n🎉 Clean database created!")
        print(f"📊 Final state:")
        print(f"  - Elian user: ID 1")
        print(f"  - Cars: {final_cars}")
        print(f"  - Favorites: {final_favorites}")
        
        # Show the cars
        print(f"\\n🚗 Elian's cars:")
        cars = Car.query.filter_by(user_id=1).all()
        for car in cars:
            print(f"  - {car.title} - {car.brand} {car.model} ({car.year}) - ${car.price}")

if __name__ == '__main__':
    clean_and_fix_database()
