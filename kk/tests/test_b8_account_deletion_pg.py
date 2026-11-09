"""B8-2 PostgreSQL checks for ``account_deletion_request``.

Runs only against a disposable local/CI PostgreSQL (same contract as
``test_f04_pg_durable_alerts.py``)::

    CARNET_PG_TEST_URL=postgresql://postgres@127.0.0.1:55455/carnet_b8_pg
    CARNET_PG_TEST_CONFIRM_DISPOSABLE=1
    pytest kk/tests/test_b8_account_deletion_pg.py

Covers: the migration chain (up / down / up, data in the neighbouring tables
untouched, one head), model <-> migration parity for the new table, the
partial unique index semantics on a real PostgreSQL, and the duplicate race.
"""

from __future__ import annotations

import os
import secrets
import subprocess
import sys
import tempfile
import threading
import uuid
from pathlib import Path

import pytest

_REPO_ROOT = Path(__file__).resolve().parents[2]
if str(_REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(_REPO_ROOT))

PG_URL = (os.environ.get("CARNET_PG_TEST_URL") or "").strip()
pytestmark = pytest.mark.skipif(
    not PG_URL, reason="CARNET_PG_TEST_URL not set (PostgreSQL rehearsal only)"
)

B8 = "a7d3e1c9b5f2"
TIP = "b8e4f2a6c1d3"  # F-17 admin_audit_log, stacked on B8
F04 = "f04a1b2c3d4e"
PREV = "v0w1x2y3z4a5"
TABLE = "account_deletion_request"


def _admin_dsn(url):
    return url.set(drivername="postgresql", database="postgres").render_as_string(hide_password=False)


def _require_disposable(url):
    if url.host not in ("localhost", "127.0.0.1", "::1") or os.environ.get("CARNET_PG_TEST_CONFIRM_DISPOSABLE") != "1":
        pytest.fail(
            "Refusing to run: the target database is dropped and re-created, so the server must be local "
            "and CARNET_PG_TEST_CONFIRM_DISPOSABLE=1 must be set."
        )


def _recreate(url, name):
    import psycopg

    with psycopg.connect(_admin_dsn(url), autocommit=True) as c:
        c.execute(f'DROP DATABASE IF EXISTS "{name}" WITH (FORCE)')
        c.execute(f'CREATE DATABASE "{name}"')


def _drop(url, name):
    import psycopg

    with psycopg.connect(_admin_dsn(url), autocommit=True) as c:
        c.execute(f'DROP DATABASE IF EXISTS "{name}" WITH (FORCE)')


def _flask_db(dsn, *args):
    env = os.environ.copy()
    env.update(
        {
            "DATABASE_URL": dsn,
            "FLASK_APP": "kk.wsgi:app",
            "APP_ENV": "testing",
            "AUTO_MIGRATE": "0",
            "SMS_PROVIDER": "console",
            "SECRET_KEY": secrets.token_hex(16),
            "JWT_SECRET_KEY": secrets.token_hex(16),
            "UPLOAD_FOLDER": tempfile.gettempdir(),
        }
    )
    env.pop("DB_PATH", None)
    proc = subprocess.run(
        [sys.executable, "-m", "flask", "db", *args],
        cwd=str(_REPO_ROOT),
        env=env,
        capture_output=True,
        text=True,
        timeout=900,
    )
    assert proc.returncode == 0, f"flask db {' '.join(args)} failed:\n{proc.stdout}\n{proc.stderr}"


@pytest.fixture(scope="module")
def migrated():
    """A throw-away database migrated through the REAL Alembic chain."""
    from sqlalchemy.engine import make_url

    url = make_url(PG_URL).set(drivername="postgresql")
    _require_disposable(url)
    name = f"{url.database}_b8del"
    _recreate(url, name)
    dsn = url.set(database=name).render_as_string(hide_password=False)
    _flask_db(dsn, "upgrade")
    yield url, name, dsn
    _drop(url, name)


def _q(dsn, sql, *params):
    import psycopg

    with psycopg.connect(dsn, autocommit=True) as c:
        cur = c.execute(sql, params)
        return cur.fetchall() if cur.description else None


def _insert_user(dsn) -> int:
    """Insert a minimal user row, filling every NOT NULL column that has no
    default (schema-driven, so it does not break when unrelated columns are added)."""
    cols = _q(
        dsn,
        "select column_name, data_type from information_schema.columns "
        "where table_schema = 'public' and table_name = 'user' "
        "and is_nullable = 'NO' and column_default is null",
    )
    names, values = [], []
    for name, dtype in cols:
        names.append(f'"{name}"')
        if name == "username":
            values.append(f"'b8_{uuid.uuid4().hex[:8]}'")
        elif name == "phone_number":
            values.append(f"'077{uuid.uuid4().int % 10**8:08d}'")
        elif name == "public_id":
            values.append(f"'pub-{uuid.uuid4().hex[:12]}'")
        elif dtype == "boolean":
            values.append("false")
        elif dtype in ("integer", "bigint", "smallint"):
            values.append("0")
        elif dtype.startswith("timestamp"):
            values.append("now()")
        else:
            values.append("'x'")
    return _q(
        dsn, f'insert into "user" ({", ".join(names)}) values ({", ".join(values)}) returning id'
    )[0][0]


def test_single_head_stacked_on_f04():
    from alembic.config import Config
    from alembic.script import ScriptDirectory

    cfg = Config(str(_REPO_ROOT / "migrations" / "alembic.ini"))
    cfg.set_main_option("script_location", str(_REPO_ROOT / "migrations"))
    script = ScriptDirectory.from_config(cfg)
    assert script.get_heads() == [TIP]
    assert script.get_revision(TIP).down_revision == B8
    assert script.get_revision(B8).down_revision == F04
    assert script.get_revision(F04).down_revision == PREV


