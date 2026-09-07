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


# D-05: nullability hardening -- revision immediately before
# migrations/versions/3f945e50c327_d05_nullability_hardening.py.
_D05_PRE_REVISION = "d7e6c32b1689"


def _d05_nullability_hardening_smoke(app) -> int:
    """D-05: prove the nullability-hardening migration against real PostgreSQL.

    Mirrors ``_c11_price_numeric_round_trip``'s downgrade / reseed / re-upgrade
    shape and complements ``kk/tests/test_d05_nullability_backfill.py``
    (SQLite): downgrades one revision to widen `user.account_type`,
    `user.dealer_status`, and `saved_search.filters` back to nullable, seeds
    both a "dirty" (explicit NULL, via raw SQL so no ORM/Core default can
    mask it) and a "clean" (explicit non-default value) row for each, then
    re-applies the migration and asserts:
      - the dirty rows were backfilled to the documented defaults,
      - the clean rows were left completely untouched,
      - all three columns are actually NOT NULL in Postgres afterwards,
      - PostgreSQL itself now rejects a raw NULL insert/update (not just the
        ORM).
    Self-cleaning: the seeded rows are deleted before returning, regardless
    of outcome, so re-running this smoke against the same database is safe.
    """
    import uuid

    from sqlalchemy import inspect, text
    from sqlalchemy.exc import IntegrityError

    from kk.extensions import db

    suffix = uuid.uuid4().hex[:8]
    dirty_username = f"d05_dirty_{suffix}"
    clean_username = f"d05_clean_{suffix}"
    dirty_user_id: int | None = None
    clean_user_id: int | None = None

    print(f"D-05: downgrading to {_D05_PRE_REVISION} to reseed NULLs...", flush=True)
    _run([sys.executable, "-m", "flask", "db", "downgrade", _D05_PRE_REVISION])

    try:
        with app.app_context():
            dirty_user_id = db.session.execute(
                text(
                    "INSERT INTO \"user\" "
                    "(public_id, username, password_hash, phone_number, first_name, last_name, "
                    " account_type, dealer_status) "
                    "VALUES (:pid, :username, 'x', :phone, 'D05', 'Dirty', NULL, NULL) "
                    "RETURNING id"
                ),
                {"pid": f"d05dirty{suffix}", "username": dirty_username, "phone": f"07562{suffix[:6]}"},
            ).scalar()
            clean_user_id = db.session.execute(
                text(
                    "INSERT INTO \"user\" "
                    "(public_id, username, password_hash, phone_number, first_name, last_name, "
                    " account_type, dealer_status) "
                    "VALUES (:pid, :username, 'x', :phone, 'D05', 'Clean', 'dealer', 'approved') "
                    "RETURNING id"
                ),
                {"pid": f"d05clean{suffix}", "username": clean_username, "phone": f"07563{suffix[:6]}"},
            ).scalar()

            dirty_search_id = db.session.execute(
                text(
                    "INSERT INTO saved_search (public_id, user_id, name, filters, notify, auto_saved) "
                    "VALUES (:pid, :uid, 'Dirty search', NULL, true, false) RETURNING id"
                ),
                {"pid": f"d05dirtysearch{suffix}", "uid": clean_user_id},
            ).scalar()
            clean_search_id = db.session.execute(
                text(
                    "INSERT INTO saved_search (public_id, user_id, name, filters, notify, auto_saved) "
                    "VALUES (:pid, :uid, 'Clean search', CAST(:filters AS json), true, false) RETURNING id"
                ),
                {
                    "pid": f"d05cleansearch{suffix}",
                    "uid": clean_user_id,
                    "filters": '{"brand": "toyota"}',
                },
            ).scalar()
            db.session.commit()

            # Sanity: prove the dirty rows are genuinely NULL pre-migration.
            row = db.session.execute(
                text("SELECT account_type, dealer_status FROM \"user\" WHERE id = :id"),
                {"id": dirty_user_id},
            ).fetchone()
            if row is None or row[0] is not None or row[1] is not None:
                print(f"D-05: dirty user seed did not land as NULL: {row!r}", file=sys.stderr)
                return 1
            row = db.session.execute(
                text("SELECT filters FROM saved_search WHERE id = :id"), {"id": dirty_search_id}
            ).fetchone()
            if row is None or row[0] is not None:
                print(f"D-05: dirty saved_search seed did not land as NULL: {row!r}", file=sys.stderr)
                return 1

        print("D-05: re-upgrading to head to apply the NOT NULL hardening...", flush=True)
        _run([sys.executable, "-m", "flask", "db", "upgrade"])

        with app.app_context():
            db.session.expire_all()

            row = db.session.execute(
                text("SELECT account_type, dealer_status FROM \"user\" WHERE id = :id"),
                {"id": dirty_user_id},
            ).fetchone()
            if row is None or row[0] != "user" or row[1] != "none":
                print(f"D-05: dirty user row not backfilled correctly: {row!r}", file=sys.stderr)
                return 1
            print("D-05: user.account_type/dealer_status backfill OK (NULL -> 'user'/'none')", flush=True)

            row = db.session.execute(
                text("SELECT account_type, dealer_status FROM \"user\" WHERE id = :id"),
                {"id": clean_user_id},
            ).fetchone()
            if row is None or row[0] != "dealer" or row[1] != "approved":
                print(f"D-05: clean user row was clobbered by backfill: {row!r}", file=sys.stderr)
                return 1
            print("D-05: pre-existing non-NULL user values preserved OK", flush=True)

            row = db.session.execute(
                text("SELECT filters FROM saved_search WHERE id = :id"), {"id": dirty_search_id}
            ).fetchone()
            if row is None or row[0] != {}:
                print(f"D-05: dirty saved_search row not backfilled correctly: {row!r}", file=sys.stderr)
                return 1
            print("D-05: saved_search.filters backfill OK (NULL -> {})", flush=True)

            row = db.session.execute(
                text("SELECT filters FROM saved_search WHERE id = :id"), {"id": clean_search_id}
            ).fetchone()
            if row is None or row[0] != {"brand": "toyota"}:
                print(f"D-05: clean saved_search row was clobbered by backfill: {row!r}", file=sys.stderr)
                return 1
            print("D-05: pre-existing non-NULL saved_search.filters preserved OK", flush=True)

            insp = inspect(db.engine)
            user_cols = {c["name"]: c for c in insp.get_columns("user")}
            search_cols = {c["name"]: c for c in insp.get_columns("saved_search")}
            checks = (
                ("user.account_type", user_cols.get("account_type")),
                ("user.dealer_status", user_cols.get("dealer_status")),
                ("saved_search.filters", search_cols.get("filters")),
            )
            for label, col in checks:
                if col is None:
                    print(f"D-05: column missing: {label}", file=sys.stderr)
                    return 1
                if col["nullable"]:
                    print(f"D-05: {label} is still nullable in Postgres after migration", file=sys.stderr)
                    return 1
                print(f"D-05: {label} is NOT NULL in Postgres OK", flush=True)

            # PostgreSQL itself (not just the ORM/model) must now reject NULL.
            for label, stmt, params in (
                (
                    "user.account_type",
                    text(
                        "INSERT INTO \"user\" "
                        "(public_id, username, password_hash, phone_number, first_name, last_name, "
                        " account_type, dealer_status) "
                        "VALUES (:pid, :username, 'x', :phone, 'D05', 'Reject', NULL, 'none')"
                    ),
                    {
                        "pid": f"d05reject1{suffix}",
                        "username": f"d05_reject1_{suffix}",
                        "phone": f"07564{suffix[:6]}",
                    },
                ),
                (
                    "user.dealer_status",
                    text(
                        "INSERT INTO \"user\" "
                        "(public_id, username, password_hash, phone_number, first_name, last_name, "
                        " account_type, dealer_status) "
                        "VALUES (:pid, :username, 'x', :phone, 'D05', 'Reject', 'user', NULL)"
                    ),
                    {
                        "pid": f"d05reject2{suffix}",
                        "username": f"d05_reject2_{suffix}",
                        "phone": f"07565{suffix[:6]}",
                    },
                ),
                (
                    "saved_search.filters",
                    text(
                        "INSERT INTO saved_search (public_id, user_id, name, filters, notify, auto_saved) "
                        "VALUES (:pid, :uid, 'Reject search', NULL, true, false)"
                    ),
                    {"pid": f"d05reject3{suffix}", "uid": clean_user_id},
                ),
            ):
                try:
                    db.session.execute(stmt, params)
                    db.session.commit()
                except IntegrityError:
                    db.session.rollback()
                    print(f"D-05: {label} correctly rejects NULL at the database level OK", flush=True)
                else:
                    print(f"D-05: {label} accepted a NULL insert -- NOT NULL not enforced", file=sys.stderr)
                    return 1

        print("D-05: nullability hardening migration OK", flush=True)
        return 0
    finally:
        # Self-cleaning: remove every row this smoke seeded, regardless of
        # outcome, so re-running it against the same database is safe.
        with app.app_context():
            db.session.rollback()
            db.session.execute(
                text("DELETE FROM saved_search WHERE public_id LIKE :pat"), {"pat": f"d05%{suffix}"}
            )
            db.session.execute(
                text("DELETE FROM \"user\" WHERE public_id LIKE :pat"), {"pat": f"d05%{suffix}"}
            )
            db.session.commit()


