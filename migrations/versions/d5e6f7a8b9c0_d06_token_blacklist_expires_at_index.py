"""D-06: add missing index on token_blacklist.expires_at

Revision ID: d5e6f7a8b9c0
Revises: c6d7e8f9a0b1
Create Date: 2026-09-20

PRODUCTION_AUDIT.md D-06 lists ``token_blacklist.expires_at`` among the
columns needing an index. ``n5o6p7q8r9s0`` (the original D-06 migration)
deliberately left this one out after finding no live query filtering on it
at the time. Re-confirmed audit now calls for it explicitly, so this
migration adds exactly that one index, matching the same existence-guard
pattern as ``n5o6p7q8r9s0`` -- safe/idempotent on both SQLite and
PostgreSQL, no table recreation needed (plain ``CREATE INDEX`` /
``DROP INDEX``).
"""

from __future__ import annotations

import sqlalchemy as sa
from alembic import op


revision = "d5e6f7a8b9c0"
down_revision = "c6d7e8f9a0b1"
branch_labels = None
depends_on = None

_TABLE = "token_blacklist"
_INDEX = "ix_token_blacklist_expires_at"
_COLUMNS = ["expires_at"]


def _has_index(inspector: sa.engine.reflection.Inspector, table: str, name: str) -> bool:
    if not inspector.has_table(table):
        return False
    return any(ix.get("name") == name for ix in inspector.get_indexes(table))


def upgrade() -> None:
    conn = op.get_bind()
    inspector = sa.inspect(conn)

    if not inspector.has_table(_TABLE):
        return
    if _has_index(inspector, _TABLE, _INDEX):
        return
    op.create_index(_INDEX, _TABLE, _COLUMNS, unique=False)


def downgrade() -> None:
    conn = op.get_bind()
    inspector = sa.inspect(conn)

    if not inspector.has_table(_TABLE):
        return
    if not _has_index(inspector, _TABLE, _INDEX):
        return
    op.drop_index(_INDEX, table_name=_TABLE)
