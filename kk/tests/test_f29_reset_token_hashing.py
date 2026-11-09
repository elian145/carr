"""F-29: password-reset tokens are hashed at rest (HMAC-SHA256 with a server pepper).

Public behaviour is unchanged (token format, 1h expiry, single use, generic responses);
only the stored representation changes. Uses a minimal Flask app (real models, real
``kk.routes.auth`` blueprint, real SQLite file) instead of ``create_app()`` so the module
does not run the whole alembic chain.
"""

from __future__ import annotations

import hmac
import logging
import os
import re
import sqlite3
import tempfile
import uuid
from datetime import timedelta

import pytest
from flask import Flask
from sqlalchemy import text

from kk.models import PasswordReset, User, db
from kk.reset_token_crypto import (
    HASH_PREFIX,
    HASHED_TOKEN_LEN,
    INVALID_TOKEN_SENTINEL,
    LEGACY_PLAINTEXT_ENV,
    hash_reset_token,
)
from kk.time_utils import utcnow

SECRET = "f29-test-secret-key-0123456789"
GENERIC = {"message": "If the account exists, a reset code has been sent"}


@pytest.fixture(scope="module")
def ctx():
    tmp = tempfile.TemporaryDirectory(prefix="carlist_f29_", ignore_cleanup_errors=True)
    saved = {k: os.environ.get(k) for k in ("APP_ENV", "SECRET_KEY", "ALLOW_DEV_CODE_IN_RESPONSE", LEGACY_PLAINTEXT_ENV)}
    os.environ["APP_ENV"] = "testing"
    os.environ.pop("ALLOW_DEV_CODE_IN_RESPONSE", None)
    os.environ.pop(LEGACY_PLAINTEXT_ENV, None)
    db_path = os.path.join(tmp.name, "f29.db")
    app = Flask("kk", static_folder=None)
    app.config.update(
        SECRET_KEY=SECRET,
        SQLALCHEMY_DATABASE_URI="sqlite:///" + db_path.replace("\\", "/"),
        SQLALCHEMY_TRACK_MODIFICATIONS=False,
        TESTING=True,
    )
    db.init_app(app)
    from kk.routes.auth import bp as auth_bp

    app.register_blueprint(auth_bp)
    with app.app_context():
        db.create_all()
    yield app, db_path
    with app.app_context():
        db.session.remove()
        db.engine.dispose()
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
def db_path(ctx):
    return ctx[1]


@pytest.fixture(autouse=True)
def _no_ip_rate_limits(monkeypatch):
    import kk.security as security_module

    monkeypatch.setattr(security_module, "check_rate_limit", lambda *a, **kw: None)
    # The reset route's inline per-account guard uses Redis; in testing without Redis the
    # in-memory escape hatch applies, nothing to patch.


def _phone() -> str:
    return f"077{uuid.uuid4().int % 10**8:08d}"


def _make_user(app) -> int:
    with app.app_context():
        u = User(
            username=f"f29_{uuid.uuid4().hex[:10]}",
            phone_number=_phone(),
            first_name="F29",
            last_name="Test",
            email=None,
            is_active=True,
            is_verified=True,
            phone_verified=True,
            public_id=f"pub-{uuid.uuid4().hex[:12]}",
        )
        u.set_password("Original1!")
        db.session.add(u)
        db.session.commit()
        return u.id


def _raw_rows(db_path):
    con = sqlite3.connect(db_path)
    try:
        return con.execute("select id, user_id, token, is_used from password_reset order by id").fetchall()
    finally:
        con.close()


def _db_file_bytes(db_path):
    with open(db_path, "rb") as fh:
        return fh.read()


def _insert_legacy_plaintext(app, user_id, raw, *, expires_in=timedelta(hours=1), used=False):
    """Simulate a row written by the pre-F-29 code (plaintext token column)."""
    with app.app_context():
        db.session.execute(
            text(
                "insert into password_reset (user_id, token, expires_at, is_used, created_at) "
                "values (:u, :t, :e, :used, :c)"
            ),
            {"u": user_id, "t": raw, "e": utcnow() + expires_in, "used": used, "c": utcnow()},
        )
        db.session.commit()


