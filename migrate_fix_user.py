import sys
sys.path.append('kk')

import app_new as app_module
from models import db
from sqlalchemy import text


def add_col(conn, table, col, typ):
	cols = {row[1] for row in conn.execute(text(f"PRAGMA table_info({table})"))}
	if col not in cols:
		conn.execute(text(f"ALTER TABLE {table} ADD COLUMN \"{col}\" {typ}"))
		return True
	return False


def run():
	app = app_module.app
	with app.app_context():
		db.create_all()
		eng = db.engine
		with eng.connect() as conn:
			changed = False
			changed |= add_col(conn, 'user', 'public_id', 'VARCHAR(50)')
			changed |= add_col(conn, 'user', 'username', 'VARCHAR(80)')
			changed |= add_col(conn, 'user', 'email', 'VARCHAR(120)')
			changed |= add_col(conn, 'user', 'password_hash', 'VARCHAR(128)')
			changed |= add_col(conn, 'user', 'phone_number', 'VARCHAR(20)')
			changed |= add_col(conn, 'user', 'first_name', 'VARCHAR(50)')
			changed |= add_col(conn, 'user', 'last_name', 'VARCHAR(50)')
			changed |= add_col(conn, 'user', 'profile_picture', 'VARCHAR(200)')
			changed |= add_col(conn, 'user', 'is_verified', 'BOOLEAN DEFAULT 0')
			changed |= add_col(conn, 'user', 'is_active', 'BOOLEAN DEFAULT 1')
			changed |= add_col(conn, 'user', 'is_admin', 'BOOLEAN DEFAULT 0')
			changed |= add_col(conn, 'user', 'created_at', 'DATETIME')
			changed |= add_col(conn, 'user', 'updated_at', 'DATETIME')
			changed |= add_col(conn, 'user', 'last_login', 'DATETIME')
			changed |= add_col(conn, 'user', 'firebase_token', 'TEXT')

			# Backfill minimal sensible defaults
			# Ensure password_hash non-null: set to placeholder where missing
			conn.execute(text("UPDATE user SET password_hash = COALESCE(NULLIF(password_hash,''), 'x')"))
			# Username fallback from email or phone or generated
			conn.execute(text("UPDATE user SET username = COALESCE(NULLIF(username,''), COALESCE(NULLIF(email,''), COALESCE(NULLIF(phone_number,''), 'user')))"))
			# Active default true
			conn.execute(text("UPDATE user SET is_active = COALESCE(is_active, 1)"))
			# Timestamps
			conn.execute(text("UPDATE user SET created_at = COALESCE(created_at, CURRENT_TIMESTAMP)"))
			# Backfill public_id where empty
			ids = [r[0] for r in conn.execute(text("SELECT id FROM user WHERE public_id IS NULL OR public_id = ''"))]
			for rid in ids:
				from uuid import uuid4
				conn.execute(text("UPDATE user SET public_id = :pid WHERE id = :rid"), {"pid": str(uuid4()), "rid": rid})
			conn.commit()
			print('MIGRATE_USER_OK')


if __name__ == '__main__':
	run()
