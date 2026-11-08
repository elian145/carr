"""F-19: admin-scoped (ES256) tokens are separated from user (HS256) tokens.

Covers ``kk/admin_tokens.py`` + the decode hook in ``kk/app_factory.py``:

* flag off (no ``ADMIN_JWT_*`` env) => legacy behaviour is unchanged;
* dual mode (keys set) => admin-signed tokens accepted ONLY on admin routes,
  user tokens and legacy admin tokens keep working;
* enforce mode => HS256 tokens carrying admin claims are rejected;
* forged / wrong-alg / ``none`` / expired / wrong-key / tampered tokens rejected;
* boot-time validation of the key configuration.

Token issuance inside ``kk/routes/auth.py`` is owned by another change; until
that small hunk (``_f19_hunk_present``) is applied, the login-flow tests emulate
it by wrapping ``create_access_token``/``create_refresh_token`` identically.
"""

from __future__ import annotations

import base64
import json
import os
import tempfile
import uuid
from datetime import datetime, timedelta, timezone

import jwt as pyjwt
import pytest
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric import ec, rsa

from kk.tests.admin_auth_helpers import attach_admin_account

_PASSWORD = "Aa123456!"
_ENV_KEYS = (
    "ADMIN_JWT_PRIVATE_KEY",
    "ADMIN_JWT_PUBLIC_KEY",
    "ADMIN_JWT_ENFORCE",
    "ADMIN_JWT_ISSUER",
    "ADMIN_JWT_AUDIENCE",
)


def _pem_private(key) -> str:
    return key.private_bytes(
        serialization.Encoding.PEM,
        serialization.PrivateFormat.PKCS8,
        serialization.NoEncryption(),
    ).decode()


def _pem_public(key) -> str:
    return key.public_key().public_bytes(
        serialization.Encoding.PEM,
        serialization.PublicFormat.SubjectPublicKeyInfo,
    ).decode()


@pytest.fixture(scope="module")
def keys():
    good = ec.generate_private_key(ec.SECP256R1())
    other = ec.generate_private_key(ec.SECP256R1())
    return {"good": good, "other": other}


def _hunk_present() -> bool:
    import kk.routes.auth as auth_routes

    return hasattr(auth_routes, "issue_admin_token")


@pytest.fixture(autouse=True)
def _emulate_issuance_hunk(monkeypatch):
    """Until kk/routes/auth.py carries the F-19 hunk, emulate it exactly."""
    import kk.routes.auth as auth_routes
    from kk.admin_tokens import issue_admin_token

    if _hunk_present():
        return
    orig_access = auth_routes.create_access_token
    orig_refresh = auth_routes.create_refresh_token

    def access(identity, additional_claims=None, **kw):
        if additional_claims:
            t = issue_admin_token(identity, "access", additional_claims)
            if t is not None:
                return t
        return orig_access(identity=identity, additional_claims=additional_claims, **kw)

    def refresh(identity, additional_claims=None, **kw):
        if additional_claims:
            t = issue_admin_token(identity, "refresh", additional_claims)
            if t is not None:
                return t
        return orig_refresh(identity=identity, additional_claims=additional_claims, **kw)

    monkeypatch.setattr(auth_routes, "create_access_token", access)
    monkeypatch.setattr(auth_routes, "create_refresh_token", refresh)


