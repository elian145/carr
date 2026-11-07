"""Phone canonicalisation (SEC-003) completed on the F-12 release base.

One Iraqi SIM can be typed ``7XXXXXXXXX`` (what the app sends after its fixed
"+964"), ``07XXXXXXXXX`` (what the SIM shows), ``+9647XXXXXXXXX``,
``+96407XXXXXXXXX`` (the app prefix + a typed leading zero) or ``00964...``,
and with Arabic-Indic digits. All of them must be ONE identity:

  * ``User.phone_number`` (UNIQUE) is stored canonically (10 digits, no
    leading 0), so the database itself prevents a second account;
  * accounts stored before the change with a leading ``0`` are still found
    (no data migration) by every login/OTP/forgot/verify/signup path;
  * the canonical form can never match a *different* subscriber, so it cannot
    be used for account takeover, and the OTP issued for one number never
    verifies another;
  * the Google-review OTP bypass only ever opens the ONE account of the
    configured number (any spelling of it), never any other user;
  * the F-12 limiter keys bucket every spelling together
    (``kk.rate_identity`` vs ``kk.routes.auth._normalize_phone`` stay in sync).

Every user is disposable, the DB is a per-module temp SQLite file (or the
LOCAL PostgreSQL named by ``CARNET_SEC_PG_URL``, tables dropped/re-created) and
``SMS_PROVIDER=console``: nothing is ever sent.
"""

from __future__ import annotations

import os
import sys
import tempfile
import threading
import uuid
from datetime import timedelta
from pathlib import Path

import pytest

_REPO_ROOT = Path(__file__).resolve().parents[2]
if str(_REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(_REPO_ROOT))

OWNER_PW = "Owner#Pass123"
ATTACKER_PW = "Attacker#Pass1"
_REVIEW_OTP = "913579"
_ARABIC_INDIC = str.maketrans("0123456789", "٠١٢٣٤٥٦٧٨٩")
_PERSIAN = str.maketrans("0123456789", "۰۱۲۳۴۵۶۷۸۹")


def _local_pg_url() -> str | None:
    """``CARNET_SEC_PG_URL`` opts this module into a disposable LOCAL
    PostgreSQL. Anything non-local is refused (never prod/Neon credentials)."""
    from urllib.parse import urlparse

    url = (os.environ.get("CARNET_SEC_PG_URL") or "").strip()
    if not url:
        return None
    if urlparse(url).hostname not in ("127.0.0.1", "localhost"):
        raise RuntimeError("CARNET_SEC_PG_URL must point at a local server")
    return url


@pytest.fixture(scope="module")
def app_ctx():
    tmp = tempfile.TemporaryDirectory(prefix="carlist_auth_canon_", ignore_cleanup_errors=True)
    os.environ["APP_ENV"] = "testing"
    os.environ["SMS_PROVIDER"] = "console"
    os.environ["ALLOW_DEV_CODE_IN_RESPONSE"] = "1"
    prev_db_url = os.environ.pop("DATABASE_URL", None)
    pg_url = _local_pg_url()
    if pg_url:
        os.environ["DATABASE_URL"] = pg_url
    os.environ.pop("REDIS_URL", None)
    os.environ["DB_PATH"] = os.path.join(tmp.name, "auth_canon.db")

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
    os.environ.pop("ALLOW_DEV_CODE_IN_RESPONSE", None)
    os.environ.pop("DATABASE_URL", None)
    if prev_db_url is not None:
        os.environ["DATABASE_URL"] = prev_db_url


@pytest.fixture
def client(app_ctx):
    return app_ctx[1]


# ---------------------------------------------------------------------------
# helpers
# ---------------------------------------------------------------------------


def _d10() -> str:
    """A fresh 10-digit Iraqi-style mobile without the leading zero."""
    return "77" + f"{uuid.uuid4().int % 10**8:08d}"


def _spellings(d: str) -> list[str]:
    """Every spelling of the SIM ``d`` the app / a user can plausibly send."""
    return [
        d,
        "0" + d,
        "+964" + d,
        "964" + d,
        "+9640" + d,
        "00964" + d,
        f"0{d[:3]} {d[3:6]}-{d[6:]}",
        "0" + d.translate(_ARABIC_INDIC),
        d.translate(_PERSIAN),
    ]


