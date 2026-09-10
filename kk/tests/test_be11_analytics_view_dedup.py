"""BE-11: decouple analytics view deduplication from recently-viewed tracking.

ROOT CAUSE (see PRODUCTION_AUDIT.md BE-11 and the BE-11 investigation):
``record_trusted_view()`` used to decide whether to increment
``ListingAnalytics.views`` using the ``is_first_view`` result of
``record_user_listing_view()`` -- the exact same shared
``user_viewed_listings`` upsert independently consumed by the detail-page
GET's best-effort ``Car.views_count`` bump
(``_increment_views_best_effort()``, ``kk/routes/cars.py``). Because both
call sites raced for the same per-(user, car) flag, at most one of the two
counters ever incremented for a single real, authenticated, non-seller
view -- never both -- and which one depended on undefined request-arrival
order.

THE FIX: a brand-new, dedicated, DB-backed table (``ListingViewClaim``,
``kk/models.py``) and helper (``claim_listing_view_once()``,
``kk/listing_metrics.py``) gate ``ListingAnalytics.views`` independently of
``user_viewed_listings`` / ``record_user_listing_view()``. The database's
own ``UNIQUE(user_id, car_id)`` constraint -- not a Python-side check -- is
the concurrency primitive, exactly like the existing D-04/D-07 upserts.

``record_user_listing_view()`` itself, ``Car.views_count``,
``claim_unique_engagement()``, and ``record_call_or_share()`` (calls/shares)
are all unmodified by this fix; this test file proves that too.

These are single-threaded-by-default, SQLite-backed HTTP/unit tests (one
dedicated real-thread SQLite concurrency test is included for extra
confidence, per the established D-04/D-07 testing philosophy -- see those
modules' docstrings). The genuine real-concurrency proof against
PostgreSQL lives in ``scripts/ci_migration_smoke.py``
(``_be11_listing_view_claim_smoke``).
"""

from __future__ import annotations

import os
import sys
import tempfile
import threading
import uuid
from pathlib import Path

import pytest

_REPO_ROOT = Path(__file__).resolve().parents[2]
if str(_REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(_REPO_ROOT))

_PASSWORD = "Aa123456!"


@pytest.fixture(scope="module")
def app_ctx():
    tmp = tempfile.TemporaryDirectory(prefix="carlist_be11_", ignore_cleanup_errors=True)
    os.environ["APP_ENV"] = "testing"
    os.environ["SMS_PROVIDER"] = "console"
    os.environ.pop("LISTING_REQUIRE_APPROVAL", None)
    # BE-11 req #7: prove the new claim mechanism has zero Redis dependency
    # by running this entire module's test suite with REDIS_URL unset --
    # mirrors kk/tests/test_token_revocation.py's "force the DB-fallback
    # blocklist path" convention for the same class of requirement.
    os.environ.pop("REDIS_URL", None)
    os.environ["DB_PATH"] = os.path.join(tmp.name, "be11.db")

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
            first_name="Be11",
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
        return car.id, car.public_id


def _login(client, username: str, password: str = _PASSWORD) -> str:
    r = client.post(
        "/api/auth/login", json={"username": username, "password": password}
    )
    assert r.status_code == 200, r.data
    return r.get_json()["access_token"]


def _auth(token: str) -> dict:
    return {"Authorization": f"Bearer {token}"}


def _views_count(app, db, car_id: int) -> int:
    from kk.models import Car

    with app.app_context():
        car = db.session.get(Car, car_id)
        return int(car.views_count or 0)


def _analytics_views(app, db, car_id: int) -> int:
    from kk.models import ListingAnalytics

    with app.app_context():
        a = ListingAnalytics.query.filter_by(car_id=car_id).first()
        return int(a.views) if a else 0


def _claim_row_count(app, db, user_id: int, car_id: int) -> int:
    from kk.models import ListingViewClaim

    with app.app_context():
        return ListingViewClaim.query.filter_by(user_id=user_id, car_id=car_id).count()


