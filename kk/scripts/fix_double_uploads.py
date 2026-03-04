import os
import sys
from sqlalchemy import text

sys.path.append(os.path.dirname(__file__) + '/..')

import app_new as app_module  # type: ignore
from models import db  # type: ignore


def main() -> None:
	app = app_module.app
	with app.app_context():
		db.create_all()
		engine = db.engine
		moved = 0
		updated = 0
		with engine.connect() as conn:
			rows = list(conn.execute(text("SELECT id, image_url FROM car_image")))
			for cid, rel in rows:
				if not rel:
					continue
				rel = rel.strip().lstrip('/')
				# Normalize leading 'static/'
				if rel.startswith('static/'):
					rel = rel[len('static/'):]
				src_rel = rel
				# Fix double 'uploads/uploads/...'
				if rel.startswith('uploads/uploads/'):
					rel = rel[len('uploads/'):]
				# Paths on disk
				src_abs = os.path.join('static', src_rel).replace('\\', '/')
				dst_abs = os.path.join('static', rel).replace('\\', '/')
				# Move file if it exists only at src_abs
				if src_abs != dst_abs and os.path.exists(src_abs) and not os.path.exists(dst_abs):
					os.makedirs(os.path.dirname(dst_abs), exist_ok=True)
					try:
						import shutil
						shutil.move(src_abs, dst_abs)
						moved += 1
					except Exception:
						pass
				# Update DB if path changed
				if src_rel != rel:
					conn.execute(text("UPDATE car_image SET image_url = :p WHERE id = :id"), {"p": rel, "id": cid})
					updated += 1
			conn.commit()
		print(f"FIX_DOUBLE_UPLOADS moved={moved} updated={updated}")


if __name__ == '__main__':
	main()


