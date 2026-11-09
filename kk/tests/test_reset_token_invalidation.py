"""Batch 7 / Agent R: pending password-reset tokens die when the password changes, and
reset-token redemption is single-use even under concurrency.

Uses a minimal Flask app (real models + real ``kk.routes.auth`` blueprint + JWT) on a real
SQLite file, like ``test_f29_reset_token_hashing``. Set ``B7_RESET_PG_URL`` to also run the
concurrency cases against a disposable PostgreSQL (skipped otherwise).
"""

from __future__ import annotations

import os
import sqlite3
import tempfile
import threading
import uuid
from datetime import timedelta

import pytest
from flask import Flask
from sqlalchemy import text

from kk.models import PasswordReset, User, db
from kk.reset_token_crypto import LEGACY_PLAINTEXT_ENV
from kk.time_utils import utcnow

SECRET = "b7-reset-test-secret-key-0123456789"
OLD_PW = "Original1!"
CHANGED_PW = "Changed1Pass!"
RESET_PW = "ResetPass1!"
PG_URL = os.environ.get("B7_RESET_PG_URL", "").strip()
# The CI PostgreSQL job sets CARNET_REQUIRE_PG_TESTS=1: there the PostgreSQL
# parametrisation is mandatory and a missing B7_RESET_PG_URL is a hard failure
# (never a silently SQLite-only run).
PG_REQUIRED = os.environ.get("CARNET_REQUIRE_PG_TESTS") == "1"


def _make_app(uri):
    from flask_jwt_extended import JWTManager

    app = Flask("kk", static_folder=None)
    app.config.update(
        SECRET_KEY=SECRET,
        JWT_SECRET_KEY=SECRET,
        SQLALCHEMY_DATABASE_URI=uri,
        SQLALCHEMY_TRACK_MODIFICATIONS=False,
        TESTING=True,
    )
    db.init_app(app)
    JWTManager(app)
    from kk.routes.auth import bp as auth_bp

    app.register_blueprint(auth_bp)
    with app.app_context():
        db.create_all()
    return app


@pytest.fixture(scope="module", params=["sqlite"] + (["pg"] if (PG_URL or PG_REQUIRED) else []))
def ctx(request):
    if request.param == "pg" and not PG_URL:
        pytest.fail("CARNET_REQUIRE_PG_TESTS=1 but B7_RESET_PG_URL is not set")
    saved = {k: os.environ.get(k) for k in ("APP_ENV", "ALLOW_DEV_CODE_IN_RESPONSE", LEGACY_PLAINTEXT_ENV)}
    os.environ["APP_ENV"] = "testing"
    os.environ.pop("ALLOW_DEV_CODE_IN_RESPONSE", None)
    os.environ.pop(LEGACY_PLAINTEXT_ENV, None)
    tmp = None
    db_path = None
    if request.param == "pg":
        uri = PG_URL
    else:
        tmp = tempfile.TemporaryDirectory(prefix="carlist_b7r_", ignore_cleanup_errors=True)
        db_path = os.path.join(tmp.name, "b7r.db")
        uri = "sqlite:///" + db_path.replace("\\", "/")
    app = _make_app(uri)
    yield app, db_path, request.param
    with app.app_context():
        db.session.remove()
        db.engine.dispose()
    if tmp:
        tmp.cleanup()
    for k, v in saved.items():
        if v is None:
            os.environ.pop(k, None)
        else:
            os.environ[k] = v


@pytest.fixture
def app(ctx):
    return ctx[0]


@pytest.fixture
def backend(ctx):
    return ctx[2]


@pytest.fixture(autouse=True)
def _no_ip_rate_limits(monkeypatch):
    import kk.security as security_module

    monkeypatch.setattr(security_module, "check_rate_limit", lambda *a, **kw: None)


# ---------------------------------------------------------------------------- helpers


def _phone() -> str:
    return f"077{uuid.uuid4().int % 10**8:08d}"