class _Env:
    def __init__(self, app, db, User, keys, tmp):
        self.app = app
        self.client = app.test_client()
        self.db = db
        self.User = User
        self.keys = keys
        self.tmp = tmp

    # -- principals -------------------------------------------------------
    def make_user(self, *, is_admin=False) -> dict:
        name = f"u_{uuid.uuid4().hex[:10]}"
        with self.app.app_context():
            user = self.User(
                username=name,
                phone_number=f"077{uuid.uuid4().int % 10**8:08d}",
                first_name="F",
                last_name="19",
                is_active=True,
                is_verified=True,
                phone_verified=True,
                is_admin=is_admin,
                public_id=f"pub-{uuid.uuid4().hex[:12]}",
            )
            user.set_password(_PASSWORD)
            self.db.session.add(user)
            self.db.session.commit()
            return {"id": user.id, "public_id": user.public_id, "username": name}

    def make_dashboard_admin(self) -> dict:
        info = self.make_user(is_admin=True)
        with self.app.app_context():
            user = self.User.query.get(info["id"])
            acct = attach_admin_account(
                self.db, user, password=_PASSWORD, username=f"dash_{info['username']}"
            )
            info["admin_username"] = acct.username
        return info

    # -- token minting ------------------------------------------------------
    def hs256(self, public_id, **claims) -> str:
        from flask_jwt_extended import create_access_token

        with self.app.app_context():
            return create_access_token(identity=public_id, additional_claims=claims or None)

    def legacy_admin(self, public_id) -> str:
        return self.hs256(public_id, is_admin=True, account_scope="admin")

    def admin_signed(self, public_id, *, token_type="access") -> str:
        from kk.admin_tokens import issue_admin_token

        with self.app.app_context():
            tok = issue_admin_token(
                public_id, token_type, {"is_admin": True, "account_scope": "admin"}
            )
        assert tok
        return tok

    def es256(self, key, public_id, *, exp_delta=timedelta(minutes=30), **claims) -> str:
        now = datetime.now(timezone.utc)
        payload = {
            "fresh": False,
            "iat": now,
            "nbf": now,
            "jti": str(uuid.uuid4()),
            "type": "access",
            "sub": public_id,
            "exp": now + exp_delta,
            # What the API stamps on every admin-signed token; pass
            # ``iss=None`` / ``aud=None`` to omit a claim.
            "iss": "carnet-api",
            "aud": "carnet-admin-web",
        }
        payload.update(claims)
        payload = {k: v for k, v in payload.items() if v is not None}
        return pyjwt.encode(payload, key, algorithm="ES256")

    # -- requests ---------------------------------------------------------------
    def get(self, path, token=None):
        headers = {"Authorization": f"Bearer {token}"} if token else {}
        return self.client.get(path, headers=headers)

    def admin_get(self, token):
        return self.get("/api/admin/users", token)

    def user_get(self, token):
        return self.get("/api/user/favorites", token)


def _build(mode: str, keys, *, public_only=False, private_only=False):
    tmp = tempfile.TemporaryDirectory(prefix="carlist_f19_", ignore_cleanup_errors=True)
    saved = {k: os.environ.get(k) for k in _ENV_KEYS}
    for k in _ENV_KEYS:
        os.environ.pop(k, None)
    os.environ["APP_ENV"] = "testing"
    os.environ["SMS_PROVIDER"] = "console"
    os.environ.pop("REDIS_URL", None)
    os.environ["DB_PATH"] = os.path.join(tmp.name, f"f19_{mode}.db")
    if mode != "legacy":
        if not public_only:
            os.environ["ADMIN_JWT_PRIVATE_KEY"] = _pem_private(keys["good"])
        if not private_only:
            os.environ["ADMIN_JWT_PUBLIC_KEY"] = _pem_public(keys["good"])
    if mode == "enforce":
        os.environ["ADMIN_JWT_ENFORCE"] = "1"
    import kk.config as config_module

    orig_rounds = config_module.Config.BCRYPT_LOG_ROUNDS
    config_module.Config.BCRYPT_LOG_ROUNDS = 4  # speed only; not under test
    try:
        from kk.app_factory import create_app

        app, *_ = create_app()
    finally:
        config_module.Config.BCRYPT_LOG_ROUNDS = orig_rounds
        for k, v in saved.items():
            if v is None:
                os.environ.pop(k, None)
            else:
                os.environ[k] = v
    from kk.models import User, db

    with app.app_context():
        db.drop_all()
        db.create_all()
    env = _Env(app, db, User, keys, tmp)
    return env


def _dispose(env):
    with env.app.app_context():
        env.db.session.remove()
        env.db.engine.dispose()
    env.tmp.cleanup()


@pytest.fixture(scope="module")
def legacy(keys):
    env = _build("legacy", keys)
    yield env
    _dispose(env)


@pytest.fixture(scope="module")
def dual(keys):
    env = _build("dual", keys)
    yield env
    _dispose(env)


@pytest.fixture(scope="module")
def enforce(keys):
    env = _build("enforce", keys)
    yield env
    _dispose(env)