# D-04: atomic SQL counters -- real-PostgreSQL concurrency proofs.
#
# Deliberately separate from the SQLite functional tests in
# kk/tests/test_d04_atomic_counters.py: those prove the *logic* is correct;
# these prove the *concurrency* guarantee actually holds under real
# PostgreSQL MVCC/row-locking, not SQLite. Each check uses its own
# threading.Thread per "concurrent request", each with an independent
# Flask app context (and therefore an independent scoped session/DB
# connection) -- ORM objects are never shared across threads; each thread
# re-loads its own row by id.
_D04_THREAD_JOIN_TIMEOUT_S = 30


def _d04_atomic_increment_primitive_smoke(app) -> int:
    """
    D-04 / A1: 20 concurrent PostgreSQL transactions each independently
    load the same User and call `atomic_increment_attempts()`. The final
    counter value must equal exactly 20 -- no lost updates, no unhandled
    database exceptions -- proving the atomic-UPDATE primitive itself
    (not yet any surrounding lockout logic) is race-free.
    """
    import threading
    import uuid

    from kk.extensions import db
    from kk.models import User
    from kk.security import atomic_increment_attempts

    suffix = uuid.uuid4().hex[:8]
    print(f"D-04: seeding atomic-increment-primitive smoke user (suffix={suffix})...", flush=True)

    with app.app_context():
        user = User(
            username=f"d04_prim_{suffix}",
            phone_number=f"07561{suffix[:6]}",
            first_name="D04",
            last_name="Primitive",
            is_active=True,
            is_verified=True,
            phone_verified=True,
            public_id=f"d04prim{suffix}",
            phone_verification_attempts=0,
        )
        user.set_password("Aa123456")
        db.session.add(user)
        db.session.commit()
        user_id = user.id

    n = 20
    barrier = threading.Barrier(n)
    errors: list[BaseException | None] = [None] * n

    def _worker(slot: int) -> None:
        try:
            barrier.wait(timeout=_D04_THREAD_JOIN_TIMEOUT_S)
            with app.app_context():
                thread_user = db.session.get(User, user_id)
                atomic_increment_attempts(thread_user, "phone_verification_attempts")
                db.session.commit()
        except BaseException as exc:  # noqa: BLE001 - captured for the main thread to report
            errors[slot] = exc

    threads = [threading.Thread(target=_worker, args=(i,)) for i in range(n)]
    for t in threads:
        t.start()
    for t in threads:
        t.join(timeout=_D04_THREAD_JOIN_TIMEOUT_S)

    failed = [(i, e) for i, e in enumerate(errors) if e is not None]
    if failed:
        for i, e in failed:
            print(f"D-04: primitive smoke thread {i} raised: {e!r}", file=sys.stderr)
        return 1

    with app.app_context():
        final = db.session.get(User, user_id).phone_verification_attempts
    if final != n:
        print(
            f"D-04: atomic_increment_attempts lost updates under concurrency: "
            f"expected {n}, got {final}",
            file=sys.stderr,
        )
        return 1
    print(f"D-04: atomic_increment_attempts primitive OK ({n} concurrent increments -> {final})", flush=True)
    return 0


