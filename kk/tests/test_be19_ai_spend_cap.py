"""BE-19 regression tests: ``POST /api/suggest-car-specs`` must be bounded by
a GLOBAL (cross-user) daily request budget, on top of (not instead of) the
existing per-user 20/hour rate limit, and each individual OpenAI call must
carry a bounded ``max_completion_tokens`` ceiling.

Bug (PRODUCTION_AUDIT.md BE-19): the only protection against unbounded
OpenAI spend was a 20 requests/hour/user rate limit
(``kk/routes/ai.py::suggest_car_specs`` -- ``@rate_limit(max_requests=20,
window_minutes=60, per_ip=False)``). Since the limit is keyed per
*authenticated user*, an attacker controlling N accounts could still drive
N x 20 calls/hour with no aggregate ceiling, and no per-request output-size
cap bounded the worst case of any single permitted call.

The fix adds:

  - ``kk.security.check_global_daily_budget`` -- a GLOBAL (not per-user/IP)
    Redis-``INCR``-based daily counter, claimed BEFORE the OpenAI call, with
    the same fail-closed-in-production-without-Redis (H-06) semantics as the
    existing per-user/IP rate limiter, and the same dev/test escape hatch.
  - ``kk/routes/ai.py::suggest_car_specs`` -- calls the above, configured via
    ``AI_SPECS_MAX_CALLS_PER_DAY`` (falls back to a documented default),
    immediately before invoking ``suggest_car_specs_from_ymm``. Returns a
    plain 503 (shape consistent with this endpoint's other error responses)
    when the budget is exhausted; does not touch the existing per-user
    ``@rate_limit(...)`` decorator.
  - ``kk/ai_service.py::suggest_car_specs_from_ymm`` -- adds
    ``max_completion_tokens`` (NOT the legacy ``max_tokens``, which OpenAI's
    o-series/reasoning models and the GPT-5 family reject outright) to the
    OpenAI Chat Completions request payload.

These tests exercise the real Flask route via the test client (per BE-19's
instructions); only the external OpenAI HTTP call
(``kk.ai_service.requests.post``) and, where explicitly noted, the Redis
client (``kk.security._redis_client``, exactly as the existing H-06 tests
already do) are mocked.
"""

from __future__ import annotations

import json
import os
import sys
import tempfile
import threading
import uuid
from pathlib import Path
from unittest import mock

import pytest

_REPO_ROOT = Path(__file__).resolve().parents[2]
if str(_REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(_REPO_ROOT))


# ---------------------------------------------------------------------------
# Shared Flask app fixture
# ---------------------------------------------------------------------------


@pytest.fixture(scope="module")
def app_ctx():
    tmp = tempfile.TemporaryDirectory(
        prefix="carlist_be19_", ignore_cleanup_errors=True
    )
    os.environ["APP_ENV"] = "testing"
    os.environ["SMS_PROVIDER"] = "console"
    os.environ.pop("LISTING_REQUIRE_APPROVAL", None)
    os.environ["DB_PATH"] = os.path.join(tmp.name, "be19.db")

    from kk.app_factory import create_app

    app, _socketio, *_ = create_app()
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
def _reset_budget_state(monkeypatch):
    """Isolate each test's global-budget counter and env from the others.

    The in-process fallback counter (``kk.security._global_budget_storage``)
    is a single module-level dict keyed only by ``name``+window -- NOT by
    test -- so it must be cleared between tests. Also ensures no stray env
    var leaks between tests unless a test explicitly opts in.
    """
    import kk.security as security_module

    security_module._global_budget_storage.clear()
    monkeypatch.delenv("REDIS_URL", raising=False)
    monkeypatch.delenv("AI_SPECS_MAX_CALLS_PER_DAY", raising=False)
    monkeypatch.delenv("OPENAI_API_KEY", raising=False)
    monkeypatch.delenv("OPENAI_MODEL", raising=False)
    yield
    security_module._global_budget_storage.clear()


# ---------------------------------------------------------------------------
# Helpers: users, auth, fake OpenAI, fake Redis
# ---------------------------------------------------------------------------