def _forms(d: str) -> list[str]:
    return [d, "0" + d]


def _make_user(
    app_ctx,
    *,
    stored_phone: str,
    verified: bool = True,
    password: str = OWNER_PW,
    is_admin: bool = False,
    is_active: bool = True,
) -> dict:
    app, _c, db, User = app_ctx
    with app.app_context():
        user = User(
            username=f"u_{uuid.uuid4().hex[:10]}",
            phone_number=stored_phone,
            first_name="Canon",
            last_name="Test",
            is_active=is_active,
            is_verified=verified,
            phone_verified=verified,
            is_admin=is_admin,
            public_id=f"pub-{uuid.uuid4().hex[:12]}",
        )
        user.set_password(password)
        db.session.add(user)
        db.session.commit()
        return {"id": user.id, "username": user.username, "phone": stored_phone}


def _rows(app_ctx, d: str) -> list[dict]:
    app, _c, _db, User = app_ctx
    with app.app_context():
        return [
            {
                "id": u.id,
                "username": u.username,
                "phone": u.phone_number,
                "verified": bool(u.is_verified),
                "last_login": u.last_login,
            }
            for u in User.query.filter(User.phone_number.in_(_forms(d))).order_by(User.id).all()
        ]


def _expire_cooldown(app_ctx, d: str) -> None:
    from kk.time_utils import utcnow

    app, _c, db, User = app_ctx
    with app.app_context():
        for u in User.query.filter(User.phone_number.in_(_forms(d))).all():
            u.phone_verification_last_sent_at = utcnow() - timedelta(minutes=5)
            u.phone_verification_locked_until = None
        db.session.commit()


def _start(client, phone: str, purpose: str | None = "signup", url: str = "/api/auth/phone/start"):
    body = {"phone_number": phone}
    if purpose:
        body["purpose"] = purpose
    return client.post(url, json=body)


def _verify(client, phone: str, code: str, purpose: str = "login"):
    return client.post(
        "/api/auth/phone/verify",
        json={"phone_number": phone, "code": code, "purpose": purpose},
    )


def _login(client, ident: str, password: str):
    return client.post("/api/auth/login", json={"username": ident, "password": password})


# ---------------------------------------------------------------------------
# A. the canonical form itself
# ---------------------------------------------------------------------------


def test_every_spelling_of_one_sim_collapses_to_one_canonical_form():
    from kk.routes.auth import _normalize_phone

    d = _d10()
    assert {_normalize_phone(s) for s in _spellings(d)} == {d}


def test_normalize_phone_is_idempotent():
    from kk.routes.auth import _normalize_phone

    d = _d10()
    for s in _spellings(d) + ["", "abc", "1234567890", "123456789", "+1 415 555 2671"]:
        once = _normalize_phone(s)
        assert _normalize_phone(once) == once, s


def test_different_subscribers_never_collapse():
    from kk.routes.auth import _normalize_phone

    d = _d10()
    other_last = d[:-1] + str((int(d[-1]) + 1) % 10)
    other_first = ("8" if d[0] != "8" else "9") + d[1:]
    canon = _normalize_phone(d)
    for other in (other_last, "0" + other_last, other_first, d[:-1], d + "0", "+1" + d, "9" + d):
        assert _normalize_phone(other) != canon, other
    # nothing is padded or invented
    assert _normalize_phone("") == ""
    assert _normalize_phone("abc") == ""
    assert _normalize_phone("123456789") == "123456789"
    assert _normalize_phone("1234567890") == "1234567890"


def test_lookup_variants_cover_only_the_two_legacy_spellings():
    from kk.routes.auth import _phone_lookup_variants

    d = _d10()
    assert _phone_lookup_variants(d) == [d, "0" + d]
    assert _phone_lookup_variants("0" + d) == [d, "0" + d]  # re-canonicalised
    assert _phone_lookup_variants("+964" + d) == [d, "0" + d]
    assert _phone_lookup_variants("") == []
    # not an Iraqi 10-digit mobile: no invented "0" spelling
    assert _phone_lookup_variants("123456789") == ["123456789"]


