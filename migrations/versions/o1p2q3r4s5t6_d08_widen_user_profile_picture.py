"""D-08: widen user.profile_picture to String(2048)

Revision ID: o1p2q3r4s5t6
Revises: n5o6p7q8r9s0
Create Date: 2026-09-08

PRODUCTION_AUDIT.md D-08 flagged `user.profile_picture` as `String(200)`
while the equivalent R2/CDN media-URL columns (`car_image.image_url`,
`car_video.video_url`, `car_video.thumbnail_url`) were already widened to
`String(2048)` (see d9e0f1a2b3c4 / b4e8a1c2d3f4). `profile_picture` is
populated by the exact same R2 upload backend (`kk/r2_ops.py`) via
`POST /api/user/upload-profile-picture` (kk/routes/user.py), so it is
subject to the same "full HTTPS CDN URL" width requirement -- and, via its
local-fallback path, an unbounded client-supplied filename
(`werkzeug.utils.secure_filename()` performs no length cap), which is a
more realistic overflow vector than the R2 path's own short, randomly
generated key.

This is a pure widen, exactly mirroring the two existing precedents:
- No backfill: widening never invalidates or truncates any existing value
  (200 <= 2048 for every row that could have been written under the old
  constraint).
- `nullable=True` is preserved exactly as-is.
- Only `user.profile_picture` is touched. `user.dealership_cover_picture`
  and `dealer_profile.dealership_cover_picture` are a separate, adjacent
  D-08-shaped risk but are NOT named by the D-08 audit row and are
  deliberately left untouched here -- out of scope for this migration.

`op.batch_alter_table("user")` is used (not plain `op.alter_column()`)
because SQLite cannot ALTER COLUMN in place; with Alembic's default
`recreate="auto"`, batch mode only recreates the table on backends that
actually need it. On PostgreSQL this executes as a single, fast, in-place
`ALTER COLUMN ... TYPE VARCHAR(2048)` (widening a VARCHAR length is a
metadata-only change there; no table rewrite, no FK/cascade concern at
all -- the guard below is never reached on that dialect).

On SQLite, however, batch mode recreates the *entire* `user` table
(rename -> create -> copy -> drop old) to change the column, exactly like
`3f945e50c327` (D-05) already had to handle for this same table. D-01
gave several tables (`saved_search`, `user_favorites`,
`user_viewed_listings`, `notification`, `user_action`, `password_reset`,
`email_verification`, ...) `ON DELETE CASCADE` foreign keys to `user.id`,
enforced on SQLite via the `PRAGMA foreign_keys=ON` connection-level event
listener in `kk/app_factory.py`. With foreign_keys=ON, dropping the
renamed old `user` table at the end of that recreate would cascade into
every D-01 cascade-linked child row for every user, silently destroying
unrelated data -- this was directly observed while developing this
migration (it broke `kk/tests/test_d05_nullability_backfill.py`, which
seeds a cascade-linked `saved_search` row and runs the full migration
chain through this new revision). This migration therefore disables
SQLite FK enforcement for the duration of the batch operation only,
using the exact same `_set_sqlite_fk_enforcement()` helper/pattern as
D-05 (duplicated here rather than shared, matching this repo's existing
convention of self-contained migration files).

ROLLBACK / DOWNGRADE SAFETY
----------------------------
`downgrade()` narrows `profile_picture` back from `String(2048)` to
`String(200)`. If this migration has been live for any length of time in
production, rows with a genuine >200-char value (a real R2/CDN URL, or a
local-fallback path built from an unusually long client filename -- see
above) may already exist. This section documents, deliberately, what
happens to that data on downgrade rather than adding new guard code for
it -- no bespoke "check row lengths before narrowing" pattern exists
anywhere else in this 53-migration chain, and the two direct precedents
for this exact widen/narrow shape -- `d9e0f1a2b3c4` (car_image.image_url)
and `b4e8a1c2d3f4` (car_video.video_url/thumbnail_url) -- both narrow
2048 -> 200 on downgrade with *zero* pre-checking, relying entirely on
each database engine's own native type-constraint enforcement. This
migration follows that same established, already-shipped convention
rather than inventing a new one:

- On PostgreSQL: `ALTER COLUMN profile_picture TYPE VARCHAR(200)` is a
  single DDL statement that PostgreSQL validates against every existing
  row as part of applying the type change (equivalent to an implicit
  `CAST` per row). If *any* row's current value is longer than 200
  characters, PostgreSQL raises `ERROR: value too long for type character
  varying(200)`, the `ALTER TABLE` fails, and -- because this runs inside
  Alembic's own migration transaction -- the *entire* downgrade is rolled
  back atomically. Nothing is truncated and nothing is destroyed: the
  column stays at `VARCHAR(2048)` with all data fully intact, exactly as
  it was before the downgrade was attempted. The operator gets a loud,
  actionable failure (identify/shorten the offending row(s), or don't
  downgrade) instead of silent data loss. This is the same fail-closed
  outcome `d9e0f1a2b3c4`/`b4e8a1c2d3f4` already accept for their
  identical downgrade shape.
- On SQLite: SQLite has no real `VARCHAR(n)` length enforcement at the
  storage engine level regardless of the declared column width (verified
  directly against a real `sqlite3` connection during this migration's
  development -- a 300-char value written to a column declared
  `VARCHAR(200)` is stored and read back in full, unmodified, with no
  error). Batch mode's recreate-and-copy does not add any coercion or
  length check either -- it is a plain `INSERT INTO new_table SELECT *
  FROM old_table`. So on SQLite, `downgrade()` always "succeeds": the
  column's *declared* type metadata narrows to `VARCHAR(200)`, but any
  *existing* value's actual stored bytes are copied through completely
  unchanged, however long they are. Nothing is truncated and nothing is
  destroyed here either -- SQLite just silently stops advertising a width
  guarantee it never enforced in the first place. This asymmetry (Postgres
  fails loudly; SQLite silently allows it) is exactly the same asymmetry
  that already exists for every other narrowing downgrade in this repo
  (including `d9e0f1a2b3c4`/`b4e8a1c2d3f4`) and for the D-05 NOT NULL
  downgrade's own dialect split -- it is not new here, only made explicit.
  See `kk/tests/test_d08_profile_picture_width.py::
  test_downgrade_with_over_200_char_value_does_not_truncate_on_sqlite` for
  a direct, empirical proof of this SQLite behavior.

In short: this downgrade can never silently corrupt or truncate data on
either dialect. On PostgreSQL it fails the migration outright if unsafe;
on SQLite it is a no-op with respect to already-stored data (only the
schema's advertised width narrows). No additional guard code is added
because PostgreSQL's own native enforcement already provides the exact
"fail loudly, never truncate" guarantee this concern calls for.
"""

