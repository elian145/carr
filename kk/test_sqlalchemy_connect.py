from sqlalchemy import create_engine, text
import os

db_path = os.path.join('instance', 'cars.db')
engine = create_engine(f'sqlite:///{db_path}')

try:
    with engine.connect() as conn:
        result = conn.execute(text("SELECT name FROM sqlite_master WHERE type='table';"))
        print("Tables:", [row[0] for row in result])
        print("Connection successful!")
except Exception as e:
    print("Connection failed:", e) 