"""add chat attachments, block, and report tables

Revision ID: c5f3a2d1e8b7
Revises: b4e8a1c2d3f4
Create Date: 2026-03-27

"""

from alembic import op
import sqlalchemy as sa


revision = "c5f3a2d1e8b7"
down_revision = "b4e8a1c2d3f4"
branch_labels = None
depends_on = None


def upgrade():
    # Add attachment_url to message table.
    try:
        op.add_column("message", sa.Column("attachment_url", sa.Text(), nullable=True))
    except Exception:
        pass

    # Create blocked_user table.
    try:
        op.create_table(
            "blocked_user",
            sa.Column("id", sa.Integer(), primary_key=True),
            sa.Column("blocker_id", sa.Integer(), sa.ForeignKey("user.id"), nullable=False),
            sa.Column("blocked_id", sa.Integer(), sa.ForeignKey("user.id"), nullable=False),
            sa.Column("created_at", sa.DateTime()),
            sa.UniqueConstraint("blocker_id", "blocked_id", name="uq_blocked_user"),
        )
        op.create_index("ix_blocked_user_blocker_id", "blocked_user", ["blocker_id"])
        op.create_index("ix_blocked_user_blocked_id", "blocked_user", ["blocked_id"])
    except Exception:
        pass

    # Create user_report table.
    try:
        op.create_table(
            "user_report",
            sa.Column("id", sa.Integer(), primary_key=True),
            sa.Column("reporter_id", sa.Integer(), sa.ForeignKey("user.id"), nullable=False),
            sa.Column("reported_id", sa.Integer(), sa.ForeignKey("user.id"), nullable=False),
            sa.Column("reason", sa.String(200), nullable=False),
            sa.Column("details", sa.Text(), nullable=True),
            sa.Column("status", sa.String(20), server_default="pending"),
            sa.Column("created_at", sa.DateTime()),
        )
        op.create_index("ix_user_report_reporter_id", "user_report", ["reporter_id"])
        op.create_index("ix_user_report_reported_id", "user_report", ["reported_id"])
    except Exception:
        pass


def downgrade():
    try:
        op.drop_table("user_report")
    except Exception:
        pass
    try:
        op.drop_table("blocked_user")
    except Exception:
        pass
    try:
        op.drop_column("message", "attachment_url")
    except Exception:
        pass
