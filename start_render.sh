#!/usr/bin/env bash
# Start command for Render (and any PaaS that runs from repo root).
# Use this as Render "Start Command":  bash start_render.sh
# Or set Start Command to:  gunicorn "kk.wsgi:app" -c "gunicorn.conf.py"
set -e
cd "$(dirname "$0")"
exec gunicorn "kk.wsgi:app" -c "gunicorn.conf.py"
