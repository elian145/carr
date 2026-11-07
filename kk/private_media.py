"""Private (never public) storage for dealer-verification photos.

Why this exists
---------------
Dealer-verification photos used to live ONLY on the web service's local disk
(``PRIVATE_UPLOAD_FOLDER/dealer_verification/``). ``render.yaml`` defines no
persistent disk, and Render's filesystem is ephemeral, so every deploy or
restart silently discarded the photos while the DB column
(``DealerApplication.verification_photo_filename``) kept pointing at them.

Storage model (no schema change -- the existing column is reused)
-----------------------------------------------------------------
* Bare filename  (``<hex>.jpg``)                  -> LEGACY local-disk file.
* ``r2:dealer_verification/<hex>.jpg``            -> object in the PRIVATE
  chat-media R2 bucket (``R2_CHAT_*``; boot validation already requires it in
  production, and it has no public URL by design).

Bytes are only ever returned through the permission-checked admin route that
proxies them server-side. No public URL and no presigned URL is ever created
for these objects.

Failure policy
--------------
* Production (``APP_ENV`` not development/testing): R2 is the only backend.
  An R2 failure raises :class:`PrivateMediaError`; callers answer 503 and the
  DB is left untouched. There is NEVER a silent fallback to ephemeral disk.
* development/testing without R2 configured: local disk, as before.
"""

from __future__ import annotations

import logging
import os
import secrets
from typing import Any

from flask import current_app

logger = logging.getLogger(__name__)

R2_REF_PREFIX = "r2:"
DEALER_VERIFICATION_PREFIX = "dealer_verification/"
_DISK_SUBDIR = "dealer_verification"

_CONTENT_TYPES = {
    ".jpg": "image/jpeg",
    ".jpeg": "image/jpeg",
    ".png": "image/png",
    ".webp": "image/webp",
    ".heic": "image/heic",
    ".heif": "image/heif",
}


class PrivateMediaError(RuntimeError):
    """Storage backend unavailable/failed (caller should answer 503)."""


class PrivateMediaNotFound(PrivateMediaError):
    """The referenced photo does not exist in its backend."""


def content_type_for(value: str | None) -> str:
    ext = os.path.splitext((value or "").strip())[1].lower()
    return _CONTENT_TYPES.get(ext, "application/octet-stream")


def is_r2_ref(value: str | None) -> bool:
    return bool(value) and str(value).startswith(R2_REF_PREFIX)


def _r2_key_from_ref(value: str) -> str:
    key = value[len(R2_REF_PREFIX):].strip()
    # Defence in depth: only ever operate on our own prefix, never a
    # chat-media or arbitrary key, and never a path-traversal shape.
    if (
        not key.startswith(DEALER_VERIFICATION_PREFIX)
        or ".." in key
        or "\\" in key
        or key.count("/") != 1
    ):
        raise PrivateMediaError("invalid private media reference")
    return key


def _r2_available() -> bool:
    from .r2_ops import r2_chat_configured_from_config

    return r2_chat_configured_from_config(current_app.config)


def _disk_fallback_allowed() -> bool:
    from .config import get_app_env

    return get_app_env() in ("development", "testing")


def _disk_folder() -> str:
    return os.path.join(current_app.config["PRIVATE_UPLOAD_FOLDER"], _DISK_SUBDIR)


def backend_name() -> str:
    if _r2_available():
        return "r2"
    if _disk_fallback_allowed():
        return "disk"
    return "unavailable"


def store_dealer_verification(data: bytes, extension: str) -> str:
    """Persist ``data`` and return the value to store in the DB column.

    Raises :class:`PrivateMediaError` if no durable private backend works.
    """
    if not data:
        raise PrivateMediaError("empty file")
    ext = (extension or ".jpg").lower()
    if ext not in _CONTENT_TYPES:
        ext = ".jpg"
    token = secrets.token_hex(24)

    if _r2_available():
        from .r2_ops import r2_chat_put_bytes

        key = f"{DEALER_VERIFICATION_PREFIX}{token}{ext}"
        try:
            r2_chat_put_bytes(
                key=key,
                body=data,
                content_type=_CONTENT_TYPES[ext],
            )
        except Exception as e:  # network, credentials, subprocess, timeout
            logger.error("dealer verification photo R2 store failed: %s", e)
            raise PrivateMediaError("private storage unavailable") from e
        return f"{R2_REF_PREFIX}{key}"

    if _disk_fallback_allowed():
        folder = _disk_folder()
        os.makedirs(folder, exist_ok=True)
        name = f"{token}{ext}"
        try:
            with open(os.path.join(folder, name), "wb") as fp:
                fp.write(data)
        except OSError as e:
            raise PrivateMediaError("local storage failed") from e
        return name

    # Production without the private bucket: refuse rather than write to a
    # disk that will be wiped on the next deploy.
    raise PrivateMediaError("durable private storage is not configured")


def read_dealer_verification(value: str) -> tuple[bytes, str]:
    """Return ``(bytes, content_type)`` for a stored reference.

    Reads an R2 reference from the private bucket, or a legacy bare filename
    from the private disk folder. Raises :class:`PrivateMediaNotFound` when
    the object/file is missing and :class:`PrivateMediaError` when the
    backend itself failed.
    """
    value = (value or "").strip()
    if not value:
        raise PrivateMediaNotFound("no reference")

    if is_r2_ref(value):
        key = _r2_key_from_ref(value)
        if not _r2_available():
            raise PrivateMediaError("private storage is not configured")
        from .r2_ops import r2_chat_get_bytes, r2_chat_head_object

        try:
            head: dict[str, Any] | None = r2_chat_head_object(key=key)
        except Exception as e:
            logger.error("dealer verification photo R2 head failed: %s", e)
            raise PrivateMediaError("private storage unavailable") from e
        if not head or not head.get("exists"):
            raise PrivateMediaNotFound(key)
        try:
            body = r2_chat_get_bytes(key=key)
        except Exception as e:
            logger.error("dealer verification photo R2 read failed: %s", e)
            raise PrivateMediaError("private storage unavailable") from e
        return body, content_type_for(key)

    # Legacy local-disk file (bare filename; never trust path components).
    name = os.path.basename(value)
    path = os.path.join(_disk_folder(), name)
    if not name or not os.path.isfile(path):
        raise PrivateMediaNotFound(name)
    try:
        with open(path, "rb") as fp:
            return fp.read(), content_type_for(name)
    except OSError as e:
        raise PrivateMediaError("local storage failed") from e


def delete_dealer_verification(value: str | None) -> bool:
    """Best-effort delete. Never raises. Returns True if nothing is left."""
    value = (value or "").strip()
    if not value:
        return True
    try:
        if is_r2_ref(value):
            key = _r2_key_from_ref(value)
            if not _r2_available():
                return False
            from .r2_ops import r2_chat_delete_object

            r2_chat_delete_object(key=key)
            return True
        path = os.path.join(_disk_folder(), os.path.basename(value))
        if os.path.isfile(path):
            os.remove(path)
        return True
    except Exception as e:
        logger.warning("dealer verification photo delete failed (best-effort): %s", e)
        return False
