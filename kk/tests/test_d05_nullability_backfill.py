"""D-05: nullability hardening -- proves the *migration* fixes the database.

Covers ``migrations/versions/3f945e50c327_d05_nullability_hardening.py``:

- ``user.account_type``
- ``user.dealer_status``
- ``saved_search.filters``

This does NOT test SQLAlchemy model-level validation (the model has always
declared ``nullable=False`` for these three columns -- that was never the
gap). It proves the *database schema itself* now rejects NULL, and that the
migration's defensive backfill step correctly repairs any pre-existing NULL
row without touching already-clean rows.

Method, mirroring ``scripts/ci_migration_smoke.py::_c11_price_numeric_round_trip``
(the established pattern in this repo for "seed pre-migration data, run the
migration, assert on the result" tests):

1. Boot a fresh SQLite DB (bootstrap runs the full migration chain to head,
   `AUTO_MIGRATE=0` so nothing auto-migrates again afterward).
2. `flask db downgrade` to the revision immediately before D-05 -- this
   widens the three columns back to nullable via D-05's own `downgrade()`.
3. Insert rows directly via the stdlib `sqlite3` module (NOT the ORM, NOT
   SQLAlchemy Core) with explicit NULLs in the target columns. This is the
   only way to prove the fix at the database level: any SQLAlchemy-based
   insert would apply the model's Python-side `default=...` and mask
   exactly the gap this migration closes.
4. `flask db upgrade` back to head (D-05) and re-inspect with raw
   `sqlite3` again.

Assertions:
- Previously-NULL rows are backfilled to the documented defaults.
- Pre-existing non-NULL rows are left untouched (no clobbering).
- The database itself (not the model) now rejects a raw NULL insert.
"""

from __future__ import annotations

import os
import sqlite3
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

_REPO_ROOT = Path(__file__).resolve().parents[2]
if str(_REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(_REPO_ROOT))

# HEAD immediately before the D-05 migration (see
# migrations/versions/3f945e50c327_d05_nullability_hardening.py's
# `down_revision`).
_PRE_D05_REVISION = "d7e6c32b1689"


