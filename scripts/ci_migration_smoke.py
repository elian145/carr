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


# C-11: revision immediately before "price Float -> Numeric(12, 2)".
_C11_PRE_REVISION = "d2e3f4a5b6c7"
_C11_EXPECTED_INDEXES = ("ix_car_price", "ix_car_active_brand_price", "ix_car_active_year_price")


def _c11_price_numeric_round_trip(app) -> int:
    """C-11: verify the price Float -> Numeric(12, 2) migration against real Postgres.

    Downgrades one revision (back to Float), seeds a row with pre-existing
    binary float noise (e.g. 12000.000000000002 -- the kind of value that
    accumulates from float8 storage/arithmetic), then re-applies the
    migration and asserts:
      - car.price / user_favorites.price_at_favorite round to an exact
        2-decimal-place Decimal (not left noisy, not just truncated to int).
      - Both columns are actually numeric(12, 2) in Postgres afterwards.
      - The price-related indexes on `car` survived the ALTER COLUMN.
    """
    from decimal import Decimal

    from sqlalchemy import inspect, text

    noisy_price = 12000.000000000002
    expected_price = Decimal("12000.00")

    print(f"C-11: downgrading to {_C11_PRE_REVISION} to reseed float noise...", flush=True)
    _run([sys.executable, "-m", "flask", "db", "downgrade", _C11_PRE_REVISION])

    from kk.extensions import db
    from kk.models import Car, User, user_favorites
    from kk.time_utils import utcnow

    with app.app_context():
        seller = User(
            username="c11_smoke_seller",
            phone_number="07001110000",
            first_name="C11",
            last_name="Smoke",
            is_active=True,
            is_verified=True,
            phone_verified=True,
            public_id="c11smokeseller",
        )
        seller.set_password("Aa123456")
        viewer = User(
            username="c11_smoke_viewer",
            phone_number="07001110001",
            first_name="C11",
            last_name="Viewer",
            is_active=True,
            is_verified=True,
            phone_verified=True,
            public_id="c11smokeviewer",
        )
        viewer.set_password("Aa123456")
        db.session.add_all([seller, viewer])
        db.session.flush()

        # At this point (pre-C-11 revision) the column is still Float; this
        # is a plain float insert, matching how pre-migration production
        # data could have accumulated noise.
        car = Car(
            seller_id=seller.id,
            brand="c11smoke",
            model="floatnoise",
            year=2020,
            mileage=1,
            engine_type="gas",
            transmission="auto",
            drive_type="fwd",
            condition="used",
            body_type="sedan",
            price=noisy_price,
            location="Erbil",
            is_active=True,
        )
        db.session.add(car)
        db.session.commit()
        car_id = car.id

        raw_price = db.session.execute(
            text("SELECT price FROM car WHERE id = :id"), {"id": car_id}
        ).scalar()
        print(f"C-11: seeded pre-migration raw car.price = {raw_price!r}", flush=True)

        db.session.execute(
            user_favorites.insert().values(
                user_id=viewer.id,
                car_id=car_id,
                created_at=utcnow(),
                price_at_favorite=noisy_price,
            )
        )
        db.session.commit()

    print("C-11: re-upgrading to head to apply the Numeric(12, 2) conversion...", flush=True)
    _run([sys.executable, "-m", "flask", "db", "upgrade"])

    with app.app_context():
        db.session.expire_all()
        car = db.session.get(Car, car_id)
        if car is None:
            print("C-11: seeded car row disappeared after upgrade", file=sys.stderr)
            return 1
        if not isinstance(car.price, Decimal) or car.price != expected_price:
            print(
                "C-11: float noise not rounded correctly: expected "
                f"{expected_price}, got {car.price!r} ({type(car.price).__name__})",
                file=sys.stderr,
            )
            return 1
        print(
            f"C-11: car.price float-noise rounding OK ({noisy_price!r} -> {car.price})",
            flush=True,
        )

        fav_price = db.session.execute(
            text("SELECT price_at_favorite FROM user_favorites WHERE car_id = :cid"),
            {"cid": car_id},
        ).scalar()
        if fav_price != expected_price:
            print(
                "C-11: price_at_favorite not rounded correctly: expected "
                f"{expected_price}, got {fav_price!r}",
                file=sys.stderr,
            )
            return 1
        print(f"C-11: user_favorites.price_at_favorite rounding OK ({fav_price})", flush=True)

        insp = inspect(db.engine)
        car_cols = {c["name"]: c for c in insp.get_columns("car")}
        fav_cols = {c["name"]: c for c in insp.get_columns("user_favorites")}
        checks = (
            ("car.price", car_cols.get("price")),
            ("user_favorites.price_at_favorite", fav_cols.get("price_at_favorite")),
        )
        for label, col in checks:
            if col is None:
                print(f"C-11: column missing: {label}", file=sys.stderr)
                return 1
            type_str = str(col["type"]).lower().replace(" ", "")
            if "numeric(12,2)" not in type_str:
                print(f"C-11: {label} is not NUMERIC(12, 2): {col['type']!r}", file=sys.stderr)
                return 1
            print(f"C-11: {label} type OK ({col['type']})", flush=True)

        car_indexes = {ix["name"] for ix in insp.get_indexes("car")}
        missing_indexes = [name for name in _C11_EXPECTED_INDEXES if name not in car_indexes]
        if missing_indexes:
            print(f"C-11: expected index(es) missing after migration: {missing_indexes}", file=sys.stderr)
            return 1
        print(f"C-11: price indexes intact: {list(_C11_EXPECTED_INDEXES)}", flush=True)

    return 0


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

    c11_status = _c11_price_numeric_round_trip(app)
    if c11_status != 0:
        return c11_status

    print("migration smoke OK", flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
