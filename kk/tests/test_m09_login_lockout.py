"""M-09: account-keyed failed-login throttle.

Bug (PRODUCTION_AUDIT.md M-09): `POST /api/auth/login` was protected only by
a per-IP `@rate_limit(max_requests=10, window_minutes=15)` decorator
(`kk/routes/auth.py`). Because the limiter key is `route:client_ip:window`
with no account component at all (`kk/security.py::_rate_limit_key`), an
attacker who spreads password guesses against ONE target account across many
source IPs never triggers any throttle: each IP gets its own fresh 10/15min
budget. `kk/auth.py::rate_limit_check()` -- a DB-backed, per-user limiter --
existed in the codebase but was dead code, never wired into `login()`.
Confirmed valid and reproduced against the pre-fix `login()` in the M-09
investigation (see PRODUCTION_AUDIT.md M-09 investigation notes).

The fix adds a SEPARATE, account-keyed failed-login throttle
(`kk/security.py::check_account_login_throttle` /
`record_account_login_failure` / `reset_account_login_failures`), checked
inside `login()` in addition to (not instead of) the existing per-IP
decorator:

  - Keyed by the ALREADY-RESOLVED account row's own canonical identifier
    (`kk/routes/auth.py::_account_login_lock_identifier` -- phone/username
    for `User`, email/phone/username for `AdminAccount`), HMAC'd with
    `SECRET_KEY` before ever touching Redis -- never a raw phone/email/
    username in a Redis key.
  - 5 failed password attempts inside a 15-minute window trigger a
    15-minute temporary lock (mirrors the existing, already-audited OTP
    lockout policy: `kk/routes/auth.py::_OTP_MAX_ATTEMPTS` /
    `_OTP_LOCKOUT_MINUTES`).
  - While locked, password verification is skipped entirely and the
    response is the SAME generic `{"message": "Invalid credentials"}` /
    401 used for an ordinary wrong password -- no distinguishing
    message/code, no remaining-attempts/lock-duration leak.
  - Only a genuinely failed password check against a RESOLVED account
    increments the counter; unknown identifiers are never throttled at the
    account level (nothing to protect, and it would create a new
    enumeration signal); a SUCCESSFUL login clears the counter/lock.
  - Redis `INCR` is atomic server-side -- no SELECT-then-UPDATE race.
  - Follows the exact same H-06 fail-closed policy as the pre-existing
    per-IP limiter: if Redis is required (production, no escape hatch) but
    unavailable, the check returns a 503, never silently "unlimited".

These tests exercise the real `/api/auth/login` route via the Flask test
client (per M-09's instructions); only `kk.security._redis_client` is
mocked (with a real, thread-safe, in-memory INCR/EXPIRE/TTL/SET/EXISTS/
DELETE stand-in -- same pattern as `test_be19_ai_spend_cap.py`/
`test_h06_rate_limit_fail_closed.py`), and `APP_ENV`/`app.config['TESTING']`
are explicitly flipped to production-like values per test (the account
throttle -- like the pre-existing per-IP limiter -- is a full no-op under
the suite's default `APP_ENV=testing`, so this must be done explicitly;
see `test_be19_ai_spend_cap.py::test_existing_per_user_rate_limit_still_enforced_independently`
for the established precedent this mirrors).
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


# ---------------------------------------------------------------------------
# Shared Flask app fixture
# ---------------------------------------------------------------------------


@pytest.fixture(scope="module")
def app_ctx():
    tmp = tempfile.TemporaryDirectory(
        prefix="carlist_m09_", ignore_cleanup_errors=True
    )
    os.environ["APP_ENV"] = "testing"
    os.environ["SMS_PROVIDER"] = "console"
    os.environ["DB_PATH"] = os.path.join(tmp.name, "m09.db")

    from kk.app_factory import create_app

    app, *_ = create_app()
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


# ---------------------------------------------------------------------------
# Fake Redis: real INCR/EXPIRE/TTL/SET/EXISTS/DELETE semantics, thread-safe,
# in-memory. Same shape/precedent as test_be19_ai_spend_cap.py /
# test_h06_rate_limit_fail_closed.py, extended with SET/EXISTS/DELETE for
# the M-09 lock flag.
# ---------------------------------------------------------------------------


class _FakeRedisHealthy:
    def __init__(self):
        self._lock = threading.Lock()
        self._counts: dict[str, int] = {}
        self._values: dict[str, str] = {}
        self._expirations: dict[str, int] = {}

    def incr(self, key):
        with self._lock:
            self._counts[key] = self._counts.get(key, 0) + 1
            return self._counts[key]

    def expire(self, key, seconds):
        with self._lock:
            self._expirations[key] = seconds
        return True

    def ttl(self, key):
        with self._lock:
            return self._expirations.get(key, 900)

    def set(self, key, value, ex=None):
        with self._lock:
            self._values[key] = value
            if ex is not None:
                self._expirations[key] = ex
        return True

    def exists(self, key):
        with self._lock:
            return 1 if key in self._values else 0

    def delete(self, *keys):
        with self._lock:
            n = 0
            for k in keys:
                if k in self._values:
                    del self._values[k]
                    n += 1
                self._counts.pop(k, None)
                self._expirations.pop(k, None)
            return n

    def reset_key(self, key):
        """Simulate a key's TTL having elapsed -- real Redis would drop it
        itself; the fake drops it to get the same effect deterministically,
        without sleeping for the real TTL duration."""
        with self._lock:
            self._counts.pop(key, None)
            self._values.pop(key, None)
            self._expirations.pop(key, None)


class _FakeRedisRaising:
    """Simulates a Redis connection that raises on every command (H-06
    fail-closed check for the new account throttle)."""

    def incr(self, key):
        raise ConnectionError("redis unavailable")

    def expire(self, key, seconds):
        raise ConnectionError("redis unavailable")

    def ttl(self, key):
        raise ConnectionError("redis unavailable")

    def set(self, key, value, ex=None):
        raise ConnectionError("redis unavailable")

    def exists(self, key):
        raise ConnectionError("redis unavailable")

    def delete(self, *keys):
        raise ConnectionError("redis unavailable")


@pytest.fixture
def prod_redis(app_ctx, monkeypatch):
    """Flips the app into a production-like rate-limiting mode (the account
    throttle -- like the existing per-IP limiter -- is a full no-op under
    the suite's default APP_ENV=testing / app.config['TESTING']=True) and
    wires in a healthy fake Redis so BOTH the pre-existing per-IP limiter
    and the new M-09 account throttle exercise their real Redis-backed
    logic."""
    app, *_ = app_ctx
    import kk.security as security_module

    fake = _FakeRedisHealthy()
    monkeypatch.setenv("APP_ENV", "production")
    monkeypatch.setitem(app.config, "TESTING", False)
    monkeypatch.setattr(security_module, "_redis_client", lambda: fake)
    return fake


# ---------------------------------------------------------------------------
# Helpers: users, admin accounts, login
# ---------------------------------------------------------------------------


def _unique_phone() -> str:
    return f"077{uuid.uuid4().int % 10**8:08d}"


def _make_user(app_ctx, *, username: str | None = None, password: str = _PASSWORD) -> str:
    app, _client, db, User = app_ctx
    username = username or f"m09_{uuid.uuid4().hex[:10]}"
    with app.app_context():
        user = User(
            username=username,
            phone_number=_unique_phone(),
            first_name="M09",
            last_name="Test",
            email=None,
            is_active=True,
            is_verified=True,
            phone_verified=True,
            public_id=f"pub-{uuid.uuid4().hex[:12]}",
        )
        user.set_password(password)
        db.session.add(user)
        db.session.commit()
    return username


def _user_phone(app_ctx, username: str) -> str:
    app, _client, db, User = app_ctx
    with app.app_context():
        user = User.query.filter_by(username=username).first()
        return user.phone_number


def _make_admin(app_ctx, *, password: str = _PASSWORD) -> dict:
    app, _client, db, User = app_ctx
    from kk.models import AdminAccount

    username = f"m09admin_{uuid.uuid4().hex[:10]}"
    with app.app_context():
        principal = User(
            username=f"{username}_principal",
            phone_number=_unique_phone(),
            first_name="M09",
            last_name="Admin",
            email=None,
            is_active=True,
            is_verified=True,
            phone_verified=True,
            is_admin=True,
            public_id=f"pub-{uuid.uuid4().hex[:12]}",
        )
        principal.set_password(uuid.uuid4().hex)
        db.session.add(principal)
        db.session.commit()

        acct = AdminAccount(
            principal_user_id=principal.id,
            username=username,
            is_active=True,
        )
        acct.set_password(password)
        db.session.add(acct)
        db.session.commit()
        acct_id = acct.id

    return {"username": username, "password": password, "id": acct_id}


def _login(client, username: str, password: str, ip: str, *, account_scope: str | None = None):
    body = {"username": username, "password": password}
    if account_scope is not None:
        body["account_scope"] = account_scope
    return client.post(
        "/api/auth/login",
        json=body,
        environ_overrides={"REMOTE_ADDR": ip},
    )


def _account_hash_for_user(app_ctx, username: str) -> str:
    """Recomputes the exact M-09 Redis key hash `login()` would use for this
    user, by calling the REAL helper functions -- not by duplicating their
    logic -- so the TTL-expiry test targets the right key."""
    app, _client, db, User = app_ctx
    from kk.routes.auth import _account_login_lock_identifier
    import kk.security as security_module

    with app.app_context():
        user = User.query.filter_by(username=username).first()
        canonical = _account_login_lock_identifier(user=user)
        return security_module.account_login_throttle_key(canonical)


# ---------------------------------------------------------------------------
# A. Existing per-IP behavior remains unchanged
# ---------------------------------------------------------------------------


def test_a_same_ip_limiter_still_allows_10_then_blocks_11th(app_ctx, client, prod_redis):
    username = _make_user(app_ctx)
    ip = "203.0.113.10"

    for i in range(10):
        r = _login(client, username, "WrongPassword!", ip)
        assert r.status_code == 401, (i, r.get_json())

    r11 = _login(client, username, "WrongPassword!", ip)
    assert r11.status_code == 429, r11.get_json()
    assert "Rate limit exceeded" in (r11.get_json() or {}).get("message", "")


# ---------------------------------------------------------------------------
# B. Distributed password spraying is stopped
# ---------------------------------------------------------------------------


def test_b_distributed_spraying_triggers_account_throttle(app_ctx, client, prod_redis):
    username = _make_user(app_ctx)

    statuses = []
    for i in range(5):
        ip = f"198.51.100.{i + 1}"
        r = _login(client, username, "WrongPassword!", ip)
        statuses.append(r.status_code)
    assert statuses == [401, 401, 401, 401, 401], statuses

    # 6th attempt, yet another distinct source IP, WITH THE CORRECT
    # PASSWORD -- must still be rejected, because the account itself (not
    # any one IP) is now throttled.
    r6 = _login(client, username, _PASSWORD, "198.51.100.99")
    assert r6.status_code == 401, r6.get_json()
    body = r6.get_json() or {}
    assert body.get("message") == "Invalid credentials"
    assert "access_token" not in body
    assert "token" not in body


# ---------------------------------------------------------------------------
# C. Failed attempts increment atomically under concurrency
# ---------------------------------------------------------------------------


def test_c_concurrent_failures_from_distinct_ips_are_not_lost(app_ctx, client, prod_redis):
    username = _make_user(app_ctx)
    n_workers = 5  # == _ACCOUNT_LOGIN_MAX_FAILURES
    barrier = threading.Barrier(n_workers)
    results: list[int] = []
    results_lock = threading.Lock()

    def worker(i):
        barrier.wait()
        r = _login(client, username, "WrongPassword!", f"192.0.2.{i + 1}")
        with results_lock:
            results.append(r.status_code)

    threads = [threading.Thread(target=worker, args=(i,)) for i in range(n_workers)]
    for t in threads:
        t.start()
    for t in threads:
        t.join()

    assert sorted(results) == [401] * n_workers, results

    # If even one of the 5 concurrent increments had been lost to a race,
    # the counter would sit at 4 (< threshold) and this correct-password
    # attempt from a 6th distinct IP would succeed (200). It must not.
    r_check = _login(client, username, _PASSWORD, "192.0.2.250")
    assert r_check.status_code == 401, r_check.get_json()


# ---------------------------------------------------------------------------
# D. Successful login clears/resets the account failure state
# ---------------------------------------------------------------------------


def test_d_successful_login_resets_failure_state(app_ctx, client, prod_redis):
    username = _make_user(app_ctx)

    # 4 failures (below the 5-failure threshold) from 4 distinct IPs.
    for i in range(4):
        r = _login(client, username, "WrongPassword!", f"203.0.113.{20 + i}")
        assert r.status_code == 401

    # Correct password from a 5th distinct IP -> succeeds and must reset
    # the counter/lock.
    r_ok = _login(client, username, _PASSWORD, "203.0.113.30")
    assert r_ok.status_code == 200, r_ok.get_json()
    body = r_ok.get_json()
    assert body["message"] == "Login successful"
    assert "access_token" in body

    # 4 MORE failures from 4 fresh distinct IPs. If the counter had NOT
    # been reset, this would be cumulative failure #5-#8 and would already
    # be locked; it must not be.
    for i in range(4):
        r = _login(client, username, "WrongPassword!", f"203.0.113.{40 + i}")
        assert r.status_code == 401

    r_ok2 = _login(client, username, _PASSWORD, "203.0.113.50")
    assert r_ok2.status_code == 200, r_ok2.get_json()


# ---------------------------------------------------------------------------
# E. The temporary throttle expires after its configured TTL/window
# ---------------------------------------------------------------------------


def test_e_throttle_expires_after_ttl(app_ctx, client, prod_redis):
    username = _make_user(app_ctx)

    for i in range(5):
        r = _login(client, username, "WrongPassword!", f"198.18.0.{i + 1}")
        assert r.status_code == 401

    r_locked = _login(client, username, _PASSWORD, "198.18.0.99")
    assert r_locked.status_code == 401, r_locked.get_json()

    # Simulate the lock's (and counter's) TTL having elapsed.
    hashed = _account_hash_for_user(app_ctx, username)
    prod_redis.reset_key(f"acct_lock:{hashed}")
    prod_redis.reset_key(f"acct_fail:{hashed}")

    r_after = _login(client, username, _PASSWORD, "198.18.0.100")
    assert r_after.status_code == 200, r_after.get_json()


# ---------------------------------------------------------------------------
# F. Different accounts have independent counters
# ---------------------------------------------------------------------------


def test_f_different_accounts_have_independent_counters(app_ctx, client, prod_redis):
    u1 = _make_user(app_ctx)
    u2 = _make_user(app_ctx)

    for i in range(5):
        r = _login(client, u1, "WrongPassword!", f"192.0.2.{100 + i}")
        assert r.status_code == 401

    r1_locked = _login(client, u1, _PASSWORD, "192.0.2.199")
    assert r1_locked.status_code == 401

    r2_ok = _login(client, u2, _PASSWORD, "192.0.2.200")
    assert r2_ok.status_code == 200, r2_ok.get_json()


# ---------------------------------------------------------------------------
# G. Different normalized identifiers resolving to the SAME account share
#    one bucket (no split-identifier bypass)
# ---------------------------------------------------------------------------


def test_g_equivalent_identifiers_share_one_bucket(app_ctx, client, prod_redis):
    username = _make_user(app_ctx)
    phone = _user_phone(app_ctx, username)

    # 3 failures via the phone number, then 2 more via the username -- the
    # SAME underlying account, addressed two different ways.
    for i in range(3):
        r = _login(client, phone, "WrongPassword!", f"203.0.113.{60 + i}")
        assert r.status_code == 401
    for i in range(2):
        r = _login(client, username, "WrongPassword!", f"203.0.113.{70 + i}")
        assert r.status_code == 401

    # Combined count is 5 -> locked, regardless of which identifier form is
    # used for the next attempt.
    r_locked_by_username = _login(client, username, _PASSWORD, "203.0.113.80")
    assert r_locked_by_username.status_code == 401, r_locked_by_username.get_json()

    r_locked_by_phone = _login(client, phone, _PASSWORD, "203.0.113.81")
    assert r_locked_by_phone.status_code == 401, r_locked_by_phone.get_json()


# ---------------------------------------------------------------------------
# H. Mobile (User) login is protected
# ---------------------------------------------------------------------------


def test_h_user_login_is_protected(app_ctx, client, prod_redis):
    username = _make_user(app_ctx)
    for i in range(5):
        r = _login(client, username, "WrongPassword!", f"172.20.0.{i + 1}")
        assert r.status_code == 401
    r_locked = _login(client, username, _PASSWORD, "172.20.0.99")
    assert r_locked.status_code == 401
    assert (r_locked.get_json() or {}).get("message") == "Invalid credentials"


# ---------------------------------------------------------------------------
# I. Admin login (account_scope=admin, same route) is protected
# ---------------------------------------------------------------------------


def test_i_admin_login_is_protected(app_ctx, client, prod_redis):
    admin = _make_admin(app_ctx)

    for i in range(5):
        r = _login(
            client,
            admin["username"],
            "WrongPassword!",
            f"172.16.0.{i + 1}",
            account_scope="admin",
        )
        assert r.status_code == 401, (i, r.get_json())

    r_locked = _login(
        client,
        admin["username"],
        admin["password"],
        "172.16.0.99",
        account_scope="admin",
    )
    assert r_locked.status_code == 401, r_locked.get_json()
    body = r_locked.get_json() or {}
    assert body.get("message") == "Invalid credentials"
    assert "access_token" not in body


# ---------------------------------------------------------------------------
# J. Unknown-account behavior remains generic (no enumeration leak)
# ---------------------------------------------------------------------------


def test_j_unknown_account_never_throttled_and_stays_generic(app_ctx, client, prod_redis):
    fake_username = f"nope_{uuid.uuid4().hex[:10]}"

    statuses = []
    bodies = []
    for i in range(8):  # well beyond the 5-failure account threshold
        r = _login(client, fake_username, "whatever", f"10.0.0.{i + 1}")
        statuses.append(r.status_code)
        bodies.append(r.get_json() or {})

    assert all(s == 401 for s in statuses), statuses
    assert all(b.get("message") == "Invalid credentials" for b in bodies)
    # Every response body is identical -- no signal distinguishing "never
    # existed" from "exists but throttled" leaks through.
    distinct_bodies = {tuple(sorted(b.items())) for b in bodies}
    assert len(distinct_bodies) == 1, bodies


# ---------------------------------------------------------------------------
# N. Existing success/error response shapes remain compatible
# ---------------------------------------------------------------------------


def test_n_success_response_shape_is_unchanged(app_ctx, client, prod_redis):
    username = _make_user(app_ctx)
    r = _login(client, username, _PASSWORD, "203.0.113.199")
    assert r.status_code == 200, r.get_json()
    body = r.get_json()
    assert body["message"] == "Login successful"
    assert set(["message", "token", "access_token", "refresh_token", "user"]) <= set(
        body.keys()
    )


def test_n_wrong_password_error_shape_is_unchanged(app_ctx, client, prod_redis):
    username = _make_user(app_ctx)
    r = _login(client, username, "WrongPassword!", "203.0.113.220")
    assert r.status_code == 401
    body = r.get_json()
    assert body == {"message": "Invalid credentials"}


# ---------------------------------------------------------------------------
# Bonus: H-06 fail-closed policy applies to the new account throttle too
# ---------------------------------------------------------------------------


def test_fail_closed_when_redis_unavailable_for_account_throttle(app_ctx, monkeypatch):
    """Directly exercises `kk.security.check_account_login_throttle` (in
    isolation from the pre-existing per-IP `@rate_limit` decorator, which
    already has its own, unmodified H-06 test coverage) to prove the NEW
    account-throttle check independently follows the exact same
    fail-closed-in-production policy: when Redis is required but
    unavailable, it must return a 503 `rate_limiter_unavailable` response
    and report `locked=False` (the caller must use the error response, not
    silently treat an unreadable lock state as "not locked" and proceed to
    verify the password)."""
    app, *_ = app_ctx
    import kk.security as security_module

    monkeypatch.setenv("APP_ENV", "production")
    monkeypatch.setitem(app.config, "TESTING", False)
    monkeypatch.setattr(security_module, "_redis_client", lambda: _FakeRedisRaising())

    with app.app_context():
        locked, error_response = security_module.check_account_login_throttle(
            "user:m09-fail-closed-probe"
        )

    assert locked is False
    assert error_response is not None
    body, status = error_response
    assert status == 503
    payload = body.get_json()
    assert payload.get("code") == "rate_limiter_unavailable"


def test_full_login_route_fails_closed_when_redis_unavailable(app_ctx, client, monkeypatch):
    """End-to-end: with Redis entirely unreachable in a production-like
    config, `login()` must return 503 (not silently allow unlimited
    attempts through either the pre-existing per-IP layer or the new
    account layer)."""
    app, *_ = app_ctx
    import kk.security as security_module

    username = _make_user(app_ctx)

    monkeypatch.setenv("APP_ENV", "production")
    monkeypatch.setitem(app.config, "TESTING", False)
    monkeypatch.setattr(security_module, "_redis_client", lambda: _FakeRedisRaising())

    r = _login(client, username, _PASSWORD, "203.0.113.240")
    assert r.status_code == 503, r.get_json()
    assert (r.get_json() or {}).get("code") == "rate_limiter_unavailable"
