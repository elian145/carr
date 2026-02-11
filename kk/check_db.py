import sqlite3

conn = sqlite3.connect('instance/car_listings_dev.db')
cursor = conn.cursor()
cursor.execute('PRAGMA table_info(user)')
for row in cursor.fetchall():
    print(row)

