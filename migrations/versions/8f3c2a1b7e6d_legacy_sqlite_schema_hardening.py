"""legacy sqlite schema hardening

Revision ID: 8f3c2a1b7e6d
Revises: 7c9a1d2f4a0b
Create Date: 2026-02-13

This migration exists to help upgrade older SQLite databases that predate the
current SQLAlchemy models / initial Alembic migration.

It is intentionally defensive and idempotent-ish:
- Only applies changes when columns are missing / constraints are stricter.
- Uses batch operations for SQLite compatibility.
"""

from __future__ import annotations

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision = "8f3c2a1b7e6d"
down_revision = "7c9a1d2f4a0b"
branch_labels = None
depends_on = None


def _has_table(conn, name: str) -> bool:
    try:
        insp = sa.inspect(conn)
        return bool(insp.has_table(name))
    except Exception:
        return False


def _cols(conn, table: str) -> set[str]:
    try:
        insp = sa.inspect(conn)
        return {c["name"] for c in insp.get_columns(table)}
    except Exception:
        return set()


def upgrade():
    conn = op.get_bind()

    # --- user table ---
    if _has_table(conn, "user"):
        user_cols = _cols(conn, "user")

        # 1) Ensure password_hash exists (some legacy DBs only have `password`)
        if "password_hash" not in user_cols:
            with op.batch_alter_table("user", schema=None) as batch_op:
                batch_op.add_column(sa.Column("password_hash", sa.String(length=128), nullable=True))
            # Best-effort backfill: assume legacy `password` already stores a bcrypt hash.
            try:
                op.execute("UPDATE user SET password_hash = COALESCE(password_hash, password)")
            except Exception:
                pass

        # 2) Make email nullable (some legacy DBs had NOT NULL + UNIQUE)
        # SQLite requires batch mode to change nullability.
        if "email" in user_cols:
            try:
                with op.batch_alter_table("user", schema=None) as batch_op:
                    batch_op.alter_column(
                        "email",
                        existing_type=sa.String(length=120),
                        nullable=True,
                    )
            except Exception:
                # Best-effort: if the DB can't be altered (locked/corrupt), do not brick upgrades.
                pass

    # --- car table ---
    if _has_table(conn, "car"):
        car_cols = _cols(conn, "car")
        if "views_count" not in car_cols:
            with op.batch_alter_table("car", schema=None) as batch_op:
                batch_op.add_column(sa.Column("views_count", sa.Integer(), nullable=True))
            try:
                # Some legacy DBs used `views` instead.
                if "views" in car_cols:
                    op.execute("UPDATE car SET views_count = COALESCE(views_count, views)")
            except Exception:
                pass


def downgrade():
    # Safe no-op downgrade: do not drop columns on legacy DBs.
    pass

