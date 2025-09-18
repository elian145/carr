#!/usr/bin/env python3
"""
Restore elian's favorites from cars.db to main database
"""

import sqlite3
from app import app, db, Favorite, User

def restore_favorites():
    with app.app_context():
        try:
            # Connect to cars.db
            cars_conn = sqlite3.connect('instance/cars.db')
            cars_cursor = cars_conn.cursor()
            
            # Get elian's favorites from cars.db
            cars_cursor.execute("SELECT car_id FROM favorite WHERE user_id = 2")
            favorite_car_ids = [row[0] for row in cars_cursor.fetchall()]
            
            print(f"📌 Found {len(favorite_car_ids)} favorites for elian: {favorite_car_ids}")
            
            if not favorite_car_ids:
                print("❌ No favorites found")
                return
            
            # Get elian user from main database
            elian_user = User.query.filter_by(username='elian').first()
            if not elian_user:
                print("❌ Elian user not found in main database")
                return
            
            print(f"✅ Found elian user: ID {elian_user.id}")
            
            # Restore favorites
            restored_count = 0
            for car_id in favorite_car_ids:
                # Check if favorite already exists
                existing_fav = Favorite.query.filter_by(
                    user_id=elian_user.id, 
                    car_id=car_id
                ).first()
                
                if existing_fav:
                    print(f"⚠️  Favorite already exists for car ID {car_id}")
                    continue
                
                # Create new favorite
                new_favorite = Favorite(
                    user_id=elian_user.id,
                    car_id=car_id
                )
                
                db.session.add(new_favorite)
                restored_count += 1
                print(f"✅ Restored favorite for car ID {car_id}")
            
            db.session.commit()
            cars_conn.close()
            
            print(f"\\n🎉 Successfully restored {restored_count} favorites!")
            
            # Verify restoration
            elian_favorites_count = Favorite.query.filter_by(user_id=elian_user.id).count()
            print(f"📈 Elian now has {elian_favorites_count} total favorites")
            
        except Exception as e:
            print(f"❌ Error: {e}")
            db.session.rollback()
            import traceback
            traceback.print_exc()

if __name__ == '__main__':
    restore_favorites()
