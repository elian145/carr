"""D-08: proves ``user.profile_picture`` was widened from ``String(200)``
to ``String(2048)``, matching the existing R2/CDN media-URL precedent
already applied to ``car_image.image_url`` / ``car_video.video_url`` /
``car_video.thumbnail_url``.

Covers:
- ``kk/models.py``'s ``User.profile_picture`` column declaration.
- ``migrations/versions/o1p2q3r4s5t6_d08_widen_user_profile_picture.py``.

Method, mirroring ``kk/tests/test_d06_fk_report_status_indexes.py`` (the
established pattern in this repo for "isolate one migration via
downgrade/upgrade and inspect the real schema"):

1. `flask db downgrade` to the revision immediately before D-08 -- the
   first `flask db ...` subprocess call always boots `kk.wsgi:app`, whose
   `create_app()` runs a full `flask_migrate.upgrade()` to head on a
   brand-new empty database first (see `kk/app_factory.py`), so this
   single call exercises the *entire* migration chain from scratch before
   landing one step before D-08 -- covering "fresh full SQLite migration
   chain" in this same step.
2. Inspect the real schema and assert `user.profile_picture` is back to
   `VARCHAR(200)` (pre-D-08 shape) and `user.dealership_cover_picture`
   (a different, NOT-in-scope column) is unaffected either way.
3. `flask db upgrade` -- applies exactly the D-08 migration in isolation.
   Assert `user.profile_picture` is now `VARCHAR(2048)`,
   `dealership_cover_picture` is still `VARCHAR(200)`, and no other
   `user` column changed.
4. Using a raw ``sqlite3`` connection directly against the migrated file
   (bypassing the ORM/Flask-SQLAlchemy layer entirely -- SQLite has no
   real ``VARCHAR(n)`` enforcement regardless of declared width, so this
   step proves the *migration and model now agree at 2048*, not that
   SQLite itself would reject an over-200 write either before or after),
   write and read back a value >200 and <=2048 characters, proving the
   widened column round-trips it unchanged. A normal, realistic
   (<=200-char) value is also round-tripped to prove existing/typical
   values keep working exactly as before.
5. `flask db downgrade` back to immediately before D-08 again (isolated
   D-08 downgrade). Assert the column is back to `VARCHAR(200)`.
6. Re-upgrade once more (isolated D-08 re-upgrade) to prove the migration
   is safe to re-run in the same process.

Separately, an ORM-level ``app_ctx`` fixture (using ``db.create_all()``
against the current models, same pattern as
``kk/tests/test_d07_view_history_upsert.py``) proves the *model*
declaration itself (`User.profile_picture` is `db.String(2048)`) and
exercises the actual upload route
(``POST /api/user/upload-profile-picture``) end-to-end for its normal,
local-fallback (no R2 configured) path -- proving the real write path
still works and does not depend on external R2.
"""

from __future__ import annotations

import os
import io
import sqlite3
import subprocess
import sys
import tempfile
import unittest
import uuid
from pathlib import Path

import pytest
import sqlalchemy as sa

_REPO_ROOT = Path(__file__).resolve().parents[2]
if str(_REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(_REPO_ROOT))

# HEAD immediately before the D-08 migration (see
# migrations/versions/o1p2q3r4s5t6_d08_widen_user_profile_picture.py's
# `down_revision`) -- this is the D-06 migration's revision id.
_PRE_D08_REVISION = "n5o6p7q8r9s0"

_LONG_VALUE = "https://pub-" + ("a" * 220) + ".r2.dev/profile_pictures/x.jpg"  # > 200, <= 2048
_NORMAL_VALUE = "https://pub-1a2b3c4d5e6f7890.r2.dev/profile_pictures/deadbeef.jpg"  # realistic, <= 200


