from app import app, db, Car

with app.app_context():
    cars = Car.query.all()
    print(f"Total cars in database: {len(cars)}")
    
    if cars:
        print("\nCars in database:")
        for car in cars:
            print(f"- {car.title} (Brand: '{car.brand}', Price: ${car.price})")
        
        brands = set(car.brand for car in cars)
        print(f"\nBrands in database: {brands}")
        
        # Test brand filtering
        print("\n=== Testing Brand Filtering ===")
        
        # Test BMW filter
        bmw_cars = Car.query.filter(Car.brand.ilike('%bmw%')).all()
        print(f"BMW cars found with ILIKE '%bmw%': {len(bmw_cars)}")
        for car in bmw_cars:
            print(f"  - {car.title} (Brand: '{car.brand}')")
        
        # Test Mercedes filter
        mercedes_cars = Car.query.filter(Car.brand.ilike('%mercedes%')).all()
        print(f"Mercedes cars found with ILIKE '%mercedes%': {len(mercedes_cars)}")
        for car in mercedes_cars:
            print(f"  - {car.title} (Brand: '{car.brand}')")
        
        # Test Toyota filter
        toyota_cars = Car.query.filter(Car.brand.ilike('%toyota%')).all()
        print(f"Toyota cars found with ILIKE '%toyota%': {len(toyota_cars)}")
        for car in toyota_cars:
            print(f"  - {car.title} (Brand: '{car.brand}')")
    else:
        print("No cars found in database") 