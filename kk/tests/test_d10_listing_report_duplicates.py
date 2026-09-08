"""D-10: dedupe historical duplicate and add unique constraint on
``listing_report(reporter_id, car_id)``.

Covers ``migrations/versions/7ae553c40b45_d_10_dedupe_historical_duplicate_and_.py``,
``kk/models.py::ListingReport.__table_args__``, and
``kk/routes/cars.py::report_car()``.

PRODUCTION_AUDIT.md D-10: "Duplicate reports allowed — no unique on
(reporter_id, car_id)". Real production PostgreSQL (Neon) evidence
(verified 2026-09-08) showed exactly one duplicate group in the entire
table's history:

  listing_report id=1 reporter_id=26 car_id=162 reason="yuhh" status="resolved"
  listing_report id=2 reporter_id=26 car_id=162 reason="bugs" status="dismissed"

The migration is fail-closed by design: it is authorized to delete ONLY
``id=2``, and only after verifying at migration time that both ``id=1``
and ``id=2`` still have ``reporter_id=26``/``car_id=162``. It then scans
the *entire* table for any other duplicate ``(reporter_id, car_id)``
group; if any exist, the whole migration (including the ``id=2`` delete,
if it ran) raises and rolls back transactionally -- it never deletes
anything else automatically. Only once zero duplicate groups are proven
does it add ``UniqueConstraint(name="uq_listing_report_reporter_car")``.

Part 1 (classes ``D10...MigrationTest``) drives the migration in
isolation via subprocess ``flask db upgrade``/``downgrade`` against a
throwaway SQLite file, mirroring the established pattern in
``kk/tests/test_d08_profile_picture_width.py``.

Part 2 (``TestListingReportModelDeclaration`` / ``TestReportCarRoute``)
covers the ORM-level constraint declaration and the
``report_car()`` route's conflict-safe upsert behavior, mirroring
``kk/tests/test_d07_view_history_upsert.py``.
"""

from __future__ import annotations

import os
import sqlite3
import subprocess
import sys
import tempfile
import uuid
from pathlib import Path

import pytest
import sqlalchemy as sa

_REPO_ROOT = Path(__file__).resolve().parents[2]
if str(_REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(_REPO_ROOT))

# down_revision of the D-10 migration -- the head immediately before it
# (D-08: widen user.profile_picture).
_PRE_D10_REVISION = "o1p2q3r4s5t6"

_UNIQUE_CONSTRAINT_NAME = "uq_listing_report_reporter_car"

_KNOWN_REPORTER_ID = 26
_KNOWN_CAR_ID = 162


# ---------------------------------------------------------------------------
# Raw-SQLite seeding helpers (deliberately bypass the ORM/app so these
# tests can seed exact historical id/column states pre-migration).
# ---------------------------------------------------------------------------


def _insert_user(conn: sqlite3.Connection, user_id: int | None = None, **overrides) -> int:
    cols = {
        "public_id": f"pub-{uuid.uuid4().hex[:12]}",
        "username": f"u_{uuid.uuid4().hex[:10]}",
        "phone_number": f"079{uuid.uuid4().int % 10 ** 8:08d}",
        "first_name": "D10",
        "last_name": "Test",
        "password_hash": "x",
        "phone_verified": 0,
        "account_type": "user",
        "dealer_status": "none",
        "is_featured_dealer": 0,
    }
    cols.update(overrides)
    if user_id is not None:
        cols["id"] = user_id
    columns = ", ".join(cols.keys())
    placeholders = ", ".join("?" for _ in cols)
    conn.execute(f"INSERT INTO user ({columns}) VALUES ({placeholders})", tuple(cols.values()))
    conn.commit()
    if user_id is not None:
        return user_id
    return conn.execute("SELECT last_insert_rowid()").fetchone()[0]


