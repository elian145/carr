"""JSON API response caching (Redis when available, in-process fallback).

Used for hot read paths: ``/api/catalog/*`` and ``/api/filters/facets``.
"""

from __future__ import annotations

import json
import logging
import time
from typing import Any

logger = logging.getLogger(__name__)

_PREFIX = "api_resp:"
_CATALOG_PREFIX = f"{_PREFIX}catalog:"
_FACETS_KEY = f"{_PREFIX}filters:facets:v1"

# Default TTLs
CATALOG_TTL_S = 60 * 60  # 1 hour — invalidated on admin catalog writes
FACETS_TTL_S = 5 * 60  # 5 minutes — also invalidated on listing writes

# Dev / no-Redis fallback: key -> (expires_at_epoch, payload)
_memory: dict[str, tuple[float, Any]] = {}
_MEMORY_MAX = 512


def _redis():
    try:
        from .security import _redis_client

        return _redis_client()
    except Exception:
        return None


def _purge_memory() -> None:
    now = time.time()
    expired = [k for k, (exp, _) in _memory.items() if exp <= now]
    for k in expired:
        _memory.pop(k, None)
    if len(_memory) > _MEMORY_MAX:
        for k in list(_memory.keys())[: int(_MEMORY_MAX * 0.1) or 1]:
            _memory.pop(k, None)


def cache_get(key: str) -> Any | None:
    """Return cached JSON-compatible value or None."""
    full = key if key.startswith(_PREFIX) else f"{_PREFIX}{key}"
    r = _redis()
    if r is not None:
        try:
            raw = r.get(full)
            if raw is None:
                return None
            return json.loads(raw)
        except Exception:
            logger.exception("response_cache get failed for %s", full)

    _purge_memory()
    entry = _memory.get(full)
    if entry is None:
        return None
    exp, value = entry
    if exp <= time.time():
        _memory.pop(full, None)
        return None
    return value


def cache_set(key: str, value: Any, ttl_s: int) -> None:
    """Store JSON-compatible value with TTL seconds."""
    full = key if key.startswith(_PREFIX) else f"{_PREFIX}{key}"
    ttl = max(30, int(ttl_s))
    r = _redis()
    if r is not None:
        try:
            r.setex(full, ttl, json.dumps(value, separators=(",", ":"), default=str))
            return
        except Exception:
            logger.exception("response_cache set failed for %s", full)

    _purge_memory()
    _memory[full] = (time.time() + ttl, value)


def cache_delete(*keys: str) -> None:
    full_keys = [k if k.startswith(_PREFIX) else f"{_PREFIX}{k}" for k in keys]
    r = _redis()
    if r is not None and full_keys:
        try:
            r.delete(*full_keys)
        except Exception:
            logger.exception("response_cache delete failed")
    for k in full_keys:
        _memory.pop(k, None)


def cache_delete_prefix(prefix: str) -> None:
    """Delete all keys under prefix (Redis SCAN + memory filter)."""
    full_prefix = prefix if prefix.startswith(_PREFIX) else f"{_PREFIX}{prefix}"
    r = _redis()
    if r is not None:
        try:
            batch: list[str] = []
            for key in r.scan_iter(match=f"{full_prefix}*", count=200):
                batch.append(key)
                if len(batch) >= 200:
                    r.delete(*batch)
                    batch.clear()
            if batch:
                r.delete(*batch)
        except Exception:
            logger.exception("response_cache prefix delete failed for %s", full_prefix)

    for k in list(_memory.keys()):
        if k.startswith(full_prefix):
            _memory.pop(k, None)


def catalog_cache_key(*parts: str) -> str:
    safe = [str(p).strip().lower().replace(" ", "_") for p in parts if str(p).strip()]
    return _CATALOG_PREFIX + (":".join(safe) if safe else "root")


def invalidate_catalog_cache() -> None:
    cache_delete_prefix(_CATALOG_PREFIX)


def invalidate_filter_facets_cache() -> None:
    cache_delete(_FACETS_KEY)


def filter_facets_cache_key() -> str:
    return _FACETS_KEY


def debug_reset_memory_cache() -> None:
    """Test helper: clear in-process fallback store."""
    _memory.clear()
