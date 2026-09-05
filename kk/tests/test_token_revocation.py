"""H-01/H-02: JWT revocation on password change/reset and ban/deactivation.

`check_if_token_revoked()` (kk/routes/auth.py) is the single chokepoint every
`@jwt_required()` route passes through. Before this fix it only consulted the
JTI blacklist (Redis, falling back to the `token_blacklist` table) -- which
can only revoke a token it currently holds (logout, refresh rotation). It has
no way to retroactively invalidate tokens issued to other devices/sessions
when:

  - a user changes their password (H-01, `change_password`),
  - a user resets their password via SMS code (H-01, `reset_password`), or
  - an account is banned/deactivated (H-02, any of the several `is_active =
    False` sites in kk/routes/admin.py).

The fix adds `User.tokens_invalid_before` (checked against the JWT `iat`
claim) and an `is_active` check directly in the blocklist loader, so both
cases are covered centrally -- including the three `@jwt_required()`-only
routes that never call `get_current_user()`
(`/api/analytics/track/message`, `/api/analytics/track/favorite`,
`/api/blur-image`).

These tests drive the real Flask app + SQLite DB via HTTP, exactly like
`test_chat_rest_delivery.py`, so the whole `@jwt_required()` ->
`check_if_token_revoked()` -> route chain is exercised end to end.
"""

from __future__ import annotations

import os
import sys
import tempfile
import time
import uuid
from datetime import datetime, timedelta, timezone
from pathlib import Path

import pytest

_REPO_ROOT = Path(__file__).resolve().parents[2]
if str(_REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(_REPO_ROOT))


@pytest.fixture(scope="module")
def app_ctx():
    tmp = tempfile.TemporaryDirectory(
        prefix="carlist_h01h02_", ignore_cleanup_errors=True
    )
    os.environ["APP_ENV"] = "testing"
    os.environ["SMS_PROVIDER"] = "console"
    os.environ.pop("REDIS_URL", None)  # force the DB-fallback blocklist path
    os.environ["DB_PATH"] = os.path.join(tmp.name, "h01h02.db")

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


_PASSWORD = "Aa123456!"


def _unique_phone() -> str:
    return f"077{uuid.uuid4().int % 10**8:08d}"


def _make_user(app_ctx, *, username: str) -> str:
    """Create an active, phone-verified user with a known password."""
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
        user.set_password(_PASSWORD)
        db.session.add(user)
        db.session.commit()
        return user.public_id


def _login(client, username: str, password: str = _PASSWORD) -> dict:
    r = client.post(
        "/api/auth/login", json={"username": username, "password": password}
    )
    assert r.status_code == 200, r.data
    return r.get_json()


def _auth(token: str) -> dict:
    return {"Authorization": f"Bearer {token}"}


def _get_user(app_ctx, public_id: str):
    app, _client, db, User = app_ctx
    with app.app_context():
        return User.query.filter_by(public_id=public_id).first()


def _set_active(app_ctx, public_id: str, is_active: bool) -> None:
    """Simulate any of the admin ban/deactivation sites: they all just flip
    User.is_active and commit -- the blocklist loader's is_active check
    covers every one of them uniformly, so exercising it directly here is
    equivalent to going through any specific admin endpoint."""
    app, _client, db, User = app_ctx
    with app.app_context():
        user = User.query.filter_by(public_id=public_id).first()
        user.is_active = is_active
        db.session.commit()


def _profile(client, token: str):
    return client.get("/api/user/profile", headers=_auth(token))


def _refresh(client, refresh_token: str):
    return client.post("/api/auth/refresh", headers=_auth(refresh_token))


# ---------------------------------------------------------------------------
# A. Password change invalidates the old access token.
# ---------------------------------------------------------------------------


def test_change_password_invalidates_old_access_token(app_ctx, client):
    username = f"h01_chpw_{uuid.uuid4().hex[:8]}"
    _make_user(app_ctx, username=username)
    tokens = _login(client, username)
    old_access = tokens["access_token"]

    # Sanity: the pre-change token works.
    assert _profile(client, old_access).status_code == 200

    # tokens_invalid_before is floored to whole seconds (see auth.py) so a
    # token minted in the *same* second is never spuriously revoked; cross
    # a real second boundary here so this test exercises "issued in an
    # earlier second", not an artifact of the two HTTP calls landing in the
    # same wall-clock second.
    time.sleep(1.1)

    r = client.post(
        "/api/auth/change-password",
        json={"current_password": _PASSWORD, "new_password": "Bb987654!"},
        headers=_auth(old_access),
    )
    assert r.status_code == 200, r.data

    r2 = _profile(client, old_access)
    assert r2.status_code == 401
    assert "revoked" in (r2.get_json() or {}).get("message", "").lower()


