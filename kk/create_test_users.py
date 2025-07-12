from app import app, db, User
from werkzeug.security import generate_password_hash

def create_test_users():
    """Create test users for payment integration testing"""
    with app.app_context():
        # Check if users already exist
        existing_users = User.query.all()
        if len(existing_users) >= 2:
            print(f"Found {len(existing_users)} existing users")
            for user in existing_users:
                print(f"  - {user.username} ({user.email})")
            return
        
        # Create test users
        test_users = [
            {
                'username': 'buyer_test',
                'email': 'buyer@test.com',
                'password': 'password123'
            },
            {
                'username': 'seller_test',
                'email': 'seller@test.com',
                'password': 'password123'
            }
        ]
        
        for user_data in test_users:
            # Check if user already exists
            existing_user = User.query.filter_by(email=user_data['email']).first()
            if existing_user:
                print(f"User {user_data['username']} already exists")
                continue
            
            user = User(
                username=user_data['username'],
                email=user_data['email'],
                password=generate_password_hash(user_data['password'])
            )
            db.session.add(user)
            print(f"Created user: {user_data['username']} ({user_data['email']})")
        
        db.session.commit()
        
        # Display all users
        all_users = User.query.all()
        print(f"\nTotal users in database: {len(all_users)}")
        for user in all_users:
            print(f"  - {user.username} ({user.email})")

if __name__ == '__main__':
    create_test_users() 