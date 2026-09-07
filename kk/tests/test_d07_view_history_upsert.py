"""D-07: proves the ``record_user_listing_view()`` upsert is race-safe.

Covers ``kk/view_history.py::record_user_listing_view()``.

Previously this function did SELECT -> branch -> UPDATE/INSERT. Two
concurrent requests for the same ``(user_id, car_id)`` could both observe
"not exists" and both attempt the INSERT branch; the composite primary key
``(user_id, car_id)`` made the losing side raise an uncaught
``IntegrityError``. The fix replaces the SELECT-then-branch with a single
``INSERT ... ON CONFLICT (user_id, car_id) DO NOTHING`` (reusing
``kk.listing_metrics._conflict_safe_insert``, the same D-04 dialect helper),
followed by a plain ``UPDATE`` to refresh ``viewed_at`` only when the
INSERT did not happen.

These are single-threaded, SQLite-backed tests: per the established D-04
testing philosophy (see ``kk/tests/test_d04_atomic_counters.py``'s module
docstring), they prove the *logic* is correct -- including by directly
simulating the race window (pre-creating the row exactly as a "winning"
concurrent request would have left it, then calling the function as the
"losing" request) -- not that it is race-free under real concurrency. The
real-concurrency proof against PostgreSQL lives in
``scripts/ci_migration_smoke.py`` (``_d07_view_history_upsert_smoke``).
"""

from __future__ import annotations

import os
import sys
import tempfile
import uuid
from datetime import datetime, timedelta
from pathlib import Path

import pytest

_REPO_ROOT = Path(__file__).resolve().parents[2]
if str(_REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(_REPO_ROOT))

_PASSWORD = "Aa123456!"