def _unique_phone() -> str:
    return f"077{uuid.uuid4().int % 10**8:08d}"


def _make_user(app_ctx, *, username: str) -> None:
    app, _client, db, User = app_ctx
    with app.app_context():
        user = User(
            username=username,
            phone_number=_unique_phone(),
            first_name=username.title(),
            last_name="Test",
            email=None,
            is_active=True,
            is_verified=True,
            phone_verified=True,
            public_id=f"pub-{uuid.uuid4().hex[:12]}",
        )
        user.set_password("Aa123456!")
        db.session.add(user)
        db.session.commit()


def _login(client, username: str, password: str = "Aa123456!") -> str:
    r = client.post(
        "/api/auth/login", json={"username": username, "password": password}
    )
    assert r.status_code == 200, r.data
    return r.get_json()["access_token"]


def _auth(token: str) -> dict:
    return {"Authorization": f"Bearer {token}"}


_VALID_SPECS_BODY = {
    "year": 2020,
    "brand": "Toyota",
    "model": "Camry",
    "trim": "LE",
}

_DEFAULT_SPEC_CONTENT = {
    "transmission": "automatic",
    "drivetrain": "fwd",
    "body_type": "sedan",
    "fuel_type": "gasoline",
    "engine_type": "gasoline",
    "engine_size_liters": 2.5,
    "cylinder_count": 4,
    "seating": 5,
    "fuel_economy": "7.5L/100km",
    "notes": "Most common trim configuration.",
}


class _FakeOpenAIResponse:
    def __init__(self, status_code=200, content=None, text=""):
        self.status_code = status_code
        self._content = content if content is not None else _DEFAULT_SPEC_CONTENT
        self.text = text

    def json(self):
        return {
            "choices": [
                {"message": {"content": json.dumps(self._content)}}
            ]
        }


class _OpenAICallRecorder:
    """Stands in for ``kk.ai_service.requests.post``. Records every call so
    tests can assert whether/how many times OpenAI was actually invoked,
    and inspect the outgoing JSON payload (e.g. for the ``max_tokens``
    ceiling)."""

    def __init__(self, content=None, status_code=200):
        self.calls: list[dict] = []
        self.content = content
        self.status_code = status_code

    def __call__(self, url, headers=None, json=None, timeout=None):  # noqa: A002
        self.calls.append(
            {"url": url, "headers": headers, "json": json, "timeout": timeout}
        )
        return _FakeOpenAIResponse(self.status_code, self.content)

    @property
    def call_count(self) -> int:
        return len(self.calls)


def _mock_openai_success(monkeypatch) -> _OpenAICallRecorder:
    import kk.ai_service as ai_service_module

    recorder = _OpenAICallRecorder()
    monkeypatch.setattr(ai_service_module.requests, "post", recorder)
    return recorder


class _FakeRedisHealthy:
    """Minimal in-memory stand-in for the real Redis client's
    incr/expire/ttl, matching the pattern already used by
    ``test_h06_rate_limit_fail_closed.py``. Uses a real lock so concurrent
    ``incr()`` calls from multiple threads are atomic, exactly like the
    real Redis ``INCR`` command -- this is what the concurrency-safety test
    below relies on.
    """

    def __init__(self):
        self._lock = threading.Lock()
        self._counts: dict[str, int] = {}
        self._expirations: dict[str, int] = {}

    def incr(self, key):
        with self._lock:
            self._counts[key] = self._counts.get(key, 0) + 1
            return self._counts[key]

    def expire(self, key, seconds):
        self._expirations[key] = seconds
        return True

    def ttl(self, key):
        return self._expirations.get(key, 86400)

    def reset_key(self, key):
        """Simulate the key's TTL having elapsed -- Redis would simply drop
        it, and the next INCR would start a fresh window."""
        self._counts.pop(key, None)
        self._expirations.pop(key, None)


class _FakeRedisRaising:
    """Simulates a Redis connection that raises on every command."""

    def incr(self, key):
        raise ConnectionError("redis unavailable")

    def expire(self, key, seconds):
        raise ConnectionError("redis unavailable")

    def ttl(self, key):
        raise ConnectionError("redis unavailable")


