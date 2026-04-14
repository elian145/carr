"""add damaged_parts column to car

Revision ID: g2h3i4j5k6l7
Revises: f8a1c2d3e4b5
Create Date: 2026-04-15
"""

from alembic import op
import sqlalchemy as sa


revision = "g2h3i4j5k6l7"
down_revision = "f8a1c2d3e4b5"
branch_labels = None
depends_on = None


def upgrade() -> None:
    with op.batch_alter_table("car") as batch_op:
        batch_op.add_column(sa.Column("damaged_parts", sa.Integer(), nullable=True))


def downgrade() -> None:
    with op.batch_alter_table("car") as batch_op:
        batch_op.drop_column("damaged_parts")
