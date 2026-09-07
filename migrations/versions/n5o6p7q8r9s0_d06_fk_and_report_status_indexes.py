"""D-06: add missing indexes on notification/user_action/password_reset/
email_verification.user_id and user_report.status

Revision ID: n5o6p7q8r9s0
Revises: 3f945e50c327
Create Date: 2026-09-07

PRODUCTION_AUDIT.md D-06 flagged six columns as "missing FK indexes". Two of
them (`car.status`, `car.region_specs`) turned out to be a separate,
unrelated model->migration index-drift issue and are explicitly NOT touched
here. A third (`token_blacklist.expires_at`) has zero query usage anywhere
in the codebase (no cleanup/retention job exists) and is deliberately NOT
indexed here either -- an index with no matching query is pure write/storage
overhead. See PRODUCTION_AUDIT.md D-06 remediation detail for the full
investigation.

This migration adds exactly the five indexes that ARE backed by a concrete,
live query pattern:

- ix_notification_user_id       -- notification.user_id is a NOT NULL FK to
  user.id with ON DELETE CASCADE (see c05b6c97708d). Every
  GET /api/user/notifications call (kk/routes/user.py) filters
  Notification by user_id; every account deletion cascades on it.
- ix_user_action_user_id        -- user_action.user_id, same FK/cascade
  shape. Used directly by the admin per-user audit-trail query
  (kk/routes/admin.py) and by the ON DELETE CASCADE scan.
- ix_password_reset_user_id     -- password_reset.user_id, same FK/cascade
  shape. Used by the invalidate-prior-tokens bulk DELETE on every
  forgot-password request and by delete_account() (kk/auth.py,
  kk/routes/auth.py).
- ix_email_verification_user_id -- email_verification.user_id, identical
  shape/usage to password_reset.user_id.
- ix_user_report_status         -- user_report.status is a plain (non-FK),
  low-cardinality column, but the admin moderation queue
  (kk/routes/admin.py::list_reports) defaults to and commonly filters
  status="pending", and the sibling table `listing_report` already has
  the equivalent `ix_listing_report_status` for the identical query shape
  -- this closes that inconsistency.

Design note: these are index-only changes on existing, already-populated
tables. Per the existing repository convention for this exact situation
(see g7h8i9j0k1l2_add_car_media_car_id_indexes.py, which added
ix_car_image_car_id / ix_car_video_car_id the same way), plain
`op.create_index()` / `op.drop_index()` is used directly -- NOT
`batch_alter_table()`. Both SQLite and PostgreSQL support CREATE INDEX /
DROP INDEX as standalone DDL with no table recreation; `batch_alter_table`
exists for operations SQLite cannot do in place (e.g. ALTER COLUMN), which
does not apply here. Existence guards make both directions idempotent/safe
to re-run.
"""

from __future__ import annotations

import sqlalchemy as sa
from alembic import op


revision = "n5o6p7q8r9s0"
down_revision = "3f945e50c327"
branch_labels = None
depends_on = None


# (table, index_name, [columns])
_D06_INDEXES: tuple[tuple[str, str, list[str]], ...] = (
    ("notification", "ix_notification_user_id", ["user_id"]),
    ("user_action", "ix_user_action_user_id", ["user_id"]),
    ("password_reset", "ix_password_reset_user_id", ["user_id"]),
    ("email_verification", "ix_email_verification_user_id", ["user_id"]),
    ("user_report", "ix_user_report_status", ["status"]),
)


def _has_index(inspector: sa.engine.reflection.Inspector, table: str, name: str) -> bool:
    if not inspector.has_table(table):
        return False
    return any(ix.get("name") == name for ix in inspector.get_indexes(table))


def upgrade() -> None:
    conn = op.get_bind()
    inspector = sa.inspect(conn)

    for table, name, columns in _D06_INDEXES:
        if not inspector.has_table(table):
            continue
        if _has_index(inspector, table, name):
            continue
        op.create_index(name, table, columns, unique=False)


def downgrade() -> None:
    conn = op.get_bind()
    inspector = sa.inspect(conn)

    for table, name, _columns in reversed(_D06_INDEXES):
        if not inspector.has_table(table):
            continue
        if not _has_index(inspector, table, name):
            continue
        op.drop_index(name, table_name=table)