# Derived from the route's fixed call:
# ``check_global_daily_budget("ai_specs", ..., window_minutes=1440)`` ->
# window_s = 1440 * 60 = 86400.
_AI_SPECS_BUDGET_KEY = "budget:ai_specs:86400"


def _post_specs(client, token: str, body: dict | None = None):
    return client.post(
        "/api/suggest-car-specs",
        json=body if body is not None else _VALID_SPECS_BODY,
        headers=_auth(token),
    )


# ---------------------------------------------------------------------------
# (a) Global cap: small budget, 3rd call denied + does not call OpenAI
# ---------------------------------------------------------------------------


def test_global_budget_denies_after_configured_cap_and_skips_openai(
    app_ctx, monkeypatch
):
    app, client, *_ = app_ctx
    monkeypatch.setenv("OPENAI_API_KEY", "test-key")
    monkeypatch.setenv("AI_SPECS_MAX_CALLS_PER_DAY", "2")
    recorder = _mock_openai_success(monkeypatch)

    username = f"be19_cap_{uuid.uuid4().hex[:8]}"
    _make_user(app_ctx, username=username)
    token = _login(client, username)

    r1 = _post_specs(client, token)
    assert r1.status_code == 200, r1.data
    r2 = _post_specs(client, token)
    assert r2.status_code == 200, r2.data
    assert recorder.call_count == 2

    r3 = _post_specs(client, token)
    assert r3.status_code == 503, r3.data
    body = r3.get_json()
    assert body.get("code") == "ai_budget_exhausted"

    # (h) Budget exhaustion: no OpenAI request happened for the 3rd call.
    assert recorder.call_count == 2, (
        "OpenAI must not be called once the global daily budget is exhausted"
    )


# ---------------------------------------------------------------------------
# (b) Global behavior: shared across different users, not per-user
# ---------------------------------------------------------------------------


def test_global_budget_is_shared_across_different_users(app_ctx, monkeypatch):
    app, client, *_ = app_ctx
    monkeypatch.setenv("OPENAI_API_KEY", "test-key")
    monkeypatch.setenv("AI_SPECS_MAX_CALLS_PER_DAY", "2")
    recorder = _mock_openai_success(monkeypatch)

    user_a = f"be19_shareA_{uuid.uuid4().hex[:8]}"
    user_b = f"be19_shareB_{uuid.uuid4().hex[:8]}"
    _make_user(app_ctx, username=user_a)
    _make_user(app_ctx, username=user_b)
    token_a = _login(client, user_a)
    token_b = _login(client, user_b)

    # First call from user A, second from user B -- both consume the same
    # SHARED global budget (cap = 2), not two independent per-user budgets.
    r_a1 = _post_specs(client, token_a)
    assert r_a1.status_code == 200, r_a1.data
    r_b1 = _post_specs(client, token_b)
    assert r_b1.status_code == 200, r_b1.data
    assert recorder.call_count == 2

    # A third call from EITHER user must now be denied -- proving the cap
    # is global, not "2 per user" (which would still allow user A a 2nd call
    # and user B a 2nd call).
    r_a2 = _post_specs(client, token_a)
    assert r_a2.status_code == 503, r_a2.data
    assert r_a2.get_json().get("code") == "ai_budget_exhausted"

    r_b2 = _post_specs(client, token_b)
    assert r_b2.status_code == 503, r_b2.data
    assert r_b2.get_json().get("code") == "ai_budget_exhausted"

    assert recorder.call_count == 2, "no further OpenAI calls once exhausted"


# ---------------------------------------------------------------------------
# (c) Window/reset: a new daily bucket permits requests again (no real wait)
# ---------------------------------------------------------------------------