# ----------------------------------------------------------------------------------------
# A. storage: raw token never in the DB
# ----------------------------------------------------------------------------------------


@pytest.mark.parametrize("channel", ["sms", "email"])
def test_raw_token_is_never_stored(app, db_path, channel):
    from kk.auth import create_password_reset_token

    uid = _make_user(app)
    with app.app_context():
        user = db.session.get(User, uid)
        raw = create_password_reset_token(user, channel=channel)
    if channel == "sms":
        assert re.fullmatch(r"\d{12}", raw)
    else:
        assert re.fullmatch(r"[A-Za-z0-9_\-]{43}", raw)  # token_urlsafe(32) format unchanged
    rows = [r for r in _raw_rows(db_path) if r[1] == uid]
    assert len(rows) == 1
    stored = rows[0][2]
    assert stored != raw and raw not in stored
    assert stored.startswith(HASH_PREFIX) and len(stored) == HASHED_TOKEN_LEN
    assert re.fullmatch(r"h1\$[0-9a-f]{64}", stored)
    with app.app_context():
        assert stored == hash_reset_token(raw)
    # nowhere in the raw DB bytes (incl. free pages / WAL-less file)
    assert raw.encode() not in _db_file_bytes(db_path)


def test_hash_fits_existing_column_so_no_migration_is_needed():
    col = PasswordReset.__table__.c.token
    assert col.type.impl.length == 100
    assert HASHED_TOKEN_LEN == 67 <= col.type.impl.length
    assert col.unique


def test_orm_attribute_after_reload_is_hash_not_raw(app):
    from kk.auth import create_password_reset_token

    uid = _make_user(app)
    with app.app_context():
        raw = create_password_reset_token(db.session.get(User, uid), channel="sms")
        db.session.expire_all()
        row = PasswordReset.query.filter_by(user_id=uid).one()
        assert row.token != raw and row.token.startswith(HASH_PREFIX)
        assert raw not in repr(row)


# ----------------------------------------------------------------------------------------
# B. verify accepts / rejects
# ----------------------------------------------------------------------------------------


def test_valid_token_verifies_and_returns_user(app):
    from kk.auth import create_password_reset_token, verify_password_reset_token

    uid = _make_user(app)
    with app.app_context():
        raw = create_password_reset_token(db.session.get(User, uid), channel="sms")
        user, err = verify_password_reset_token(raw)
        assert err is None and user.id == uid


def test_wrong_token_rejected(app):
    from kk.auth import create_password_reset_token, verify_password_reset_token

    uid = _make_user(app)
    with app.app_context():
        raw = create_password_reset_token(db.session.get(User, uid), channel="sms")
        wrong = f"{(int(raw) + 1) % 10**12:012d}"
        user, err = verify_password_reset_token(wrong)
        assert user is None and err == "Invalid or expired token"


def test_expired_token_rejected_and_marked_used(app, db_path):
    from kk.auth import create_password_reset_token, verify_password_reset_token

    uid = _make_user(app)
    with app.app_context():
        raw = create_password_reset_token(db.session.get(User, uid), channel="sms")
        row = PasswordReset.query.filter_by(user_id=uid).one()
        row.expires_at = utcnow() - timedelta(seconds=1)
        db.session.commit()
        user, err = verify_password_reset_token(raw)
        assert user is None and err == "Token has expired"
        user2, err2 = verify_password_reset_token(raw)
        assert user2 is None and err2 == "Invalid or expired token"
    assert [r[3] for r in _raw_rows(db_path) if r[1] == uid] == [1]


def test_used_token_rejected(app):
    from kk.auth import create_password_reset_token, verify_password_reset_token

    uid = _make_user(app)
    with app.app_context():
        raw = create_password_reset_token(db.session.get(User, uid), channel="sms")
        PasswordReset.query.filter_by(user_id=uid).one().is_used = True
        db.session.commit()
        assert verify_password_reset_token(raw) == (None, "Invalid or expired token")


