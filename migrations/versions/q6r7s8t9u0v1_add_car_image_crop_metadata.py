"""add car image crop metadata

Revision ID: q6r7s8t9u0v1
Revises: e5f6a7b8c9d0
Create Date: 2026-07-17
"""

from __future__ import annotations

from alembic import op
import sqlalchemy as sa


revision = "q6r7s8t9u0v1"
down_revision = "e5f6a7b8c9d0"
branch_labels = None
depends_on = None


def upgrade() -> None:
    with op.batch_alter_table("car_image", schema=None) as batch_op:
        batch_op.add_column(sa.Column("focus_y", sa.Float(), nullable=True))
        batch_op.add_column(sa.Column("image_width", sa.Integer(), nullable=True))
        batch_op.add_column(sa.Column("image_height", sa.Integer(), nullable=True))
        batch_op.create_check_constraint(
            "ck_car_image_focus_y_range",
            "focus_y IS NULL OR (focus_y >= 0.0 AND focus_y <= 1.0)",
        )


def downgrade() -> None:
    with op.batch_alter_table("car_image", schema=None) as batch_op:
        batch_op.drop_constraint("ck_car_image_focus_y_range", type_="check")
        batch_op.drop_column("image_height")
        batch_op.drop_column("image_width")
        batch_op.drop_column("focus_y")
