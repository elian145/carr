"""add car_image.kind for listing vs damage photos

Revision ID: v8k9m0n1p2q3
Revises: u1v2w3x4y5z6
Create Date: 2026-05-14

PostgreSQL / production: required so ORM queries selecting CarImage.kind succeed.
"""

from __future__ import annotations

from alembic import op
import sqlalchemy as sa


revision = "v8k9m0n1p2q3"
down_revision = "u1v2w3x4y5z6"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column(
        "car_image",
        sa.Column(
            "kind",
            sa.String(length=20),
            nullable=False,
            server_default=sa.text("'listing'"),
        ),
    )


def downgrade() -> None:
    op.drop_column("car_image", "kind")
