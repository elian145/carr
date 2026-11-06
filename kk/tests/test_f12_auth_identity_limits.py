"""F-12 part 2: identity-aware limits on the remaining unauthenticated auth
endpoints (login, forgot-password, signup, send-email-verification).

Same opt-in style as ``test_f12_otp_rate_limits.py``: the limiter (like the
legacy ``check_rate_limit``) is a no-op under ``APP_ENV=testing`` so each test
switches to production + fake Redis (or development + in-process store).

Threat model being pinned down:
* many DIFFERENT identities behind ONE (carrier NAT) IP keep working up to the
  IP ceiling;
* the SAME identity is blocked no matter how many IPs / device ids are rotated
  (``X-Device-Id`` is client asserted and never an escape hatch);
* the M-09 per-account failure throttle is unchanged and still bounds password
  guesses against one account across many IPs;
* forgot-password stays enumeration free and cannot SMS-bomb one number;
* reset-password / verify-email keep their legacy per-IP limits.
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

_PASSWORD = "CorrectHorse!42"
_ENV_PREFIXES = ("OTP_SEND_", "OTP_VERIFY_", "AUTH_LOGIN_", "AUTH_FORGOT_", "AUTH_SIGNUP_", "AUTH_EMAIL_SEND_")


@pytest.fixture(scope="module")
def app_ctx():
    tmp = tempfile.TemporaryDirectory(prefix="carlist_f12b_", ignore_cleanup_errors=True)
    os.environ["APP_ENV"] = "testing"
    os.environ["SMS_PROVIDER"] = "console"
    os.environ["DB_PATH"] = os.path.join(tmp.name, "f12b.db")

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

    # login throttle (M-09) primitives
    def exists(self, key):
        with self._lock:
            return 1 if key in self.counts else 0

    def set(self, key, value, ex=None):
        with self._lock:
            self.counts[key] = 1
            if ex:
                self.ttls[key] = int(ex)
            return True

    def delete(self, *keys):
        with self._lock:
            for k in keys:
                self.counts.pop(k, None)
                self.ttls.pop(k, None)
            return len(keys)


class RaisingRedis:
    def incr(self, key):
        raise ConnectionError("redis down")

    expire = ttl = exists = set = delete = incr


def _clean_env(monkeypatch):
    for name in list(os.environ):
        if name.startswith(_ENV_PREFIXES) or name in ("RATE_LIMIT_SEND_OTP", "RATE_LIMIT_SIGNUP"):
            monkeypatch.delenv(name)


class _SmsCounter:
    def __init__(self):
        self.sent: list[str] = []
        self._lock = threading.Lock()

    def __call__(self, phone, token, locale=None, **kw):
        with self._lock:
            self.sent.append(str(phone))
        return True


@pytest.fixture
def prod(app_ctx, monkeypatch):
    """Production env + fake Redis, limiters ENABLED."""
    import kk.rate_identity as ri
    import kk.security as security_module
    import kk.sms_service as sms_module

    _clean_env(monkeypatch)
    monkeypatch.setenv("APP_ENV", "production")
    monkeypatch.setitem(app_ctx.config, "TESTING", False)
    fake = FakeRedis()
    monkeypatch.setattr(security_module, "_redis_client", lambda: fake)
    sms = _SmsCounter()
    monkeypatch.setattr(sms_module, "send_password_reset_sms", sms)
    ri.reset_in_memory_state()
    client = app_ctx.test_client()
    client.fake_redis = fake
    client.sms = sms
    return client


@pytest.fixture
def dev_memory(app_ctx, monkeypatch):
    import kk.rate_identity as ri
    import kk.security as security_module

    _clean_env(monkeypatch)
    monkeypatch.setenv("APP_ENV", "development")
    monkeypatch.setitem(app_ctx.config, "TESTING", False)
    monkeypatch.setattr(security_module, "_redis_client", lambda: None)
    ri.reset_in_memory_state()
    return app_ctx.test_client()


# ---------------------------------------------------------------------------
# helpers
# ---------------------------------------------------------------------------


def _phone() -> str:
    return f"077{uuid.uuid4().int % 10**8:08d}"


def _make_user(app_ctx, *, phone=None, email=None, password=_PASSWORD, with_password=True):
    from kk.models import User, db
    from kk.routes.auth import _normalize_phone

    phone = _normalize_phone(phone or _phone())
    with app_ctx.app_context():
        user = User(
            username=f"f12b_{uuid.uuid4().hex[:10]}",
            phone_number=phone,
            first_name="F12",
            last_name="Test",
            email=email,
            is_active=True,
            is_verified=True,
            phone_verified=True,
            public_id=f"pub-{uuid.uuid4().hex[:12]}",
        )
        if with_password:
            user.set_password(password)
        db.session.add(user)
        db.session.commit()
        return {"id": user.id, "username": user.username, "phone": phone, "public_id": user.public_id}


def _login(client, ident, password="WrongPassword!1", *, ip="10.0.0.1", device=None, body=None):
    payload = {"username": ident, "password": password} if body is None else body
    headers = {"X-Device-Id": device} if device else {}
    return client.post(
        "/api/auth/login", json=payload, headers=headers, environ_overrides={"REMOTE_ADDR": ip}
    )


def _forgot(client, phone, *, ip="10.0.0.1", device=None, field="phone_number"):
    headers = {"X-Device-Id": device} if device else {}
    return client.post(
        "/api/auth/forgot-password",
        json={field: phone},
        headers=headers,
        environ_overrides={"REMOTE_ADDR": ip},
    )


def _signup(client, body, *, ip="10.0.0.1", device=None):
    headers = {"X-Device-Id": device} if device else {}
    return client.post(
        "/api/auth/signup", json=body, headers=headers, environ_overrides={"REMOTE_ADDR": ip}
    )


def _is_limited(resp) -> bool:
    return resp.status_code == 429 and (resp.get_json() or {}).get("code") == "auth_rate_limited"


def _assert_limited_consistently(resp):
    assert resp.status_code == 429
    body = resp.get_json()
    assert body["code"] == "auth_rate_limited"
    assert "Rate limit exceeded" in body["message"]
    assert int(resp.headers["Retry-After"]) >= 1
    assert body["retry_after"] == int(resp.headers["Retry-After"])


def _ips(prefix: str, n: int):
    return [f"{prefix}.{i // 250}.{i % 250 + 1}" for i in range(n)]


# ---------------------------------------------------------------------------
# LOGIN
# ---------------------------------------------------------------------------


def test_login_shared_ip_many_distinct_identities_all_served_up_to_ip_ceiling(prod):
    # 60 different identifiers behind one carrier IP: none of them is limited
    # (the old per-IP limit stopped everybody after 10).
    for _ in range(60):
        resp = _login(prod, f"nobody_{uuid.uuid4().hex[:12]}", ip="37.236.9.9")
        assert resp.status_code == 401, resp.get_data(as_text=True)


def test_login_shared_ip_real_users_can_all_sign_in(app_ctx, prod):
    users = [_make_user(app_ctx) for _ in range(12)]
    for u in users:
        resp = _login(prod, u["username"], _PASSWORD, ip="37.236.9.10")
        assert resp.status_code == 200, resp.get_data(as_text=True)


def test_login_same_identifier_blocked_regardless_of_ip(prod):
    ident = f"victim_{uuid.uuid4().hex[:8]}"
    for ip in _ips("10.1", 10):
        assert _login(prod, ident, ip=ip).status_code == 401
    resp = _login(prod, ident, ip="198.51.100.77")  # a never-seen IP
    _assert_limited_consistently(resp)


def test_login_identifier_spellings_share_one_bucket(prod):
    base = "Alice.Smith"
    spellings = [
        base,
        base.lower(),
        base.upper(),
        f"  {base}  ",
        base[:5] + "\u200b" + base[5:],  # zero-width space
        "\uff21lice.Smith",  # fullwidth A (NFKC)
    ]
    for i in range(10):
        _login(prod, spellings[i % len(spellings)], ip=f"10.2.0.{i + 1}")
    _assert_limited_consistently(_login(prod, spellings[3], ip="10.2.9.9"))


@pytest.mark.parametrize(
    "variants",
    [
        ["07701234501", "7701234501", "+9647701234501", "009647701234501", "+964 770 123 4501", "0770-123-4501"],
        ["07701234502", "\u0660\u0667\u0667\u0660\u0661\u0662\u0663\u0664\u0665\u0660\u0662"],  # Arabic-Indic digits
    ],
)
def test_login_phone_format_variants_share_one_bucket(prod, variants):
    for i in range(10):
        _login(prod, variants[i % len(variants)], ip=f"10.3.0.{i + 1}")
    _assert_limited_consistently(_login(prod, variants[0], ip="10.3.9.9"))


def test_login_brute_force_across_many_ips_bounded_per_account(app_ctx, prod, monkeypatch):
    """100 IPs guessing one account: the M-09 throttle (unchanged) caps real
    password verifications at 5, and the identifier limiter ends the attempts
    at 10 - the account is never open to an unbounded guess budget."""
    from kk.models import User

    user = _make_user(app_ctx)
    calls = {"n": 0}
    real = User.check_password

    def counting(self, pw):
        calls["n"] += 1
        return real(self, pw)

    monkeypatch.setattr(User, "check_password", counting)
    statuses = []
    for ip in _ips("10.4", 100):
        statuses.append(_login(prod, user["username"], f"guess-{ip}", ip=ip).status_code)
    assert calls["n"] == 5  # M-09: lock after 5 failures, no more bcrypt runs
    assert statuses.count(401) == 10 and statuses.count(429) == 90
    # even the right password is refused while the account is throttled/limited
    assert _login(prod, user["username"], _PASSWORD, ip="10.4.250.250").status_code in (401, 429)


def test_login_ip_ceiling_bounds_credential_stuffing_from_one_ip(prod):
    ip = "203.0.113.50"
    results = [_login(prod, f"stuff_{i}_{uuid.uuid4().hex[:6]}", ip=ip).status_code for i in range(101)]
    assert results[:100] == [401] * 100  # default ceiling: 100 / 15 min
    assert results[100] == 429
    _assert_limited_consistently(_login(prod, "another_identity", ip=ip))
    # a different IP is unaffected
    assert _login(prod, "another_identity", ip="203.0.113.51").status_code == 401


def test_login_ip_ceiling_env_override(prod, monkeypatch):
    monkeypatch.setenv("AUTH_LOGIN_IP_MAX", "5")
    ip = "203.0.113.60"
    out = [_login(prod, f"envid_{i}", ip=ip).status_code for i in range(6)]
    assert out == [401] * 5 + [429]


def test_login_rejected_by_identity_does_not_burn_ip_budget(prod, monkeypatch):
    monkeypatch.setenv("AUTH_LOGIN_IP_MAX", "15")
    ip = "203.0.113.70"
    ident = "hammered_" + uuid.uuid4().hex[:6]
    for _ in range(40):  # 10 pass, 30 rejected by the identifier limiter
        _login(prod, ident, ip=ip)
    # IP budget consumed only by the 10 that passed -> 5 more fresh identities fit
    assert [_login(prod, f"fresh_{i}", ip=ip).status_code for i in range(5)] == [401] * 5
    assert _login(prod, "fresh_over", ip=ip).status_code == 429


def test_login_device_id_rotation_does_not_bypass_identity_limit(prod):
    ident = "rot_" + uuid.uuid4().hex[:8]
    for i in range(10):
        assert _login(prod, ident, ip="10.5.0.1", device=f"device-{uuid.uuid4()}").status_code == 401
    _assert_limited_consistently(_login(prod, ident, ip="10.5.0.1", device=f"device-{uuid.uuid4()}"))


def test_login_device_id_rotation_does_not_bypass_ip_ceiling(prod, monkeypatch):
    monkeypatch.setenv("AUTH_LOGIN_IP_MAX", "12")
    ip = "203.0.113.80"
    out = [
        _login(prod, f"rd_{i}", ip=ip, device=f"device-{uuid.uuid4()}").status_code for i in range(13)
    ]
    assert out == [401] * 12 + [429]


def test_login_one_device_is_limited_across_many_identities_and_ips(prod):
    device = "dev-" + uuid.uuid4().hex
    out = [
        _login(prod, f"dv_{i}", ip=f"10.6.0.{i + 1}", device=device).status_code for i in range(31)
    ]
    assert out == [401] * 30 + [429]


def test_login_invalid_device_id_is_ignored_not_a_shared_bucket(prod):
    for i in range(40):
        resp = _login(prod, f"inv_{i}", ip=f"10.7.0.{i + 1}", device="bad id!")  # fails the format check
        assert resp.status_code == 401


@pytest.mark.parametrize("garbage", [None, True, False, [], ["a"], {"a": 1}, "", "   ", "\u200b\u200b", 0])
def test_login_garbage_identity_cannot_bypass_ip_ceiling(prod, monkeypatch, garbage):
    monkeypatch.setenv("AUTH_LOGIN_IP_MAX", "6")
    ip = "203.0.113.90"
    codes = []
    for _ in range(7):
        resp = _login(prod, None, ip=ip, body={"username": garbage, "password": "x"})
        codes.append(resp.status_code)
    assert codes[-1] == 429, codes
    assert all(c != 200 for c in codes)


def test_login_non_json_body_cannot_bypass_ip_ceiling(prod, monkeypatch):
    monkeypatch.setenv("AUTH_LOGIN_IP_MAX", "4")
    codes = [
        prod.post(
            "/api/auth/login",
            data="not json",
            content_type="text/plain",
            environ_overrides={"REMOTE_ADDR": "203.0.113.91"},
        ).status_code
        for _ in range(5)
    ]
    assert codes[-1] == 429 and codes[:4] == [400] * 4


def test_login_limit_response_is_identical_for_existing_and_unknown_accounts(app_ctx, prod, monkeypatch):
    monkeypatch.setenv("AUTH_LOGIN_IDENT_MAX", "2")
    user = _make_user(app_ctx)
    unknown = "ghost_" + uuid.uuid4().hex[:8]
    bodies = []
    for ident in (user["username"], unknown):
        for _ in range(2):
            _login(prod, ident, ip="10.8.0.1")
        resp = _login(prod, ident, ip="10.8.0.2")
        assert resp.status_code == 429
        body = resp.get_json()
        body.pop("retry_after")
        bodies.append((body, resp.headers.get("Content-Type")))
    assert bodies[0] == bodies[1]


def test_login_success_is_not_affected_for_a_fresh_identity(app_ctx, prod):
    user = _make_user(app_ctx)
    resp = _login(prod, user["username"], _PASSWORD, ip="10.9.0.1", device=str(uuid.uuid4()))
    assert resp.status_code == 200
    assert resp.get_json()["access_token"]


def test_login_concurrent_requests_for_one_identifier_never_exceed_limit(app_ctx, prod):
    ident = "race_" + uuid.uuid4().hex[:8]
    n = 40
    codes = [None] * n
    barrier = threading.Barrier(n)

    def worker(i):
        c = app_ctx.test_client()
        barrier.wait()
        codes[i] = _login(c, ident, ip=f"10.10.{i}.1").status_code

    threads = [threading.Thread(target=worker, args=(i,)) for i in range(n)]
    for t in threads:
        t.start()
    for t in threads:
        t.join()
    assert codes.count(429) == n - 10  # exactly the identifier limit passes
    assert codes.count(401) == 10


def test_login_concurrent_requests_from_one_ip_never_exceed_ip_ceiling(app_ctx, prod, monkeypatch):
    monkeypatch.setenv("AUTH_LOGIN_IP_MAX", "10")
    n = 30
    codes = [None] * n
    barrier = threading.Barrier(n)

    def worker(i):
        c = app_ctx.test_client()
        barrier.wait()
        codes[i] = _login(c, f"conc_{i}_{uuid.uuid4().hex[:6]}", ip="203.0.113.99").status_code

    threads = [threading.Thread(target=worker, args=(i,)) for i in range(n)]
    for t in threads:
        t.start()
    for t in threads:
        t.join()
    assert codes.count(401) == 10 and codes.count(429) == n - 10


# ---------------------------------------------------------------------------
# FORGOT PASSWORD
# ---------------------------------------------------------------------------


def test_forgot_shared_ip_30_distinct_phones_each_served(app_ctx, prod):
    for _ in range(30):
        resp = _forgot(prod, _phone(), ip="37.236.7.7")
        assert resp.status_code == 200, resp.get_data(as_text=True)


def test_forgot_ip_ceiling_default_30_per_15_min(prod):
    ip = "203.0.113.110"
    codes = [_forgot(prod, _phone(), ip=ip).status_code for _ in range(31)]
    assert codes == [200] * 30 + [429]
    _assert_limited_consistently(_forgot(prod, _phone(), ip=ip))


def test_forgot_same_phone_blocked_after_three_regardless_of_ip_and_device(app_ctx, prod):
    user = _make_user(app_ctx)
    codes = [
        _forgot(prod, user["phone"], ip=ip, device=f"device-{uuid.uuid4()}").status_code
        for ip in _ips("10.20", 30)
    ]
    assert codes == [200] * 3 + [429] * 27
    assert len(prod.sms.sent) == 3  # SMS-bomb: never more than 3 texts to one number


def test_forgot_responses_identical_for_existing_and_unknown_phone(app_ctx, prod):
    user = _make_user(app_ctx)
    unknown = _phone()
    seen = {"known": [], "unknown": []}
    for _ in range(4):
        for label, phone in (("known", user["phone"]), ("unknown", unknown)):
            resp = _forgot(prod, phone, ip="10.21.0.1")
            body = resp.get_json()
            body.pop("retry_after", None)
            seen[label].append((resp.status_code, body, resp.headers.get("Retry-After") is None))
    assert seen["known"] == seen["unknown"]
    assert [s for s, _, _ in seen["known"]] == [200, 200, 200, 429]
    # an unknown number is limited exactly like a real one (no oracle) and no SMS for it
    assert prod.sms.sent.count(user["phone"]) == 3
    assert unknown not in prod.sms.sent


def test_forgot_phone_format_variants_share_one_budget(app_ctx, prod):
    variants = ["07701234510", "7701234510", "+9647701234510", "009647701234510", "0770 123 4510"]
    codes = [_forgot(prod, variants[i % len(variants)], ip=f"10.22.0.{i + 1}").status_code for i in range(6)]
    assert codes == [200, 200, 200, 429, 429, 429]


def test_forgot_phone_field_precedence_decoy_cannot_dodge(prod):
    phone = _phone()
    codes = []
    for i in range(5):
        resp = prod.post(
            "/api/auth/forgot-password",
            json={"phone_number": phone, "phone": _phone()},  # handler uses phone_number first
            environ_overrides={"REMOTE_ADDR": f"10.23.0.{i + 1}"},
        )
        codes.append(resp.status_code)
    assert codes == [200] * 3 + [429] * 2


def test_forgot_daily_phone_cap(prod, monkeypatch):
    monkeypatch.setenv("AUTH_FORGOT_PHONE_MAX", "1000")
    phone = _phone()
    codes = [_forgot(prod, phone, ip=f"10.24.0.{i + 1}").status_code for i in range(12)]
    assert codes == [200] * 10 + [429] * 2


def test_forgot_device_rotation_does_not_bypass_ip_ceiling(prod, monkeypatch):
    monkeypatch.setenv("AUTH_FORGOT_IP_MAX", "8")
    ip = "203.0.113.120"
    codes = [_forgot(prod, _phone(), ip=ip, device=f"device-{uuid.uuid4()}").status_code for i in range(9)]
    assert codes == [200] * 8 + [429]


def test_forgot_one_device_limited_across_phones(prod):
    device = "dev-" + uuid.uuid4().hex
    codes = [_forgot(prod, _phone(), ip=f"10.25.0.{i + 1}", device=device).status_code for i in range(11)]
    assert codes == [200] * 10 + [429]


def test_forgot_garbage_phone_cannot_bypass_ip_ceiling(prod, monkeypatch):
    monkeypatch.setenv("AUTH_FORGOT_IP_MAX", "5")
    ip = "203.0.113.130"
    codes = []
    for garbage in (None, [], {"a": 1}, "", "abc", 12345, True):
        resp = prod.post(
            "/api/auth/forgot-password",
            json={"phone_number": garbage},
            environ_overrides={"REMOTE_ADDR": ip},
        )
        codes.append(resp.status_code)
    assert codes[:5].count(429) == 0 and codes[5:] == [429, 429]


def test_forgot_concurrent_requests_for_one_phone_send_at_most_three_sms(app_ctx, prod):
    user = _make_user(app_ctx)
    n = 30
    codes = [None] * n
    barrier = threading.Barrier(n)

    def worker(i):
        c = app_ctx.test_client()
        barrier.wait()
        codes[i] = _forgot(c, user["phone"], ip=f"10.26.{i}.1").status_code

    threads = [threading.Thread(target=worker, args=(i,)) for i in range(n)]
    for t in threads:
        t.start()
    for t in threads:
        t.join()
    assert codes.count(429) == n - 3
    assert len(prod.sms.sent) <= 3


# ---------------------------------------------------------------------------
# SIGNUP
# ---------------------------------------------------------------------------


def test_signup_shared_ip_many_distinct_phones_served(prod):
    for _ in range(30):
        resp = _signup(prod, {"phone": _phone(), "password": "x"}, ip="37.236.5.5")
        assert resp.status_code != 429  # 400/404 from the handler is fine


def test_signup_same_phone_blocked_regardless_of_ip_and_decoy_field(prod):
    phone = _phone()
    codes = [
        _signup(
            prod,
            {"phone": phone, "phone_number": _phone(), "password": "x"},  # handler reads `phone` first
            ip=ip,
            device=f"device-{uuid.uuid4()}",
        ).status_code
        for ip in _ips("10.30", 14)
    ]
    assert 429 not in codes[:10] and codes[10:] == [429] * 4


def test_signup_ip_ceiling_and_legacy_env(prod, monkeypatch):
    ip = "203.0.113.140"
    codes = [_signup(prod, {"phone": _phone(), "password": "x"}, ip=ip).status_code for _ in range(61)]
    assert 429 not in codes[:60] and codes[60] == 429
    monkeypatch.setenv("RATE_LIMIT_SIGNUP", "3")
    ip2 = "203.0.113.141"
    codes = [_signup(prod, {"phone": _phone(), "password": "x"}, ip=ip2).status_code for _ in range(4)]
    assert 429 not in codes[:3] and codes[3] == 429


# ---------------------------------------------------------------------------
# SEND EMAIL VERIFICATION (authenticated)
# ---------------------------------------------------------------------------


def _auth_header(app_ctx, user):
    from flask_jwt_extended import create_access_token

    with app_ctx.app_context():
        return {"Authorization": f"Bearer {create_access_token(identity=user['public_id'])}"}


def _send_email(client, headers, *, ip="10.0.0.1"):
    return client.post(
        "/api/auth/send-email-verification", headers=headers, environ_overrides={"REMOTE_ADDR": ip}
    )


@pytest.fixture
def email_prod(prod, monkeypatch):
    import kk.routes.auth as auth_module

    sent: list[str] = []
    monkeypatch.setattr(
        auth_module, "_send_email_verification_email", lambda email, token: sent.append(email) or True
    )
    prod.sent_emails = sent
    return prod


def test_email_send_per_account_limit_regardless_of_ip(app_ctx, email_prod):
    user = _make_user(app_ctx, email=f"a{uuid.uuid4().hex[:8]}@example.com")
    headers = _auth_header(app_ctx, user)
    codes = [_send_email(email_prod, headers, ip=ip).status_code for ip in _ips("10.40", 8)]
    assert codes == [200] * 5 + [429] * 3
    assert len(email_prod.sent_emails) == 5
    _assert_limited_consistently(_send_email(email_prod, headers, ip="10.40.9.9"))


def test_email_send_many_accounts_one_ip_are_all_served(app_ctx, email_prod):
    for _ in range(12):
        user = _make_user(app_ctx, email=f"u{uuid.uuid4().hex[:8]}@example.com")
        resp = _send_email(email_prod, _auth_header(app_ctx, user), ip="37.236.4.4")
        assert resp.status_code == 200


def test_email_send_many_accounts_cannot_bomb_one_inbox(app_ctx, email_prod):
    # e-mail is unique per account only case-sensitively, but the handler
    # lower-cases the destination: case variants are accounts that all point at
    # ONE inbox.
    local = f"victim{uuid.uuid4().hex[:6]}"
    inbox = f"{local}@example.com"
    variants = [
        "".join(ch.upper() if (i >> k) & 1 else ch for k, ch in enumerate(local)) + "@example.com"
        for i in range(1, 9)
    ]
    assert len({v.lower() for v in variants}) == 1 and len(set(variants)) == 8
    codes = []
    for i, email in enumerate(variants):
        user = _make_user(app_ctx, email=email)
        codes.append(_send_email(email_prod, _auth_header(app_ctx, user), ip=f"10.41.0.{i + 1}").status_code)
    assert codes == [200] * 5 + [429] * 3
    assert email_prod.sent_emails.count(inbox) == 5

def test_email_send_unauthenticated_is_still_rejected_and_not_counted(email_prod):
    resp = email_prod.post("/api/auth/send-email-verification", environ_overrides={"REMOTE_ADDR": "10.42.0.1"})
    assert resp.status_code in (401, 422)
    assert not email_prod.fake_redis.counts


# ---------------------------------------------------------------------------
# UNCHANGED legacy per-IP limits (must NOT get weaker)
# ---------------------------------------------------------------------------


def test_reset_password_per_ip_limit_is_unchanged_10_per_15_min(prod):
    ip = "203.0.113.150"
    codes = [
        prod.post(
            "/api/auth/reset-password",
            json={"token": f"{i:012d}", "password": "Str0ng!Passw0rd"},
            environ_overrides={"REMOTE_ADDR": ip},
        ).status_code
        for i in range(11)
    ]
    assert codes[:10] == [400] * 10
    assert codes[10] == 429  # token brute force stays bounded to 10 guesses / 15 min / IP


def test_verify_email_per_ip_limit_is_unchanged(prod):
    ip = "203.0.113.151"
    codes = [
        prod.post("/api/auth/verify-email", json={"token": f"t{i}"}, environ_overrides={"REMOTE_ADDR": ip}).status_code
        for i in range(11)
    ]
    assert codes[:10] == [400] * 10 and codes[10] == 429


# ---------------------------------------------------------------------------
# Store semantics / configuration / privacy
# ---------------------------------------------------------------------------


@pytest.mark.parametrize("scope_url", ["/api/auth/login", "/api/auth/forgot-password", "/api/auth/signup"])
def test_production_without_redis_fails_closed_503(prod, monkeypatch, scope_url):
    import kk.security as security_module

    monkeypatch.setattr(security_module, "_redis_client", lambda: None)
    resp = prod.post(scope_url, json={"username": "x", "password": "y", "phone": _phone()})
    assert resp.status_code == 503
    assert resp.get_json()["code"] == "rate_limiter_unavailable"


def test_production_redis_error_fails_closed_503(prod, monkeypatch):
    import kk.security as security_module

    monkeypatch.setattr(security_module, "_redis_client", lambda: RaisingRedis())
    assert _login(prod, "x").status_code == 503


def test_development_memory_fallback_enforces_limits(dev_memory, monkeypatch):
    monkeypatch.setenv("AUTH_LOGIN_IDENT_MAX", "3")
    ident = "devmem_" + uuid.uuid4().hex[:6]
    codes = [_login(dev_memory, ident, ip=f"10.50.0.{i + 1}").status_code for i in range(5)]
    assert codes == [401, 401, 401, 429, 429]
    monkeypatch.setenv("AUTH_FORGOT_PHONE_MAX", "2")
    phone = _phone()
    codes = [_forgot(dev_memory, phone, ip=f"10.51.0.{i + 1}").status_code for i in range(4)]
    assert codes[:2] == [200, 200] and codes[2:] == [429, 429]


def test_limiter_is_noop_under_testing_env(app_ctx):
    client = app_ctx.test_client()  # APP_ENV=testing from the module fixture
    ident = "noop_" + uuid.uuid4().hex[:6]
    assert {_login(client, ident).status_code for _ in range(15)} == {401}


def test_redis_keys_never_contain_raw_identifiers_or_device(app_ctx, prod):
    phone = "07701234599"
    _login(prod, "SecretUserName", ip="203.0.113.77", device="device-secret-12345")
    _forgot(prod, phone, ip="203.0.113.78", device="device-secret-12345")
    keys = list(prod.fake_redis.counts)
    assert keys
    blob = " ".join(keys).lower()
    assert "secretusername" not in blob and "7701234599" not in blob and "device-secret" not in blob
    assert all(k.startswith(("authrl:", "acct_", "rl:")) for k in keys)


def test_production_defaults_dev_defaults_and_env_overrides(monkeypatch):
    from kk.rate_identity import _limits_for

    _clean_env(monkeypatch)
    monkeypatch.setenv("APP_ENV", "production")
    assert dict(_limits_for("login")) == {
        "ident": [(10, 900)],
        "device": [(30, 900)],
        "ip": [(100, 900)],
    }
    assert dict(_limits_for("forgot")) == {
        "phone": [(3, 900), (10, 86400)],
        "device": [(10, 900)],
        "ip": [(30, 900), (300, 86400)],
    }
    assert dict(_limits_for("signup")) == {
        "phone": [(10, 3600)],
        "device": [(10, 3600)],
        "ip": [(60, 3600)],
    }
    assert dict(_limits_for("email_send")) == {
        "account": [(5, 900), (10, 86400)],
        "email": [(5, 900), (10, 86400)],
        "ip": [(60, 900)],
    }
    monkeypatch.setenv("AUTH_LOGIN_IDENT_MAX", "7")
    monkeypatch.setenv("AUTH_LOGIN_WINDOW_MINUTES", "5")
    assert dict(_limits_for("login"))["ident"] == [(7, 300)]
    monkeypatch.setenv("RATE_LIMIT_SIGNUP", "9")
    assert dict(_limits_for("signup"))["ip"] == [(9, 3600)]
    monkeypatch.setenv("AUTH_SIGNUP_IP_MAX", "11")
    assert dict(_limits_for("signup"))["ip"] == [(11, 3600)]
    # development is looser (x10) but never tighter than production
    monkeypatch.setenv("APP_ENV", "development")
    _clean_env(monkeypatch)
    dev = dict(_limits_for("login"))
    assert dev["ident"][0][0] == 100 and dev["ip"][0][0] == 1000
    assert dict(_limits_for("forgot"))["phone"][0][0] == 30
    # garbage env falls back to the default
    monkeypatch.setenv("AUTH_LOGIN_IDENT_MAX", "abc")
    assert dict(_limits_for("login"))["ident"][0][0] == 100


def test_login_ident_limit_stays_at_or_above_the_account_failure_throttle():
    """The identifier limiter must never be tighter than M-09 (5 failures)
    or it would shadow the audited per-account throttle."""
    from kk import security as sec
    from kk.rate_identity import _LOGIN_DEFAULTS

    assert _LOGIN_DEFAULTS["IDENT_MAX"][0] >= sec._ACCOUNT_LOGIN_MAX_FAILURES
    assert sec._ACCOUNT_LOGIN_MAX_FAILURES == 5 and sec._ACCOUNT_LOGIN_LOCK_MINUTES == 15


def test_unknown_scope_is_rejected_at_decoration_time():
    from kk.rate_identity import auth_rate_limit

    with pytest.raises(ValueError):
        auth_rate_limit("nope")


def test_app_generated_uuid_device_id_is_accepted_by_the_backend_format():
    """The Flutter app sends a lower-case UUIDv4 (36 chars); the backend format
    check (shared with the OTP limiter) must accept it, and nothing longer or with
    other characters than the documented alphabet."""
    from kk.rate_identity import _DEVICE_ID_RE

    for _ in range(50):
        assert _DEVICE_ID_RE.match(str(uuid.uuid4()))
    assert not _DEVICE_ID_RE.match("x" * 129)
    assert not _DEVICE_ID_RE.match("has space in it")
    assert not _DEVICE_ID_RE.match("short")


def test_login_uuid_device_header_is_counted_as_a_device(prod):
    device = str(uuid.uuid4())
    out = [_login(prod, f"u_{i}", ip=f"10.60.0.{i + 1}", device=device).status_code for i in range(31)]
    assert out == [401] * 30 + [429]