def _insert_car(conn: sqlite3.Connection, seller_id: int, car_id: int | None = None, **overrides) -> int:
    cols = {
        "public_id": f"car-{uuid.uuid4().hex[:12]}",
        "seller_id": seller_id,
        "title": "D10 probe car",
        "title_status": "clean",
        "brand": "toyota",
        "model": "corolla",
        "trim": "base",
        "year": 2021,
        "mileage": 10,
        "engine_type": "gas",
        "fuel_type": "gasoline",
        "transmission": "auto",
        "drive_type": "fwd",
        "condition": "used",
        "body_type": "sedan",
        "status": "active",
        "price": 15000,
        "location": "Erbil",
        "seating": 5,
        "is_active": 1,
    }
    cols.update(overrides)
    if car_id is not None:
        cols["id"] = car_id
    columns = ", ".join(cols.keys())
    placeholders = ", ".join("?" for _ in cols)
    conn.execute(f"INSERT INTO car ({columns}) VALUES ({placeholders})", tuple(cols.values()))
    conn.commit()
    if car_id is not None:
        return car_id
    return conn.execute("SELECT last_insert_rowid()").fetchone()[0]


def _insert_listing_report(
    conn: sqlite3.Connection,
    reporter_id: int | None,
    car_id: int | None,
    report_id: int | None = None,
    **overrides,
) -> int:
    cols = {
        "reporter_id": reporter_id,
        "car_id": car_id,
        "reason": "test reason",
        "status": "pending",
        "created_at": "2026-01-01 00:00:00",
    }
    cols.update(overrides)
    if report_id is not None:
        cols["id"] = report_id
    columns = ", ".join(cols.keys())
    placeholders = ", ".join("?" for _ in cols)
    conn.execute(f"INSERT INTO listing_report ({columns}) VALUES ({placeholders})", tuple(cols.values()))
    conn.commit()
    if report_id is not None:
        return report_id
    return conn.execute("SELECT last_insert_rowid()").fetchone()[0]


def _listing_report_ids(conn: sqlite3.Connection) -> list[int]:
    rows = conn.execute("SELECT id FROM listing_report ORDER BY id").fetchall()
    return [r[0] for r in rows]


def _alembic_version(conn: sqlite3.Connection) -> str:
    row = conn.execute("SELECT version_num FROM alembic_version").fetchone()
    return row[0] if row else None


# ---------------------------------------------------------------------------
# Part 1: migration-isolation tests (subprocess `flask db upgrade`/`downgrade`)
# ---------------------------------------------------------------------------


class D10ListingReportDedupeMigrationTest:
    """Shared setUp/tearDown + subprocess helper. Not collected directly by
    pytest (no `Test` prefix on this base) -- subclassed below."""

    def setup_method(self):
        self._tmp = tempfile.TemporaryDirectory(prefix="carlist_d10_", ignore_cleanup_errors=True)
        self._db_path = os.path.join(self._tmp.name, "d10.db")

        self._env = os.environ.copy()
        self._env["APP_ENV"] = "testing"
        self._env["FLASK_APP"] = "kk.wsgi:app"
        self._env["AUTO_MIGRATE"] = "0"
        self._env["SMS_PROVIDER"] = "console"
        self._env["DB_PATH"] = self._db_path

    def teardown_method(self):
        self._tmp.cleanup()

    def _flask_db(self, *args: str, expect_success: bool = True):
        result = subprocess.run(
            [sys.executable, "-m", "flask", "db", *args],
            cwd=_REPO_ROOT,
            env=self._env,
            capture_output=True,
            text=True,
        )
        if expect_success and result.returncode != 0:
            raise AssertionError(
                f"`flask db {' '.join(args)}` failed (exit {result.returncode}):\n"
                f"--- stdout ---\n{result.stdout}\n--- stderr ---\n{result.stderr}"
            )
        if not expect_success and result.returncode == 0:
            raise AssertionError(
                f"`flask db {' '.join(args)}` was expected to FAIL but succeeded:\n"
                f"--- stdout ---\n{result.stdout}\n--- stderr ---\n{result.stderr}"
            )
        return result

    def _connect(self) -> sqlite3.Connection:
        return sqlite3.connect(self._db_path)

    def _has_unique_constraint(self) -> bool:
        engine = sa.create_engine(f"sqlite:///{self._db_path}")
        try:
            insp = sa.inspect(engine)
            names = {uc["name"] for uc in insp.get_unique_constraints("listing_report")}
            if _UNIQUE_CONSTRAINT_NAME in names:
                return True
            # SQLite may also surface a table-level UNIQUE as an index;
            # accept either reflection shape.
            idx_names = {ix["name"] for ix in insp.get_indexes("listing_report") if ix.get("unique")}
            return _UNIQUE_CONSTRAINT_NAME in idx_names
        finally:
            engine.dispose()

    def _assert_duplicate_insert_rejected(self, reporter_id: int, car_id: int) -> None:
        conn = self._connect()
        try:
            with pytest.raises(sqlite3.IntegrityError):
                _insert_listing_report(conn, reporter_id, car_id, reason="dup-probe")
        finally:
            conn.close()


