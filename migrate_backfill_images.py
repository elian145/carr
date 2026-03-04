import sys
import os
sys.path.append('kk')

import app_new as app_module
from models import db
from sqlalchemy import text


def normalize_path(path: str) -> str:
    if not path:
        return path
    p = path.strip()
    # Remove leading slashes
    while p.startswith('/'):
        p = p[1:]
    # Strip leading 'static/' if present
    if p.startswith('static/'):
        p = p[len('static/'):]
    # Many legacy values may already be like 'uploads/car_photos/...' – keep as is
    return p


def run():
    app = app_module.app
    with app.app_context():
        eng = db.engine
        with eng.connect() as conn:
            # Ensure car_image table exists by letting SQLAlchemy create missing tables
            db.create_all()

            # Check if legacy column exists
            car_cols = {row[1] for row in conn.execute(text('PRAGMA table_info(car)'))}
            if 'image_url' not in car_cols:
                print('NO_LEGACY_IMAGE_URL')
                return

            # Count cars with legacy image_url
            total_with_legacy = conn.execute(text("SELECT COUNT(*) FROM car WHERE image_url IS NOT NULL AND image_url <> ''")).scalar()
            print('CARS_WITH_LEGACY_IMAGE', int(total_with_legacy or 0))

            if not total_with_legacy:
                print('NOTHING_TO_BACKFILL')
                return

            # For each car with legacy image_url and no existing car_image rows, create one primary image
            rows = conn.execute(text(
                """
                SELECT c.id, c.image_url
                FROM car c
                LEFT JOIN (
                    SELECT car_id, COUNT(*) AS cnt FROM car_image GROUP BY car_id
                ) ci ON ci.car_id = c.id
                WHERE (c.image_url IS NOT NULL AND c.image_url <> '')
                  AND (ci.cnt IS NULL OR ci.cnt = 0)
                """
            ))
            to_insert = [(r[0], normalize_path(r[1])) for r in rows]

            inserted = 0
            for car_id, rel_path in to_insert:
                if not rel_path:
                    continue
                conn.execute(
                    text(
                        "INSERT INTO car_image (car_id, image_url, is_primary, "
                        "order, created_at) VALUES (:cid, :img, 1, 0, CURRENT_TIMESTAMP)"
                    ),
                    {"cid": car_id, "img": rel_path},
                )
                inserted += 1

            conn.commit()
            print('BACKFILL_IMAGES_INSERTED', inserted)


if __name__ == '__main__':
    run()


