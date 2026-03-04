import sys
sys.path.append('kk')

import app_new as app_module
from models import db
from sqlalchemy import text


def add_col(conn, table: str, col: str, typ: str) -> bool:
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
            changed |= add_col(conn, 'car_video', 'thumbnail_url', 'VARCHAR(200)')
            changed |= add_col(conn, 'car_video', 'duration', 'INTEGER')
            changed |= add_col(conn, 'car_video', 'order', 'INTEGER DEFAULT 0')
            changed |= add_col(conn, 'car_video', 'created_at', 'DATETIME')

            conn.commit()
            print('MIGRATE_CAR_VIDEO_OK')


if __name__ == '__main__':
    run()

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
			changed |= add_col(conn, 'car_video', 'thumbnail_url', 'VARCHAR(200)')
			changed |= add_col(conn, 'car_video', 'duration', 'INTEGER')
			changed |= add_col(conn, 'car_video', 'order', 'INTEGER DEFAULT 0')
			changed |= add_col(conn, 'car_video', 'created_at', 'DATETIME')
			conn.commit()
			print('MIGRATE_CAR_VIDEO_OK')


if __name__ == '__main__':
	run()