class TestD10KnownDuplicateHappyPath(D10ListingReportDedupeMigrationTest):
    def test_a_known_duplicate_is_cleaned_and_constraint_created(self):
        self._flask_db("downgrade", _PRE_D10_REVISION)

        conn = self._connect()
        try:
            conn.execute("PRAGMA foreign_keys = OFF")
            reporter_id = _insert_user(conn, user_id=_KNOWN_REPORTER_ID)
            seller_id = _insert_user(conn)
            car_id = _insert_car(conn, seller_id, car_id=_KNOWN_CAR_ID)
            _insert_listing_report(
                conn, reporter_id, car_id, report_id=1, reason="yuhh", status="resolved"
            )
            _insert_listing_report(
                conn, reporter_id, car_id, report_id=2, reason="bugs", status="dismissed"
            )
        finally:
            conn.close()

        self._flask_db("upgrade")

        conn = self._connect()
        try:
            ids = _listing_report_ids(conn)
            assert ids == [1], f"expected only id=1 to survive, got {ids}"
            row = conn.execute(
                "SELECT reporter_id, car_id, reason, status FROM listing_report WHERE id = 1"
            ).fetchone()
            assert row == (_KNOWN_REPORTER_ID, _KNOWN_CAR_ID, "yuhh", "resolved")
        finally:
            conn.close()

        assert self._has_unique_constraint(), "uq_listing_report_reporter_car must exist after upgrade"
        self._assert_duplicate_insert_rejected(_KNOWN_REPORTER_ID, _KNOWN_CAR_ID)


class TestD10FreshDatabase(D10ListingReportDedupeMigrationTest):
    def test_b_fresh_database_is_a_noop_then_creates_constraint(self):
        # Bootstrap the FULL chain from empty -> head in one go (covers the
        # "fresh SQLite database from scratch" scenario -- no downgrade
        # step first, since there is nothing to downgrade from yet).
        self._flask_db("upgrade")

        conn = self._connect()
        try:
            assert _listing_report_ids(conn) == []
        finally:
            conn.close()

        assert self._has_unique_constraint(), "uq_listing_report_reporter_car must exist on a fresh DB"
        # Functional proof: seed a first row, then a duplicate must be rejected.
        conn = self._connect()
        try:
            conn.execute("PRAGMA foreign_keys = OFF")
            reporter_id = _insert_user(conn)
            seller_id = _insert_user(conn)
            car_id = _insert_car(conn, seller_id)
            _insert_listing_report(conn, reporter_id, car_id)
        finally:
            conn.close()
        self._assert_duplicate_insert_rejected(reporter_id, car_id)