def test_global_budget_resets_once_the_daily_window_elapses(app_ctx, monkeypatch):
    app, client, *_ = app_ctx
    import kk.security as security_module

    monkeypatch.setenv("OPENAI_API_KEY", "test-key")
    monkeypatch.setenv("AI_SPECS_MAX_CALLS_PER_DAY", "1")
    recorder = _mock_openai_success(monkeypatch)

    fake_redis = _FakeRedisHealthy()
    monkeypatch.setattr(security_module, "_redis_client", lambda: fake_redis)

    username = f"be19_reset_{uuid.uuid4().hex[:8]}"
    _make_user(app_ctx, username=username)
    token = _login(client, username)

    r1 = _post_specs(client, token)
    assert r1.status_code == 200, r1.data
    assert fake_redis._expirations.get(_AI_SPECS_BUDGET_KEY) == 86400, (
        "the daily budget key must be given a ~24h TTL on first claim"
    )

    r2 = _post_specs(client, token)
    assert r2.status_code == 503, r2.data
    assert recorder.call_count == 1

    # Simulate the key's 24h TTL having elapsed (Redis would drop it itself;
    # we drop it from the fake to get the same effect deterministically,
    # without sleeping for a day).
    fake_redis.reset_key(_AI_SPECS_BUDGET_KEY)

    r3 = _post_specs(client, token)
    assert r3.status_code == 200, r3.data
    assert recorder.call_count == 2, "a fresh window must permit calls again"


# ---------------------------------------------------------------------------
# (d) Existing per-user limiter: still enforced, independently of the budget
# ---------------------------------------------------------------------------


def test_existing_per_user_rate_limit_still_enforced_independently(
    app_ctx, monkeypatch
):
    """The per-user @rate_limit(max_requests=20, window_minutes=60,
    per_ip=False) decorator (unmodified by BE-19) must still trip on its
    own, separately from the new global daily budget. ``check_rate_limit``
    is normally a no-op under APP_ENV=testing / app.config['TESTING'] (see
    other tests in this suite / test_signup_otp_required.py's note on this),
    so both are explicitly flipped off for this test only."""
    app, client, *_ = app_ctx
    import kk.security as security_module

    monkeypatch.setenv("APP_ENV", "production")
    monkeypatch.setitem(app.config, "TESTING", False)
    monkeypatch.setenv("OPENAI_API_KEY", "test-key")
    # Generous global budget so ONLY the per-user limiter can trip here.
    monkeypatch.setenv("AI_SPECS_MAX_CALLS_PER_DAY", "1000")
    recorder = _mock_openai_success(monkeypatch)

    fake_redis = _FakeRedisHealthy()
    monkeypatch.setattr(security_module, "_redis_client", lambda: fake_redis)

    username = f"be19_peruser_{uuid.uuid4().hex[:8]}"
    _make_user(app_ctx, username=username)
    token = _login(client, username)

    for i in range(20):
        r = _post_specs(client, token)
        assert r.status_code == 200, (i, r.data)
    assert recorder.call_count == 20

    # 21st call from the SAME user within the hour: blocked by the per-user
    # limiter (429), NOT the global budget (which still has ~980 left).
    r21 = _post_specs(client, token)
    assert r21.status_code == 429, r21.data
    assert "Rate limit exceeded" in (r21.get_json() or {}).get("message", "")

    # The blocked request never reached the route body, so it never touched
    # (and did not need to touch) the global budget or OpenAI.
    assert recorder.call_count == 20, (
        "a per-user-rate-limited request must not consume global budget or "
        "call OpenAI"
    )


# ---------------------------------------------------------------------------
# (e) Redis failure: production fails closed; dev/test escape hatch preserved
# ---------------------------------------------------------------------------


def test_route_production_redis_unavailable_fails_closed(app_ctx, monkeypatch):
    app, client, *_ = app_ctx
    import kk.security as security_module

    monkeypatch.setenv("APP_ENV", "production")
    monkeypatch.setenv("OPENAI_API_KEY", "test-key")
    monkeypatch.setattr(security_module, "_redis_client", lambda: None)
    recorder = _mock_openai_success(monkeypatch)

    username = f"be19_redisdown_{uuid.uuid4().hex[:8]}"
    _make_user(app_ctx, username=username)
    token = _login(client, username)

    r = _post_specs(client, token)
    assert r.status_code == 503, r.data
    assert r.get_json().get("code") == "rate_limiter_unavailable"
    assert recorder.call_count == 0, "must fail closed before calling OpenAI"


