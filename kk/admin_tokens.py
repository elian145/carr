"""F-19: admin-scoped JWTs signed with a key user tokens never use.

Problem (audit F-19): the admin Next.js service held the API's shared
``JWT_SECRET_KEY`` (HS256) to verify the admin session cookie. Anyone who
compromised admin-web could therefore mint a valid token for ANY user.

Design (opt-in, OFF by default; no env vars => legacy behaviour is untouched)
--------------------------------------------------------------------------
* User tokens keep being signed with ``JWT_SECRET_KEY`` (HS256).
* Admin-scoped tokens (``account_scope=admin``, issued only after an
  ``AdminAccount`` dashboard login) are signed with an EC P-256 private key
  (ES256) that only the API holds (``ADMIN_JWT_PRIVATE_KEY``). admin-web only
  gets the PUBLIC key (``ADMIN_JWT_PUBLIC_KEY``), so it can verify but never
  mint anything, and it needs no HS256 secret at all.
* The API accepts an ES256 token only if (a) the signature verifies against
  the admin public key, (b) it carries the admin claims, and (c) it is used on
  an admin route (``/api/admin/*``) or one of the few session endpoints the
  dashboard needs (``/api/auth/me|refresh|logout``).
* With ``ADMIN_JWT_ENFORCE=1`` the API additionally rejects any HS256 token
  that carries admin claims (``account_scope=admin`` / ``is_admin``), so even a
  leaked ``JWT_SECRET_KEY`` cannot be used to forge an admin token. Until then
  (dual mode) legacy HS256 admin tokens keep working so the roll-out can be
  staged without logging admins out.

Token issuance lives in ``kk/routes/auth.py`` (``_access_token_for_user`` /
``_refresh_token_for_user``); they call :func:`issue_admin_token`, which
returns ``None`` when the feature is off so the legacy path is used.
"""

from __future__ import annotations

import uuid
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from typing import Any

import jwt as pyjwt
from flask import current_app, has_request_context, request
from jwt.exceptions import InvalidTokenError

from . import config as _config

ADMIN_TOKEN_ALGORITHM = "ES256"
_EXTENSION_KEY = "carnet_admin_tokens"

#: Routes an admin-signed token may be presented to. Everything else is a
#: user-facing route: admin-signed tokens are refused there.
ADMIN_ROUTE_PREFIXES = ("/api/admin/",)
ADMIN_ROUTE_EXACT = frozenset(
    {
        "/api/admin",
        "/api/auth/me",
        "/api/auth/refresh",
        "/api/auth/logout",
    }
)


@dataclass(frozen=True)
class AdminTokenSettings:
    public_key: Any  # cryptography EllipticCurvePublicKey
    private_key: Any | None  # cryptography EllipticCurvePrivateKey (API only)
    enforce: bool


def _load_settings() -> AdminTokenSettings | None:
    """Parse/validate the env configuration. ``None`` = feature off."""
    from cryptography.hazmat.primitives import serialization
    from cryptography.hazmat.primitives.asymmetric import ec

    private_pem = _config.admin_jwt_private_key_pem()
    public_pem = _config.admin_jwt_public_key_pem()
    enforce = _config.admin_jwt_enforce_enabled()

    if not private_pem and not public_pem:
        if enforce:
            raise RuntimeError(
                "ADMIN_JWT_ENFORCE is set but neither ADMIN_JWT_PRIVATE_KEY nor "
                "ADMIN_JWT_PUBLIC_KEY is configured; refusing to start (admins "
                "could not log in)."
            )
        return None

    def _require_p256(key: Any, name: str) -> None:
        curve = getattr(key, "curve", None)
        if not isinstance(curve, ec.SECP256R1):
            raise RuntimeError(f"{name} must be an EC P-256 (prime256v1) key for ES256.")

    private_key = None
    if private_pem:
        try:
            private_key = serialization.load_pem_private_key(
                private_pem.encode("utf-8"), password=None
            )
        except Exception as exc:  # noqa: BLE001 - never echo key material
            raise RuntimeError("ADMIN_JWT_PRIVATE_KEY is not a valid unencrypted PEM key.") from exc
        _require_p256(private_key, "ADMIN_JWT_PRIVATE_KEY")

    public_key = None
    if public_pem:
        try:
            public_key = serialization.load_pem_public_key(public_pem.encode("utf-8"))
        except Exception as exc:  # noqa: BLE001
            raise RuntimeError("ADMIN_JWT_PUBLIC_KEY is not a valid PEM public key.") from exc
        _require_p256(public_key, "ADMIN_JWT_PUBLIC_KEY")

    if private_key is not None:
        derived = private_key.public_key()
        if public_key is not None and (
            public_key.public_numbers() != derived.public_numbers()
        ):
            raise RuntimeError(
                "ADMIN_JWT_PUBLIC_KEY does not match ADMIN_JWT_PRIVATE_KEY."
            )
        public_key = derived

    if enforce and private_key is None:
        raise RuntimeError(
            "ADMIN_JWT_ENFORCE requires ADMIN_JWT_PRIVATE_KEY on the API service "
            "(otherwise no admin token could be issued)."
        )

    return AdminTokenSettings(
        public_key=public_key, private_key=private_key, enforce=enforce
    )


