"""F-06 / F-38 regression tests: a device push token belongs to ONE account.

F-06: ``POST /api/users/push_token`` stored the token on the caller only and
never cleared the same token from other accounts, so after account A's session
ended without a server logout (expired refresh, reinstall, local clear) and B
signed in on the same phone, A's chat/listing notifications were delivered to
B's device. Registration now clears the token from every other user in the same
transaction (single-token-per-user model unchanged, no migration).

F-38 (server side): the Flutter client now completes an *expired-session*
logout by renewing the access token with the refresh token and then calling
``/api/auth/logout``. These tests pin the auth rules of that flow: only valid
proof of identity (a live access token, or a live refresh token exchanged via
``/api/auth/refresh``) can clear a token, only the proven user's own token is
ever cleared, and an expired / revoked / foreign credential clears nothing.
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

os.environ.setdefault("APP_ENV", "testing")
os.environ.setdefault("SECRET_KEY", "test-secret-key-for-f06")
os.environ.setdefault("JWT_SECRET_KEY", "test-jwt-secret-key-for-f06")

_PASSWORD = "Aa123456!"


@pytest.fixture(scope="module")
def app_ctx():
    tmp = tempfile.TemporaryDirectory(prefix="carlist_f06_", ignore_cleanup_errors=True)
    os.environ["APP_ENV"] = "testing"
    os.environ["SMS_PROVIDER"] = "console"
    os.environ["DB_PATH"] = os.path.join(tmp.name, "f06.db")

    from kk.app_factory import create_app

    app, *_ = create_app()
    from kk.models import User, db

    with app.app_context():
        db.drop_all()
        db.create_all()

    yield app, db, User

    with app.app_context():
        db.session.remove()
        db.engine.dispose()
    tmp.cleanup()


@pytest.fixture
def client(app_ctx):
    return app_ctx[0].test_client()


def _phone() -> str:
    return f"078{uuid.uuid4().int % 10**8:08d}"


def _auth(token: str) -> dict:
    return {"Authorization": f"Bearer {token}"}


class _Acct:
    def __init__(self, user_id, public_id, username, access, refresh):
        self.id = user_id
        self.public_id = public_id
        self.username = username
        self.access = access
        self.refresh = refresh


def _make_account(app_ctx, client, tag: str, *, firebase_token: str | None = None) -> _Acct:
    app, db, User = app_ctx
    with app.app_context():
        username = f"f06_{tag}_{uuid.uuid4().hex[:10]}"
        user = User(
            username=username,
            phone_number=_phone(),
            first_name="F06",
            last_name="Test",
            is_active=True,
            is_verified=True,
            phone_verified=True,
            public_id=f"f06-{tag}-{uuid.uuid4().hex[:12]}",
            firebase_token=firebase_token,
        )
        user.set_password(_PASSWORD)
        db.session.add(user)
        db.session.commit()
        user_id, public_id = user.id, user.public_id
    resp = client.post("/api/auth/login", json={"username": username, "password": _PASSWORD})
    assert resp.status_code == 200, resp.data
    body = resp.get_json()
    assert body.get("refresh_token"), body
    return _Acct(user_id, public_id, username, body["access_token"], body["refresh_token"])


def _token_of(app_ctx, user_id: int):
    app, db, User = app_ctx
    with app.app_context():
        db.session.expire_all()
        user = db.session.get(User, user_id)
        return user.firebase_token if user else None


def _holders(app_ctx, token: str) -> list[int]:
    app, db, User = app_ctx
    with app.app_context():
        db.session.expire_all()
        return sorted(u.id for u in User.query.filter(User.firebase_token == token).all())


def _set_token(app_ctx, user_id: int, token) -> None:
    app, db, User = app_ctx
    with app.app_context():
        db.session.get(User, user_id).firebase_token = token
        db.session.commit()


def _register(client, acct: _Acct, token, **extra):
    payload = dict(extra)
    if token is not None:
        payload["token"] = token
    return client.post("/api/users/push_token", json=payload, headers=_auth(acct.access))


def _tok() -> str:
    return f"fcm-{uuid.uuid4().hex}"


# --------------------------------------------------------------------------
# F-06: backend de-duplication
# --------------------------------------------------------------------------


def test_token_moves_from_a_to_b_and_clears_a(app_ctx, client):
    a = _make_account(app_ctx, client, "movea")
    b = _make_account(app_ctx, client, "moveb")
    t = _tok()

    assert _register(client, a, t).status_code == 200
    assert _holders(app_ctx, t) == [a.id]

    resp = _register(client, b, t)
    assert resp.status_code == 200, resp.data
    assert _holders(app_ctx, t) == [b.id]
    assert _token_of(app_ctx, a.id) is None
    assert _token_of(app_ctx, b.id) == t


def test_a_can_reregister_later_and_clears_b(app_ctx, client):
    a = _make_account(app_ctx, client, "rea")
    b = _make_account(app_ctx, client, "reb")
    t = _tok()

    _register(client, a, t)
    _register(client, b, t)
    assert _holders(app_ctx, t) == [b.id]

    assert _register(client, a, t).status_code == 200
    assert _holders(app_ctx, t) == [a.id]
    assert _token_of(app_ctx, b.id) is None


def test_same_user_reregister_is_idempotent_and_leaves_others_alone(app_ctx, client):
    a = _make_account(app_ctx, client, "idema")
    other = _make_account(app_ctx, client, "idemo")
    t, other_t = _tok(), _tok()
    _register(client, other, other_t)

    for _ in range(3):
        resp = _register(client, a, t)
        assert resp.status_code == 200
        assert resp.get_json()["registered"] is True
    assert _holders(app_ctx, t) == [a.id]
    assert _token_of(app_ctx, other.id) == other_t


def test_registering_a_different_token_replaces_own_and_never_touches_others(app_ctx, client):
    a = _make_account(app_ctx, client, "rota")
    b = _make_account(app_ctx, client, "rotb")
    old, new, b_tok = _tok(), _tok(), _tok()
    _register(client, a, old)
    _register(client, b, b_tok)

    # FCM token rotation for A: the new token replaces A's old one (single
    # token per user) and B's unrelated token is untouched.
    assert _register(client, a, new).status_code == 200
    assert _token_of(app_ctx, a.id) == new
    assert _holders(app_ctx, old) == []
    assert _token_of(app_ctx, b.id) == b_tok


def test_token_is_trimmed_before_comparison(app_ctx, client):
    a = _make_account(app_ctx, client, "trima")
    b = _make_account(app_ctx, client, "trimb")
    t = _tok()
    _register(client, a, t)
    assert _register(client, b, f"  {t}  ").status_code == 200
    assert _holders(app_ctx, t) == [b.id]


def test_blank_token_is_rejected_and_changes_nothing(app_ctx, client):
    a = _make_account(app_ctx, client, "blanka")
    b = _make_account(app_ctx, client, "blankb")
    ta, tb = _tok(), _tok()
    _register(client, a, ta)
    _register(client, b, tb)

    for bad in ("", "   ", None):
        resp = _register(client, a, bad)
        assert resp.status_code == 400, resp.data
    assert _token_of(app_ctx, a.id) == ta
    assert _token_of(app_ctx, b.id) == tb


def test_disable_clears_only_the_callers_own_token(app_ctx, client):
    a = _make_account(app_ctx, client, "disa")
    b = _make_account(app_ctx, client, "disb")
    ta, tb = _tok(), _tok()
    _register(client, a, ta)
    _register(client, b, tb)

    resp = _register(client, a, None, enabled=False)
    assert resp.status_code == 200, resp.data
    assert _token_of(app_ctx, a.id) is None
    assert _token_of(app_ctx, b.id) == tb

    # Disabling with a token field naming B's token must not clear B either.
    resp = client.post(
        "/api/users/push_token",
        json={"enabled": False, "token": tb},
        headers=_auth(a.access),
    )
    assert resp.status_code == 200
    assert _token_of(app_ctx, b.id) == tb


def test_preexisting_duplicate_rows_are_all_cleared_by_the_next_registration(app_ctx, client):
    a = _make_account(app_ctx, client, "dupa")
    b = _make_account(app_ctx, client, "dupb")
    c = _make_account(app_ctx, client, "dupc")
    t = _tok()
    # Legacy data from before the fix: several accounts hold the same token.
    _set_token(app_ctx, a.id, t)
    _set_token(app_ctx, b.id, t)
    assert _holders(app_ctx, t) == sorted([a.id, b.id])

    assert _register(client, c, t).status_code == 200
    assert _holders(app_ctx, t) == [c.id]


def test_concurrent_registration_of_one_token_never_leaves_two_owners(app_ctx):
    app, _db, _User = app_ctx
    accounts = [
        _make_account(app_ctx, app.test_client(), f"race{i}") for i in range(4)
    ]
    t = _tok()
    statuses: list[int] = []
    barrier = threading.Barrier(len(accounts))

    def worker(acct):
        c = app.test_client()
        barrier.wait()
        statuses.append(_register(c, acct, t).status_code)

    threads = [threading.Thread(target=worker, args=(a,)) for a in accounts]
    for th in threads:
        th.start()
    for th in threads:
        th.join(timeout=60)

    assert 200 in statuses
    assert len(_holders(app_ctx, t)) <= 1


def test_unauthenticated_registration_is_rejected(app_ctx, client):
    assert client.post("/api/users/push_token", json={"token": _tok()}).status_code in (401, 422)


def test_be05_conditional_cleanup_does_not_clear_the_new_owner(app_ctx, client):
    """The BE-05 conditional UPDATE (id AND token) must stay a safe no-op for
    the account the token moved away from, and must still clear the new owner
    if FCM rejects it for that owner."""
    from kk.push import _clear_invalidated_token

    app, _db, _User = app_ctx
    a = _make_account(app_ctx, client, "be05a")
    b = _make_account(app_ctx, client, "be05b")
    t = _tok()
    _register(client, a, t)
    _register(client, b, t)

    with app.app_context():
        _clear_invalidated_token(a.id, t)
    assert _token_of(app_ctx, b.id) == t

    with app.app_context():
        _clear_invalidated_token(b.id, t)
    assert _token_of(app_ctx, b.id) is None


def test_moved_token_is_no_longer_reported_as_registered_for_the_old_account(app_ctx, client):
    a = _make_account(app_ctx, client, "stata")
    b = _make_account(app_ctx, client, "statb")
    t = _tok()
    _register(client, a, t)
    _register(client, b, t)

    assert client.get("/api/users/push_status", headers=_auth(a.access)).get_json()["registered"] is False
    assert client.get("/api/users/push_status", headers=_auth(b.access)).get_json()["registered"] is True


# --------------------------------------------------------------------------
# F-38: expired-session logout -- what may (not) clear a push token
# --------------------------------------------------------------------------


def _expired_access(app_ctx, public_id: str) -> str:
    from flask_jwt_extended import create_access_token

    app, _db, _User = app_ctx
    with app.app_context():
        return create_access_token(identity=public_id, expires_delta=timedelta(seconds=-60))


def _expired_refresh(app_ctx, public_id: str) -> str:
    from flask_jwt_extended import create_refresh_token

    app, _db, _User = app_ctx
    with app.app_context():
        return create_refresh_token(identity=public_id, expires_delta=timedelta(seconds=-60))


def test_logout_with_valid_access_token_clears_own_token(app_ctx, client):
    a = _make_account(app_ctx, client, "lo")
    t = _tok()
    _register(client, a, t)
    resp = client.post("/api/auth/logout", headers=_auth(a.access), json={"refresh_token": a.refresh})
    assert resp.status_code == 200, resp.data
    assert _token_of(app_ctx, a.id) is None


def test_expired_access_token_cannot_logout_or_clear_anything(app_ctx, client):
    a = _make_account(app_ctx, client, "expacc")
    t = _tok()
    _register(client, a, t)
    expired = _expired_access(app_ctx, a.public_id)

    resp = client.post("/api/auth/logout", headers=_auth(expired), json={"refresh_token": a.refresh})
    assert resp.status_code == 401
    assert _token_of(app_ctx, a.id) == t
    # ... and the refresh token it carried was NOT revoked by the rejected call.
    assert client.post("/api/auth/refresh", headers=_auth(a.refresh)).status_code == 200


def test_expired_session_logout_via_refresh_clears_token_and_revokes_refresh(app_ctx, client):
    """The client flow: 401 on logout -> /auth/refresh with the refresh token ->
    retry /auth/logout with the NEW access + NEW refresh token."""
    a = _make_account(app_ctx, client, "flow")
    t = _tok()
    _register(client, a, t)
    expired = _expired_access(app_ctx, a.public_id)

    assert client.post("/api/auth/logout", headers=_auth(expired), json={"refresh_token": a.refresh}).status_code == 401

    renewed = client.post("/api/auth/refresh", headers=_auth(a.refresh))
    assert renewed.status_code == 200, renewed.data
    new_access = renewed.get_json()["access_token"]
    new_refresh = renewed.get_json()["refresh_token"]
    assert _token_of(app_ctx, a.id) == t  # refresh alone clears nothing

    out = client.post("/api/auth/logout", headers=_auth(new_access), json={"refresh_token": new_refresh})
    assert out.status_code == 200, out.data
    assert _token_of(app_ctx, a.id) is None
    # The session is fully dead: neither the new refresh nor the rotated-away
    # old one can mint another access token.
    assert client.post("/api/auth/refresh", headers=_auth(new_refresh)).status_code == 401
    assert client.post("/api/auth/refresh", headers=_auth(a.refresh)).status_code == 401
    # and the logged-out access token itself is revoked
    assert client.post("/api/auth/logout", headers=_auth(new_access)).status_code == 401


def test_expired_refresh_token_cannot_refresh_or_clear(app_ctx, client):
    a = _make_account(app_ctx, client, "exprt")
    t = _tok()
    _register(client, a, t)
    dead = _expired_refresh(app_ctx, a.public_id)

    assert client.post("/api/auth/refresh", headers=_auth(dead)).status_code == 401
    assert client.post("/api/auth/logout", headers=_auth(dead)).status_code in (401, 422)
    assert _token_of(app_ctx, a.id) == t


def test_garbage_and_missing_credentials_cannot_clear_anything(app_ctx, client):
    a = _make_account(app_ctx, client, "junk")
    t = _tok()
    _register(client, a, t)

    for headers in ({}, _auth("not.a.jwt"), _auth("a.b.c"), {"Authorization": "Bearer "}):
        assert client.post("/api/auth/logout", headers=headers, json={"refresh_token": a.refresh}).status_code in (401, 422)
        assert client.post("/api/auth/refresh", headers=headers).status_code in (401, 422)
    assert _token_of(app_ctx, a.id) == t


def test_refresh_token_cannot_be_used_directly_as_an_access_credential(app_ctx, client):
    a = _make_account(app_ctx, client, "rtbearer")
    t = _tok()
    _register(client, a, t)

    assert client.post("/api/auth/logout", headers=_auth(a.refresh)).status_code in (401, 422)
    assert client.post("/api/users/push_token", json={"enabled": False}, headers=_auth(a.refresh)).status_code in (401, 422)
    assert _token_of(app_ctx, a.id) == t


def test_access_token_cannot_be_used_as_a_refresh_credential(app_ctx, client):
    a = _make_account(app_ctx, client, "atrefresh")
    assert client.post("/api/auth/refresh", headers=_auth(a.access)).status_code in (401, 422)


def test_reused_rotated_refresh_token_is_rejected(app_ctx, client):
    a = _make_account(app_ctx, client, "reuse")
    first = client.post("/api/auth/refresh", headers=_auth(a.refresh))
    assert first.status_code == 200
    assert client.post("/api/auth/refresh", headers=_auth(a.refresh)).status_code == 401


def test_wrong_user_credentials_never_clear_someone_elses_token(app_ctx, client):
    a = _make_account(app_ctx, client, "victim")
    b = _make_account(app_ctx, client, "attacker")
    ta, tb = _tok(), _tok()
    _register(client, a, ta)
    _register(client, b, tb)

    # B's valid access token + A's refresh token in the body: only B's own
    # session ends; A's push token and A's refresh token are untouched.
    resp = client.post("/api/auth/logout", headers=_auth(b.access), json={"refresh_token": a.refresh})
    assert resp.status_code == 200, resp.data
    assert _token_of(app_ctx, a.id) == ta
    assert _token_of(app_ctx, b.id) is None
    assert client.post("/api/auth/refresh", headers=_auth(a.refresh)).status_code == 200

    # B's expired access token + A's live refresh token: nothing happens.
    b2 = _make_account(app_ctx, client, "attacker2")
    _register(client, b2, _tok())
    expired_b = _expired_access(app_ctx, b2.public_id)
    a2 = _make_account(app_ctx, client, "victim2")
    ta2 = _tok()
    _register(client, a2, ta2)
    resp = client.post("/api/auth/logout", headers=_auth(expired_b), json={"refresh_token": a2.refresh})
    assert resp.status_code == 401
    assert _token_of(app_ctx, a2.id) == ta2
    assert client.post("/api/auth/refresh", headers=_auth(a2.refresh)).status_code == 200


def test_refresh_for_one_user_never_logs_out_or_clears_another(app_ctx, client):
    a = _make_account(app_ctx, client, "indepa")
    b = _make_account(app_ctx, client, "indepb")
    ta, tb = _tok(), _tok()
    _register(client, a, ta)
    _register(client, b, tb)

    renewed = client.post("/api/auth/refresh", headers=_auth(a.refresh)).get_json()
    client.post(
        "/api/auth/logout",
        headers=_auth(renewed["access_token"]),
        json={"refresh_token": renewed["refresh_token"]},
    )
    assert _token_of(app_ctx, a.id) is None
    assert _token_of(app_ctx, b.id) == tb
    assert client.post("/api/auth/refresh", headers=_auth(b.refresh)).status_code == 200


def test_logout_after_token_moved_does_not_clear_the_new_owner_via_dedup_gap(app_ctx, client):
    """Documented single-token model: A's logout clears A's CURRENT token only.
    After the token moved to B, A has none, so A's (expired-session) logout can
    never disturb B's registration."""
    a = _make_account(app_ctx, client, "gapa")
    b = _make_account(app_ctx, client, "gapb")
    t = _tok()
    _register(client, a, t)
    _register(client, b, t)

    resp = client.post("/api/auth/logout", headers=_auth(a.access), json={"refresh_token": a.refresh})
    assert resp.status_code == 200
    assert _token_of(app_ctx, b.id) == t
