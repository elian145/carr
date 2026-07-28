"""Widen car_image.image_url for full R2/CDN HTTPS URLs

Revision ID: d9e0f1a2b3c4
Revises: c8d9e0f1a2b3
Create Date: 2026-07-29

"""

from __future__ import annotations

import sqlalchemy as sa
from alembic import op


revision = "d9e0f1a2b3c4"
down_revision = "c8d9e0f1a2b3"
branch_labels = None
depends_on = None


def upgrade() -> None:
    with op.batch_alter_table("car_image", schema=None) as batch_op:
        batch_op.alter_column(
            "image_url",
            existing_type=sa.String(length=200),
            type_=sa.String(length=2048),
            existing_nullable=False,
        )


def downgrade() -> None:
    with op.batch_alter_table("car_image", schema=None) as batch_op:
        batch_op.alter_column(
            "image_url",
            existing_type=sa.String(length=2048),
            type_=sa.String(length=200),
            existing_nullable=False,
        )
