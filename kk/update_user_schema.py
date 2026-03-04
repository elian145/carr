#!/usr/bin/env python3
"""
Script to update the User table schema to include new fields.
This adds the missing columns: first_name, last_name, phone_number, profile_picture
"""

import os
import sqlite3
from datetime import datetime

# Database path
DB_PATH = os.path.join(os.path.dirname(__file__), 'instance', 'cars.db')

def update_user_schema():
    """Add new columns to the User table if they don't exist"""
    try:
        # Connect to the database
        conn = sqlite3.connect(DB_PATH)
        cursor = conn.cursor()
        
        # Check if columns exist and add them if they don't
        cursor.execute("PRAGMA table_info(user)")
        columns = [column[1] for column in cursor.fetchall()]
        
        new_columns = [
            ('first_name', 'VARCHAR(80)'),
            ('last_name', 'VARCHAR(80)'),
            ('phone_number', 'VARCHAR(20)'),
            ('profile_picture', 'VARCHAR(200)')
        ]
        
        for column_name, column_type in new_columns:
            if column_name not in columns:
                print(f"Adding column: {column_name}")
                cursor.execute(f"ALTER TABLE user ADD COLUMN {column_name} {column_type}")
            else:
                print(f"Column {column_name} already exists")
        
        # Commit changes
        conn.commit()
        print("Database schema updated successfully!")
        
        # Verify the changes
        cursor.execute("PRAGMA table_info(user)")
        columns = cursor.fetchall()
        print("\nCurrent User table schema:")
        for column in columns:
            print(f"  {column[1]} {column[2]}")
            
    except Exception as e:
        print(f"Error updating database schema: {e}")
        return False
    finally:
        if conn:
            conn.close()
    
    return True

if __name__ == "__main__":
    print("Updating User table schema...")
    success = update_user_schema()
    if success:
        print("Schema update completed successfully!")
    else:
        print("Schema update failed!")
