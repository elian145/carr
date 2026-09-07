"""D-05: enforce NOT NULL on user.account_type/dealer_status and saved_search.filters

Revision ID: 3f945e50c327
Revises: d7e6c32b1689
Create Date: 2026-09-07

Production audit item D-05 (see PRODUCTION_AUDIT.md): three columns have
been declared ``nullable=False`` in ``kk/models.py`` since they were added,
but the migrations that created them left the real (SQLite/PostgreSQL)
column ``nullable=True`` at the database level, with no
``server_default``/backfill-then-constrain follow-up:

- ``user.account_type``    (added nullable=True, backfilled once, in
  ``c9d8e7f6a5b4_add_dealer_account_fields.py``; never constrained)
- ``user.dealer_status``   (same migration, same story)
- ``saved_search.filters`` (added nullable=True, never backfilled, in
  ``w1x2y3z4a5b6_add_alerts_retention_tables.py``)

Investigation (D-05, approved) found no live write path that can currently
produce a NULL in any of the three columns: ``kk/routes/auth.py``'s signup
sets ``account_type``/``dealer_status`` explicitly; ``kk/admin_identity.py``
relies on the ORM's Python-side ``default=`` (reliably applied by
SQLAlchemy for both ORM and Core inserts); and
``kk/routes/saved_searches.py``'s ``_clean_filters()`` has unconditionally
returned a ``dict`` (never ``None``) since the very first commit that
introduced saved searches. The backfill below is therefore a defensive,
idempotent safety net (expected to match zero rows in the common case), not
a corrective data fix for a known-bad production state -- it exists so this
migration cannot fail on ``SET NOT NULL`` even if an untracked legacy row
somehow slipped through.

No model changes accompany this migration (``kk/models.py`` already
declares the intended ``nullable=False`` for all three columns) and no
FK/ondelete behavior is touched (that is D-01's domain, already resolved).
This is a schema-nullability-only change: backfill then constrain, per
column, on both dialects.
"""

from __future__ import annotations

from alembic import op
import sqlalchemy as sa


revision = "3f945e50c327"
down_revision = "d7e6c32b1689"
branch_labels = None
depends_on = None


# (column, sqlalchemy type for batch alter_column, backfill default value)
_USER_COLUMNS: list[tuple[str, sa.types.TypeEngine, str]] = [
    ("account_type", sa.String(length=20), "user"),
    ("dealer_status", sa.String(length=20), "none"),
]


def _backfill_string(table: str, column: str, value: str) -> None:
    """Idempotent defensive backfill: UPDATE ... WHERE <column> IS NULL."""
    tbl = sa.table(table, sa.column(column, sa.String()))
    op.execute(tbl.update().where(tbl.c[column].is_(None)).values({column: value}))


def _backfill_json(table: str, column: str) -> None:
    """Same as `_backfill_string`, but for the JSON `saved_search.filters` column."""
    tbl = sa.table(table, sa.column(column, sa.JSON()))
    op.execute(tbl.update().where(tbl.c[column].is_(None)).values({column: {}}))


def _set_sqlite_fk_enforcement(conn, enabled: bool) -> None:
    """Toggle SQLite's `PRAGMA foreign_keys` so it actually takes effect.

    SQLite treats `PRAGMA foreign_keys` as a no-op while a transaction is
    open, and Alembic runs a `flask db upgrade`/`downgrade` invocation
    inside one logical transaction (`context.begin_transaction()` in
    `migrations/env.py`). A plain `op.execute(text("PRAGMA foreign_keys=..."))`
    can therefore silently fail to apply -- observed in practice as the
    toggle back to ON never taking effect when this migration runs as one
    step of a larger from-scratch `flask db upgrade` (e.g. every test that
    boots a fresh app against an empty SQLite file), leaving FK enforcement
    permanently off for the rest of that process's connection.

    `op.get_context().autocommit_block()` is Alembic's own documented
    mechanism for running a statement outside the migration's transaction
    (see the Alembic docs: "the occasional database DDL or system operation
    that specifically has to be run outside of any kind of transaction
    block"). It commits any transaction Alembic is currently tracking via
    the *SQLAlchemy* `Transaction` API (not raw SQL), switches the
    connection to `isolation_level="AUTOCOMMIT"` for the duration of the
    `with` block, and on exit re-establishes Alembic's transaction the same
    way -- so Alembic's own bookkeeping (`MigrationContext._transaction`)
    stays consistent with the real connection state throughout, whether or
    not a real transaction happened to be open when this function was
    called. This only ever runs for SQLite; it has no effect on the
    PostgreSQL path.
    """
    with op.get_context().autocommit_block():
        conn.execute(sa.text(f"PRAGMA foreign_keys={'ON' if enabled else 'OFF'}"))


