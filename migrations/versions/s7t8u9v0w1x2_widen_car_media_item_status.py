"""Widen car_media_item.status from VARCHAR(12) to VARCHAR(32)

Revision ID: s7t8u9v0w1x2
Revises: r5s6t7u8v9w0
Create Date: 2026-09-29

PRODUCTION INCIDENT: immediately after r5s6t7u8v9w0 (the migration that
created `car_media_item`) deployed, `POST /api/cars` started returning
500 on PostgreSQL with:

    psycopg.errors.StringDataRightTruncation:
    value too long for type character varying(12)

Root cause: r5s6t7u8v9w0 declared `car_media_item.status` as
`sa.String(length=12)`, and `kk/models.py`'s `CarMediaItem.status`
mirrored that same (wrong) width as `db.String(12)`. But the very first
value ever written to this column -- the `default='awaiting_upload'`
every row gets at `create_car()` time (see kk/routes/cars.py) -- is 15
characters long. 15 > 12, so PostgreSQL's own `VARCHAR(12)` constraint
rejected the insert outright on every single listing-create call, i.e.
100% of the time, for every seller, immediately on deploy. (SQLite has
no real `VARCHAR(n)` length enforcement at the storage level, which is
why this was never caught locally/in CI against the SQLite test DB --
see `kk/tests/test_migration_schema_drift.py`'s own docstring on this
exact SQLite-vs-Postgres asymmetry, and why the new regression test
added alongside this migration checks the *declared* width
programmatically instead of relying on a real overflow to surface it.)

The four values `status` can ever hold (see `CarMediaItem.ALL_STATUSES`
in kk/models.py, and kk/media_readiness.py's module docstring for the
state machine): `awaiting_upload` (15), `processing` (10), `attached`
(8), `failed` (6). 32 is chosen -- not the tighter 15 -- to leave
headroom for any future state without needing another migration for a
while, matching this repo's existing convention of picking a
comfortably round widened size rather than the exact current maximum
(see d9e0f1a2b3c4/b4e8a1c2d3f4's 200 -> 2048, o1p2q3r4s5t6's same).

DO NOT MODIFY r5s6t7u8v9w0 INSTEAD OF ADDING THIS MIGRATION: r5s6t7u8v9w0
has already been applied against the production database. Editing an
already-applied migration file changes nothing about the live schema --
production's `alembic_version` row already points past it, so
`flask db upgrade` would never re-run it. Only a new migration stacked on
top (this one) can actually change the live column.

`op.batch_alter_table("car_media_item")` is used so this also works on
SQLite (which cannot `ALTER COLUMN` in place); with Alembic's default
`recreate="auto"`, batch mode only recreates the table on backends that
actually need it -- on PostgreSQL this is a single, fast, metadata-only
`ALTER COLUMN ... TYPE VARCHAR(32)` (widening a VARCHAR length never
rewrites existing rows or touches any FK/cascade). `car_media_item` has
no FK enforcement concern on SQLite recreate either: nothing has a
FOREIGN KEY REFERENCES car_media_item(...), it only holds an outgoing FK
to `car.id` -- same "leaf table" precedent already noted in
r5s6t7u8v9w0's own docstring for `car_image`.

ROLLBACK / DOWNGRADE SAFETY
----------------------------
Unlike the pure "widen, never narrow back unsafely" precedents
(d9e0f1a2b3c4/b4e8a1c2d3f4/o1p2q3r4s5t6, where 200 was always big enough
for every value ever written under the old constraint), narrowing this
column back to VARCHAR(12) on downgrade is **not** safe in the general
case: 'awaiting_upload' (15 chars) is the column's own DEFAULT value, so
essentially every `car_media_item` row ever written -- not just some
rare edge case -- is guaranteed to be too long for VARCHAR(12). This
downgrade is therefore left as a documented no-op rather than following
those precedents' "narrow and let the DB's native constraint fail
loudly" pattern: that pattern is appropriate when narrowing MIGHT fail
for some rows; here it would fail for effectively ALL of them, which is
not a useful rollback (it would just make `flask db downgrade` unusable
on any database that has ever run this app, defeating the point of
having a downgrade path at all). Leaving the column at VARCHAR(32) on
downgrade is fully backwards-compatible with every earlier migration
(VARCHAR(32) still accepts every value VARCHAR(12) ever could) and never
truncates or destroys data on either dialect.
"""

from __future__ import annotations

import sqlalchemy as sa
from alembic import op

# revision identifiers, used by Alembic.
revision = "s7t8u9v0w1x2"
down_revision = "r5s6t7u8v9w0"
branch_labels = None
depends_on = None


def upgrade() -> None:
    with op.batch_alter_table("car_media_item", schema=None) as batch_op:
        batch_op.alter_column(
            "status",
            existing_type=sa.String(length=12),
            type_=sa.String(length=32),
            existing_nullable=False,
            existing_server_default=sa.text("'awaiting_upload'"),
        )


def downgrade() -> None:
    # See "ROLLBACK / DOWNGRADE SAFETY" above: narrowing back to
    # VARCHAR(12) would fail for effectively every row this app has ever
    # written (the column's own default, 'awaiting_upload', is 15 chars),
    # so this is deliberately left as a no-op rather than a destructive
    # or guaranteed-to-fail narrowing. The column stays at VARCHAR(32).
    pass
