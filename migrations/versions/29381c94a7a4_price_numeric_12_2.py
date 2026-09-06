"""C-11: store money as Numeric(12, 2), not Float

Revision ID: 29381c94a7a4
Revises: d2e3f4a5b6c7
Create Date: 2026-09-06

Money must not be stored as IEEE-754 binary float: floats cannot represent
common decimal values exactly, so prices drift on round-trips/arithmetic
(see PRODUCTION_AUDIT.md C-11). This migration converts the two monetary
columns from ``Float`` to ``Numeric(12, 2)``:

- ``car.price``
- ``user_favorites.price_at_favorite`` (nullable — NULLs are preserved)

PostgreSQL (production/CI ``migrations`` job): a native
``ALTER COLUMN ... TYPE NUMERIC(12, 2) USING ROUND(<col>::numeric, 2)``.
The explicit ``ROUND(..., 2)`` in the ``USING`` clause is the backfill step:
it normalizes any pre-existing binary float noise (e.g.
``12000.000000000002``, which can accumulate from float8 storage/arithmetic)
to an exact 2-decimal-place value *during* the type conversion, in the same
statement, so there is no separate backfill pass and no window where the
column has already changed type but still holds unrounded values.
``ROUND(NULL::numeric, 2)`` evaluates to ``NULL``, so nullable
``price_at_favorite`` rows stay ``NULL`` (not coerced to ``0``).

SQLite (local dev / `kk/tests` convenience): there is no native FLOAT vs
NUMERIC distinction (SQLite uses dynamic column typing / type affinity, and
stores whatever byte-exact value Python handed it), so there is no
float-noise to round there. This branch uses ``batch_alter_table`` (as the
rest of this migration chain already does for SQLite, e.g.
``b4e8a1c2d3f4_car_video_url_longer_for_r2.py``) purely to keep the
declared schema consistent with the ORM model on local/test databases.

Indexes on ``car.price`` (``ix_car_price``, ``ix_car_active_brand_price``,
``ix_car_active_year_price``) and the `user_favorites` primary key are left
alone: PostgreSQL's ``ALTER COLUMN ... TYPE`` rewrites the table and rebuilds
dependent indexes automatically in the same statement, and Alembic's SQLite
batch-table-recreation reflects and recreates existing indexes by default.
"""
from __future__ import annotations

from alembic import op
import sqlalchemy as sa


revision = "29381c94a7a4"
down_revision = "d2e3f4a5b6c7"
branch_labels = None
depends_on = None


def upgrade() -> None:
    conn = op.get_bind()
    if conn.dialect.name == "postgresql":
        op.execute(
            sa.text(
                "ALTER TABLE car ALTER COLUMN price "
                "TYPE NUMERIC(12, 2) USING ROUND(price::numeric, 2)"
            )
        )
        op.execute(
            sa.text(
                "ALTER TABLE user_favorites ALTER COLUMN price_at_favorite "
                "TYPE NUMERIC(12, 2) "
                "USING ROUND(price_at_favorite::numeric, 2)"
            )
        )
        return

    # SQLite (and any other non-Postgres dialect): schema-declaration-only
    # type change; no float noise to backfill on this backend (see module
    # docstring).
    with op.batch_alter_table("car", schema=None) as batch_op:
        batch_op.alter_column(
            "price",
            existing_type=sa.Float(),
            type_=sa.Numeric(12, 2),
            existing_nullable=False,
        )
    with op.batch_alter_table("user_favorites", schema=None) as batch_op:
        batch_op.alter_column(
            "price_at_favorite",
            existing_type=sa.Float(),
            type_=sa.Numeric(12, 2),
            existing_nullable=True,
        )


def downgrade() -> None:
    conn = op.get_bind()
    if conn.dialect.name == "postgresql":
        # Reasonable downgrade back to Float; precision loss on downgrade
        # (beyond double's ~15-17 significant digits) is acceptable — this
        # only matters if a rollback is ever needed after the forward
        # migration has already run.
        op.execute(
            sa.text("ALTER TABLE car ALTER COLUMN price TYPE DOUBLE PRECISION")
        )
        op.execute(
            sa.text(
                "ALTER TABLE user_favorites ALTER COLUMN price_at_favorite "
                "TYPE DOUBLE PRECISION"
            )
        )
        return

    with op.batch_alter_table("user_favorites", schema=None) as batch_op:
        batch_op.alter_column(
            "price_at_favorite",
            existing_type=sa.Numeric(12, 2),
            type_=sa.Float(),
            existing_nullable=True,
        )
    with op.batch_alter_table("car", schema=None) as batch_op:
        batch_op.alter_column(
            "price",
            existing_type=sa.Numeric(12, 2),
            type_=sa.Float(),
            existing_nullable=False,
        )
