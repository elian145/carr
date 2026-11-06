"""``python -m kk.phone_inventory_cli``: read-only, privacy-safe duplicate report.

Pinned guarantees: SELECT-only (asserted on the statements actually issued and
by a fail-closed guard), the database file is byte-identical afterwards,
only masked phones / public_ids / counts are printed, exit code non-zero only for
errors.
"""

from __future__ import annotations

import hashlib
import json
import os
import re
import subprocess
import sys
import uuid
from pathlib import Path

import pytest

_REPO_ROOT = Path(__file__).resolve().parents[2]
if str(_REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(_REPO_ROOT))

from kk import phone_inventory_cli as cli  # noqa: E402

SECRET_NAME = "Zyxwvu"
SECRET_EMAIL_DOMAIN = "secret-mail.example"

# (stored spelling, group label)
SEEDS = [
    ("7700000001", "g1"),
    ("07700000001", "g1"),
    ("7700000002", "g2"),
    ("+9647700000002", "g2"),
    ("009647700000002", "g2"),
    ("7700000003", "g3"),
    ("٧٧٠٠٠٠٠٠٠٣", "g3"),  # Arabic-Indic digits
    ("7700000004", None),  # unique, no collision
    ("+15551234567", None),  # foreign, unique
    ("deleted_12345678", None),  # placeholder written by account deletion
]
FULL_NUMBERS = ["7700000001", "7700000002", "7700000003", "7700000004", "5551234567", "15551234567"]


@pytest.fixture(scope="module")
def db_file(tmp_path_factory):
    for key in ("DATABASE_URL", "DB_PATH", "APP_ENV"):
        os.environ.pop(key, None)
    path = tmp_path_factory.mktemp("phone_inv") / "inv.db"

    from flask import Flask

    from kk.models import User, db

    app = Flask(__name__)
    app.config["SQLALCHEMY_DATABASE_URI"] = "sqlite:///" + str(path).replace("\\", "/")
    app.config["SQLALCHEMY_TRACK_MODIFICATIONS"] = False
    db.init_app(app)
    with app.app_context():
        db.create_all()
        for i, (phone, _label) in enumerate(SEEDS):
            u = User(
                username=f"inv_{i}_{uuid.uuid4().hex[:6]}",
                email=f"u{i}@{SECRET_EMAIL_DOMAIN}",
                phone_number=phone,
                first_name=SECRET_NAME,
                last_name="Person",
                public_id=f"pub-inv-{i}",
                is_active=(i != 1),
            )
            u.set_password("Aa123456!")
            db.session.add(u)
        db.session.commit()
        db.session.remove()
        db.engine.dispose()
    return path


def _sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def _run(argv, capsys):
    code = cli.main(argv)
    out = capsys.readouterr()
    return code, out.out, out.err


# ------------------------------------------------------------------ content
def test_json_report_counts_and_members(db_file, capsys):
    code, out, err = _run(["--db-path", str(db_file), "--json"], capsys)
    assert code == 0, err
    rep = json.loads(out)
    assert rep["read_only"] is True
    assert rep["total_users"] == len(SEEDS)
    assert rep["non_phone_rows"] == 1
    assert rep["phone_like_users"] == len(SEEDS) - 1
    assert rep["collision_groups"] == 3
    assert rep["users_in_collision_groups"] == 7
    assert rep["manual_merge_required"] is True
    members = {m["public_id"] for g in rep["groups"] for m in g["members"]}
    assert members == {f"pub-inv-{i}" for i in range(7)}
    spellings = {m["spelling"] for g in rep["groups"] for m in g["members"]}
    assert {"canonical", "leading_zero", "plus_prefixed", "international_00", "non_ascii_digits"} <= spellings
    inactive = [m for g in rep["groups"] for m in g["members"] if not m["is_active"]]
    assert [m["public_id"] for m in inactive] == ["pub-inv-1"]
    assert "manual" in rep["note"].lower() and "separately approved" in rep["note"].lower()


def test_text_and_summary_modes(db_file, capsys):
    code, out, _ = _run(["--db-path", str(db_file)], capsys)
    assert code == 0
    assert "duplicate groups:          3" in out
    assert "pub-inv-0" in out and "group 1" in out
    code, out, _ = _run(["--db-path", str(db_file), "--summary"], capsys)
    assert code == 0
    assert "duplicate groups:          3" in out
    assert "pub-inv-" not in out and "group 1" not in out
    code, out, _ = _run(["--db-path", str(db_file), "--summary", "--json"], capsys)
    rep = json.loads(out)
    assert "groups" not in rep and rep["collision_groups"] == 3


def test_group_limit_keeps_counts_exact(db_file, capsys):
    code, out, _ = _run(["--db-path", str(db_file), "--json", "--limit", "1"], capsys)
    rep = json.loads(out)
    assert rep["collision_groups"] == 3 and rep["groups_listed"] == 1 and len(rep["groups"]) == 1


