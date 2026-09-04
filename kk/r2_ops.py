"""
Eventlet-safe Cloudflare R2 helpers.

boto3 client creation recurses forever under eventlet's SSL monkey-patch
(RecursionError in ssl.SSLContext.options). Run S3 ops in a clean subprocess
(same pattern as OTPIQ / Roboflow).
"""
from __future__ import annotations

import json
import logging
import os
import subprocess
import sys
import tempfile
from typing import Any

from flask import current_app

logger = logging.getLogger(__name__)

_r2_script_path: str | None = None


def _get_r2_script_path() -> str | None:
    global _r2_script_path
    if _r2_script_path is None:
        here = os.path.dirname(os.path.abspath(__file__))
        path = os.path.join(here, "..", "tools", "r2_s3_op.py")
        if os.path.isfile(path):
            _r2_script_path = os.path.normpath(os.path.abspath(path))
        else:
            _r2_script_path = ""
    return _r2_script_path or None


def r2_configured_from_config(config: Any) -> bool:
    return bool(
        config.get("R2_ACCOUNT_ID")
        and config.get("R2_BUCKET_NAME")
        and config.get("R2_ACCESS_KEY_ID")
        and config.get("R2_SECRET_ACCESS_KEY")
    )


def r2_public_base_from_config(config: Any) -> str:
    return (config.get("R2_PUBLIC_URL") or "").strip().rstrip("/")


def r2_chat_configured_from_config(config: Any) -> bool:
    """C-10: True when the PRIVATE chat-media bucket is fully configured.

    Deliberately does NOT check for a public URL — this bucket must never
    have one.
    """
    return bool(
        config.get("R2_ACCOUNT_ID")
        and config.get("R2_CHAT_BUCKET_NAME")
        and config.get("R2_CHAT_ACCESS_KEY_ID")
        and config.get("R2_CHAT_SECRET_ACCESS_KEY")
    )


def _cred_payload() -> dict[str, str]:
    c = current_app.config
    return {
        "account_id": (c.get("R2_ACCOUNT_ID") or "").strip(),
        "bucket": (c.get("R2_BUCKET_NAME") or "").strip(),
        "access_key": (c.get("R2_ACCESS_KEY_ID") or "").strip(),
        "secret_key": (c.get("R2_SECRET_ACCESS_KEY") or "").strip(),
        "region": (os.environ.get("R2_REGION") or "auto").strip() or "auto",
    }


def _chat_cred_payload() -> dict[str, str]:
    """Credentials for the PRIVATE chat-media bucket (C-10).

    Same Cloudflare account as listing media (shared R2_ACCOUNT_ID), but its
    own bucket name + access key/secret so a scoped API token can be limited
    to only this bucket.
    """
    c = current_app.config
    return {
        "account_id": (c.get("R2_ACCOUNT_ID") or "").strip(),
        "bucket": (c.get("R2_CHAT_BUCKET_NAME") or "").strip(),
        "access_key": (c.get("R2_CHAT_ACCESS_KEY_ID") or "").strip(),
        "secret_key": (c.get("R2_CHAT_SECRET_ACCESS_KEY") or "").strip(),
        "region": (os.environ.get("R2_REGION") or "auto").strip() or "auto",
    }


# Default presigned-GET lifetime for private chat media (C-10). Short-lived by
# design: long enough for a client to load/play the media once, short enough
# to bound the exposure window of a leaked URL (proxy log, screenshot, etc.).
CHAT_PRESIGN_GET_DEFAULT_EXPIRES_SECONDS = 600


