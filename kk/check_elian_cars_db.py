#!/usr/bin/env python3
"""
Check cars.db for elian's original listings
"""

import sqlite3
import os

def check_elian_cars_db():
    db_path = 'instance/cars.db'
    
    if not os.path.exists(db_path):
        print(f"❌ Database {db_path} does not exist")
        return
    
    try:
        conn = sqlite3.connect(db_path)
        cursor = conn.cursor()
        
        # Check users
        cursor.execute("SELECT * FROM user WHERE username = 'elian'")
        elian_user = cursor.fetchone()
        
        if elian_user:
            print(f"✅ Found elian user: {elian_user}")
            user_id = elian_user[0]
            
            # Check cars for elian
            cursor.execute("SELECT COUNT(*) FROM car WHERE user_id = ?", (user_id,))
            count = cursor.fetchone()[0]
            print(f"🚗 Elian has {count} cars in cars.db")
            
            if count > 0:
                cursor.execute("SELECT id, title, brand, model, year, price, created_at FROM car WHERE user_id = ? ORDER BY created_at DESC LIMIT 10", (user_id,))
                cars = cursor.fetchall()
                print("\\n📋 Elian's cars:")
                for car in cars:
                    print(f"  ID: {car[0]}, {car[1]} - {car[2]} {car[3]} ({car[4]}) - ${car[5]} - {car[6]}")
        else:
            print("❌ Elian user not found in cars.db")
            
            # Check all users
            cursor.execute("SELECT id, username, email FROM user")
            users = cursor.fetchall()
            print("\\n👥 All users in cars.db:")
            for user in users:
                print(f"  ID: {user[0]}, Username: {user[1]}, Email: {user[2]}")
                
        conn.close()
        
    except Exception as e:
        print(f"❌ Error checking {db_path}: {e}")
        import traceback
        traceback.print_exc()

if __name__ == '__main__':
    check_elian_cars_db()