def test_duplicates_found_still_exit_zero_and_output_is_deterministic(db_file, capsys):
    a = _run(["--db-path", str(db_file), "--json"], capsys)
    b = _run(["--db-path", str(db_file), "--json"], capsys)
    assert a[0] == b[0] == 0
    assert a[1] == b[1]


# ------------------------------------------------------------------ privacy
@pytest.mark.parametrize("mode", [[], ["--json"], ["--summary"], ["--summary", "--json"]])
def test_output_never_contains_full_phones_names_emails_or_url(db_file, capsys, mode):
    code, out, err = _run(["--db-path", str(db_file), *mode], capsys)
    assert code == 0
    blob = out + err
    for number in FULL_NUMBERS:
        assert number not in blob
    for phone, _ in SEEDS:
        assert phone not in blob
    assert SECRET_NAME not in blob and SECRET_EMAIL_DOMAIN not in blob and "inv_" not in blob
    assert str(db_file) not in blob
    # no run of >3 consecutive digits except inside public ids / counts
    stripped = re.sub(r"pub-inv-\d+", "", blob)
    stripped = re.sub(r"\*+\d{1,3}", "", stripped)
    assert not re.search(r"\d{4,}", stripped), stripped


def test_mask_never_reveals_more_than_three_digits():
    assert cli.mask_phone("7700000001") == "*******001"
    assert cli.mask_phone("+9647700000001") == "**********001"
    assert cli.mask_phone("123") == "****"
    assert cli.mask_phone(None) == "****"
    for raw in ("7700000001", "07700000001", "٧٧٠٠٠٠٠٠٠١"):
        assert len(re.findall(r"\d", cli.mask_phone(raw))) <= 3


def test_error_output_does_not_echo_database_url(monkeypatch, capsys):
    secret = "postgresql://dbuser:s3cretpw@127.0.0.1:1/nodb"
    monkeypatch.delenv("DATABASE_URL", raising=False)
    code, out, err = _run(["--database-url", secret], capsys)
    assert code == 3
    assert "s3cretpw" not in out + err and "dbuser" not in out + err


# ------------------------------------------------------------------ read-only
def test_only_select_statements_are_issued(db_file, monkeypatch, capsys):
    from sqlalchemy import event

    seen: list[str] = []
    real_open = cli.open_readonly_engine

    def spying_open(**kw):
        engine = real_open(**kw)

        @event.listens_for(engine, "before_cursor_execute")
        def _record(_c, _cur, statement, *_a):
            seen.append(statement)

        return engine

    monkeypatch.setattr(cli, "open_readonly_engine", spying_open)
    code, _out, err = _run(["--db-path", str(db_file), "--json"], capsys)
    assert code == 0, err
    assert seen, "expected at least the user SELECT"
    for stmt in seen:
        assert re.match(r"^\s*(select|show)\b", stmt, re.I), stmt
        assert not re.search(r"\b(insert|update|delete|drop|alter|create)\b", stmt, re.I), stmt
    assert any('FROM "user"' in s for s in seen)


def test_database_file_is_unchanged_after_a_run(db_file, capsys):
    before = (_sha(db_file), db_file.stat().st_size, db_file.stat().st_mtime_ns)
    for argv in (["--json"], [], ["--summary"]):
        assert _run(["--db-path", str(db_file), *argv], capsys)[0] == 0
    assert (_sha(db_file), db_file.stat().st_size, db_file.stat().st_mtime_ns) == before
    leftovers = [p.name for p in db_file.parent.iterdir() if p.name != db_file.name]
    assert leftovers == []


@pytest.mark.parametrize(
    "sql",
    [
        'UPDATE "user" SET phone_number = \'x\'',
        'INSERT INTO "user" (username) VALUES (\'x\')',
        'DELETE FROM "user"',
        'DROP TABLE "user"',
        "PRAGMA query_only=OFF",
        'WITH d AS (SELECT 1) DELETE FROM "user"',
        "SELECT 1; DELETE FROM \"user\"",
        "  update \"user\" set is_active = 0",
    ],
)
def test_guard_fails_closed_for_any_write(db_file, sql):
    from sqlalchemy import text

    engine = cli.open_readonly_engine(db_path=str(db_file))
    try:
        with pytest.raises(cli.ReadOnlyViolation):
            with engine.connect() as conn:
                conn.execute(text(sql))
    finally:
        engine.dispose()


def test_database_layer_refuses_writes_even_if_the_guard_were_bypassed(db_file):
    """Defence in depth: bypass SQLAlchemy entirely and write through the DBAPI."""
    import sqlite3

    engine = cli.open_readonly_engine(db_path=str(db_file))
    before = _sha(db_file)
    try:
        raw = engine.raw_connection()
        try:
            cur = raw.cursor()
            with pytest.raises(sqlite3.OperationalError):
                cur.execute('UPDATE "user" SET phone_number = \'0\'')
                raw.commit()
        finally:
            raw.close()
    finally:
        engine.dispose()
    assert _sha(db_file) == before


