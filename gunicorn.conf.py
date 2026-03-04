import os

# Bind to 0.0.0.0 for containers / cloud
bind = os.environ.get("BIND", "0.0.0.0:5003")

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

# Socket.IO: use a websocket-friendly worker when configured.
# NOTE: For gevent support you'll need gevent/gevent-websocket installed.
_sio_async = (os.environ.get("SOCKETIO_ASYNC_MODE") or "").strip().lower()
if _sio_async == "eventlet":
    worker_class = "eventlet"
elif _sio_async == "gevent":
    worker_class = "gevent"

# Basic hardening
limit_request_line = 8190
limit_request_fields = 100
limit_request_field_size = 8190

