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


# C-1: with ``gthread`` + threading Socket.IO each open WebSocket pins one worker
# thread, so the old default of 4 let four sockets starve the whole REST API.
DEFAULT_GUNICORN_THREADS = 32
DEFAULT_SOCKETIO_MAX_HTTP_BUFFER_SIZE = 64 * 1024  # bytes per Socket.IO frame
DEFAULT_JSON_MAX_CONTENT_LENGTH = 1024 * 1024  # bytes per JSON request body


def resolve_gunicorn_threads(raw: str | None = None) -> int:
    """Gunicorn ``threads`` for the single gthread worker (``GUNICORN_THREADS``)."""
    text = (raw or "").strip()
    if not text:
        return DEFAULT_GUNICORN_THREADS
    try:
        n = int(text)
    except ValueError:
        return DEFAULT_GUNICORN_THREADS
    return n if n > 0 else DEFAULT_GUNICORN_THREADS


def resolve_socketio_max_http_buffer_size(raw: str | None = None) -> int:
    """Largest Socket.IO message accepted (engine.io ``max_http_buffer_size``)."""
    text = (raw or "").strip()
    try:
        n = int(text) if text else DEFAULT_SOCKETIO_MAX_HTTP_BUFFER_SIZE
    except ValueError:
        return DEFAULT_SOCKETIO_MAX_HTTP_BUFFER_SIZE
    return n if n >= 1024 else DEFAULT_SOCKETIO_MAX_HTTP_BUFFER_SIZE


def resolve_json_max_content_length(raw: str | None = None) -> int:
    """Largest ``application/json`` request body accepted (``JSON_MAX_CONTENT_LENGTH``)."""
    text = (raw or "").strip()
    try:
        n = int(text) if text else DEFAULT_JSON_MAX_CONTENT_LENGTH
    except ValueError:
        return DEFAULT_JSON_MAX_CONTENT_LENGTH
    return n if n >= 1024 else DEFAULT_JSON_MAX_CONTENT_LENGTH