def _run_r2_op(payload: dict[str, Any], *, timeout: float) -> dict[str, Any]:
    script_path = _get_r2_script_path()
    if not script_path:
        raise RuntimeError("r2_s3_op.py missing")

    proc = subprocess.run(
        [sys.executable, script_path],
        input=json.dumps(payload),
        capture_output=True,
        text=True,
        timeout=timeout,
        env=os.environ.copy(),
    )
    out = (proc.stdout or "").strip()
    if not out:
        err = (proc.stderr or "").strip() or f"exit {proc.returncode}"
        raise RuntimeError(err)
    try:
        result = json.loads(out)
    except json.JSONDecodeError as e:
        raise RuntimeError(f"invalid r2 subprocess response: {e}") from e
    if not isinstance(result, dict):
        raise RuntimeError("invalid r2 subprocess response")
    if result.get("error"):
        raise RuntimeError(str(result["error"]))
    if not result.get("ok"):
        raise RuntimeError("r2 subprocess failed")
    return result


def r2_put_bytes(
    *,
    key: str,
    body: bytes,
    content_type: str = "application/octet-stream",
    timeout: float = 120,
) -> None:
    """Upload bytes to R2 under ``key`` (eventlet-safe)."""
    if not body:
        raise RuntimeError("Empty file body")
    creds = _cred_payload()
    fd, path = tempfile.mkstemp(prefix="r2_put_", suffix=".bin")
    try:
        with os.fdopen(fd, "wb") as fp:
            fp.write(body)
        payload = {
            **creds,
            "op": "put_object",
            "key": key,
            "content_type": content_type,
            "body_path": path,
        }
        _run_r2_op(payload, timeout=timeout)
    finally:
        try:
            os.remove(path)
        except OSError:
            pass


def r2_chat_put_bytes(
    *,
    key: str,
    body: bytes,
    content_type: str = "application/octet-stream",
    timeout: float = 120,
) -> None:
    """Upload bytes to the PRIVATE chat-media R2 bucket (C-10, eventlet-safe).

    Uses the R2_CHAT_* credentials/bucket — never the public listing-media
    bucket. Callers must store only the returned ``key`` (never a public
    URL); reads must go through :func:`r2_presign_get`.
    """
    if not body:
        raise RuntimeError("Empty file body")
    creds = _chat_cred_payload()
    fd, path = tempfile.mkstemp(prefix="r2_chat_put_", suffix=".bin")
    try:
        with os.fdopen(fd, "wb") as fp:
            fp.write(body)
        payload = {
            **creds,
            "op": "put_object",
            "key": key,
            "content_type": content_type,
            "body_path": path,
        }
        _run_r2_op(payload, timeout=timeout)
    finally:
        try:
            os.remove(path)
        except OSError:
            pass


def r2_presign_get(
    *,
    key: str,
    expires_in: int = CHAT_PRESIGN_GET_DEFAULT_EXPIRES_SECONDS,
    timeout: float = 30,
) -> str:
    """Return a short-lived presigned GET URL for one object (C-10).

    Always targets the PRIVATE chat-media bucket (R2_CHAT_*), never the
    public listing-media bucket. Callers MUST only invoke this after already
    confirming the current viewer is authorized to see the message that owns
    ``key`` — this function performs no authorization of its own.
    """
    creds = _chat_cred_payload()
    payload: dict[str, Any] = {
        **creds,
        "op": "presign_get",
        "key": key,
        "expires_in": expires_in,
    }
    result = _run_r2_op(payload, timeout=timeout)
    url = (result.get("download_url") or "").strip()
    if not url:
        raise RuntimeError("presign_get returned empty download_url")
    return url


def r2_presign_put(
    *,
    key: str,
    content_type: str,
    expires_in: int = 900,
    content_length: int | None = None,
    timeout: float = 30,
) -> str:
    """Return a presigned PUT URL for R2 (eventlet-safe)."""
    creds = _cred_payload()
    payload: dict[str, Any] = {
        **creds,
        "op": "presign_put",
        "key": key,
        "content_type": content_type,
        "expires_in": expires_in,
    }
    if content_length is not None:
        payload["content_length"] = content_length
    result = _run_r2_op(payload, timeout=timeout)
    url = (result.get("upload_url") or "").strip()
    if not url:
        raise RuntimeError("presign returned empty upload_url")
    return url
