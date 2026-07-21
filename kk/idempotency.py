"""Idempotent POST helpers (audit: listing create)."""

from __future__ import annotations

import json
import logging
import threading
import time
from typing import Any

logger = logging.getLogger(__name__)

_LOCK = threading.Lock()
_MEMORY: dict[str, tuple[float, int, Any]] = {}
_DEFAULT_TTL_S = 24 * 60 * 60


def _redis():
    try:
        from .security import _redis_client

        return _redis_client()
    except Exception:
        return None


def _mem_get(key: str) -> tuple[int, Any] | None:
    now = time.time()
    with _LOCK:
        row = _MEMORY.get(key)
        if not row:
            return None
        expires, status, body = row
        if expires <= now:
            _MEMORY.pop(key, None)
            return None
        return status, body


def _mem_set(key: str, status: int, body: Any, ttl_s: int) -> None:
    with _LOCK:
        _MEMORY[key] = (time.time() + ttl_s, status, body)


def remember_response(
    *,
    scope: str,
    actor_id: str,
    idem_key: str,
    status: int,
    body: Any,
    ttl_s: int = _DEFAULT_TTL_S,
) -> None:
    """Store a successful response for later replay."""
    key = f"idem:{scope}:{actor_id}:{idem_key.strip()}"
    if not idem_key.strip():
        return
    r = _redis()
    if r is not None:
        try:
            payload = json.dumps(
                {"status": int(status), "body": body},
                separators=(",", ":"),
                default=str,
            )
            r.setex(key, int(ttl_s), payload)
            return
        except Exception as e:
            logger.warning("idempotency redis set failed: %s", e)
    _mem_set(key, int(status), body, int(ttl_s))


def replay_response(
    *,
    scope: str,
    actor_id: str,
    idem_key: str,
) -> tuple[int, Any] | None:
    """Return (status, body) if this key was already completed."""
    cleaned = (idem_key or "").strip()
    if not cleaned:
        return None
    key = f"idem:{scope}:{actor_id}:{cleaned}"
    r = _redis()
    if r is not None:
        try:
            raw = r.get(key)
            if raw:
                data = json.loads(raw)
                return int(data["status"]), data["body"]
        except Exception as e:
            logger.warning("idempotency redis get failed: %s", e)
    return _mem_get(key)
