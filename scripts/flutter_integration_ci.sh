#!/usr/bin/env bash
# Device/emulator integration smoke (M-18).
# Requires a connected Android device or emulator (or android-emulator-runner in CI).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

FLAVOR="${FLAVOR:-dev}"

echo "flutter_integration_ci: flavor=$FLAVOR"
flutter test integration_test/app_smoke_test.dart --flavor "$FLAVOR" "$@"
