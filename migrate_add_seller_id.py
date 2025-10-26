import sys
sys.path.append('kk')

import app_new as app_module
from models import db
from sqlalchemy import text


def run():
    app = app_module.app
    with app.app_context():
        eng = db.engine
        with eng.connect() as conn:
            # Check existing columns
            cols = {row[1] for row in conn.execute(text("PRAGMA table_info(car)"))}
            if 'seller_id' not in cols:
                conn.execute(text('ALTER TABLE car ADD COLUMN seller_id INTEGER'))

            # Recompute columns after potential ALTER
            cols = {row[1] for row in conn.execute(text("PRAGMA table_info(car)"))}

            # Backfill from legacy columns if present
            for legacy in ('user_id', 'seller', 'owner_id'):
                if legacy in cols:
                    conn.execute(text(f'UPDATE car SET seller_id = {legacy} WHERE seller_id IS NULL'))
                    break
            else:
                # Fallback: set to first user id if available (keeps not-null semantics for new app)
                conn.execute(text('UPDATE car SET seller_id = (SELECT id FROM user ORDER BY id LIMIT 1) WHERE seller_id IS NULL'))

            # Optional: ensure public_id exists for car and user (compat with app)
            cols_car = {row[1] for row in conn.execute(text("PRAGMA table_info(car)"))}
            if 'public_id' not in cols_car:
                conn.execute(text('ALTER TABLE car ADD COLUMN public_id VARCHAR(50)'))
            cols_user = {row[1] for row in conn.execute(text("PRAGMA table_info(user)"))}
            if 'public_id' not in cols_user:
                conn.execute(text('ALTER TABLE user ADD COLUMN public_id VARCHAR(50)'))

            conn.commit()
            print('MIGRATE_SELLER_ID_OK')


if __name__ == '__main__':
    run()