class TestD10UnexpectedDuplicateFailsClosed(D10ListingReportDedupeMigrationTest):
    def test_c_unexpected_duplicate_group_fails_and_rolls_back_everything(self):
        """
        Seeds BOTH the exact known duplicate (id=1/id=2 for (26, 162)) AND
        a second, unrelated duplicate group (ids 50/51, a different
        (reporter_id, car_id) pair). The migration must FAIL -- and,
        critically, roll back the id=2 deletion it already performed in
        Step 1 before Step 2 discovered the unrelated group and raised.
        Proves this is a real transactional rollback, not just "stop
        before doing anything else".
        """
        self._flask_db("downgrade", _PRE_D10_REVISION)

        conn = self._connect()
        try:
            conn.execute("PRAGMA foreign_keys = OFF")
            known_reporter_id = _insert_user(conn, user_id=_KNOWN_REPORTER_ID)
            seller_id = _insert_user(conn)
            known_car_id = _insert_car(conn, seller_id, car_id=_KNOWN_CAR_ID)
            _insert_listing_report(
                conn, known_reporter_id, known_car_id, report_id=1, reason="yuhh", status="resolved"
            )
            _insert_listing_report(
                conn, known_reporter_id, known_car_id, report_id=2, reason="bugs", status="dismissed"
            )

            other_reporter_id = _insert_user(conn)
            other_car_id = _insert_car(conn, seller_id)
            _insert_listing_report(
                conn, other_reporter_id, other_car_id, report_id=50, reason="first"
            )
            _insert_listing_report(
                conn, other_reporter_id, other_car_id, report_id=51, reason="second"
            )
        finally:
            conn.close()

        result = self._flask_db("upgrade", expect_success=False)
        combined_output = (result.stdout or "") + (result.stderr or "")
        assert "unexpected duplicate" in combined_output.lower()

        conn = self._connect()
        try:
            ids = _listing_report_ids(conn)
            # Nothing deleted -- id=2 must have been rolled back along with
            # everything else.
            assert ids == [1, 2, 50, 51], f"expected all four rows to survive the rollback, got {ids}"
            row2 = conn.execute(
                "SELECT reporter_id, car_id FROM listing_report WHERE id = 2"
            ).fetchone()
            assert row2 == (_KNOWN_REPORTER_ID, _KNOWN_CAR_ID)

            assert _alembic_version(conn) == _PRE_D10_REVISION, "alembic_version must not have advanced"
        finally:
            conn.close()

        assert not self._has_unique_constraint(), "constraint must NOT exist after a failed migration"

    def test_c2_unexpected_duplicate_with_no_known_duplicate_present_also_fails(self):
        """Same fail-closed behavior when the known (26, 162) pair is
        entirely absent (id=2 never existed) -- Step 1 is a no-op, Step 2
        alone must still catch and reject the unrelated duplicate."""
        self._flask_db("downgrade", _PRE_D10_REVISION)

        conn = self._connect()
        try:
            conn.execute("PRAGMA foreign_keys = OFF")
            reporter_id = _insert_user(conn)
            seller_id = _insert_user(conn)
            car_id = _insert_car(conn, seller_id)
            _insert_listing_report(conn, reporter_id, car_id, report_id=50, reason="first")
            _insert_listing_report(conn, reporter_id, car_id, report_id=51, reason="second")
        finally:
            conn.close()

        self._flask_db("upgrade", expect_success=False)

        conn = self._connect()
        try:
            assert _listing_report_ids(conn) == [50, 51]
            assert _alembic_version(conn) == _PRE_D10_REVISION
        finally:
            conn.close()
        assert not self._has_unique_constraint()

    def test_c3_id2_present_but_identity_does_not_match_known_evidence_fails_closed(self):
        """id=2 exists but its (reporter_id, car_id) does NOT match the
        verified production identity (26, 162) -- e.g. id=1 is absent, or
        id=2 belongs to a completely different pair. The migration must
        refuse to delete it automatically and fail loudly instead."""
        self._flask_db("downgrade", _PRE_D10_REVISION)

        conn = self._connect()
        try:
            conn.execute("PRAGMA foreign_keys = OFF")
            reporter_id = _insert_user(conn)
            seller_id = _insert_user(conn)
            car_id = _insert_car(conn, seller_id)
            # id=1 absent entirely; id=2 present but unrelated identity.
            _insert_listing_report(conn, reporter_id, car_id, report_id=2, reason="unrelated")
        finally:
            conn.close()

        result = self._flask_db("upgrade", expect_success=False)
        combined_output = (result.stdout or "") + (result.stderr or "")
        assert "does not exactly match" in combined_output.lower() or "refusing to delete" in combined_output.lower()

        conn = self._connect()
        try:
            ids = _listing_report_ids(conn)
            assert ids == [2], "the mismatched id=2 row must survive untouched"
            assert _alembic_version(conn) == _PRE_D10_REVISION
        finally:
            conn.close()


