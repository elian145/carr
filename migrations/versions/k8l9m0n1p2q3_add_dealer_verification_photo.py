"""add private dealer verification photo

Revision ID: k8l9m0n1p2q3
Revises: j7k8l9m0n1p2
Create Date: 2026-07-18
"""

from __future__ import annotations

from alembic import op
import sqlalchemy as sa


revision = "k8l9m0n1p2q3"
down_revision = "j7k8l9m0n1p2"
branch_labels = None
depends_on = None


def _columns(conn, table: str) -> set[str]:
    try:
        return {column["name"] for column in sa.inspect(conn).get_columns(table)}
    except Exception:
        return set()


def upgrade() -> None:
    conn = op.get_bind()
    columns = _columns(conn, "dealer_application")
    if not columns or "verification_photo_filename" in columns:
        return
    with op.batch_alter_table("dealer_application", schema=None) as batch_op:
        batch_op.add_column(
            sa.Column(
                "verification_photo_filename",
                sa.String(length=255),
                nullable=True,
            )
        )


def downgrade() -> None:
    conn = op.get_bind()
    columns = _columns(conn, "dealer_application")
    if "verification_photo_filename" not in columns:
        return
    with op.batch_alter_table("dealer_application", schema=None) as batch_op:
        batch_op.drop_column("verification_photo_filename")