def _b64(obj) -> str:
    return base64.urlsafe_b64encode(json.dumps(obj).encode()).rstrip(b"=").decode()


def _unsigned_none(public_id, **claims) -> str:
    payload = {
        "sub": public_id,
        "type": "access",
        "jti": str(uuid.uuid4()),
        "exp": int((datetime.now(timezone.utc) + timedelta(hours=1)).timestamp()),
        "is_admin": True,
        "account_scope": "admin",
    }
    payload.update(claims)
    return f"{_b64({'alg': 'none', 'typ': 'JWT'})}.{_b64(payload)}."


# --------------------------------------------------------------------------
# Flag OFF: legacy behaviour unchanged
# --------------------------------------------------------------------------
def test_flag_off_registers_nothing_and_issues_nothing(legacy):
    from kk.admin_tokens import admin_tokens_enabled, issue_admin_token

    with legacy.app.app_context():
        assert admin_tokens_enabled() is False
        assert "carnet_admin_tokens" not in legacy.app.extensions
        assert not legacy.app.config.get("JWT_DECODE_ALGORITHMS")
        assert (
            issue_admin_token("x", "access", {"is_admin": True, "account_scope": "admin"})
            is None
        )


def test_flag_off_legacy_dashboard_login_and_admin_route_unchanged(legacy):
    admin = legacy.make_dashboard_admin()
    login = legacy.client.post(
        "/api/auth/login",
        json={
            "username": admin["admin_username"],
            "password": _PASSWORD,
            "account_scope": "admin",
        },
    )
    assert login.status_code == 200, login.data
    body = login.get_json()
    for tok in (body["access_token"], body["refresh_token"]):
        assert pyjwt.get_unverified_header(tok)["alg"] == "HS256"
    assert legacy.admin_get(body["access_token"]).status_code == 200
    # refresh keeps admin scope exactly as before
    rotated = legacy.client.post(
        "/api/auth/refresh", headers={"Authorization": f"Bearer {body['refresh_token']}"}
    )
    assert rotated.status_code == 200, rotated.data
    assert legacy.admin_get(rotated.get_json()["access_token"]).status_code == 200


def test_flag_off_user_and_legacy_admin_tokens_work_es256_rejected(legacy, keys):
    user = legacy.make_user()
    admin = legacy.make_dashboard_admin()
    assert legacy.user_get(legacy.hs256(user["public_id"])).status_code == 200
    assert legacy.admin_get(legacy.hs256(user["public_id"])).status_code == 403
    assert legacy.admin_get(legacy.legacy_admin(admin["public_id"])).status_code == 200
    # An ES256 token is not even a recognised algorithm when the feature is off.
    es = legacy.es256(
        keys["good"], admin["public_id"], is_admin=True, account_scope="admin"
    )
    assert legacy.admin_get(es).status_code == 401


# --------------------------------------------------------------------------
# Dual mode (keys set, enforce off)
# --------------------------------------------------------------------------
def test_dual_dashboard_login_issues_admin_signed_tokens_and_refresh_works(dual, keys):
    admin = dual.make_dashboard_admin()
    login = dual.client.post(
        "/api/auth/login",
        json={
            "username": admin["admin_username"],
            "password": _PASSWORD,
            "account_scope": "admin",
        },
    )
    assert login.status_code == 200, login.data
    body = login.get_json()
    for tok in (body["access_token"], body["refresh_token"]):
        assert pyjwt.get_unverified_header(tok)["alg"] == "ES256"
        unverified = pyjwt.decode(tok, options={"verify_signature": False})
        assert unverified["iss"] == "carnet-api"
        assert unverified["aud"] == "carnet-admin-web"
    # Verifies with the PUBLIC key only (what admin-web holds).
    claims = pyjwt.decode(
        body["access_token"],
        keys["good"].public_key(),
        algorithms=["ES256"],
        issuer="carnet-api",
        audience="carnet-admin-web",
    )
    assert claims["account_scope"] == "admin" and claims["is_admin"] is True
    assert claims["sub"] == admin["public_id"]
    assert dual.admin_get(body["access_token"]).status_code == 200
    me = dual.get("/api/auth/me", body["access_token"])
    assert me.status_code == 200 and me.get_json()["is_admin"] is True

    rotated = dual.client.post(
        "/api/auth/refresh", headers={"Authorization": f"Bearer {body['refresh_token']}"}
    )
    assert rotated.status_code == 200, rotated.data
    new_access = rotated.get_json()["access_token"]
    assert pyjwt.get_unverified_header(new_access)["alg"] == "ES256"
    assert dual.admin_get(new_access).status_code == 200