def _recently_viewed_row_count(app, db, user_id: int, car_id: int) -> int:
    from kk.models import user_viewed_listings

    with app.app_context():
        rows = db.session.execute(
            user_viewed_listings.select().where(
                user_viewed_listings.c.user_id == user_id,
                user_viewed_listings.c.car_id == car_id,
            )
        ).fetchall()
        return len(rows)


def _reset_counters(app, db, car_id: int) -> None:
    from kk.models import Car, ListingAnalytics

    with app.app_context():
        car = db.session.get(Car, car_id)
        car.views_count = 0
        a = ListingAnalytics.query.filter_by(car_id=car_id).first()
        if a:
            a.views = 0
        db.session.commit()


# --------------------------------------------------------------------------
# 1 & 2: first / repeat track/view
# --------------------------------------------------------------------------


class TestFirstAndRepeatTrackView:
    def test_first_track_view_counts_and_creates_claim_row(self, app_ctx):
        app, client, db = app_ctx
        seller_id = _make_user(app, db)
        viewer_id = _make_user(app, db)
        car_id, public_id = _make_car(app, db, seller_id)
        token = _login(client, _username_of(app, db, viewer_id))

        r = client.post(
            "/api/analytics/track/view",
            json={"listing_id": public_id},
            headers=_auth(token),
        )
        assert r.status_code == 200, r.data
        body = r.get_json()
        assert body["success"] is True
        assert body["counted"] is True
        assert body["code"] == "counted"

        assert _analytics_views(app, db, car_id) == 1
        assert _claim_row_count(app, db, viewer_id, car_id) == 1

    def test_repeat_track_view_does_not_increment_or_duplicate_claim(self, app_ctx):
        app, client, db = app_ctx
        seller_id = _make_user(app, db)
        viewer_id = _make_user(app, db)
        car_id, public_id = _make_car(app, db, seller_id)
        token = _login(client, _username_of(app, db, viewer_id))

        r1 = client.post(
            "/api/analytics/track/view",
            json={"listing_id": public_id},
            headers=_auth(token),
        )
        assert r1.status_code == 200
        assert r1.get_json()["counted"] is True

        for _ in range(3):
            r2 = client.post(
                "/api/analytics/track/view",
                json={"listing_id": public_id},
                headers=_auth(token),
            )
            assert r2.status_code == 200, r2.data
            body2 = r2.get_json()
            assert body2["counted"] is False
            assert body2["code"] == "already_viewed"

        assert _analytics_views(app, db, car_id) == 1
        assert _claim_row_count(app, db, viewer_id, car_id) == 1


# --------------------------------------------------------------------------
# 3: seller viewing own listing
# --------------------------------------------------------------------------


class TestSellerOwnListing:
    def test_seller_view_own_listing_not_counted_no_claim_row(self, app_ctx):
        app, client, db = app_ctx
        seller_id = _make_user(app, db)
        car_id, public_id = _make_car(app, db, seller_id)
        token = _login(client, _username_of(app, db, seller_id))

        r = client.post(
            "/api/analytics/track/view",
            json={"listing_id": public_id},
            headers=_auth(token),
        )
        assert r.status_code == 200, r.data
        body = r.get_json()
        assert body["counted"] is False
        assert body["code"] == "own_listing"

        assert _analytics_views(app, db, car_id) == 0
        assert _claim_row_count(app, db, seller_id, car_id) == 0

    def test_seller_get_own_listing_still_bumps_views_count_unrelated_to_claim(self, app_ctx):
        """
        Scope guard: BE-11 must NOT change Car.views_count's existing
        "seller not excluded" behavior on the GET path.
        """
        app, client, db = app_ctx
        seller_id = _make_user(app, db)
        car_id, public_id = _make_car(app, db, seller_id)
        _reset_counters(app, db, car_id)
        token = _login(client, _username_of(app, db, seller_id))

        r = client.get(f"/api/cars/{public_id}", headers=_auth(token))
        assert r.status_code == 200, r.data

        assert _views_count(app, db, car_id) == 1
        assert _analytics_views(app, db, car_id) == 0
        assert _claim_row_count(app, db, seller_id, car_id) == 0


