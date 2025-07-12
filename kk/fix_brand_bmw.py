from app import app, db, Car

with app.app_context():
    # Normalize all BMW listings to have brand 'bmw'
    bmw_cars = Car.query.filter(Car.brand.ilike('%bmw%')).all()
    for car in bmw_cars:
        car.brand = 'bmw'
    db.session.commit()
    print(f"Updated {len(bmw_cars)} BMW listings to brand 'bmw'.")