def test_new_token_supersedes_previous_unused_token(app):
    from kk.auth import create_password_reset_token, verify_password_reset_token

    uid = _make_user(app)
    with app.app_context():
        user = db.session.get(User, uid)
        first = create_password_reset_token(user, channel="sms")
        second = create_password_reset_token(user, channel="sms")
        assert verify_password_reset_token(first)[0] is None
        assert verify_password_reset_token(second)[0].id == uid
        assert PasswordReset.query.filter_by(user_id=uid).count() == 1


def test_stored_hash_cannot_be_replayed_as_a_token(app):
    """A DB-dump holder must not be able to use the stored value as the token."""
    from kk.auth import create_password_reset_token, verify_password_reset_token

    uid = _make_user(app)
    with app.app_context():
        create_password_reset_token(db.session.get(User, uid), channel="sms")
        stored = PasswordReset.query.filter_by(user_id=uid).one().token
        assert verify_password_reset_token(stored) == (None, "Invalid or expired token")
        assert verify_password_reset_token(stored[len(HASH_PREFIX):]) == (None, "Invalid or expired token")


@pytest.mark.parametrize("bad", [None, "", 123456789012, ["x"], {"a": 1}, "x" * 5000, INVALID_TOKEN_SENTINEL, True])
def test_malformed_tokens_are_rejected_without_error(app, bad):
    from kk.auth import verify_password_reset_token

    with app.app_context():
        user, err = verify_password_reset_token(bad)
    assert user is None and err == "Invalid or expired token"


def test_hash_depends_on_server_pepper(app):
    with app.app_context():
        h1 = hash_reset_token("123456789012")
        assert h1 == hash_reset_token("123456789012")  # deterministic -> usable for lookup
        app.config["SECRET_KEY"] = "another-secret"
        try:
            assert hash_reset_token("123456789012") != h1
        finally:
            app.config["SECRET_KEY"] = SECRET


def test_missing_secret_fails_closed(app, monkeypatch):
    monkeypatch.delenv("SECRET_KEY", raising=False)
    with app.app_context():
        app.config["SECRET_KEY"] = ""
        try:
            with pytest.raises(RuntimeError):
                hash_reset_token("123456789012")
        finally:
            app.config["SECRET_KEY"] = SECRET


def test_comparison_is_constant_time(app, monkeypatch):
    """The DB match is confirmed with hmac.compare_digest (timing-safe)."""
    import kk.reset_token_crypto as crypto
    from kk.auth import create_password_reset_token, verify_password_reset_token

    calls = []
    real = hmac.compare_digest

    def spy(a, b):
        calls.append((len(a), len(b)))
        return real(a, b)

    monkeypatch.setattr(crypto.hmac, "compare_digest", spy)
    uid = _make_user(app)
    with app.app_context():
        raw = create_password_reset_token(db.session.get(User, uid), channel="sms")
        assert verify_password_reset_token(raw)[0].id == uid
    assert calls and all(a == b == HASHED_TOKEN_LEN for a, b in calls)


# ----------------------------------------------------------------------------------------
# C. legacy plaintext transition
# ----------------------------------------------------------------------------------------


def test_legacy_plaintext_row_still_works_then_is_scrubbed(app, db_path):
    from kk.auth import verify_password_reset_token

    uid = _make_user(app)
    raw = f"{uuid.uuid4().int % 10**12:012d}"
    _insert_legacy_plaintext(app, uid, raw)
    assert [r[2] for r in _raw_rows(db_path) if r[1] == uid] == [raw]  # plaintext at rest (legacy)
    with app.app_context():
        user, err = verify_password_reset_token(raw)
        assert err is None and user.id == uid
    # first use rewrote it to the hashed form; plaintext is gone from the DB
    stored = [r[2] for r in _raw_rows(db_path) if r[1] == uid]
    assert len(stored) == 1 and stored[0].startswith(HASH_PREFIX)
    with app.app_context():
        assert stored[0] == hash_reset_token(raw)
        assert verify_password_reset_token(raw)[0].id == uid  # now via the hash path

