"""
Add car_image.kind for listing vs damage/crash disclosure photos (SQLite).

Run from repo root: python migrate_car_image_kind.py

Imports must use the `kk` package (not `sys.path` + `import app_new`) so
`kk/app_new.py` relative imports like `from .app_factory` resolve correctly.
"""
import sys
from pathlib import Path

_ROOT = Path(__file__).resolve().parent
if str(_ROOT) not in sys.path:
    sys.path.insert(0, str(_ROOT))

from kk.app_new import app  # noqa: E402
from kk.models import db  # noqa: E402
from sqlalchemy import text  # noqa: E402


def add_col(conn, table, col, typ):
    cols = {row[1] for row in conn.execute(text(f"PRAGMA table_info({table})"))}
    if col not in cols:
        conn.execute(text(f'ALTER TABLE {table} ADD COLUMN "{col}" {typ}'))
        return True
    return False


def run():
    with app.app_context():
        db.create_all()
        eng = db.engine
        with eng.connect() as conn:
            changed = add_col(conn, "car_image", "kind", "TEXT DEFAULT 'listing'")
            conn.commit()
            print("MIGRATE_CAR_IMAGE_KIND_OK" if changed else "MIGRATE_CAR_IMAGE_KIND_SKIP")


if __name__ == "__main__":
    run()