def test_missing_sqlite_file_is_an_error_and_is_not_created(tmp_path, capsys):
    target = tmp_path / "nope.db"
    code, out, err = _run(["--db-path", str(target)], capsys)
    assert code == cli.EXIT_USAGE
    assert not target.exists()


def test_is_read_only_statement_table():
    ok = ["SELECT 1", "  select * from x", "SHOW server_version", "WITH a AS (SELECT 1) SELECT * FROM a"]
    bad = [
        "UPDATE t SET a=1",
        "insert into t values (1)",
        "DELETE FROM t",
        "DROP TABLE t",
        "CREATE TABLE t(a)",
        "TRUNCATE t",
        "COPY t TO STDOUT",
        "SELECT * INTO new_t FROM t",
        "WITH a AS (SELECT 1) DELETE FROM t",
        "",
        "BEGIN",
    ]
    assert all(cli.is_read_only_statement(s) for s in ok)
    assert not any(cli.is_read_only_statement(s) for s in bad)


def test_module_has_no_write_path():
    src = Path(cli.__file__).read_text(encoding="utf-8")
    import ast

    imported: set[str] = set()
    for node in ast.walk(ast.parse(src)):
        if isinstance(node, ast.Import):
            imported.update(a.name for a in node.names)
        elif isinstance(node, ast.ImportFrom):
            imported.add(("." * node.level) + (node.module or ""))
            imported.update(a.name for a in node.names)
    # the Flask app / models (create_app runs migrations) are never imported;
    # the only project import is the pure canonicaliser from the auth routes.
    assert not {i for i in imported if "app_factory" in i or "models" in i or "create_app" in i}
    assert not re.search(r"\.commit\(|session\.add|\.merge\(|db\.session", src)
    assert "separately approved" in src.lower()


# ------------------------------------------------------------------ errors
def test_no_database_configured_is_a_usage_error(monkeypatch, capsys):
    monkeypatch.delenv("DATABASE_URL", raising=False)
    code, _out, err = _run([], capsys)
    assert code == cli.EXIT_USAGE and "no database configured" in err


def test_unreadable_database_is_a_db_error(tmp_path, capsys):
    bad = tmp_path / "garbage.db"
    bad.write_bytes(b"this is not a sqlite database" * 20)
    code, _out, err = _run(["--db-path", str(bad)], capsys)
    assert code == cli.EXIT_DB
    assert "garbage" not in err


def test_schema_without_user_table_is_a_db_error(tmp_path, capsys):
    import sqlite3

    p = tmp_path / "empty.db"
    sqlite3.connect(p).close()
    code, _out, err = _run(["--db-path", str(p)], capsys)
    assert code == cli.EXIT_DB


def test_unsupported_url_scheme_is_a_usage_error(capsys):
    code, _out, err = _run(["--database-url", "mysql://u:p@h/db"], capsys)
    assert code == cli.EXIT_USAGE


def test_python_dash_m_entrypoint(db_file):
    env = {k: v for k, v in os.environ.items() if k not in ("DATABASE_URL", "DB_PATH", "APP_ENV")}
    proc = subprocess.run(
        [sys.executable, "-m", "kk.phone_inventory_cli", "--db-path", str(db_file), "--json"],
        cwd=str(_REPO_ROOT),
        env=env,
        capture_output=True,
        text=True,
        timeout=120,
    )
    assert proc.returncode == 0, proc.stderr
    assert json.loads(proc.stdout)["collision_groups"] == 3


# ------------------------------------------------------------------ pure logic
def test_build_inventory_pure_function():
    rows = [
        (1, "a", "7711111111", True),
        (2, "b", "07711111111", True),
        (3, "c", "7722222222", True),
        (4, "d", None, True),
        (5, "e", "adm_5_abcdef", True),
    ]
    rep = cli.build_inventory(rows)
    assert rep["collision_groups"] == 1 and rep["non_phone_rows"] == 2
    assert [m["public_id"] for m in rep["groups"][0]["members"]] == ["a", "b"]
    assert rep["manual_merge_required"] is True
    assert cli.build_inventory([(1, "a", "7711111111", True)])["manual_merge_required"] is False


@pytest.mark.skipif(not os.environ.get("PHONE_INVENTORY_TEST_PG_URL"), reason="disposable PG not configured")
def test_postgres_read_only_run(capsys):
    url = os.environ["PHONE_INVENTORY_TEST_PG_URL"]
    code, out, err = _run(["--database-url", url, "--json"], capsys)
    assert code == 0, err
    assert json.loads(out)["read_only"] is True