def test_legacy_plaintext_disabled_by_flag(app, monkeypatch):
    from kk.auth import verify_password_reset_token

    uid = _make_user(app)
    raw = f"{uuid.uuid4().int % 10**12:012d}"
    _insert_legacy_plaintext(app, uid, raw)
    monkeypatch.setenv(LEGACY_PLAINTEXT_ENV, "0")
    with app.app_context():
        assert verify_password_reset_token(raw) == (None, "Invalid or expired token")
    monkeypatch.delenv(LEGACY_PLAINTEXT_ENV)
    with app.app_context():
        assert verify_password_reset_token(raw)[0].id == uid


def test_legacy_expired_and_used_rows_are_rejected(app):
    from kk.auth import verify_password_reset_token

    uid = _make_user(app)
    exp = f"{uuid.uuid4().int % 10**12:012d}"
    used = f"{uuid.uuid4().int % 10**12:012d}"
    _insert_legacy_plaintext(app, uid, exp, expires_in=timedelta(seconds=-5))
    _insert_legacy_plaintext(app, uid, used, used=True)
    with app.app_context():
        assert verify_password_reset_token(exp) == (None, "Token has expired")
        assert verify_password_reset_token(used) == (None, "Invalid or expired token")


def test_legacy_path_does_not_accept_hash_shaped_input(app):
    """A legacy row whose plaintext starts with the hash prefix is impossible to claim."""
    from kk.auth import verify_password_reset_token

    uid = _make_user(app)
    fake = HASH_PREFIX + "a" * 64
    _insert_legacy_plaintext(app, uid, fake)
    with app.app_context():
        assert verify_password_reset_token(fake) == (None, "Invalid or expired token")


# ----------------------------------------------------------------------------------------
# D. clearing: use / supersede / helper
# ----------------------------------------------------------------------------------------


def test_invalidate_helper_marks_unused_tokens_used(app):
    from kk.auth import create_password_reset_token, invalidate_password_reset_tokens, verify_password_reset_token

    uid = _make_user(app)
    with app.app_context():
        raw = create_password_reset_token(db.session.get(User, uid), channel="sms")
        invalidate_password_reset_tokens(uid)
        db.session.commit()
        assert verify_password_reset_token(raw) == (None, "Invalid or expired token")


# ----------------------------------------------------------------------------------------
# E. through the real routes (forgot-password -> reset-password)
# ----------------------------------------------------------------------------------------


def _forgot(app, monkeypatch, phone):
    sent = {}

    def fake_sms(dest, token, locale=None):
        sent["token"] = token
        return True

    monkeypatch.setattr("kk.sms_service.send_password_reset_sms", fake_sms)
    r = app.test_client().post("/api/auth/forgot-password", json={"phone_number": phone})
    return r, sent.get("token")


def _user_phone(app, uid):
    with app.app_context():
        return db.session.get(User, uid).phone_number


def test_route_flow_hashes_at_rest_and_is_single_use(app, db_path, monkeypatch, caplog):
    caplog.set_level(logging.DEBUG)
    uid = _make_user(app)
    r, raw = _forgot(app, monkeypatch, _user_phone(app, uid))
    assert r.status_code == 200 and r.get_json() == GENERIC
    assert raw and re.fullmatch(r"\d{12}", raw)
    assert raw.encode() not in _db_file_bytes(db_path)
    assert [x[2][:3] for x in _raw_rows(db_path) if x[1] == uid] == [HASH_PREFIX]

    c = app.test_client()
    ok = c.post("/api/auth/reset-password", json={"token": raw, "password": "NewPassw0rd!"})
    assert ok.status_code == 200, ok.data
    assert [x[3] for x in _raw_rows(db_path) if x[1] == uid] == [1]  # consumed by the (unchanged) route
    replay = c.post("/api/auth/reset-password", json={"token": raw, "password": "Another1Pass!"})
    assert replay.status_code == 400
    with app.app_context():
        assert db.session.get(User, uid).check_password("NewPassw0rd!")
    assert raw not in caplog.text


