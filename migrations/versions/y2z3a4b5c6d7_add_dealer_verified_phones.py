"""add verified dealership phone numbers

Revision ID: y2z3a4b5c6d7
Revises: l9m0n1p2q3r4
Create Date: 2026-07-19
"""

from __future__ import annotations

import sqlalchemy as sa
from alembic import op


revision = "y2z3a4b5c6d7"
down_revision = "l9m0n1p2q3r4"
branch_labels = None
depends_on = None


def _normalize_phone(value: object) -> str:
    digits = "".join(ch for ch in str(value or "") if ch.isdigit())
    if digits.startswith("964") and len(digits) >= 12:
        digits = digits[3:]
    if len(digits) > 11:
        digits = digits[-11:]
    return digits


def upgrade() -> None:
    conn = op.get_bind()
    inspector = sa.inspect(conn)
    if not inspector.has_table("user"):
        return
    columns = {column["name"] for column in inspector.get_columns("user")}
    if "dealership_verified_phones" not in columns:
        with op.batch_alter_table("user", schema=None) as batch_op:
            batch_op.add_column(
                sa.Column("dealership_verified_phones", sa.JSON(), nullable=True)
            )

    user_table = sa.table(
        "user",
        sa.column("id", sa.Integer()),
        sa.column("account_type", sa.String()),
        sa.column("dealership_phone", sa.String()),
        sa.column("dealership_phones", sa.JSON()),
        sa.column("dealership_verified_phones", sa.JSON()),
    )
    rows = conn.execute(
        sa.select(
            user_table.c.id,
            user_table.c.dealership_phone,
            user_table.c.dealership_phones,
        ).where(sa.func.lower(user_table.c.account_type) == "dealer")
    )
    for row in rows:
        raw_phones = row.dealership_phones
        phones = raw_phones if isinstance(raw_phones, list) else []
        if not phones and row.dealership_phone:
            phones = [row.dealership_phone]
        verified = []
        for phone in phones:
            normalized = _normalize_phone(phone)
            if normalized and normalized not in verified:
                verified.append(normalized)
        conn.execute(
            user_table.update()
            .where(user_table.c.id == row.id)
            .values(dealership_verified_phones=verified)
        )


def downgrade() -> None:
    conn = op.get_bind()
    if not sa.inspect(conn).has_table("user"):
        return
    columns = {column["name"] for column in sa.inspect(conn).get_columns("user")}
    if "dealership_verified_phones" in columns:
        with op.batch_alter_table("user", schema=None) as batch_op:
            batch_op.drop_column("dealership_verified_phones")