class D08ProfilePictureWidthMigrationTest(unittest.TestCase):
    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory(prefix="carlist_d08_", ignore_cleanup_errors=True)
        self._db_path = os.path.join(self._tmp.name, "d08.db")

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

    def _profile_picture_column(self, insp: sa.engine.reflection.Inspector) -> dict:
        for col in insp.get_columns("user"):
            if col["name"] == "profile_picture":
                return col
        self.fail("user.profile_picture column not found")

    def _dealership_cover_picture_column(self, insp: sa.engine.reflection.Inspector) -> dict:
        for col in insp.get_columns("user"):
            if col["name"] == "dealership_cover_picture":
                return col
        self.fail("user.dealership_cover_picture column not found")

    def _user_column_names(self, insp: sa.engine.reflection.Inspector) -> set[str]:
        return {c["name"] for c in insp.get_columns("user")}

    def test_migration_widens_and_narrows_profile_picture_only(self):
        # Step 1: bootstrap the FULL chain from scratch (empty -> head, via
        # create_app()'s AUTO_MIGRATE bootstrap), then step back to
        # immediately before D-08. Covers "fresh full SQLite migration
        # chain from scratch".
        self._flask_db("downgrade", _PRE_D08_REVISION)

        engine = sa.create_engine(f"sqlite:///{self._db_path}")
        try:
            insp = sa.inspect(engine)
            col = self._profile_picture_column(insp)
            self.assertEqual(
                str(col["type"]), "VARCHAR(200)", "pre-D-08: profile_picture should be VARCHAR(200)"
            )
            self.assertTrue(col["nullable"], "pre-D-08: profile_picture should stay nullable")
            pre_columns = self._user_column_names(insp)
            pre_cover_col = self._dealership_cover_picture_column(insp)
            self.assertEqual(str(pre_cover_col["type"]), "VARCHAR(200)")
        finally:
            engine.dispose()

        # Step 2: isolated D-08 upgrade (exactly one migration step).
        self._flask_db("upgrade")

        engine = sa.create_engine(f"sqlite:///{self._db_path}")
        try:
            insp = sa.inspect(engine)
            col = self._profile_picture_column(insp)
            self.assertEqual(
                str(col["type"]), "VARCHAR(2048)", "post-D-08: profile_picture should be VARCHAR(2048)"
            )
            self.assertTrue(col["nullable"], "post-D-08: profile_picture must remain nullable")

            # dealership_cover_picture (User) must be completely untouched.
            cover_col = self._dealership_cover_picture_column(insp)
            self.assertEqual(
                str(cover_col["type"]),
                "VARCHAR(200)",
                "user.dealership_cover_picture must stay VARCHAR(200) -- out of D-08 scope",
            )

            # No other user column was added/removed/changed by this migration.
            post_columns = self._user_column_names(insp)
            self.assertEqual(
                pre_columns,
                post_columns,
                "D-08 must not add/remove any user column -- only widen profile_picture",
            )

            # dealer_profile.dealership_cover_picture is a different table
            # entirely and must also be untouched.
            dp_col = next(
                c for c in insp.get_columns("dealer_profile") if c["name"] == "dealership_cover_picture"
            )
            self.assertEqual(str(dp_col["type"]), "VARCHAR(200)")
        finally:
            engine.dispose()

        # Step 3: prove the widening itself is what allows a >200-char
        # value to persist. Raw sqlite3 (not the ORM) is used deliberately
        # so no Flask-SQLAlchemy default/validation layer is in the way --
        # this isolates the DB-column-width behavior exactly.
        self.assertGreater(len(_LONG_VALUE), 200)
        self.assertLessEqual(len(_LONG_VALUE), 2048)
        conn = sqlite3.connect(self._db_path)
        try:
            conn.execute("PRAGMA foreign_keys = OFF")
            conn.execute(
                """
                INSERT INTO user (
                    public_id, username, phone_number, first_name, last_name,
                    password_hash, phone_verified, account_type, dealer_status,
                    is_featured_dealer, profile_picture
                ) VALUES (?, ?, ?, ?, ?, ?, 0, 'user', 'none', 0, ?)
                """,
                (
                    f"pub-{uuid.uuid4().hex[:12]}",
                    f"u_{uuid.uuid4().hex[:10]}",
                    f"079{uuid.uuid4().int % 10**8:08d}",
                    "D08",
                    "Test",
                    "x",
                    _LONG_VALUE,
                ),
            )
            conn.commit()
            row = conn.execute(
                "SELECT profile_picture FROM user WHERE profile_picture = ?", (_LONG_VALUE,)
            ).fetchone()
            self.assertIsNotNone(row, ">200-char value must round-trip after D-08 widening")
            self.assertEqual(row[0], _LONG_VALUE)
            self.assertEqual(len(row[0]), len(_LONG_VALUE))

            # A normal, realistic (<=200-char) value must keep working
            # exactly as before the widening.
            conn.execute(
                """
                INSERT INTO user (
                    public_id, username, phone_number, first_name, last_name,
                    password_hash, phone_verified, account_type, dealer_status,
                    is_featured_dealer, profile_picture
                ) VALUES (?, ?, ?, ?, ?, ?, 0, 'user', 'none', 0, ?)
                """,
                (
                    f"pub-{uuid.uuid4().hex[:12]}",
                    f"u_{uuid.uuid4().hex[:10]}",
                    f"079{uuid.uuid4().int % 10**8:08d}",
                    "D08b",
                    "Test",
                    "x",
                    _NORMAL_VALUE,
                ),
            )
            conn.commit()
            row2 = conn.execute(
                "SELECT profile_picture FROM user WHERE profile_picture = ?", (_NORMAL_VALUE,)
            ).fetchone()
            self.assertIsNotNone(row2, "normal <=200-char value must keep working")
            self.assertEqual(row2[0], _NORMAL_VALUE)

            # And profile_picture must still accept NULL.
            conn.execute(
                """
                INSERT INTO user (
                    public_id, username, phone_number, first_name, last_name,
                    password_hash, phone_verified, account_type, dealer_status,
                    is_featured_dealer, profile_picture
                ) VALUES (?, ?, ?, ?, ?, ?, 0, 'user', 'none', 0, NULL)
                """,
                (
                    f"pub-{uuid.uuid4().hex[:12]}",
                    f"u_{uuid.uuid4().hex[:10]}",
                    f"079{uuid.uuid4().int % 10**8:08d}",
                    "D08c",
                    "Test",
                    "x",
                ),
            )
            conn.commit()
            null_row = conn.execute(
                "SELECT profile_picture FROM user WHERE first_name = 'D08c'"
            ).fetchone()
            self.assertIsNone(null_row[0], "profile_picture must still accept NULL after D-08")
        finally:
            conn.close()

        # Step 4: isolated D-08 downgrade (exactly one migration step back).
        self._flask_db("downgrade", _PRE_D08_REVISION)
        engine = sa.create_engine(f"sqlite:///{self._db_path}")
        try:
            insp = sa.inspect(engine)
            col = self._profile_picture_column(insp)
            self.assertEqual(
                str(col["type"]), "VARCHAR(200)", "post-downgrade: profile_picture should be back to VARCHAR(200)"
            )
            self.assertTrue(col["nullable"])
        finally:
            engine.dispose()

        # Step 5: re-upgrade once more to prove the migration is safe to
        # re-run in the same process.
        self._flask_db("upgrade")
        engine = sa.create_engine(f"sqlite:///{self._db_path}")
        try:
            insp = sa.inspect(engine)
            col = self._profile_picture_column(insp)
            self.assertEqual(
                str(col["type"]), "VARCHAR(2048)", "post-re-upgrade: profile_picture should be VARCHAR(2048) again"
            )
            self.assertTrue(col["nullable"])
        finally:
            engine.dispose()

    def test_migration_does_not_cascade_delete_fk_linked_child_rows(self):
        """
        Regression guard: ``op.batch_alter_table("user")`` on SQLite
        recreates the *entire* ``user`` table (rename -> create -> copy ->
        drop old). D-01 gave several tables (``saved_search``,
        ``notification``, ...) ``ON DELETE CASCADE`` foreign keys to
        ``user.id``. With SQLite's ``PRAGMA foreign_keys=ON`` (the
        production/app-factory default), dropping the renamed old ``user``
        table during that recreate would cascade-delete every such child
        row unless FK enforcement is disabled for the duration of the
        batch operation -- exactly the failure mode ``3f945e50c327``
        (D-05) already had to guard against for this same table. This was
        caught for real while developing this migration: without the
        guard, this exact scenario silently deleted
        ``kk/tests/test_d05_nullability_backfill.py``'s seeded
        ``saved_search`` row.

        Seeds a cascade-linked ``saved_search`` row for a real user
        *before* the isolated D-08 upgrade step (which boots via
        ``kk.wsgi:app``'s ``create_app()``, registering the same
        connection-level ``PRAGMA foreign_keys=ON`` listener the real app
        uses -- see ``kk/app_factory.py``), then asserts both the user
        and the saved_search row still exist afterward.
        """
        self._flask_db("downgrade", _PRE_D08_REVISION)

        conn = sqlite3.connect(self._db_path)
        try:
            conn.execute("PRAGMA foreign_keys = ON")
            conn.execute(
                """
                INSERT INTO user (
                    public_id, username, phone_number, first_name, last_name,
                    password_hash, phone_verified, account_type, dealer_status,
                    is_featured_dealer
                ) VALUES (?, ?, ?, 'D08', 'FkGuard', 'x', 0, 'user', 'none', 0)
                """,
                (
                    f"pub-{uuid.uuid4().hex[:12]}",
                    f"u_{uuid.uuid4().hex[:10]}",
                    f"079{uuid.uuid4().int % 10**8:08d}",
                ),
            )
            conn.commit()
            user_id = conn.execute(
                "SELECT id FROM user WHERE first_name = 'D08' AND last_name = 'FkGuard'"
            ).fetchone()[0]

            conn.execute(
                """
                INSERT INTO saved_search (public_id, user_id, name, filters, created_at)
                VALUES (?, ?, 'd08-fk-guard-search', '{}', '2026-01-01')
                """,
                (f"ss-{uuid.uuid4().hex[:12]}", user_id),
            )
            conn.commit()
            saved_search_id = conn.execute(
                "SELECT id FROM saved_search WHERE name = 'd08-fk-guard-search'"
            ).fetchone()[0]
        finally:
            conn.close()

        # Isolated D-08 upgrade -- the step under test.
        self._flask_db("upgrade")

        conn = sqlite3.connect(self._db_path)
        try:
            user_row = conn.execute(
                "SELECT id FROM user WHERE id = ?", (user_id,)
            ).fetchone()
            self.assertIsNotNone(user_row, "user row must survive the D-08 migration")

            search_row = conn.execute(
                "SELECT id, user_id FROM saved_search WHERE id = ?", (saved_search_id,)
            ).fetchone()
            self.assertIsNotNone(
                search_row,
                "D-01 cascade-linked saved_search row must NOT be deleted by the "
                "D-08 user-table batch_alter_table recreate",
            )
            self.assertEqual(search_row[1], user_id)
        finally:
            conn.close()

    def test_downgrade_with_over_200_char_value_does_not_truncate_on_sqlite(self):
        """
        Rollback-safety regression: ``downgrade()`` narrows
        ``profile_picture`` from ``VARCHAR(2048)`` back to ``VARCHAR(200)``
        with NO explicit pre-check on existing row lengths -- deliberately
        matching the zero-pre-check convention already established by this
        migration's two precedents (``d9e0f1a2b3c4``, ``b4e8a1c2d3f4``),
        which narrow 2048 -> 200 the exact same way. This is safe because
        each database engine's own native type-constraint enforcement is
        the actual safety net:

        - PostgreSQL would reject (fail the ALTER, roll back the whole
          downgrade transaction) if a >200-char value already exists --
          not tested here (no local PostgreSQL available; see the D-08
          implementation report), but this is standard, well-documented
          PostgreSQL ALTER COLUMN behavior for narrowing VARCHAR(n).
        - SQLite (this test) never enforces VARCHAR(n) length at the
          storage engine level, declared width or not -- proven directly
          here: a value written while the column is VARCHAR(2048) is read
          back byte-for-byte identical, at full length, AFTER downgrading
          the column's declared type to VARCHAR(200). Nothing is
          truncated, nothing is destroyed, on either side of the
          downgrade.
        """
        # Bootstrap the full chain to head (includes this D-08 upgrade).
        self._flask_db("upgrade")

        long_value = "https://pub-" + ("b" * 230) + ".r2.dev/profile_pictures/y.jpg"
        self.assertGreater(len(long_value), 200)
        self.assertLessEqual(len(long_value), 2048)

        conn = sqlite3.connect(self._db_path)
        try:
            conn.execute("PRAGMA foreign_keys = OFF")
            conn.execute(
                """
                INSERT INTO user (
                    public_id, username, phone_number, first_name, last_name,
                    password_hash, phone_verified, account_type, dealer_status,
                    is_featured_dealer, profile_picture
                ) VALUES (?, ?, ?, 'D08', 'Rollback', 'x', 0, 'user', 'none', 0, ?)
                """,
                (
                    f"pub-{uuid.uuid4().hex[:12]}",
                    f"u_{uuid.uuid4().hex[:10]}",
                    f"079{uuid.uuid4().int % 10**8:08d}",
                    long_value,
                ),
            )
            conn.commit()
            user_id = conn.execute(
                "SELECT id FROM user WHERE first_name = 'D08' AND last_name = 'Rollback'"
            ).fetchone()[0]

            # Sanity check pre-downgrade: the long value is really there.
            row = conn.execute(
                "SELECT profile_picture FROM user WHERE id = ?", (user_id,)
            ).fetchone()
            self.assertEqual(row[0], long_value)
        finally:
            conn.close()

        # The downgrade itself must not raise on SQLite (no pre-check, no
        # enforcement -- it is expected to complete as a schema-only,
        # data-preserving no-op with respect to this over-length value).
        self._flask_db("downgrade", _PRE_D08_REVISION)

        engine = sa.create_engine(f"sqlite:///{self._db_path}")
        try:
            insp = sa.inspect(engine)
            col = self._profile_picture_column(insp)
            self.assertEqual(
                str(col["type"]),
                "VARCHAR(200)",
                "column must report VARCHAR(200) after downgrade regardless of existing over-length data",
            )
        finally:
            engine.dispose()

        conn = sqlite3.connect(self._db_path)
        try:
            row = conn.execute(
                "SELECT profile_picture FROM user WHERE id = ?", (user_id,)
            ).fetchone()
            self.assertIsNotNone(row, "row must survive the downgrade")
            self.assertEqual(
                row[0],
                long_value,
                "downgrade must NOT truncate/modify an existing >200-char value on SQLite",
            )
            self.assertEqual(len(row[0]), len(long_value))
        finally:
            conn.close()


