import sys
sys.path.append('kk')
import app as app_module
from app import db, Car, CarImage
app = app_module.app
with app.app_context():
    total_cars = db.session.query(Car).count()
    with_images = db.session.query(Car).join(CarImage, Car.id==CarImage.car_id).distinct().count()
    imgs = db.session.query(CarImage).count()
    sample = db.session.query(Car).order_by(Car.created_at.desc()).limit(5).all()
    print('cars:', total_cars, 'cars_with_images:', with_images, 'total_images:', imgs)
    for c in sample:
        first = (c.images[0].image_url if c.images else c.image_url)
        print(c.id, c.title, 'img:', first)
