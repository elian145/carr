#!/usr/bin/env bash
# Render start command for admin-web (optional; render.yaml uses `npm start` directly).
set -euo pipefail
cd "$(dirname "$0")"
export NODE_ENV="${NODE_ENV:-production}"
export PORT="${PORT:-3000}"
exec npm start
