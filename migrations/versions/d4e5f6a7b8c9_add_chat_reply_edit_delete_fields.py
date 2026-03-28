"""add chat reply edit delete fields

Revision ID: d4e5f6a7b8c9
Revises: a7c4d9e1b2f3
Create Date: 2026-03-28

"""

from alembic import op
import sqlalchemy as sa


revision = "d4e5f6a7b8c9"
down_revision = "a7c4d9e1b2f3"
branch_labels = None
depends_on = None


def upgrade():
    try:
        op.add_column("message", sa.Column("reply_to_id", sa.Integer(), nullable=True))
    except Exception:
        pass
    try:
        op.create_index("ix_message_reply_to_id", "message", ["reply_to_id"])
    except Exception:
        pass
    try:
        op.create_foreign_key(
            "fk_message_reply_to_id_message",
            "message",
            "message",
            ["reply_to_id"],
            ["id"],
        )
    except Exception:
        pass
    try:
        op.add_column("message", sa.Column("is_deleted", sa.Boolean(), nullable=True, server_default=sa.false()))
    except Exception:
        pass
    try:
        op.create_index("ix_message_is_deleted", "message", ["is_deleted"])
    except Exception:
        pass
    try:
        op.add_column("message", sa.Column("edited_at", sa.DateTime(), nullable=True))
    except Exception:
        pass


def downgrade():
    try:
        op.drop_column("message", "edited_at")
    except Exception:
        pass
    try:
        op.drop_index("ix_message_is_deleted", table_name="message")
    except Exception:
        pass
    try:
        op.drop_column("message", "is_deleted")
    except Exception:
        pass
    try:
        op.drop_constraint("fk_message_reply_to_id_message", "message", type_="foreignkey")
    except Exception:
        pass
    try:
        op.drop_index("ix_message_reply_to_id", table_name="message")
    except Exception:
        pass
    try:
        op.drop_column("message", "reply_to_id")
    except Exception:
        pass
