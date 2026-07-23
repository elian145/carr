"""add listing contact phones and verified contact phones

Revision ID: c8d9e0f1a2b3
Revises: b7c8d9e0f1a2
Create Date: 2026-07-23
"""

from __future__ import annotations

import sqlalchemy as sa
from alembic import op


revision = "c8d9e0f1a2b3"
down_revision = "b7c8d9e0f1a2"
branch_labels = None
depends_on = None


def upgrade() -> None:
    conn = op.get_bind()
    inspector = sa.inspect(conn)

    if inspector.has_table("user"):
        user_cols = {column["name"] for column in inspector.get_columns("user")}
        if "contact_verified_phones" not in user_cols:
            with op.batch_alter_table("user", schema=None) as batch_op:
                batch_op.add_column(
                    sa.Column("contact_verified_phones", sa.JSON(), nullable=True)
                )

    if inspector.has_table("car"):
        car_cols = {column["name"] for column in inspector.get_columns("car")}
        with op.batch_alter_table("car", schema=None) as batch_op:
            if "contact_phone" not in car_cols:
                batch_op.add_column(
                    sa.Column("contact_phone", sa.String(length=20), nullable=True)
                )
            if "contact_phones" not in car_cols:
                batch_op.add_column(
                    sa.Column("contact_phones", sa.JSON(), nullable=True)
                )


def downgrade() -> None:
    conn = op.get_bind()
    inspector = sa.inspect(conn)

    if inspector.has_table("car"):
        car_cols = {column["name"] for column in inspector.get_columns("car")}
        with op.batch_alter_table("car", schema=None) as batch_op:
            if "contact_phones" in car_cols:
                batch_op.drop_column("contact_phones")
            if "contact_phone" in car_cols:
                batch_op.drop_column("contact_phone")

    if inspector.has_table("user"):
        user_cols = {column["name"] for column in inspector.get_columns("user")}
        if "contact_verified_phones" in user_cols:
            with op.batch_alter_table("user", schema=None) as batch_op:
                batch_op.drop_column("contact_verified_phones")
