import random
from datetime import datetime
from app import app, db, Car, CarImage
import os

# Sample data for random car generation
brands = [
    'bmw', 'mercedes-benz', 'audi', 'toyota', 'honda', 'nissan', 'ford', 
    'chevrolet', 'hyundai', 'kia', 'volkswagen', 'volvo', 'lexus', 'porsche',
    'jaguar', 'land-rover', 'mini', 'smart', 'subaru', 'mazda', 'mitsubishi',
    'suzuki', 'ferrari', 'lamborghini', 'bentley', 'rolls-royce', 'aston-martin',
    'mclaren', 'maserati', 'bugatti', 'pagani', 'koenigsegg', 'alfa-romeo',
    'fiat', 'lancia', 'abarth', 'opel', 'vauxhall', 'peugeot', 'citroen',
    'renault', 'ds', 'seat', 'skoda', 'dacia', 'cadillac', 'buick', 'gmc',
    'chrysler', 'dodge', 'jeep', 'ram', 'lincoln', 'alpina', 'brabus',
    'mansory', 'genesis', 'isuzu', 'datsun', 'ktm', 'jac-motors', 'jac-trucks',
    'byd', 'geely-zgh', 'great-wall-motors', 'chery-automobile', 'baic',
    'gac', 'saic', 'mg', 'bestune', 'hongqi', 'dongfeng-motor', 'faw',
    'faw-jiefang', 'foton', 'leapmotor', 'man', 'iran-khodro'
]

models = {
    'bmw': ['X3', 'X5', 'X7', '3 Series', '5 Series', '7 Series', 'M3', 'M5', 'X1', 'X6'],
    'mercedes-benz': ['C-Class', 'E-Class', 'S-Class', 'GLC', 'GLE', 'GLS', 'A-Class', 'CLA', 'GLA', 'AMG GT'],
    'audi': ['A3', 'A4', 'A6', 'A8', 'Q3', 'Q5', 'Q7', 'Q8', 'RS6', 'TT'],
    'toyota': ['Camry', 'Corolla', 'RAV4', 'Highlander', 'Tacoma', 'Tundra', 'Prius', 'Avalon', '4Runner', 'Sequoia'],
    'honda': ['Civic', 'Accord', 'CR-V', 'Pilot', 'Ridgeline', 'Odyssey', 'HR-V', 'Passport', 'Insight', 'Clarity'],
    'nissan': ['Altima', 'Maxima', 'Rogue', 'Murano', 'Pathfinder', 'Frontier', 'Titan', 'Leaf', 'Sentra', 'Versa'],
    'ford': ['F-150', 'Mustang', 'Explorer', 'Escape', 'Edge', 'Ranger', 'Bronco', 'Mach-E', 'Focus', 'Fusion'],
    'chevrolet': ['Silverado', 'Camaro', 'Equinox', 'Tahoe', 'Suburban', 'Colorado', 'Corvette', 'Malibu', 'Cruze', 'Traverse'],
    'hyundai': ['Elantra', 'Sonata', 'Tucson', 'Santa Fe', 'Palisade', 'Kona', 'Venue', 'Accent', 'Veloster', 'Ioniq'],
    'kia': ['Forte', 'K5', 'Sportage', 'Telluride', 'Sorento', 'Soul', 'Rio', 'Stinger', 'EV6', 'Niro']
}

trims = ['Base', 'Sport', 'Luxury', 'Premium', 'Limited', 'Platinum', 'Signature', 'Touring', 'SE', 'LE', 'XLE', 'XSE']

conditions = ['new', 'used']
transmissions = ['automatic', 'manual']
fuel_types = ['gasoline', 'diesel', 'electric', 'hybrid', 'lpg', 'plug_in_hybrid']
colors = ['black', 'white', 'silver', 'gray', 'red', 'blue', 'green', 'yellow', 'orange', 'purple', 'brown', 'beige', 'gold']
body_types = ['sedan', 'suv', 'hatchback', 'coupe', 'wagon', 'pickup', 'van', 'minivan', 'motorcycle', 'utv', 'atv']
cities = ['baghdad', 'basra', 'erbil', 'najaf', 'karbala', 'kirkuk', 'mosul', 'sulaymaniyah', 'dohuk', 'anbar', 'halabja', 'diyala', 'diyarbakir', 'maysan', 'muthanna', 'dhi_qar', 'salaheldeen']

# Sample car images (using placeholder URLs or existing uploads)
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