class TestD10UnrelatedReportUntouched(D10ListingReportDedupeMigrationTest):
    def test_d_unrelated_third_report_survives_known_duplicate_cleanup(self):
        self._flask_db("downgrade", _PRE_D10_REVISION)

        conn = self._connect()
        try:
            conn.execute("PRAGMA foreign_keys = OFF")
            known_reporter_id = _insert_user(conn, user_id=_KNOWN_REPORTER_ID)
            seller_id = _insert_user(conn)
            known_car_id = _insert_car(conn, seller_id, car_id=_KNOWN_CAR_ID)
            _insert_listing_report(conn, known_reporter_id, known_car_id, report_id=1, reason="yuhh")
            _insert_listing_report(conn, known_reporter_id, known_car_id, report_id=2, reason="bugs")

            other_reporter_id = _insert_user(conn)
            other_car_id = _insert_car(conn, seller_id)
            unrelated_id = _insert_listing_report(
                conn, other_reporter_id, other_car_id, report_id=3, reason="totally unrelated",
                status="reviewed", admin_notes="keep me",
            )
        finally:
            conn.close()

        self._flask_db("upgrade")

        conn = self._connect()
        try:
            ids = _listing_report_ids(conn)
            assert ids == [1, unrelated_id]
            row = conn.execute(
                "SELECT reporter_id, car_id, reason, status, admin_notes FROM listing_report WHERE id = ?",
                (unrelated_id,),
            ).fetchone()
            assert row == (other_reporter_id, other_car_id, "totally unrelated", "reviewed", "keep me")
        finally:
            conn.close()


class TestD10FksSurviveBatchRecreate(D10ListingReportDedupeMigrationTest):
    def test_e_on_delete_set_null_fks_survive_sqlite_batch_recreate(self):
        """
        Regression guard mirroring D-08's analogous FK-survival test:
        adding the unique constraint on SQLite requires
        ``batch_alter_table("listing_report")`` (recreate-the-table).
        D-01 gave ``listing_report.reporter_id``/``car_id`` ``ON DELETE
        SET NULL`` (deliberately, not CASCADE/RESTRICT, so report history
        outlives the reporter's account or the reported listing). This
        proves that FK behavior is completely intact after the D-10
        recreate: deleting the referenced user/car still SETs NULL rather
        than cascading, erroring, or silently becoming enforced
        differently.
        """
        self._flask_db("upgrade")

        conn = self._connect()
        try:
            conn.execute("PRAGMA foreign_keys = ON")
            reporter_id = _insert_user(conn)
            seller_id = _insert_user(conn)
            car_id = _insert_car(conn, seller_id)
            report_id = _insert_listing_report(conn, reporter_id, car_id, reason="fk survival probe")

            conn.execute("DELETE FROM user WHERE id = ?", (reporter_id,))
            conn.commit()
            row = conn.execute(
                "SELECT reporter_id, car_id FROM listing_report WHERE id = ?", (report_id,)
            ).fetchone()
            assert row == (None, car_id), "reporter_id must be SET NULL, not block/cascade the user delete"

            conn.execute("DELETE FROM car WHERE id = ?", (car_id,))
            conn.commit()
            row2 = conn.execute(
                "SELECT reporter_id, car_id FROM listing_report WHERE id = ?", (report_id,)
            ).fetchone()
            assert row2 == (None, None), "car_id must be SET NULL, not block/cascade the car delete"
        finally:
            conn.close()

    def test_e2_two_null_reporter_rows_do_not_violate_unique_constraint(self):
        """NULL-vs-NULL is never treated as a duplicate by SQL uniqueness
        semantics -- proves that historical SET-NULL'd rows (from the
        scenario above, replayed twice) can coexist under the new
        constraint."""
        self._flask_db("upgrade")

        conn = self._connect()
        try:
            conn.execute("PRAGMA foreign_keys = OFF")
            _insert_listing_report(conn, None, None, reason="first null pair")
            # Must NOT raise -- two (NULL, NULL) rows are not duplicates.
            _insert_listing_report(conn, None, None, reason="second null pair")
            assert len(_listing_report_ids(conn)) == 2
        finally:
            conn.close()