# --------------------------------------------------------------------------
# 4 & 5: ordering independence (the actual BE-11 regression)
# --------------------------------------------------------------------------


class TestOrderingIndependence:
    def test_get_detail_then_track_view_both_independent(self, app_ctx):
        """
        Sequence A from the task: GET detail (recently-viewed claim occurs)
        -> POST track/view -> analytics view increments exactly once.

        This is the exact sequence that FAILED under the pre-BE-11
        implementation (the GET's call into record_user_listing_view()
        consumed the shared flag that record_trusted_view() used to gate
        the analytics increment, so the follow-up track/view silently
        no-op'd with code=already_viewed and ListingAnalytics.views never
        moved off 0). See test_old_behavior_negative_regression below for
        the actual reproduction of that historical failure.
        """
        app, client, db = app_ctx
        seller_id = _make_user(app, db)
        viewer_id = _make_user(app, db)
        car_id, public_id = _make_car(app, db, seller_id)
        _reset_counters(app, db, car_id)
        token = _login(client, _username_of(app, db, viewer_id))

        r_get = client.get(f"/api/cars/{public_id}", headers=_auth(token))
        assert r_get.status_code == 200, r_get.data
        assert _views_count(app, db, car_id) == 1
        assert _analytics_views(app, db, car_id) == 0
        assert _recently_viewed_row_count(app, db, viewer_id, car_id) == 1
        assert _claim_row_count(app, db, viewer_id, car_id) == 0

        r_track = client.post(
            "/api/analytics/track/view",
            json={"listing_id": public_id},
            headers=_auth(token),
        )
        assert r_track.status_code == 200, r_track.data
        body = r_track.get_json()
        assert body["counted"] is True, (
            "BE-11 regression: track/view after GET detail must still count "
            f"-- got {body}"
        )
        assert body["code"] == "counted"

        assert _views_count(app, db, car_id) == 1, "GET-side counter must be unaffected"
        assert _analytics_views(app, db, car_id) == 1
        assert _claim_row_count(app, db, viewer_id, car_id) == 1

    def test_track_view_then_get_detail_analytics_stays_once(self, app_ctx):
        """
        Sequence B from the task: POST track/view (analytics claim occurs)
        -> GET detail -> analytics view remains exactly once, and
        recently-viewed tracking (independent mechanism) still works.
        """
        app, client, db = app_ctx
        seller_id = _make_user(app, db)
        viewer_id = _make_user(app, db)
        car_id, public_id = _make_car(app, db, seller_id)
        _reset_counters(app, db, car_id)
        token = _login(client, _username_of(app, db, viewer_id))

        r_track = client.post(
            "/api/analytics/track/view",
            json={"listing_id": public_id},
            headers=_auth(token),
        )
        assert r_track.status_code == 200, r_track.data
        assert r_track.get_json()["counted"] is True
        assert _analytics_views(app, db, car_id) == 1
        assert _views_count(app, db, car_id) == 0
        # record_trusted_view() calls record_user_listing_view() itself, so
        # recently-viewed tracking already happened here too.
        assert _recently_viewed_row_count(app, db, viewer_id, car_id) == 1

        r_get = client.get(f"/api/cars/{public_id}", headers=_auth(token))
        assert r_get.status_code == 200, r_get.data

        assert _analytics_views(app, db, car_id) == 1, "must not double-count"
        assert _claim_row_count(app, db, viewer_id, car_id) == 1
        # The GET's own dedup (user_viewed_listings) was already consumed
        # by record_trusted_view()'s call above -- views_count must NOT
        # increment a second time for the same user.
        assert _views_count(app, db, car_id) == 0
        assert _recently_viewed_row_count(app, db, viewer_id, car_id) == 1


# --------------------------------------------------------------------------
# 6: repeated GET/track combinations
# --------------------------------------------------------------------------


