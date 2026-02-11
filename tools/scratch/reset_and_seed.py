import sys, os
sys.path.append('kk')
import app_new as app_module
from models import db, User, Car
from datetime import datetime
import secrets

app = app_module.app
print('CWD:', os.getcwd())
print('DB URI:', app.config['SQLALCHEMY_DATABASE_URI'])

with app.app_context():
    try:
        db.drop_all()
    except Exception as e:
        print('drop_all warning:', e)
    db.create_all()
    u = User(username='demo', email='demo@example.com', phone_number='07000000001', first_name='Demo', last_name='User')
    demo_password = (os.environ.get('DEMO_PASSWORD') or '').strip()
    generated = False
    if not demo_password:
        demo_password = secrets.token_urlsafe(12)
        generated = True
    u.set_password(demo_password)
    db.session.add(u)
    db.session.commit()
    if generated:
        print('DEMO_PASSWORD (generated):', demo_password)
    cars = [
        dict(brand='toyota', model='camry', year=2020, mileage=25000, engine_type='gasoline', transmission='automatic', drive_type='fwd', condition='used', body_type='sedan', price=21000.0, location='baghdad'),
        dict(brand='bmw', model='x5', year=2021, mileage=15000, engine_type='gasoline', transmission='automatic', drive_type='awd', condition='used', body_type='suv', price=55000.0, location='erbil'),
    ]
    for s in cars:
        db.session.add(Car(seller_id=u.id, **s))
    db.session.commit()
print('RESET_SEEDED_OK')
