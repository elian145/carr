"""
Minimal model <-> migrated-schema drift check (see PRODUCTION_AUDIT.md C-07).

Used by:
- kk/tests/test_migration_schema_drift.py (SQLite, fast local/CI check)
- scripts/ci_migration_smoke.py (Postgres, CI `migrations` job)

Keep this file small: one comparison function plus the two documented
exception lists below. Do not grow this into a general schema-diff tool.
"""
from __future__ import annotations

# Migration-created tables that intentionally have no SQLAlchemy model.
# Empty today (verified 2026-09-04, C-07 archaeology): every table
# `flask db upgrade` creates has a corresponding model. Add here ONLY with a
# comment explaining why the table is deliberately model-less.
KNOWN_TABLE_EXCEPTIONS: frozenset[str] = frozenset()

# Pre-existing nullable drift between kk/models.py and the migration that
# created the column: the model declares nullable=False (enforced only at
# the ORM layer via a Python-side default=...) but the migration created the
# column as nullable=True with no server_default/backfill-then-constrain
# step. Tracked as D-05 in PRODUCTION_AUDIT.md; out of scope for the C-07
# PendingSignup cleanup this test was added for. Listed here explicitly so
# genuinely NEW drift still fails this check.
KNOWN_NULLABLE_DRIFT: frozenset[tuple[str, str]] = frozenset(
    {
        ("user", "account_type"),
        ("user", "dealer_status"),
        ("saved_search", "filters"),
    }
)


def compute_schema_drift(inspector, metadata, *, table_exceptions=None, nullable_exceptions=None):
    """
    Compare a live database's inspected schema against SQLAlchemy `metadata`.

    Args:
        inspector: a `sqlalchemy.inspect(engine)` result bound to the DB to
            check (expected to already have the full Alembic chain applied).
        metadata: the SQLAlchemy `MetaData` to compare against (`db.metadata`).
        table_exceptions: migration-created table names to ignore when
            looking for tables with no model.
        nullable_exceptions: set of `(table, column)` tuples to ignore when
            comparing `nullable`.

    Returns a dict with three lists (all empty == no drift):
        - missing_from_migrations: model tables the database does not have.
          Never suppress entries here via `table_exceptions` -- a model
          table with no migration is exactly the class of bug this check
          exists to catch.
        - missing_from_models: database tables (excluding `alembic_version`
          and `table_exceptions`) with no corresponding model.
        - nullable_mismatches: [{table, column, model_nullable,
          migrated_nullable}] for columns present in both, excluding
          `nullable_exceptions`.
    """
    table_exceptions = set(table_exceptions or ())
    nullable_exceptions = set(nullable_exceptions or ())

    db_tables = set(inspector.get_table_names()) - {"alembic_version"}
    model_tables = set(metadata.tables)

    missing_from_migrations = sorted(model_tables - db_tables)
    missing_from_models = sorted(db_tables - model_tables - table_exceptions)

    nullable_mismatches = []
    for table in sorted(model_tables & db_tables):
        db_cols = {c["name"]: bool(c["nullable"]) for c in inspector.get_columns(table)}
        for col in metadata.tables[table].columns:
            if col.name not in db_cols or (table, col.name) in nullable_exceptions:
                continue
            if bool(col.nullable) != db_cols[col.name]:
                nullable_mismatches.append(
                    {
                        "table": table,
                        "column": col.name,
                        "model_nullable": bool(col.nullable),
                        "migrated_nullable": db_cols[col.name],
                    }
                )

    return {
        "missing_from_migrations": missing_from_migrations,
        "missing_from_models": missing_from_models,
        "nullable_mismatches": nullable_mismatches,
    }