@pytest.fixture(scope="module")
def app_ctx():
    tmp = tempfile.TemporaryDirectory(prefix="carlist_d07_", ignore_cleanup_errors=True)
    os.environ["APP_ENV"] = "testing"
    os.environ["SMS_PROVIDER"] = "console"
    os.environ.pop("LISTING_REQUIRE_APPROVAL", None)
    os.environ["DB_PATH"] = os.path.join(tmp.name, "d07.db")

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
    extra.setdefault("username", f"u_{uuid.uuid4().hex[:10]}")
    with app.app_context():
        user = User(
            first_name="D07",
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


def _row(db, user_id: int, car_id: int):
    from kk.models import user_viewed_listings

    return db.session.execute(
        user_viewed_listings.select().where(
            user_viewed_listings.c.user_id == user_id,
            user_viewed_listings.c.car_id == car_id,
        )
    ).first()


def _row_count(db, user_id: int, car_id: int) -> int:
    from kk.models import user_viewed_listings

    rows = db.session.execute(
        user_viewed_listings.select().where(
            user_viewed_listings.c.user_id == user_id,
            user_viewed_listings.c.car_id == car_id,
        )
    ).fetchall()
    return len(rows)


class TestRecordUserListingViewUpsert:
    def test_fresh_pair_returns_first_view_true_and_creates_row(self, app_ctx):
        app, _client, db = app_ctx
        from kk.models import User
        from kk.view_history import record_user_listing_view

        seller_id = _make_user(app, db)
        viewer_id = _make_user(app, db)
        car_id = _make_car(app, db, seller_id)

        with app.app_context():
            viewer = db.session.get(User, viewer_id)
            car, is_first = record_user_listing_view(viewer, str(car_id))
            db.session.commit()

            assert car is not None
            assert car.id == car_id
            assert is_first is True
            assert _row_count(db, viewer_id, car_id) == 1

    def test_existing_pair_returns_first_view_false(self, app_ctx):
        app, _client, db = app_ctx
        from kk.models import User
        from kk.view_history import record_user_listing_view

        seller_id = _make_user(app, db)
        viewer_id = _make_user(app, db)
        car_id = _make_car(app, db, seller_id)

        with app.app_context():
            viewer = db.session.get(User, viewer_id)
            _car1, is_first1 = record_user_listing_view(viewer, str(car_id))
            db.session.commit()
            assert is_first1 is True

            _car2, is_first2 = record_user_listing_view(viewer, str(car_id))
            db.session.commit()
            assert is_first2 is False

    def test_existing_pair_refreshes_viewed_at(self, app_ctx, monkeypatch):
        app, _client, db = app_ctx
        from kk.models import User
        import kk.view_history as view_history_mod

        seller_id = _make_user(app, db)
        viewer_id = _make_user(app, db)
        car_id = _make_car(app, db, seller_id)

        t1 = datetime(2026, 1, 1, 10, 0, 0)
        t2 = datetime(2026, 1, 2, 11, 30, 0)

        with app.app_context():
            viewer = db.session.get(User, viewer_id)

            monkeypatch.setattr(view_history_mod, "utcnow", lambda: t1)
            _car, is_first1 = view_history_mod.record_user_listing_view(
                viewer, str(car_id)
            )
            db.session.commit()
            assert is_first1 is True
            row1 = _row(db, viewer_id, car_id)
            assert row1.viewed_at == t1

            monkeypatch.setattr(view_history_mod, "utcnow", lambda: t2)
            _car, is_first2 = view_history_mod.record_user_listing_view(
                viewer, str(car_id)
            )
            db.session.commit()
            assert is_first2 is False
            row2 = _row(db, viewer_id, car_id)
            assert row2.viewed_at == t2
            assert row2.viewed_at != row1.viewed_at

    def test_exactly_one_row_after_repeated_calls(self, app_ctx):
        app, _client, db = app_ctx
        from kk.models import User
        from kk.view_history import record_user_listing_view

        seller_id = _make_user(app, db)
        viewer_id = _make_user(app, db)
        car_id = _make_car(app, db, seller_id)

        with app.app_context():
            viewer = db.session.get(User, viewer_id)
            for _ in range(5):
                record_user_listing_view(viewer, str(car_id))
                db.session.commit()

            assert _row_count(db, viewer_id, car_id) == 1

    def test_other_users_and_cars_are_not_modified(self, app_ctx):
        app, _client, db = app_ctx
        from kk.models import User
        from kk.view_history import record_user_listing_view

        seller_id = _make_user(app, db)
        viewer_id = _make_user(app, db)
        other_viewer_id = _make_user(app, db)
        car_id = _make_car(app, db, seller_id)
        other_car_id = _make_car(app, db, seller_id)

        with app.app_context():
            viewer = db.session.get(User, viewer_id)
            other_viewer = db.session.get(User, other_viewer_id)

            # Unrelated pairs pre-exist.
            record_user_listing_view(other_viewer, str(car_id))
            db.session.commit()
            record_user_listing_view(viewer, str(other_car_id))
            db.session.commit()

            other_row_before = _row(db, other_viewer_id, car_id)
            unrelated_row_before = _row(db, viewer_id, other_car_id)

            # The pair under test.
            record_user_listing_view(viewer, str(car_id))
            db.session.commit()

            assert _row(db, other_viewer_id, car_id) == other_row_before
            assert _row(db, viewer_id, other_car_id) == unrelated_row_before
            assert _row_count(db, viewer_id, car_id) == 1
            assert _row_count(db, other_viewer_id, car_id) == 1
            assert _row_count(db, viewer_id, other_car_id) == 1

    def test_simulated_race_pre_existing_row_does_not_raise(self, app_ctx):
        """
        Simulate the exact race the old code could lose: another
        concurrent request already inserted the (user_id, car_id) row
        (by writing it directly via Core, bypassing
        ``record_user_listing_view`` entirely -- exactly what a "winning"
        concurrent caller's own successful insert would have left behind)
        before this call ever runs. The call must not raise
        ``IntegrityError`` and must report ``is_first_view=False``, proving
        the conflict itself -- not a try/except around it -- is what makes
        this safe.
        """
        app, _client, db = app_ctx
        from kk.models import User, user_viewed_listings
        from kk.view_history import record_user_listing_view

        seller_id = _make_user(app, db)
        viewer_id = _make_user(app, db)
        car_id = _make_car(app, db, seller_id)

        pre_existing_viewed_at = datetime(2020, 1, 1, 0, 0, 0)

        with app.app_context():
            # Simulate the "winning" concurrent request's own insert,
            # completely bypassing record_user_listing_view().
            db.session.execute(
                user_viewed_listings.insert().values(
                    user_id=viewer_id,
                    car_id=car_id,
                    viewed_at=pre_existing_viewed_at,
                )
            )
            db.session.commit()

            viewer = db.session.get(User, viewer_id)
            car, is_first_view = record_user_listing_view(viewer, str(car_id))

            assert car is not None
            assert car.id == car_id
            assert is_first_view is False
            assert _row_count(db, viewer_id, car_id) == 1

    def test_simulated_race_refreshes_viewed_at_on_conflict(self, app_ctx):
        """Same simulated-race setup as above, but asserts viewed_at moved
        forward from the pre-existing (race-winner's) value to the value
        this call supplied -- proving the conflict path still performs the
        documented "refresh viewed_at on every view" side effect."""
        app, _client, db = app_ctx
        from kk.models import User, user_viewed_listings
        import kk.view_history as view_history_mod

        seller_id = _make_user(app, db)
        viewer_id = _make_user(app, db)
        car_id = _make_car(app, db, seller_id)

        pre_existing_viewed_at = datetime(2020, 1, 1, 0, 0, 0)

        with app.app_context():
            db.session.execute(
                user_viewed_listings.insert().values(
                    user_id=viewer_id,
                    car_id=car_id,
                    viewed_at=pre_existing_viewed_at,
                )
            )
            db.session.commit()

            viewer = db.session.get(User, viewer_id)
            _car, is_first_view = view_history_mod.record_user_listing_view(
                viewer, str(car_id)
            )
            db.session.commit()

            assert is_first_view is False
            row = _row(db, viewer_id, car_id)
            assert row.viewed_at != pre_existing_viewed_at
            assert row.viewed_at > pre_existing_viewed_at

    def test_uses_conflict_safe_insert_not_select_then_branch(self, app_ctx, monkeypatch):
        """
        Guard against silently reintroducing the old SELECT-then-branch
        (or an ``except IntegrityError`` shortcut) instead of the approved
        conflict-safe write: assert the shared D-04 dialect helper
        (``kk.listing_metrics._conflict_safe_insert``) is actually invoked
        by ``record_user_listing_view``.
        """
        app, _client, db = app_ctx
        from kk.models import User
        import kk.listing_metrics as listing_metrics_mod
        from kk.view_history import record_user_listing_view

        seller_id = _make_user(app, db)
        viewer_id = _make_user(app, db)
        car_id = _make_car(app, db, seller_id)

        calls: list[object] = []
        original = listing_metrics_mod._conflict_safe_insert

        def _spy(model):
            calls.append(model)
            return original(model)

        monkeypatch.setattr(listing_metrics_mod, "_conflict_safe_insert", _spy)

        with app.app_context():
            viewer = db.session.get(User, viewer_id)
            record_user_listing_view(viewer, str(car_id))
            db.session.commit()

        assert len(calls) == 1


def _login(client, username: str, password: str = _PASSWORD) -> str:
    r = client.post(
        "/api/auth/login", json={"username": username, "password": password}
    )
    assert r.status_code == 200, r.data
    return r.get_json()["access_token"]


def _auth(token: str) -> dict:
    return {"Authorization": f"Bearer {token}"}


class TestRecentlyViewedRoutes:
    """
    HTTP-level regression coverage for the two live callers of
    ``record_user_listing_view()``. Both previously could 500 under the
    exact double-call pattern the Flutter client actually performs (tap a
    listing card -> ``POST /api/user/recently-viewed``, then navigate to
    the details page -> ``POST /api/analytics/track/view``, both for the
    same listing in quick succession -- see the D-07 investigation for the
    traced call graph). Firing both calls back-to-back for the same
    listing here reproduces that pattern and must not 500 on either call.
    """

    def test_recently_viewed_route_returns_success(self, app_ctx):
        app, client, db = app_ctx
        username = f"d07_user_{uuid.uuid4().hex[:10]}"

        seller_id = _make_user(app, db)
        _make_user(app, db, username=username)
        car_id = _make_car(app, db, seller_id)

        with app.app_context():
            from kk.models import Car

            public_id = db.session.get(Car, car_id).public_id

        token = _login(client, username)

        resp = client.post(
            "/api/user/recently-viewed",
            json={"listing_id": public_id},
            headers=_auth(token),
        )
        assert resp.status_code == 200, resp.data
        body = resp.get_json()
        assert body["success"] is True
        assert body["car_id"] == public_id

    def test_analytics_track_view_route_returns_success(self, app_ctx):
        app, client, db = app_ctx
        username = f"d07_user_{uuid.uuid4().hex[:10]}"

        seller_id = _make_user(app, db)
        _make_user(app, db, username=username)
        car_id = _make_car(app, db, seller_id)

        with app.app_context():
            from kk.models import Car

            public_id = db.session.get(Car, car_id).public_id

        token = _login(client, username)

        resp = client.post(
            "/api/analytics/track/view",
            json={"listing_id": public_id},
            headers=_auth(token),
        )
        assert resp.status_code == 200, resp.data
        body = resp.get_json()
        assert body["success"] is True

    def test_both_routes_back_to_back_do_not_500(self, app_ctx):
        """
        Reproduces the actual Flutter double-call pattern for one listing
        view: ``recordView()`` fired from the card tap, immediately
        followed by ``AnalyticsService.trackView()`` (which itself calls
        ``recordView()`` again, then ``/analytics/track/view``) fired from
        the details page's ``initState()``. Three calls into
        ``record_user_listing_view()`` for the exact same
        ``(user_id, car_id)`` in a row, over real HTTP, through real Flask
        request/response cycles -- none may 500.
        """
        app, client, db = app_ctx
        username = f"d07_user_{uuid.uuid4().hex[:10]}"

        seller_id = _make_user(app, db)
        _make_user(app, db, username=username)
        car_id = _make_car(app, db, seller_id)

        with app.app_context():
            from kk.models import Car

            public_id = db.session.get(Car, car_id).public_id

        token = _login(client, username)

        r1 = client.post(
            "/api/user/recently-viewed",
            json={"listing_id": public_id},
            headers=_auth(token),
        )
        r2 = client.post(
            "/api/user/recently-viewed",
            json={"listing_id": public_id},
            headers=_auth(token),
        )
        r3 = client.post(
            "/api/analytics/track/view",
            json={"listing_id": public_id},
            headers=_auth(token),
        )

        assert r1.status_code == 200, r1.data
        assert r2.status_code == 200, r2.data
        assert r3.status_code == 200, r3.data

        with app.app_context():
            from kk.models import User

            viewer_id = User.query.filter_by(username=username).one().id
            assert _row_count(db, viewer_id, car_id) == 1


if __name__ == "__main__":
    pytest.main([__file__, "-v"])