class TestD10Downgrade(D10ListingReportDedupeMigrationTest):
    def test_f_downgrade_drops_constraint_and_is_safely_reversible(self):
        self._flask_db("downgrade", _PRE_D10_REVISION)

        conn = self._connect()
        try:
            conn.execute("PRAGMA foreign_keys = OFF")
            reporter_id = _insert_user(conn, user_id=_KNOWN_REPORTER_ID)
            seller_id = _insert_user(conn)
            car_id = _insert_car(conn, seller_id, car_id=_KNOWN_CAR_ID)
            _insert_listing_report(conn, reporter_id, car_id, report_id=1, reason="yuhh")
            _insert_listing_report(conn, reporter_id, car_id, report_id=2, reason="bugs")
        finally:
            conn.close()

        self._flask_db("upgrade")
        conn = self._connect()
        try:
            assert _listing_report_ids(conn) == [1]
        finally:
            conn.close()
        assert self._has_unique_constraint()

        # Downgrade: only the constraint is dropped -- id=2 must NOT be
        # recreated (downgrade() contains no data statement of any kind).
        self._flask_db("downgrade", _PRE_D10_REVISION)
        assert not self._has_unique_constraint(), "constraint must be gone after downgrade"
        conn = self._connect()
        try:
            assert _listing_report_ids(conn) == [1], "downgrade must not resurrect id=2 or touch any row"
            # Duplicate insert must now succeed again (no constraint).
            _insert_listing_report(conn, reporter_id, car_id, report_id=2, reason="re-inserted")
            assert _listing_report_ids(conn) == [1, 2]
        finally:
            conn.close()

        # Re-upgrade must succeed even with a *new* id=2 present, as long
        # as it once again matches the known identity -- and must succeed
        # cleanly a second time in the same process either way.
        conn = self._connect()
        try:
            row = conn.execute(
                "SELECT reporter_id, car_id FROM listing_report WHERE id = 2"
            ).fetchone()
            assert row == (_KNOWN_REPORTER_ID, _KNOWN_CAR_ID)
        finally:
            conn.close()

        self._flask_db("upgrade")
        conn = self._connect()
        try:
            assert _listing_report_ids(conn) == [1]
        finally:
            conn.close()
        assert self._has_unique_constraint()


# ---------------------------------------------------------------------------
# Part 2: ORM model declaration + report_car() route-level tests
# ---------------------------------------------------------------------------

_PASSWORD = "Aa123456!"


@pytest.fixture(scope="module")
def app_ctx():
    tmp = tempfile.TemporaryDirectory(prefix="carlist_d10_orm_", ignore_cleanup_errors=True)
    os.environ["APP_ENV"] = "testing"
    os.environ["SMS_PROVIDER"] = "console"
    os.environ.pop("LISTING_REQUIRE_APPROVAL", None)
    os.environ["DB_PATH"] = os.path.join(tmp.name, "d10_orm.db")

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
    return f"079{uuid.uuid4().int % 10 ** 8:08d}"