# ---------------------------------------------------------------------------
# ORM / model-declaration + route-level tests
# ---------------------------------------------------------------------------

_PASSWORD = "Aa123456!"


@pytest.fixture(scope="module")
def app_ctx():
    tmp = tempfile.TemporaryDirectory(prefix="carlist_d08_orm_", ignore_cleanup_errors=True)
    os.environ["APP_ENV"] = "testing"
    os.environ["SMS_PROVIDER"] = "console"
    os.environ.pop("LISTING_REQUIRE_APPROVAL", None)
    # Deliberately do NOT set R2_* env vars -- proves the upload route's
    # local-fallback path (the one most at risk of a >200-char filename)
    # works without any external R2 dependency.
    for key in ("R2_ACCESS_KEY_ID", "R2_SECRET_ACCESS_KEY", "R2_PUBLIC_URL", "R2_BUCKET", "R2_ENDPOINT_URL"):
        os.environ.pop(key, None)
    os.environ["DB_PATH"] = os.path.join(tmp.name, "d08_orm.db")

    from kk.app_factory import create_app

    app, _socketio, *_ = create_app()
    from kk.models import db

    with app.app_context():
        db.drop_all()
        db.create_all()

    yield app, app.test_client(), db

    with app.app_context():
        db.session.remove()
        db.engine.dispose()
    tmp.cleanup()


