"""add vehicle catalog tables (brand / model / body type)

Revision ID: c3d4e5f6a7b8
Revises: b2c3d4e5f6a7
Create Date: 2026-07-13
"""

from __future__ import annotations

from alembic import op
import sqlalchemy as sa


revision = "c3d4e5f6a7b8"
down_revision = "b2c3d4e5f6a7"
branch_labels = None
depends_on = None


def upgrade():
    op.create_table(
        "catalog_brand",
        sa.Column("id", sa.Integer(), nullable=False),
        sa.Column("name", sa.String(length=120), nullable=False),
        sa.Column("is_active", sa.Boolean(), nullable=False, server_default=sa.true()),
        sa.Column("sort_order", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("created_at", sa.DateTime(), nullable=True),
        sa.Column("updated_at", sa.DateTime(), nullable=True),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("name"),
    )
    op.create_index("ix_catalog_brand_name", "catalog_brand", ["name"])

    op.create_table(
        "catalog_vehicle_model",
        sa.Column("id", sa.Integer(), nullable=False),
        sa.Column("brand_id", sa.Integer(), nullable=False),
        sa.Column("name", sa.String(length=120), nullable=False),
        sa.Column("is_active", sa.Boolean(), nullable=False, server_default=sa.true()),
        sa.Column("sort_order", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("created_at", sa.DateTime(), nullable=True),
        sa.Column("updated_at", sa.DateTime(), nullable=True),
        sa.ForeignKeyConstraint(["brand_id"], ["catalog_brand.id"]),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("brand_id", "name", name="uq_catalog_model_brand_name"),
    )
    op.create_index("ix_catalog_vehicle_model_brand_id", "catalog_vehicle_model", ["brand_id"])
    op.create_index("ix_catalog_vehicle_model_name", "catalog_vehicle_model", ["name"])

    op.create_table(
        "catalog_body_type",
        sa.Column("id", sa.Integer(), nullable=False),
        sa.Column("name", sa.String(length=80), nullable=False),
        sa.Column("is_active", sa.Boolean(), nullable=False, server_default=sa.true()),
        sa.Column("sort_order", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("created_at", sa.DateTime(), nullable=True),
        sa.Column("updated_at", sa.DateTime(), nullable=True),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("name"),
    )
    op.create_index("ix_catalog_body_type_name", "catalog_body_type", ["name"])


def downgrade():
    op.drop_index("ix_catalog_body_type_name", table_name="catalog_body_type")
    op.drop_table("catalog_body_type")
    op.drop_index("ix_catalog_vehicle_model_name", table_name="catalog_vehicle_model")
    op.drop_index("ix_catalog_vehicle_model_brand_id", table_name="catalog_vehicle_model")
    op.drop_table("catalog_vehicle_model")
    op.drop_index("ix_catalog_brand_name", table_name="catalog_brand")
    op.drop_table("catalog_brand")