def test_dual_user_login_and_tokens_stay_hs256_and_never_admin(dual):
    user = dual.make_user()
    login = dual.client.post(
        "/api/auth/login", json={"username": user["username"], "password": _PASSWORD}
    )
    assert login.status_code == 200, login.data
    tok = login.get_json()["access_token"]
    assert pyjwt.get_unverified_header(tok)["alg"] == "HS256"
    assert dual.user_get(tok).status_code == 200
    assert dual.admin_get(tok).status_code == 403


def test_dual_admin_signed_token_accepted_only_on_admin_routes(dual):
    admin = dual.make_dashboard_admin()
    tok = dual.admin_signed(admin["public_id"])
    assert dual.admin_get(tok).status_code == 200
    assert dual.get("/api/auth/me", tok).status_code == 200
    # User-facing route: refused (401), not merely "not admin".
    assert dual.user_get(tok).status_code == 401


def test_dual_legacy_hs256_admin_token_still_accepted_during_migration(dual):
    admin = dual.make_dashboard_admin()
    assert dual.admin_get(dual.legacy_admin(admin["public_id"])).status_code == 200


def test_dual_token_signed_by_wrong_key_rejected(dual, keys):
    admin = dual.make_dashboard_admin()
    forged = dual.es256(
        keys["other"], admin["public_id"], is_admin=True, account_scope="admin"
    )
    assert dual.admin_get(forged).status_code == 401


def test_dual_es256_without_admin_scope_rejected_even_if_validly_signed(dual, keys):
    """The admin key is only for admin-scoped tokens."""
    user = dual.make_user()
    plain = dual.es256(keys["good"], user["public_id"])
    assert dual.user_get(plain).status_code == 401
    assert dual.admin_get(plain).status_code == 401
    only_is_admin = dual.es256(keys["good"], user["public_id"], is_admin=True)
    assert dual.admin_get(only_is_admin).status_code == 401


def test_dual_expired_admin_token_rejected(dual, keys):
    admin = dual.make_dashboard_admin()
    expired = dual.es256(
        keys["good"],
        admin["public_id"],
        exp_delta=timedelta(seconds=-60),
        is_admin=True,
        account_scope="admin",
    )
    r = dual.admin_get(expired)
    assert r.status_code == 401


def test_dual_alg_confusion_hs256_signed_with_public_key_rejected(dual, keys):
    admin = dual.make_dashboard_admin()
    pub = _pem_public(keys["good"])
    # PyJWT refuses PEM-as-HMAC-secret itself; craft the signature by hand.
    import hashlib
    import hmac

    header = _b64({"alg": "HS256", "typ": "JWT"})
    payload = _b64(
        {
            "sub": admin["public_id"],
            "type": "access",
            "jti": str(uuid.uuid4()),
            "exp": int((datetime.now(timezone.utc) + timedelta(hours=1)).timestamp()),
            "is_admin": True,
            "account_scope": "admin",
        }
    )
    sig = base64.urlsafe_b64encode(
        hmac.new(pub.encode(), f"{header}.{payload}".encode(), hashlib.sha256).digest()
    ).rstrip(b"=").decode()
    assert dual.admin_get(f"{header}.{payload}.{sig}").status_code == 401