def _make_user(app, db, **extra):
    from kk.models import User

    extra.setdefault("phone_number", _phone())
    extra.setdefault("username", f"u_{uuid.uuid4().hex[:10]}")
    with app.app_context():
        user = User(
            first_name="D10",
            last_name="Test",
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
        return user.id


def _make_car(app, db, seller_id: int, **extra):
    from kk.models import Car

    with app.app_context():
        car = Car(
            seller_id=seller_id,
            public_id=f"car-{uuid.uuid4().hex[:12]}",
            title="D10 route test car",
            title_status="clean",
            brand="toyota",
            model="corolla",
            year=2021,
            mileage=10,
            engine_type="gas",
            transmission="auto",
            drive_type="fwd",
            condition="used",
            body_type="sedan",
            price=15000,
            location="Erbil",
            is_active=True,
            **extra,
        )
        db.session.add(car)
        db.session.commit()
        return car.id, car.public_id


def _login(client, username: str, password: str = _PASSWORD) -> str:
    r = client.post("/api/auth/login", json={"username": username, "password": password})
    assert r.status_code == 200, r.data
    return r.get_json()["access_token"]


def _auth(token: str) -> dict:
    return {"Authorization": f"Bearer {token}"}


class TestListingReportModelDeclaration:
    def test_unique_constraint_is_declared_on_the_model(self, app_ctx):
        from kk.models import ListingReport

        unique_constraints = [
            c for c in ListingReport.__table__.constraints
            if isinstance(c, sa.UniqueConstraint)
        ]
        matching = [
            c for c in unique_constraints
            if c.name == _UNIQUE_CONSTRAINT_NAME
        ]
        assert matching, (
            f"ListingReport must declare a UniqueConstraint named "
            f"{_UNIQUE_CONSTRAINT_NAME!r}"
        )
        column_names = {col.name for col in matching[0].columns}
        assert column_names == {"reporter_id", "car_id"}

    def test_fresh_created_schema_has_the_constraint(self, app_ctx):
        app, _client, db = app_ctx
        with app.app_context():
            insp = sa.inspect(db.engine)
            names = {uc["name"] for uc in insp.get_unique_constraints("listing_report")}
            assert _UNIQUE_CONSTRAINT_NAME in names

    def test_fk_ondelete_set_null_still_declared(self, app_ctx):
        from kk.models import ListingReport

        for col_name in ("reporter_id", "car_id"):
            col = ListingReport.__table__.columns[col_name]
            assert col.nullable is True
            fks = list(col.foreign_keys)
            assert len(fks) == 1
            assert fks[0].ondelete == "SET NULL"


class TestReportCarRoute:
    def test_first_report_returns_201(self, app_ctx):
        app, client, db = app_ctx
        username = f"d10_{uuid.uuid4().hex[:10]}"

        seller_id = _make_user(app, db)
        reporter_id = _make_user(app, db, username=username)
        _car_id, public_id = _make_car(app, db, seller_id)

        token = _login(client, username)
        resp = client.post(
            f"/api/cars/{public_id}/report",
            json={"reason": "spam", "details": "looks fake"},
            headers=_auth(token),
        )
        assert resp.status_code == 201, resp.data
        assert "submitted" in resp.get_json()["message"].lower()

    def test_repeat_report_returns_200_not_500(self, app_ctx):
        app, client, db = app_ctx
        username = f"d10_{uuid.uuid4().hex[:10]}"

        seller_id = _make_user(app, db)
        _make_user(app, db, username=username)
        _car_id, public_id = _make_car(app, db, seller_id)

        token = _login(client, username)
        r1 = client.post(
            f"/api/cars/{public_id}/report",
            json={"reason": "spam"},
            headers=_auth(token),
        )
        assert r1.status_code == 201, r1.data

        r2 = client.post(
            f"/api/cars/{public_id}/report",
            json={"reason": "different reason this time"},
            headers=_auth(token),
        )
        assert r2.status_code == 200, r2.data
        assert "already reported" in r2.get_json()["message"].lower()

    def test_repeat_report_does_not_create_a_second_row_or_change_the_first(self, app_ctx):
        app, client, db = app_ctx
        from kk.models import ListingReport, User

        username = f"d10_{uuid.uuid4().hex[:10]}"
        seller_id = _make_user(app, db)
        _make_user(app, db, username=username)
        _car_id, public_id = _make_car(app, db, seller_id)

        token = _login(client, username)
        client.post(
            f"/api/cars/{public_id}/report",
            json={"reason": "original reason"},
            headers=_auth(token),
        )
        client.post(
            f"/api/cars/{public_id}/report",
            json={"reason": "SHOULD NOT OVERWRITE"},
            headers=_auth(token),
        )

        with app.app_context():
            from kk.models import Car

            reporter_id = User.query.filter_by(username=username).one().id
            car_id = Car.query.filter_by(public_id=public_id).one().id
            rows = ListingReport.query.filter_by(
                reporter_id=reporter_id, car_id=car_id
            ).all()
            assert len(rows) == 1
            assert rows[0].reason == "original reason"

    def test_three_rapid_repeat_calls_none_500(self, app_ctx):
        app, client, db = app_ctx
        username = f"d10_{uuid.uuid4().hex[:10]}"
        seller_id = _make_user(app, db)
        _make_user(app, db, username=username)
        _car_id, public_id = _make_car(app, db, seller_id)

        token = _login(client, username)
        statuses = []
        for _ in range(3):
            r = client.post(
                f"/api/cars/{public_id}/report",
                json={"reason": "spam"},
                headers=_auth(token),
            )
            statuses.append(r.status_code)
        assert statuses == [201, 200, 200], statuses

    def test_different_reporters_can_both_report_same_car(self, app_ctx):
        app, client, db = app_ctx
        username1 = f"d10_{uuid.uuid4().hex[:10]}"
        username2 = f"d10_{uuid.uuid4().hex[:10]}"

        seller_id = _make_user(app, db)
        _make_user(app, db, username=username1)
        _make_user(app, db, username=username2)
        _car_id, public_id = _make_car(app, db, seller_id)

        token1 = _login(client, username1)
        token2 = _login(client, username2)

        r1 = client.post(
            f"/api/cars/{public_id}/report",
            json={"reason": "spam"},
            headers=_auth(token1),
        )
        r2 = client.post(
            f"/api/cars/{public_id}/report",
            json={"reason": "spam"},
            headers=_auth(token2),
        )
        assert r1.status_code == 201, r1.data
        assert r2.status_code == 201, r2.data

    def test_same_reporter_can_report_two_different_cars(self, app_ctx):
        app, client, db = app_ctx
        username = f"d10_{uuid.uuid4().hex[:10]}"

        seller_id = _make_user(app, db)
        _make_user(app, db, username=username)
        _car_id_1, public_id_1 = _make_car(app, db, seller_id)
        _car_id_2, public_id_2 = _make_car(app, db, seller_id)

        token = _login(client, username)
        r1 = client.post(
            f"/api/cars/{public_id_1}/report",
            json={"reason": "spam"},
            headers=_auth(token),
        )
        r2 = client.post(
            f"/api/cars/{public_id_2}/report",
            json={"reason": "spam"},
            headers=_auth(token),
        )
        assert r1.status_code == 201, r1.data
        assert r2.status_code == 201, r2.data

    def test_self_report_still_blocked_with_400(self, app_ctx):
        """Unrelated to D-10, but a quick smoke that the existing
        self-report guard (checked before the conflict-safe insert is
        even attempted) still works unchanged."""
        app, client, db = app_ctx
        username = f"d10_{uuid.uuid4().hex[:10]}"
        seller_id = _make_user(app, db, username=username)
        _car_id, public_id = _make_car(app, db, seller_id)

        token = _login(client, username)
        resp = client.post(
            f"/api/cars/{public_id}/report",
            json={"reason": "spam"},
            headers=_auth(token),
        )
        assert resp.status_code == 400, resp.data

    def test_uses_conflict_safe_insert_not_raw_add_commit(self, app_ctx, monkeypatch):
        """
        Guard against silently reintroducing the pre-D-10 plain
        ``db.session.add(ListingReport(...))`` (which would 500 on
        conflict once the unique constraint exists) instead of the
        approved conflict-safe write: assert the shared D-04 dialect
        helper (``kk.listing_metrics._conflict_safe_insert``) is actually
        invoked by ``report_car()``.
        """
        app, client, db = app_ctx
        import kk.listing_metrics as listing_metrics_mod

        username = f"d10_{uuid.uuid4().hex[:10]}"
        seller_id = _make_user(app, db)
        _make_user(app, db, username=username)
        _car_id, public_id = _make_car(app, db, seller_id)

        calls: list[object] = []
        original = listing_metrics_mod._conflict_safe_insert

        def _spy(model):
            calls.append(model)
            return original(model)

        monkeypatch.setattr(listing_metrics_mod, "_conflict_safe_insert", _spy)

        token = _login(client, username)
        resp = client.post(
            f"/api/cars/{public_id}/report",
            json={"reason": "spam"},
            headers=_auth(token),
        )
        assert resp.status_code == 201, resp.data
        assert len(calls) == 1

    def test_null_reporter_and_car_id_do_not_collide_at_orm_level(self, app_ctx):
        """After D-01 SET NULL (account deletion / listing purge),
        multiple historical rows can end up with NULL reporter_id and/or
        car_id. Proves the new unique constraint never blocks that at the
        ORM/session level either."""
        app, _client, db = app_ctx
        from kk.models import ListingReport

        with app.app_context():
            db.session.add(ListingReport(reporter_id=None, car_id=None, reason="orphaned #1"))
            db.session.add(ListingReport(reporter_id=None, car_id=None, reason="orphaned #2"))
            db.session.commit()  # must not raise

            count = ListingReport.query.filter_by(reporter_id=None, car_id=None).count()
            assert count == 2


if __name__ == "__main__":
    pytest.main([__file__, "-v"])
