from app import app, db, Car, User

def fix_car_users():
    """Associate existing cars with users for testing"""
    with app.app_context():
        cars = Car.query.all()
        users = User.query.all()
        
        print(f"Found {len(cars)} cars and {len(users)} users")
        
        if len(cars) == 0:
            print("No cars found")
            return
        
        if len(users) == 0:
            print("No users found")
            return
        
        # Get the first user as the seller
        seller = users[0]
        print(f"Using {seller.username} as seller for all cars")
        
        # Update all cars to have a user_id
        updated_count = 0
        for car in cars:
            if car.user_id is None:
                car.user_id = seller.id
                updated_count += 1
        
        db.session.commit()
        print(f"Updated {updated_count} cars with user_id")
        
        # Verify the update
        cars_with_users = Car.query.filter(Car.user_id.isnot(None)).count()
        print(f"Total cars with users: {cars_with_users}")

if __name__ == '__main__':
    fix_car_users() 