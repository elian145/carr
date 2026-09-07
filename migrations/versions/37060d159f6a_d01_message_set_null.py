"""D-01: message.* foreign keys -> ON DELETE SET NULL

Revision ID: 37060d159f6a
Revises: c05b6c97708d
Create Date: 2026-09-07

Product decision (D-01, approved): deleting a user account must preserve
conversation history for the *other* party in a chat. `message.sender_id`
and `message.receiver_id` therefore use `ON DELETE SET NULL` rather than
`CASCADE` (which would destroy the other participant's messages too) or the
implicit `NO ACTION` default (which would block/error out account
deletion entirely). `message.car_id` and `message.reply_to_id` get the same
`SET NULL` treatment for consistency: a message must not become
undeletable-account-blocking just because it references a car listing or an
earlier message that no longer exists.

`SET NULL` requires the referencing column to be nullable, so
`sender_id`/`receiver_id` are widened from `NOT NULL` to `NULL` here
(`car_id`/`reply_to_id` were already nullable). Call sites that read these
columns and treat a NULL as "deleted/anonymized" are updated separately in
this same change (see kk/routes/chat.py::list_chats() and
kk/chat_realtime.py::emit_message_to_participants()); `kk/routes/auth.py`'s
`delete_account()` no longer bulk-deletes `Message` rows for this same
reason.
"""

from __future__ import annotations

from alembic import op
import sqlalchemy as sa


revision = "37060d159f6a"
down_revision = "c05b6c97708d"
branch_labels = None
depends_on = None


# (column, referred_table, referred_column, was_nullable_before)
_MESSAGE_FKS: list[tuple[str, str, str, bool]] = [
    ("sender_id", "user", "id", False),
    ("receiver_id", "user", "id", False),
    ("car_id", "car", "id", True),
    ("reply_to_id", "message", "id", True),
]

_NAMING_CONVENTION = {
    "fk": "fk_%(table_name)s_%(column_0_name)s_%(referred_table_name)s",
}


def _fk_name(column: str, referred_table: str) -> str:
    return f"fk_message_{column}_{referred_table}"


def _find_fk(conn, column: str, referred_table: str) -> dict | None:
    for fk in sa.inspect(conn).get_foreign_keys("message"):
        if fk.get("constrained_columns") == [column] and fk.get("referred_table") == referred_table:
            return fk
    return None


def upgrade() -> None:
    conn = op.get_bind()
    insp = sa.inspect(conn)
    if not insp.has_table("message"):
        return

    # NOTE: `message.reply_to_id`'s FK was originally added via a bare (i.e.
    # non-batch) `op.create_foreign_key()` in
    # d4e5f6a7b8c9_add_chat_reply_edit_delete_fields.py, wrapped in a
    # try/except. SQLite does not support `ALTER TABLE ... ADD CONSTRAINT`
    # outside of Alembic's batch mode, so on SQLite that call silently
    # no-ops and `reply_to_id` has never actually had a real FK constraint
    # at the database level there (only the column + index) — unlike on
    # PostgreSQL, where it does exist. `exists` distinguishes "constraint
    # not present at all" (skip the drop; nothing to drop) from "constraint
    # present but unnamed" (drop it via the batch naming convention).
    existing = [
        (column, referred_table, referred_column, was_nullable, _find_fk(conn, column, referred_table))
        for column, referred_table, referred_column, was_nullable in _MESSAGE_FKS
    ]

    if conn.dialect.name == "sqlite":
        with op.batch_alter_table("message", schema=None, naming_convention=_NAMING_CONVENTION) as batch_op:
            for column, referred_table, _rc, _was_nullable, fk in existing:
                if fk is None:
                    continue
                constraint_name = fk.get("name") or _fk_name(column, referred_table)
                batch_op.drop_constraint(constraint_name, type_="foreignkey")
            batch_op.alter_column("sender_id", existing_type=sa.Integer(), nullable=True)
            batch_op.alter_column("receiver_id", existing_type=sa.Integer(), nullable=True)
            for column, referred_table, referred_column, _was_nullable, _fk in existing:
                batch_op.create_foreign_key(
                    _fk_name(column, referred_table),
                    referred_table,
                    [column],
                    [referred_column],
                    ondelete="SET NULL",
                )
        return

    # PostgreSQL
    op.execute(sa.text('ALTER TABLE message ALTER COLUMN sender_id DROP NOT NULL'))
    op.execute(sa.text('ALTER TABLE message ALTER COLUMN receiver_id DROP NOT NULL'))
    for column, referred_table, referred_column, _was_nullable, fk in existing:
        if fk is not None and fk.get("name"):
            op.drop_constraint(fk["name"], "message", type_="foreignkey")
        op.create_foreign_key(
            _fk_name(column, referred_table),
            "message",
            referred_table,
            [column],
            [referred_column],
            ondelete="SET NULL",
        )


def downgrade() -> None:
    conn = op.get_bind()
    insp = sa.inspect(conn)
    if not insp.has_table("message"):
        return

    existing = [
        (column, referred_table, referred_column, _find_fk(conn, column, referred_table))
        for column, referred_table, referred_column, _was_nullable in _MESSAGE_FKS
    ]

    if conn.dialect.name == "sqlite":
        with op.batch_alter_table("message", schema=None, naming_convention=_NAMING_CONVENTION) as batch_op:
            for column, referred_table, _rc, fk in existing:
                if fk is None:
                    continue
                batch_op.drop_constraint(fk.get("name") or _fk_name(column, referred_table), type_="foreignkey")
            batch_op.alter_column("sender_id", existing_type=sa.Integer(), nullable=False)
            batch_op.alter_column("receiver_id", existing_type=sa.Integer(), nullable=False)
            for column, referred_table, referred_column, _fk in existing:
                batch_op.create_foreign_key(None, referred_table, [column], [referred_column])
        return

    # PostgreSQL: NOTE — downgrading with existing NULL rows present would
    # violate the restored NOT NULL constraint. This mirrors the same
    # accepted limitation as other D-01 downgrades (only intended for a
    # rollback immediately after the forward migration, before any SET NULL
    # has actually fired).
    for column, referred_table, referred_column, fk in existing:
        if fk is not None and fk.get("name"):
            op.drop_constraint(fk["name"], "message", type_="foreignkey")
        op.create_foreign_key(None, "message", referred_table, [column], [referred_column])
    op.execute(sa.text('ALTER TABLE message ALTER COLUMN sender_id SET NOT NULL'))
    op.execute(sa.text('ALTER TABLE message ALTER COLUMN receiver_id SET NOT NULL'))
