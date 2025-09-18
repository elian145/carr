#!/usr/bin/env python3
"""
Simple cleanup - remove all non-elian cars and keep only original data
"""

import sqlite3

def simple_cleanup():
    print("🧹 Simple cleanup - keeping only elian's original data...")
    
    # Connect to current database
    conn = sqlite3.connect('instance/car_listings.db')
    cursor = conn.cursor()
    
    # Get current state
    cursor.execute("SELECT COUNT(*) FROM car")
    total_cars = cursor.fetchone()[0]
    print(f"📊 Current total cars: {total_cars}")
    
    # Get elian's user ID
    cursor.execute("SELECT id FROM user WHERE username = 'elian'")
    elian_id = cursor.fetchone()
    if not elian_id:
        print("❌ Elian user not found")
        return
    
    elian_id = elian_id[0]
    print(f"✅ Elian user ID: {elian_id}")
    
    # Get elian's cars
    cursor.execute("SELECT id, title, brand, model, year FROM car WHERE user_id = ?", (elian_id,))
    elian_cars = cursor.fetchall()
    print(f"🚗 Elian's current cars: {len(elian_cars)}")
    
    # Show current cars
    for car in elian_cars:
        print(f"  - ID {car[0]}: {car[1]} - {car[2]} {car[3]} ({car[4]})")
    
    # Keep only original Toyota cars
    original_cars = [
        "Toyota Camry XLE",
        "Toyota Corolla SE", 
        "Toyota Camry SE"
    ]
    
    # Find cars to keep
    cars_to_keep = []
    for car in elian_cars:
        if car[1] in original_cars:
            cars_to_keep.append(car[0])
            print(f"✅ Keeping: {car[1]}")
        else:
            print(f"🗑️  Will remove: {car[1]}")
    
    # Remove non-original cars
    if len(cars_to_keep) < len(elian_cars):
        placeholders = ','.join(['?' for _ in cars_to_keep])
        cursor.execute(f"DELETE FROM car WHERE user_id = ? AND id NOT IN ({placeholders})", 
                      [elian_id] + cars_to_keep)
        removed_count = cursor.rowcount
        print(f"🗑️  Removed {removed_count} non-original cars")
    
    # Clear and recreate favorites
    cursor.execute("DELETE FROM favorite WHERE user_id = ?", (elian_id,))
    print("🗑️  Cleared existing favorites")
    
    # Add favorites for original cars
    for car_id in cars_to_keep:
        cursor.execute("INSERT INTO favorite (user_id, car_id) VALUES (?, ?)", (elian_id, car_id))
        print(f"❤️  Added favorite for car ID {car_id}")
    
    conn.commit()
    
    # Verify final state
    cursor.execute("SELECT COUNT(*) FROM car WHERE user_id = ?", (elian_id,))
    final_cars = cursor.fetchone()[0]
    
    cursor.execute("SELECT COUNT(*) FROM favorite WHERE user_id = ?", (elian_id,))
    final_favorites = cursor.fetchone()[0]
    
    print(f"\\n🎉 Cleanup complete!")
    print(f"📊 Final state:")
    print(f"  - Elian cars: {final_cars}")
    print(f"  - Elian favorites: {final_favorites}")
    
    # Show final cars
    cursor.execute("SELECT title, brand, model, year, price FROM car WHERE user_id = ?", (elian_id,))
    final_cars_list = cursor.fetchall()
    print(f"\\n🚗 Elian's final cars:")
    for car in final_cars_list:
        print(f"  - {car[0]} - {car[1]} {car[2]} ({car[3]}) - ${car[4]}")
    
    conn.close()

if __name__ == '__main__':
    simple_cleanup()
