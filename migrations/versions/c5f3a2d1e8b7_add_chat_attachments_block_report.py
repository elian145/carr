"""add chat attachments, block, and report tables

Revision ID: c5f3a2d1e8b7
Revises: b4e8a1c2d3f4
Create Date: 2026-03-27

"""

from __future__ import annotations

from alembic import op
import sqlalchemy as sa


revision = "c5f3a2d1e8b7"
down_revision = "b4e8a1c2d3f4"
branch_labels = None
depends_on = None


# D-02: these three read-only introspection helpers may legitimately return a
# conservative default ("not present") if the DB can't be inspected for some
# reason -- that only affects whether we *attempt* an operation, never
# whether a genuine failure from the operation itself is reported. They must
# not be used to swallow errors from op.* calls (see PRODUCTION_AUDIT.md D-02).
def _has_table(conn, name: str) -> bool:
    try:
        return bool(sa.inspect(conn).has_table(name))
    except Exception:
        return False


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


def upgrade():
    conn = op.get_bind()

    # Add attachment_url to message table.
    if "attachment_url" not in _columns(conn, "message"):
        op.add_column("message", sa.Column("attachment_url", sa.Text(), nullable=True))

    # Create blocked_user table.
    if not _has_table(conn, "blocked_user"):
        op.create_table(
            "blocked_user",
            sa.Column("id", sa.Integer(), primary_key=True),
            sa.Column("blocker_id", sa.Integer(), sa.ForeignKey("user.id"), nullable=False),
            sa.Column("blocked_id", sa.Integer(), sa.ForeignKey("user.id"), nullable=False),
            sa.Column("created_at", sa.DateTime()),
            sa.UniqueConstraint("blocker_id", "blocked_id", name="uq_blocked_user"),
        )
    blocked_user_indexes = _index_names(conn, "blocked_user")
    if "ix_blocked_user_blocker_id" not in blocked_user_indexes:
        op.create_index("ix_blocked_user_blocker_id", "blocked_user", ["blocker_id"])
    if "ix_blocked_user_blocked_id" not in blocked_user_indexes:
        op.create_index("ix_blocked_user_blocked_id", "blocked_user", ["blocked_id"])

    # Create user_report table.
    if not _has_table(conn, "user_report"):
        op.create_table(
            "user_report",
            sa.Column("id", sa.Integer(), primary_key=True),
            sa.Column("reporter_id", sa.Integer(), sa.ForeignKey("user.id"), nullable=False),
            sa.Column("reported_id", sa.Integer(), sa.ForeignKey("user.id"), nullable=False),
            sa.Column("reason", sa.String(200), nullable=False),
            sa.Column("details", sa.Text(), nullable=True),
            sa.Column("status", sa.String(20), server_default="pending"),
            sa.Column("created_at", sa.DateTime()),
        )
    user_report_indexes = _index_names(conn, "user_report")
    if "ix_user_report_reporter_id" not in user_report_indexes:
        op.create_index("ix_user_report_reporter_id", "user_report", ["reporter_id"])
    if "ix_user_report_reported_id" not in user_report_indexes:
        op.create_index("ix_user_report_reported_id", "user_report", ["reported_id"])


def downgrade():
    conn = op.get_bind()
    if _has_table(conn, "user_report"):
        op.drop_table("user_report")
    if _has_table(conn, "blocked_user"):
        op.drop_table("blocked_user")
    if "attachment_url" in _columns(conn, "message"):
        op.drop_column("message", "attachment_url")