def _make_user(app, phone=None):
    with app.app_context():
        u = User(
            username=f"b7r_{uuid.uuid4().hex[:10]}",
            phone_number=phone or _phone(),
            first_name="B7",
            last_name="Reset",
            email=None,
            is_active=True,
            is_verified=True,
            phone_verified=True,
            public_id=f"pub-{uuid.uuid4().hex[:12]}",
        )
        u.set_password(OLD_PW)
        db.session.add(u)
        db.session.commit()
        return u.id, u.public_id, u.phone_number


def _issue(app, uid, channel="sms"):
    from kk.auth import create_password_reset_token

    with app.app_context():
        return create_password_reset_token(db.session.get(User, uid), channel=channel)


def _bearer(app, public_id):
    from flask_jwt_extended import create_access_token

    with app.app_context():
        return {"Authorization": "Bearer " + create_access_token(identity=public_id)}


def _change(app, public_id, current, new):
    return app.test_client().post(
        "/api/auth/change-password",
        json={"current_password": current, "new_password": new},
        headers=_bearer(app, public_id),
    )


def _reset(app, token, password=RESET_PW):
    return app.test_client().post("/api/auth/reset-password", json={"token": token, "password": password})


def _unused_count(app, uid):
    with app.app_context():
        db.session.expire_all()
        return PasswordReset.query.filter_by(user_id=uid, is_used=False).count()


def _check_pw(app, uid, pw):
    with app.app_context():
        db.session.expire_all()
        return db.session.get(User, uid).check_password(pw)


def _insert_legacy_plaintext(app, uid, raw):
    with app.app_context():
        db.session.execute(
            text(
                "insert into password_reset (user_id, token, expires_at, is_used, created_at) "
                "values (:u, :t, :e, :used, :c)"
            ),
            {"u": uid, "t": raw, "e": utcnow() + timedelta(hours=1), "used": False, "c": utcnow()},
        )
        db.session.commit()


# ------------------------------------------------------------------ (a) change_password


def test_change_password_kills_pending_token(app):
    uid, pub, _ = _make_user(app)
    raw = _issue(app, uid)
    assert _unused_count(app, uid) == 1
    r = _change(app, pub, OLD_PW, CHANGED_PW)
    assert r.status_code == 200 and r.get_json() == {"message": "Password changed successfully"}
    assert _unused_count(app, uid) == 0


def test_token_reuse_after_change_fails_and_password_untouched(app):
    uid, pub, _ = _make_user(app)
    raw = _issue(app, uid)
    assert _change(app, pub, OLD_PW, CHANGED_PW).status_code == 200
    r = _reset(app, raw)
    assert r.status_code == 400
    assert r.get_json() == {"message": "Invalid or expired token"}  # same message as any dead token
    assert _check_pw(app, uid, CHANGED_PW) and not _check_pw(app, uid, RESET_PW)


def test_wrong_current_password_does_not_invalidate_token(app):
    uid, pub, _ = _make_user(app)
    raw = _issue(app, uid)
    r = _change(app, pub, "Wrong1Pass!", CHANGED_PW)
    assert r.status_code == 400 and r.get_json() == {"message": "Current password is incorrect"}
    assert _unused_count(app, uid) == 1
    assert _reset(app, raw).status_code == 200


def test_weak_new_password_does_not_invalidate_token(app):
    uid, pub, _ = _make_user(app)
    raw = _issue(app, uid)
    r = _change(app, pub, OLD_PW, "short")
    assert r.status_code == 400
    assert _unused_count(app, uid) == 1
    assert _reset(app, raw).status_code == 200


def test_new_token_after_change_works(app):
    uid, pub, _ = _make_user(app)
    old = _issue(app, uid)
    assert _change(app, pub, OLD_PW, CHANGED_PW).status_code == 200
    fresh = _issue(app, uid)
    assert fresh != old
    assert _unused_count(app, uid) == 1
    assert _reset(app, old).status_code == 400
    r = _reset(app, fresh)
    assert r.status_code == 200 and r.get_json() == {"message": "Password reset successful"}
    assert _check_pw(app, uid, RESET_PW)


