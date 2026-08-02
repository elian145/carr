#!/usr/bin/env bash
# Start command for Render (and any PaaS that runs from repo root).
# Use this as Render "Start Command":  bash start_render.sh
set -e
# Ensure we run from repo root (where kk/ and gunicorn.conf.py live).
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
cd "$ROOT"
export FLASK_APP=kk.wsgi:app
# Eventlet monkey_patch after Flask import takes Render down with 502s.
# Prefer threading/gthread unless SOCKETIO_ALLOW_EVENTLET=1 is set deliberately.
if [ "${SOCKETIO_ALLOW_EVENTLET:-}" != "1" ] && [ "${SOCKETIO_ALLOW_EVENTLET:-}" != "true" ]; then
  case "${SOCKETIO_ASYNC_MODE:-}" in
    eventlet|gevent)
      echo "WARNING: clearing SOCKETIO_ASYNC_MODE=${SOCKETIO_ASYNC_MODE} (use gthread/threading). Set SOCKETIO_ALLOW_EVENTLET=1 to keep it."
      unset SOCKETIO_ASYNC_MODE
      ;;
  esac
fi
echo "Running database migrations..."
python -m flask db upgrade
echo "Starting gunicorn..."
exec gunicorn "kk.wsgi:app" -c "gunicorn.conf.py"
