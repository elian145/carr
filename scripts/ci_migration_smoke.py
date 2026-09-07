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


def _d01_fk_ondelete_smoke(app) -> int:
    """D-01: prove ON DELETE policies against real PostgreSQL.

    Complements ``kk/tests/test_d01_fk_ondelete.py`` (SQLite + pragma). This
    runs in the CI ``migrations`` job after the Alembic chain is at head.
    """
    import uuid

    from sqlalchemy import inspect, text
    from sqlalchemy.exc import IntegrityError

    from kk.extensions import db
    from kk.models import (
        AdminAccount,
        Car,
        CarImage,
        DealerApplication,
        ListingAnalytics,
        ListingReport,
        Message,
        User,
        UserReport,
    )
    from kk.time_utils import utcnow

    suffix = uuid.uuid4().hex[:8]
    print(f"D-01: seeding FK smoke rows (suffix={suffix})...", flush=True)

    def _user(username: str, phone: str, **extra) -> User:
        u = User(
            username=username,
            phone_number=phone,
            first_name="D01",
            last_name="Smoke",
            is_active=True,
            is_verified=True,
            phone_verified=True,
            public_id=f"d01{username}",
            **extra,
        )
        u.set_password("Aa123456")
        return u

    def _car(seller_id: int) -> Car:
        return Car(
            seller_id=seller_id,
            public_id=f"d01car{suffix}{seller_id}",
            brand="d01smoke",
            model="fk",
            year=2020,
            mileage=1,
            engine_type="gas",
            transmission="auto",
            drive_type="fwd",
            condition="used",
            body_type="sedan",
            price=1000,
            location="Erbil",
            is_active=True,
        )

    with app.app_context():
        insp = inspect(db.engine)
        car_fks = insp.get_foreign_keys("car")
        seller_fk = next(
            (
                fk
                for fk in car_fks
                if fk.get("constrained_columns") == ["seller_id"]
            ),
            None,
        )
        if not seller_fk or (seller_fk.get("options") or {}).get("ondelete") != "RESTRICT":
            print(
                f"D-01: car.seller_id ondelete is not RESTRICT: {seller_fk!r}",
                file=sys.stderr,
            )
            return 1

        seller = _user(f"d01_seller_{suffix}", f"07551{suffix[:6]}")
        buyer = _user(f"d01_buyer_{suffix}", f"07552{suffix[:6]}")
        doomed = _user(f"d01_doomed_{suffix}", f"07553{suffix[:6]}")
        principal = _user(
            f"d01_principal_{suffix}",
            f"07554{suffix[:6]}",
            is_admin=True,
        )
        db.session.add_all([seller, buyer, doomed, principal])
        db.session.flush()

        car = _car(seller.id)
        db.session.add(car)
        db.session.flush()
        db.session.add(CarImage(car_id=car.id, image_url="https://example.com/d01.jpg"))
        db.session.add(ListingAnalytics(car_id=car.id))
        report = ListingReport(reporter_id=buyer.id, car_id=car.id, reason="d01")
        db.session.add(report)
        msg = Message(
            sender_id=buyer.id,
            receiver_id=seller.id,
            car_id=car.id,
            content="d01-car-msg",
        )
        db.session.add(msg)

        orphan_msg = Message(
            sender_id=doomed.id,
            receiver_id=buyer.id,
            content="d01-user-msg",
        )
        db.session.add(orphan_msg)
        urep = UserReport(
            reporter_id=doomed.id, reported_id=buyer.id, reason="d01-user"
        )
        db.session.add(urep)
        appn = DealerApplication(
            user_id=doomed.id,
            status="submitted",
            dealership_name="D01 Shop",
            dealership_phone="07000000000",
            dealership_location="Erbil",
        )
        db.session.add(appn)

        acct = AdminAccount(
            principal_user_id=principal.id,
            origin_user_public_id=principal.public_id,
            username=f"d01_dash_{suffix}",
            password_hash="x" * 60,
            admin_role="super_admin",
            created_at=utcnow(),
            updated_at=utcnow(),
        )
        db.session.add(acct)
        db.session.commit()

        seller_id = seller.id
        car_id = car.id
        report_id = report.id
        msg_id = msg.id
        doomed_id = doomed.id
        orphan_msg_id = orphan_msg.id
        urep_id = urep.id
        appn_id = appn.id
        principal_id = principal.id

        # RESTRICT: deleting a seller who still has cars must fail at the DB.
        try:
            db.session.execute(
                text('DELETE FROM "user" WHERE id = :id'), {"id": seller_id}
            )
            db.session.commit()
            print("D-01: DELETE seller with cars unexpectedly succeeded", file=sys.stderr)
            return 1
        except IntegrityError:
            db.session.rollback()
            print("D-01: car.seller_id RESTRICT OK", flush=True)

        # RESTRICT: admin_account.principal_user_id.
        try:
            db.session.execute(
                text('DELETE FROM "user" WHERE id = :id'), {"id": principal_id}
            )
            db.session.commit()
            print(
                "D-01: DELETE admin principal unexpectedly succeeded",
                file=sys.stderr,
            )
            return 1
        except IntegrityError:
            db.session.rollback()
            print("D-01: admin_account.principal_user_id RESTRICT OK", flush=True)

        # CASCADE / SET NULL when a car is deleted at the DB level.
        db.session.execute(text("DELETE FROM car WHERE id = :id"), {"id": car_id})
        db.session.commit()
        image_left = db.session.execute(
            text("SELECT COUNT(*) FROM car_image WHERE car_id = :id"), {"id": car_id}
        ).scalar()
        analytics_left = db.session.execute(
            text("SELECT COUNT(*) FROM listing_analytics WHERE car_id = :id"),
            {"id": car_id},
        ).scalar()
        report_car_id = db.session.execute(
            text("SELECT car_id FROM listing_report WHERE id = :id"),
            {"id": report_id},
        ).scalar()
        msg_car_id = db.session.execute(
            text("SELECT car_id FROM message WHERE id = :id"), {"id": msg_id}
        ).scalar()
        if image_left or analytics_left:
            print(
                f"D-01: car child CASCADE failed image={image_left} analytics={analytics_left}",
                file=sys.stderr,
            )
            return 1
        if report_car_id is not None or msg_car_id is not None:
            print(
                f"D-01: car child SET NULL failed report.car_id={report_car_id} "
                f"message.car_id={msg_car_id}",
                file=sys.stderr,
            )
            return 1
        print("D-01: car CASCADE/SET NULL OK", flush=True)

        # SET NULL / CASCADE when a car-less user is deleted.
        db.session.execute(
            text('DELETE FROM "user" WHERE id = :id'), {"id": doomed_id}
        )
        db.session.commit()
        if db.session.get(User, doomed_id) is not None:
            print("D-01: car-less user DELETE failed", file=sys.stderr)
            return 1
        orphan = db.session.get(Message, orphan_msg_id)
        kept_urep = db.session.get(UserReport, urep_id)
        kept_app = db.session.get(DealerApplication, appn_id)
        if orphan is None or orphan.sender_id is not None:
            print(f"D-01: message.sender_id SET NULL failed: {orphan!r}", file=sys.stderr)
            return 1
        if kept_urep is None or kept_urep.reporter_id is not None:
            print(f"D-01: user_report SET NULL failed: {kept_urep!r}", file=sys.stderr)
            return 1
        if kept_app is None or kept_app.user_id is not None:
            print(
                f"D-01: dealer_application.user_id SET NULL failed: {kept_app!r}",
                file=sys.stderr,
            )
            return 1
        print("D-01: user SET NULL OK", flush=True)

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

    d01_status = _d01_fk_ondelete_smoke(app)
    if d01_status != 0:
        return d01_status

    print("migration smoke OK", flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
