import random
from datetime import datetime
from app import app, db, Car, CarImage

# Real car data with accurate specifications
real_cars = [
    # BMW Models
    {
        'brand': 'bmw', 'model': 'X3', 'trim': 'xDrive30i', 'year': 2023, 'price': 48500, 'mileage': 15000,
        'condition': 'used', 'transmission': 'automatic', 'fuel_type': 'gasoline', 'color': 'white',
        'body_type': 'suv', 'seating': 5, 'drive_type': 'awd', 'cylinder_count': 4, 'engine_size': 2.0
    },
    {
        'brand': 'bmw', 'model': '5 Series', 'trim': '530i', 'year': 2022, 'price': 62000, 'mileage': 25000,
        'condition': 'used', 'transmission': 'automatic', 'fuel_type': 'gasoline', 'color': 'black',
        'body_type': 'sedan', 'seating': 5, 'drive_type': 'rwd', 'cylinder_count': 4, 'engine_size': 2.0
    },
    {
        'brand': 'bmw', 'model': 'M3', 'trim': 'Competition', 'year': 2024, 'price': 85000, 'mileage': 5000,
        'condition': 'used', 'transmission': 'automatic', 'fuel_type': 'gasoline', 'color': 'blue',
        'body_type': 'sedan', 'seating': 5, 'drive_type': 'rwd', 'cylinder_count': 6, 'engine_size': 3.0
    },
    
    # Mercedes-Benz Models
    {
        'brand': 'mercedes-benz', 'model': 'C-Class', 'trim': 'C300', 'year': 2023, 'price': 55000, 'mileage': 12000,
        'condition': 'used', 'transmission': 'automatic', 'fuel_type': 'gasoline', 'color': 'silver',
        'body_type': 'sedan', 'seating': 5, 'drive_type': 'rwd', 'cylinder_count': 4, 'engine_size': 2.0
    },
    {
        'brand': 'mercedes-benz', 'model': 'GLC', 'trim': '300', 'year': 2022, 'price': 58000, 'mileage': 18000,
        'condition': 'used', 'transmission': 'automatic', 'fuel_type': 'gasoline', 'color': 'white',
        'body_type': 'suv', 'seating': 5, 'drive_type': 'awd', 'cylinder_count': 4, 'engine_size': 2.0
    },
    {
        'brand': 'mercedes-benz', 'model': 'S-Class', 'trim': 'S500', 'year': 2024, 'price': 120000, 'mileage': 3000,
        'condition': 'used', 'transmission': 'automatic', 'fuel_type': 'gasoline', 'color': 'black',
        'body_type': 'sedan', 'seating': 5, 'drive_type': 'rwd', 'cylinder_count': 6, 'engine_size': 3.0
    },
    
    # Audi Models
    {
        'brand': 'audi', 'model': 'A4', 'trim': 'Premium Plus', 'year': 2023, 'price': 52000, 'mileage': 14000,
        'condition': 'used', 'transmission': 'automatic', 'fuel_type': 'gasoline', 'color': 'gray',
        'body_type': 'sedan', 'seating': 5, 'drive_type': 'awd', 'cylinder_count': 4, 'engine_size': 2.0
    },
    {
        'brand': 'audi', 'model': 'Q5', 'trim': 'Premium Plus', 'year': 2022, 'price': 56000, 'mileage': 22000,
        'condition': 'used', 'transmission': 'automatic', 'fuel_type': 'gasoline', 'color': 'white',
        'body_type': 'suv', 'seating': 5, 'drive_type': 'awd', 'cylinder_count': 4, 'engine_size': 2.0
    },
    {
        'brand': 'audi', 'model': 'RS6', 'trim': 'Avant', 'year': 2024, 'price': 130000, 'mileage': 8000,
        'condition': 'used', 'transmission': 'automatic', 'fuel_type': 'gasoline', 'color': 'blue',
        'body_type': 'wagon', 'seating': 5, 'drive_type': 'awd', 'cylinder_count': 8, 'engine_size': 4.0
    },
    
    # Toyota Models
    {
        'brand': 'toyota', 'model': 'Camry', 'trim': 'XSE', 'year': 2023, 'price': 35000, 'mileage': 16000,
        'condition': 'used', 'transmission': 'automatic', 'fuel_type': 'gasoline', 'color': 'red',
        'body_type': 'sedan', 'seating': 5, 'drive_type': 'fwd', 'cylinder_count': 4, 'engine_size': 2.5
    },
    {
        'brand': 'toyota', 'model': 'RAV4', 'trim': 'XLE', 'year': 2022, 'price': 38000, 'mileage': 20000,
        'condition': 'used', 'transmission': 'automatic', 'fuel_type': 'gasoline', 'color': 'silver',
        'body_type': 'suv', 'seating': 5, 'drive_type': 'awd', 'cylinder_count': 4, 'engine_size': 2.5
    },
    {
        'brand': 'toyota', 'model': 'Prius', 'trim': 'Limited', 'year': 2024, 'price': 42000, 'mileage': 5000,
        'condition': 'used', 'transmission': 'automatic', 'fuel_type': 'hybrid', 'color': 'white',
        'body_type': 'hatchback', 'seating': 5, 'drive_type': 'fwd', 'cylinder_count': 4, 'engine_size': 2.0
    },
    
    # Honda Models
    {
        'brand': 'honda', 'model': 'Civic', 'trim': 'Sport', 'year': 2023, 'price': 28000, 'mileage': 12000,
        'condition': 'used', 'transmission': 'automatic', 'fuel_type': 'gasoline', 'color': 'blue',
        'body_type': 'sedan', 'seating': 5, 'drive_type': 'fwd', 'cylinder_count': 4, 'engine_size': 1.5
    },
    {
        'brand': 'honda', 'model': 'CR-V', 'trim': 'EX-L', 'year': 2022, 'price': 35000, 'mileage': 18000,
        'condition': 'used', 'transmission': 'automatic', 'fuel_type': 'gasoline', 'color': 'black',
        'body_type': 'suv', 'seating': 5, 'drive_type': 'awd', 'cylinder_count': 4, 'engine_size': 1.5
    },
    {
        'brand': 'honda', 'model': 'Accord', 'trim': 'Touring', 'year': 2024, 'price': 38000, 'mileage': 8000,
        'condition': 'used', 'transmission': 'automatic', 'fuel_type': 'gasoline', 'color': 'gray',
        'body_type': 'sedan', 'seating': 5, 'drive_type': 'fwd', 'cylinder_count': 4, 'engine_size': 1.5
    },
    
    # Ford Models
    {
        'brand': 'ford', 'model': 'F-150', 'trim': 'XLT', 'year': 2023, 'price': 55000, 'mileage': 15000,
        'condition': 'used', 'transmission': 'automatic', 'fuel_type': 'gasoline', 'color': 'white',
        'body_type': 'pickup', 'seating': 6, 'drive_type': '4wd', 'cylinder_count': 6, 'engine_size': 3.5
    },
    {
        'brand': 'ford', 'model': 'Mustang', 'trim': 'GT', 'year': 2022, 'price': 48000, 'mileage': 12000,
        'condition': 'used', 'transmission': 'manual', 'fuel_type': 'gasoline', 'color': 'red',
        'body_type': 'coupe', 'seating': 4, 'drive_type': 'rwd', 'cylinder_count': 8, 'engine_size': 5.0
    },
    {
        'brand': 'ford', 'model': 'Explorer', 'trim': 'Limited', 'year': 2024, 'price': 52000, 'mileage': 6000,
        'condition': 'used', 'transmission': 'automatic', 'fuel_type': 'gasoline', 'color': 'black',
        'body_type': 'suv', 'seating': 7, 'drive_type': 'awd', 'cylinder_count': 6, 'engine_size': 3.0
    },
    
    # Chevrolet Models
    {
        'brand': 'chevrolet', 'model': 'Silverado', 'trim': 'LT', 'year': 2023, 'price': 58000, 'mileage': 14000,
        'condition': 'used', 'transmission': 'automatic', 'fuel_type': 'gasoline', 'color': 'silver',
        'body_type': 'pickup', 'seating': 6, 'drive_type': '4wd', 'cylinder_count': 8, 'engine_size': 5.3
    },
    {
        'brand': 'chevrolet', 'model': 'Corvette', 'trim': 'Stingray', 'year': 2024, 'price': 85000, 'mileage': 3000,
        'condition': 'used', 'transmission': 'automatic', 'fuel_type': 'gasoline', 'color': 'yellow',
        'body_type': 'coupe', 'seating': 2, 'drive_type': 'rwd', 'cylinder_count': 8, 'engine_size': 6.2
    },
    {
        'brand': 'chevrolet', 'model': 'Tahoe', 'trim': 'Premier', 'year': 2022, 'price': 72000, 'mileage': 20000,
        'condition': 'used', 'transmission': 'automatic', 'fuel_type': 'gasoline', 'color': 'white',
        'body_type': 'suv', 'seating': 8, 'drive_type': '4wd', 'cylinder_count': 8, 'engine_size': 5.3
    },
    
    # Hyundai Models
    {
        'brand': 'hyundai', 'model': 'Elantra', 'trim': 'Limited', 'year': 2023, 'price': 28000, 'mileage': 10000,
        'condition': 'used', 'transmission': 'automatic', 'fuel_type': 'gasoline', 'color': 'blue',
        'body_type': 'sedan', 'seating': 5, 'drive_type': 'fwd', 'cylinder_count': 4, 'engine_size': 2.0
    },
    {
        'brand': 'hyundai', 'model': 'Tucson', 'trim': 'SEL', 'year': 2022, 'price': 32000, 'mileage': 16000,
        'condition': 'used', 'transmission': 'automatic', 'fuel_type': 'gasoline', 'color': 'gray',
        'body_type': 'suv', 'seating': 5, 'drive_type': 'awd', 'cylinder_count': 4, 'engine_size': 2.5
    },
    {
        'brand': 'hyundai', 'model': 'Ioniq', 'trim': 'Limited', 'year': 2024, 'price': 45000, 'mileage': 4000,
        'condition': 'used', 'transmission': 'automatic', 'fuel_type': 'electric', 'color': 'white',
        'body_type': 'sedan', 'seating': 5, 'drive_type': 'fwd', 'cylinder_count': None, 'engine_size': None
    },
    
    # Kia Models
    {
        'brand': 'kia', 'model': 'Forte', 'trim': 'GT', 'year': 2023, 'price': 26000, 'mileage': 12000,
        'condition': 'used', 'transmission': 'automatic', 'fuel_type': 'gasoline', 'color': 'red',
        'body_type': 'sedan', 'seating': 5, 'drive_type': 'fwd', 'cylinder_count': 4, 'engine_size': 1.6
    },
    {
        'brand': 'kia', 'model': 'Sportage', 'trim': 'EX', 'year': 2022, 'price': 34000, 'mileage': 18000,
        'condition': 'used', 'transmission': 'automatic', 'fuel_type': 'gasoline', 'color': 'black',
        'body_type': 'suv', 'seating': 5, 'drive_type': 'awd', 'cylinder_count': 4, 'engine_size': 2.5
    },
    {
        'brand': 'kia', 'model': 'EV6', 'trim': 'Wind', 'year': 2024, 'price': 52000, 'mileage': 6000,
        'condition': 'used', 'transmission': 'automatic', 'fuel_type': 'electric', 'color': 'blue',
        'body_type': 'suv', 'seating': 5, 'drive_type': 'awd', 'cylinder_count': None, 'engine_size': None
    },
    
    # Volkswagen Models
    {
        'brand': 'volkswagen', 'model': 'Golf', 'trim': 'GTI', 'year': 2023, 'price': 35000, 'mileage': 10000,
        'condition': 'used', 'transmission': 'manual', 'fuel_type': 'gasoline', 'color': 'white',
        'body_type': 'hatchback', 'seating': 5, 'drive_type': 'fwd', 'cylinder_count': 4, 'engine_size': 2.0
    },
    {
        'brand': 'volkswagen', 'model': 'Tiguan', 'trim': 'SE', 'year': 2022, 'price': 38000, 'mileage': 15000,
        'condition': 'used', 'transmission': 'automatic', 'fuel_type': 'gasoline', 'color': 'silver',
        'body_type': 'suv', 'seating': 7, 'drive_type': 'awd', 'cylinder_count': 4, 'engine_size': 2.0
    },
    {
        'brand': 'volkswagen', 'model': 'ID.4', 'trim': 'Pro', 'year': 2024, 'price': 48000, 'mileage': 8000,
        'condition': 'used', 'transmission': 'automatic', 'fuel_type': 'electric', 'color': 'gray',
        'body_type': 'suv', 'seating': 5, 'drive_type': 'awd', 'cylinder_count': None, 'engine_size': None
    },
    
    # Luxury Models
    {
        'brand': 'porsche', 'model': '911', 'trim': 'Carrera', 'year': 2023, 'price': 120000, 'mileage': 8000,
        'condition': 'used', 'transmission': 'automatic', 'fuel_type': 'gasoline', 'color': 'black',
        'body_type': 'coupe', 'seating': 4, 'drive_type': 'rwd', 'cylinder_count': 6, 'engine_size': 3.0
    },
    {
        'brand': 'ferrari', 'model': 'F8', 'trim': 'Tributo', 'year': 2024, 'price': 280000, 'mileage': 2000,
        'condition': 'used', 'transmission': 'automatic', 'fuel_type': 'gasoline', 'color': 'red',
        'body_type': 'coupe', 'seating': 2, 'drive_type': 'rwd', 'cylinder_count': 8, 'engine_size': 3.9
    },
    {
        'brand': 'lamborghini', 'model': 'Huracan', 'trim': 'EVO', 'year': 2023, 'price': 250000, 'mileage': 5000,
        'condition': 'used', 'transmission': 'automatic', 'fuel_type': 'gasoline', 'color': 'yellow',
        'body_type': 'coupe', 'seating': 2, 'drive_type': 'awd', 'cylinder_count': 10, 'engine_size': 5.2
    }
]

