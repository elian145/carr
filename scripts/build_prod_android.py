#!/usr/bin/env python3
"""
Build production Android artifacts with signing + HTTPS API_BASE preflight.

Examples:
  python scripts/build_prod_android.py
  python scripts/build_prod_android.py --apk
  python scripts/build_prod_android.py --api-base https://carr-5hrm.onrender.com
"""

from __future__ import annotations

import argparse
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_API_BASE = "https://carr-5hrm.onrender.com"


class ApiBaseValidationError(ValueError):
    """Raised by validate_api_base() with a distinct, actionable message."""


def validate_api_base(value: str | None) -> str:
    """Validate a candidate production API_BASE value.

    Mirrors the release-mode rules enforced at runtime by
    ``validateReleaseApiBase()`` in ``lib/services/config.dart``: this is the
    **production** build path (no dev/LAN defaults, no insecure-HTTP escape
    hatch), so exactly two failure states are distinguished from the single
    accepted state:

    - missing/empty (after trimming)      -> raises (distinct message)
    - non-empty but not ``https://``      -> raises (distinct message)
    - valid ``https://`` origin           -> returns the normalized value
      (trailing slash stripped)

    Pure / side-effect-free so it can be unit tested directly — see
    ``scripts/test_build_prod_android_validate.py`` — without invoking
    Flutter or performing any I/O.
    """
    raw = (value or "").strip()
    if not raw:
        raise ApiBaseValidationError(
            "Missing API_BASE: pass --api-base https://<your-domain> "
            "(production builds must not omit it)."
        )
    normalized = raw.rstrip("/")
    if not normalized.startswith("https://"):
        raise ApiBaseValidationError(
            f"Insecure API_BASE {normalized!r}: production builds require https://."
        )
    return normalized


def _flutter() -> str:
    return shutil.which("flutter") or "flutter"


def _has_local_signing() -> bool:
    return any((ROOT / rel).is_file() for rel in ("android/signing.properties", "signing.properties"))


def main() -> None:
    p = argparse.ArgumentParser(description="Build prod Android release with preflight checks")
    p.add_argument(
        "--api-base",
        default=DEFAULT_API_BASE,
        help="HTTPS API origin (no /api suffix)",
    )
    p.add_argument("--apk", action="store_true", help="Build APK instead of app bundle")
    p.add_argument("--skip-preflight", action="store_true", help="Skip verify_publish_ready.py")
    args = p.parse_args()

    try:
        api_base = validate_api_base(args.api_base)
    except ApiBaseValidationError as exc:
        print(f"FAIL: {exc}", file=sys.stderr)
        raise SystemExit(1)

    if not args.skip_preflight:
        subprocess.check_call([sys.executable, "scripts/verify_publish_ready.py"], cwd=ROOT)
        if not _has_local_signing():
            print(
                "FAIL: android/signing.properties missing (copy from signing.properties.example)",
                file=sys.stderr,
            )
            raise SystemExit(1)

    target = "apk" if args.apk else "appbundle"
    cmd = [
        _flutter(),
        "build",
        target,
        "--release",
        "--flavor",
        "prod",
        f"--dart-define=API_BASE={api_base}",
    ]
    print(">>", " ".join(cmd))
    subprocess.check_call(cmd, cwd=ROOT)

    if target == "appbundle":
        artifact = ROOT / "build/app/outputs/bundle/prodRelease/app-prod-release.aab"
    else:
        artifact = ROOT / "build/app/outputs/flutter-apk/app-prod-release.apk"

    print(f"\nBuilt prod {target} with API_BASE={api_base}")
    if artifact.is_file():
        print(f"Artifact: {artifact.relative_to(ROOT)}")
        subprocess.check_call(
            [sys.executable, "scripts/verify_aab_signing.py", str(artifact)],
            cwd=ROOT,
        )
    print("\nBefore Play upload:")
    print("  1. Set ANDROID_SHA256_CERT_FINGERPRINTS on Render (python scripts/print_android_app_link_sha.py)")
    print("  2. python scripts/publish_gate.py --host", api_base)
    print("  3. Upload the AAB to Play Console (internal testing first)")


if __name__ == "__main__":
    main()
