"""add dealer account fields

Revision ID: c9d8e7f6a5b4
Revises: f8a1c2d3e4b5
Create Date: 2026-04-15
"""

from __future__ import annotations

from alembic import op
import sqlalchemy as sa


revision = "c9d8e7f6a5b4"
down_revision = "f8a1c2d3e4b5"
branch_labels = None
depends_on = None


def _has_table(conn, name: str) -> bool:
    try:
        return bool(sa.inspect(conn).has_table(name))
    except Exception:
        return False


def _cols(conn, table: str) -> set[str]:
    try:
        return {c["name"] for c in sa.inspect(conn).get_columns(table)}
    except Exception:
        return set()


def upgrade() -> None:
    conn = op.get_bind()

    if _has_table(conn, "user"):
        user_cols = _cols(conn, "user")
        with op.batch_alter_table("user", schema=None) as batch_op:
            if "account_type" not in user_cols:
                batch_op.add_column(sa.Column("account_type", sa.String(length=20), nullable=True))
            if "dealer_status" not in user_cols:
                batch_op.add_column(sa.Column("dealer_status", sa.String(length=20), nullable=True))
            if "dealership_name" not in user_cols:
                batch_op.add_column(sa.Column("dealership_name", sa.String(length=120), nullable=True))
            if "dealership_phone" not in user_cols:
                batch_op.add_column(sa.Column("dealership_phone", sa.String(length=20), nullable=True))
            if "dealership_location" not in user_cols:
                batch_op.add_column(sa.Column("dealership_location", sa.String(length=200), nullable=True))
        op.execute("UPDATE user SET account_type = COALESCE(account_type, 'user')")
        op.execute("UPDATE user SET dealer_status = COALESCE(dealer_status, 'none')")

    if _has_table(conn, "pending_signup"):
        pending_cols = _cols(conn, "pending_signup")
        with op.batch_alter_table("pending_signup", schema=None) as batch_op:
            if "is_dealer_requested" not in pending_cols:
                batch_op.add_column(sa.Column("is_dealer_requested", sa.Boolean(), nullable=True))
            if "dealership_name" not in pending_cols:
                batch_op.add_column(sa.Column("dealership_name", sa.String(length=120), nullable=True))
            if "dealership_phone" not in pending_cols:
                batch_op.add_column(sa.Column("dealership_phone", sa.String(length=20), nullable=True))
            if "dealership_location" not in pending_cols:
                batch_op.add_column(sa.Column("dealership_location", sa.String(length=200), nullable=True))
        op.execute("UPDATE pending_signup SET is_dealer_requested = COALESCE(is_dealer_requested, 0)")


def downgrade() -> None:
    conn = op.get_bind()

    if _has_table(conn, "pending_signup"):
        pending_cols = _cols(conn, "pending_signup")
        with op.batch_alter_table("pending_signup", schema=None) as batch_op:
            if "dealership_location" in pending_cols:
                batch_op.drop_column("dealership_location")
            if "dealership_phone" in pending_cols:
                batch_op.drop_column("dealership_phone")
            if "dealership_name" in pending_cols:
                batch_op.drop_column("dealership_name")
            if "is_dealer_requested" in pending_cols:
                batch_op.drop_column("is_dealer_requested")

    if _has_table(conn, "user"):
        user_cols = _cols(conn, "user")
        with op.batch_alter_table("user", schema=None) as batch_op:
            if "dealership_location" in user_cols:
                batch_op.drop_column("dealership_location")
            if "dealership_phone" in user_cols:
                batch_op.drop_column("dealership_phone")
            if "dealership_name" in user_cols:
                batch_op.drop_column("dealership_name")
            if "dealer_status" in user_cols:
                batch_op.drop_column("dealer_status")
            if "account_type" in user_cols:
                batch_op.drop_column("account_type")
