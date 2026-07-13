"""add admin_role to user for RBAC

Revision ID: b2c3d4e5f6a7
Revises: a1b2c3d4e5f6
Create Date: 2026-07-13
"""

from __future__ import annotations

from alembic import op
import sqlalchemy as sa


revision = "b2c3d4e5f6a7"
down_revision = "a1b2c3d4e5f6"
branch_labels = None
depends_on = None


def upgrade():
    with op.batch_alter_table("user") as batch:
        batch.add_column(sa.Column("admin_role", sa.String(length=32), nullable=True))


def downgrade():
    with op.batch_alter_table("user") as batch:
        batch.drop_column("admin_role")
