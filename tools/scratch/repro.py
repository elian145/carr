import sys, traceback
sys.path.append('kk')
from app_new import app
from models import db, Car

with app.app_context():
    try:
        page=1; per_page=20
        brand=model=location=condition=body_type=transmission=drive_type=engine_type=None
        year_min=year_max=price_min=price_max=None
        query = Car.query.filter_by(is_active=True)
        query = query.order_by(Car.is_featured.desc(), Car.created_at.desc())
        pagination = query.paginate(page=page, per_page=per_page, error_out=False)
        cars=[]
        for c in pagination.items:
            d = c.to_dict()
            d['id'] = c.id
            image_list = [img.image_url for img in c.images] if c.images else []
            primary_rel = image_list[0] if image_list else ''
            d['image_url'] = primary_rel
            d['images'] = image_list
            d['videos'] = [v.video_url for v in c.videos] if c.videos else []
            if not d.get('title'):
                d['title'] = f"{(c.brand or '').title()} {(c.model or '').title()} {c.year or ''}".strip()
            cars.append(d)
        print('OK', len(cars))
    except Exception as e:
        print('ERR', repr(e))
        traceback.print_exc()