class D05NullabilityBackfillTest(unittest.TestCase):
    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory(prefix="carlist_d05_", ignore_cleanup_errors=True)
        self._db_path = os.path.join(self._tmp.name, "d05.db")

        self._env = os.environ.copy()
        self._env["APP_ENV"] = "testing"
        self._env["FLASK_APP"] = "kk.wsgi:app"
        # Once the initial bootstrap has created the schema, we drive every
        # further migration step explicitly via `flask db downgrade`/
        # `upgrade` -- AUTO_MIGRATE=0 stops create_app() from re-upgrading
        # out from under us on every subprocess call.
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

    def test_migration_backfills_nulls_and_enforces_not_null(self):
        # Step 1: boot to head, then step back to right before D-05. The
        # first `flask db ...` invocation always loads `kk.wsgi:app`, whose
        # create_app() bootstrap runs a full `flask_migrate.upgrade()` to
        # head on a brand-new empty database (see kk/app_factory.py) before
        # the CLI's own `downgrade` argument is applied -- so this single
        # call reliably lands exactly on `_PRE_D05_REVISION` regardless.
        self._flask_db("downgrade", _PRE_D05_REVISION)

        conn = sqlite3.connect(self._db_path)
        try:
            conn.execute("PRAGMA foreign_keys = OFF")

            # "Dirty" user: account_type/dealer_status explicitly NULL,
            # inserted via raw sqlite3 so no ORM/Core default ever runs.
            conn.execute(
                "INSERT INTO user "
                "(public_id, username, password_hash, phone_number, first_name, last_name, "
                " account_type, dealer_status) "
                "VALUES ('d05-dirty-user', 'd05_dirty_user', 'x', '0790000001', 'Dirty', 'User', "
                " NULL, NULL)"
            )
            dirty_user_id = conn.execute(
                "SELECT id FROM user WHERE username = 'd05_dirty_user'"
            ).fetchone()[0]

            # "Clean" user: explicit non-NULL, non-default values, to prove
            # the backfill does not clobber legitimate existing data.
            conn.execute(
                "INSERT INTO user "
                "(public_id, username, password_hash, phone_number, first_name, last_name, "
                " account_type, dealer_status) "
                "VALUES ('d05-clean-user', 'd05_clean_user', 'x', '0790000002', 'Clean', 'User', "
                " 'dealer', 'approved')"
            )
            clean_user_id = conn.execute(
                "SELECT id FROM user WHERE username = 'd05_clean_user'"
            ).fetchone()[0]

            # "Dirty" saved_search: filters explicitly NULL.
            conn.execute(
                "INSERT INTO saved_search (public_id, user_id, name, filters, notify, auto_saved) "
                "VALUES ('d05-dirty-search', ?, 'Dirty search', NULL, 1, 0)",
                (clean_user_id,),
            )
            dirty_search_id = conn.execute(
                "SELECT id FROM saved_search WHERE public_id = 'd05-dirty-search'"
            ).fetchone()[0]

            # "Clean" saved_search: explicit non-empty JSON, to prove the
            # backfill does not clobber legitimate existing data.
            conn.execute(
                "INSERT INTO saved_search (public_id, user_id, name, filters, notify, auto_saved) "
                "VALUES ('d05-clean-search', ?, 'Clean search', '{\"brand\": \"toyota\"}', 1, 0)",
                (clean_user_id,),
            )
            clean_search_id = conn.execute(
                "SELECT id FROM saved_search WHERE public_id = 'd05-clean-search'"
            ).fetchone()[0]
            conn.commit()

            # Sanity check: prove the dirty rows are genuinely NULL
            # pre-migration (not merely "not yet asserted").
            row = conn.execute(
                "SELECT account_type, dealer_status FROM user WHERE id = ?", (dirty_user_id,)
            ).fetchone()
            self.assertIsNone(row[0])
            self.assertIsNone(row[1])
            row = conn.execute(
                "SELECT filters FROM saved_search WHERE id = ?", (dirty_search_id,)
            ).fetchone()
            self.assertIsNone(row[0])
        finally:
            conn.close()

        # Step 2: upgrade through D-05.
        self._flask_db("upgrade")

        conn = sqlite3.connect(self._db_path)
        try:
            # The migration's defensive backfill repaired the dirty rows.
            row = conn.execute(
                "SELECT account_type, dealer_status FROM user WHERE id = ?", (dirty_user_id,)
            ).fetchone()
            self.assertEqual(row[0], "user")
            self.assertEqual(row[1], "none")

            row = conn.execute(
                "SELECT filters FROM saved_search WHERE id = ?", (dirty_search_id,)
            ).fetchone()
            self.assertEqual(row[0], "{}")

            # Pre-existing non-NULL values were left completely untouched.
            row = conn.execute(
                "SELECT account_type, dealer_status FROM user WHERE id = ?", (clean_user_id,)
            ).fetchone()
            self.assertEqual(row[0], "dealer")
            self.assertEqual(row[1], "approved")

            row = conn.execute(
                "SELECT filters FROM saved_search WHERE id = ?", (clean_search_id,)
            ).fetchone()
            self.assertEqual(row[0], '{"brand": "toyota"}')

            # The database itself now rejects NULL -- a raw sqlite3 insert
            # that never goes anywhere near SQLAlchemy/ORM validation.
            with self.assertRaises(sqlite3.IntegrityError):
                conn.execute(
                    "INSERT INTO user "
                    "(public_id, username, password_hash, phone_number, first_name, last_name, "
                    " account_type, dealer_status) "
                    "VALUES ('d05-reject-1', 'd05_reject_1', 'x', '0790000003', 'Reject', 'One', "
                    " NULL, 'none')"
                )
            conn.rollback()

            with self.assertRaises(sqlite3.IntegrityError):
                conn.execute(
                    "INSERT INTO user "
                    "(public_id, username, password_hash, phone_number, first_name, last_name, "
                    " account_type, dealer_status) "
                    "VALUES ('d05-reject-2', 'd05_reject_2', 'x', '0790000004', 'Reject', 'Two', "
                    " 'user', NULL)"
                )
            conn.rollback()

            with self.assertRaises(sqlite3.IntegrityError):
                conn.execute(
                    "INSERT INTO saved_search (public_id, user_id, name, filters, notify, auto_saved) "
                    "VALUES ('d05-reject-3', ?, 'Reject three', NULL, 1, 0)",
                    (clean_user_id,),
                )
            conn.rollback()
        finally:
            conn.close()


if __name__ == "__main__":
    unittest.main(verbosity=2)
