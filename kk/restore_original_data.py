#!/usr/bin/env python3
"""
Restore elian's original data from cars.db to the current database
"""

import sqlite3
from app import app, db, Car, User, Favorite
from datetime import datetime

def restore_original_data():
    with app.app_context():
        try:
            print("🔄 Restoring elian's original data...")
            
            # Get elian user
            elian_user = User.query.filter_by(username='elian').first()
            if not elian_user:
                print("❌ Elian user not found")
                return
            
            print(f"✅ Found elian user: ID {elian_user.id}")
            
            # Get original data from cars.db
            cars_conn = sqlite3.connect('instance/cars.db')
            cars_cursor = cars_conn.cursor()
            
            # Get elian's original cars
            cars_cursor.execute("SELECT * FROM car WHERE user_id = 2")
            original_cars = cars_cursor.fetchall()
            print(f"📋 Found {len(original_cars)} original cars in cars.db")
            
            # Get elian's original favorites
            cars_cursor.execute("SELECT car_id FROM favorite WHERE user_id = 2")
            original_favorites = [row[0] for row in cars_cursor.fetchall()]
            print(f"❤️  Found {len(original_favorites)} original favorites in cars.db")
            
            cars_conn.close()
            
            # Add original cars
            for car_data in original_cars:
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
                        user_id=elian_user.id,
                        created_at=datetime.utcnow()
                    )
                    db.session.add(new_car)
                    print(f"✅ Added: {car_data[1]}")
                except Exception as e:
                    print(f"⚠️  Error adding {car_data[1]}: {e}")
            
            db.session.commit()
            print(f"✅ Added {len(original_cars)} cars to database")
            
            # Add favorites for the cars
            elian_cars = Car.query.filter_by(user_id=elian_user.id).all()
            for i, car in enumerate(elian_cars):
                if i < 3:  # Add up to 3 favorites
                    favorite = Favorite(
                        user_id=elian_user.id,
                        car_id=car.id
                    )
                    db.session.add(favorite)
                    print(f"❤️  Added favorite: {car.title}")
            
            db.session.commit()
            
            # Verify final state
            final_cars = Car.query.filter_by(user_id=elian_user.id).count()
            final_favorites = Favorite.query.filter_by(user_id=elian_user.id).count()
            
            print(f"\\n🎉 Data restored successfully!")
            print(f"📊 Final state:")
            print(f"  - Elian cars: {final_cars}")
            print(f"  - Elian favorites: {final_favorites}")
            
            # Show the cars
            print(f"\\n🚗 Elian's cars:")
            cars = Car.query.filter_by(user_id=elian_user.id).all()
            for car in cars:
                print(f"  - {car.title} - {car.brand} {car.model} ({car.year}) - ${car.price}")
                
        except Exception as e:
            print(f"❌ Error: {e}")
            db.session.rollback()
            import traceback
            traceback.print_exc()

if __name__ == '__main__':
    restore_original_data()
