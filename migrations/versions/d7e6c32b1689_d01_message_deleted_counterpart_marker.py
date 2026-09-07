"""D-01 follow-up: message.deleted_counterpart_marker for chat-list grouping

Revision ID: d7e6c32b1689
Revises: 6e469e1b250a
Create Date: 2026-09-07

Fixes a correctness bug found during D-01 final review: after
`message.sender_id`/`message.receiver_id` get `ON DELETE SET NULL`'d (see
`37060d159f6a_d01_message_set_null.py`), `kk/routes/chat.py::list_chats()`
had no stable way to tell "these ten historical messages were all the same
now-deleted counterpart" apart from "these were two different deleted
counterparts who each messaged about the same car" — the identifying user
id is gone from the row the moment it is nulled, for *every* message that
referenced that user, project-wide, in one shot. There is no other existing
column that can reconstruct this after the fact.

`message.deleted_counterpart_marker` is a plain nullable integer with *no*
foreign key and *no* `ondelete` policy — it must never be nulled, cascaded,
or otherwise touched by any FK machinery; it exists purely so the id can be
captured (by `kk/routes/auth.py::delete_account()`) immediately before the
real FK's `SET NULL` fires, and later used (by `list_chats()`) only to
group already-anonymous messages, never to resolve a live user. This is not
one of the D-01 FK-policy columns and does not change any `ondelete`
behavior; it only adds a new column.

Rows written before this migration/backing code shipped have no marker to
fall back on (that identity is unrecoverable) and keep the previous
conservative per-message grouping in `list_chats()`.
"""

from __future__ import annotations

from alembic import op
import sqlalchemy as sa


revision = "d7e6c32b1689"
down_revision = "6e469e1b250a"
branch_labels = None
depends_on = None

_COLUMN = "deleted_counterpart_marker"


def upgrade() -> None:
    conn = op.get_bind()
    insp = sa.inspect(conn)
    if not insp.has_table("message"):
        return
    existing = {c["name"] for c in insp.get_columns("message")}
    if _COLUMN in existing:
        return
    op.add_column("message", sa.Column(_COLUMN, sa.Integer(), nullable=True))


def downgrade() -> None:
    conn = op.get_bind()
    insp = sa.inspect(conn)
    if not insp.has_table("message"):
        return
    existing = {c["name"] for c in insp.get_columns("message")}
    if _COLUMN not in existing:
        return
    if conn.dialect.name == "sqlite":
        with op.batch_alter_table("message", schema=None) as batch_op:
            batch_op.drop_column(_COLUMN)
        return
    op.drop_column("message", _COLUMN)