def test_forgot_password_route_after_change_issues_working_token(app, monkeypatch):
    uid, pub, phone = _make_user(app)
    _issue(app, uid)
    assert _change(app, pub, OLD_PW, CHANGED_PW).status_code == 200
    sent = {}
    monkeypatch.setattr(
        "kk.sms_service.send_password_reset_sms",
        lambda dest, token, locale=None: sent.setdefault("token", token) or True,
    )
    r = app.test_client().post("/api/auth/forgot-password", json={"phone_number": phone})
    assert r.status_code == 200
    assert r.get_json() == {"message": "If the account exists, a reset code has been sent"}
    assert _reset(app, sent["token"]).status_code == 200


def test_second_token_for_same_user_also_invalidated(app):
    """Two unused rows (e.g. a legacy plaintext row next to a hashed one) both die."""
    uid, pub, _ = _make_user(app)
    hashed = _issue(app, uid)
    legacy = f"{uuid.uuid4().int % 10**12:012d}"
    _insert_legacy_plaintext(app, uid, legacy)
    assert _unused_count(app, uid) == 2
    assert _change(app, pub, OLD_PW, CHANGED_PW).status_code == 200
    assert _unused_count(app, uid) == 0
    assert _reset(app, hashed).status_code == 400
    assert _reset(app, legacy).status_code == 400  # legacy plaintext fallback must not revive it
    assert _check_pw(app, uid, CHANGED_PW)


def test_other_users_tokens_untouched(app):
    uid, pub, _ = _make_user(app)
    other, _, _ = _make_user(app)
    mine = _issue(app, uid)
    theirs = _issue(app, other)
    assert _change(app, pub, OLD_PW, CHANGED_PW).status_code == 200
    assert _unused_count(app, uid) == 0 and _unused_count(app, other) == 1
    assert _reset(app, mine).status_code == 400
    assert _reset(app, theirs).status_code == 200
    assert _check_pw(app, other, RESET_PW)


def test_already_used_token_stays_used_and_unexpired_state_preserved(app):
    uid, pub, _ = _make_user(app)
    raw = _issue(app, uid)
    assert _reset(app, raw).status_code == 200
    with app.app_context():
        assert PasswordReset.query.filter_by(user_id=uid, is_used=True).count() == 1
    assert _change(app, pub, RESET_PW, CHANGED_PW).status_code == 200
    with app.app_context():
        assert PasswordReset.query.filter_by(user_id=uid, is_used=True).count() == 1
        assert PasswordReset.query.filter_by(user_id=uid, is_used=False).count() == 0
    assert _reset(app, raw).status_code == 400


# ------------------------------------------------------------------- (b) reset_password


def test_reset_flow_end_to_end(app, monkeypatch):
    uid, pub, phone = _make_user(app)
    sent = {}
    monkeypatch.setattr(
        "kk.sms_service.send_password_reset_sms",
        lambda dest, token, locale=None: sent.setdefault("token", token) or True,
    )
    r = app.test_client().post("/api/auth/forgot-password", json={"phone_number": phone})
    assert r.status_code == 200
    r = _reset(app, sent["token"])
    assert r.status_code == 200 and r.get_json() == {"message": "Password reset successful"}
    assert _check_pw(app, uid, RESET_PW) and not _check_pw(app, uid, OLD_PW)
    assert _reset(app, sent["token"], "Another1Pass!").status_code == 400  # single use
    assert _check_pw(app, uid, RESET_PW)


def test_reset_invalidates_other_outstanding_tokens(app):
    uid, _, _ = _make_user(app)
    used = _issue(app, uid)
    other = f"{uuid.uuid4().int % 10**12:012d}"
    _insert_legacy_plaintext(app, uid, other)  # a second unused row (create_* would have deleted it)
    assert _unused_count(app, uid) == 2
    assert _reset(app, used).status_code == 200
    assert _unused_count(app, uid) == 0
    r = _reset(app, other, "Another1Pass!")
    assert r.status_code == 400 and r.get_json() == {"message": "Invalid or expired token"}
    assert _check_pw(app, uid, RESET_PW)


def test_reset_leaves_other_users_tokens_alone(app):
    uid, _, _ = _make_user(app)
    other, _, _ = _make_user(app)
    mine = _issue(app, uid)
    theirs = _issue(app, other)
    assert _reset(app, mine).status_code == 200
    assert _unused_count(app, other) == 1
    assert _reset(app, theirs).status_code == 200


