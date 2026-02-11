from app_new import db, User, app
import os

with app.app_context():
    user = User.query.filter_by(email='elianyaqoob1005@gmail.com').first()
    if user:
        raw = (os.environ.get('TEST_PASSWORDS') or '').strip()
        candidates = [p for p in (s.strip() for s in raw.split(',')) if p] if raw else []
        for p in candidates:
            print(f"Testing password '{p}': {user.check_password(p)}")
        print(f"Username: {user.username}")
        print(f"To dict output:")
        print(user.to_dict())

