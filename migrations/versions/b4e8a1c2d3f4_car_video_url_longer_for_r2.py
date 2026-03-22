"""Widen car_video.video_url for full R2/CDN HTTPS URLs

Revision ID: b4e8a1c2d3f4
Revises: 9b2d7f3c1e4a
Create Date: 2026-03-21

"""

from alembic import op
import sqlalchemy as sa


revision = "b4e8a1c2d3f4"
down_revision = "9b2d7f3c1e4a"
branch_labels = None
depends_on = None


def upgrade() -> None:
    with op.batch_alter_table("car_video") as batch_op:
        batch_op.alter_column(
            "video_url",
            existing_type=sa.String(length=200),
            type_=sa.String(length=2048),
            existing_nullable=False,
        )
        batch_op.alter_column(
            "thumbnail_url",
            existing_type=sa.String(length=200),
            type_=sa.String(length=2048),
            existing_nullable=True,
        )


def downgrade() -> None:
    with op.batch_alter_table("car_video") as batch_op:
        batch_op.alter_column(
            "thumbnail_url",
            existing_type=sa.String(length=2048),
            type_=sa.String(length=200),
            existing_nullable=True,
        )
        batch_op.alter_column(
            "video_url",
            existing_type=sa.String(length=2048),
            type_=sa.String(length=200),
            existing_nullable=False,
        )
