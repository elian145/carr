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
# In-flight claims (F-37): safety net only. A claim is released as soon as the
# request that took it has produced its response; the TTL just bounds how long
# a crashed worker can block retries of the same key.
_INFLIGHT_TTL_S = 120
_INFLIGHT: dict[str, float] = {}


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


# ---------------------------------------------------------------------------
# In-flight claim (F-37)
#
# ``replay_response`` only knows about requests that already COMPLETED. A
# client that times out and re-sends the same Idempotency-Key while the first
# request is still running on the server (the typical Render cold-start case)
# would otherwise pass that check and execute the write a second time. The
# claim below is taken atomically -- Redis ``SET NX EX``, or a lock-protected
# in-process map when Redis is unavailable -- so at most one request per
# (scope, actor, key) executes at a time. A duplicate that arrives meanwhile is
# answered with a retryable 503 (``request_in_progress``); once the first
# request finishes, the same key replays its stored response.
# ---------------------------------------------------------------------------


def _inflight_key(scope: str, actor_id: str, idem_key: str) -> str:
    return f"idem-inflight:{scope}:{actor_id}:{idem_key.strip()}"


def claim_in_flight(
    *,
    scope: str,
    actor_id: str,
    idem_key: str,
    ttl_s: int = _INFLIGHT_TTL_S,
) -> bool:
    """Atomically claim ``(scope, actor, key)``.

    Returns True when the caller now owns the claim (or there is no key to
    claim), False when another request currently holds it.
    """
    cleaned = (idem_key or "").strip()
    if not cleaned:
        return True
    key = _inflight_key(scope, actor_id, cleaned)
    r = _redis()
    if r is not None:
        try:
            return bool(r.set(key, "1", nx=True, ex=int(ttl_s)))
        except Exception as e:
            logger.warning("idempotency redis claim failed: %s", e)
    now = time.time()
    with _LOCK:
        expires = _INFLIGHT.get(key)
        if expires is not None and expires > now:
            return False
        _INFLIGHT[key] = now + int(ttl_s)
        return True


def release_in_flight(*, scope: str, actor_id: str, idem_key: str) -> None:
    """Drop a claim taken with :func:`claim_in_flight` (idempotent)."""
    cleaned = (idem_key or "").strip()
    if not cleaned:
        return
    key = _inflight_key(scope, actor_id, cleaned)
    r = _redis()
    if r is not None:
        try:
            r.delete(key)
        except Exception as e:
            logger.warning("idempotency redis release failed: %s", e)
    with _LOCK:
        _INFLIGHT.pop(key, None)


def begin_request(
    *,
    scope: str,
    actor_id: str,
    idem_key: str,
) -> tuple[str, tuple[int, Any] | None]:
    """Decide how to handle a (possibly repeated) keyed request.

    Returns one of:

    * ``("proceed", None)``  -- execute the request. When a key was supplied
      the claim is released automatically once this request's response has
      been produced (success or failure; a failed request may be retried).
    * ``("replay", (status, body))`` -- the key already completed; return the
      stored response instead of executing again.
    * ``("busy", None)`` -- another request with the same key is executing
      right now; answer with :func:`in_progress_response`.

    Must be called inside a Flask request context.
    """
    cleaned = (idem_key or "").strip()
    if not cleaned:
        return "proceed", None

    replayed = replay_response(scope=scope, actor_id=actor_id, idem_key=cleaned)
    if replayed is not None:
        return "replay", replayed

    if not claim_in_flight(scope=scope, actor_id=actor_id, idem_key=cleaned):
        return "busy", None

    from flask import after_this_request

    @after_this_request
    def _release_claim(response):  # pragma: no cover - trivial wrapper
        release_in_flight(scope=scope, actor_id=actor_id, idem_key=cleaned)
        return response

    # The previous holder may have finished (stored its response and released)
    # between our replay check above and the claim: look again before running.
    replayed = replay_response(scope=scope, actor_id=actor_id, idem_key=cleaned)
    if replayed is not None:
        return "replay", replayed
    return "proceed", None


def in_progress_response():
    """503 + Retry-After for a duplicate that raced the original request.

    503 (not 409/429) on purpose: the app treats 408/5xx as *retryable* and
    keeps the idempotency key and any frozen media manifest, whereas other 4xx
    codes are read as "the server definitively refused this request".
    """
    from flask import jsonify

    response = jsonify(
        {
            "message": "This request is already being processed. Retry shortly.",
            "code": "request_in_progress",
        }
    )
    response.status_code = 503
    response.headers["Retry-After"] = "2"
    return response
