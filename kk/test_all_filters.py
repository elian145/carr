from app import app, db, Car

with app.app_context():
    print("=== Testing All Filter Types ===\n")
    
    # Get all cars first
    all_cars = Car.query.all()
    print(f"Total cars in database: {len(all_cars)}")
    for car in all_cars:
        print(f"- {car.title} (Brand: '{car.brand}', Price: ${car.price}, Year: {car.year}, Mileage: {car.mileage})")
    
    print("\n=== Testing Individual Filters ===")
    
    # Test 1: Brand filter
    print("\n1. Brand filter - 'mercedes-benz':")
    brand_filtered = Car.query.filter(Car.brand.ilike('%mercedes-benz%')).all()
    print(f"   Found {len(brand_filtered)} cars")
    for car in brand_filtered:
        print(f"   - {car.title}")
    
    # Test 2: Price filter
    print("\n2. Price filter - $100k-$150k:")
    price_filtered = Car.query.filter(Car.price >= 100000, Car.price <= 150000).all()
    print(f"   Found {len(price_filtered)} cars")
    for car in price_filtered:
        print(f"   - {car.title} (${car.price})")
    
    # Test 3: Year filter
    print("\n3. Year filter - 2021+:")
    year_filtered = Car.query.filter(Car.year >= 2021).all()
    print(f"   Found {len(year_filtered)} cars")
    for car in year_filtered:
        print(f"   - {car.title} ({car.year})")
    
    # Test 4: Mileage filter
    print("\n4. Mileage filter - 20k-40k:")
    mileage_filtered = Car.query.filter(Car.mileage >= 20000, Car.mileage <= 40000).all()
    print(f"   Found {len(mileage_filtered)} cars")
    for car in mileage_filtered:
        print(f"   - {car.title} ({car.mileage} km)")
    
    # Test 5: Transmission filter
    print("\n5. Transmission filter - 'automatic':")
    transmission_filtered = Car.query.filter(Car.transmission == 'automatic').all()
    print(f"   Found {len(transmission_filtered)} cars")
    for car in transmission_filtered:
        print(f"   - {car.title} ({car.transmission})")
    
    # Test 6: Color filter
    print("\n6. Color filter - 'black':")
    color_filtered = Car.query.filter(Car.color == 'black').all()
    print(f"   Found {len(color_filtered)} cars")
    for car in color_filtered:
        print(f"   - {car.title} ({car.color})")
    
    # Test 7: Body type filter
    print("\n7. Body type filter - 'sedan':")
    body_filtered = Car.query.filter(Car.body_type == 'sedan').all()
    print(f"   Found {len(body_filtered)} cars")
    for car in body_filtered:
        print(f"   - {car.title} ({car.body_type})")
    
    # Test 8: City filter
    print("\n8. City filter - 'baghdad':")
    city_filtered = Car.query.filter(Car.city == 'baghdad').all()
    print(f"   Found {len(city_filtered)} cars")
    for car in city_filtered:
        print(f"   - {car.title} ({car.city})")
    
    # Test 9: Condition filter
    print("\n9. Condition filter - 'used':")
    condition_filtered = Car.query.filter(Car.condition == 'used').all()
    print(f"   Found {len(condition_filtered)} cars")
    for car in condition_filtered:
        print(f"   - {car.title} ({car.condition})")
    
    # Test 10: Combined filters
    print("\n10. Combined filters - BMW + Automatic:")
    combined = Car.query.filter(
        Car.brand.ilike('%bmw%'),
        Car.transmission == 'automatic'
    ).all()
    print(f"    Found {len(combined)} cars")
    for car in combined:
        print(f"    - {car.title} ({car.brand}, {car.transmission})") 