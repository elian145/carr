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

    api_base = args.api_base.strip().rstrip("/")
    if not api_base.startswith("https://"):
        print("FAIL: --api-base must use https://", file=sys.stderr)
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
    print("\nBefore Play upload:")
    print("  1. Set ANDROID_SHA256_CERT_FINGERPRINTS on Render (python scripts/print_android_app_link_sha.py)")
    print("  2. python scripts/publish_gate.py --host", api_base)
    print("  3. Upload the AAB to Play Console (internal testing first)")


if __name__ == "__main__":
    main()
