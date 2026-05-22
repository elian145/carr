#!/usr/bin/env python3
"""
Static publish preflight (no network). Fails with exit code 1 when required
store/release files are missing or misconfigured.

Run from repo root:
  python scripts/verify_publish_ready.py
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def _fail(msg: str) -> None:
    print(f"FAIL: {msg}", file=sys.stderr)
    raise SystemExit(1)


def _ok(msg: str) -> None:
    print(f"OK: {msg}")


def _check_file(path: Path, label: str) -> None:
    if not path.is_file():
        _fail(f"{label} missing: {path.relative_to(ROOT)}")
    _ok(label)


def _check_prod_firebase() -> None:
    path = ROOT / "android/app/src/prod/google-services.json"
    _check_file(path, "Android prod google-services.json")
    data = json.loads(path.read_text(encoding="utf-8"))
    clients = data.get("client") or []
    packages = [
        (c.get("client_info") or {}).get("android_client_info", {}).get("package_name")
        for c in clients
    ]
    if "com.carzo.app" not in packages:
        _fail(f"google-services.json must include package_name com.carzo.app, got {packages!r}")
    _ok("prod Firebase package_name com.carzo.app")


def _check_ios_firebase() -> None:
    path = ROOT / "ios/Runner/GoogleService-Info.plist"
    _check_file(path, "iOS GoogleService-Info.plist")
    text = path.read_text(encoding="utf-8", errors="replace")
    if "com.carzo.app" not in text:
        _fail("GoogleService-Info.plist should reference bundle id com.carzo.app")
    _ok("iOS Firebase plist references com.carzo.app")


def _check_app_icon() -> None:
    _check_file(ROOT / "assets/icon/app_icon.png", "Launcher icon source")


def _check_license() -> None:
    _check_file(ROOT / "LICENSE", "LICENSE")


def _check_no_example_app_id() -> None:
    bad = []
    for rel in (
        "android/app/build.gradle.kts",
        "pubspec.yaml",
    ):
        p = ROOT / rel
        if p.is_file() and "com.example" in p.read_text(encoding="utf-8", errors="replace"):
            bad.append(rel)
    if bad:
        _fail(f"com.example identifier still present in: {', '.join(bad)}")
    _ok("no com.example in core Android/pubspec files")


def main() -> None:
    print(f"Publish preflight ({ROOT.name})")
    _check_license()
    _check_app_icon()
    _check_prod_firebase()
    _check_ios_firebase()
    _check_no_example_app_id()
    print("All static publish checks passed.")


if __name__ == "__main__":
    main()
