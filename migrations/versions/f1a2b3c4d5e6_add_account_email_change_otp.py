"""add personal account email-change OTP columns (S7 hardening)

Revision ID: f1a2b3c4d5e6
Revises: e2f3a4b5c6d7
Create Date: 2026-08-06
"""

from __future__ import annotations

import sqlalchemy as sa
from alembic import op


revision = "f1a2b3c4d5e6"
down_revision = "e2f3a4b5c6d7"
branch_labels = None
depends_on = None


def upgrade() -> None:
    conn = op.get_bind()
    inspector = sa.inspect(conn)

    if inspector.has_table("user"):
        columns = {column["name"] for column in inspector.get_columns("user")}
        with op.batch_alter_table("user", schema=None) as batch_op:
            if "pending_email" not in columns:
                batch_op.add_column(sa.Column("pending_email", sa.String(120), nullable=True))
            if "email_change_code_hash" not in columns:
                batch_op.add_column(
                    sa.Column("email_change_code_hash", sa.String(128), nullable=True)
                )
            if "email_change_expires_at" not in columns:
                batch_op.add_column(
                    sa.Column("email_change_expires_at", sa.DateTime(), nullable=True)
                )
            if "email_change_attempts" not in columns:
                batch_op.add_column(
                    sa.Column("email_change_attempts", sa.Integer(), nullable=True)
                )
            if "email_change_last_sent_at" not in columns:
                batch_op.add_column(
                    sa.Column("email_change_last_sent_at", sa.DateTime(), nullable=True)
                )
            if "email_change_locked_until" not in columns:
                batch_op.add_column(
                    sa.Column("email_change_locked_until", sa.DateTime(), nullable=True)
                )


def downgrade() -> None:
    conn = op.get_bind()
    inspector = sa.inspect(conn)

    if inspector.has_table("user"):
        columns = {column["name"] for column in inspector.get_columns("user")}
        with op.batch_alter_table("user", schema=None) as batch_op:
            for name in (
                "email_change_locked_until",
                "email_change_last_sent_at",
                "email_change_attempts",
                "email_change_expires_at",
                "email_change_code_hash",
                "pending_email",
            ):
                if name in columns:
                    batch_op.drop_column(name)
