import os

# Bind: use BIND if set, else 0.0.0.0:PORT (Render/Heroku set PORT), else 0.0.0.0:5003
_port = os.environ.get("PORT", "5003")
bind = os.environ.get("BIND") or f"0.0.0.0:{_port}"

# Reasonable defaults; override in env.
#
# IMPORTANT:
# - If you run multiple Gunicorn workers AND use Socket.IO, you MUST configure
#   a Socket.IO message queue (Redis) so broadcasts reach all clients.
# - If no message queue is configured, default to 1 worker to avoid broken chat.
_mq = (os.environ.get("SOCKETIO_MESSAGE_QUEUE") or os.environ.get("REDIS_URL") or "").strip()
_w_default = "2" if _mq else "1"
workers = int(os.environ.get("WEB_CONCURRENCY", _w_default))
threads = int(os.environ.get("GUNICORN_THREADS", "4"))

timeout = int(os.environ.get("GUNICORN_TIMEOUT", "60"))
graceful_timeout = int(os.environ.get("GUNICORN_GRACEFUL_TIMEOUT", "30"))
keepalive = int(os.environ.get("GUNICORN_KEEPALIVE", "5"))

# Logging to stdout/stderr for platform capture
accesslog = "-"
errorlog = "-"
loglevel = os.environ.get("LOG_LEVEL", "info").lower()

# Socket.IO worker class MUST match flask-socketio async_mode (kk.app_factory).
# Default: gthread + threading (safe; Redis message queue still works for fan-out).
# Opt-in websockets: set SOCKETIO_ASYNC_MODE=eventlet|gevent AND a message queue
# so the async worker monkey-patches *before* the app is imported.
# Never pair SOCKETIO_ASYNC_MODE=eventlet with gthread — late monkey_patch hangs workers.
_sio_async = (os.environ.get("SOCKETIO_ASYNC_MODE") or "").strip().lower()
_use_async_worker = bool(_mq) and _sio_async in ("eventlet", "gevent")
if _use_async_worker and _sio_async == "eventlet":
    worker_class = "eventlet"
elif _use_async_worker and _sio_async == "gevent":
    worker_class = "gevent"
else:
    worker_class = "gthread"
    if _sio_async in ("eventlet", "gevent") and not _mq:
        # Avoid late monkey_patch under gthread; app_factory should also stay on threading
        # unless Redis is configured — surface a clear boot warning via stderr.
        import sys

        print(
            "WARNING: SOCKETIO_ASYNC_MODE="
            + _sio_async
            + " requires REDIS_URL or SOCKETIO_MESSAGE_QUEUE; "
            "falling back to gthread. Unset SOCKETIO_ASYNC_MODE or set a message queue.",
            file=sys.stderr,
        )

# Basic hardening
limit_request_line = 8190
limit_request_fields = 100
limit_request_field_size = 8190