def test_new_token_supersedes_previous(app):
    uid, _, _ = _make_user(app)
    first = _issue(app, uid)
    second = _issue(app, uid)
    assert _unused_count(app, uid) == 1
    assert _reset(app, first).status_code == 400
    assert _reset(app, second).status_code == 200


def test_legacy_plaintext_token_still_redeemable_then_single_use(app):
    uid, _, _ = _make_user(app)
    legacy = f"{uuid.uuid4().int % 10**12:012d}"
    _insert_legacy_plaintext(app, uid, legacy)
    assert _reset(app, legacy).status_code == 200
    assert _reset(app, legacy, "Another1Pass!").status_code == 400
    assert _check_pw(app, uid, RESET_PW)


def test_invalid_and_malformed_tokens_unchanged_responses(app):
    uid, _, _ = _make_user(app)
    _issue(app, uid)
    r = _reset(app, "000000000000")
    assert r.status_code == 400 and r.get_json() == {"message": "Invalid or expired token"}
    r = app.test_client().post("/api/auth/reset-password", json={"password": RESET_PW})
    assert r.status_code == 400 and r.get_json() == {"message": "Token and new password are required"}
    assert _unused_count(app, uid) == 1


def test_expired_token_response_unchanged(app):
    uid, _, _ = _make_user(app)
    raw = _issue(app, uid)
    with app.app_context():
        PasswordReset.query.filter_by(user_id=uid).update({"expires_at": utcnow() - timedelta(minutes=1)})
        db.session.commit()
    r = _reset(app, raw)
    assert r.status_code == 400 and r.get_json() == {"message": "Token has expired"}
    assert _check_pw(app, uid, OLD_PW)


# ------------------------------------------------------------ (c) OTP signup path


def test_signup_password_replacement_invalidates_pending_token(app, monkeypatch):
    """compat_signup (phone-OTP proven) replaces an existing row's password -> pending code dies."""
    uid, _, phone = _make_user(app)
    raw = _issue(app, uid)
    import kk.routes.auth as auth_routes

    monkeypatch.setattr(auth_routes, "_consume_phone_otp", lambda *a, **k: None)
    monkeypatch.setattr(auth_routes, "_access_token_for_user", lambda *a, **k: "t")
    monkeypatch.setattr(auth_routes, "_refresh_token_for_user", lambda *a, **k: "t")
    r = app.test_client().post(
        "/api/auth/signup",
        json={"phone": phone, "password": "SignupPass1!", "otp_code": "123456", "username": f"su{uuid.uuid4().hex[:8]}"},
    )
    assert r.status_code == 201, r.get_json()
    assert _unused_count(app, uid) == 0
    assert _reset(app, raw).status_code == 400
    assert _check_pw(app, uid, "SignupPass1!")


# ---------------------------------------------------------------- concurrency tests


def _run_threads(fns):
    results = [None] * len(fns)
    errors = []

    def wrap(i, fn):
        try:
            results[i] = fn()
        except BaseException as exc:  # noqa: BLE001
            errors.append(repr(exc))

    ts = [threading.Thread(target=wrap, args=(i, fn)) for i, fn in enumerate(fns)]
    for t in ts:
        t.start()
    for t in ts:
        t.join(60)
    assert not errors, errors
    assert all(not t.is_alive() for t in ts)
    return results


def _sync_after_verify(monkeypatch, parties):
    """Force every redeemer to pass ``verify_password_reset_token`` before any of them claims."""
    import kk.routes.auth as auth_routes

    barrier = threading.Barrier(parties, timeout=30)
    real = auth_routes.verify_password_reset_token

    def wrapped(token):
        out = real(token)
        barrier.wait()
        return out

    monkeypatch.setattr(auth_routes, "verify_password_reset_token", wrapped)


