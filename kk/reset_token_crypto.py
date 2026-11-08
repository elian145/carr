"""F-29: password-reset tokens are stored hashed at rest.

The raw token (12-digit SMS code / URL-safe email token) is only ever sent to the
user. The ``password_reset.token`` column stores ``"h1$" + HMAC-SHA256(pepper, token)``
(hex, 3 + 64 = 67 chars, fits the existing ``String(100)`` column -> no migration).

Why HMAC with a server pepper and not a bare SHA-256: SMS codes have only 10**12
possible values, so an unsalted hash of a leaked row could be brute-forced offline in
minutes. The pepper is derived from the app ``SECRET_KEY`` and never stored in the DB,
so a database dump / backup alone cannot be turned back into usable codes.

Mechanism: :class:`HashedResetToken` is a SQLAlchemy ``TypeDecorator`` bound to the
``PasswordReset.token`` column. Every value *bound* to that column (inserts AND
``filter_by(token=<raw>)`` look-ups) is hashed on the way in, so existing callers that
pass the raw token (including ``kk/routes/auth.py``, which marks the row used) keep
working unchanged and can never write or compare a plaintext token again.

Legacy (pre-F-29) rows hold the plaintext token. They are accepted for the remaining
(at most one hour) lifetime by ``kk.auth.verify_password_reset_token`` and re-written to
the hashed form on first sight; see ``LEGACY_PLAINTEXT_ENV``. Delete
``legacy_plaintext_enabled`` + ``kk.auth._find_legacy_plaintext_row`` to remove that path.
"""

from __future__ import annotations

import hashlib
import hmac
import os

from flask import current_app, has_app_context
from sqlalchemy import String
from sqlalchemy.types import TypeDecorator

HASH_PREFIX = "h1$"
# 3 (prefix) + 64 (sha256 hex)
HASHED_TOKEN_LEN = len(HASH_PREFIX) + 64
# Hash of an unusable input; never equals a real HMAC digest of any token.
INVALID_TOKEN_SENTINEL = HASH_PREFIX + "0" * 64
MAX_RAW_TOKEN_LEN = 256

_PEPPER_CONTEXT = b"carnet/password-reset-token/v1"

# Set to "0"/"false"/"off" once the first post-deploy hour has passed (or at deploy time
# if you prefer to invalidate in-flight codes). Default: accept legacy plaintext rows.
LEGACY_PLAINTEXT_ENV = "PASSWORD_RESET_ACCEPT_LEGACY_PLAINTEXT"


def _secret_key() -> bytes:
    key = None
    if has_app_context():
        key = current_app.config.get("SECRET_KEY")
    if not key:
        key = os.environ.get("SECRET_KEY")
    if not key:
        # Fail closed: never hash with an empty/guessable pepper.
        raise RuntimeError("SECRET_KEY is required to protect password-reset tokens")
    return key.encode("utf-8") if isinstance(key, str) else bytes(key)


def _pepper(context: bytes = _PEPPER_CONTEXT) -> bytes:
    return hmac.new(_secret_key(), context, hashlib.sha256).digest()


def hash_reset_token(raw) -> str:
    """Return the at-rest form of ``raw``; a never-matching sentinel for unusable input.

    Always hashes: a caller (or attacker) submitting a stored ``h1$...`` value as the
    "token" gets that string hashed again, so a leaked row cannot be replayed.
    """
    if not isinstance(raw, str) or not raw or len(raw) > MAX_RAW_TOKEN_LEN:
        return INVALID_TOKEN_SENTINEL
    digest = hmac.new(_pepper(), raw.encode("utf-8"), hashlib.sha256).hexdigest()
    return HASH_PREFIX + digest


# F-29 (follow-up): e-mail verification tokens get the same treatment under a separate
# pepper context, so a reset-token hash can never be replayed as a verification token.
_EMAIL_VERIFICATION_PEPPER_CONTEXT = b"carnet/email-verification-token/v1"


def hash_email_verification_token(raw) -> str:
    if not isinstance(raw, str) or not raw or len(raw) > MAX_RAW_TOKEN_LEN:
        return INVALID_TOKEN_SENTINEL
    key = _pepper(_EMAIL_VERIFICATION_PEPPER_CONTEXT)
    return HASH_PREFIX + hmac.new(key, raw.encode("utf-8"), hashlib.sha256).hexdigest()


def is_hashed_form(stored) -> bool:
    return (
        isinstance(stored, str)
        and len(stored) == HASHED_TOKEN_LEN
        and stored.startswith(HASH_PREFIX)
    )


def tokens_equal(a: str, b: str) -> bool:
    """Constant-time comparison of two stored/derived token strings."""
    return hmac.compare_digest(a.encode("utf-8"), b.encode("utf-8"))


def legacy_plaintext_enabled() -> bool:
    val = (os.environ.get(LEGACY_PLAINTEXT_ENV) or "1").strip().lower()
    return val not in ("0", "false", "no", "off")


class HashedResetToken(TypeDecorator):
    """``String(100)`` column whose bound values are HMAC-hashed (see module docstring)."""

    impl = String(100)
    cache_ok = True

    def process_bind_param(self, value, dialect):
        if value is None:
            return None
        return hash_reset_token(value)

    def process_result_value(self, value, dialect):
        return value


class HashedEmailVerificationToken(TypeDecorator):
    """``String(100)`` column whose bound values are HMAC-hashed (see ``hash_email_verification_token``)."""

    impl = String(100)
    cache_ok = True

    def process_bind_param(self, value, dialect):
        if value is None:
            return None
        return hash_email_verification_token(value)

    def process_result_value(self, value, dialect):
        return value