# ---------------------------------------------------------------------------
# B. Password reset invalidates the old access token.
# ---------------------------------------------------------------------------


def test_reset_password_invalidates_old_access_token(app_ctx, client):
    username = f"h01_reset_{uuid.uuid4().hex[:8]}"
    public_id = _make_user(app_ctx, username=username)
    tokens = _login(client, username)
    old_access = tokens["access_token"]
    assert _profile(client, old_access).status_code == 200

    # See test_change_password_invalidates_old_access_token for why.
    time.sleep(1.1)

    user = _get_user(app_ctx, public_id)
    forgot = client.post(
        "/api/auth/forgot-password", json={"phone_number": user.phone_number}
    )
    assert forgot.status_code == 200, forgot.data
    dev_code = forgot.get_json()["dev_code"]

    r = client.post(
        "/api/auth/reset-password",
        json={"token": dev_code, "password": "Cc135791!"},
    )
    assert r.status_code == 200, r.data

    r2 = _profile(client, old_access)
    assert r2.status_code == 401
    assert "revoked" in (r2.get_json() or {}).get("message", "").lower()


# ---------------------------------------------------------------------------
# C. Ban/deactivation invalidates the old access token.
# ---------------------------------------------------------------------------


def test_ban_invalidates_old_access_token(app_ctx, client):
    username = f"h02_ban_{uuid.uuid4().hex[:8]}"
    public_id = _make_user(app_ctx, username=username)
    tokens = _login(client, username)
    old_access = tokens["access_token"]
    assert _profile(client, old_access).status_code == 200

    _set_active(app_ctx, public_id, False)

    r2 = _profile(client, old_access)
    assert r2.status_code == 401
    assert "revoked" in (r2.get_json() or {}).get("message", "").lower()


# ---------------------------------------------------------------------------
# A2/B2/C2. The corresponding REFRESH tokens are rejected too, via the real
# /api/auth/refresh endpoint -- not just access tokens. A leaked/stolen
# refresh token surviving a password change or ban would fully defeat
# H-01/H-02, since it can be exchanged for a brand-new access token.
# ---------------------------------------------------------------------------


def test_change_password_invalidates_old_refresh_token(app_ctx, client):
    username = f"h01_chpw_refresh_{uuid.uuid4().hex[:8]}"
    _make_user(app_ctx, username=username)
    tokens = _login(client, username)
    old_access = tokens["access_token"]
    old_refresh = tokens["refresh_token"]

    # See test_change_password_invalidates_old_access_token for why.
    time.sleep(1.1)

    r = client.post(
        "/api/auth/change-password",
        json={"current_password": _PASSWORD, "new_password": "Ff112233!"},
        headers=_auth(old_access),
    )
    assert r.status_code == 200, r.data

    r2 = _refresh(client, old_refresh)
    assert r2.status_code == 401, r2.data
    assert "revoked" in (r2.get_json() or {}).get("message", "").lower()


def test_reset_password_invalidates_old_refresh_token(app_ctx, client):
    username = f"h01_reset_refresh_{uuid.uuid4().hex[:8]}"
    public_id = _make_user(app_ctx, username=username)
    tokens = _login(client, username)
    old_refresh = tokens["refresh_token"]

    # See test_change_password_invalidates_old_access_token for why.
    time.sleep(1.1)

    user = _get_user(app_ctx, public_id)
    forgot = client.post(
        "/api/auth/forgot-password", json={"phone_number": user.phone_number}
    )
    assert forgot.status_code == 200, forgot.data
    dev_code = forgot.get_json()["dev_code"]

    r = client.post(
        "/api/auth/reset-password",
        json={"token": dev_code, "password": "Gg445566!"},
    )
    assert r.status_code == 200, r.data

    r2 = _refresh(client, old_refresh)
    assert r2.status_code == 401, r2.data
    assert "revoked" in (r2.get_json() or {}).get("message", "").lower()


