"""H-06: rate limiting must fail CLOSED in production when its backend
(Redis or the DB) is unavailable/raises, while preserving the existing
lenient behavior in development/testing (and the explicit
``ALLOW_INMEMORY_RATE_LIMITS`` escape hatch).

Two fixes are covered here:

  A. ``kk/routes/auth.py::reset_password()`` -- the inline per-account Redis
     counter (in addition to the route's `@rate_limit` per-IP decorator) used
     to silently swallow any Redis exception (`except Exception: pass`),
     skipping the brute-force guard entirely. It now reuses
     ``kk.security._allow_inmemory_rate_limits()`` /
     ``kk.security._rate_limit_unavailable_response()`` to fail closed (503)
     in production, unchanged elsewhere.

  B. ``kk/auth.py::rate_limit_check()`` -- a DB-backed check (currently dead
     code, never called by any route) that returned ``True`` (allow) on any
     DB exception. It now returns ``False`` in production and ``True`` in
     development/testing, matching the same environment semantics.

The route's own per-IP ``@rate_limit(...)`` decorator (``kk/security.py``,
NOT modified by this fix) is bypassed in these tests via a monkeypatch of
``kk.security.check_rate_limit`` so each test exercises only the inline
per-account block under test, in isolation from the unrelated per-IP layer.
"""

from __future__ import annotations

import os
import sys
import tempfile
import uuid
from pathlib import Path
from unittest.mock import MagicMock

import pytest

_REPO_ROOT = Path(__file__).resolve().parents[2]
if str(_REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(_REPO_ROOT))


# ---------------------------------------------------------------------------
# Shared Flask app fixture
# ---------------------------------------------------------------------------


@pytest.fixture(scope="module")
def app_ctx():
    tmp = tempfile.TemporaryDirectory(prefix="carlist_h06_", ignore_cleanup_errors=True)
    os.environ["APP_ENV"] = "testing"
    os.environ["SMS_PROVIDER"] = "console"
    os.environ.pop("LISTING_REQUIRE_APPROVAL", None)
    os.environ["DB_PATH"] = os.path.join(tmp.name, "h06.db")

    from kk.app_factory import create_app

    app, socketio, *_ = create_app()
    from kk.models import User, db

    with app.app_context():
        db.drop_all()
        db.create_all()

    yield app, app.test_client(), db, User

    with app.app_context():
        db.session.remove()
        db.engine.dispose()
    tmp.cleanup()


@pytest.fixture
def client(app_ctx):
    return app_ctx[1]


@pytest.fixture(autouse=True)
def _bypass_per_ip_decorator(monkeypatch):
    """Isolate the inline per-account block under test from the unrelated
    per-IP ``@rate_limit`` decorator (``kk/security.py``, not modified by
    this fix, and already known-good/fail-closed on its own)."""
    import kk.security as security_module

    monkeypatch.setattr(security_module, "check_rate_limit", lambda *a, **kw: None)


def _unique_phone() -> str:
    return f"077{uuid.uuid4().int % 10**8:08d}"


def _make_user(app_ctx):
    app, _client, db, User = app_ctx
    with app.app_context():
        user = User(
            username=f"h06_user_{uuid.uuid4().hex[:8]}",
            phone_number=_unique_phone(),
            first_name="H06",
            last_name="Test",
            email=None,
            is_active=True,
            is_verified=True,
            phone_verified=True,
            public_id=f"pub-{uuid.uuid4().hex[:12]}",
        )
        user.set_password("Original1!")
        db.session.add(user)
        db.session.commit()
        return user.id


def _make_reset_token(app_ctx, user_id: int) -> str:
    app, _client, db, User = app_ctx
    with app.app_context():
        from kk.auth import create_password_reset_token

        user = User.query.get(user_id)
        return create_password_reset_token(user, channel="sms")


# ---------------------------------------------------------------------------
# Fake Redis clients
# ---------------------------------------------------------------------------


class _FakeRedisHealthy:
    """Minimal in-memory stand-in for the real Redis client's incr/expire/ttl."""

    def __init__(self):
        self._counts: dict[str, int] = {}

    def incr(self, key):
        self._counts[key] = self._counts.get(key, 0) + 1
        return self._counts[key]

    def expire(self, key, seconds):
        return True

    def ttl(self, key):
        return 900


class _FakeRedisRaising:
    """Simulates a Redis connection that raises on every command."""

    def incr(self, key):
        raise ConnectionError("redis unavailable")

    def expire(self, key, seconds):
        raise ConnectionError("redis unavailable")

    def ttl(self, key):
        raise ConnectionError("redis unavailable")


# ---------------------------------------------------------------------------
# A. kk/routes/auth.py::reset_password() -- per-account Redis check
# ---------------------------------------------------------------------------


