"""car_media_item: server-owned cover + display order.

Revision ID: t8u9v0w1x2y3
Revises: s7t8u9v0w1x2
Create Date: 2026-10-16

The seller's starred cover photo (and photo order) used to live only in the
Flutter client, so the backend's self-attach (`attach_processed_car_image`)
made the cover whichever photo finished processing first. The create-time
`expected_media` manifest now declares the choice and it is stored on the
manifest row:

- ``car_media_item.sort_order`` (nullable INTEGER): display position the
  seller chose (cover first). NULL = not declared (every existing row).
- ``car_media_item.is_cover`` (BOOLEAN NOT NULL, server_default false): the
  seller's cover. Every existing row reads false, which keeps the legacy
  "first attached image is the cover" behavior for them.

Both additions are nullable/defaulted, so no backfill is required and the
migration is safe on SQLite and PostgreSQL.
"""

from __future__ import annotations

import sqlalchemy as sa
from alembic import op

# revision identifiers, used by Alembic.
revision = "t8u9v0w1x2y3"
down_revision = "s7t8u9v0w1x2"
branch_labels = None
depends_on = None


def upgrade() -> None:
    with op.batch_alter_table("car_media_item", schema=None) as batch_op:
        batch_op.add_column(sa.Column("sort_order", sa.Integer(), nullable=True))
        batch_op.add_column(
            sa.Column(
                "is_cover",
                sa.Boolean(),
                nullable=False,
                server_default=sa.false(),
            )
        )


def downgrade() -> None:
    with op.batch_alter_table("car_media_item", schema=None) as batch_op:
        batch_op.drop_column("is_cover")
        batch_op.drop_column("sort_order")
