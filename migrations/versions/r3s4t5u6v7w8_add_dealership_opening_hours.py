"""add dealership_opening_hours to user

Revision ID: r3s4t5u6v7w8
Revises: z9y8x7w6v5u4
Create Date: 2026-04-18
"""

from __future__ import annotations

import sqlalchemy as sa
from alembic import op

revision = "r3s4t5u6v7w8"
down_revision = "z9y8x7w6v5u4"
branch_labels = None
depends_on = None


def _has_table(conn, name: str) -> bool:
    try:
        return bool(sa.inspect(conn).has_table(name))
    except Exception:
        return False


def _cols(conn, table: str) -> set[str]:
    try:
        return {c["name"] for c in sa.inspect(conn).get_columns(table)}
    except Exception:
        return set()


def upgrade() -> None:
    conn = op.get_bind()
    if not _has_table(conn, "user"):
        return
    user_cols = _cols(conn, "user")
    with op.batch_alter_table("user", schema=None) as batch_op:
        if "dealership_opening_hours" not in user_cols:
            batch_op.add_column(sa.Column("dealership_opening_hours", sa.JSON(), nullable=True))


def downgrade() -> None:
    conn = op.get_bind()
    if not _has_table(conn, "user"):
        return
    user_cols = _cols(conn, "user")
    with op.batch_alter_table("user", schema=None) as batch_op:
        if "dealership_opening_hours" in user_cols:
            batch_op.drop_column("dealership_opening_hours")