class TestResetPasswordPerAccountFailClosed:
    def _reset(self, client, app_ctx, user_id: int, *, password="NewPassw0rd!"):
        token = _make_reset_token(app_ctx, user_id)
        return client.post(
            "/api/auth/reset-password",
            json={"token": token, "password": password},
        )

    def test_production_redis_incr_exception_returns_503(
        self, client, app_ctx, monkeypatch
    ):
        import kk.security as security_module

        monkeypatch.setenv("APP_ENV", "production")
        monkeypatch.setattr(security_module, "_redis_client", lambda: _FakeRedisRaising())

        user_id = _make_user(app_ctx)
        resp = self._reset(client, app_ctx, user_id)

        assert resp.status_code == 503, resp.data
        body = resp.get_json()
        assert body.get("code") == "rate_limiter_unavailable"

    def test_production_redis_unavailable_returns_503(
        self, client, app_ctx, monkeypatch
    ):
        import kk.security as security_module

        monkeypatch.setenv("APP_ENV", "production")
        monkeypatch.setattr(security_module, "_redis_client", lambda: None)

        user_id = _make_user(app_ctx)
        resp = self._reset(client, app_ctx, user_id)

        assert resp.status_code == 503, resp.data
        body = resp.get_json()
        assert body.get("code") == "rate_limiter_unavailable"

    def test_production_healthy_redis_still_blocks_after_five_attempts(
        self, client, app_ctx, monkeypatch
    ):
        import kk.security as security_module

        monkeypatch.setenv("APP_ENV", "production")
        fake_redis = _FakeRedisHealthy()
        monkeypatch.setattr(security_module, "_redis_client", lambda: fake_redis)

        user_id = _make_user(app_ctx)

        # First 5 attempts: each gets a fresh valid token and succeeds --
        # what matters is the per-account counter increments on every
        # attempt, exactly like production.
        for _ in range(5):
            resp = self._reset(client, app_ctx, user_id)
            assert resp.status_code == 200, resp.data

        # 6th attempt: existing behavior unchanged -- 429 once the per-account
        # counter exceeds 5 within the window.
        resp = self._reset(client, app_ctx, user_id)
        assert resp.status_code == 429, resp.data
        body = resp.get_json()
        assert "Too many reset attempts" in body.get("message", "")

    def test_development_redis_exception_still_allows_request(
        self, client, app_ctx, monkeypatch
    ):
        import kk.security as security_module

        monkeypatch.setenv("APP_ENV", "development")
        monkeypatch.setattr(security_module, "_redis_client", lambda: _FakeRedisRaising())

        user_id = _make_user(app_ctx)
        resp = self._reset(client, app_ctx, user_id)

        assert resp.status_code == 200, resp.data

    def test_testing_redis_unavailable_still_allows_request(
        self, client, app_ctx, monkeypatch
    ):
        import kk.security as security_module

        monkeypatch.setenv("APP_ENV", "testing")
        monkeypatch.setattr(security_module, "_redis_client", lambda: None)

        user_id = _make_user(app_ctx)
        resp = self._reset(client, app_ctx, user_id)

        assert resp.status_code == 200, resp.data


# ---------------------------------------------------------------------------
# B. kk/auth.py::rate_limit_check() -- DB-backed check (currently dead code)
# ---------------------------------------------------------------------------


class TestRateLimitCheckFailClosed:
    def test_production_db_exception_returns_false(self, app_ctx, monkeypatch):
        app, _client, _db, User = app_ctx
        from kk.auth import rate_limit_check
        from kk.models import UserAction

        monkeypatch.setenv("APP_ENV", "production")
        with app.app_context():
            monkeypatch.setattr(
                UserAction,
                "query",
                MagicMock(filter=MagicMock(side_effect=RuntimeError("db down"))),
            )
            result = rate_limit_check(1, "some_action")

        assert result is False

    def test_development_db_exception_returns_true(self, app_ctx, monkeypatch):
        app, _client, _db, User = app_ctx
        from kk.auth import rate_limit_check
        from kk.models import UserAction

        monkeypatch.setenv("APP_ENV", "development")
        with app.app_context():
            monkeypatch.setattr(
                UserAction,
                "query",
                MagicMock(filter=MagicMock(side_effect=RuntimeError("db down"))),
            )
            result = rate_limit_check(1, "some_action")

        assert result is True

    def test_testing_db_exception_returns_true(self, app_ctx, monkeypatch):
        app, _client, _db, User = app_ctx
        from kk.auth import rate_limit_check
        from kk.models import UserAction

        monkeypatch.setenv("APP_ENV", "testing")
        with app.app_context():
            monkeypatch.setattr(
                UserAction,
                "query",
                MagicMock(filter=MagicMock(side_effect=RuntimeError("db down"))),
            )
            result = rate_limit_check(1, "some_action")

        assert result is True

    def test_normal_behavior_under_limit_returns_true(self, app_ctx):
        app, _client, db, User = app_ctx
        from kk.auth import rate_limit_check
        from kk.models import UserAction

        user_id = _make_user(app_ctx)
        with app.app_context():
            for _ in range(3):
                db.session.add(UserAction(user_id=user_id, action_type="h06_probe"))
            db.session.commit()

            assert rate_limit_check(user_id, "h06_probe", limit=5, window_minutes=60) is True

    def test_normal_behavior_at_limit_returns_false(self, app_ctx):
        app, _client, db, User = app_ctx
        from kk.auth import rate_limit_check
        from kk.models import UserAction

        user_id = _make_user(app_ctx)
        with app.app_context():
            for _ in range(5):
                db.session.add(UserAction(user_id=user_id, action_type="h06_probe_limit"))
            db.session.commit()

            assert rate_limit_check(user_id, "h06_probe_limit", limit=5, window_minutes=60) is False