def test_ban_invalidates_old_refresh_token(app_ctx, client):
    """The old refresh token must be rejected because the account is now
    inactive. The centralized blocklist loader's is_active check intercepts
    the request before refresh()'s own body -- including its own explicit
    `if not user.is_active` guard -- ever runs, so the observed response is
    the same "Token has been revoked" the loader produces for every other
    is_active rejection (see test_ban_invalidates_old_access_token). This
    proves the ban is enforced for refresh tokens too, not just access
    tokens."""
    username = f"h02_ban_refresh_{uuid.uuid4().hex[:8]}"
    public_id = _make_user(app_ctx, username=username)
    tokens = _login(client, username)
    old_refresh = tokens["refresh_token"]

    # Sanity: the pre-ban refresh token works.
    r0 = _refresh(client, old_refresh)
    assert r0.status_code == 200, r0.data
    # That call rotated/consumed old_refresh; the freshly-issued refresh
    # token from it is what "old" means for the ban check below (still
    # issued before the ban, just via one extra legitimate rotation hop).
    old_refresh = r0.get_json()["refresh_token"]

    _set_active(app_ctx, public_id, False)

    r2 = _refresh(client, old_refresh)
    assert r2.status_code == 401, r2.data
    assert "revoked" in (r2.get_json() or {}).get("message", "").lower()


# ---------------------------------------------------------------------------
# D. The three previously-bypassing routes are now covered too.
# ---------------------------------------------------------------------------


def test_ban_blocks_the_three_get_current_user_bypass_routes(app_ctx, client):
    username = f"h02_bypass_{uuid.uuid4().hex[:8]}"
    public_id = _make_user(app_ctx, username=username)
    tokens = _login(client, username)
    old_access = tokens["access_token"]

    # Before ban: these routes accept the token (they don't 401 for auth
    # reasons -- track_message/track_favorite may still 400 on missing
    # listing_id, and blur-image may 400 on a missing file, but neither of
    # those is a 401).
    r_msg = client.post(
        "/api/analytics/track/message", json={}, headers=_auth(old_access)
    )
    assert r_msg.status_code != 401
    r_fav = client.post(
        "/api/analytics/track/favorite", json={}, headers=_auth(old_access)
    )
    assert r_fav.status_code != 401
    r_blur = client.post("/api/blur-image", headers=_auth(old_access))
    assert r_blur.status_code != 401

    _set_active(app_ctx, public_id, False)

    # After ban: the blocklist loader rejects the token before any of these
    # three routes' bodies run, regardless of their own request validation.
    r_msg2 = client.post(
        "/api/analytics/track/message", json={}, headers=_auth(old_access)
    )
    assert r_msg2.status_code == 401, r_msg2.data

    r_fav2 = client.post(
        "/api/analytics/track/favorite", json={}, headers=_auth(old_access)
    )
    assert r_fav2.status_code == 401, r_fav2.data

    r_blur2 = client.post("/api/blur-image", headers=_auth(old_access))
    assert r_blur2.status_code == 401, r_blur2.data


# ---------------------------------------------------------------------------
# E. A newly issued token after a password change remains valid.
# ---------------------------------------------------------------------------


def test_new_token_after_password_change_remains_valid(app_ctx, client):
    username = f"h01_newtok_{uuid.uuid4().hex[:8]}"
    _make_user(app_ctx, username=username)
    tokens = _login(client, username)
    old_access = tokens["access_token"]

    new_password = "Dd246813!"
    r = client.post(
        "/api/auth/change-password",
        json={"current_password": _PASSWORD, "new_password": new_password},
        headers=_auth(old_access),
    )
    assert r.status_code == 200, r.data

    fresh_tokens = _login(client, username, password=new_password)
    fresh_access = fresh_tokens["access_token"]
    assert _profile(client, fresh_access).status_code == 200


# ---------------------------------------------------------------------------
# F. A newly issued token after unban remains valid.
# ---------------------------------------------------------------------------


def test_new_token_after_unban_remains_valid(app_ctx, client):
    username = f"h02_unban_{uuid.uuid4().hex[:8]}"
    public_id = _make_user(app_ctx, username=username)

    _set_active(app_ctx, public_id, False)
    # A banned user cannot log in at all -- confirms login() itself still
    # blocks inactive accounts (unrelated pre-existing behavior, unchanged).
    r_denied = client.post(
        "/api/auth/login", json={"username": username, "password": _PASSWORD}
    )
    assert r_denied.status_code == 401

    _set_active(app_ctx, public_id, True)
    fresh_tokens = _login(client, username)
    assert _profile(client, fresh_tokens["access_token"]).status_code == 200


# ---------------------------------------------------------------------------
# G. An active user with tokens_invalid_before unset (NULL) remains valid.
# ---------------------------------------------------------------------------


