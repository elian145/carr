#!/usr/bin/env python3
"""
Check for elian's favorites in cars.db
"""

import sqlite3

def check_favorites():
    try:
        conn = sqlite3.connect('instance/cars.db')
        cursor = conn.cursor()
        
        # Check favorites for elian
        cursor.execute('SELECT COUNT(*) FROM favorite WHERE user_id = 2')
        fav_count = cursor.fetchone()[0]
        print(f'📌 Favorites in cars.db: {fav_count}')
        
        if fav_count > 0:
            cursor.execute('SELECT car_id FROM favorite WHERE user_id = 2')
            fav_cars = cursor.fetchall()
            print('Favorite car IDs:', [f[0] for f in fav_cars])
        else:
            print('No favorites found for elian')
            
        conn.close()
        
    except Exception as e:
        print(f'❌ Error: {e}')

if __name__ == '__main__':
    check_favorites()
