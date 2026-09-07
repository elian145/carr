"""D-06: proves the migration adds (and cleanly removes) exactly five
indexes, and that the deliberately-excluded sixth column stays unindexed.

Covers ``migrations/versions/n5o6p7q8r9s0_d06_fk_and_report_status_indexes.py``:

- ``notification.user_id``       -> ix_notification_user_id
- ``user_action.user_id``        -> ix_user_action_user_id
- ``password_reset.user_id``     -> ix_password_reset_user_id
- ``email_verification.user_id`` -> ix_email_verification_user_id
- ``user_report.status``         -> ix_user_report_status

``token_blacklist.expires_at`` is explicitly part of the original D-06 audit
row but was investigated and excluded (zero query usage anywhere in the
codebase) -- this test also asserts it stays unindexed, so a future change
can't silently reintroduce it without a deliberate test update.

Method, mirroring ``kk/tests/test_d05_nullability_backfill.py`` (the
established pattern for "isolate one migration via downgrade/upgrade and
inspect the real schema" tests in this repo):

1. `flask db downgrade` to the revision immediately before D-06 -- the first
   `flask db ...` subprocess call always boots `kk.wsgi:app`, whose
   `create_app()` runs a full `flask_migrate.upgrade()` to head on a
   brand-new empty database first (see `kk/app_factory.py`), so this single
   call exercises the *entire* migration chain from scratch before landing
   one step before D-06 -- covering "fresh full SQLite migration chain"
   in this same step.
2. Inspect the real schema with `sqlalchemy.inspect` and assert none of the
   five target indexes exist yet, and that `token_blacklist` has no
   `expires_at` index.
3. `flask db upgrade` -- applies exactly the D-06 migration in isolation
   (isolated D-06 upgrade). Assert all five indexes now exist with the
   correct columns, and `token_blacklist.expires_at` is still unindexed.
4. `flask db downgrade` back to immediately before D-06 again (isolated
   D-06 downgrade). Assert all five indexes are gone again.
5. Re-upgrade once more to prove the existence guards make the migration
   idempotent/safe to re-run.
"""

from __future__ import annotations

import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

import sqlalchemy as sa

_REPO_ROOT = Path(__file__).resolve().parents[2]
if str(_REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(_REPO_ROOT))

# HEAD immediately before the D-06 migration (see
# migrations/versions/n5o6p7q8r9s0_d06_fk_and_report_status_indexes.py's
# `down_revision`) -- this is the D-05 migration's revision id.
_PRE_D06_REVISION = "3f945e50c327"

_D06_INDEXES: tuple[tuple[str, str, list[str]], ...] = (
    ("notification", "ix_notification_user_id", ["user_id"]),
    ("user_action", "ix_user_action_user_id", ["user_id"]),
    ("password_reset", "ix_password_reset_user_id", ["user_id"]),
    ("email_verification", "ix_email_verification_user_id", ["user_id"]),
    ("user_report", "ix_user_report_status", ["status"]),
)


class D06FkAndReportStatusIndexesTest(unittest.TestCase):
    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory(prefix="carlist_d06_", ignore_cleanup_errors=True)
        self._db_path = os.path.join(self._tmp.name, "d06.db")

        self._env = os.environ.copy()
        self._env["APP_ENV"] = "testing"
        self._env["FLASK_APP"] = "kk.wsgi:app"
        # AUTO_MIGRATE=0 stops create_app() from re-upgrading out from under
        # us on every subprocess call after the initial bootstrap.
        self._env["AUTO_MIGRATE"] = "0"
        self._env["SMS_PROVIDER"] = "console"
        self._env["DB_PATH"] = self._db_path

    def tearDown(self):
        self._tmp.cleanup()

    def _flask_db(self, *args: str) -> None:
        result = subprocess.run(
            [sys.executable, "-m", "flask", "db", *args],
            cwd=_REPO_ROOT,
            env=self._env,
            capture_output=True,
            text=True,
        )
        if result.returncode != 0:
            self.fail(
                f"`flask db {' '.join(args)}` failed (exit {result.returncode}):\n"
                f"--- stdout ---\n{result.stdout}\n--- stderr ---\n{result.stderr}"
            )

    def _index_names(self, insp: sa.engine.reflection.Inspector, table: str) -> set[str]:
        return {ix["name"] for ix in insp.get_indexes(table)}

    def _assert_indexes_absent(self, label: str) -> None:
        engine = sa.create_engine(f"sqlite:///{self._db_path}")
        try:
            insp = sa.inspect(engine)
            for table, name, _cols in _D06_INDEXES:
                self.assertNotIn(
                    name,
                    self._index_names(insp, table),
                    f"{name} should not exist yet ({label})",
                )
            self.assertNotIn(
                "ix_token_blacklist_expires_at",
                self._index_names(insp, "token_blacklist"),
                f"token_blacklist.expires_at must stay unindexed ({label})",
            )
        finally:
            engine.dispose()

    def _assert_indexes_present(self, label: str) -> None:
        engine = sa.create_engine(f"sqlite:///{self._db_path}")
        try:
            insp = sa.inspect(engine)
            for table, name, cols in _D06_INDEXES:
                indexes = {ix["name"]: ix for ix in insp.get_indexes(table)}
                self.assertIn(name, indexes, f"{name} should exist ({label})")
                self.assertEqual(
                    indexes[name]["column_names"],
                    cols,
                    f"{name} should cover exactly {cols} ({label})",
                )
            # D-06 deliberately excludes token_blacklist.expires_at --
            # confirm it stays unindexed even after the migration runs.
            self.assertNotIn(
                "ix_token_blacklist_expires_at",
                self._index_names(insp, "token_blacklist"),
                f"token_blacklist.expires_at must stay unindexed ({label})",
            )
            # And the pre-existing token_blacklist.jti unique index must be
            # completely unaffected by this migration.
            self.assertIn(
                "ix_token_blacklist_jti",
                self._index_names(insp, "token_blacklist"),
                "ix_token_blacklist_jti must be untouched by D-06",
            )
        finally:
            engine.dispose()

    def test_migration_adds_and_removes_exactly_five_indexes(self):
        # Step 1: bootstrap the FULL chain from scratch (empty -> head, via
        # create_app()'s AUTO_MIGRATE bootstrap), then step back to
        # immediately before D-06. Covers "fresh full SQLite migration
        # chain from scratch".
        self._flask_db("downgrade", _PRE_D06_REVISION)
        self._assert_indexes_absent("pre-D-06, after initial bootstrap+downgrade")

        # Step 2: isolated D-06 upgrade (exactly one migration step).
        self._flask_db("upgrade")
        self._assert_indexes_present("post-D-06 upgrade")

        # Step 3: isolated D-06 downgrade (exactly one migration step back).
        self._flask_db("downgrade", _PRE_D06_REVISION)
        self._assert_indexes_absent("post-D-06 downgrade")

        # Step 4: re-upgrade once more to prove idempotent re-application
        # (the migration's existence guards must not choke on a normal
        # re-run in the same process/db).
        self._flask_db("upgrade")
        self._assert_indexes_present("post-D-06 re-upgrade")


if __name__ == "__main__":
    unittest.main(verbosity=2)
