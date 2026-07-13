"""add app_setting table for admin-editable platform config

Revision ID: a1b2c3d4e5f6
Revises: h4i5j6k7l8m9
Create Date: 2026-07-13
"""

from __future__ import annotations

from alembic import op
import sqlalchemy as sa


revision = "a1b2c3d4e5f6"
down_revision = "h4i5j6k7l8m9"
branch_labels = None
depends_on = None


def upgrade():
    op.create_table(
        "app_setting",
        sa.Column("id", sa.Integer(), nullable=False),
        sa.Column("key", sa.String(length=64), nullable=False),
        sa.Column("value", sa.JSON(), nullable=False),
        sa.Column("updated_at", sa.DateTime(), nullable=True),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("key"),
    )
    op.create_index("ix_app_setting_key", "app_setting", ["key"])


def downgrade():
    op.drop_index("ix_app_setting_key", table_name="app_setting")
    op.drop_table("app_setting")