def test_dual_wrong_hs256_secret_and_none_alg_and_tamper_rejected(dual):
    admin = dual.make_dashboard_admin()
    bad_hs = pyjwt.encode(
        {
            "sub": admin["public_id"],
            "type": "access",
            "jti": str(uuid.uuid4()),
            "exp": datetime.now(timezone.utc) + timedelta(hours=1),
            "is_admin": True,
            "account_scope": "admin",
        },
        "not-the-real-secret-not-the-real-secret",
        algorithm="HS256",
    )
    assert dual.admin_get(bad_hs).status_code == 401
    assert dual.admin_get(_unsigned_none(admin["public_id"])).status_code == 401
    assert dual.user_get(_unsigned_none(admin["public_id"])).status_code == 401

    good = dual.admin_signed(admin["public_id"])
    h, p, s = good.split(".")
    tampered_payload = json.loads(base64.urlsafe_b64decode(p + "=" * (-len(p) % 4)))
    tampered_payload["sub"] = "someone-else"
    tampered = f"{h}.{_b64(tampered_payload)}.{s}"
    assert dual.admin_get(tampered).status_code == 401
    # Header downgraded ES256 -> HS256 keeps the ES256 signature: invalid.
    downgraded = f"{_b64({'alg': 'HS256', 'typ': 'JWT'})}.{p}.{s}"
    assert dual.admin_get(downgraded).status_code == 401


def test_dual_revocation_and_inactive_user_still_enforced_for_admin_tokens(dual):
    admin = dual.make_dashboard_admin()
    tok = dual.admin_signed(admin["public_id"])
    assert dual.admin_get(tok).status_code == 200
    with dual.app.app_context():
        user = dual.User.query.get(admin["id"])
        user.is_active = False
        dual.db.session.commit()
    assert dual.admin_get(tok).status_code == 401


def test_dual_refresh_token_cannot_be_used_as_access_on_admin_route(dual, legacy):
    """Refresh-as-access is refused exactly like the legacy HS256 behaviour.

    The app's error handling turns flask-jwt-extended's wrong-token-type error
    into 401 (the existing suite accepts 401/422, see test_f06_push_token_dedup).
    The admin-signed token must get the SAME status as an HS256 refresh token on
    the legacy app: the type check is untouched by the F-19 hook.
    """
    from flask_jwt_extended import create_refresh_token

    admin = dual.make_dashboard_admin()
    refresh = dual.admin_signed(admin["public_id"], token_type="refresh")
    got = dual.admin_get(refresh).status_code

    legacy_admin = legacy.make_dashboard_admin()
    with legacy.app.app_context():
        hs_refresh = create_refresh_token(
            identity=legacy_admin["public_id"],
            additional_claims={"is_admin": True, "account_scope": "admin"},
        )
    expected = legacy.admin_get(hs_refresh).status_code
    assert expected in (401, 422)
    assert got == expected


def test_issue_admin_token_refuses_non_admin_claims(dual):
    from kk.admin_tokens import issue_admin_token

    with dual.app.app_context():
        assert issue_admin_token("x", "access", None) is None
        assert issue_admin_token("x", "access", {"auth_method": "phone_otp"}) is None
        assert issue_admin_token("x", "access", {"is_admin": True}) is None


def test_admin_route_scope_helper():
    from kk.admin_tokens import is_admin_route_path

    for ok in ("/api/admin/users", "/api/admin/auto-moderation/x", "/api/admin", "/api/auth/me", "/api/auth/refresh", "/api/auth/logout"):
        assert is_admin_route_path(ok), ok
    for bad in ("/api/user/favorites", "/api/cars", "/api/administrator", "/api/auth/login", "/api/auth/me/x", "", "/socket.io/"):
        assert not is_admin_route_path(bad), bad


# --------------------------------------------------------------------------
# Enforce mode
# --------------------------------------------------------------------------
def test_enforce_rejects_hs256_tokens_with_admin_claims_everywhere(enforce):
    admin = enforce.make_dashboard_admin()
    legacy_admin = enforce.legacy_admin(admin["public_id"])
    assert enforce.admin_get(legacy_admin).status_code == 401
    assert enforce.user_get(legacy_admin).status_code == 401
    assert enforce.get("/api/auth/me", legacy_admin).status_code == 401
    only_scope = enforce.hs256(admin["public_id"], account_scope="admin")
    assert enforce.admin_get(only_scope).status_code == 401
    only_flag = enforce.hs256(admin["public_id"], is_admin=True)
    assert enforce.admin_get(only_flag).status_code == 401