from __future__ import annotations

import sqlalchemy as sa
from alembic import op


revision = "o1p2q3r4s5t6"
down_revision = "n5o6p7q8r9s0"
branch_labels = None
depends_on = None


def _set_sqlite_fk_enforcement(conn, enabled: bool) -> None:
    """Toggle SQLite's `PRAGMA foreign_keys` so it actually takes effect.

    SQLite treats `PRAGMA foreign_keys` as a no-op while a transaction is
    open, and Alembic runs a `flask db upgrade`/`downgrade` invocation
    inside one logical transaction (`context.begin_transaction()` in
    `migrations/env.py`). `op.get_context().autocommit_block()` is
    Alembic's own documented mechanism for running a statement outside the
    migration's transaction -- see `3f945e50c327`'s identical helper for
    the full reasoning. This only ever runs for SQLite; it has no effect
    on the PostgreSQL path.
    """
    with op.get_context().autocommit_block():
        conn.execute(sa.text(f"PRAGMA foreign_keys={'ON' if enabled else 'OFF'}"))


def upgrade() -> None:
    conn = op.get_bind()
    is_sqlite = conn.dialect.name == "sqlite"

    if is_sqlite:
        _set_sqlite_fk_enforcement(conn, enabled=False)

    with op.batch_alter_table("user", schema=None) as batch_op:
        batch_op.alter_column(
            "profile_picture",
            existing_type=sa.String(length=200),
            type_=sa.String(length=2048),
            existing_nullable=True,
        )

    if is_sqlite:
        _set_sqlite_fk_enforcement(conn, enabled=True)


def downgrade() -> None:
    # See "ROLLBACK / DOWNGRADE SAFETY" above: narrowing 2048 -> 200 is
    # deliberately left to each database's own native type-constraint
    # enforcement (the same convention already used by this migration's
    # two precedents, d9e0f1a2b3c4 / b4e8a1c2d3f4). No pre-check is added
    # here. On PostgreSQL, a genuine >200-char value causes this
    # `ALTER COLUMN` to fail loudly and the whole downgrade to roll back
    # atomically -- no data is destroyed or truncated. On SQLite, which
    # never enforces `VARCHAR(n)` at the storage level, the narrowing
    # "succeeds" as a no-op with respect to any already-stored value's
    # actual bytes -- also never truncated.
    conn = op.get_bind()
    is_sqlite = conn.dialect.name == "sqlite"

    if is_sqlite:
        _set_sqlite_fk_enforcement(conn, enabled=False)

    with op.batch_alter_table("user", schema=None) as batch_op:
        batch_op.alter_column(
            "profile_picture",
            existing_type=sa.String(length=2048),
            type_=sa.String(length=200),
            existing_nullable=True,
        )

    if is_sqlite:
        _set_sqlite_fk_enforcement(conn, enabled=True)
