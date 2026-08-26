"""add dealership social media links

Revision ID: a3b4c5d6e7f8
Revises: g7h8i9j0k1l2
Create Date: 2026-08-26
"""

from __future__ import annotations

import sqlalchemy as sa
from alembic import op


revision = "a3b4c5d6e7f8"
down_revision = "g7h8i9j0k1l2"
branch_labels = None
depends_on = None


def upgrade() -> None:
    conn = op.get_bind()
    inspector = sa.inspect(conn)

    if inspector.has_table("user"):
        columns = {column["name"] for column in inspector.get_columns("user")}
        if "dealership_socials" not in columns:
            with op.batch_alter_table("user", schema=None) as batch_op:
                batch_op.add_column(sa.Column("dealership_socials", sa.JSON(), nullable=True))

    if inspector.has_table("dealer_profile"):
        columns = {
            column["name"] for column in inspector.get_columns("dealer_profile")
        }
        if "dealership_socials" not in columns:
            with op.batch_alter_table("dealer_profile", schema=None) as batch_op:
                batch_op.add_column(sa.Column("dealership_socials", sa.JSON(), nullable=True))


def downgrade() -> None:
    conn = op.get_bind()
    inspector = sa.inspect(conn)

    if inspector.has_table("dealer_profile"):
        columns = {
            column["name"] for column in inspector.get_columns("dealer_profile")
        }
        if "dealership_socials" in columns:
            with op.batch_alter_table("dealer_profile", schema=None) as batch_op:
                batch_op.drop_column("dealership_socials")

    if inspector.has_table("user"):
        columns = {column["name"] for column in inspector.get_columns("user")}
        if "dealership_socials" in columns:
            with op.batch_alter_table("user", schema=None) as batch_op:
                batch_op.drop_column("dealership_socials")