class TestRepeatedCombinations:
    def test_interleaved_get_and_track_calls_stay_correct(self, app_ctx):
        app, client, db = app_ctx
        seller_id = _make_user(app, db)
        viewer_id = _make_user(app, db)
        car_id, public_id = _make_car(app, db, seller_id)
        _reset_counters(app, db, car_id)
        token = _login(client, _username_of(app, db, viewer_id))
        hdr = _auth(token)

        # GET, track, GET, track, GET -- analytics must land at exactly 1,
        # views_count must land at exactly 1 (per-user dedup, not per-hit),
        # recently-viewed must have exactly one row for this pair.
        client.get(f"/api/cars/{public_id}", headers=hdr)
        client.post("/api/analytics/track/view", json={"listing_id": public_id}, headers=hdr)
        client.get(f"/api/cars/{public_id}", headers=hdr)
        client.post("/api/analytics/track/view", json={"listing_id": public_id}, headers=hdr)
        client.get(f"/api/cars/{public_id}", headers=hdr)

        assert _views_count(app, db, car_id) == 1
        assert _analytics_views(app, db, car_id) == 1
        assert _claim_row_count(app, db, viewer_id, car_id) == 1
        assert _recently_viewed_row_count(app, db, viewer_id, car_id) == 1

    def test_different_users_each_get_their_own_independent_claim(self, app_ctx):
        app, client, db = app_ctx
        seller_id = _make_user(app, db)
        car_id, public_id = _make_car(app, db, seller_id)
        _reset_counters(app, db, car_id)

        viewers = [_make_user(app, db) for _ in range(3)]
        for vid in viewers:
            token = _login(client, _username_of(app, db, vid))
            r = client.post(
                "/api/analytics/track/view",
                json={"listing_id": public_id},
                headers=_auth(token),
            )
            assert r.get_json()["counted"] is True

        assert _analytics_views(app, db, car_id) == 3
        for vid in viewers:
            assert _claim_row_count(app, db, vid, car_id) == 1


# --------------------------------------------------------------------------
# 7: Redis absent
# --------------------------------------------------------------------------


class TestRedisAbsent:
    def test_claim_works_with_redis_url_unset(self, app_ctx, monkeypatch):
        """
        The whole module runs with REDIS_URL unset (see app_ctx), but make
        the absence explicit and local to this test too, and additionally
        force kk.listing_metrics._redis_client() (used only by
        claim_unique_engagement, calls/shares) to return None, proving
        claim_listing_view_once()/record_trusted_view() have zero
        dependency on Redis being reachable -- unlike claim_unique_engagement,
        there is no Redis code path in claim_listing_view_once() at all.
        """
        app, client, db = app_ctx
        monkeypatch.delenv("REDIS_URL", raising=False)

        import kk.listing_metrics as listing_metrics_mod

        monkeypatch.setattr(listing_metrics_mod, "_redis_client", lambda: None)

        seller_id = _make_user(app, db)
        viewer_id = _make_user(app, db)
        car_id, public_id = _make_car(app, db, seller_id)
        token = _login(client, _username_of(app, db, viewer_id))

        r1 = client.post(
            "/api/analytics/track/view",
            json={"listing_id": public_id},
            headers=_auth(token),
        )
        assert r1.status_code == 200
        assert r1.get_json()["counted"] is True

        r2 = client.post(
            "/api/analytics/track/view",
            json={"listing_id": public_id},
            headers=_auth(token),
        )
        assert r2.status_code == 200
        assert r2.get_json()["counted"] is False

        assert _analytics_views(app, db, car_id) == 1
        assert _claim_row_count(app, db, viewer_id, car_id) == 1


# --------------------------------------------------------------------------
# 8: concurrent duplicate claims
# --------------------------------------------------------------------------


