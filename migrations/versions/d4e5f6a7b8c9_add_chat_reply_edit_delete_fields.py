"""add chat reply edit delete fields

Revision ID: d4e5f6a7b8c9
Revises: a7c4d9e1b2f3
Create Date: 2026-03-28

"""

from __future__ import annotations

from alembic import op
import sqlalchemy as sa


revision = "d4e5f6a7b8c9"
down_revision = "a7c4d9e1b2f3"
branch_labels = None
depends_on = None


# D-02: read-only introspection helpers. A conservative "not present" default
# on inspection failure only controls whether we *attempt* an operation --
# it must never be used to swallow an error raised by the op.* calls below
# (see PRODUCTION_AUDIT.md D-02).
def _columns(conn, table: str) -> set[str]:
    try:
        return {c["name"] for c in sa.inspect(conn).get_columns(table)}
    except Exception:
        return set()


def _index_names(conn, table: str) -> set[str]:
    try:
        return {ix["name"] for ix in sa.inspect(conn).get_indexes(table)}
    except Exception:
        return set()


def _fk_names(conn, table: str) -> set[str]:
    try:
        return {fk["name"] for fk in sa.inspect(conn).get_foreign_keys(table) if fk.get("name")}
    except Exception:
        return set()


def upgrade():
    conn = op.get_bind()

    if "reply_to_id" not in _columns(conn, "message"):
        op.add_column("message", sa.Column("reply_to_id", sa.Integer(), nullable=True))

    if "ix_message_reply_to_id" not in _index_names(conn, "message"):
        op.create_index("ix_message_reply_to_id", "message", ["reply_to_id"])

    # NOTE (D-02 archaeology): a plain (non-batch) `create_foreign_key()`
    # cannot succeed on SQLite -- SQLite does not support
    # `ALTER TABLE ... ADD CONSTRAINT` outside of Alembic's batch
    # (table-rebuild) mode. That was true when this migration was written
    # and silently swallowed by the try/except this change removes; it is
    # still true today. This is NOT a regression introduced by removing the
    # swallow: on SQLite this statement has never actually created the
    # constraint. The D-01 migration `37060d159f6a_d01_message_set_null.py`
    # creates this exact FK for real via batch mode (with
    # `ondelete='SET NULL'`) a few revisions later, for both SQLite and
    # PostgreSQL, so every environment ends up with the constraint by the
    # current migration head regardless of dialect. On PostgreSQL, where a
    # plain `create_foreign_key` does work, create it here as originally
    # intended (skipped only if already present from a previous partial
    # run).
    if conn.dialect.name != "sqlite" and "fk_message_reply_to_id_message" not in _fk_names(conn, "message"):
        op.create_foreign_key(
            "fk_message_reply_to_id_message",
            "message",
            "message",
            ["reply_to_id"],
            ["id"],
        )

    if "is_deleted" not in _columns(conn, "message"):
        op.add_column("message", sa.Column("is_deleted", sa.Boolean(), nullable=True, server_default=sa.false()))

    if "ix_message_is_deleted" not in _index_names(conn, "message"):
        op.create_index("ix_message_is_deleted", "message", ["is_deleted"])

    if "edited_at" not in _columns(conn, "message"):
        op.add_column("message", sa.Column("edited_at", sa.DateTime(), nullable=True))


def downgrade():
    conn = op.get_bind()

    if "edited_at" in _columns(conn, "message"):
        op.drop_column("message", "edited_at")

    if "ix_message_is_deleted" in _index_names(conn, "message"):
        op.drop_index("ix_message_is_deleted", table_name="message")

    if "is_deleted" in _columns(conn, "message"):
        op.drop_column("message", "is_deleted")

    if conn.dialect.name != "sqlite" and "fk_message_reply_to_id_message" in _fk_names(conn, "message"):
        op.drop_constraint("fk_message_reply_to_id_message", "message", type_="foreignkey")

    if "ix_message_reply_to_id" in _index_names(conn, "message"):
        op.drop_index("ix_message_reply_to_id", table_name="message")

    if "reply_to_id" in _columns(conn, "message"):
        op.drop_column("message", "reply_to_id")
