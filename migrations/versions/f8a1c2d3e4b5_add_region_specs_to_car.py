"""add region_specs column to car

Revision ID: f8a1c2d3e4b5
Revises: d4e5f6a7b8c9
Create Date: 2026-04-13
"""

from alembic import op
import sqlalchemy as sa


revision = "f8a1c2d3e4b5"
down_revision = "d4e5f6a7b8c9"
branch_labels = None
depends_on = None


def upgrade() -> None:
    with op.batch_alter_table("car") as batch_op:
        batch_op.add_column(sa.Column("region_specs", sa.String(length=20), nullable=True))


def downgrade() -> None:
    with op.batch_alter_table("car") as batch_op:
        batch_op.drop_column("region_specs")