def test_f12_limiter_and_auth_agree_on_the_canonical_number(app_ctx):
    """kk.rate_identity must bucket every spelling exactly like auth does,
    otherwise the per-phone OTP budget could be multiplied by re-spelling."""
    from kk import rate_identity
    from kk.routes.auth import _normalize_phone

    app = app_ctx[0]
    d = _d10()
    with app.app_context():
        expected = {rate_identity._hash("phone", d)}
        for s in _spellings(d):
            assert rate_identity._canonical_phone(s) == _normalize_phone(s) == d, s
            assert set(rate_identity._identity_keys({"phone_number": s})) == expected, s
            # login identifiers keep a literal-ident key AND the shared phone key
            keys = rate_identity._login_identifier_keys(s)
            assert rate_identity._hash("phone", d) in keys, s


# ---------------------------------------------------------------------------
# B. one account per SIM, whichever spelling creates it
# ---------------------------------------------------------------------------


@pytest.mark.parametrize(
    "url",
    ["/api/auth/phone/start", "/api/auth/send-verification", "/api/auth/send_otp"],
)
def test_every_spelling_creates_the_same_single_canonical_account(app_ctx, client, url):
    d = _d10()
    for s in _spellings(d):
        resp = _start(client, s, purpose=None, url=url)
        assert resp.status_code in (200, 429), (s, resp.status_code, resp.data)
        _expire_cooldown(app_ctx, d)
    rows = _rows(app_ctx, d)
    assert len(rows) == 1, rows
    assert rows[0]["phone"] == d  # canonical: the UNIQUE column enforces it


def test_a_losing_concurrent_creation_adopts_the_winner_row(app_ctx):
    """Two first requests for one SIM race on the UNIQUE canonical column; the
    loser must reuse the winner's account, not 500 and not duplicate."""
    from unittest.mock import patch

    from kk.routes import auth as auth_routes

    app, _c, _db, _User = app_ctx
    d = _d10()
    winner = _make_user(app_ctx, stored_phone=d, verified=False)

    real_find = auth_routes._find_user_by_phone
    calls = {"n": 0}

    def blind_first_lookup(phone_digits, **filters):
        calls["n"] += 1
        if calls["n"] == 1:
            return None  # the racer did not see the winner's row yet
        return real_find(phone_digits, **filters)

    with app.app_context():
        with patch.object(auth_routes, "_find_user_by_phone", side_effect=blind_first_lookup):
            got = auth_routes._get_or_create_user_for_phone("0" + d)
        assert got.id == winner["id"]
    assert len(_rows(app_ctx, d)) == 1


@pytest.mark.skipif(not _local_pg_url(), reason="needs the disposable local PostgreSQL (CARNET_SEC_PG_URL)")
def test_pg_parallel_first_requests_in_different_spellings_make_one_account(app_ctx):
    """Real UNIQUE constraint + real concurrency on PostgreSQL."""
    app, _c, _db, _User = app_ctx
    d = _d10()
    spellings = ["0" + d, d, "+964" + d, "00964" + d]
    barrier = threading.Barrier(len(spellings))
    results: list = []

    def worker(spelling):
        cl = app.test_client()
        barrier.wait()
        results.append(_start(cl, spelling).status_code)

    threads = [threading.Thread(target=worker, args=(s,)) for s in spellings]
    for t in threads:
        t.start()
    for t in threads:
        t.join(30)
    rows = _rows(app_ctx, d)
    assert len(rows) == 1 and rows[0]["phone"] == d, (rows, results)
    assert all(code in (200, 429) for code in results), results


# ---------------------------------------------------------------------------
# C. legacy "07..." rows keep working through every path (no data migration)
# ---------------------------------------------------------------------------


def test_legacy_leading_zero_account_is_adopted_not_duplicated_by_any_spelling(app_ctx, client):
    d = _d10()
    legacy = _make_user(app_ctx, stored_phone="0" + d)
    for s in _spellings(d):
        resp = _start(client, s, purpose="login")
        assert resp.status_code in (200, 429), (s, resp.data)
        _expire_cooldown(app_ctx, d)
    rows = _rows(app_ctx, d)
    assert [r["id"] for r in rows] == [legacy["id"]]
    assert rows[0]["phone"] == "0" + d  # never rewritten behind the user's back