def test_route_production_redis_raising_fails_closed(app_ctx, monkeypatch):
    app, client, *_ = app_ctx
    import kk.security as security_module

    monkeypatch.setenv("APP_ENV", "production")
    monkeypatch.setenv("OPENAI_API_KEY", "test-key")
    monkeypatch.setattr(security_module, "_redis_client", lambda: _FakeRedisRaising())
    recorder = _mock_openai_success(monkeypatch)

    username = f"be19_redisraise_{uuid.uuid4().hex[:8]}"
    _make_user(app_ctx, username=username)
    token = _login(client, username)

    r = _post_specs(client, token)
    assert r.status_code == 503, r.data
    assert r.get_json().get("code") == "rate_limiter_unavailable"
    assert recorder.call_count == 0


def test_route_development_redis_unavailable_uses_escape_hatch(app_ctx, monkeypatch):
    """Preserve the existing dev/test escape hatch: outside production,
    Redis being unavailable falls back to the in-process counter instead of
    failing closed (matching check_rate_limit's own documented behavior)."""
    app, client, *_ = app_ctx
    import kk.security as security_module

    monkeypatch.setenv("APP_ENV", "development")
    monkeypatch.setenv("OPENAI_API_KEY", "test-key")
    monkeypatch.setattr(security_module, "_redis_client", lambda: None)
    recorder = _mock_openai_success(monkeypatch)

    username = f"be19_devfallback_{uuid.uuid4().hex[:8]}"
    _make_user(app_ctx, username=username)
    token = _login(client, username)

    r = _post_specs(client, token)
    assert r.status_code == 200, r.data
    assert recorder.call_count == 1


# ---------------------------------------------------------------------------
# (f) OpenAI payload: token ceiling actually present, using the
# model-agnostic `max_completion_tokens` parameter (NOT the legacy
# `max_tokens`, which OpenAI's o-series/reasoning models and the GPT-5
# family reject outright -- and OPENAI_MODEL is an existing, operator-
# configurable env var with no allowlist, so this must not be assumed to
# always be `gpt-4o-mini`).
# ---------------------------------------------------------------------------


def test_openai_request_payload_includes_max_completion_tokens_ceiling(
    app_ctx, monkeypatch
):
    app, client, *_ = app_ctx
    monkeypatch.setenv("OPENAI_API_KEY", "test-key")
    recorder = _mock_openai_success(monkeypatch)

    username = f"be19_tokens_{uuid.uuid4().hex[:8]}"
    _make_user(app_ctx, username=username)
    token = _login(client, username)

    r = _post_specs(client, token)
    assert r.status_code == 200, r.data
    assert recorder.call_count == 1

    payload = recorder.calls[0]["json"]
    assert "max_completion_tokens" in payload, (
        "OpenAI request must set a max_completion_tokens ceiling"
    )
    assert (
        isinstance(payload["max_completion_tokens"], int)
        and payload["max_completion_tokens"] > 0
    )
    assert "max_tokens" not in payload, (
        "the legacy max_tokens parameter must not be sent -- it is rejected "
        "by OpenAI's o-series/reasoning models and the GPT-5 family, which "
        "are realistic values for the operator-configurable OPENAI_MODEL"
    )
    # Unrelated fields/behavior must be untouched.
    assert payload["response_format"] == {"type": "json_object"}
    assert payload["model"] == "gpt-4o-mini"
    assert payload["temperature"] == 0.2


# ---------------------------------------------------------------------------
# (g) Success compatibility: under budget, response shape unchanged
# ---------------------------------------------------------------------------


