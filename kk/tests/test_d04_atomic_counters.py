"""D-04: atomic SQL counters.

SQLite-side functional coverage for:
- `kk.security.atomic_increment_attempts()` (OTP/verification attempt
  counters — replaces the previous Python read -> +1 -> assign race).
- `kk.listing_metrics.get_or_create_analytics()` /
  `_bulk_create_missing_analytics()` (ListingAnalytics get-or-create race —
  replaces the previous SELECT-then-INSERT race).
- `kk.listing_metrics.bump_listing_metric()` (unchanged atomic
  `SET metric = metric + 1`, regression-checked after the refactor).

These are single-threaded, SQLite-backed tests: they prove the *logic* is
correct, not that it is race-free under real concurrency. The concurrency
proof against real PostgreSQL lives in
``scripts/ci_migration_smoke.py`` (`_d04_atomic_increment_primitive_smoke`,
`_d04_otp_lockout_concurrency_smoke`, `_d04_analytics_concurrency_smoke`).
"""

from __future__ import annotations

import os
import sys
import tempfile
import uuid
from pathlib import Path
from types import SimpleNamespace

import pytest
from sqlalchemy.exc import IntegrityError

_REPO_ROOT = Path(__file__).resolve().parents[2]
if str(_REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(_REPO_ROOT))

_PASSWORD = "Aa123456!"


@pytest.fixture(scope="module")
def app_ctx():
    tmp = tempfile.TemporaryDirectory(prefix="carlist_d04_", ignore_cleanup_errors=True)
    os.environ["APP_ENV"] = "testing"
    os.environ["SMS_PROVIDER"] = "console"
    os.environ.pop("LISTING_REQUIRE_APPROVAL", None)
    os.environ["DB_PATH"] = os.path.join(tmp.name, "d04.db")

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