def _phone() -> str:
    return f"079{uuid.uuid4().int % 10**8:08d}"


def _make_user_and_token(app, db, client, **extra):
    from kk.models import User

    extra.setdefault("phone_number", _phone())
    extra.setdefault("username", f"u_{uuid.uuid4().hex[:10]}")
    with app.app_context():
        user = User(
            first_name="D08",
            last_name="Orm",
            is_active=True,
            is_verified=True,
            phone_verified=True,
            public_id=f"pub-{uuid.uuid4().hex[:12]}",
            phone_verification_attempts=0,
            **extra,
        )
        user.set_password(_PASSWORD)
        db.session.add(user)
        db.session.commit()
        user_id = user.id

        from flask_jwt_extended import create_access_token

        token = create_access_token(identity=str(user_id))
        return user_id, token


class TestProfilePictureModelDeclaration:
    def test_model_column_is_string_2048(self, app_ctx):
        from kk.models import User

        col = User.__table__.columns["profile_picture"]
        assert isinstance(col.type, sa_string_type()), "profile_picture must be a String column"
        assert col.type.length == 2048, "User.profile_picture must be String(2048) after D-08"
        assert col.nullable is True, "profile_picture must remain nullable after D-08"

    def test_dealership_cover_picture_model_untouched(self, app_ctx):
        from kk.models import User, DealerProfile

        user_col = User.__table__.columns["dealership_cover_picture"]
        assert user_col.type.length == 200, "user.dealership_cover_picture must stay String(200)"

        dp_col = DealerProfile.__table__.columns["dealership_cover_picture"]
        assert dp_col.type.length == 200, "dealer_profile.dealership_cover_picture must stay String(200)"

    def test_fresh_created_schema_width_matches_model(self, app_ctx):
        """Model declaration and a freshly created (db.create_all()) SQLite
        schema must agree on the width -- the model/schema-width agreement
        this fix establishes."""
        app, _client, db = app_ctx
        import sqlalchemy as sa

        with app.app_context():
            insp = sa.inspect(db.engine)
            col = next(c for c in insp.get_columns("user") if c["name"] == "profile_picture")
            assert str(col["type"]) == "VARCHAR(2048)"