def test_success_response_shape_unchanged_when_under_budget(app_ctx, monkeypatch):
    app, client, *_ = app_ctx
    monkeypatch.setenv("OPENAI_API_KEY", "test-key")
    _mock_openai_success(monkeypatch)

    username = f"be19_shape_{uuid.uuid4().hex[:8]}"
    _make_user(app_ctx, username=username)
    token = _login(client, username)

    r = _post_specs(client, token)
    assert r.status_code == 200, r.data
    body = r.get_json()
    assert body["success"] is True
    specs = body["specs"]
    assert specs["transmission"] == "automatic"
    assert specs["drivetrain"] == "fwd"
    assert specs["body_type"] == "sedan"
    assert specs["source"] == "openai"
    assert specs["model"] == "gpt-4o-mini"


# ---------------------------------------------------------------------------
# Concurrency safety of the global counter
# ---------------------------------------------------------------------------


def test_global_budget_counter_is_concurrency_safe(app_ctx):
    """Directly hammer ``check_global_daily_budget`` from many threads
    concurrently against a shared fake-but-atomic Redis client (real lock
    inside ``_FakeRedisHealthy.incr``, mirroring Redis's own atomic INCR).
    Exactly `max_calls` callers must be permitted -- never more -- proving
    concurrent requests cannot jointly exceed the configured cap."""
    app, _client, *_ = app_ctx
    import kk.security as security_module

    fake_redis = _FakeRedisHealthy()
    max_calls = 10
    n_threads = 50
    permitted = []
    permitted_lock = threading.Lock()

    def worker():
        with app.app_context():
            with app.test_request_context():
                result = security_module.check_global_daily_budget(
                    "be19_concurrency_probe", max_calls, window_minutes=1440
                )
        if result is None:
            with permitted_lock:
                permitted.append(1)

    with mock.patch.object(security_module, "_redis_client", lambda: fake_redis):
        threads = [threading.Thread(target=worker) for _ in range(n_threads)]
        for t in threads:
            t.start()
        for t in threads:
            t.join()

    assert len(permitted) == max_calls, (
        f"expected exactly {max_calls} permitted calls out of {n_threads} "
        f"concurrent attempts, got {len(permitted)} -- the counter is not "
        "concurrency-safe"
    )


def test_global_budget_in_memory_fallback_is_concurrency_safe(
    app_ctx, monkeypatch
):
    """Same property as the Redis-backed concurrency test above, but for
    the NEW in-process fallback path (``_global_budget_storage`` +
    ``_global_budget_storage_lock`` in ``kk/security.py``). Forces the
    fallback path explicitly (Redis unavailable + dev/test escape hatch),
    hammers ``check_global_daily_budget`` from many concurrent threads with
    a small cap, and proves the permitted count never exceeds the cap --
    i.e. the compound read/window-check/increment/write sequence is not
    subject to a lost-update race, and this is NOT merely relying on the
    GIL (there is no lock-free path being exercised here)."""
    app, _client, *_ = app_ctx
    import kk.security as security_module

    # Force the in-memory fallback path, not Redis: APP_ENV=development
    # (or the explicit ALLOW_INMEMORY_RATE_LIMITS escape hatch) makes
    # `_allow_inmemory_rate_limits()` True, and returning None from
    # `_redis_client()` means the Redis branch is skipped entirely.
    monkeypatch.setenv("APP_ENV", "development")
    monkeypatch.setattr(security_module, "_redis_client", lambda: None)

    max_calls = 10
    n_threads = 50
    permitted = []
    permitted_lock = threading.Lock()

    def worker():
        with app.app_context():
            with app.test_request_context():
                result = security_module.check_global_daily_budget(
                    "be19_inmemory_concurrency_probe",
                    max_calls,
                    window_minutes=1440,
                )
        if result is None:
            with permitted_lock:
                permitted.append(1)

    threads = [threading.Thread(target=worker) for _ in range(n_threads)]
    for t in threads:
        t.start()
    for t in threads:
        t.join()

    assert len(permitted) == max_calls, (
        f"expected exactly {max_calls} permitted calls out of {n_threads} "
        f"concurrent attempts against the in-memory fallback, got "
        f"{len(permitted)} -- the fallback counter is not concurrency-safe "
        "(missing/ineffective lock around the compound operation)"
    )
