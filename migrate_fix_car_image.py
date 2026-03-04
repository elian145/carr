import sys
sys.path.append('kk')

import app_new as app_module
from models import db
from sqlalchemy import text


def add_col(conn, table, col, typ):
    cols = {row[1] for row in conn.execute(text(f"PRAGMA table_info({table})"))}
    if col not in cols:
        # Quote column name to support reserved identifiers like "order"
        conn.execute(text(f"ALTER TABLE {table} ADD COLUMN \"{col}\" {typ}"))
        return True
    return False


def run():
    app = app_module.app
    with app.app_context():
        # Ensure tables exist
        db.create_all()
        eng = db.engine
        with eng.connect() as conn:
            changed = False
            changed |= add_col(conn, 'car_image', 'is_primary', 'BOOLEAN DEFAULT 0')
            changed |= add_col(conn, 'car_image', 'order', 'INTEGER DEFAULT 0')
            changed |= add_col(conn, 'car_image', 'created_at', 'DATETIME')

            # Set a primary image per car if none flagged
            conn.execute(text(
                """
                UPDATE car_image
                SET is_primary = 1
                WHERE id IN (
                  SELECT id FROM (
                    SELECT MIN(id) AS id
                    FROM car_image
                    GROUP BY car_id
                  )
                ) AND (is_primary IS NULL OR is_primary = 0)
                """
            ))

            conn.commit()
            print('MIGRATE_CAR_IMAGE_OK')


if __name__ == '__main__':
    run()