def test_route_wrong_and_garbage_tokens(app):
    c = app.test_client()
    for tok in ("000000000000", 123456789012, ["1"], "x" * 400):
        r = c.post("/api/auth/reset-password", json={"token": tok, "password": "NewPassw0rd!"})
        assert r.status_code == 400, (tok, r.data)


def test_route_legacy_plaintext_token_still_resets_once(app, db_path):
    uid = _make_user(app)
    raw = f"{uuid.uuid4().int % 10**12:012d}"
    _insert_legacy_plaintext(app, uid, raw)
    c = app.test_client()
    ok = c.post("/api/auth/reset-password", json={"token": raw, "password": "NewPassw0rd!"})
    assert ok.status_code == 200, ok.data
    rows = [x for x in _raw_rows(db_path) if x[1] == uid]
    assert len(rows) == 1 and rows[0][2].startswith(HASH_PREFIX) and rows[0][3] == 1
    replay = c.post("/api/auth/reset-password", json={"token": raw, "password": "Another1Pass!"})
    assert replay.status_code == 400


def test_dev_code_not_exposed_by_default(app, monkeypatch):
    uid = _make_user(app)
    r, _raw = _forgot(app, monkeypatch, _user_phone(app, uid))
    assert "dev_code" not in r.get_json()


# ----------------------------------------------------------------------------------------
# F. e-mail verification tokens (same at-rest treatment, separate pepper context)
# ----------------------------------------------------------------------------------------


def _ev_rows(db_path):
    con = sqlite3.connect(db_path)
    try:
        return con.execute("select user_id, token, is_used from email_verification order by id").fetchall()
    finally:
        con.close()


def test_email_verification_token_hashed_at_rest_single_use_and_domain_separated(app, db_path):
    from kk.auth import create_email_verification_token, verify_email_verification_token
    from kk.reset_token_crypto import hash_email_verification_token

    uid = _make_user(app)
    with app.app_context():
        raw = create_email_verification_token(db.session.get(User, uid))
        stored = [r[1] for r in _ev_rows(db_path) if r[0] == uid]
        assert stored == [hash_email_verification_token(raw)]
        assert re.fullmatch(r"h1\$[0-9a-f]{64}", stored[0]) and raw not in stored[0]
        assert hash_email_verification_token(raw) != hash_reset_token(raw)
        assert raw.encode() not in _db_file_bytes(db_path)
        # submitting the stored hash as the "token" must not verify
        assert verify_email_verification_token(stored[0])[0] is None
        user, err = verify_email_verification_token(raw)
        assert err is None and user.id == uid
        assert verify_email_verification_token(raw)[0] is None  # single use


def test_email_verification_expired_and_legacy_plaintext(app, db_path, monkeypatch):
    from kk.auth import create_email_verification_token, verify_email_verification_token
    from kk.models import EmailVerification

    uid = _make_user(app)
    with app.app_context():
        raw = create_email_verification_token(db.session.get(User, uid))
        EmailVerification.query.filter_by(user_id=uid).update({"expires_at": utcnow() - timedelta(minutes=1)})
        db.session.commit()
        assert verify_email_verification_token(raw) == (None, "Token has expired")

        # pre-change row holding a plaintext token still works once while the legacy flag is on
        db.session.execute(
            text("insert into email_verification (user_id, token, expires_at, is_used, created_at) "
                 "values (:u, 'legacy-plain-token', :e, 0, :c)"),
            {"u": uid, "e": utcnow() + timedelta(hours=1), "c": utcnow()},
        )
        db.session.commit()
        monkeypatch.setenv(LEGACY_PLAINTEXT_ENV, "0")
        assert verify_email_verification_token("legacy-plain-token")[0] is None
        monkeypatch.delenv(LEGACY_PLAINTEXT_ENV)
        user, err = verify_email_verification_token("legacy-plain-token")
        assert err is None and user.id == uid
        assert verify_email_verification_token("legacy-plain-token")[0] is None
