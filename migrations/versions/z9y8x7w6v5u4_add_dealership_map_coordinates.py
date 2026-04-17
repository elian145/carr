"""add dealership map coordinates

Revision ID: z9y8x7w6v5u4
Revises: p4q5r6s7t8u9
Create Date: 2026-04-17
"""

from __future__ import annotations

import sqlalchemy as sa
from alembic import op

revision = "z9y8x7w6v5u4"
down_revision = "p4q5r6s7t8u9"
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
        if "dealership_latitude" not in user_cols:
            batch_op.add_column(sa.Column("dealership_latitude", sa.Float(), nullable=True))
        if "dealership_longitude" not in user_cols:
            batch_op.add_column(sa.Column("dealership_longitude", sa.Float(), nullable=True))


def downgrade() -> None:
    conn = op.get_bind()
    if not _has_table(conn, "user"):
        return
    user_cols = _cols(conn, "user")
    with op.batch_alter_table("user", schema=None) as batch_op:
        if "dealership_longitude" in user_cols:
            batch_op.drop_column("dealership_longitude")
        if "dealership_latitude" in user_cols:
            batch_op.drop_column("dealership_latitude")