def test_enforce_forged_legacy_admin_refresh_cannot_mint_admin_session(enforce):
    """A leaked JWT_SECRET_KEY must not turn into an admin session."""
    from flask_jwt_extended import create_refresh_token

    admin = enforce.make_dashboard_admin()
    with enforce.app.app_context():
        forged_refresh = create_refresh_token(
            identity=admin["public_id"],
            additional_claims={"is_admin": True, "account_scope": "admin"},
        )
    r = enforce.client.post(
        "/api/auth/refresh", headers={"Authorization": f"Bearer {forged_refresh}"}
    )
    assert r.status_code == 401, r.data


def test_enforce_user_tokens_and_admin_signed_tokens_work(enforce):
    user = enforce.make_user()
    admin = enforce.make_dashboard_admin()
    assert enforce.user_get(enforce.hs256(user["public_id"])).status_code == 200
    assert enforce.admin_get(enforce.hs256(user["public_id"])).status_code == 403
    assert enforce.admin_get(enforce.admin_signed(admin["public_id"])).status_code == 200
    # mobile-style claims (auth_method) without admin claims remain user tokens
    mobile = enforce.hs256(admin["public_id"], auth_method="password")
    assert enforce.user_get(mobile).status_code == 200
    assert enforce.admin_get(mobile).status_code == 403


def test_enforce_dashboard_login_and_refresh_still_work(enforce):
    admin = enforce.make_dashboard_admin()
    login = enforce.client.post(
        "/api/auth/login",
        json={
            "username": admin["admin_username"],
            "password": _PASSWORD,
            "account_scope": "admin",
        },
    )
    assert login.status_code == 200, login.data
    body = login.get_json()
    assert enforce.admin_get(body["access_token"]).status_code == 200
    rotated = enforce.client.post(
        "/api/auth/refresh", headers={"Authorization": f"Bearer {body['refresh_token']}"}
    )
    assert rotated.status_code == 200, rotated.data
    assert enforce.admin_get(rotated.get_json()["access_token"]).status_code == 200


# --------------------------------------------------------------------------
# Key configuration validation / partial configurations
# --------------------------------------------------------------------------
def _settings_with_env(monkeypatch, **env):
    from kk.admin_tokens import _load_settings

    for k in _ENV_KEYS:
        monkeypatch.delenv(k, raising=False)
    for k, v in env.items():
        monkeypatch.setenv(k, v)
    return _load_settings()


def test_private_key_only_derives_public_key(keys, monkeypatch):
    s = _settings_with_env(monkeypatch, ADMIN_JWT_PRIVATE_KEY=_pem_private(keys["good"]))
    assert s is not None and s.private_key is not None and s.enforce is False
    assert s.public_key.public_numbers() == keys["good"].public_key().public_numbers()


def test_no_env_means_feature_off(monkeypatch):
    assert _settings_with_env(monkeypatch) is None


def test_public_key_only_verifies_but_cannot_issue(keys):
    """A replica / verifier holding only the public key can never mint."""
    env = _build("dual", keys, public_only=True)
    try:
        from kk.admin_tokens import issue_admin_token

        admin = env.make_dashboard_admin()
        with env.app.app_context():
            assert (
                issue_admin_token(
                    admin["public_id"],
                    "access",
                    {"is_admin": True, "account_scope": "admin"},
                )
                is None
            )
        signed = env.es256(
            keys["good"], admin["public_id"], is_admin=True, account_scope="admin"
        )
        assert env.admin_get(signed).status_code == 200
    finally:
        _dispose(env)


def _create_app_with_env(**overrides):
    saved = {k: os.environ.get(k) for k in _ENV_KEYS}
    tmp = tempfile.TemporaryDirectory(prefix="carlist_f19b_", ignore_cleanup_errors=True)
    try:
        for k in _ENV_KEYS:
            os.environ.pop(k, None)
        os.environ["APP_ENV"] = "testing"
        os.environ["SMS_PROVIDER"] = "console"
        os.environ.pop("REDIS_URL", None)
        os.environ["DB_PATH"] = os.path.join(tmp.name, "f19_cfg.db")
        os.environ.update(overrides)
        from kk.app_factory import create_app

        return create_app()
    finally:
        for k, v in saved.items():
            if v is None:
                os.environ.pop(k, None)
            else:
                os.environ[k] = v
        tmp.cleanup()


