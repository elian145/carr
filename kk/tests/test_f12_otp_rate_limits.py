"""F-12: OTP/auth rate limiting must not punish everybody behind one shared
(carrier-grade NAT) IP, while abuse of one phone / one device / bulk abuse from
one IP stays bounded.

``check_rate_limit`` (and the new ``kk.rate_identity`` limiter) are no-ops under
``APP_ENV=testing`` / ``app.config['TESTING']``; like the M-09/BE-19 tests these
tests opt back in explicitly (production env + fake Redis, or development env +
in-process store) per test, so the default suite behaviour is unchanged.
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

SEND_URLS = ("/api/auth/phone/start", "/api/auth/send-verification", "/api/auth/send_otp")


@pytest.fixture(scope="module")
def app_ctx():
    tmp = tempfile.TemporaryDirectory(prefix="carlist_f12_", ignore_cleanup_errors=True)
    os.environ["APP_ENV"] = "testing"
    os.environ["SMS_PROVIDER"] = "console"
    os.environ["DB_PATH"] = os.path.join(tmp.name, "f12.db")

    from kk.app_factory import create_app

    app, *_ = create_app()
    from kk.models import db

    with app.app_context():
        db.drop_all()
        db.create_all()
    yield app
    with app.app_context():
        db.session.remove()
        db.engine.dispose()
    tmp.cleanup()


class FakeRedis:
    """Atomic (lock-protected) INCR/EXPIRE/TTL stand-in for a Redis server."""

    def __init__(self):
        self.counts: dict[str, int] = {}
        self.ttls: dict[str, int] = {}
        self._lock = threading.Lock()

    def incr(self, key):
        with self._lock:
            self.counts[key] = self.counts.get(key, 0) + 1
            return self.counts[key]

    def expire(self, key, seconds):
        with self._lock:
            self.ttls[key] = int(seconds)
            return True

    def ttl(self, key):
        with self._lock:
            return self.ttls.get(key, -1)


class RaisingRedis:
    def incr(self, key):
        raise ConnectionError("redis down")

    expire = ttl = incr


@pytest.fixture
def prod(app_ctx, monkeypatch):
    """Production env + fake Redis, limiter ENABLED."""
    import kk.rate_identity as ri
    import kk.routes.auth as auth_module
    import kk.security as security_module
    import kk.sms_service as sms_module

    for name in list(os.environ):
        if name.startswith(("OTP_SEND_", "OTP_VERIFY_")) or name == "RATE_LIMIT_SEND_OTP":
            monkeypatch.delenv(name)
    monkeypatch.setenv("APP_ENV", "production")
    monkeypatch.setitem(app_ctx.config, "TESTING", False)
    fake = FakeRedis()
    monkeypatch.setattr(security_module, "_redis_client", lambda: fake)
    monkeypatch.setattr(auth_module, "_OTP_RESEND_COOLDOWN_SECONDS", 0)
    monkeypatch.setattr(sms_module, "send_verification_sms_result", lambda *a, **k: (True, "ok"))
    ri.reset_in_memory_state()
    client = app_ctx.test_client()
    client.fake_redis = fake
    return client


@pytest.fixture
def dev_memory(app_ctx, monkeypatch):
    """Development env, in-process store, limiter ENABLED."""
    import kk.rate_identity as ri
    import kk.routes.auth as auth_module
    import kk.security as security_module
    import kk.sms_service as sms_module

    for name in list(os.environ):
        if name.startswith(("OTP_SEND_", "OTP_VERIFY_")) or name == "RATE_LIMIT_SEND_OTP":
            monkeypatch.delenv(name)
    monkeypatch.setenv("APP_ENV", "development")
    monkeypatch.setitem(app_ctx.config, "TESTING", False)
    monkeypatch.setattr(security_module, "_redis_client", lambda: None)
    monkeypatch.setattr(auth_module, "_OTP_RESEND_COOLDOWN_SECONDS", 0)
    monkeypatch.setattr(sms_module, "send_verification_sms_result", lambda *a, **k: (True, "ok"))
    ri.reset_in_memory_state()
    return app_ctx.test_client()


def _phone() -> str:
    return f"077{uuid.uuid4().int % 10**8:08d}"


def _post(client, url, phone=None, *, ip="10.0.0.1", device=None, body=None, **extra):
    payload = {"phone_number": phone} if body is None else body
    if extra:
        payload = {**payload, **extra}
    headers = {"X-Device-Id": device} if device else {}
    return client.post(
        url, json=payload, headers=headers, environ_overrides={"REMOTE_ADDR": ip}
    )


def _is_limited(resp) -> bool:
    return resp.status_code == 429 and (resp.get_json() or {}).get("code") == "otp_rate_limited"


def _assert_limited_consistently(resp):
    assert resp.status_code == 429
    body = resp.get_json()
    assert body["code"] == "otp_rate_limited"
    assert int(resp.headers["Retry-After"]) >= 1
    assert body["retry_after"] == int(resp.headers["Retry-After"])


# ---------------------------------------------------------------------------
# Shared (carrier NAT) IP
# ---------------------------------------------------------------------------


def test_shared_ip_30_distinct_phones_each_get_their_first_otp(prod):
    for _ in range(30):
        resp = _post(prod, SEND_URLS[0], _phone(), ip="37.236.1.1")
        assert resp.status_code == 200, resp.get_data(as_text=True)


@pytest.mark.parametrize("url", SEND_URLS)
def test_shared_ip_distinct_phones_all_endpoints(prod, url):
    for _ in range(10):
        resp = _post(prod, url, _phone(), ip="37.236.1.2")
        assert not _is_limited(resp), (url, resp.get_data(as_text=True))


def test_same_phone_blocked_after_phone_limit_regardless_of_ip(prod):
    phone = _phone()
    # production default: 3 per 10 minutes per phone, each from a different IP
    for i in range(3):
        resp = _post(prod, SEND_URLS[0], phone, ip=f"10.1.0.{i + 1}")
        assert resp.status_code == 200, resp.get_data(as_text=True)
    for i in range(4, 9):
        resp = _post(prod, SEND_URLS[0], phone, ip=f"10.1.0.{i}")
        _assert_limited_consistently(resp)


def test_phone_budget_is_shared_across_send_endpoints_without_double_counting(prod):
    phone = _phone()
    # three requests through three different endpoints (send_otp internally
    # re-enters send-verification: must count ONCE) all pass ...
    for url in SEND_URLS:
        resp = _post(prod, url, phone)
        assert not _is_limited(resp), (url, resp.get_data(as_text=True))
    # ... and the 4th, through any endpoint, is limited
    for url in SEND_URLS:
        _assert_limited_consistently(_post(prod, url, phone, ip="10.2.0.9"))


@pytest.mark.parametrize(
    "variants",
    [
        ("07701234567", "7701234567", "+9647701234567", "009647701234567"),
        ("0770 123 4567", "0770-123-4567", "9647701234567", "٠٧٧٠١٢٣٤٥٦٧"),
    ],
)
def test_format_variants_of_one_phone_share_one_budget(prod, variants):
    # 3 allowed in total across all variants, 4th limited
    results = [
        _is_limited(_post(prod, SEND_URLS[0], v, ip=f"10.3.0.{i + 1}"))
        for i, v in enumerate(variants)
    ]
    assert results == [False, False, False, True], results


def test_device_limit_independent_of_phone_and_ip(prod):
    device = "dev-" + uuid.uuid4().hex
    # production default: 5 per 10 minutes per device (each a different phone/IP)
    for i in range(5):
        resp = _post(prod, SEND_URLS[0], _phone(), ip=f"10.4.0.{i + 1}", device=device)
        assert resp.status_code == 200, resp.get_data(as_text=True)
    _assert_limited_consistently(
        _post(prod, SEND_URLS[0], _phone(), ip="10.4.0.99", device=device)
    )
    # another device on the same IP is unaffected
    other = _post(prod, SEND_URLS[0], _phone(), ip="10.4.0.1", device="dev-" + uuid.uuid4().hex)
    assert other.status_code == 200


def test_invalid_device_id_is_ignored_not_a_bypass_or_shared_bucket(prod):
    # junk / too short ids are treated as "no device": phone + IP still apply
    phone = _phone()
    for i in range(3):
        assert not _is_limited(_post(prod, SEND_URLS[0], phone, device="x", ip=f"10.5.0.{i}"))
    _assert_limited_consistently(_post(prod, SEND_URLS[0], phone, device="x", ip="10.5.0.9"))
    # and 20 requests with the same junk id for distinct phones are not device-limited
    for _ in range(20):
        assert not _is_limited(_post(prod, SEND_URLS[0], _phone(), device="bad id!", ip="10.5.1.1"))


def test_ip_ceiling_bounds_bulk_abuse_from_one_ip_default_is_100(prod):
    ip = "198.51.100.7"
    seen_limited_at = None
    for n in range(1, 130):
        resp = _post(prod, SEND_URLS[0], _phone(), ip=ip)
        if _is_limited(resp):
            seen_limited_at = n
            _assert_limited_consistently(resp)
            break
    assert seen_limited_at == 101


def test_ip_ceiling_env_override_and_rejected_requests_do_not_burn_ip_budget(prod, monkeypatch):
    monkeypatch.setenv("OTP_SEND_IP_MAX", "5")
    ip = "198.51.100.8"
    victim = _phone()
    for _ in range(3):
        assert _post(prod, SEND_URLS[0], victim, ip=ip).status_code == 200  # IP count 3
    # 25 more hits on the exhausted phone are rejected by the phone limit and
    # must NOT consume the shared IP budget ...
    for _ in range(25):
        assert _is_limited(_post(prod, SEND_URLS[0], victim, ip=ip))
    # ... so two other users behind the same IP still succeed ...
    for _ in range(2):
        assert _post(prod, SEND_URLS[0], _phone(), ip=ip).status_code == 200  # IP count 5
    # ... until the ceiling is genuinely reached
    _assert_limited_consistently(_post(prod, SEND_URLS[0], _phone(), ip=ip))


def test_daily_phone_cap_bounds_slow_sms_pumping_of_one_number(prod, monkeypatch):
    # short window effectively unlimited; the 24h cap (default 10) must hold
    monkeypatch.setenv("OTP_SEND_PHONE_MAX", "1000")
    phone = _phone()
    for i in range(10):
        assert not _is_limited(_post(prod, SEND_URLS[0], phone, ip=f"10.6.0.{i}"))
    resp = _post(prod, SEND_URLS[0], phone, ip="10.6.0.99")
    _assert_limited_consistently(resp)
    assert int(resp.headers["Retry-After"]) > 3600  # the 24h window, not the 10 min one


# ---------------------------------------------------------------------------
# Verify endpoints (OTP brute force)
# ---------------------------------------------------------------------------


@pytest.mark.parametrize("url", ("/api/auth/phone/verify", "/api/auth/verify-phone"))
def test_verify_attempts_per_phone_bounded_across_many_ips(prod, url):
    phone = _phone()
    body = {"phone_number": phone, "code": "123456", "verification_code": "123456"}
    # production default: 10 per 15 min per phone, however many IPs are used
    for i in range(10):
        resp = _post(prod, url, body=body, ip=f"10.7.{i}.1")
        assert not _is_limited(resp), resp.get_data(as_text=True)
    for i in range(10, 25):
        _assert_limited_consistently(_post(prod, url, body=body, ip=f"10.7.{i}.1"))


def test_verify_daily_cap_per_phone(prod, monkeypatch):
    monkeypatch.setenv("OTP_VERIFY_PHONE_MAX", "1000")
    phone = _phone()
    body = {"phone_number": phone, "code": "123456"}
    for i in range(30):
        assert not _is_limited(_post(prod, "/api/auth/phone/verify", body=body, ip=f"10.8.0.{i}"))
    resp = _post(prod, "/api/auth/phone/verify", body=body, ip="10.8.1.1")
    _assert_limited_consistently(resp)
    assert int(resp.headers["Retry-After"]) > 3600


def test_verify_shared_ip_many_users_not_locked_out(prod):
    # was: 10 verify attempts / 15 min per IP => 11th user behind the NAT blocked
    for _ in range(40):
        resp = _post(
            prod, "/api/auth/phone/verify",
            body={"phone_number": _phone(), "code": "123456"}, ip="37.236.9.9",
        )
        assert not _is_limited(resp)


def test_verify_ip_ceiling_default_200(prod):
    ip = "198.51.100.9"
    limited_at = None
    for n in range(1, 230):
        resp = _post(
            prod, "/api/auth/phone/verify",
            body={"phone_number": _phone(), "code": "123456"}, ip=ip,
        )
        if _is_limited(resp):
            limited_at = n
            break
    assert limited_at == 201


def test_verify_and_send_budgets_are_independent(prod):
    phone = _phone()
    for i in range(3):
        assert _post(prod, SEND_URLS[0], phone, ip=f"10.9.0.{i}").status_code == 200
    resp = _post(prod, "/api/auth/phone/verify", body={"phone_number": phone, "code": "123456"})
    assert not _is_limited(resp)


# ---------------------------------------------------------------------------
# Garbage / missing identity
# ---------------------------------------------------------------------------


def test_missing_or_invalid_phone_still_hits_ip_ceiling(prod, monkeypatch):
    monkeypatch.setenv("OTP_SEND_IP_MAX", "6")
    ip = "198.51.100.10"
    bodies = [{}, {"phone_number": ""}, {"phone_number": "abc"}, {"phone": None},
              {"phone_number": ["0770"]}, {"phone_number": {"a": 1}}]
    for b in bodies:
        resp = _post(prod, SEND_URLS[0], body=b, ip=ip)
        assert not _is_limited(resp)
        assert resp.status_code in (400, 500)  # rejected by the handler, never an unlimited send
    _assert_limited_consistently(_post(prod, SEND_URLS[0], body={}, ip=ip))


def test_non_json_body_cannot_bypass_ip_ceiling(prod, monkeypatch):
    monkeypatch.setenv("OTP_SEND_IP_MAX", "3")
    ip = "198.51.100.11"
    for _ in range(3):
        resp = prod.post(SEND_URLS[0], data="not json", environ_overrides={"REMOTE_ADDR": ip})
        assert not _is_limited(resp)
    resp = prod.post(SEND_URLS[0], data="not json", environ_overrides={"REMOTE_ADDR": ip})
    _assert_limited_consistently(resp)


def test_garbage_decoration_cannot_dodge_phone_limit(prod):
    phone = f"0770{uuid.uuid4().int % 10**7:07d}"
    decorated = [phone, f" {phone} ", f"{phone}abc", f"+964 {phone[1:]}", f"({phone[:4]}) {phone[4:]}"]
    flags = [_is_limited(_post(prod, SEND_URLS[0], p, ip=f"10.10.0.{i}")) for i, p in enumerate(decorated)]
    assert flags == [False, False, False, True, True], flags


def test_phone_key_prefers_phone_number_like_the_handler(prod):
    # handler uses phone_number first, then phone: an attacker cannot spend the
    # budget of one number while sending to another by adding a decoy field.
    phone = _phone()
    for i in range(3):
        _post(prod, SEND_URLS[0], body={"phone_number": phone, "phone": _phone()}, ip=f"10.11.0.{i}")
    _assert_limited_consistently(
        _post(prod, SEND_URLS[0], body={"phone_number": phone, "phone": _phone()}, ip="10.11.1.1")
    )


# ---------------------------------------------------------------------------
# Concurrency
# ---------------------------------------------------------------------------


def _hammer(app, make_kwargs, scope, n):
    from kk.rate_identity import check_otp_rate_limit

    barrier = threading.Barrier(n)
    results: list = [None] * n

    def worker(i):
        with app.test_request_context(**make_kwargs(i)):
            barrier.wait()
            results[i] = check_otp_rate_limit(scope)

    threads = [threading.Thread(target=worker, args=(i,)) for i in range(n)]
    for t in threads:
        t.start()
    for t in threads:
        t.join()
    return results


@pytest.mark.parametrize("store", ["redis", "memory"])
def test_concurrent_requests_for_one_phone_never_exceed_limit(app_ctx, prod, monkeypatch, store):
    import kk.security as security_module

    monkeypatch.setenv("OTP_SEND_PHONE_MAX", "3")  # production default, also for dev env
    if store == "memory":
        monkeypatch.setenv("APP_ENV", "development")
        monkeypatch.setattr(security_module, "_redis_client", lambda: None)
    phone = _phone()

    def kwargs(i):
        return {
            "path": SEND_URLS[0],
            "method": "POST",
            "json": {"phone_number": phone},
            "environ_overrides": {"REMOTE_ADDR": f"10.20.{i}.1"},
        }

    results = _hammer(app_ctx, kwargs, "send", 40)
    allowed = sum(1 for r in results if r is None)
    assert allowed == 3  # exactly the per-phone limit, from 40 racing requests/40 IPs
    assert all(r is None or r.status_code == 429 for r in results)


def test_concurrent_requests_for_one_device_never_exceed_limit(app_ctx, prod):
    device = "dev-" + uuid.uuid4().hex

    def kwargs(i):
        return {
            "path": SEND_URLS[0],
            "method": "POST",
            "json": {"phone_number": _phone()},
            "headers": {"X-Device-Id": device},
            "environ_overrides": {"REMOTE_ADDR": f"10.21.{i}.1"},
        }

    results = _hammer(app_ctx, kwargs, "send", 30)
    assert sum(1 for r in results if r is None) == 5


def test_concurrent_http_requests_for_one_phone_at_most_limit_pass(app_ctx, prod):
    phone = _phone()
    n = 12
    statuses: list = [None] * n
    barrier = threading.Barrier(n)

    def worker(i):
        c = app_ctx.test_client()
        barrier.wait()
        resp = _post(c, SEND_URLS[0], phone, ip=f"10.22.{i}.1")
        statuses[i] = _is_limited(resp)

    threads = [threading.Thread(target=worker, args=(i,)) for i in range(n)]
    for t in threads:
        t.start()
    for t in threads:
        t.join()
    assert None not in statuses
    assert statuses.count(False) == 3
    assert statuses.count(True) == n - 3


# ---------------------------------------------------------------------------
# Store semantics: fail closed, no PII in keys, TTL repair, testing no-op
# ---------------------------------------------------------------------------


def test_production_without_redis_fails_closed_503(prod, monkeypatch):
    import kk.security as security_module

    monkeypatch.setattr(security_module, "_redis_client", lambda: None)
    resp = _post(prod, SEND_URLS[0], _phone())
    assert resp.status_code == 503
    assert resp.get_json()["code"] == "rate_limiter_unavailable"
    resp = _post(prod, "/api/auth/phone/verify", body={"phone_number": _phone(), "code": "123456"})
    assert resp.status_code == 503


def test_production_redis_error_fails_closed_503(prod, monkeypatch):
    import kk.security as security_module

    monkeypatch.setattr(security_module, "_redis_client", lambda: RaisingRedis())
    resp = _post(prod, SEND_URLS[0], _phone())
    assert resp.status_code == 503
    assert resp.get_json()["code"] == "rate_limiter_unavailable"


def test_development_memory_fallback_enforces_limits(dev_memory):
    # dev defaults: 30 per phone window
    phone = _phone()
    flags = [_is_limited(_post(dev_memory, SEND_URLS[0], phone)) for _ in range(32)]
    assert flags.count(False) == 30 and flags[-1] is True


def test_redis_keys_never_contain_raw_phone_device_or_ip(prod):
    phone = "07701234599"
    device = "device-secret-12345"
    _post(prod, SEND_URLS[0], phone, ip="203.0.113.77", device=device)
    keys = list(prod.fake_redis.counts)
    assert keys
    blob = " ".join(keys)
    assert "7701234599" not in blob and device not in blob
    assert all(k.startswith("otp:send:") for k in keys)


def test_counter_without_ttl_is_repaired_when_blocking(prod):
    phone = _phone()
    for _ in range(3):
        _post(prod, SEND_URLS[0], phone)
    for key in list(prod.fake_redis.ttls):
        prod.fake_redis.ttls.pop(key)  # simulate crash between INCR and EXPIRE
    resp = _post(prod, SEND_URLS[0], phone)
    _assert_limited_consistently(resp)
    assert all(v > 0 for v in prod.fake_redis.ttls.values())


def test_limiter_is_noop_under_testing_env(app_ctx, monkeypatch):
    import kk.security as security_module

    monkeypatch.setenv("APP_ENV", "testing")
    monkeypatch.setattr(security_module, "_redis_client", lambda: None)
    client = app_ctx.test_client()
    phone = _phone()
    for _ in range(40):
        assert not _is_limited(_post(client, SEND_URLS[0], phone))


# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------


def test_production_defaults_and_legacy_env(monkeypatch):
    from kk.rate_identity import _limits_for

    for name in list(os.environ):
        if name.startswith(("OTP_SEND_", "OTP_VERIFY_")) or name == "RATE_LIMIT_SEND_OTP":
            monkeypatch.delenv(name)
    monkeypatch.setenv("APP_ENV", "production")
    assert dict(_limits_for("send")) == {
        "phone": [(3, 600), (10, 86400)],
        "device": [(5, 600), (30, 86400)],
        "ip": [(100, 600), (2000, 86400)],
    }
    assert dict(_limits_for("verify")) == {
        "phone": [(10, 900), (30, 86400)],
        "device": [(20, 900)],
        "ip": [(200, 900)],
    }
    monkeypatch.setenv("RATE_LIMIT_SEND_OTP", "7")
    assert dict(_limits_for("send"))["phone"][0] == (7, 600)
    monkeypatch.setenv("OTP_SEND_PHONE_MAX", "4")
    assert dict(_limits_for("send"))["phone"][0] == (4, 600)
    monkeypatch.setenv("OTP_SEND_PHONE_MAX", "garbage")
    assert dict(_limits_for("send"))["phone"][0] == (7, 600)