# Realistic cities in Iraq
cities = ['baghdad', 'basra', 'erbil', 'najaf', 'karbala', 'kirkuk', 'mosul', 'sulaymaniyah', 'dohuk', 'anbar', 'halabja', 'diyala', 'diyarbakir', 'maysan', 'muthanna', 'dhi_qar', 'salaheldeen']

# Available car images
car_images = [
    'uploads/20250621_024654_wdwdwdwdwdwdwdwdwdwd.png',
    'uploads/20250621_020641_122222.png',
    'uploads/20250621_020641_77777777777777777777777_-_Copy_-_Copy_-_Copy_2.png',
    'uploads/20250621_020641_77777777777777777777777_-_Copy_2.png',
    'uploads/20250621_020641_77777777777777777777777_-_Copy.png',
    'uploads/20250621_020641_a_fast_food_restaurant_named_supass_create_for_me_a_logo_where_the_background_is_white_and_the_supass_is_on_top_of_a_burger_-_Copy_-_Copy_-_Copy_2.jpg',
    'uploads/20250621_020641_a_fast_food_restaurant_named_supass_create_for_me_a_logo_where_the_background_is_white_and_the_supass_is_on_top_of_a_burger_-_Copy_-_Copy_-_Copy.jpg',
    'uploads/20250621_020641_acura-logo.png',
    'uploads/20250621_020641_amerr_-_Copy_-_Copy.png',
    'uploads/20250621_021256_77777777777777777777777_-_Copy_-_Copy_3_-_Copy.png',
    'uploads/20250621_021256_77777777777777777777777_-_Copy_3_-_Copy_-_Copy.png',
    'uploads/20250621_021256_wdwdwdwdwdwdwdwdwdwd_-_Copy_-_Copy_2.png',
    'uploads/20250621_021256_wdwdwdwdwdwdwdwdwdwd_-_Copy_2_-_Copy.png',
    'uploads/20250621_021256_wdwdwdwdwdwdwdwdwdwd_-_Copy_3.png',
    'uploads/20250621_021256_yyyyyyyyyyyyy_-_Copy_-_Copy_-_Copy_-_Copy.png',
    'uploads/20250621_021256_yyyyyyyyyyyyy_-_Copy_-_Copy_2.png',
    'uploads/20250621_021256_yyyyyyyyyyyyy_-_Copy_-_Copy.png',
    'uploads/20250621_022230_122222_-_Copy.png',
    'uploads/20250621_022230_122222.png',
    'uploads/20250621_022230_77777777777777777777777_-_Copy_-_Copy_-_Copy_2.png',
    'uploads/20250621_022230_77777777777777777777777_-_Copy_-_Copy_3.png',
    'uploads/20250621_022230_77777777777777777777777_-_Copy_-_Copy.png',
    'uploads/20250621_022230_77777777777777777777777_-_Copy_2_-_Copy.png',
    'uploads/20250621_023530_77777777777777777777777_-_Copy_-_Copy_-_Copy_3.png',
    'uploads/20250621_023530_77777777777777777777777_-_Copy_2_-_Copy_-_Copy.png',
    'uploads/20250621_023530_77777777777777777777777_-_Copy_3.png'
]

