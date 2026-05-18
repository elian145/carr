"""add saved searches and favorite price tracking for alerts

Revision ID: w1x2y3z4a5b6
Revises: v8k9m0n1p2q3
Create Date: 2026-05-17

"""

from alembic import op
import sqlalchemy as sa


revision = "w1x2y3z4a5b6"
down_revision = "v8k9m0n1p2q3"
branch_labels = None
depends_on = None


def upgrade():
    op.create_table(
        "saved_search",
        sa.Column("id", sa.Integer(), nullable=False),
        sa.Column("public_id", sa.String(length=50), nullable=True),
        sa.Column("user_id", sa.Integer(), nullable=False),
        sa.Column("name", sa.String(length=200), nullable=False),
        sa.Column("filters", sa.JSON(), nullable=True),
        sa.Column("notify", sa.Boolean(), nullable=False, server_default=sa.true()),
        sa.Column("auto_saved", sa.Boolean(), nullable=False, server_default=sa.false()),
        sa.Column("created_at", sa.DateTime(), nullable=True),
        sa.Column("updated_at", sa.DateTime(), nullable=True),
        sa.ForeignKeyConstraint(["user_id"], ["user.id"]),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("public_id"),
    )
    op.create_index("ix_saved_search_user_id", "saved_search", ["user_id"], unique=False)
    op.create_index("ix_saved_search_public_id", "saved_search", ["public_id"], unique=True)
    op.create_index("ix_saved_search_created_at", "saved_search", ["created_at"], unique=False)

    op.create_table(
        "saved_search_alert",
        sa.Column("id", sa.Integer(), nullable=False),
        sa.Column("saved_search_id", sa.Integer(), nullable=False),
        sa.Column("car_id", sa.Integer(), nullable=False),
        sa.Column("created_at", sa.DateTime(), nullable=True),
        sa.ForeignKeyConstraint(["car_id"], ["car.id"]),
        sa.ForeignKeyConstraint(["saved_search_id"], ["saved_search.id"]),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("saved_search_id", "car_id", name="uq_saved_search_alert"),
    )
    op.create_index(
        "ix_saved_search_alert_saved_search_id",
        "saved_search_alert",
        ["saved_search_id"],
        unique=False,
    )
    op.create_index("ix_saved_search_alert_car_id", "saved_search_alert", ["car_id"], unique=False)

    try:
        op.add_column(
            "user_favorites",
            sa.Column("price_at_favorite", sa.Float(), nullable=True),
        )
    except Exception:
        pass


def downgrade():
    try:
        op.drop_column("user_favorites", "price_at_favorite")
    except Exception:
        pass
    op.drop_index("ix_saved_search_alert_car_id", table_name="saved_search_alert")
    op.drop_index("ix_saved_search_alert_saved_search_id", table_name="saved_search_alert")
    op.drop_table("saved_search_alert")
    op.drop_index("ix_saved_search_created_at", table_name="saved_search")
    op.drop_index("ix_saved_search_public_id", table_name="saved_search")
    op.drop_index("ix_saved_search_user_id", table_name="saved_search")
    op.drop_table("saved_search")
