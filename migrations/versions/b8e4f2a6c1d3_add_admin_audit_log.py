"""Add admin_audit_log (append-only administrator audit trail, F-17).

Revision ID: b8e4f2a6c1d3
Revises: a7d3e1c9b5f2
Create Date: 2026-11-08

One new table, ``admin_audit_log``. Admin actions were only recorded in
``user_action`` whose ``user_id`` is ``ON DELETE CASCADE``, so deleting or
purging a user erased that user's admin history. The new table has NO foreign
key to ``user`` (actor id + username snapshot only) so nothing can cascade into
it. On PostgreSQL a trigger additionally rejects UPDATE and DELETE (append-only).

PURELY ADDITIVE: no existing table/column/row is touched, nothing is
backfilled; the release currently in production (which never reads the table)
keeps working against the upgraded schema.

Downgrade drops the trigger, function and table (the audit rows in the new
table are lost -- export first if any exist). ``user_action`` is untouched.
"""

from __future__ import annotations

import sqlalchemy as sa
from alembic import op

# revision identifiers, used by Alembic.
revision = "b8e4f2a6c1d3"
down_revision = "a7d3e1c9b5f2"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "admin_audit_log",
        sa.Column("id", sa.Integer(), nullable=False),
        sa.Column("admin_user_id", sa.Integer(), nullable=True),
        sa.Column("admin_username", sa.String(length=80), nullable=True),
        sa.Column("action_type", sa.String(length=50), nullable=False),
        sa.Column("target_type", sa.String(length=50), nullable=True),
        sa.Column("target_id", sa.String(length=50), nullable=True),
        sa.Column("action_metadata", sa.JSON(), nullable=True),
        sa.Column("created_at", sa.DateTime(), nullable=False),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index("ix_admin_audit_log_admin_user_id", "admin_audit_log", ["admin_user_id"])
    op.create_index("ix_admin_audit_log_action_type", "admin_audit_log", ["action_type"])
    op.create_index("ix_admin_audit_log_created_at", "admin_audit_log", ["created_at"])

    if op.get_bind().dialect.name == "postgresql":
        op.execute(
            """
            CREATE FUNCTION admin_audit_log_append_only() RETURNS trigger AS $$
            BEGIN
                RAISE EXCEPTION 'admin_audit_log is append-only';
            END;
            $$ LANGUAGE plpgsql
            """
        )
        op.execute(
            """
            CREATE TRIGGER admin_audit_log_no_update_delete
            BEFORE UPDATE OR DELETE ON admin_audit_log
            FOR EACH ROW EXECUTE FUNCTION admin_audit_log_append_only()
            """
        )


def downgrade() -> None:
    if op.get_bind().dialect.name == "postgresql":
        op.execute("DROP TRIGGER IF EXISTS admin_audit_log_no_update_delete ON admin_audit_log")
        op.execute("DROP FUNCTION IF EXISTS admin_audit_log_append_only()")
    op.drop_index("ix_admin_audit_log_created_at", table_name="admin_audit_log")
    op.drop_index("ix_admin_audit_log_action_type", table_name="admin_audit_log")
    op.drop_index("ix_admin_audit_log_admin_user_id", table_name="admin_audit_log")
    op.drop_table("admin_audit_log")
