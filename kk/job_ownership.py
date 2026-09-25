"""
Ownership tracking for Celery job polling.

``GET /api/jobs/<task_id>`` must not leak task state/results to arbitrary
authenticated users. Ownership is recorded at enqueue time (Redis when
available, otherwise an in-process map for single-worker/dev/test).
"""

from __future__ import annotations

import logging
import re
import time
from typing import Any

logger = logging.getLogger(__name__)

# Celery default ids are UUIDs; also allow hex tokens used by some backends.
_TASK_ID_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9_.\-]{7,200}$")
_OWNER_KEY_PREFIX = "job:owner:"
_DEFAULT_TTL_S = 60 * 60 * 24  # 24h — matches long image jobs + polling window

# In-process fallback: task_id -> (owner_public_id, expires_at_epoch)
_memory_owners: dict[str, tuple[str, float]] = {}


def is_valid_task_id(task_id: str) -> bool:
    raw = (task_id or "").strip()
    return bool(raw and _TASK_ID_RE.match(raw))


def _redis_client():
    try:
        from .security import _redis_client as redis_client

        return redis_client()
    except Exception:
        return None


def register_job_owner(
    task_id: str,
    owner_public_id: str,
    *,
    ttl_s: int = _DEFAULT_TTL_S,
) -> None:
    """Bind a Celery task id to the user who enqueued it."""
    tid = (task_id or "").strip()
    owner = (owner_public_id or "").strip()
    if not tid or not owner or not is_valid_task_id(tid):
        return

    r = _redis_client()
    if r is not None:
        try:
            r.setex(f"{_OWNER_KEY_PREFIX}{tid}", int(ttl_s), owner)
            return
        except Exception:
            logger.exception("Failed to register job owner in Redis for %s", tid)

    # Best-effort local fallback (dev/test / Redis outage).
    _purge_expired_memory()
    _memory_owners[tid] = (owner, time.time() + max(60, int(ttl_s)))


def get_registered_job_owner(task_id: str) -> str | None:
    tid = (task_id or "").strip()
    if not tid or not is_valid_task_id(tid):
        return None

    r = _redis_client()
    if r is not None:
        try:
            val = r.get(f"{_OWNER_KEY_PREFIX}{tid}")
            if val:
                return str(val).strip() or None
        except Exception:
            logger.exception("Failed to read job owner from Redis for %s", tid)

    entry = _memory_owners.get(tid)
    if not entry:
        return None
    owner, expires_at = entry
    if time.time() > expires_at:
        _memory_owners.pop(tid, None)
        return None
    return owner


def owner_from_task_payload(payload: Any) -> str | None:
    """Extract owner_public_id from Celery result/meta dicts when present."""
    if not isinstance(payload, dict):
        return None
    owner = payload.get("owner_public_id") or payload.get("ownerPublicId")
    if owner is None:
        return None
    text = str(owner).strip()
    return text or None


def resolve_job_owner(task_id: str, *, result_payload: Any = None, meta_payload: Any = None) -> str | None:
    """
    Resolve the owner for a job.

    Prefer the enqueue-time registry; fall back to result/meta embedded by the task.
    """
    owner = get_registered_job_owner(task_id)
    if owner:
        return owner
    return owner_from_task_payload(result_payload) or owner_from_task_payload(meta_payload)


def _purge_expired_memory() -> None:
    now = time.time()
    expired = [k for k, (_, exp) in _memory_owners.items() if now > exp]
    for k in expired:
        _memory_owners.pop(k, None)


def clear_job_owners_for_tests() -> None:
    """Test helper: wipe in-memory ownership map."""
    _memory_owners.clear()


# ---------------------------------------------------------------------------
# Phase 2 of the server-side video transcode fallback: durable job-enqueue
# idempotency.
#
# ``POST /api/media/r2/finalize-video-source-upload`` must NOT enqueue a new
# Celery transcode task every time it is called for the same
# (owner, draft_media_id) -- a client may legitimately call finalize more
# than once (retry after a dropped response, app restart, duplicate submit).
# This is explicitly NOT solved with a plain in-memory Python dict (that
# would not survive a web-process restart and would not be shared across
# multiple web workers/instances) -- it reuses this EXACT module's existing
# Redis-backed pattern (``_redis_client()``, with the same in-process
# fallback already used by ``register_job_owner`` above for dev/test/Redis
# outage) rather than introducing a new, separate persistence mechanism or a
# new DB model. A dedup record is keyed by a caller-chosen string (see
# ``kk/tasks/video_tasks.py``'s ``_video_job_dedupe_key()``) and simply maps
# to the Celery task id that was enqueued for it -- looking that task id up
# again via Celery's own ``AsyncResult`` (see
# ``kk/routes/media.py::finalize_video_source_upload``) is what lets the
# response also report a live job state, without this module needing to
# know anything about Celery task state itself.
# ---------------------------------------------------------------------------
_IDEMPOTENCY_KEY_PREFIX = "job:idempotent:"
_DEFAULT_IDEMPOTENCY_TTL_S = 60 * 60 * 24  # 24h -- see kk/tasks/video_tasks.py's TTL rationale

# In-process fallback: dedupe_key -> (task_id, expires_at_epoch)
_memory_idempotent_jobs: dict[str, tuple[str, float]] = {}


def get_idempotent_job_task_id(dedupe_key: str) -> str | None:
    """Return the previously-enqueued task id for ``dedupe_key``, if any."""
    key = (dedupe_key or "").strip()
    if not key:
        return None

    r = _redis_client()
    if r is not None:
        try:
            val = r.get(f"{_IDEMPOTENCY_KEY_PREFIX}{key}")
            if val:
                return str(val).strip() or None
        except Exception:
            logger.exception("Failed to read idempotent job id from Redis for %s", key)

    entry = _memory_idempotent_jobs.get(key)
    if not entry:
        return None
    task_id, expires_at = entry
    if time.time() > expires_at:
        _memory_idempotent_jobs.pop(key, None)
        return None
    return task_id


def register_idempotent_job_task_id(
    dedupe_key: str,
    task_id: str,
    *,
    ttl_s: int = _DEFAULT_IDEMPOTENCY_TTL_S,
) -> None:
    """Record that ``dedupe_key`` has already enqueued ``task_id``.

    Callers must call :func:`get_idempotent_job_task_id` first and only
    call this when it returned ``None`` -- this function itself does not
    perform a check-then-set; a benign race (two near-simultaneous finalize
    calls both missing the initial read) can at worst enqueue two tasks,
    exactly the same benign-duplicate-work race Celery/idempotency designs
    of this size normally accept, and is not the primary abuse case this
    guards against (repeated/retried calls from ONE client over time).
    """
    key = (dedupe_key or "").strip()
    tid = (task_id or "").strip()
    if not key or not tid:
        return

    r = _redis_client()
    if r is not None:
        try:
            r.setex(f"{_IDEMPOTENCY_KEY_PREFIX}{key}", int(ttl_s), tid)
            return
        except Exception:
            logger.exception("Failed to register idempotent job id in Redis for %s", key)

    _memory_idempotent_jobs[key] = (tid, time.time() + max(60, int(ttl_s)))


def clear_idempotent_jobs_for_tests() -> None:
    """Test helper: wipe in-memory idempotency map."""
    _memory_idempotent_jobs.clear()
