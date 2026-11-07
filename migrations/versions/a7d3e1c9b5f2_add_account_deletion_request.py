"""Add account_deletion_request (durable web account-deletion requests).

Revision ID: a7d3e1c9b5f2
Revises: f04a1b2c3d4e
Create Date: 2026-11-07

One table, ``account_deletion_request``: the durable record behind
``POST /api/account-deletion-request`` (the public /delete-account form). The
row is committed BEFORE the API reports success, so an email-provider outage
can no longer silently lose a request; the support email is only a
best-effort notification of the row. ``status`` is ``pending`` -> ``completed``,
and a completed row carries a ``resolution`` (``account_deleted`` /
``no_account_found`` / ``declined``) so "completed" never implies deletion by itself.
A PARTIAL unique index allows at most one ``pending`` row per ``phone_key``
(repeat submissions are de-duplicated; completed rows never block a later
request).

PURELY ADDITIVE: one new table plus indexes. No existing table, column,
constraint or row is touched and nothing is backfilled; the application code
currently in production (which never reads this table) keeps working against
the upgraded schema. The foreign key to ``user`` is ``ON DELETE SET NULL``
so a request row can never block a user delete.

Downgrade drops the table only (the request queue history is lost; users and
everything else are unaffected). Export pending rows first if any exist.
"""

from __future__ import annotations

import sqlalchemy as sa
from alembic import op

# revision identifiers, used by Alembic.
revision = "a7d3e1c9b5f2"
down_revision = "f04a1b2c3d4e"
branch_labels = None
depends_on = None

_PENDING = sa.text("status = 'pending'")


def upgrade() -> None:
    # The FK to ``user`` briefly needs SHARE ROW EXCLUSIVE on that table. Bound
    # the wait so the migration fails fast (the deploy stops, the running
    # release keeps serving) instead of queueing writes behind this DDL.
    if op.get_bind().dialect.name == "postgresql":
        op.execute("SET LOCAL lock_timeout = '5s'")

    op.create_table(
        "account_deletion_request",
        sa.Column("id", sa.Integer(), nullable=False),
        sa.Column("public_id", sa.String(length=36), nullable=False),
        sa.Column("phone", sa.String(length=32), nullable=False),
        sa.Column("phone_key", sa.String(length=64), nullable=False),
        sa.Column("email", sa.String(length=120), nullable=True),
        sa.Column("details", sa.Text(), nullable=True),
        sa.Column("ip_hash", sa.String(length=64), nullable=True),
        sa.Column("status", sa.String(length=16), server_default="pending", nullable=False),
        sa.Column("created_at", sa.DateTime(), nullable=False),
        sa.Column("updated_at", sa.DateTime(), nullable=False),
        sa.Column("notify_attempts", sa.Integer(), server_default="0", nullable=False),
        sa.Column("notified_at", sa.DateTime(), nullable=True),
        sa.Column("last_notify_error", sa.String(length=255), nullable=True),
        sa.Column("completed_at", sa.DateTime(), nullable=True),
        sa.Column("completed_by_user_id", sa.Integer(), nullable=True),
        sa.Column("completion_note", sa.String(length=255), nullable=True),
        sa.Column("resolution", sa.String(length=24), nullable=True),
        sa.ForeignKeyConstraint(["completed_by_user_id"], ["user.id"], ondelete="SET NULL"),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("public_id"),
    )
    op.create_index(
        "uq_account_deletion_request_pending_phone",
        "account_deletion_request",
        ["phone_key"],
        unique=True,
        postgresql_where=_PENDING,
        sqlite_where=_PENDING,
    )
    op.create_index(
        "ix_account_deletion_request_status_created",
        "account_deletion_request",
        ["status", "created_at"],
        unique=False,
    )


def downgrade() -> None:
    op.drop_index(
        "ix_account_deletion_request_status_created", table_name="account_deletion_request"
    )
    op.drop_index(
        "uq_account_deletion_request_pending_phone", table_name="account_deletion_request"
    )
    op.drop_table("account_deletion_request")
