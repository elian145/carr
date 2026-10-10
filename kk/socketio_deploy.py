"""Socket.IO / Gunicorn deployment helpers (CHAT-1).

Keeps worker-count policy testable without importing ``gunicorn.conf``
(which binds ports / reads live env at import time).
"""

from __future__ import annotations


def resolve_web_concurrency(
    web_concurrency: str | None = None,
    *,
    redis_url: str | None = None,
    socketio_message_queue: str | None = None,
) -> int:
    """Return the Gunicorn worker count for Socket.IO-safe defaults.

    Redis presence alone must **not** raise the default above 1: with
    ``gthread`` + Engine.IO polling on a non-sticky load balancer, multiple
    workers break session affinity even when a Socket.IO message queue is
    configured.
    """
    raw = (web_concurrency or "").strip()
    if raw:
        try:
            n = int(raw)
            return n if n > 0 else 1
        except ValueError:
            return 1
    # Intentionally ignore redis_url / socketio_message_queue for the default.
    _ = redis_url, socketio_message_queue
    return 1


def socketio_multi_worker_requires_sticky_sessions(worker_count: int) -> bool:
    """True when ops must provide sticky sessions in addition to Redis MQ."""
    return worker_count > 1