def test_concurrent_double_redemption_exactly_one_wins(app, monkeypatch):
    uid, _, _ = _make_user(app)
    raw = _issue(app, uid)
    _sync_after_verify(monkeypatch, 2)
    res = _run_threads(
        [lambda: _reset(app, raw, "RaceOne1Pass!"), lambda: _reset(app, raw, "RaceTwo2Pass!")]
    )
    codes = sorted(r.status_code for r in res)
    assert codes == [200, 400], codes
    loser = next(r for r in res if r.status_code == 400)
    assert loser.get_json() == {"message": "Invalid or expired token"}
    winner_pw = "RaceOne1Pass!" if res[0].status_code == 200 else "RaceTwo2Pass!"
    loser_pw = "RaceTwo2Pass!" if winner_pw == "RaceOne1Pass!" else "RaceOne1Pass!"
    assert _check_pw(app, uid, winner_pw) and not _check_pw(app, uid, loser_pw)
    assert _unused_count(app, uid) == 0


def test_change_completing_between_verify_and_claim_defeats_redemption(app, monkeypatch):
    """A redeemer already past verification loses to a change_password that commits first."""
    uid, pub, _ = _make_user(app)
    raw = _issue(app, uid)
    import kk.routes.auth as auth_routes

    verified = threading.Event()
    go = threading.Event()
    real = auth_routes.verify_password_reset_token

    def wrapped(token):
        out = real(token)
        verified.set()
        assert go.wait(30)
        return out

    monkeypatch.setattr(auth_routes, "verify_password_reset_token", wrapped)

    def redeem():
        return _reset(app, raw)

    def change():
        assert verified.wait(30)
        try:
            return _change(app, pub, OLD_PW, CHANGED_PW)
        finally:
            go.set()

    redeem_r, change_r = _run_threads([redeem, change])
    assert change_r.status_code == 200
    assert redeem_r.status_code == 400 and redeem_r.get_json() == {"message": "Invalid or expired token"}
    assert _check_pw(app, uid, CHANGED_PW) and not _check_pw(app, uid, RESET_PW)
    assert _unused_count(app, uid) == 0


@pytest.mark.parametrize("round_no", range(4))
def test_change_racing_redemption_never_leaves_usable_token(app, monkeypatch, round_no):
    uid, pub, _ = _make_user(app)
    raw = _issue(app, uid)
    start = threading.Barrier(2, timeout=30)

    def redeem():
        start.wait()
        return _reset(app, raw, RESET_PW)

    def change():
        start.wait()
        return _change(app, pub, OLD_PW, CHANGED_PW)

    redeem_r, change_r = _run_threads([redeem, change])
    assert change_r.status_code == 200
    assert redeem_r.status_code in (200, 400)
    # Whatever the interleaving: nothing usable remains and the token cannot be redeemed again.
    assert _unused_count(app, uid) == 0
    assert _reset(app, raw, "Another1Pass!").status_code == 400
    if redeem_r.status_code == 200:
        # reset then change (or change's UPDATE waited): change's password is the last writer
        assert _check_pw(app, uid, CHANGED_PW) or _check_pw(app, uid, RESET_PW)
    else:
        assert _check_pw(app, uid, CHANGED_PW)


def test_two_concurrent_password_changes_leave_no_token(app):
    uid, pub, _ = _make_user(app)
    _issue(app, uid)
    start = threading.Barrier(2, timeout=30)

    def change(pw):
        def run():
            start.wait()
            return _change(app, pub, OLD_PW, pw)

        return run

    r1, r2 = _run_threads([change("ChangeOne1Pass!"), change("ChangeTwo2Pass!")])
    assert r1.status_code == 200 and r2.status_code == 200
    assert _unused_count(app, uid) == 0
    assert _check_pw(app, uid, "ChangeOne1Pass!") or _check_pw(app, uid, "ChangeTwo2Pass!")


def test_claim_helper_is_conditional_update(app):
    from kk.auth import consume_password_reset_token

    uid, _, _ = _make_user(app)
    other, _, _ = _make_user(app)
    raw = _issue(app, uid)
    with app.app_context():
        assert consume_password_reset_token(raw, other) is False  # wrong user
        assert consume_password_reset_token("nope", uid) is False
        assert consume_password_reset_token(None, uid) is False
        assert consume_password_reset_token(raw, uid) is True
        assert consume_password_reset_token(raw, uid) is False  # already used
        db.session.commit()
