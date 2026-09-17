"""MI-03: add locale column to user

Revision ID: c6d7e8f9a0b1
Revises: b3c4d5e6f7a8
Create Date: 2026-09-17

PRODUCTION_AUDIT.md MI-03: ``User`` had no ``language``/``locale`` column, so
backend-generated strings (login errors, push/alert/email/SMS templates,
force-update messaging) had no per-account language to select -- everything
was English-only regardless of the account's actual language. This
migration adds a single nullable ``locale`` column to ``user``.

NULL preserves the existing behavior exactly for every pre-existing row: the
request-time/background locale helpers (``kk/localization.py``) fall back to
the ``Accept-Language`` header (request-time) or English (background jobs)
whenever ``User.locale`` is NULL -- "do not invent a language preference for
existing users" (MI-03 scope, matches the MI-02 precedent of never
backfilling a value for existing rows). Only ``en`` / ``ar`` / ``ku`` are
accepted by the application layer (``kk.localization.normalize_locale``);
this column does not itself constrain the value at the database level
(SQLite has no native CHECK-by-enum here, matching the existing precedent of
other short string columns on this table, e.g. ``account_type`` /
``dealer_status``).

A single, deterministic ``ALTER TABLE ... ADD COLUMN`` (via batch mode for
SQLite compatibility) -- no existence-check guard, no server default, no
backfill. This mirrors the established, un-guarded pattern for other
single-nullable-column additions to ``user``/``car``
(e.g. ``b3c4d5e6f7a8`` / ``g2h3i4j5k6l7``).
"""
from __future__ import annotations

from alembic import op
import sqlalchemy as sa


revision = "c6d7e8f9a0b1"
down_revision = "b3c4d5e6f7a8"
branch_labels = None
depends_on = None


def upgrade():
    with op.batch_alter_table("user") as batch_op:
        batch_op.add_column(sa.Column("locale", sa.String(length=8), nullable=True))


def downgrade():
    with op.batch_alter_table("user") as batch_op:
        batch_op.drop_column("locale")
