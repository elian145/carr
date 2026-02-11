from app_new import db, User, app

with app.app_context():
    user = User.query.filter_by(email='elianyaqoob1005@gmail.com').first()
    if user:
        print(f"User found: {user.username}")
        print(f"Email: {user.email}")
        print(f"Password hash exists: {bool(user.password_hash)}")
    else:
        print("User not found, searching by username...")
        user = User.query.filter_by(username='eliantest').first()
        if user:
            print(f"User found by username: {user.username}")
            print(f"Email: {user.email}")
        else:
            print("No user found")

