#!/usr/bin/env python3
"""
Clean up the current database to only have elian's original data
"""

from app import app, db, Car, User, Favorite
from datetime import datetime

def clean_current_database():
    with app.app_context():
        try:
            print("🧹 Cleaning current database...")
            
            # Get elian user
            elian_user = User.query.filter_by(username='elian').first()
            if not elian_user:
                print("❌ Elian user not found")
                return
            
            print(f"✅ Found elian user: ID {elian_user.id}")
            
            # Get elian's original cars (the ones we transferred)
            elian_cars = Car.query.filter_by(user_id=elian_user.id).all()
            print(f"📊 Current elian cars: {len(elian_cars)}")
            
            # Show current cars
            print("\\nCurrent elian cars:")
            for car in elian_cars:
                print(f"  ID: {car.id}, {car.title} - {car.brand} {car.model} ({car.year}) - ${car.price}")
            
            # Remove all test/transferred cars, keep only original ones
            # Original cars have specific titles and years
            original_titles = [
                "Toyota Camry XLE",
                "Toyota Corolla SE", 
                "Toyota Camry SE"
            ]
            
            cars_to_keep = []
            cars_to_remove = []
            
            for car in elian_cars:
                if car.title in original_titles:
                    cars_to_keep.append(car)
                    print(f"✅ Keeping: {car.title}")
                else:
                    cars_to_remove.append(car)
                    print(f"🗑️  Removing: {car.title}")
            
            # Remove non-original cars
            for car in cars_to_remove:
                db.session.delete(car)
            
            # Clear all favorites and recreate with original cars
            Favorite.query.filter_by(user_id=elian_user.id).delete()
            
            # Add favorites for original cars
            for i, car in enumerate(cars_to_keep):
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
            
            print(f"\\n🎉 Database cleaned!")
            print(f"📊 Final state:")
            print(f"  - Elian cars: {final_cars}")
            print(f"  - Elian favorites: {final_favorites}")
            
            # Show final cars
            print(f"\\n🚗 Elian's final cars:")
            final_cars_list = Car.query.filter_by(user_id=elian_user.id).all()
            for car in final_cars_list:
                print(f"  - {car.title} - {car.brand} {car.model} ({car.year}) - ${car.price}")
                
        except Exception as e:
            print(f"❌ Error: {e}")
            db.session.rollback()
            import traceback
            traceback.print_exc()

if __name__ == '__main__':
    clean_current_database()