def test_migration_up_down_up_preserves_neighbouring_data(migrated):
    url, _name, dsn = migrated
    assert _q(dsn, "select version_num from alembic_version") == [(TIP,)]
    assert _q(dsn, f"select to_regclass('public.{TABLE}') is not null") == [(True,)]
    uid = _insert_user(dsn)
    _q(
        dsn,
        f"insert into {TABLE} (public_id, phone, phone_key, status, created_at, updated_at) "
        "values (%s, '07700000001', '7700000001', 'pending', now(), now())",
        str(uuid.uuid4()),
    )

    _flask_db(dsn, "upgrade")  # idempotent at head
    assert _q(dsn, "select version_num from alembic_version") == [(TIP,)]

    _flask_db(dsn, "downgrade", F04)
    assert _q(dsn, "select version_num from alembic_version") == [(F04,)]
    assert _q(dsn, f"select to_regclass('public.{TABLE}') is not null") == [(False,)]
    assert _q(dsn, "select to_regclass('public.saved_search_alert_job') is not null") == [(True,)]
    assert _q(dsn, 'select count(*) from "user" where id = %s', uid) == [(1,)]  # users untouched

    _flask_db(dsn, "upgrade")
    assert _q(dsn, "select version_num from alembic_version") == [(TIP,)]
    assert _q(dsn, f"select count(*) from {TABLE}") == [(0,)]  # downgrade drops queue history only


def test_model_matches_migrated_schema(migrated):
    from alembic.autogenerate import compare_metadata
    from alembic.migration import MigrationContext
    from sqlalchemy import create_engine

    from kk.models import db

    _url, _name, dsn = migrated
    engine = create_engine(dsn.replace("postgresql://", "postgresql+psycopg://", 1))
    try:
        with engine.connect() as conn:
            ctx = MigrationContext.configure(
                conn,
                opts={
                    "compare_type": True,
                    "include_name": lambda name, type_, parent: type_ != "table" or name == TABLE,
                    "include_object": lambda obj, name, type_, reflected, compare_to: (
                        (getattr(obj, "table", None) is not None and obj.table.name == TABLE)
                        if type_ in ("index", "unique_constraint", "foreign_key_constraint", "column")
                        else name == TABLE
                    ),
                },
            )
            diffs = compare_metadata(ctx, db.metadata)
    finally:
        engine.dispose()
    assert diffs == [], diffs


def test_partial_unique_index_semantics_on_postgresql(migrated):
    import psycopg

    _url, _name, dsn = migrated

    def ins(key, status):
        _q(
            dsn,
            f"insert into {TABLE} (public_id, phone, phone_key, status, created_at, updated_at) "
            "values (%s, %s, %s, %s, now(), now())",
            str(uuid.uuid4()),
            key,
            key,
            status,
        )

    key = f"77{uuid.uuid4().int % 10**8:08d}"
    ins(key, "pending")
    with pytest.raises(psycopg.errors.UniqueViolation):
        ins(key, "pending")  # second pending for the same phone is impossible
    ins(key, "completed")  # completed rows never block
    ins(key, "completed")
    _q(dsn, f"update {TABLE} set status = 'completed' where phone_key = %s and status = 'pending'", key)
    ins(key, "pending")  # a new request is allowed once the old one is completed


def test_concurrent_duplicate_submissions_create_exactly_one_row(migrated, monkeypatch):
    url, _name, dsn = migrated
    monkeypatch.setenv("APP_ENV", "testing")
    monkeypatch.setenv("SMS_PROVIDER", "console")
    monkeypatch.setenv("SECRET_KEY", secrets.token_hex(16))
    monkeypatch.setenv("JWT_SECRET_KEY", secrets.token_hex(16))
    monkeypatch.delenv("DB_PATH", raising=False)
    monkeypatch.setenv("DATABASE_URL", dsn)
    monkeypatch.setenv("AUTO_MIGRATE", "0")
    monkeypatch.setenv("UPLOAD_FOLDER", tempfile.mkdtemp(prefix="b8_pg_uploads_"))

    from kk.app_factory import create_app
    from kk.account_deletion_requests import phone_key_for, submit_request
    from kk.models import AccountDeletionRequest, db

    app, _socketio, *_ = create_app()
    assert app.config["SQLALCHEMY_DATABASE_URI"].startswith("postgresql")
    phone = f"077{uuid.uuid4().int % 10**8:08d}"
    n = 8
    barrier = threading.Barrier(n)
    results: list = []
    errors: list = []

    def worker():
        try:
            with app.app_context():
                barrier.wait(timeout=30)
                row, created = submit_request(
                    phone=phone, email="", details="", ip=None, support_email=""
                )
                results.append((row.public_id, created))
        except Exception as e:  # pragma: no cover - surfaced by the assertion below
            errors.append(e)

    threads = [threading.Thread(target=worker) for _ in range(n)]
    for t in threads:
        t.start()
    for t in threads:
        t.join(60)
    assert not errors, errors
    assert len(results) == n
    assert len({pid for pid, _c in results}) == 1, "every caller must resolve to the same single request"
    assert sum(1 for _p, created in results if created) == 1
    with app.app_context():
        assert AccountDeletionRequest.query.filter_by(phone_key=phone_key_for(phone)).count() == 1
        db.session.remove()
        db.engine.dispose()
