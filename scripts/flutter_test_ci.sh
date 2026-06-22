#!/usr/bin/env bash
# CI test runner: API/unit tests in parallel; widget/smoke tests one at a time.
#
# Widget tests import production_app → carzo_shared (multi-thousand-line library).
# After `flutter clean`, compiling many of those suites in parallel on macOS CI
# often fails at "loading …" (OOM / compile timeout). Serializing them fixes that.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

shopt -s nullglob

HEAVY=(
  test/app_smoke_test.dart
  test/carzo_app_smoke_test.dart
  test/widget_test.dart
  test/legacy_*_test.dart
)

is_heavy_file() {
  local target="$1"
  local f
  for f in "${HEAVY[@]}"; do
    if [ "$f" = "$target" ]; then
      return 0
    fi
  done
  return 1
}

LIGHT=()
for f in test/*_test.dart; do
  if ! is_heavy_file "$f"; then
    LIGHT+=("$f")
  fi
done

echo "flutter_test_ci: ${#LIGHT[@]} lightweight + ${#HEAVY[@]} widget/smoke test file(s)"

if ((${#LIGHT[@]} > 0)); then
  flutter test "${LIGHT[@]}" --concurrency=4 --timeout=2m "$@"
fi

if ((${#HEAVY[@]} > 0)); then
  flutter test "${HEAVY[@]}" --concurrency=1 --timeout=5m "$@"
fi