def test_otp_login_works_across_spellings_and_returns_the_legacy_account(app_ctx, client):
    d = _d10()
    legacy = _make_user(app_ctx, stored_phone="0" + d)
    for start_as, verify_as in (("+964" + d, "0" + d), ("0" + d, d), (d, "00964" + d)):
        resp = _start(client, start_as, purpose="login")
        assert resp.status_code == 200, resp.data
        code = resp.get_json()["dev_code"]
        ok = _verify(client, verify_as, code)
        assert ok.status_code == 200, (start_as, verify_as, ok.data)
        assert ok.get_json()["user"]["username"] == legacy["username"]
        _expire_cooldown(app_ctx, d)
    assert len(_rows(app_ctx, d)) == 1


def test_password_login_finds_canonical_and_legacy_rows_in_any_spelling(app_ctx, client):
    d1, d2 = _d10(), _d10()
    canon = _make_user(app_ctx, stored_phone=d1)
    legacy = _make_user(app_ctx, stored_phone="0" + d2)
    for d, who in ((d1, canon), (d2, legacy)):
        for s in _spellings(d):
            r = _login(client, s, OWNER_PW)
            assert r.status_code == 200, (s, r.data)
            assert r.get_json()["user"]["username"] == who["username"]


def test_password_login_by_username_still_works(app_ctx, client):
    info = _make_user(app_ctx, stored_phone=_d10())
    r = _login(client, info["username"], OWNER_PW)
    assert r.status_code == 200, r.data


def test_wrong_password_and_near_miss_numbers_are_the_same_generic_401(app_ctx, client):
    d = _d10()
    _make_user(app_ctx, stored_phone="0" + d)
    near = d[:-1] + str((int(d[-1]) + 1) % 10)
    bad_pw = _login(client, "0" + d, "definitely-wrong-1")
    near_miss = _login(client, "0" + near, OWNER_PW)
    unknown = _login(client, f"nobody_{uuid.uuid4().hex[:8]}", OWNER_PW)
    assert bad_pw.status_code == near_miss.status_code == unknown.status_code == 401
    assert bad_pw.get_json() == near_miss.get_json() == unknown.get_json()


def test_unverified_row_still_cannot_password_login_in_any_spelling(app_ctx, client):
    """F-01 must hold through the canonical fallback (no proven owner, no login)."""
    d = _d10()
    _make_user(app_ctx, stored_phone=d, verified=False)
    for s in (d, "0" + d, "+964" + d):
        assert _login(client, s, OWNER_PW).status_code == 401, s


def test_admin_principal_password_login_stays_blocked_in_any_spelling(app_ctx, client):
    from kk.models import AdminAccount

    app, _c, db, _User = app_ctx
    d = _d10()
    info = _make_user(app_ctx, stored_phone="0" + d, is_admin=True)
    with app.app_context():
        acct = AdminAccount(
            principal_user_id=info["id"], username=f"dash_{uuid.uuid4().hex[:8]}", is_active=True
        )
        acct.set_password(OWNER_PW)
        db.session.add(acct)
        db.session.commit()
    for s in ("0" + d, d, "+964" + d):
        assert _login(client, s, OWNER_PW).status_code == 401, s


def test_forgot_password_finds_a_legacy_row_in_any_spelling(app_ctx, client):
    d = _d10()
    _make_user(app_ctx, stored_phone="0" + d)
    for s in ("+964" + d, d, "0" + d):
        r = client.post("/api/auth/forgot-password", json={"phone": s})
        assert r.status_code == 200, (s, r.data)
        _expire_cooldown(app_ctx, d)
    assert len(_rows(app_ctx, d)) == 1


def test_legacy_duplicates_prefer_canonical_and_never_make_a_third_row(app_ctx, client):
    d = _d10()
    legacy = _make_user(app_ctx, stored_phone="0" + d)
    canon = _make_user(app_ctx, stored_phone=d)
    from kk.routes.auth import _find_user_by_phone

    app = app_ctx[0]
    with app.app_context():
        assert _find_user_by_phone("0" + d).id == canon["id"]
        assert _find_user_by_phone(d, is_active=True).id == canon["id"]
    resp = _start(client, "0" + d, purpose="login")
    assert resp.status_code == 200, resp.data
    ok = _verify(client, "+964" + d, resp.get_json()["dev_code"])
    assert ok.status_code == 200, ok.data
    assert ok.get_json()["user"]["username"] == canon["username"]
    rows = _rows(app_ctx, d)
    assert sorted(r["id"] for r in rows) == sorted([legacy["id"], canon["id"]])
    legacy_row = next(r for r in rows if r["id"] == legacy["id"])
    assert legacy_row["last_login"] is None  # untouched


