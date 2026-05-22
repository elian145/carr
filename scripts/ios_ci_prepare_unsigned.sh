#!/usr/bin/env bash
# Prepare Xcode for an unsigned iphoneos build on CI (Codemagic / no Apple login).
# Flutter 3.22+ still targets device for `flutter build ios --release --no-codesign`
# unless signing is explicitly disabled in xcconfig / project settings.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

MARKER="// CI unsigned build (scripts/ios_ci_prepare_unsigned.sh)"
for cfg in ios/Flutter/Release.xcconfig ios/Flutter/Debug.xcconfig; do
  if [ -f "$cfg" ] && ! grep -qF "$MARKER" "$cfg" 2>/dev/null; then
    cat >>"$cfg" <<EOF

$MARKER
CODE_SIGN_STYLE=Manual
CODE_SIGNING_ALLOWED=NO
CODE_SIGNING_REQUIRED=NO
DEVELOPMENT_TEAM=
CODE_SIGN_IDENTITY=
EOF
  fi
done

python3 scripts/ios_ci_prepare_unsigned.py

echo "iOS CI: disabled code signing for unsigned device build."
