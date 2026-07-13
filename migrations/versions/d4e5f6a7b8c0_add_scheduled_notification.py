"""add scheduled_notification table

Revision ID: d4e5f6a7b8c0
Revises: c3d4e5f6a7b8
Create Date: 2026-07-13
"""

from __future__ import annotations

from alembic import op
import sqlalchemy as sa


revision = "d4e5f6a7b8c0"
down_revision = "c3d4e5f6a7b8"
branch_labels = None
depends_on = None


def upgrade():
    op.create_table(
        "scheduled_notification",
        sa.Column("id", sa.Integer(), nullable=False),
        sa.Column("title", sa.String(length=200), nullable=False),
        sa.Column("message", sa.Text(), nullable=False),
        sa.Column("audience", sa.String(length=20), nullable=False, server_default="all"),
        sa.Column("target_user_public_id", sa.String(length=50), nullable=True),
        sa.Column("notification_type", sa.String(length=50), nullable=False, server_default="admin"),
        sa.Column("send_push", sa.Boolean(), nullable=False, server_default=sa.true()),
        sa.Column("scheduled_at", sa.DateTime(), nullable=False),
        sa.Column("status", sa.String(length=20), nullable=False, server_default="pending"),
        sa.Column("result", sa.JSON(), nullable=True),
        sa.Column("error_message", sa.Text(), nullable=True),
        sa.Column("created_by_user_id", sa.Integer(), nullable=True),
        sa.Column("created_at", sa.DateTime(), nullable=True),
        sa.Column("updated_at", sa.DateTime(), nullable=True),
        sa.Column("sent_at", sa.DateTime(), nullable=True),
        sa.ForeignKeyConstraint(["created_by_user_id"], ["user.id"]),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index("ix_scheduled_notification_scheduled_at", "scheduled_notification", ["scheduled_at"])
    op.create_index("ix_scheduled_notification_status", "scheduled_notification", ["status"])


def downgrade():
    op.drop_index("ix_scheduled_notification_status", table_name="scheduled_notification")
    op.drop_index("ix_scheduled_notification_scheduled_at", table_name="scheduled_notification")
    op.drop_table("scheduled_notification")
