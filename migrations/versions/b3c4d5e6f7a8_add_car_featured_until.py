"""MI-02: add featured_until column to car

Revision ID: b3c4d5e6f7a8
Revises: a1c2d3e4f5b6
Create Date: 2026-09-17

PRODUCTION_AUDIT.md MI-02: ``Car.is_featured`` had no expiry -- once an
admin set it, a listing stayed featured forever (no ``featured_until``
column, no un-feature job). This migration adds a single nullable
``featured_until`` DateTime column to ``car``. NULL preserves the existing
behavior exactly (indefinite feature, matching every pre-existing row and
every admin action that omits an expiry); a non-NULL value lets a listing
be featured only until that UTC timestamp.

Query-time enforcement (``Car.effective_featured_expr()`` /
``Car.is_effectively_featured``) is the correctness mechanism for expiry --
this column addition alone does not change any existing row's behavior.
No server default is used and no existing rows are backfilled with a value:
"do not invent expiry dates for existing featured rows" (MI-02 scope).

A single, deterministic ``ALTER TABLE ... ADD COLUMN`` (via batch mode for
SQLite compatibility) -- no existence-check guard. This is a brand-new,
one-shot column addition (not a multi-step/multi-dialect migration recovering
a partially-applied prior run, e.g. ``d4e5f6a7b8c9``, nor a legacy database
with inconsistent history), so there is no legitimate partial-run scenario to
defend against; an existence guard here would only ever fire on genuinely
unexpected schema drift (e.g. an out-of-band column of the same name) and
would silently no-op instead of failing loudly, which is exactly what the
D-02 migration hardening was meant to prevent. This matches the established,
un-guarded pattern for every other single-nullable-column addition to `car`
(e.g. ``g2h3i4j5k6l7`` / ``f8a1c2d3e4b5``).
"""
from __future__ import annotations

from alembic import op
import sqlalchemy as sa


revision = "b3c4d5e6f7a8"
down_revision = "a1c2d3e4f5b6"
branch_labels = None
depends_on = None


def upgrade():
    with op.batch_alter_table("car") as batch_op:
        batch_op.add_column(sa.Column("featured_until", sa.DateTime(), nullable=True))


def downgrade():
    with op.batch_alter_table("car") as batch_op:
        batch_op.drop_column("featured_until")