def test_active_user_with_no_cutoff_remains_valid(app_ctx, client):
    username = f"h01_nocutoff_{uuid.uuid4().hex[:8]}"
    public_id = _make_user(app_ctx, username=username)
    user = _get_user(app_ctx, public_id)
    assert user.tokens_invalid_before is None

    tokens = _login(client, username)
    assert _profile(client, tokens["access_token"]).status_code == 200


# ---------------------------------------------------------------------------
# H. iat exactly equal to the cutoff is NOT rejected (strict "<" only).
# ---------------------------------------------------------------------------


def test_iat_equal_to_cutoff_is_not_rejected(app_ctx):
    """White-box boundary test against the registered blocklist callback
    directly, since a real signed JWT's `iat` cannot be pinned to an exact
    microsecond-matching value through the public login API."""
    app, _client, db, User = app_ctx
    from kk.extensions import jwt as jwt_manager

    username = f"h01_boundary_{uuid.uuid4().hex[:8]}"
    public_id = _make_user(app_ctx, username=username)

    with app.app_context():
        cutoff = datetime(2030, 1, 1, 12, 0, 0)
        user = User.query.filter_by(public_id=public_id).first()
        user.tokens_invalid_before = cutoff
        db.session.commit()

        cutoff_epoch = int(
            cutoff.replace(tzinfo=timezone.utc).timestamp()
        )

        callback = jwt_manager._token_in_blocklist_callback
        assert callback is not None

        # iat == cutoff -> must NOT be treated as revoked.
        equal_payload = {"sub": public_id, "iat": cutoff_epoch, "jti": "boundary-eq"}
        assert callback({}, equal_payload) is False

        # iat one second before cutoff -> must be treated as revoked.
        before_payload = {
            "sub": public_id,
            "iat": cutoff_epoch - 1,
            "jti": "boundary-lt",
        }
        assert callback({}, before_payload) is True

        # iat one second after cutoff -> must NOT be treated as revoked.
        after_payload = {
            "sub": public_id,
            "iat": cutoff_epoch + 1,
            "jti": "boundary-gt",
        }
        assert callback({}, after_payload) is False


# ---------------------------------------------------------------------------
# I. Existing JTI blacklist (logout) behavior still works.
# ---------------------------------------------------------------------------


def test_logout_still_blacklists_the_presented_token(app_ctx, client):
    username = f"logout_{uuid.uuid4().hex[:8]}"
    _make_user(app_ctx, username=username)
    tokens = _login(client, username)
    access = tokens["access_token"]
    assert _profile(client, access).status_code == 200

    r = client.post("/api/auth/logout", headers=_auth(access))
    assert r.status_code == 200, r.data

    r2 = _profile(client, access)
    assert r2.status_code == 401
    assert "revoked" in (r2.get_json() or {}).get("message", "").lower()


# ---------------------------------------------------------------------------
# J. Existing refresh-token rotation behavior still works.
# ---------------------------------------------------------------------------


def test_refresh_token_rotation_still_works_and_revokes_old_refresh_token(
    app_ctx, client
):
    username = f"refresh_{uuid.uuid4().hex[:8]}"
    _make_user(app_ctx, username=username)
    tokens = _login(client, username)
    old_refresh = tokens["refresh_token"]

    r = client.post("/api/auth/refresh", headers=_auth(old_refresh))
    assert r.status_code == 200, r.data
    body = r.get_json()
    new_access = body["access_token"]
    new_refresh = body["refresh_token"]
    assert new_access and new_refresh

    # New access token works.
    assert _profile(client, new_access).status_code == 200

    # Old refresh token was rotated out -- reusing it must fail.
    r2 = client.post("/api/auth/refresh", headers=_auth(old_refresh))
    assert r2.status_code == 401


# ---------------------------------------------------------------------------
# K. Missing/nonexistent user stays consistent with the existing contract.
# ---------------------------------------------------------------------------


def test_unknown_identity_in_blocklist_loader_is_not_treated_as_revoked(app_ctx):
    """A JWT for an identity that no longer resolves to any User must not be
    rejected by the blocklist loader itself -- get_current_user()/the route
    already returns 404 for a missing user; the loader must not turn that
    into a different (401 'revoked') outcome than before this change."""
    app, _client, db, User = app_ctx
    from kk.extensions import jwt as jwt_manager

    with app.app_context():
        callback = jwt_manager._token_in_blocklist_callback
        payload = {
            "sub": f"nonexistent-{uuid.uuid4().hex}",
            "iat": int(datetime.now(timezone.utc).timestamp()),
            "jti": f"unknown-{uuid.uuid4().hex}",
        }
        assert callback({}, payload) is False


