#!/usr/bin/env python3
"""
Check cars.db for elian's original listings
"""

import sqlite3
import os

def check_cars_db():
    db_path = 'instance/cars.db'
    
    if not os.path.exists(db_path):
        print(f"❌ Database {db_path} does not exist")
        return
    
    try:
        conn = sqlite3.connect(db_path)
        cursor = conn.cursor()
        
        # Check tables
        cursor.execute("SELECT name FROM sqlite_master WHERE type='table'")
        tables = cursor.fetchall()
        print(f"📊 Tables in {db_path}: {[t[0] for t in tables]}")
        
        # Check if cars table exists
        if ('cars',) in tables:
            cursor.execute("SELECT COUNT(*) FROM cars")
            count = cursor.fetchone()[0]
            print(f"🚗 Total cars: {count}")
            
            # Check for elian's cars
            cursor.execute("SELECT * FROM cars WHERE user_id = 2 OR username = 'elian' LIMIT 10")
            elian_cars = cursor.fetchall()
            
            if elian_cars:
                print(f"✅ Found {len(elian_cars)} cars for elian:")
                for car in elian_cars:
                    print(f"  {car}")
            else:
                print("❌ No cars found for elian in cars.db")
                
        conn.close()
        
    except Exception as e:
        print(f"❌ Error checking {db_path}: {e}")

if __name__ == '__main__':
    check_cars_db()