def test_find_user_by_phone_applies_filters_to_every_spelling(app_ctx):
    from kk.routes.auth import _find_user_by_phone

    app = app_ctx[0]
    d = _d10()
    _make_user(app_ctx, stored_phone="0" + d, is_active=False)
    with app.app_context():
        assert _find_user_by_phone(d, is_active=True) is None
        assert _find_user_by_phone(d, is_active=False) is not None


# ---------------------------------------------------------------------------
# D. cross-format takeover is impossible
# ---------------------------------------------------------------------------


def test_otp_for_one_number_never_verifies_another_number(app_ctx, client):
    victim_d, attacker_d = _d10(), _d10()
    victim = _make_user(app_ctx, stored_phone="0" + victim_d)
    resp = _start(client, attacker_d)
    assert resp.status_code == 200, resp.data
    attacker_code = resp.get_json()["dev_code"]
    for target in _spellings(victim_d):
        r = _verify(client, target, attacker_code)
        assert r.status_code in (400, 429), (target, r.status_code, r.data)
        assert "access_token" not in (r.get_json() or {})
    # the victim row is unchanged and still the only row of that SIM
    rows = _rows(app_ctx, victim_d)
    assert [r["id"] for r in rows] == [victim["id"]]
    assert rows[0]["last_login"] is None


def test_signup_with_another_spelling_cannot_overwrite_a_verified_account(app_ctx, client):
    d = _d10()
    victim = _make_user(app_ctx, stored_phone="0" + d)
    for s in ("+964" + d, d, "00964" + d):
        r = client.post(
            "/api/auth/signup",
            json={
                "phone": s,
                "password": ATTACKER_PW,
                "otp_code": "000000",
                "username": "attacker_name",
                "first_name": "A",
                "last_name": "B",
            },
        )
        assert r.status_code in (400, 429), (s, r.status_code, r.data)
        assert "access_token" not in (r.get_json() or {})
    # the owner's password still works (in every spelling) and the attacker's does not
    assert _login(client, "0" + d, OWNER_PW).status_code == 200
    assert _login(client, "+964" + d, ATTACKER_PW).status_code == 401
    assert _login(client, victim["username"], ATTACKER_PW).status_code == 401


def test_phone_start_in_another_spelling_never_modifies_an_existing_account(app_ctx, client):
    d = _d10()
    _make_user(app_ctx, stored_phone="0" + d)
    before = _rows(app_ctx, d)
    r = client.post(
        "/api/auth/phone/start",
        json={
            "phone_number": "+964" + d,
            "purpose": "signup",
            "password": ATTACKER_PW,
            "is_dealer": True,
            "dealership_name": "Evil",
            "dealership_phone": "07700000001",
            "dealership_location": "Erbil",
        },
    )
    assert r.status_code in (200, 409), r.data
    after = _rows(app_ctx, d)
    assert [x["id"] for x in after] == [x["id"] for x in before]
    assert _login(client, "0" + d, ATTACKER_PW).status_code == 401
    assert _login(client, "0" + d, OWNER_PW).status_code == 200


# ---------------------------------------------------------------------------
# E. Google-review bypass: exactly one configured number, nobody else
# ---------------------------------------------------------------------------


@pytest.fixture
def review_env(monkeypatch):
    def _set(phone: str, enabled: str = "1"):
        monkeypatch.setenv("GOOGLE_REVIEW_LOGIN_ENABLED", enabled)
        monkeypatch.setenv("GOOGLE_REVIEW_PHONE", phone)
        monkeypatch.setenv("GOOGLE_REVIEW_OTP", _REVIEW_OTP)

    return _set


def _review_verify(client, phone: str, code: str = _REVIEW_OTP):
    return _verify(client, phone, code)