class TestConcurrentClaims:
    def test_deterministic_race_window_simulation(self, app_ctx):
        """
        D-04/D-07-style deterministic simulation of the race window,
        single-threaded: pre-insert the claim row exactly as a "winning"
        concurrent caller would have left it, then call
        claim_listing_view_once() as the "losing" caller. Must return
        False cleanly (no IntegrityError leaking out), and must leave
        exactly one row behind.
        """
        app, client, db = app_ctx
        from kk.listing_metrics import claim_listing_view_once
        from kk.models import ListingViewClaim

        seller_id = _make_user(app, db)
        viewer_id = _make_user(app, db)
        car_id, _public_id = _make_car(app, db, seller_id)

        with app.app_context():
            won = claim_listing_view_once(viewer_id, car_id)
            assert won is True

            # Simulate a second, concurrent caller arriving just after the
            # first one committed.
            lost = claim_listing_view_once(viewer_id, car_id)
            assert lost is False

            rows = ListingViewClaim.query.filter_by(
                user_id=viewer_id, car_id=car_id
            ).all()
            assert len(rows) == 1

    def test_real_thread_concurrent_claims_exactly_one_winner(self, app_ctx):
        """
        Real ``threading.Barrier``-synchronized concurrent callers against
        the same SQLite-backed app, each with its own app context. Per the
        established D-04/D-07 testing philosophy, this proves the logic
        holds even under genuine thread interleaving on SQLite; the
        stronger real-PostgreSQL multi-process proof lives in
        ``scripts/ci_migration_smoke.py::_be11_listing_view_claim_smoke``.
        """
        app, client, db = app_ctx
        from kk.listing_metrics import claim_listing_view_once
        from kk.models import ListingViewClaim

        seller_id = _make_user(app, db)
        viewer_id = _make_user(app, db)
        car_id, _public_id = _make_car(app, db, seller_id)

        n_workers = 12
        barrier = threading.Barrier(n_workers)
        results: list[bool | None] = [None] * n_workers
        errors: list[BaseException | None] = [None] * n_workers

        def _worker(slot: int) -> None:
            try:
                barrier.wait(timeout=10)
                with app.app_context():
                    results[slot] = claim_listing_view_once(viewer_id, car_id)
            except BaseException as exc:  # noqa: BLE001
                errors[slot] = exc

        threads = [threading.Thread(target=_worker, args=(i,)) for i in range(n_workers)]
        for t in threads:
            t.start()
        for t in threads:
            t.join(timeout=15)

        failed = [(i, e) for i, e in enumerate(errors) if e is not None]
        assert not failed, f"threads raised: {failed}"

        assert sum(1 for r in results if r is True) == 1, results
        assert sum(1 for r in results if r is False) == n_workers - 1, results

        with app.app_context():
            rows = ListingViewClaim.query.filter_by(
                user_id=viewer_id, car_id=car_id
            ).all()
            assert len(rows) == 1


# --------------------------------------------------------------------------
# 9: migration -- fresh upgrade / downgrade / upgrade again / constraint
# --------------------------------------------------------------------------