def test_enforce_without_keys_refuses_to_boot():
    with pytest.raises(RuntimeError, match="ADMIN_JWT_ENFORCE"):
        _create_app_with_env(ADMIN_JWT_ENFORCE="1")


def test_enforce_with_public_key_only_refuses_to_boot(keys):
    with pytest.raises(RuntimeError, match="PRIVATE_KEY"):
        _create_app_with_env(
            ADMIN_JWT_ENFORCE="1", ADMIN_JWT_PUBLIC_KEY=_pem_public(keys["good"])
        )


def test_non_p256_and_garbage_and_mismatched_keys_refuse_to_boot(keys):
    rsa_key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    with pytest.raises(RuntimeError, match="P-256"):
        _create_app_with_env(ADMIN_JWT_PRIVATE_KEY=_pem_private(rsa_key))
    with pytest.raises(RuntimeError, match="valid"):
        _create_app_with_env(ADMIN_JWT_PUBLIC_KEY="not a pem")
    with pytest.raises(RuntimeError, match="does not match"):
        _create_app_with_env(
            ADMIN_JWT_PRIVATE_KEY=_pem_private(keys["good"]),
            ADMIN_JWT_PUBLIC_KEY=_pem_public(keys["other"]),
        )


def test_pem_with_escaped_newlines_is_accepted(keys, monkeypatch):
    """Dashboards often store PEMs with literal ``\\n``."""
    escaped = _pem_private(keys["good"]).strip().replace("\n", "\\n")
    assert "\\n" in escaped and "\n" not in escaped
    s = _settings_with_env(monkeypatch, ADMIN_JWT_PRIVATE_KEY=escaped)
    assert s is not None and s.private_key is not None


def test_hunk_status_info():
    """Documents (does not assert) whether the auth.py hunk is already applied."""
    assert isinstance(_hunk_present(), bool)


def test_issued_admin_tokens_always_carry_exp_even_if_config_disables_expiry(dual):
    """F-32: admin-web rejects exp-less tokens, so the API must never mint one."""
    from kk.admin_tokens import issue_admin_token

    claims = {"is_admin": True, "account_scope": "admin"}
    with dual.app.app_context():
        saved = {
            k: dual.app.config[k]
            for k in ("JWT_ACCESS_TOKEN_EXPIRES", "JWT_REFRESH_TOKEN_EXPIRES")
        }
        try:
            for k in saved:
                dual.app.config[k] = False
            for kind in ("access", "refresh"):
                tok = issue_admin_token("x", kind, claims)
                payload = pyjwt.decode(tok, options={"verify_signature": False})
                assert isinstance(payload.get("exp"), int)
                assert payload["exp"] > int(datetime.now(timezone.utc).timestamp())
        finally:
            dual.app.config.update(saved)


# --------------------------------------------------------------------------
# iss / aud on admin-signed tokens (strictly required on every path)
# --------------------------------------------------------------------------
_ADMIN_CLAIMS = {"is_admin": True, "account_scope": "admin"}


@pytest.mark.parametrize(
    "bad",
    [
        {"iss": None},
        {"iss": "someone-else"},
        {"aud": None},
        {"aud": "someone-else"},
        {"aud": ["other-service"]},
        {"aud": 7},
    ],
    ids=["no-iss", "wrong-iss", "no-aud", "wrong-aud", "wrong-aud-list", "int-aud"],
)
def test_dual_admin_signed_token_with_missing_or_wrong_iss_aud_rejected(dual, keys, bad):
    admin = dual.make_dashboard_admin()
    good_tok = dual.es256(keys["good"], admin["public_id"], **_ADMIN_CLAIMS)
    assert dual.admin_get(good_tok).status_code == 200  # control: same token, valid iss/aud
    tok = dual.es256(keys["good"], admin["public_id"], **_ADMIN_CLAIMS, **bad)
    assert dual.admin_get(tok).status_code == 401
    assert dual.get("/api/auth/me", tok).status_code == 401
    # also on the session-refresh path (refresh token type)
    refresh = dual.es256(
        keys["good"], admin["public_id"], type="refresh", **_ADMIN_CLAIMS, **bad
    )
    r = dual.client.post(
        "/api/auth/refresh", headers={"Authorization": f"Bearer {refresh}"}
    )
    assert r.status_code == 401


