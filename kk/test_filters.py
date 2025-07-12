from app import app, db, Car

with app.app_context():
    print("=== Testing Filter Logic ===\n")
    
    # Test 1: Get all cars
    all_cars = Car.query.all()
    print(f"1. All cars ({len(all_cars)}):")
    for car in all_cars:
        print(f"   - {car.title} (Brand: {car.brand})")
    
    # Test 2: Filter by brand 'bmw'
    bmw_cars = Car.query.filter(Car.brand.ilike('%bmw%')).all()
    print(f"\n2. BMW cars ({len(bmw_cars)}):")
    for car in bmw_cars:
        print(f"   - {car.title} (Brand: {car.brand})")
    
    # Test 3: Filter by price range
    price_filtered = Car.query.filter(Car.price >= 30000, Car.price <= 50000).all()
    print(f"\n3. Cars between $30k-$50k ({len(price_filtered)}):")
    for car in price_filtered:
        print(f"   - {car.title} (Price: ${car.price})")
    
    # Test 4: Filter by year
    year_filtered = Car.query.filter(Car.year >= 2021).all()
    print(f"\n4. Cars from 2021+ ({len(year_filtered)}):")
    for car in year_filtered:
        print(f"   - {car.title} (Year: {car.year})")
    
    # Test 5: Filter by transmission
    auto_cars = Car.query.filter(Car.transmission == 'automatic').all()
    print(f"\n5. Automatic cars ({len(auto_cars)}):")
    for car in auto_cars:
        print(f"   - {car.title} (Transmission: {car.transmission})")
    
    # Test 6: Combined filters
    combined = Car.query.filter(
        Car.brand.ilike('%bmw%'),
        Car.price >= 40000
    ).all()
    print(f"\n6. BMW cars over $40k ({len(combined)}):")
    for car in combined:
        print(f"   - {car.title} (Brand: {car.brand}, Price: ${car.price})") 