@pytest.mark.parametrize("configured_as", ["national", "app"])
def test_review_bypass_matches_the_configured_sim_in_any_spelling(app_ctx, client, review_env, configured_as):
    d = _d10()
    review_env(("0" + d) if configured_as == "national" else d)
    ids = set()
    for s in _spellings(d):
        r = _review_verify(client, s)
        assert r.status_code == 200, (s, r.data)
        body = r.get_json()
        assert body["access_token"]
        ids.add(body["user"]["id"])
        assert body["user"]["phone_number"] == d  # canonical, whatever was typed
    assert len(ids) == 1
    assert [row["phone"] for row in _rows(app_ctx, d)] == [d]


def test_review_bypass_never_opens_any_other_number(app_ctx, client, review_env):
    d = _d10()
    review_env(d)
    other_last = d[:-1] + str((int(d[-1]) + 1) % 10)
    other_first = ("8" if d[0] != "8" else "9") + d[1:]
    victim_d = _d10()
    _make_user(app_ctx, stored_phone="0" + victim_d)  # a real user, legacy row
    for other in (other_last, "0" + other_last, other_first, d[:-1], d + "0", "+1" + d, victim_d, "0" + victim_d):
        r = _review_verify(client, other)
        # 400 (generic wrong code) / 404 (no account for that number) / 429: never a token
        assert r.status_code in (400, 404, 429), (other, r.status_code, r.data)
        assert "access_token" not in (r.get_json() or {})
        assert "refresh_token" not in (r.get_json() or {})
    # the real user was not logged in nor touched
    assert _rows(app_ctx, victim_d)[0]["last_login"] is None
    # and the review number itself rejects a wrong code
    bad = _review_verify(client, d, "000000")
    assert bad.status_code == 400 and bad.get_json()["message"] == "Invalid or expired verification code"


def test_review_bypass_reuses_a_legacy_leading_zero_review_row(app_ctx, client, review_env):
    d = _d10()
    legacy = _make_user(app_ctx, stored_phone="0" + d, verified=False)
    review_env(d)
    r = _review_verify(client, "+964" + d)
    assert r.status_code == 200, r.data
    assert r.get_json()["user"]["username"] == legacy["username"]
    rows = _rows(app_ctx, d)
    assert [x["id"] for x in rows] == [legacy["id"]]
    assert rows[0]["phone"] == "0" + d  # legacy row is found, not rewritten or duplicated


def test_review_bypass_off_means_off_for_every_spelling(app_ctx, client, review_env):
    d = _d10()
    review_env(d, enabled="0")
    for s in _spellings(d):
        r = _review_verify(client, s)
        assert r.status_code != 200, (s, r.data)
        assert "access_token" not in (r.get_json() or {})


def test_review_start_never_sends_sms_or_echoes_a_code_in_any_spelling(app_ctx, client, review_env, monkeypatch):
    import kk.sms_service as sms_module

    d = _d10()
    review_env(d)

    def _boom(*_a, **_k):
        raise AssertionError("SMS must never be sent for the reviewer phone")

    monkeypatch.setattr(sms_module, "send_verification_sms_result", _boom)
    for s in _spellings(d):
        r = _start(client, s)
        assert r.status_code == 200, (s, r.data)
        assert r.get_json() == {"message": "OTP sent"}
    assert len(_rows(app_ctx, d)) == 1


# ---------------------------------------------------------------------------
# F. root cause of the three google-review test failures
# ---------------------------------------------------------------------------


def test_root_cause_new_rows_echo_the_canonical_number_not_the_typed_one(app_ctx, client, review_env):
    """The old google-review tests asserted ``user.phone_number == "0779..."``
    (the TYPED spelling). Storage is canonical now, so the API echoes the
    10-digit value the app itself shows after "+964"; the typed spelling is
    only a lookup key. This pins both halves of that contract."""
    d = _d10()
    typed = "0" + d
    # review account (created on first successful bypass login)
    review_env(typed)
    r = _review_verify(client, typed)
    assert r.status_code == 200, r.data
    assert r.get_json()["user"]["phone_number"] == d
    me = client.get("/api/auth/me", headers={"Authorization": f"Bearer {r.get_json()['access_token']}"})
    assert me.get_json()["phone_number"] == d
    # ordinary OTP account created through the same typed spelling
    d2 = _d10()
    start = _start(client, "0" + d2)
    ok = _verify(client, "0" + d2, start.get_json()["dev_code"], purpose="signup")
    assert ok.status_code == 200, ok.data
    assert ok.get_json()["user"]["phone_number"] == d2