def validate_admin_token_config() -> None:
    """Fail fast (``RuntimeError``) on a malformed/partial ADMIN_JWT_* config."""
    _load_settings()


def get_settings(app=None) -> AdminTokenSettings | None:
    app = app or current_app
    return app.extensions.get(_EXTENSION_KEY)


def admin_tokens_enabled(app=None) -> bool:
    return get_settings(app) is not None


def _has_admin_claims(payload: dict) -> bool:
    return (
        str(payload.get("account_scope") or "").strip().lower() == "admin"
        or payload.get("is_admin") is True
    )


def is_admin_route_path(path: str) -> bool:
    p = path or ""
    return p in ADMIN_ROUTE_EXACT or any(p.startswith(x) for x in ADMIN_ROUTE_PREFIXES)


def issue_admin_token(
    identity: str,
    token_type: str,
    claims: dict | None,
    *,
    fresh: bool = False,
) -> str | None:
    """Sign an admin-scoped token with the admin key, or ``None`` (legacy path).

    Returns ``None`` when the feature is off, when this process has no private
    key, or when ``claims`` is not an admin-scope claim set -- callers then fall
    back to ``create_access_token`` / ``create_refresh_token`` (HS256) unchanged.
    The payload mirrors flask-jwt-extended's (iat/nbf/jti/type/fresh/sub/exp) so
    blocklist, ``tokens_invalid_before`` and ``/auth/refresh`` logic keep working.
    """
    settings = get_settings()
    if settings is None or settings.private_key is None:
        return None
    claims = dict(claims or {})
    if str(claims.get("account_scope") or "").strip().lower() != "admin":
        return None
    if token_type not in ("access", "refresh"):
        raise ValueError("token_type must be 'access' or 'refresh'")

    now = datetime.now(timezone.utc)
    ttl = current_app.config[
        "JWT_ACCESS_TOKEN_EXPIRES" if token_type == "access" else "JWT_REFRESH_TOKEN_EXPIRES"
    ]
    payload: dict[str, Any] = {
        "fresh": bool(fresh),
        "iat": now,
        "nbf": now,
        "jti": str(uuid.uuid4()),
        "type": token_type,
        "sub": identity,
    }
    # F-32: an admin-signed token must always expire (admin-web rejects exp-less
    # tokens); fall back to conservative defaults if the config disabled expiry.
    if not ttl:
        ttl = timedelta(minutes=30) if token_type == "access" else timedelta(days=7)
    payload["exp"] = now + ttl
    payload.update(claims)
    # Admin-signed tokens always carry both admin claims.
    payload["account_scope"] = "admin"
    payload["is_admin"] = True
    return pyjwt.encode(
        payload, settings.private_key, algorithm=ADMIN_TOKEN_ALGORITHM
    )


def _decode_key_for(app, settings: AdminTokenSettings, header: dict, payload: dict):
    """Pick the verification key from the UNVERIFIED header, then constrain it.

    Raising ``InvalidTokenError`` here makes flask-jwt-extended answer 401
    (``Invalid token``) for ``@jwt_required`` and makes ``decode_token`` raise.
    The returned key is only ever used by PyJWT with ``algorithms=`` limited to
    ``HS256``/``ES256``, so an attacker-chosen ``alg`` can neither select the
    wrong key type (HS256 uses ONLY the shared secret, ES256 ONLY the admin
    public key) nor use ``none``.
    """
    alg = (header or {}).get("alg")
    if alg == ADMIN_TOKEN_ALGORITHM:
        if not _has_admin_claims(payload) or (
            str(payload.get("account_scope") or "").strip().lower() != "admin"
        ):
            raise InvalidTokenError("admin-signed token without admin scope")
        if has_request_context() and not is_admin_route_path(request.path):
            raise InvalidTokenError("admin-signed token not valid on this route")
        return settings.public_key

    # Everything else is the legacy (user) HS256 path.
    if settings.enforce and _has_admin_claims(payload):
        raise InvalidTokenError("admin claims require an admin-signed token")
    return app.config["JWT_SECRET_KEY"]


def init_admin_tokens(app, jwt_manager) -> None:
    """Wire the feature into ``app``; a complete no-op when the env is unset."""
    settings = _load_settings()
    if settings is None:
        return
    app.extensions[_EXTENSION_KEY] = settings
    algorithms = ["HS256", ADMIN_TOKEN_ALGORITHM]
    app.config["JWT_DECODE_ALGORITHMS"] = algorithms

    @jwt_manager.decode_key_loader
    def _admin_aware_decode_key(unverified_header, unverified_payload):
        return _decode_key_for(app, settings, unverified_header, unverified_payload)
