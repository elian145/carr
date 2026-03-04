#!/usr/bin/env bash
# Start command for Render (and any PaaS that runs from repo root).
# Use this as Render "Start Command":  bash start_render.sh
set -e
# Ensure we run from repo root (where kk/ and gunicorn.conf.py live).
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
cd "$ROOT"
export FLASK_APP=kk.wsgi:app
echo "Running database migrations..."
python -m flask db upgrade
echo "Starting gunicorn..."
exec gunicorn "kk.wsgi:app" -c "gunicorn.conf.py"
