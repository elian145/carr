"""Copy legacy car.image_url into car_image rows (legacy SQLite)."""
from __future__ import annotations

import sys
from pathlib import Path

_REPO_ROOT = Path(__file__).resolve().parents[2]
if str(_REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(_REPO_ROOT))

from kk.app_new import app  # noqa: E402
from kk.models import db  # noqa: E402
from sqlalchemy import text  # noqa: E402


def normalize_path(path: str) -> str:
    if not path:
        return path
    p = path.strip()
    while p.startswith("/"):
        p = p[1:]
    if p.startswith("static/"):
        p = p[len("static/") :]
    return p


def run():
    with app.app_context():
        eng = db.engine
        with eng.connect() as conn:
            db.create_all()
            car_cols = {row[1] for row in conn.execute(text("PRAGMA table_info(car)"))}
            if "image_url" not in car_cols:
                print("NO_LEGACY_IMAGE_URL")
                return

            total_with_legacy = conn.execute(
                text(
                    "SELECT COUNT(*) FROM car WHERE image_url IS NOT NULL AND image_url <> ''"
                )
            ).scalar()
            print("CARS_WITH_LEGACY_IMAGE", int(total_with_legacy or 0))

            if not total_with_legacy:
                print("NOTHING_TO_BACKFILL")
                return

            rows = conn.execute(
                text(
                    """
                    SELECT c.id, c.image_url
                    FROM car c
                    LEFT JOIN (
                        SELECT car_id, COUNT(*) AS cnt FROM car_image GROUP BY car_id
                    ) ci ON ci.car_id = c.id
                    WHERE (c.image_url IS NOT NULL AND c.image_url <> '')
                      AND (ci.cnt IS NULL OR ci.cnt = 0)
                    """
                )
            )
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
            print("BACKFILL_IMAGES_INSERTED", inserted)


if __name__ == "__main__":
    run()
