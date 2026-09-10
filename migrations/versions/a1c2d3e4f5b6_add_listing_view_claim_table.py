"""BE-11: add listing_view_claim table for durable analytics-view dedup

Revision ID: a1c2d3e4f5b6
Revises: 7ae553c40b45
Create Date: 2026-09-11

PRODUCTION_AUDIT.md BE-11: `record_trusted_view()` previously decided
whether to increment `ListingAnalytics.views` using the `is_first_view`
result of `record_user_listing_view()` -- the exact same shared
`user_viewed_listings` upsert already consumed, independently, by the
detail-page GET's best-effort `Car.views_count` bump
(`_increment_views_best_effort()`, `kk/routes/cars.py`). Because both call
sites raced for the same per-(user, car) flag, at most one of the two
counters ever incremented for a single real, authenticated, non-seller
view -- never both -- and which one depended on undefined request-arrival
order (see the BE-11 investigation report for a controlled reproduction).

This migration adds a new, dedicated table -- `listing_view_claim` -- whose
sole purpose is to gate `ListingAnalytics.views` increments, completely
independent of `user_viewed_listings`. A row existing here means "this
user's view of this listing has already been counted"; nothing else reads
or writes it. `record_user_listing_view()` / `user_viewed_listings` and
`Car.views_count` are entirely untouched by this change.

Group-A dependent data (see migration c05b6c97708d's "Group A" policy: rows
that are strictly child/dependent data of their parent and have no
independent value once the parent is gone): both foreign keys are created
with explicit `ON DELETE CASCADE` from the start, matching the existing
`user_viewed_listings` / `user_favorites` association tables exactly --
no follow-up "make explicit" migration is needed since this table is new.

The composite uniqueness guarantee -- `UniqueConstraint(user_id, car_id)`
-- is the actual concurrency primitive
(`kk.listing_metrics.claim_listing_view_once()` relies on the database
rejecting a duplicate insert, not on any Python-side existence check).
Supported on both SQLite and PostgreSQL identically via
`sa.UniqueConstraint(...)` passed inline to `op.create_table(...)`, so no
Alembic batch mode is needed here (this is a brand-new table, not an
in-place alter of an existing one).

downgrade() only drops the table it created; no other table is touched.
"""
from __future__ import annotations

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision = "a1c2d3e4f5b6"
down_revision = "7ae553c40b45"
branch_labels = None
depends_on = None


_TABLE_NAME = "listing_view_claim"
_UNIQUE_CONSTRAINT_NAME = "uq_listing_view_claim_user_car"


def _has_table(conn, name: str) -> bool:
    try:
        return bool(sa.inspect(conn).has_table(name))
    except Exception:
        return False


def upgrade():
    conn = op.get_bind()
    if _has_table(conn, _TABLE_NAME):
        return

    op.create_table(
        _TABLE_NAME,
        sa.Column("id", sa.Integer(), nullable=False),
        sa.Column("user_id", sa.Integer(), nullable=False),
        sa.Column("car_id", sa.Integer(), nullable=False),
        sa.Column("claimed_at", sa.DateTime(), nullable=False),
        sa.ForeignKeyConstraint(["user_id"], ["user.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["car_id"], ["car.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("user_id", "car_id", name=_UNIQUE_CONSTRAINT_NAME),
    )
    op.create_index(
        "ix_listing_view_claim_user_id", _TABLE_NAME, ["user_id"], unique=False
    )
    op.create_index(
        "ix_listing_view_claim_car_id", _TABLE_NAME, ["car_id"], unique=False
    )


def downgrade():
    conn = op.get_bind()
    if not _has_table(conn, _TABLE_NAME):
        return
    op.drop_index("ix_listing_view_claim_car_id", table_name=_TABLE_NAME)
    op.drop_index("ix_listing_view_claim_user_id", table_name=_TABLE_NAME)
    op.drop_table(_TABLE_NAME)
