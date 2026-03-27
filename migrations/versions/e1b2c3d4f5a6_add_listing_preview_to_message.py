"""add listing preview to message

Revision ID: e1b2c3d4f5a6
Revises: c5f3a2d1e8b7
Create Date: 2026-03-27

"""

from alembic import op
import sqlalchemy as sa


revision = "e1b2c3d4f5a6"
down_revision = "c5f3a2d1e8b7"
branch_labels = None
depends_on = None


def upgrade():
    try:
        op.add_column("message", sa.Column("listing_preview", sa.JSON(), nullable=True))
    except Exception:
        pass


def downgrade():
    try:
        op.drop_column("message", "listing_preview")
    except Exception:
        pass
