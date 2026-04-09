#!/usr/bin/env bash
# Render "Build command" — keep output obvious in deploy logs.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
cd "$ROOT"

echo "=== Render build: python ==="
python --version

echo "=== Render build: upgrade pip ==="
python -m pip install --upgrade pip setuptools wheel

echo "=== Render build: install requirements (no wheel cache — saves disk on free tier) ==="
python -m pip install --no-cache-dir -r kk/requirements.txt

echo "=== Render build: OK ==="
