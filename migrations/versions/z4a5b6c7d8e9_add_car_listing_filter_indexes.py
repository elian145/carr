"""add composite indexes for car listing filters

Revision ID: z4a5b6c7d8e9
Revises: y2z3a4b5c6d7
Create Date: 2026-07-21

Public browse queries always filter ``is_active`` (+ status) and commonly
combine brand/price/year/location with ``created_at`` / ``is_featured`` sorts.
Single-column indexes alone force wide scans at scale.
"""

from __future__ import annotations

import sqlalchemy as sa
from alembic import op


revision = "z4a5b6c7d8e9"
down_revision = "y2z3a4b5c6d7"
branch_labels = None
depends_on = None

_INDEXES: tuple[tuple[str, list[str]], ...] = (
    ("ix_car_active_status_created_at", ["is_active", "status", "created_at"]),
    ("ix_car_active_brand_price", ["is_active", "brand", "price"]),
    ("ix_car_active_location_created_at", ["is_active", "location", "created_at"]),
    ("ix_car_active_year_price", ["is_active", "year", "price"]),
    ("ix_car_active_featured_created_at", ["is_active", "is_featured", "created_at"]),
    ("ix_car_seller_active_created_at", ["seller_id", "is_active", "created_at"]),
)


def upgrade() -> None:
    conn = op.get_bind()
    inspector = sa.inspect(conn)
    if not inspector.has_table("car"):
        return
    existing = {ix["name"] for ix in inspector.get_indexes("car")}
    with op.batch_alter_table("car", schema=None) as batch_op:
        for name, cols in _INDEXES:
            if name in existing:
                continue
            batch_op.create_index(name, cols, unique=False)


def downgrade() -> None:
    conn = op.get_bind()
    inspector = sa.inspect(conn)
    if not inspector.has_table("car"):
        return
    existing = {ix["name"] for ix in inspector.get_indexes("car")}
    with op.batch_alter_table("car", schema=None) as batch_op:
        for name, _cols in reversed(_INDEXES):
            if name in existing:
                batch_op.drop_index(name)