def upgrade() -> None:
    conn = op.get_bind()
    insp = sa.inspect(conn)

    # D-01 gave several tables (saved_search, user_favorites, notification,
    # token_blacklist, ...) `ON DELETE CASCADE` foreign keys to `user.id`,
    # enforced on SQLite via the `PRAGMA foreign_keys=ON` connection-level
    # event listener in `kk/app_factory.py`. Alembic's SQLite batch mode
    # recreates the *entire* `user` table (rename -> create -> copy -> drop
    # old) to add a NOT NULL constraint -- SQLite has no native
    # `ALTER COLUMN ... SET NOT NULL`. With foreign_keys=ON, dropping the
    # renamed old `user` table at the end of that recreate would cascade
    # into every D-01 cascade-linked child row for every user, which would
    # silently destroy unrelated data. Disable enforcement for the
    # remainder of this migration only; nothing here inserts/deletes rows
    # in a way that depends on FK enforcement being active, and PostgreSQL
    # (the only place these FKs matter for real cascade behavior) is
    # entirely unaffected -- it never takes this branch at all.
    if conn.dialect.name == "sqlite":
        _set_sqlite_fk_enforcement(conn, enabled=False)

    if insp.has_table("user"):
        for column, _col_type, default_value in _USER_COLUMNS:
            _backfill_string("user", column, default_value)

        if conn.dialect.name == "sqlite":
            with op.batch_alter_table("user", schema=None) as batch_op:
                for column, col_type, _default_value in _USER_COLUMNS:
                    batch_op.alter_column(column, existing_type=col_type, nullable=False)
        else:
            for column, _col_type, _default_value in _USER_COLUMNS:
                op.execute(sa.text(f'ALTER TABLE "user" ALTER COLUMN {column} SET NOT NULL'))

    if insp.has_table("saved_search"):
        _backfill_json("saved_search", "filters")

        if conn.dialect.name == "sqlite":
            with op.batch_alter_table("saved_search", schema=None) as batch_op:
                batch_op.alter_column("filters", existing_type=sa.JSON(), nullable=False)
        else:
            op.execute(sa.text("ALTER TABLE saved_search ALTER COLUMN filters SET NOT NULL"))

    if conn.dialect.name == "sqlite":
        _set_sqlite_fk_enforcement(conn, enabled=True)


def downgrade() -> None:
    # Widen back to nullable=True. Existing (non-NULL) data is left exactly
    # as-is -- relaxing a NOT NULL constraint never violates existing rows,
    # so no data changes are needed here, only the constraint.
    conn = op.get_bind()
    insp = sa.inspect(conn)

    # Same reasoning as upgrade(): recreating `user` via SQLite batch mode
    # must not cascade-delete D-01 cascade-linked child rows as a side
    # effect. See the detailed comment in upgrade().
    if conn.dialect.name == "sqlite":
        _set_sqlite_fk_enforcement(conn, enabled=False)

    if insp.has_table("saved_search"):
        if conn.dialect.name == "sqlite":
            with op.batch_alter_table("saved_search", schema=None) as batch_op:
                batch_op.alter_column("filters", existing_type=sa.JSON(), nullable=True)
        else:
            op.execute(sa.text("ALTER TABLE saved_search ALTER COLUMN filters DROP NOT NULL"))

    if insp.has_table("user"):
        if conn.dialect.name == "sqlite":
            with op.batch_alter_table("user", schema=None) as batch_op:
                for column, col_type, _default_value in _USER_COLUMNS:
                    batch_op.alter_column(column, existing_type=col_type, nullable=True)
        else:
            for column, _col_type, _default_value in _USER_COLUMNS:
                op.execute(sa.text(f'ALTER TABLE "user" ALTER COLUMN {column} DROP NOT NULL'))

    if conn.dialect.name == "sqlite":
        _set_sqlite_fk_enforcement(conn, enabled=True)