def _d04_otp_lockout_concurrency_smoke(app) -> int:
    """
    D-04 / A2: exercise the actual `_consume_phone_otp()` business-logic
    function (threshold + lockout, not just the raw counter) under real
    concurrency, in two scenarios:

      A2a. N = _OTP_MAX_ATTEMPTS - 1 concurrent wrong-code attempts must
           record exactly N attempts (not fewer -- proves no lost
           increment lets an attacker keep extra "free" guesses) and must
           not lock the account.
      A2b. N = _OTP_MAX_ATTEMPTS concurrent wrong-code attempts must
           produce exactly one "otp_locked" (429) result and N-1
           "otp_invalid" (400) results, with the same lockout/reset state
           the sequential test in kk/tests/test_signup_otp_required.py
           already proves for the non-concurrent case.

    Assertions are on aggregate outcome (counts / final DB state), never
    on which specific thread got which result, so they do not depend on
    thread-scheduling order -- only on the atomicity already proven by
    `_d04_atomic_increment_primitive_smoke`.
    """
    import threading
    import uuid
    from collections import Counter
    from datetime import timedelta

    from kk.extensions import db
    from kk.models import User
    from kk.routes.auth import (
        _OTP_MAX_ATTEMPTS,
        OtpError,
        _consume_phone_otp,
        _hash_phone_verification_code,
    )
    from kk.time_utils import utcnow

    def _seed_user(tag: str) -> tuple[int, str]:
        suffix = uuid.uuid4().hex[:8]
        phone = f"07562{suffix[:6]}"
        with app.app_context():
            user = User(
                username=f"d04_{tag}_{suffix}",
                phone_number=phone,
                first_name="D04",
                last_name="Otp",
                is_active=True,
                is_verified=True,
                phone_verified=True,
                public_id=f"d04{tag}{suffix}",
                phone_verification_attempts=0,
                phone_verification_code_hash=_hash_phone_verification_code(
                    phone, "123456"
                ),
                phone_verification_expires_at=utcnow() + timedelta(minutes=10),
            )
            user.set_password("Aa123456")
            db.session.add(user)
            db.session.commit()
            return user.id, phone

    def _run_concurrent_wrong_attempts(n: int, tag: str) -> tuple[int, str, list]:
        user_id, phone = _seed_user(tag)
        barrier = threading.Barrier(n)
        # (code, status) per thread, or an exception repr on unexpected failure.
        results: list[object] = [None] * n

        def _worker(slot: int) -> None:
            try:
                barrier.wait(timeout=_D04_THREAD_JOIN_TIMEOUT_S)
                with app.app_context():
                    thread_user = db.session.get(User, user_id)
                    try:
                        _consume_phone_otp(thread_user, phone, "000000")
                        results[slot] = ("no_error", 0)
                    except OtpError as exc:
                        results[slot] = (exc.code, exc.status)
            except BaseException as exc:  # noqa: BLE001
                results[slot] = ("unexpected_exception", repr(exc))

        threads = [threading.Thread(target=_worker, args=(i,)) for i in range(n)]
        for t in threads:
            t.start()
        for t in threads:
            t.join(timeout=_D04_THREAD_JOIN_TIMEOUT_S)

        return user_id, phone, results

    # --- A2a: below threshold -----------------------------------------
    n_below = _OTP_MAX_ATTEMPTS - 1
    print(f"D-04: OTP lockout smoke -- {n_below} concurrent wrong attempts (below threshold)...", flush=True)
    user_id, _phone, results = _run_concurrent_wrong_attempts(n_below, "below")

    unexpected = [r for r in results if not isinstance(r, tuple) or r[0] == "unexpected_exception"]
    if unexpected:
        print(f"D-04: unexpected thread failures (below-threshold): {unexpected}", file=sys.stderr)
        return 1

    outcome_counts = Counter(r[0] for r in results)
    if outcome_counts.get("otp_invalid", 0) != n_below or "otp_locked" in outcome_counts:
        print(
            f"D-04: below-threshold concurrent attempts gave unexpected outcomes: {dict(outcome_counts)} "
            f"(expected exactly {n_below} otp_invalid, zero otp_locked)",
            file=sys.stderr,
        )
        return 1

    with app.app_context():
        u = db.session.get(User, user_id)
        if u.phone_verification_attempts != n_below:
            print(
                f"D-04: below-threshold final attempts={u.phone_verification_attempts}, "
                f"expected exactly {n_below} (a lower value means a lost increment)",
                file=sys.stderr,
            )
            return 1
        if u.phone_verification_locked_until is not None:
            print("D-04: below-threshold attempts unexpectedly locked the account", file=sys.stderr)
            return 1
    print(f"D-04: below-threshold OK (exactly {n_below} recorded, no lockout)", flush=True)

    # --- A2b: at threshold ----------------------------------------------
    n_at = _OTP_MAX_ATTEMPTS
    print(f"D-04: OTP lockout smoke -- {n_at} concurrent wrong attempts (at threshold)...", flush=True)
    user_id, _phone, results = _run_concurrent_wrong_attempts(n_at, "at")

    unexpected = [r for r in results if not isinstance(r, tuple) or r[0] == "unexpected_exception"]
    if unexpected:
        print(f"D-04: unexpected thread failures (at-threshold): {unexpected}", file=sys.stderr)
        return 1

    outcome_counts = Counter(r[0] for r in results)
    if outcome_counts.get("otp_locked", 0) != 1 or outcome_counts.get("otp_invalid", 0) != n_at - 1:
        print(
            f"D-04: at-threshold concurrent attempts gave unexpected outcomes: {dict(outcome_counts)} "
            f"(expected exactly 1 otp_locked and {n_at - 1} otp_invalid)",
            file=sys.stderr,
        )
        return 1
    locked_status = next(status for (code, status) in results if code == "otp_locked")
    if locked_status != 429:
        print(f"D-04: otp_locked result had status {locked_status}, expected 429", file=sys.stderr)
        return 1

    with app.app_context():
        u = db.session.get(User, user_id)
        if u.phone_verification_attempts != 0:
            print(
                f"D-04: at-threshold final attempts={u.phone_verification_attempts}, expected 0 (reset)",
                file=sys.stderr,
            )
            return 1
        if u.phone_verification_locked_until is None or u.phone_verification_locked_until <= utcnow():
            print("D-04: at-threshold lockout was not set to a future time", file=sys.stderr)
            return 1
        if u.phone_verification_code_hash is not None or u.phone_verification_expires_at is not None:
            print("D-04: at-threshold lockout did not clear the OTP code/expiry", file=sys.stderr)
            return 1
    print(
        f"D-04: at-threshold OK (exactly 1 otp_locked + {n_at - 1} otp_invalid, "
        "lockout/reset state matches existing semantics)",
        flush=True,
    )
    return 0


