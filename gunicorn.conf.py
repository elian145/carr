import os
import sys

# Bind: use BIND if set, else 0.0.0.0:PORT (Render/Heroku set PORT), else 0.0.0.0:5003
_port = os.environ.get("PORT", "5003")
bind = os.environ.get("BIND") or f"0.0.0.0:{_port}"

# Reasonable defaults; override in env.
#
# CHAT-1 (Socket.IO on gthread):
# - Default to 1 worker even when Redis is present. A Redis message queue fans
#   out *broadcasts*, but Engine.IO long-polling sessions are still sticky to
#   the worker that created them. Render's load balancer is not sticky, so
#   WEB_CONCURRENCY>1 causes intermittent connect failures (polling hops).
# - Scale HTTP concurrency with GUNICORN_THREADS, not more workers, unless
#   sticky sessions + Redis Socket.IO queue are verified together.
# - Explicit WEB_CONCURRENCY overrides this default (ops must opt in).
_mq = (os.environ.get("SOCKETIO_MESSAGE_QUEUE") or os.environ.get("REDIS_URL") or "").strip()
try:
    from kk.socketio_deploy import resolve_web_concurrency as _resolve_workers
except Exception:  # pragma: no cover - conf loaded before package on some hosts
    def _resolve_workers(web_concurrency=None, **_kwargs):  # type: ignore[misc]
        try:
            return max(1, int((web_concurrency or "1").strip() or "1"))
        except Exception:
            return 1

workers = _resolve_workers(
    os.environ.get("WEB_CONCURRENCY"),
    redis_url=os.environ.get("REDIS_URL"),
    socketio_message_queue=os.environ.get("SOCKETIO_MESSAGE_QUEUE"),
)
threads = int(os.environ.get("GUNICORN_THREADS", "4"))
if workers > 1 and not _mq:
    print(
        "WARNING: WEB_CONCURRENCY=%s without REDIS_URL/SOCKETIO_MESSAGE_QUEUE; "
        "Socket.IO rooms/broadcasts will not cross workers."
        % workers,
        file=sys.stderr,
    )
elif workers > 1:
    print(
        "WARNING: WEB_CONCURRENCY=%s with Redis MQ still needs sticky sessions "
        "for Engine.IO polling on Render; prefer WEB_CONCURRENCY=1 and raise "
        "GUNICORN_THREADS instead." % workers,
        file=sys.stderr,
    )

timeout = int(os.environ.get("GUNICORN_TIMEOUT", "60"))
graceful_timeout = int(os.environ.get("GUNICORN_GRACEFUL_TIMEOUT", "30"))
keepalive = int(os.environ.get("GUNICORN_KEEPALIVE", "5"))

# Logging to stdout/stderr for platform capture
accesslog = "-"
errorlog = "-"
loglevel = os.environ.get("LOG_LEVEL", "info").lower()

# Socket.IO worker class MUST match flask-socketio async_mode (kk.app_factory).
# Default: gthread + threading (safe; Redis message queue still works for fan-out).
#
# Eventlet is deprecated and currently breaks boot on Render: flask-socketio calls
# monkey_patch() after Flask/Werkzeug are imported → LocalProxy / RLock errors and
# 502s. Do NOT enable it just because SOCKETIO_ASYNC_MODE=eventlet is set in the
# dashboard. Require the explicit break-glass flag SOCKETIO_ALLOW_EVENTLET=1 plus
# a Redis message queue.
_sio_async = (os.environ.get("SOCKETIO_ASYNC_MODE") or "").strip().lower()
_allow_eventlet = (os.environ.get("SOCKETIO_ALLOW_EVENTLET") or "").strip().lower() in (
    "1",
    "true",
    "yes",
)
_use_async_worker = (
    _allow_eventlet and bool(_mq) and _sio_async in ("eventlet", "gevent")
)
if _use_async_worker and _sio_async == "eventlet":
    worker_class = "eventlet"
elif _use_async_worker and _sio_async == "gevent":
    worker_class = "gevent"
else:
    worker_class = "gthread"
    if _sio_async in ("eventlet", "gevent"):
        reason = (
            "SOCKETIO_ALLOW_EVENTLET is not set"
            if not _allow_eventlet
            else "REDIS_URL / SOCKETIO_MESSAGE_QUEUE is missing"
        )
        print(
            "WARNING: ignoring SOCKETIO_ASYNC_MODE="
            + _sio_async
            + " ("
            + reason
            + "); using gthread. Unset SOCKETIO_ASYNC_MODE on Render.",
            file=sys.stderr,
        )

# Basic hardening
limit_request_line = 8190
limit_request_fields = 100
limit_request_field_size = 8190

