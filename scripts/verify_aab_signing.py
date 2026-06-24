#!/usr/bin/env python3
"""
Verify a prod AAB/APK is signed with the upload keystore (not debug).

Compares SHA-256 from the artifact to signing.properties keystore fingerprints.

Usage:
  python scripts/verify_aab_signing.py
  python scripts/verify_aab_signing.py build/app/outputs/bundle/prodRelease/app-prod-release.aab
"""

from __future__ import annotations

import argparse
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from android_jdk_tools import (
    REPO_ROOT,
    find_jdk_tool,
    load_signing_properties,
    parse_sha256_lines,
    resolve_keystore,
)

DEFAULT_AAB = REPO_ROOT / "build/app/outputs/bundle/prodRelease/app-prod-release.aab"


def _fail(msg: str) -> None:
    print(f"FAIL: {msg}", file=sys.stderr)
    raise SystemExit(1)


def _keystore_sha256(keytool: str, props: dict[str, str]) -> list[str]:
    store_file = props.get("STORE_FILE", "").strip()
    alias = props.get("KEY_ALIAS", "upload").strip() or "upload"
    keystore = resolve_keystore(store_file)
    if keystore is None:
        _fail(f"keystore not found: {store_file}")

    cmd = [keytool, "-list", "-v", "-keystore", str(keystore), "-alias", alias]
    store_pass = props.get("STORE_PASSWORD", "").strip()
    key_pass = props.get("KEY_PASSWORD", "").strip()
    if store_pass:
        cmd.extend(["-storepass", store_pass])
    if key_pass:
        cmd.extend(["-keypass", key_pass])

    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0:
        _fail(result.stderr or result.stdout or "keytool failed")
    fps = parse_sha256_lines(result.stdout)
    if not fps:
        _fail("no SHA256 fingerprint in keystore keytool output")
    return fps


def _artifact_sha256(keytool: str, artifact: Path) -> tuple[list[str], str]:
    result = subprocess.run(
        [keytool, "-printcert", "-jarfile", str(artifact)],
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        _fail(result.stderr or result.stdout or "keytool -printcert failed")

    owner = ""
    for line in result.stdout.splitlines():
        if line.strip().startswith("Owner:"):
            owner = line.strip()
            break

    if "Android Debug" in owner:
        _fail("artifact is debug-signed (Owner contains Android Debug)")

    fps = parse_sha256_lines(result.stdout)
    if not fps:
        _fail("no SHA256 fingerprint in artifact certificate")
    return fps, owner


def main() -> None:
    p = argparse.ArgumentParser(description="Verify prod AAB/APK upload signing")
    p.add_argument(
        "artifact",
        nargs="?",
        default=str(DEFAULT_AAB),
        help="Path to .aab or .apk (default: prod release AAB)",
    )
    args = p.parse_args()

    artifact = Path(args.artifact)
    if not artifact.is_file():
        _fail(f"artifact missing: {artifact.relative_to(REPO_ROOT)}")

    loaded = load_signing_properties()
    if loaded[0] is None:
        _fail("signing.properties missing (android/ or repo root)")
    props, _ = loaded

    keytool = find_jdk_tool("keytool")
    if keytool is None:
        _fail("keytool not found (install JDK or Android Studio)")

    expected = _keystore_sha256(keytool, props)
    actual, owner = _artifact_sha256(keytool, artifact)

    if actual[0] not in expected:
        _fail(
            "artifact SHA256 does not match upload keystore\n"
            f"  artifact: {actual[0]}\n"
            f"  keystore: {', '.join(expected)}",
        )

    print(f"OK: {artifact.relative_to(REPO_ROOT)} signed with upload keystore")
    print(f"  {owner}")
    print(f"  SHA256: {actual[0]}")


if __name__ == "__main__":
    main()