def test_dual_valid_iss_aud_list_audience_accepted(dual, keys):
    admin = dual.make_dashboard_admin()
    tok = dual.es256(
        keys["good"],
        admin["public_id"],
        aud=["other-service", "carnet-admin-web"],
        **_ADMIN_CLAIMS,
    )
    assert dual.admin_get(tok).status_code == 200


def test_dual_wrong_alg_and_expired_still_rejected_with_valid_iss_aud(dual, keys):
    admin = dual.make_dashboard_admin()
    expired = dual.es256(
        keys["good"],
        admin["public_id"],
        exp_delta=timedelta(seconds=-60),
        **_ADMIN_CLAIMS,
    )
    assert dual.admin_get(expired).status_code == 401
    # right claims but HS256 + the (wrong) admin public key as secret
    hs = pyjwt.encode(
        {
            "sub": admin["public_id"],
            "type": "access",
            "jti": str(uuid.uuid4()),
            "exp": datetime.now(timezone.utc) + timedelta(hours=1),
            "iss": "carnet-api",
            "aud": "carnet-admin-web",
            **_ADMIN_CLAIMS,
        },
        "x" * 40,
        algorithm="HS256",
    )
    assert dual.admin_get(hs).status_code == 401
    assert dual.admin_get(_unsigned_none(admin["public_id"], iss="carnet-api", aud="carnet-admin-web")).status_code == 401


def test_dual_refreshed_admin_tokens_carry_iss_aud(dual):
    admin = dual.make_dashboard_admin()
    refresh = dual.admin_signed(admin["public_id"], token_type="refresh")
    r = dual.client.post(
        "/api/auth/refresh", headers={"Authorization": f"Bearer {refresh}"}
    )
    assert r.status_code == 200, r.data
    body = r.get_json()
    for tok in (body["access_token"], body.get("refresh_token")):
        if not tok:
            continue
        claims = pyjwt.decode(tok, options={"verify_signature": False})
        assert claims["iss"] == "carnet-api" and claims["aud"] == "carnet-admin-web"


def test_enforce_admin_signed_token_without_iss_aud_rejected(enforce, keys):
    admin = enforce.make_dashboard_admin()
    ok = enforce.es256(keys["good"], admin["public_id"], **_ADMIN_CLAIMS)
    assert enforce.admin_get(ok).status_code == 200
    for bad in ({"iss": None}, {"aud": None}, {"iss": "x"}, {"aud": "x"}):
        tok = enforce.es256(keys["good"], admin["public_id"], **_ADMIN_CLAIMS, **bad)
        assert enforce.admin_get(tok).status_code == 401, bad


def test_issue_admin_token_always_stamps_iss_aud_caller_cannot_override(dual):
    from kk.admin_tokens import issue_admin_token

    with dual.app.app_context():
        tok = issue_admin_token(
            "pub-id",
            "access",
            {**_ADMIN_CLAIMS, "iss": "forged", "aud": "forged"},
        )
    claims = pyjwt.decode(tok, options={"verify_signature": False})
    assert claims["iss"] == "carnet-api" and claims["aud"] == "carnet-admin-web"


def test_iss_aud_env_overrides_are_read_at_boot_and_default_otherwise(keys, monkeypatch):
    s = _settings_with_env(monkeypatch, ADMIN_JWT_PRIVATE_KEY=_pem_private(keys["good"]))
    assert (s.issuer, s.audience) == ("carnet-api", "carnet-admin-web")
    s = _settings_with_env(
        monkeypatch,
        ADMIN_JWT_PRIVATE_KEY=_pem_private(keys["good"]),
        ADMIN_JWT_ISSUER="  my-iss ",
        ADMIN_JWT_AUDIENCE="my-aud",
    )
    assert (s.issuer, s.audience) == ("my-iss", "my-aud")
    # blank values fall back to the defaults, never to "no check"
    s = _settings_with_env(
        monkeypatch,
        ADMIN_JWT_PRIVATE_KEY=_pem_private(keys["good"]),
        ADMIN_JWT_ISSUER="   ",
        ADMIN_JWT_AUDIENCE="",
    )
    assert (s.issuer, s.audience) == ("carnet-api", "carnet-admin-web")