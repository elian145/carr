"""Add saved_search_alert_job (F-04 durable saved-search alert delivery).

Revision ID: f04a1b2c3d4e
Revises: v0w1x2y3z4a5
Create Date: 2026-11-06

One table, ``saved_search_alert_job``: a transactional marker "saved-search
alerts are owed for this listing", inserted in the same transaction that
publishes the listing (only while the ``SAVED_SEARCH_ALERT_DURABILITY`` flag
is ``record`` or ``on``; the flag defaults to ``off``, so this migration alone
changes no behaviour). ``UNIQUE(car_id)`` is the first-publication marker:
a listing gets at most one job, ever.

PURELY ADDITIVE: one new table, one unique constraint and one index. No
existing table, column, constraint or row is touched, nothing is backfilled
(listings published before the feature are deliberately never alerted
retroactively), and the application code currently in production (which never
reads this table) keeps working against the upgraded schema. The foreign key
to ``car`` is ``ON DELETE CASCADE`` so a job can never block a listing delete.

Downgrade drops the table only (pending/finished job history is lost;
listings, saved searches and ``saved_search_alert`` de-dupe rows are
unaffected).
"""

from __future__ import annotations

import sqlalchemy as sa
from alembic import op

# revision identifiers, used by Alembic.
revision = "f04a1b2c3d4e"
down_revision = "v0w1x2y3z4a5"
branch_labels = None
depends_on = None


def upgrade() -> None:
    # Creating a table with a foreign key briefly needs SHARE ROW EXCLUSIVE on
    # the referenced table (car). Bound the wait so the migration fails fast
    # (the deploy stops, the running release keeps serving) instead of queueing
    # every later write to ``car`` behind this DDL. Transaction-local.
    if op.get_bind().dialect.name == "postgresql":
        op.execute("SET LOCAL lock_timeout = '5s'")

    op.create_table(
        "saved_search_alert_job",
        sa.Column("id", sa.Integer(), nullable=False),
        sa.Column("car_id", sa.Integer(), nullable=False),
        sa.Column("created_at", sa.DateTime(), nullable=False),
        sa.Column("claimed_at", sa.DateTime(), nullable=True),
        sa.Column("next_run_at", sa.DateTime(), nullable=True),
        sa.Column("finished_at", sa.DateTime(), nullable=True),
        sa.Column("outcome", sa.String(length=16), nullable=True),
        sa.Column("attempts", sa.Integer(), server_default="0", nullable=False),
        sa.Column("last_error", sa.String(length=255), nullable=True),
        sa.ForeignKeyConstraint(["car_id"], ["car.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("car_id", name="uq_saved_search_alert_job_car"),
    )
    op.create_index(
        "ix_saved_search_alert_job_pending",
        "saved_search_alert_job",
        ["finished_at", "created_at"],
        unique=False,
    )


def downgrade() -> None:
    op.drop_index("ix_saved_search_alert_job_pending", table_name="saved_search_alert_job")
    op.drop_table("saved_search_alert_job")