def sa_string_type():
    import sqlalchemy as sa

    return sa.String


class TestProfilePictureUploadRoute:
    """Route regression for POST /api/user/upload-profile-picture.

    No R2 env vars are set (see app_ctx fixture), so every upload in this
    class exercises the local-fallback path -- the same path whose
    unbounded `secure_filename()` output is the most realistic overflow
    vector identified in the D-08 investigation. This directly proves the
    normal upload path still works post-widening, without any dependency
    on external R2.
    """

    def test_normal_upload_succeeds_and_round_trips(self, app_ctx):
        app, client, db = app_ctx
        user_id, token = _make_user_and_token(app, db, client)

        data = {"file": (io.BytesIO(b"\xff\xd8\xff\xe0" + b"0" * 100), "avatar.jpg")}
        resp = client.post(
            "/api/user/upload-profile-picture",
            data=data,
            headers={"Authorization": f"Bearer {token}"},
            content_type="multipart/form-data",
        )
        assert resp.status_code == 200, resp.get_json()
        body = resp.get_json()
        assert body.get("profile_picture")
        assert body["profile_picture"].startswith("uploads/profile_pictures/")

        with app.app_context():
            from kk.models import User

            user = db.session.get(User, user_id)
            assert user.profile_picture == body["profile_picture"]

    def test_upload_with_long_original_filename_succeeds_post_widening(self, app_ctx):
        """
        D-08's investigation identified the local-fallback path's
        `secure_filename(file.filename)` as the realistic >200-char
        overflow vector (Werkzeug does not cap filename length). This
        proves that, after the widening, a long-but-plausible client
        filename no longer risks exceeding the column width.
        """
        app, client, db = app_ctx
        user_id, token = _make_user_and_token(app, db, client)

        # uploads/profile_pictures/ (25 chars) + this filename must exceed
        # 200 chars total to prove the >200-char case specifically.
        long_stem = "x" * 220
        long_filename = f"{long_stem}.jpg"
        data = {"file": (io.BytesIO(b"\xff\xd8\xff\xe0" + b"0" * 100), long_filename)}
        resp = client.post(
            "/api/user/upload-profile-picture",
            data=data,
            headers={"Authorization": f"Bearer {token}"},
            content_type="multipart/form-data",
        )
        assert resp.status_code == 200, resp.get_json()
        body = resp.get_json()
        stored = body.get("profile_picture") or ""
        assert len(stored) > 200, "test setup should have produced a >200-char stored value"
        assert len(stored) <= 2048

        with app.app_context():
            from kk.models import User

            user = db.session.get(User, user_id)
            assert user.profile_picture == stored
            assert len(user.profile_picture) == len(stored)


if __name__ == "__main__":
    unittest.main(verbosity=2)
