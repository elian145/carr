"""Add car_image metadata columns and primary flags (legacy SQLite)."""
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
            add_col(conn, "car_image", "is_primary", "BOOLEAN DEFAULT 0")
            add_col(conn, "car_image", "order", "INTEGER DEFAULT 0")
            add_col(conn, "car_image", "created_at", "DATETIME")
            conn.execute(
                text(
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
                )
            )
            conn.commit()
            print("MIGRATE_CAR_IMAGE_OK")


if __name__ == "__main__":
    run()