def generate_random_car():
    """Generate a random car with realistic specifications"""
    brand = random.choice(brands)
    
    # Get model for the brand, or use a generic model if brand not in models dict
    if brand in models:
        model = random.choice(models[brand])
    else:
        model = f"{brand.title()} Model"
    
    trim = random.choice(trims)
    year = random.randint(2015, 2024)
    price = random.randint(15000, 200000)
    mileage = random.randint(0, 150000)
    condition = random.choice(conditions)
    transmission = random.choice(transmissions)
    fuel_type = random.choice(fuel_types)
    color = random.choice(colors)
    body_type = random.choice(body_types)
    seating = random.randint(2, 8)
    drive_type = random.choice(['fwd', 'rwd', 'awd', '4wd'])
    city = random.choice(cities)
    
    # Generate title
    title = f"{brand.upper()} {model}"
    
    # Random additional specs
    cylinder_count = random.choice([4, 6, 8, 12]) if fuel_type != 'electric' else None
    engine_size = random.choice([1.6, 2.0, 2.5, 3.0, 3.5, 4.0, 5.0, 6.0]) if fuel_type != 'electric' else None
    import_country = random.choice(['us', 'gcc', 'iraq', 'canada', 'eu', 'cn', 'korea', 'ru', 'iran'])
    license_plate_type = random.choice(['private', 'temporary', 'commercial', 'taxi'])
    title_status = random.choice(['clean', 'damaged'])
    damaged_parts = random.randint(1, 5) if title_status == 'damaged' else None
    
    return {
        'title': title,
        'brand': brand,
        'model': model,
        'trim': trim,
        'year': year,
        'price': price,
        'mileage': mileage,
        'condition': condition,
        'transmission': transmission,
        'fuel_type': fuel_type,
        'color': color,
        'body_type': body_type,
        'seating': seating,
        'drive_type': drive_type,
        'city': city,
        'cylinder_count': cylinder_count,
        'engine_size': engine_size,
        'import_country': import_country,
        'license_plate_type': license_plate_type,
        'title_status': title_status,
        'damaged_parts': damaged_parts
    }

def add_random_listings():
    """Add 100 random car listings to the database, each with a real car photo as its image."""
    with app.app_context():
        # Clear existing cars and images
        CarImage.query.delete()
        Car.query.delete()
        db.session.commit()
        print("Cleared existing cars and images")

        # Get all real car photo paths
        car_photos_dir = os.path.join('static', 'uploads', 'car_photos')
        car_photos = [f"uploads/car_photos/{f}" for f in os.listdir(car_photos_dir) if f.lower().endswith('.jpg')]
        if not car_photos:
            raise Exception("No real car photos found in static/uploads/car_photos!")

        # Add 100 random cars
        for i in range(100):
            car_data = generate_random_car()
            car = Car(
                title=car_data['title'],
                brand=car_data['brand'],
                model=car_data['model'],
                trim=car_data['trim'],
                year=car_data['year'],
                price=car_data['price'],
                mileage=car_data['mileage'],
                condition=car_data['condition'],
                transmission=car_data['transmission'],
                fuel_type=car_data['fuel_type'],
                color=car_data['color'],
                body_type=car_data['body_type'],
                seating=car_data['seating'],
                drive_type=car_data['drive_type'],
                city=car_data['city'],
                cylinder_count=car_data['cylinder_count'],
                engine_size=car_data['engine_size'],
                import_country=car_data['import_country'],
                license_plate_type=car_data['license_plate_type'],
                title_status=car_data['title_status'],
                damaged_parts=car_data['damaged_parts'],
                created_at=datetime.utcnow(),
                status='active'
            )
            db.session.add(car)
            db.session.flush()  # Get the car ID

            # Assign a random real car photo as the car image
            car_image_path = random.choice(car_photos)
            car_image = CarImage(
                car_id=car.id,
                image_url=car_image_path
            )
            db.session.add(car_image)
            print(f"Added: {car_data['title']} (${car_data['price']:,}) with real car photo {car_image_path}")
        db.session.commit()
        # Display summary
        cars = Car.query.all()
        print(f"\nTotal cars in database: {len(cars)}")
        print("\nCars added:")
        for car in cars:
            image_count = len(car.images)
            print(f"- {car.title} (Brand: '{car.brand}', Price: ${car.price:,}, Year: {car.year}, Images: {image_count})")

if __name__ == "__main__":
    add_random_listings() 