"""
C-07 regression: every SQLAlchemy model table must be created by the
Alembic migration chain, and every migration-created table must have a
model (unless documented in kk/schema_drift.py).

This builds a throwaway SQLite database via `flask db upgrade` ONLY (the
create_app() bootstrap's db.create_all() fallback is never reached because
the database starts out genuinely empty and AUTO_MIGRATE defaults to "1"),
so this proves what a real `flask db upgrade` deploy actually produces --
not what the ORM models declare. See kk/schema_drift.py and the C-07
section of PRODUCTION_AUDIT.md.
"""
from __future__ import annotations

import os
import sys
import tempfile
import unittest
from pathlib import Path

_REPO_ROOT = Path(__file__).resolve().parents[2]
if str(_REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(_REPO_ROOT))


class MigrationSchemaDriftTest(unittest.TestCase):
    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory(
            prefix="carlist_c07_drift_", ignore_cleanup_errors=True
        )
        os.environ["APP_ENV"] = "testing"
        os.environ["DB_PATH"] = os.path.join(self._tmp.name, "c07_drift.db")
        # Default AUTO_MIGRATE ("1"): create_app()'s bootstrap sees the fresh,
        # empty SQLite file and runs `flask_migrate.upgrade()` -- the same
        # code path Render's start_render.sh drives -- never db.create_all().
        os.environ.pop("AUTO_MIGRATE", None)
        os.environ["SMS_PROVIDER"] = "console"

        from kk.app_factory import create_app

        self.app, *_ = create_app()

    def tearDown(self):
        with self.app.app_context():
            from kk.extensions import db

            try:
                db.session.remove()
            except Exception:
                pass
            try:
                db.engine.dispose()
            except Exception:
                pass
        self._tmp.cleanup()

    def test_migrated_schema_matches_models(self):
        from sqlalchemy import inspect

        from kk.extensions import db
        from kk.schema_drift import (
            KNOWN_NULLABLE_DRIFT,
            KNOWN_TABLE_EXCEPTIONS,
            compute_schema_drift,
        )

        with self.app.app_context():
            insp = inspect(db.engine)
            drift = compute_schema_drift(
                insp,
                db.metadata,
                table_exceptions=KNOWN_TABLE_EXCEPTIONS,
                nullable_exceptions=KNOWN_NULLABLE_DRIFT,
            )

        self.assertEqual(
            drift["missing_from_migrations"],
            [],
            "Model table(s) with no Alembic migration creating them -- "
            "`flask db upgrade` on a fresh database will NOT have these "
            f"tables (PRODUCTION_AUDIT.md C-07): {drift['missing_from_migrations']}",
        )
        self.assertEqual(
            drift["missing_from_models"],
            [],
            "Migration-created table(s) with no SQLAlchemy model (add to "
            "KNOWN_TABLE_EXCEPTIONS in kk/schema_drift.py if this is "
            f"intentional): {drift['missing_from_models']}",
        )
        self.assertEqual(
            drift["nullable_mismatches"],
            [],
            "New nullable drift between a model and its migration (add to "
            "KNOWN_NULLABLE_DRIFT in kk/schema_drift.py only if this is a "
            f"pre-existing, already-tracked issue): {drift['nullable_mismatches']}",
        )


if __name__ == "__main__":
    unittest.main(verbosity=2)
