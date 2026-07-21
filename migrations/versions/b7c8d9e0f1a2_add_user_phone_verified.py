"""Add user.phone_verified for phone OTP vs email gates.

Revision ID: b7c8d9e0f1a2
Revises: a9b8c7d6e5f4
Create Date: 2026-07-21

Email verification must not unlock listing/media/chat gates. Grandfather
existing is_verified users as phone_verified so current phone-OTP users
are not locked out; forward path sets phone_verified only on phone OTP.
"""

from __future__ import annotations

import sqlalchemy as sa
from alembic import op


revision = "b7c8d9e0f1a2"
down_revision = "a9b8c7d6e5f4"
branch_labels = None
depends_on = None


def upgrade():
    with op.batch_alter_table("user") as batch:
        batch.add_column(
            sa.Column(
                "phone_verified",
                sa.Boolean(),
                nullable=False,
                server_default=sa.false(),
            )
        )

    # Preserve access for accounts already treated as verified (mostly phone OTP).
    op.execute(
        sa.text(
            "UPDATE \"user\" SET phone_verified = true WHERE is_verified IS true"
        )
    )


def downgrade():
    with op.batch_alter_table("user") as batch:
        batch.drop_column("phone_verified")
