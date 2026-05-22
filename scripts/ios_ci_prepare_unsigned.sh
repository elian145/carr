#!/usr/bin/env bash
# Prepare Xcode for an unsigned iphoneos build on CI (Codemagic / no Apple login).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

TEAM="${APPLE_TEAM_ID:-LN3R46L4H8}"
export APPLE_TEAM_ID="$TEAM"

MARKER="// CI unsigned build (scripts/ios_ci_prepare_unsigned.sh)"
append_xcconfig() {
  local cfg="$1"
  [ -f "$cfg" ] || return 0
  # Remove prior CI append (idempotent).
  if grep -qF "$MARKER" "$cfg" 2>/dev/null; then
    perl -0pi -e 's/\n\/\/ CI unsigned build[\s\S]*$//' "$cfg"
  fi
  # Remove invalid # comment lines from older script versions.
  perl -pi -e 's/^# CI unsigned.*\n//mg' "$cfg" 2>/dev/null || true
  cat >>"$cfg" <<EOF

$MARKER
CODE_SIGN_STYLE=Manual
CODE_SIGNING_ALLOWED=NO
CODE_SIGNING_REQUIRED=NO
DEVELOPMENT_TEAM=$TEAM
CODE_SIGN_IDENTITY=
EOF
}

append_xcconfig ios/Flutter/Release.xcconfig
append_xcconfig ios/Flutter/Debug.xcconfig

python3 scripts/ios_ci_prepare_unsigned.py

echo "iOS CI: unsigned device build ready (TEAM=$TEAM, signing disabled)."
