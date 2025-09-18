#!/usr/bin/env python3
"""
Transfer elian's original cars from cars.db to the main database
"""

import sqlite3
from app import app, db, Car, User
from datetime import datetime

def transfer_original_cars():
    with app.app_context():
        try:
            # Connect to cars.db
            cars_conn = sqlite3.connect('instance/cars.db')
            cars_cursor = cars_conn.cursor()
            
            # Get elian's cars from cars.db
            cars_cursor.execute("""
                SELECT id, title, brand, model, year, price, mileage, condition, 
                       transmission, fuel_type, color, image_url, created_at, 
                       cylinder_count, engine_size, import_country, body_type, 
                       seating, drive_type, license_plate_type, city, status
                FROM car WHERE user_id = 2
            """)
            original_cars = cars_cursor.fetchall()
            
            print(f"📊 Found {len(original_cars)} original cars for elian")
            
            if not original_cars:
                print("❌ No original cars found")
                return
            
            # Get elian user from main database
            elian_user = User.query.filter_by(username='elian').first()
            if not elian_user:
                print("❌ Elian user not found in main database")
                return
            
            print(f"✅ Found elian user: ID {elian_user.id}")
            
            # Transfer each car
            transferred_count = 0
            for car_data in original_cars:
                # Check if car already exists (by title and year)
                existing_car = Car.query.filter_by(
                    title=car_data[1], 
                    year=car_data[3], 
                    user_id=elian_user.id
                ).first()
                
                if existing_car:
                    print(f"⚠️  Car already exists: {car_data[1]} ({car_data[3]})")
                    continue
                
                # Create new car in main database
                new_car = Car(
                    title=car_data[1],
                    brand=car_data[2],
                    model=car_data[3],
                    trim='Base',  # Default trim value
                    year=car_data[4],  # Fixed: year is at index 4
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
                    user_id=elian_user.id,
                    created_at=datetime.fromisoformat(car_data[12].replace('Z', '+00:00')) if car_data[12] else datetime.utcnow()
                )
                
                db.session.add(new_car)
                transferred_count += 1
                print(f"✅ Transferred: {car_data[1]} - {car_data[2]} {car_data[3]} ({car_data[3]})")
            
            db.session.commit()
            cars_conn.close()
            
            print(f"\\n🎉 Successfully transferred {transferred_count} original cars!")
            
            # Verify transfer
            elian_cars_count = Car.query.filter_by(user_id=elian_user.id).count()
            print(f"📈 Elian now has {elian_cars_count} total cars")
            
        except Exception as e:
            print(f"❌ Error: {e}")
            db.session.rollback()
            import traceback
            traceback.print_exc()

if __name__ == '__main__':
    transfer_original_cars()
