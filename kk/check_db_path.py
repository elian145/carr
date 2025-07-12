import os

db_path = os.path.join('instance', 'cars.db')
abs_path = os.path.abspath(db_path)
print(f"Relative path: {db_path}")
print(f"Absolute path: {abs_path}")
print(f"Exists: {os.path.exists(db_path)}")
if os.path.exists(db_path):
    print(f"File size: {os.path.getsize(db_path)} bytes")
else:
    print("File does not exist or is not accessible.") 