class TestMigrationChain:
    def test_fresh_upgrade_downgrade_reupgrade_and_unique_constraint(self):
        import sqlalchemy as sa
        from flask_migrate import downgrade, upgrade

        tmp = tempfile.TemporaryDirectory(prefix="carlist_be11_mig_", ignore_cleanup_errors=True)
        prev_env = {
            k: os.environ.get(k) for k in ("APP_ENV", "SMS_PROVIDER", "DB_PATH", "REDIS_URL")
        }
        try:
            os.environ["APP_ENV"] = "testing"
            os.environ["SMS_PROVIDER"] = "console"
            os.environ.pop("LISTING_REQUIRE_APPROVAL", None)
            os.environ.pop("REDIS_URL", None)
            os.environ["DB_PATH"] = os.path.join(tmp.name, "be11_mig.db")

            from kk.app_factory import create_app

            mig_app, *_ = create_app()
            from kk.models import db as mig_db

            with mig_app.app_context():
                upgrade()

                insp = sa.inspect(mig_db.engine)
                assert insp.has_table("listing_view_claim")
                cols = {c["name"] for c in insp.get_columns("listing_view_claim")}
                assert cols == {"id", "user_id", "car_id", "claimed_at"}

                uniques = insp.get_unique_constraints("listing_view_claim")
                unique_col_sets = [set(u["column_names"]) for u in uniques]
                assert {"user_id", "car_id"} in unique_col_sets

                fks = insp.get_foreign_keys("listing_view_claim")
                assert len(fks) == 2
                for fk in fks:
                    assert fk["options"].get("ondelete", "").upper() == "CASCADE"

                downgrade(revision="7ae553c40b45")
                insp = sa.inspect(mig_db.engine)
                assert not insp.has_table("listing_view_claim")

                upgrade()
                insp = sa.inspect(mig_db.engine)
                assert insp.has_table("listing_view_claim")

                # DB-level unique constraint actually enforced.
                from kk.models import Car, ListingViewClaim, User
                from kk.time_utils import utcnow

                u = User(
                    username=f"u_{uuid.uuid4().hex[:10]}",
                    first_name="Mig",
                    last_name="Test",
                    is_active=True,
                    is_verified=True,
                    phone_verified=True,
                    public_id=f"pub-{uuid.uuid4().hex[:12]}",
                    phone_number=_phone(),
                )
                u.set_password(_PASSWORD)
                mig_db.session.add(u)
                mig_db.session.commit()

                c = Car(
                    seller_id=u.id,
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
                )
                mig_db.session.add(c)
                mig_db.session.commit()

                mig_db.session.add(
                    ListingViewClaim(user_id=u.id, car_id=c.id, claimed_at=utcnow())
                )
                mig_db.session.commit()

                mig_db.session.add(
                    ListingViewClaim(user_id=u.id, car_id=c.id, claimed_at=utcnow())
                )
                with pytest.raises(Exception):
                    mig_db.session.commit()
                mig_db.session.rollback()

            with mig_app.app_context():
                mig_db.session.remove()
                mig_db.engine.dispose()
        finally:
            for k, v in prev_env.items():
                if v is None:
                    os.environ.pop(k, None)
                else:
                    os.environ[k] = v
            tmp.cleanup()


# --------------------------------------------------------------------------
# 10: existing calls/shares unchanged
# --------------------------------------------------------------------------


class TestCallsSharesUnchanged:
    def test_call_dedup_unchanged(self, app_ctx):
        app, client, db = app_ctx
        from kk.listing_metrics import clear_engagement_claims_for_tests

        clear_engagement_claims_for_tests()

        seller_id = _make_user(app, db)
        viewer_id = _make_user(app, db)
        car_id, public_id = _make_car(app, db, seller_id)
        token = _login(client, _username_of(app, db, viewer_id))

        r1 = client.post(
            "/api/analytics/track/call",
            json={"listing_id": public_id},
            headers=_auth(token),
        )
        assert r1.status_code == 200, r1.data
        assert r1.get_json()["counted"] is True

        r2 = client.post(
            "/api/analytics/track/call",
            json={"listing_id": public_id},
            headers=_auth(token),
        )
        assert r2.status_code == 200
        assert r2.get_json()["counted"] is False
        assert r2.get_json()["code"] == "deduped"

    def test_share_dedup_and_seller_exclusion_unchanged(self, app_ctx):
        app, client, db = app_ctx
        from kk.listing_metrics import clear_engagement_claims_for_tests

        clear_engagement_claims_for_tests()

        seller_id = _make_user(app, db)
        car_id, public_id = _make_car(app, db, seller_id)
        token = _login(client, _username_of(app, db, seller_id))

        r = client.post(
            "/api/analytics/track/share",
            json={"listing_id": public_id},
            headers=_auth(token),
        )
        assert r.status_code == 200
        body = r.get_json()
        assert body["counted"] is False
        assert body["code"] == "own_listing"

    def test_claim_unique_engagement_function_itself_untouched_by_views(self, app_ctx):
        """
        Scope guard: ``action="views"`` must never reach
        ``claim_unique_engagement()`` -- it is used by calls/shares only.
        """
        app, client, db = app_ctx
        import kk.listing_metrics as listing_metrics_mod

        calls_seen: list[str] = []
        original = listing_metrics_mod.claim_unique_engagement

        def _spy(*, user_id, car_id, action, ttl_s=None):
            calls_seen.append(action)
            if ttl_s is None:
                return original(user_id=user_id, car_id=car_id, action=action)
            return original(user_id=user_id, car_id=car_id, action=action, ttl_s=ttl_s)

        listing_metrics_mod.claim_unique_engagement = _spy
        try:
            seller_id = _make_user(app, db)
            viewer_id = _make_user(app, db)
            car_id, public_id = _make_car(app, db, seller_id)
            token = _login(client, _username_of(app, db, viewer_id))

            r = client.post(
                "/api/analytics/track/view",
                json={"listing_id": public_id},
                headers=_auth(token),
            )
            assert r.status_code == 200
            assert r.get_json()["counted"] is True
        finally:
            listing_metrics_mod.claim_unique_engagement = original

        assert "views" not in calls_seen
        assert calls_seen == []


