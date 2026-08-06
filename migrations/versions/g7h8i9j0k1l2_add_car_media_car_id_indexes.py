"""Add indexes on car_image.car_id and car_video.car_id

Revision ID: g7h8i9j0k1l2
Revises: f1a2b3c4d5e6
Create Date: 2026-08-06
"""

from __future__ import annotations

import sqlalchemy as sa
from alembic import op


revision = "g7h8i9j0k1l2"
down_revision = "f1a2b3c4d5e6"
branch_labels = None
depends_on = None


def upgrade() -> None:
    conn = op.get_bind()
    inspector = sa.inspect(conn)

    def _has_index(table: str, name: str) -> bool:
        if not inspector.has_table(table):
            return False
        return any(idx.get("name") == name for idx in inspector.get_indexes(table))

    if inspector.has_table("car_image") and not _has_index("car_image", "ix_car_image_car_id"):
        op.create_index("ix_car_image_car_id", "car_image", ["car_id"], unique=False)
    if inspector.has_table("car_video") and not _has_index("car_video", "ix_car_video_car_id"):
        op.create_index("ix_car_video_car_id", "car_video", ["car_id"], unique=False)


def downgrade() -> None:
    conn = op.get_bind()
    inspector = sa.inspect(conn)

    def _has_index(table: str, name: str) -> bool:
        if not inspector.has_table(table):
            return False
        return any(idx.get("name") == name for idx in inspector.get_indexes(table))

    if _has_index("car_video", "ix_car_video_car_id"):
        op.drop_index("ix_car_video_car_id", table_name="car_video")
    if _has_index("car_image", "ix_car_image_car_id"):
        op.drop_index("ix_car_image_car_id", table_name="car_image")
