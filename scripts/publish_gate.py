#!/usr/bin/env python3
"""
Store-upload readiness gate: static assets, deployed API, and app-link well-known files.

Examples:
  python scripts/publish_gate.py
  python scripts/publish_gate.py --host https://carr-5hrm.onrender.com
  python scripts/publish_gate.py --with-flutter
  python scripts/publish_gate.py --skip-app-links   # before Render SHA env is set
  python scripts/publish_gate.py --skip-host        # local static + AAB only
"""

from __future__ import annotations

import argparse
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_HOST = "https://carr-5hrm.onrender.com"
AAB = ROOT / "build/app/outputs/bundle/prodRelease/app-prod-release.aab"


def _flutter() -> str:
    return shutil.which("flutter") or "flutter"


def _run(label: str, cmd: list[str]) -> None:
    print(f"\n== {label} ==")
    subprocess.check_call(cmd, cwd=ROOT)


def _note_aab() -> None:
    if AAB.is_file():
        size_mb = AAB.stat().st_size / (1024 * 1024)
        print(f"OK: prod AAB present ({AAB.relative_to(ROOT)}, {size_mb:.1f} MB)")
        try:
            subprocess.check_call(
                [sys.executable, "scripts/verify_aab_signing.py", str(AAB)],
                cwd=ROOT,
            )
        except subprocess.CalledProcessError:
            print("WARN: AAB signing verification failed (rebuild with build_prod_android.py)")
    else:
        print(
            "WARN: prod AAB not built yet; run: python scripts/build_prod_android.py",
        )


def _note_android_sha() -> None:
    if any((ROOT / rel).is_file() for rel in ("android/signing.properties", "signing.properties")):
        print(
            "TIP: Render env ANDROID_SHA256_CERT_FINGERPRINTS -> "
            "python scripts/print_android_app_link_sha.py",
        )


def main() -> None:
    p = argparse.ArgumentParser(description="Final gate before Play / App Store upload")
    p.add_argument("--host", default=DEFAULT_HOST, help="Deployed API origin")
    p.add_argument(
        "--skip-app-links",
        action="store_true",
        help="Do not require assetlinks.json / AASA (pre-Render SHA setup)",
    )
    p.add_argument(
        "--with-flutter",
        action="store_true",
        help="Also run flutter analyze and flutter test",
    )
    p.add_argument(
        "--skip-host",
        action="store_true",
        help="Skip deployed API checks (Render cold start / offline)",
    )
    p.add_argument("--timeout", type=float, default=90.0)
    args = p.parse_args()

    print(f"Publish gate ({ROOT.name})")
    _run("Static publish preflight", [sys.executable, "scripts/verify_publish_ready.py"])

    if not args.skip_host:
        host_cmd = [
            sys.executable,
            "scripts/verify_production_host.py",
            "--host",
            args.host.strip().rstrip("/"),
            "--timeout",
            str(args.timeout),
        ]
        if not args.skip_app_links:
            host_cmd.append("--require-app-links")
        _run(f"Deployed API ({args.host.strip()})", host_cmd)

    if args.with_flutter:
        _run("Flutter analyze", [_flutter(), "analyze", "--no-fatal-infos"])
        _run("Flutter test", [_flutter(), "test"])

    print("\n== Local artifacts ==")
    _note_aab()
    _note_android_sha()

    print("\nPublish gate passed.")


if __name__ == "__main__":
    main()