# --------------------------------------------------------------------------
# Verify old/new semantics explicitly: separate tables, no cross-blocking
# --------------------------------------------------------------------------


class TestClaimTablesAreSeparate:
    def test_row_in_one_table_does_not_prevent_insertion_into_the_other(self, app_ctx):
        app, client, db = app_ctx
        from kk.listing_metrics import claim_listing_view_once
        from kk.models import ListingViewClaim, user_viewed_listings
        from kk.view_history import record_user_listing_view
        from kk.models import User

        seller_id = _make_user(app, db)
        viewer_id = _make_user(app, db)
        car_id, _public_id = _make_car(app, db, seller_id)

        with app.app_context():
            # Claim the analytics gate WITHOUT ever calling
            # record_user_listing_view() -- proves the analytics claim
            # table has no dependency on the recently-viewed table.
            claimed = claim_listing_view_once(viewer_id, car_id)
            assert claimed is True

            rv_rows_before = db.session.execute(
                user_viewed_listings.select().where(
                    user_viewed_listings.c.user_id == viewer_id,
                    user_viewed_listings.c.car_id == car_id,
                )
            ).fetchall()
            assert len(rv_rows_before) == 0, (
                "claim_listing_view_once() must never write to "
                "user_viewed_listings"
            )

            # Now exercise record_user_listing_view() -- must succeed and
            # insert its own row despite the listing_view_claim row already
            # existing for this exact (user, car) pair.
            viewer = db.session.get(User, viewer_id)
            car, is_first = record_user_listing_view(viewer, str(car_id))
            db.session.commit()
            assert car is not None
            assert is_first is True, (
                "a pre-existing listing_view_claim row must NOT block "
                "record_user_listing_view()'s own, independent upsert"
            )

            rv_rows_after = db.session.execute(
                user_viewed_listings.select().where(
                    user_viewed_listings.c.user_id == viewer_id,
                    user_viewed_listings.c.car_id == car_id,
                )
            ).fetchall()
            assert len(rv_rows_after) == 1

            claim_rows = ListingViewClaim.query.filter_by(
                user_id=viewer_id, car_id=car_id
            ).all()
            assert len(claim_rows) == 1

    def test_recently_viewed_row_first_does_not_prevent_analytics_claim(self, app_ctx):
        app, client, db = app_ctx
        from kk.listing_metrics import claim_listing_view_once
        from kk.models import ListingViewClaim, User
        from kk.view_history import record_user_listing_view

        seller_id = _make_user(app, db)
        viewer_id = _make_user(app, db)
        car_id, _public_id = _make_car(app, db, seller_id)

        with app.app_context():
            viewer = db.session.get(User, viewer_id)
            _car, is_first = record_user_listing_view(viewer, str(car_id))
            db.session.commit()
            assert is_first is True

            claimed = claim_listing_view_once(viewer_id, car_id)
            assert claimed is True, (
                "a pre-existing user_viewed_listings row must NOT block "
                "claim_listing_view_once()'s own, independent claim"
            )

            claim_rows = ListingViewClaim.query.filter_by(
                user_id=viewer_id, car_id=car_id
            ).all()
            assert len(claim_rows) == 1


def _username_of(app, db, user_id: int) -> str:
    from kk.models import User

    with app.app_context():
        return db.session.get(User, user_id).username
