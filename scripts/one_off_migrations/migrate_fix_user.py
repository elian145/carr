"""Backfill user table columns for legacy SQLite databases."""
from __future__ import annotations

import sys
from pathlib import Path
from uuid import uuid4

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
            add_col(conn, "user", "public_id", "VARCHAR(50)")
            add_col(conn, "user", "username", "VARCHAR(80)")
            add_col(conn, "user", "email", "VARCHAR(120)")
            add_col(conn, "user", "password_hash", "VARCHAR(128)")
            add_col(conn, "user", "phone_number", "VARCHAR(20)")
            add_col(conn, "user", "first_name", "VARCHAR(50)")
            add_col(conn, "user", "last_name", "VARCHAR(50)")
            add_col(conn, "user", "profile_picture", "VARCHAR(200)")
            add_col(conn, "user", "is_verified", "BOOLEAN DEFAULT 0")
            add_col(conn, "user", "is_active", "BOOLEAN DEFAULT 1")
            add_col(conn, "user", "is_admin", "BOOLEAN DEFAULT 0")
            add_col(conn, "user", "created_at", "DATETIME")
            add_col(conn, "user", "updated_at", "DATETIME")
            add_col(conn, "user", "last_login", "DATETIME")
            add_col(conn, "user", "firebase_token", "TEXT")

            conn.execute(
                text(
                    "UPDATE user SET password_hash = COALESCE(NULLIF(password_hash,''), 'x')"
                )
            )
            conn.execute(
                text(
                    "UPDATE user SET username = COALESCE(NULLIF(username,''), "
                    "COALESCE(NULLIF(email,''), COALESCE(NULLIF(phone_number,''), 'user')))"
                )
            )
            conn.execute(text("UPDATE user SET is_active = COALESCE(is_active, 1)"))
            conn.execute(
                text("UPDATE user SET created_at = COALESCE(created_at, CURRENT_TIMESTAMP)")
            )
            ids = [
                r[0]
                for r in conn.execute(
                    text("SELECT id FROM user WHERE public_id IS NULL OR public_id = ''")
                )
            ]
            for rid in ids:
                conn.execute(
                    text("UPDATE user SET public_id = :pid WHERE id = :rid"),
                    {"pid": str(uuid4()), "rid": rid},
                )
            conn.commit()
            print("MIGRATE_USER_OK")


if __name__ == "__main__":
    run()
