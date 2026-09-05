"""H-01/H-02: add user.tokens_invalid_before for JWT revocation on
password change/reset (and, via the is_active check, ban/deactivation).

Revision ID: d2e3f4a5b6c7
Revises: a3b4c5d6e7f8
Create Date: 2026-09-05
"""

from __future__ import annotations

import sqlalchemy as sa
from alembic import op


revision = "d2e3f4a5b6c7"
down_revision = "a3b4c5d6e7f8"
branch_labels = None
depends_on = None


def upgrade() -> None:
    conn = op.get_bind()
    inspector = sa.inspect(conn)

    if inspector.has_table("user"):
        columns = {column["name"] for column in inspector.get_columns("user")}
        if "tokens_invalid_before" not in columns:
            with op.batch_alter_table("user", schema=None) as batch_op:
                batch_op.add_column(
                    sa.Column("tokens_invalid_before", sa.DateTime(), nullable=True)
                )


def downgrade() -> None:
    conn = op.get_bind()
    inspector = sa.inspect(conn)

    if inspector.has_table("user"):
        columns = {column["name"] for column in inspector.get_columns("user")}
        if "tokens_invalid_before" in columns:
            with op.batch_alter_table("user", schema=None) as batch_op:
                batch_op.drop_column("tokens_invalid_before")
