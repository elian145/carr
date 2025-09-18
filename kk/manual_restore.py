#!/usr/bin/env python3
"""
Manually restore elian's original data with correct field mapping
"""

from app import app, db, Car, User, Favorite
from datetime import datetime

def manual_restore():
    with app.app_context():
        try:
            print("🔄 Manually restoring elian's original data...")
            
            # Get elian user
            elian_user = User.query.filter_by(username='elian').first()
            if not elian_user:
                print("❌ Elian user not found")
                return
            
            print(f"✅ Found elian user: ID {elian_user.id}")
            
            # Clear existing data
            Car.query.filter_by(user_id=elian_user.id).delete()
            Favorite.query.filter_by(user_id=elian_user.id).delete()
            print("🗑️  Cleared existing data")
            
            # Add elian's original cars manually
            cars_data = [
                {
                    'title': 'Toyota Camry XLE',
                    'brand': 'toyota',
                    'model': 'Camry',
                    'year': 2022,
                    'price': 1000.0,
                    'mileage': 1000,
                    'condition': 'certified',
                    'transmission': 'semi-automatic',
                    'fuel_type': 'hybrid',
                    'color': 'brown',
                    'image_url': 'car_photos/20250907_234443_scaled_94.jpg',
                    'city': 'mosul'
                },
                {
                    'title': 'Toyota Corolla SE',
                    'brand': 'toyota',
                    'model': 'Corolla',
                    'year': 2022,
                    'price': 16000.0,
                    'mileage': 11000,
                    'condition': 'used',
                    'transmission': 'automatic',
                    'fuel_type': 'gasoline',
                    'color': 'white',
                    'image_url': '',
                    'city': 'baghdad'
                },
                {
                    'title': 'Toyota Camry SE',
                    'brand': 'toyota',
                    'model': 'Camry',
                    'year': 2023,
                    'price': 1000.0,
                    'mileage': 1000,
                    'condition': 'certified',
                    'transmission': 'semi-automatic',
                    'fuel_type': 'hybrid',
                    'color': 'brown',
                    'image_url': 'car_photos/20250911_114608_scaled_94.jpg',
                    'city': 'mosul'
                }
            ]
            
            # Add cars
            for car_data in cars_data:
                new_car = Car(
                    title=car_data['title'],
                    brand=car_data['brand'],
                    model=car_data['model'],
                    trim='Base',
                    year=car_data['year'],
                    price=car_data['price'],
                    mileage=car_data['mileage'],
                    condition=car_data['condition'],
                    transmission=car_data['transmission'],
                    fuel_type=car_data['fuel_type'],
                    color=car_data['color'],
                    image_url=car_data['image_url'],
                    city=car_data['city'],
                    status='active',
                    user_id=elian_user.id,
                    created_at=datetime.utcnow()
                )
                db.session.add(new_car)
                print(f"✅ Added: {car_data['title']}")
            
            db.session.commit()
            print(f"✅ Added {len(cars_data)} cars to database")
            
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
    manual_restore()