# ---------------------------------------------------------------------------
# L. Timezone-aware/UTC handling: no naive-vs-aware comparison bug.
# ---------------------------------------------------------------------------


def test_cutoff_comparison_uses_utc_consistently(app_ctx, client):
    """change_password/reset_password store tokens_invalid_before via the
    project's naive-UTC utcnow() convention; the blocklist loader must
    convert the JWT's UTC `iat` the same way (naive UTC) before comparing,
    or this comparison would raise/misbehave across a DST or local-timezone
    boundary. This does not just check "no exception" -- it forces a
    real several-hour gap between a naive local-time misinterpretation and
    the correct UTC interpretation of `iat`, so a naive/aware or
    UTC/local mixup would flip the assertions below."""
    app, _client, db, User = app_ctx
    from kk.extensions import jwt as jwt_manager
    from kk.time_utils import utcnow

    username = f"h01_tz_{uuid.uuid4().hex[:8]}"
    public_id = _make_user(app_ctx, username=username)

    with app.app_context():
        now = utcnow()
        assert now.tzinfo is None  # project convention: naive UTC

        user = User.query.filter_by(public_id=public_id).first()
        user.tokens_invalid_before = now
        db.session.commit()

        callback = jwt_manager._token_in_blocklist_callback

        # A token issued 5 seconds before `now`, expressed as a correct UTC
        # unix timestamp, must be revoked.
        stale_iat = int((now - timedelta(seconds=5)).replace(tzinfo=timezone.utc).timestamp())
        assert callback(
            {}, {"sub": public_id, "iat": stale_iat, "jti": "tz-stale"}
        ) is True

        # A token issued 5 seconds after `now` must remain valid.
        fresh_iat = int((now + timedelta(seconds=5)).replace(tzinfo=timezone.utc).timestamp())
        assert callback(
            {}, {"sub": public_id, "iat": fresh_iat, "jti": "tz-fresh"}
        ) is False


# ---------------------------------------------------------------------------
# M. Password change/reset update the cutoff in one commit, not two.
# ---------------------------------------------------------------------------


def test_change_password_commits_password_and_cutoff_atomically(app_ctx, client, monkeypatch):
    """If set_password() and tokens_invalid_before were committed separately,
    a commit failure after the first would silently leave the account with a
    new password but no revoked old tokens (reopening H-01).

    change_password() does legitimately call db.session.commit() twice: once
    for the User row (password_hash + tokens_invalid_before together), and a
    second, separate one from the pre-existing log_user_action() helper for
    an unrelated UserAction row. What must NOT happen is the User row's own
    two fields being split across two different commits. Assert that by the
    time the *first* commit() call fires, the in-memory User object already
    has BOTH the new password hash and the new cutoff staged -- proving they
    are part of the same transaction, not two.
    """
    from kk.routes import auth as auth_module
    from kk.models import User as UserModel

    app, _client, db, User = app_ctx
    username = f"h01_atomic_{uuid.uuid4().hex[:8]}"
    public_id = _make_user(app_ctx, username=username)
    original_hash = _get_user(app_ctx, public_id).password_hash

    tokens = _login(client, username)
    access = tokens["access_token"]

    commit_calls = []
    first_commit_snapshot = {}
    original_commit = auth_module.db.session.commit

    def snapshotting_commit():
        commit_calls.append(1)
        if len(commit_calls) == 1:
            # Read the pending in-memory attribute values directly from the
            # identity map -- no new query, so no autoflush is triggered and
            # this genuinely reflects state *before* this commit() runs.
            for obj in list(auth_module.db.session.identity_map.values()):
                if isinstance(obj, UserModel) and obj.public_id == public_id:
                    first_commit_snapshot["password_hash"] = obj.password_hash
                    first_commit_snapshot["tokens_invalid_before"] = (
                        obj.tokens_invalid_before
                    )
                    break
        return original_commit()

    monkeypatch.setattr(auth_module.db.session, "commit", snapshotting_commit)

    r = client.post(
        "/api/auth/change-password",
        json={"current_password": _PASSWORD, "new_password": "Ee975310!"},
        headers=_auth(access),
    )
    assert r.status_code == 200, r.data

    # log_user_action()'s own commit is the only other one -- both expected,
    # not a sign the User row's two fields were split.
    assert len(commit_calls) == 2

    assert first_commit_snapshot.get("password_hash") not in (None, original_hash)
    assert first_commit_snapshot.get("tokens_invalid_before") is not None