def _make_user(app, db, **extra):
    from kk.models import User

    extra.setdefault("phone_number", _phone())
    with app.app_context():
        user = User(
            username=f"u_{uuid.uuid4().hex[:10]}",
            first_name="D04",
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
        return car.id


# --- A. atomic_increment_attempts() ----------------------------------------


class TestAtomicIncrementAttempts:
    def test_normal_increment(self, app_ctx):
        """Single call on a zeroed counter returns 1 and persists 1."""
        app, _client, db = app_ctx
        from kk.models import User
        from kk.security import atomic_increment_attempts

        uid = _make_user(app, db)
        with app.app_context():
            user = db.session.get(User, uid)
            result = atomic_increment_attempts(user, "phone_verification_attempts")
            db.session.commit()
            assert result == 1
            assert db.session.get(User, uid).phone_verification_attempts == 1

    def test_null_counter_is_treated_as_zero(self, app_ctx):
        """
        `dealer_email_verification_attempts` / `email_change_attempts` have
        no column default (nullable, starts as NULL for a freshly-created
        user). The atomic UPDATE's COALESCE(column, 0) + 1 must handle this
        the same way the old `int(getattr(user, field, 0) or 0) + 1` did,
        not propagate NULL or raise.
        """
        app, _client, db = app_ctx
        from kk.models import User
        from kk.security import atomic_increment_attempts

        uid = _make_user(app, db)
        with app.app_context():
            user = db.session.get(User, uid)
            assert user.dealer_email_verification_attempts is None
            result = atomic_increment_attempts(
                user, "dealer_email_verification_attempts"
            )
            db.session.commit()
            assert result == 1
            assert (
                db.session.get(User, uid).dealer_email_verification_attempts == 1
            )

    def test_sequential_calls_are_monotonic(self, app_ctx):
        """Non-concurrent regression parity with the old Python +1 behavior."""
        app, _client, db = app_ctx
        from kk.models import User
        from kk.security import atomic_increment_attempts

        uid = _make_user(app, db)
        seen = []
        with app.app_context():
            for _ in range(5):
                user = db.session.get(User, uid)
                seen.append(
                    atomic_increment_attempts(user, "phone_verification_attempts")
                )
                db.session.commit()
        assert seen == [1, 2, 3, 4, 5]

    def test_email_change_attempts_field_also_supported(self, app_ctx):
        app, _client, db = app_ctx
        from kk.models import User
        from kk.security import atomic_increment_attempts

        uid = _make_user(app, db)
        with app.app_context():
            user = db.session.get(User, uid)
            result = atomic_increment_attempts(user, "email_change_attempts")
            db.session.commit()
            assert result == 1
            assert db.session.get(User, uid).email_change_attempts == 1

    def test_rejects_field_names_outside_the_allow_list(self, app_ctx):
        """
        D-04 explicitly requires this helper cannot become a generic
        "UPDATE any column" primitive -- only the three known
        attempt-counter fields are accepted.
        """
        app, _client, db = app_ctx
        from kk.models import User
        from kk.security import atomic_increment_attempts

        uid = _make_user(app, db)
        with app.app_context():
            user = db.session.get(User, uid)
            for bad_field in ("is_admin", "password_hash", "views_count", "id"):
                with pytest.raises(ValueError):
                    atomic_increment_attempts(user, bad_field)


# --- B. OTP lockout threshold behavior (regression, real business logic) ---


class TestOtpLockoutThresholdUnchanged:
    """
    `_consume_phone_otp()` itself already has full-stack coverage in
    `test_signup_otp_required.py` (thresholds, lockout minutes, response
    codes/messages, resend/expiry interplay) via the real
    `/api/auth/signup` route. That suite is re-run as part of D-04
    verification rather than duplicated here; this class only re-confirms
    that swapping in `atomic_increment_attempts()` didn't change the
    single-threaded threshold/lockout outcome for the helper directly.
    """

    def test_wrong_code_below_threshold_does_not_lock(self, app_ctx):
        app, _client, db = app_ctx
        from kk.models import User
        from kk.routes.auth import (
            _OTP_MAX_ATTEMPTS,
            OtpError,
            _consume_phone_otp,
            _hash_phone_verification_code,
        )
        from kk.time_utils import utcnow
        from datetime import timedelta

        phone = _phone()
        uid = _make_user(app, db, phone_number=phone)
        with app.app_context():
            user = db.session.get(User, uid)
            user.phone_verification_code_hash = _hash_phone_verification_code(
                phone, "123456"
            )
            user.phone_verification_expires_at = utcnow() + timedelta(minutes=10)
            db.session.commit()

            for attempt in range(1, _OTP_MAX_ATTEMPTS):
                with pytest.raises(OtpError) as exc_info:
                    _consume_phone_otp(user, phone, "000000")
                assert exc_info.value.code == "otp_invalid"
                assert exc_info.value.status == 400
                assert (
                    db.session.get(User, uid).phone_verification_attempts
                    == attempt
                )

            user = db.session.get(User, uid)
            assert user.phone_verification_locked_until is None

    def test_wrong_code_at_threshold_locks_with_unchanged_semantics(self, app_ctx):
        app, _client, db = app_ctx
        from kk.models import User
        from kk.routes.auth import (
            _OTP_MAX_ATTEMPTS,
            OtpError,
            _consume_phone_otp,
            _hash_phone_verification_code,
        )
        from kk.time_utils import utcnow
        from datetime import timedelta

        phone = _phone()
        uid = _make_user(app, db, phone_number=phone)
        with app.app_context():
            user = db.session.get(User, uid)
            user.phone_verification_code_hash = _hash_phone_verification_code(
                phone, "123456"
            )
            user.phone_verification_expires_at = utcnow() + timedelta(minutes=10)
            db.session.commit()

            for _ in range(_OTP_MAX_ATTEMPTS - 1):
                with pytest.raises(OtpError):
                    _consume_phone_otp(user, phone, "000000")

            with pytest.raises(OtpError) as exc_info:
                _consume_phone_otp(user, phone, "000000")
            assert exc_info.value.code == "otp_locked"
            assert exc_info.value.status == 429

            user = db.session.get(User, uid)
            assert user.phone_verification_attempts == 0
            assert user.phone_verification_locked_until is not None
            assert user.phone_verification_locked_until > utcnow()
            assert user.phone_verification_code_hash is None
            assert user.phone_verification_expires_at is None


# --- C. get_or_create_analytics() / _bulk_create_missing_analytics() -------


class TestGetOrCreateAnalytics:
    def test_creates_row_when_missing(self, app_ctx):
        app, _client, db = app_ctx
        from kk.models import Car, ListingAnalytics
        from kk.listing_metrics import get_or_create_analytics

        seller_id = _make_user(app, db)
        car_id = _make_car(app, db, seller_id)
        with app.app_context():
            assert ListingAnalytics.query.filter_by(car_id=car_id).first() is None
            car = db.session.get(Car, car_id)
            row, created = get_or_create_analytics(car)
            db.session.commit()
            assert created is True
            assert row.car_id == car_id
            assert row.views == 0
            assert (
                ListingAnalytics.query.filter_by(car_id=car_id).count() == 1
            )

    def test_returns_existing_row_without_duplicate(self, app_ctx):
        app, _client, db = app_ctx
        from kk.models import Car, ListingAnalytics
        from kk.listing_metrics import get_or_create_analytics

        seller_id = _make_user(app, db)
        car_id = _make_car(app, db, seller_id)
        with app.app_context():
            existing = ListingAnalytics(car_id=car_id, views=7)
            db.session.add(existing)
            db.session.commit()

            car = db.session.get(Car, car_id)
            row, created = get_or_create_analytics(car)
            assert created is False
            assert row.id == existing.id
            assert row.views == 7
            assert (
                ListingAnalytics.query.filter_by(car_id=car_id).count() == 1
            )

    def test_repeated_calls_are_idempotent(self, app_ctx):
        app, _client, db = app_ctx
        from kk.models import Car, ListingAnalytics
        from kk.listing_metrics import get_or_create_analytics

        seller_id = _make_user(app, db)
        car_id = _make_car(app, db, seller_id)
        with app.app_context():
            car = db.session.get(Car, car_id)
            _row1, created1 = get_or_create_analytics(car)
            db.session.commit()
            _row2, created2 = get_or_create_analytics(car)
            db.session.commit()
            _row3, created3 = get_or_create_analytics(car)
            db.session.commit()

            assert (created1, created2, created3) == (True, False, False)
            assert (
                ListingAnalytics.query.filter_by(car_id=car_id).count() == 1
            )

    def test_does_not_swallow_unrelated_database_errors(self, app_ctx):
        """
        A foreign-key violation (nonexistent car_id) is a genuinely
        different failure than the car_id-uniqueness race the helper is
        designed to resolve silently. It must propagate, not be caught.
        """
        app, _client, db = app_ctx
        from kk.listing_metrics import get_or_create_analytics

        with app.app_context():
            fake_car = SimpleNamespace(id=999_999_999)
            with pytest.raises(IntegrityError):
                get_or_create_analytics(fake_car)
            db.session.rollback()

    def test_bulk_create_missing_analytics_creates_all_and_is_idempotent(
        self, app_ctx
    ):
        app, _client, db = app_ctx
        from kk.models import ListingAnalytics
        from kk.listing_metrics import _bulk_create_missing_analytics

        seller_id = _make_user(app, db)
        car_ids = [_make_car(app, db, seller_id) for _ in range(3)]
        with app.app_context():
            _bulk_create_missing_analytics(car_ids)
            db.session.commit()
            rows = ListingAnalytics.query.filter(
                ListingAnalytics.car_id.in_(car_ids)
            ).all()
            assert {r.car_id for r in rows} == set(car_ids)

            # Idempotent: calling again for the same (now-existing) ids must
            # not raise and must not create duplicates.
            _bulk_create_missing_analytics(car_ids)
            db.session.commit()
            assert (
                ListingAnalytics.query.filter(
                    ListingAnalytics.car_id.in_(car_ids)
                ).count()
                == 3
            )

    def test_bulk_create_missing_analytics_noop_for_empty_list(self, app_ctx):
        app, _client, db = app_ctx
        from kk.listing_metrics import _bulk_create_missing_analytics

        with app.app_context():
            _bulk_create_missing_analytics([])  # must not raise / must not query


# --- D. bump_listing_metric() regression ------------------------------------


class TestBumpListingMetricRegression:
    def test_bump_listing_metric_still_atomic_after_refactor(self, app_ctx):
        """
        Sequential (non-concurrent) regression: repeated calls for a car
        with no pre-existing row must still end up with exactly one
        ListingAnalytics row and an exact final count.
        """
        app, _client, db = app_ctx
        from kk.models import Car, ListingAnalytics
        from kk.listing_metrics import bump_listing_metric

        seller_id = _make_user(app, db)
        car_id = _make_car(app, db, seller_id)
        with app.app_context():
            for _ in range(5):
                car = db.session.get(Car, car_id)
                bump_listing_metric(car, "views")

            rows = ListingAnalytics.query.filter_by(car_id=car_id).all()
            assert len(rows) == 1
            assert rows[0].views == 5

    def test_bump_listing_metric_rejects_unknown_field(self, app_ctx):
        app, _client, db = app_ctx
        from kk.models import Car
        from kk.listing_metrics import bump_listing_metric

        seller_id = _make_user(app, db)
        car_id = _make_car(app, db, seller_id)
        with app.app_context():
            car = db.session.get(Car, car_id)
            with pytest.raises(ValueError):
                bump_listing_metric(car, "not_a_real_metric")
