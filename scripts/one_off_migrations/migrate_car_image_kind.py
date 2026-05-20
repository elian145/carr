"""Add car_image.kind for listing vs damage photos (legacy SQLite)."""
from __future__ import annotations

import sys
from pathlib import Path

_REPO_ROOT = Path(__file__).resolve().parents[2]
if str(_REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(_REPO_ROOT))

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