def add_realistic_listings():
    """Add 100 realistic car listings to the database"""
    with app.app_context():
        # Clear existing cars and images
        CarImage.query.delete()
        Car.query.delete()
        db.session.commit()
        print("Cleared existing cars and images")
        
        total_to_add = 100
        for i in range(total_to_add):
            car_data = random.choice(real_cars)
            # Add some randomization to make each listing unique
            price_variation = random.uniform(0.9, 1.1)  # ±10% price variation
            mileage_variation = random.uniform(0.8, 1.2)  # ±20% mileage variation
            year_variation = random.randint(-2, 1)  # Slight year variation
            car = Car(
                title=f"{car_data['brand'].title()} {car_data['model']} #{i+1}",
                brand=car_data['brand'],
                model=car_data['model'],
                trim=car_data['trim'],
                year=car_data['year'] + year_variation,
                price=int(car_data['price'] * price_variation),
                mileage=int(car_data['mileage'] * mileage_variation),
                condition=car_data['condition'],
                transmission=car_data['transmission'],
                fuel_type=car_data['fuel_type'],
                color=random.choice([car_data['color'], random.choice(['white','black','gray','silver','red','blue','yellow'])]),
                body_type=car_data['body_type'],
                seating=car_data['seating'],
                drive_type=car_data['drive_type'],
                city=random.choice(cities),
                cylinder_count=car_data['cylinder_count'],
                engine_size=car_data['engine_size'],
                import_country=random.choice(['us', 'gcc', 'iraq', 'canada', 'eu', 'cn', 'korea', 'ru', 'iran']),
                license_plate_type=random.choice(['private', 'temporary', 'commercial', 'taxi']),
                title_status=random.choice(['clean', 'clean', 'rebuilt']),  # Mostly clean titles
                damaged_parts=None,  # Clean titles
                created_at=datetime.utcnow(),
                status='active'  # Ensure listing is active and visible
            )
            db.session.add(car)
            db.session.flush()  # Get the car ID
            # Add 2-4 random images to each car
            num_images = random.randint(2, 4)
            selected_images = random.sample(car_images, min(num_images, len(car_images)))
            for img_url in selected_images:
                car_image = CarImage(
                    car_id=car.id,
                    image_url=img_url
                )
                db.session.add(car_image)
            print(f"Added: {car.title} (${car.price:,}) with {len(selected_images)} images")
        db.session.commit()
        # Display summary
        cars = Car.query.all()
        print(f"\nTotal cars in database: {len(cars)}")
        # Group by brand
        brands_summary = {}
        for car in cars:
            if car.brand not in brands_summary:
                brands_summary[car.brand] = []
            brands_summary[car.brand].append(car)
        print("\nCars by brand:")
        for brand, brand_cars in sorted(brands_summary.items()):
            print(f"\n{brand.upper()} ({len(brand_cars)} cars):")
            for car in brand_cars:
                image_count = len(car.images)
                print(f"  - {car.title} (${car.price:,}, {car.year}, {image_count} images)")

if __name__ == "__main__":
    add_realistic_listings() 