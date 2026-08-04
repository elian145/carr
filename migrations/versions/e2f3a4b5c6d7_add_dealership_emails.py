"""add dealership contact emails and verification otp columns

Revision ID: e2f3a4b5c6d7
Revises: d9e0f1a2b3c4
Create Date: 2026-08-04
"""

from __future__ import annotations

import sqlalchemy as sa
from alembic import op


revision = "e2f3a4b5c6d7"
down_revision = "d9e0f1a2b3c4"
branch_labels = None
depends_on = None


def upgrade() -> None:
    conn = op.get_bind()
    inspector = sa.inspect(conn)

    if inspector.has_table("user"):
        columns = {column["name"] for column in inspector.get_columns("user")}
        with op.batch_alter_table("user", schema=None) as batch_op:
            if "dealership_emails" not in columns:
                batch_op.add_column(sa.Column("dealership_emails", sa.JSON(), nullable=True))
            if "dealership_verified_emails" not in columns:
                batch_op.add_column(
                    sa.Column("dealership_verified_emails", sa.JSON(), nullable=True)
                )
            if "dealer_email_verification_code_hash" not in columns:
                batch_op.add_column(
                    sa.Column(
                        "dealer_email_verification_code_hash",
                        sa.String(128),
                        nullable=True,
                    )
                )
            if "dealer_email_verification_expires_at" not in columns:
                batch_op.add_column(
                    sa.Column(
                        "dealer_email_verification_expires_at",
                        sa.DateTime(),
                        nullable=True,
                    )
                )
            if "dealer_email_verification_attempts" not in columns:
                batch_op.add_column(
                    sa.Column(
                        "dealer_email_verification_attempts",
                        sa.Integer(),
                        nullable=True,
                    )
                )
            if "dealer_email_verification_last_sent_at" not in columns:
                batch_op.add_column(
                    sa.Column(
                        "dealer_email_verification_last_sent_at",
                        sa.DateTime(),
                        nullable=True,
                    )
                )
            if "dealer_email_verification_locked_until" not in columns:
                batch_op.add_column(
                    sa.Column(
                        "dealer_email_verification_locked_until",
                        sa.DateTime(),
                        nullable=True,
                    )
                )

    if inspector.has_table("dealer_profile"):
        columns = {
            column["name"] for column in inspector.get_columns("dealer_profile")
        }
        with op.batch_alter_table("dealer_profile", schema=None) as batch_op:
            if "dealership_emails" not in columns:
                batch_op.add_column(sa.Column("dealership_emails", sa.JSON(), nullable=True))
            if "dealership_verified_emails" not in columns:
                batch_op.add_column(
                    sa.Column("dealership_verified_emails", sa.JSON(), nullable=True)
                )


def downgrade() -> None:
    conn = op.get_bind()
    inspector = sa.inspect(conn)

    if inspector.has_table("dealer_profile"):
        columns = {
            column["name"] for column in inspector.get_columns("dealer_profile")
        }
        with op.batch_alter_table("dealer_profile", schema=None) as batch_op:
            if "dealership_verified_emails" in columns:
                batch_op.drop_column("dealership_verified_emails")
            if "dealership_emails" in columns:
                batch_op.drop_column("dealership_emails")

    if inspector.has_table("user"):
        columns = {column["name"] for column in inspector.get_columns("user")}
        with op.batch_alter_table("user", schema=None) as batch_op:
            for name in (
                "dealer_email_verification_locked_until",
                "dealer_email_verification_last_sent_at",
                "dealer_email_verification_attempts",
                "dealer_email_verification_expires_at",
                "dealer_email_verification_code_hash",
                "dealership_verified_emails",
                "dealership_emails",
            ):
                if name in columns:
                    batch_op.drop_column(name)
