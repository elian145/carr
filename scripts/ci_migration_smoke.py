#!/usr/bin/env python3
"""
CI smoke: apply Alembic migrations against Postgres and verify core tables.

Run from repo root (Postgres must already be reachable via DATABASE_URL):

  export APP_ENV=testing
  export DATABASE_URL=postgresql://postgres:postgres@127.0.0.1:5432/car_listings_ci
  export FLASK_APP=kk.wsgi:app
  python scripts/ci_migration_smoke.py
"""

from __future__ import annotations

import os
import subprocess
import sys
from pathlib import Path

_REPO_ROOT = Path(__file__).resolve().parents[1]


def _run(cmd: list[str]) -> None:
    print("+", " ".join(cmd), flush=True)
    subprocess.run(cmd, cwd=_REPO_ROOT, check=True, env=os.environ.copy())


def main() -> int:
    os.chdir(_REPO_ROOT)
    if str(_REPO_ROOT) not in sys.path:
        sys.path.insert(0, str(_REPO_ROOT))

    database_url = (os.environ.get("DATABASE_URL") or "").strip()
    if not database_url:
        print("DATABASE_URL is required", file=sys.stderr)
        return 2
    if "postgresql" not in database_url.lower():
        print("DATABASE_URL must point at Postgres for this smoke", file=sys.stderr)
        return 2

    os.environ.setdefault("APP_ENV", "testing")
    os.environ.setdefault("FLASK_APP", "kk.wsgi:app")
    os.environ.setdefault("AUTO_MIGRATE", "0")
    os.environ.setdefault("SMS_PROVIDER", "console")

    # Apply chain twice to catch non-idempotent upgrades.
    _run([sys.executable, "-m", "flask", "db", "upgrade"])
    _run([sys.executable, "-m", "flask", "db", "upgrade"])
    _run([sys.executable, "-m", "flask", "db", "current"])

    from sqlalchemy import inspect, text

    from kk.app_factory import create_app

    app, *_ = create_app()
    with app.app_context():
        from kk.extensions import db

        insp = inspect(db.engine)
        for table in ("alembic_version", "user", "car", "message"):
            if not insp.has_table(table):
                print(f"missing table after upgrade: {table}", file=sys.stderr)
                return 1

        # C-07: generic model <-> migrated-schema drift check against real
        # Postgres (see kk/schema_drift.py and PRODUCTION_AUDIT.md C-07).
        from kk.schema_drift import (
            KNOWN_NULLABLE_DRIFT,
            KNOWN_TABLE_EXCEPTIONS,
            compute_schema_drift,
        )

        drift = compute_schema_drift(
            insp,
            db.metadata,
            table_exceptions=KNOWN_TABLE_EXCEPTIONS,
            nullable_exceptions=KNOWN_NULLABLE_DRIFT,
        )
        if drift["missing_from_migrations"]:
            print(
                "model table(s) with no Alembic migration: "
                f"{drift['missing_from_migrations']}",
                file=sys.stderr,
            )
            return 1
        if drift["missing_from_models"]:
            print(
                "migration-created table(s) with no ORM model: "
                f"{drift['missing_from_models']}",
                file=sys.stderr,
            )
            return 1
        if drift["nullable_mismatches"]:
            print(f"new nullable drift: {drift['nullable_mismatches']}", file=sys.stderr)
            return 1
        print("schema drift check OK (model <-> migrated Postgres schema match)", flush=True)

        with db.engine.connect() as conn:
            row = conn.execute(
                text("SELECT version_num FROM alembic_version LIMIT 1")
            ).fetchone()
            if not row or not row[0]:
                print("alembic_version is empty", file=sys.stderr)
                return 1
            print(f"alembic_version={row[0]}", flush=True)

    print("migration smoke OK", flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