def _d04_analytics_concurrency_smoke(app) -> int:
    """
    D-04 / analytics: seed one Car with no ListingAnalytics row, then have
    20 concurrent PostgreSQL threads each independently call
    `bump_listing_metric(car, "views")`. Must end with exactly one
    ListingAnalytics row and views == 20 -- proving the
    INSERT ... ON CONFLICT DO NOTHING get-or-create fix closes the race
    without any thread leaking an IntegrityError.
    """
    import threading
    import uuid

    from kk.extensions import db
    from kk.listing_metrics import bump_listing_metric
    from kk.models import Car, ListingAnalytics, User

    suffix = uuid.uuid4().hex[:8]
    print(f"D-04: seeding analytics-concurrency smoke car (suffix={suffix})...", flush=True)

    with app.app_context():
        seller = User(
            username=f"d04_an_seller_{suffix}",
            phone_number=f"07563{suffix[:6]}",
            first_name="D04",
            last_name="Seller",
            is_active=True,
            is_verified=True,
            phone_verified=True,
            public_id=f"d04anseller{suffix}",
        )
        seller.set_password("Aa123456")
        db.session.add(seller)
        db.session.flush()
        car = Car(
            seller_id=seller.id,
            public_id=f"d04ancar{suffix}",
            brand="d04smoke",
            model="analytics",
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
        db.session.add(car)
        db.session.commit()
        car_id = car.id

        if ListingAnalytics.query.filter_by(car_id=car_id).first() is not None:
            print("D-04: freshly-seeded car unexpectedly already has a ListingAnalytics row", file=sys.stderr)
            return 1

    n = 20
    barrier = threading.Barrier(n)
    errors: list[BaseException | None] = [None] * n

    def _worker(slot: int) -> None:
        try:
            barrier.wait(timeout=_D04_THREAD_JOIN_TIMEOUT_S)
            with app.app_context():
                thread_car = db.session.get(Car, car_id)
                bump_listing_metric(thread_car, "views")
        except BaseException as exc:  # noqa: BLE001
            errors[slot] = exc

    threads = [threading.Thread(target=_worker, args=(i,)) for i in range(n)]
    for t in threads:
        t.start()
    for t in threads:
        t.join(timeout=_D04_THREAD_JOIN_TIMEOUT_S)

    failed = [(i, e) for i, e in enumerate(errors) if e is not None]
    if failed:
        for i, e in failed:
            print(f"D-04: analytics smoke thread {i} raised: {e!r}", file=sys.stderr)
        return 1

    with app.app_context():
        rows = ListingAnalytics.query.filter_by(car_id=car_id).all()
        if len(rows) != 1:
            print(
                f"D-04: expected exactly 1 ListingAnalytics row for car_id={car_id}, found {len(rows)}",
                file=sys.stderr,
            )
            return 1
        if rows[0].views != n:
            print(
                f"D-04: expected views == {n} after {n} concurrent bumps, got {rows[0].views}",
                file=sys.stderr,
            )
            return 1
    print(f"D-04: analytics get-or-create + increment OK (1 row, views == {n})", flush=True)
    return 0


def _d07_view_history_upsert_smoke(app) -> int:
    """
    D-07: seed one viewer + one car with no ``user_viewed_listings`` row,
    then have 20 concurrent PostgreSQL threads each independently call
    ``record_user_listing_view()`` for the exact same ``(user_id, car_id)``
    pair. Must end with exactly one row, no thread raising an
    ``IntegrityError`` (or anything else), and ``viewed_at`` populated --
    proving the ``INSERT ... ON CONFLICT (user_id, car_id) DO NOTHING``
    fix closes the TOCTOU race documented under D-07. Also asserts exactly
    one of the 20 threads observed ``is_first_view=True`` -- the contract
    the route layer depends on to know whether to bump the view counter.

    Deliberately separate from the SQLite functional tests in
    ``kk/tests/test_d07_view_history_upsert.py``: those prove the *logic*
    is correct (including by directly simulating the race window); this
    proves the *concurrency* guarantee actually holds under real
    PostgreSQL MVCC/row-locking, not SQLite. Mirrors the established D-04
    real-thread pattern (``_d04_analytics_concurrency_smoke``): each
    "concurrent request" is a real ``threading.Thread`` with its own Flask
    app context (its own scoped session/DB connection) synchronized on a
    ``threading.Barrier`` so all 20 calls hit the database at effectively
    the same instant.
    """
    import threading
    import uuid

    from sqlalchemy import text

    from kk.extensions import db
    from kk.models import Car, User, user_viewed_listings
    from kk.view_history import record_user_listing_view

    suffix = uuid.uuid4().hex[:8]
    print(f"D-07: seeding view-history-upsert smoke user/car (suffix={suffix})...", flush=True)

    try:
        with app.app_context():
            seller = User(
                username=f"d07_seller_{suffix}",
                phone_number=f"07564{suffix[:6]}",
                first_name="D07",
                last_name="Seller",
                is_active=True,
                is_verified=True,
                phone_verified=True,
                public_id=f"d07seller{suffix}",
            )
            seller.set_password("Aa123456")
            db.session.add(seller)
            db.session.flush()

            viewer = User(
                username=f"d07_viewer_{suffix}",
                phone_number=f"07565{suffix[:6]}",
                first_name="D07",
                last_name="Viewer",
                is_active=True,
                is_verified=True,
                phone_verified=True,
                public_id=f"d07viewer{suffix}",
            )
            viewer.set_password("Aa123456")
            db.session.add(viewer)
            db.session.flush()

            car = Car(
                seller_id=seller.id,
                public_id=f"d07car{suffix}",
                brand="d07smoke",
                model="viewhistory",
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
            db.session.add(car)
            db.session.commit()
            viewer_id = viewer.id
            car_id = car.id
            car_public_id = car.public_id

            existing = db.session.execute(
                user_viewed_listings.select().where(
                    user_viewed_listings.c.user_id == viewer_id,
                    user_viewed_listings.c.car_id == car_id,
                )
            ).first()
            if existing is not None:
                print("D-07: freshly-seeded pair unexpectedly already has a view-history row", file=sys.stderr)
                return 1

        n = 20
        barrier = threading.Barrier(n)
        errors: list[BaseException | None] = [None] * n
        first_view_results: list[bool | None] = [None] * n

        def _worker(slot: int) -> None:
            try:
                barrier.wait(timeout=_D04_THREAD_JOIN_TIMEOUT_S)
                with app.app_context():
                    thread_viewer = db.session.get(User, viewer_id)
                    _car, is_first = record_user_listing_view(thread_viewer, car_public_id)
                    first_view_results[slot] = is_first
            except BaseException as exc:  # noqa: BLE001
                errors[slot] = exc

        threads = [threading.Thread(target=_worker, args=(i,)) for i in range(n)]
        for t in threads:
            t.start()
        for t in threads:
            t.join(timeout=_D04_THREAD_JOIN_TIMEOUT_S)

        failed = [(i, e) for i, e in enumerate(errors) if e is not None]
        if failed:
            for i, e in failed:
                print(f"D-07: view-history smoke thread {i} raised: {e!r}", file=sys.stderr)
            return 1

        with app.app_context():
            rows = db.session.execute(
                user_viewed_listings.select().where(
                    user_viewed_listings.c.user_id == viewer_id,
                    user_viewed_listings.c.car_id == car_id,
                )
            ).fetchall()
            if len(rows) != 1:
                print(
                    f"D-07: expected exactly 1 user_viewed_listings row for "
                    f"(viewer_id={viewer_id}, car_id={car_id}), found {len(rows)}",
                    file=sys.stderr,
                )
                return 1
            if rows[0].viewed_at is None:
                print("D-07: user_viewed_listings.viewed_at is NULL after concurrent upsert", file=sys.stderr)
                return 1
            print(
                f"D-07: exactly 1 user_viewed_listings row after {n} concurrent calls, "
                f"viewed_at={rows[0].viewed_at} OK",
                flush=True,
            )

        true_count = sum(1 for v in first_view_results if v is True)
        false_count = sum(1 for v in first_view_results if v is False)
        if true_count != 1 or false_count != n - 1:
            print(
                f"D-07: expected exactly 1 is_first_view=True and {n - 1} False across "
                f"{n} concurrent callers, got {true_count} True / {false_count} False",
                file=sys.stderr,
            )
            return 1
        print(f"D-07: is_first_view contract OK (1 True, {n - 1} False across {n} concurrent callers)", flush=True)
        return 0
    finally:
        # Self-cleaning: remove every row this smoke seeded, regardless of
        # outcome, so re-running it against the same database is safe.
        with app.app_context():
            db.session.rollback()
            db.session.execute(
                text("DELETE FROM user_viewed_listings WHERE car_id IN "
                     "(SELECT id FROM car WHERE public_id = :pid)"),
                {"pid": f"d07car{suffix}"},
            )
            db.session.execute(text("DELETE FROM car WHERE public_id = :pid"), {"pid": f"d07car{suffix}"})
            db.session.execute(
                text("DELETE FROM \"user\" WHERE public_id IN (:v, :s)"),
                {"v": f"d07viewer{suffix}", "s": f"d07seller{suffix}"},
            )
            db.session.commit()


# D-06: FK/report-status indexes -- exact index names this migration must
# create. Deliberately excludes token_blacklist.expires_at (investigated,
# zero query usage anywhere in the codebase -- see PRODUCTION_AUDIT.md D-06
# remediation detail).
_D06_EXPECTED_INDEXES: tuple[tuple[str, str, tuple[str, ...]], ...] = (
    ("notification", "ix_notification_user_id", ("user_id",)),
    ("user_action", "ix_user_action_user_id", ("user_id",)),
    ("password_reset", "ix_password_reset_user_id", ("user_id",)),
    ("email_verification", "ix_email_verification_user_id", ("user_id",)),
    ("user_report", "ix_user_report_status", ("status",)),
)


def _d06_fk_report_status_index_smoke(app) -> int:
    """D-06: verify the five new indexes exist on real PostgreSQL.

    Simpler than the C-11/D-01/D-05 smokes above: this migration is pure
    index-only DDL with no data/column changes, so there is nothing to
    seed/round-trip -- the chain is already at head (``main()`` runs
    ``flask db upgrade`` before calling any smoke function), so this just
    inspects the real Postgres catalog and asserts each expected index
    exists with the correct column(s), and that the deliberately-excluded
    ``token_blacklist.expires_at`` was NOT given an index.
    """
    from sqlalchemy import inspect

    from kk.extensions import db

    with app.app_context():
        insp = inspect(db.engine)

        for table, name, cols in _D06_EXPECTED_INDEXES:
            indexes = {ix["name"]: ix for ix in insp.get_indexes(table)}
            if name not in indexes:
                print(f"D-06: expected index missing after migration: {name} on {table}", file=sys.stderr)
                return 1
            actual_cols = tuple(indexes[name]["column_names"])
            if actual_cols != cols:
                print(
                    f"D-06: {name} covers {actual_cols}, expected {cols}",
                    file=sys.stderr,
                )
                return 1
            print(f"D-06: {name} on {table}{list(cols)} OK", flush=True)

        token_blacklist_indexes = {ix["name"] for ix in insp.get_indexes("token_blacklist")}
        if "ix_token_blacklist_expires_at" in token_blacklist_indexes:
            print(
                "D-06: token_blacklist.expires_at was indexed but should NOT be "
                "(zero query usage -- see PRODUCTION_AUDIT.md D-06 remediation detail)",
                file=sys.stderr,
            )
            return 1
        if "ix_token_blacklist_jti" not in token_blacklist_indexes:
            print("D-06: pre-existing ix_token_blacklist_jti is missing (unrelated regression)", file=sys.stderr)
            return 1
        print("D-06: token_blacklist.expires_at correctly left unindexed; jti index untouched", flush=True)

    print("D-06: FK/report-status indexes OK", flush=True)
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

    d05_status = _d05_nullability_hardening_smoke(app)
    if d05_status != 0:
        return d05_status

    d04_primitive_status = _d04_atomic_increment_primitive_smoke(app)
    if d04_primitive_status != 0:
        return d04_primitive_status

    d04_otp_status = _d04_otp_lockout_concurrency_smoke(app)
    if d04_otp_status != 0:
        return d04_otp_status

    d04_analytics_status = _d04_analytics_concurrency_smoke(app)
    if d04_analytics_status != 0:
        return d04_analytics_status

    d06_status = _d06_fk_report_status_index_smoke(app)
    if d06_status != 0:
        return d06_status

    d07_status = _d07_view_history_upsert_smoke(app)
    if d07_status != 0:
        return d07_status

    print("migration smoke OK", flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
