"""Backfill car.seller_id and optional public_id columns (legacy SQLite)."""
from __future__ import annotations

import sys
from pathlib import Path

_REPO_ROOT = Path(__file__).resolve().parents[2]
if str(_REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(_REPO_ROOT))

from kk.app_new import app  # noqa: E402
from kk.models import db  # noqa: E402
from sqlalchemy import text  # noqa: E402


def run():
    with app.app_context():
        eng = db.engine
        with eng.connect() as conn:
            cols = {row[1] for row in conn.execute(text("PRAGMA table_info(car)"))}
            if "seller_id" not in cols:
                conn.execute(text("ALTER TABLE car ADD COLUMN seller_id INTEGER"))

            cols = {row[1] for row in conn.execute(text("PRAGMA table_info(car)"))}
            for legacy in ("user_id", "seller", "owner_id"):
                if legacy in cols:
                    conn.execute(
                        text(
                            f"UPDATE car SET seller_id = {legacy} WHERE seller_id IS NULL"
                        )
                    )
                    break
            else:
                conn.execute(
                    text(
                        "UPDATE car SET seller_id = (SELECT id FROM user ORDER BY id LIMIT 1) "
                        "WHERE seller_id IS NULL"
                    )
                )

            cols_car = {row[1] for row in conn.execute(text("PRAGMA table_info(car)"))}
            if "public_id" not in cols_car:
                conn.execute(text("ALTER TABLE car ADD COLUMN public_id VARCHAR(50)"))
            cols_user = {row[1] for row in conn.execute(text("PRAGMA table_info(user)"))}
            if "public_id" not in cols_user:
                conn.execute(text("ALTER TABLE user ADD COLUMN public_id VARCHAR(50)"))

            conn.commit()
            print("MIGRATE_SELLER_ID_OK")


if __name__ == "__main__":
    run()
