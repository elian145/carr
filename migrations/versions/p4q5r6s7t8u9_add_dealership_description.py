"""add dealership_description to user

Revision ID: p4q5r6s7t8u9
Revises: n7o8p9q1r2s3
Create Date: 2026-04-16
"""

from __future__ import annotations

from alembic import op
import sqlalchemy as sa


revision = "p4q5r6s7t8u9"
down_revision = "n7o8p9q1r2s3"
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
        if "dealership_description" not in user_cols:
            batch_op.add_column(sa.Column("dealership_description", sa.Text(), nullable=True))


def downgrade() -> None:
    conn = op.get_bind()
    if not _has_table(conn, "user"):
        return
    user_cols = _cols(conn, "user")
    with op.batch_alter_table("user", schema=None) as batch_op:
        if "dealership_description" in user_cols:
            batch_op.drop_column("dealership_description")
