from app import app, db, Car

with app.app_context():
    print("=== Debugging Mercedes Filter ===\n")
    
    # Check all cars in database
    all_cars = Car.query.all()
    print(f"Total cars in database: {len(all_cars)}")
    for car in all_cars:
        print(f"- {car.title} (Brand: '{car.brand}')")
    
    # Test different Mercedes filter variations
    print("\n=== Testing Mercedes Filters ===")
    
    # Test 1: Exact match
    mercedes_exact = Car.query.filter(Car.brand == 'mercedes').all()
    print(f"1. Exact match 'mercedes': {len(mercedes_exact)} cars")
    
    # Test 2: Case insensitive
    mercedes_ilike = Car.query.filter(Car.brand.ilike('%mercedes%')).all()
    print(f"2. ILIKE '%mercedes%': {len(mercedes_ilike)} cars")
    
    # Test 3: Mercedes-Benz
    mercedes_benz = Car.query.filter(Car.brand.ilike('%mercedes-benz%')).all()
    print(f"3. ILIKE '%mercedes-benz%': {len(mercedes_benz)} cars")
    
    # Test 4: Just 'benz'
    benz = Car.query.filter(Car.brand.ilike('%benz%')).all()
    print(f"4. ILIKE '%benz%': {len(benz)} cars")
    
    # Test 5: Show all brands in database
    print("\n=== All brands in database ===")
    brands = db.session.query(Car.brand).distinct().all()
    for brand in brands:
        print(f"- '{brand[0]}'")
    
    # Test 6: Show Mercedes cars with full details
    if mercedes_ilike:
        print("\n=== Mercedes cars found ===")
        for car in mercedes_ilike:
            print(f"- {car.title} (Brand: '{car.brand}', ID: {car.id})")
    else:
        print("\nNo Mercedes cars found with ILIKE filter") 