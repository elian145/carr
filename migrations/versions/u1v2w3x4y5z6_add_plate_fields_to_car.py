"""add plate type and city to car

Revision ID: u1v2w3x4y5z6
Revises: t1u2v3w4x5y6
Create Date: 2026-04-23
"""

from alembic import op
import sqlalchemy as sa


revision = "u1v2w3x4y5z6"
down_revision = "t1u2v3w4x5y6"
branch_labels = None
depends_on = None


def upgrade() -> None:
    with op.batch_alter_table("car") as batch_op:
        batch_op.add_column(sa.Column("plate_type", sa.String(length=20), nullable=True))
        batch_op.add_column(sa.Column("plate_city", sa.String(length=50), nullable=True))
        batch_op.create_index("ix_car_plate_type", ["plate_type"])
        batch_op.create_index("ix_car_plate_city", ["plate_city"])


def downgrade() -> None:
    with op.batch_alter_table("car") as batch_op:
        batch_op.drop_index("ix_car_plate_city")
        batch_op.drop_index("ix_car_plate_type")
        batch_op.drop_column("plate_city")
        batch_op.drop_column("plate_type")

