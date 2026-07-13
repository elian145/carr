"""add featured dealer + catalog_trim

Revision ID: e5f6a7b8c9d0
Revises: d4e5f6a7b8c0
Create Date: 2026-07-13
"""

from __future__ import annotations

from alembic import op
import sqlalchemy as sa


revision = "e5f6a7b8c9d0"
down_revision = "d4e5f6a7b8c0"
branch_labels = None
depends_on = None


def upgrade():
    with op.batch_alter_table("user") as batch:
        batch.add_column(
            sa.Column(
                "is_featured_dealer",
                sa.Boolean(),
                nullable=False,
                server_default=sa.false(),
            )
        )

    op.create_table(
        "catalog_trim",
        sa.Column("id", sa.Integer(), nullable=False),
        sa.Column("model_id", sa.Integer(), nullable=False),
        sa.Column("name", sa.String(length=120), nullable=False),
        sa.Column("is_active", sa.Boolean(), nullable=False, server_default=sa.true()),
        sa.Column("sort_order", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("created_at", sa.DateTime(), nullable=True),
        sa.Column("updated_at", sa.DateTime(), nullable=True),
        sa.ForeignKeyConstraint(["model_id"], ["catalog_vehicle_model.id"]),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("model_id", "name", name="uq_catalog_trim_model_name"),
    )
    op.create_index("ix_catalog_trim_model_id", "catalog_trim", ["model_id"])


def downgrade():
    op.drop_index("ix_catalog_trim_model_id", table_name="catalog_trim")
    op.drop_table("catalog_trim")
    with op.batch_alter_table("user") as batch:
        batch.drop_column("is_featured_dealer")
