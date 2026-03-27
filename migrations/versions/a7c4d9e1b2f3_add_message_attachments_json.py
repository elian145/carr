"""add attachments json to message

Revision ID: a7c4d9e1b2f3
Revises: e1b2c3d4f5a6
Create Date: 2026-03-27

"""

from alembic import op
import sqlalchemy as sa


revision = "a7c4d9e1b2f3"
down_revision = "e1b2c3d4f5a6"
branch_labels = None
depends_on = None


def upgrade():
    try:
        op.add_column("message", sa.Column("attachments", sa.JSON(), nullable=True))
    except Exception:
        pass


def downgrade():
    try:
        op.drop_column("message", "attachments")
    except Exception:
        pass
