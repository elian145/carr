#!/usr/bin/env python3
"""
Print SHA-256 certificate fingerprint(s) for Render env ANDROID_SHA256_CERT_FINGERPRINTS.

Reads signing.properties from the repo root (or android/signing.properties), runs
keytool, and prints a comma-separated value ready to paste into Render.

Usage (from repo root):
  python scripts/print_android_app_link_sha.py

If signing.properties is missing, prints manual steps and exits 1.
"""

from __future__ import annotations

import glob
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]


def _find_keytool() -> str | None:
    found = shutil.which("keytool")
    if found:
        return found

    java_home = os.environ.get("JAVA_HOME", "").strip()
    if java_home:
        for name in ("keytool.exe", "keytool"):
            candidate = Path(java_home) / "bin" / name
            if candidate.is_file():
                return str(candidate)

    program_files = os.environ.get("ProgramFiles", r"C:\Program Files")
    local_app_data = os.environ.get("LOCALAPPDATA", "")
    candidates: list[Path] = []
    for android_root in (
        Path(program_files) / "Android",
        Path(local_app_data) / "Programs" / "Android",
    ):
        if android_root.is_dir():
            candidates.extend(android_root.glob("Android Studio*/jbr/bin/keytool.exe"))

    candidates.extend(
        Path(p) for p in glob.glob(str(Path(program_files) / "Java" / "*" / "bin" / "keytool.exe"))
    )

    for candidate in candidates:
        if candidate.is_file():
            return str(candidate)
    return None


def _load_signing_props() -> tuple[dict[str, str], Path] | tuple[None, None]:
    for rel in ("signing.properties", "android/signing.properties"):
        path = REPO_ROOT / rel
        if not path.is_file():
            continue
        props: dict[str, str] = {}
        for line in path.read_text(encoding="utf-8", errors="replace").splitlines():
            line = line.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            key, value = line.split("=", 1)
            props[key.strip()] = value.strip()
        return props, path
    return None, None


def _resolve_keystore(store_file: str) -> Path | None:
    p = Path(store_file)
    if p.is_file():
        return p
    candidate = REPO_ROOT / store_file
    if candidate.is_file():
        return candidate
    return None


def main() -> None:
    loaded = _load_signing_props()
    if loaded[0] is None:
        print("No signing.properties found. Copy signing.properties.example to signing.properties.", file=sys.stderr)
        print("\nUpload keystore fingerprint:", file=sys.stderr)
        print("  keytool -list -v -keystore release-keystore.jks -alias upload", file=sys.stderr)
        print("\nOr use Play Console → Release → Setup → App signing → App signing key certificate", file=sys.stderr)
        raise SystemExit(1)

    props, props_path = loaded
    store_file = props.get("STORE_FILE", "").strip()
    alias = props.get("KEY_ALIAS", "upload").strip() or "upload"
    if not store_file:
        print(f"STORE_FILE is empty in {props_path}", file=sys.stderr)
        raise SystemExit(1)

    keystore = _resolve_keystore(store_file)
    if keystore is None:
        print(f"Keystore not found: {store_file}", file=sys.stderr)
        raise SystemExit(1)

    print(f"Using keystore: {keystore} (alias={alias})")
    keytool = _find_keytool()
    if keytool is None:
        print(
            "keytool not found. Install JDK or Android Studio, or add JAVA_HOME/bin to PATH.",
            file=sys.stderr,
        )
        print(
            "\nManual: keytool -list -v -keystore release-keystore.jks -alias upload",
            file=sys.stderr,
        )
        raise SystemExit(1)

    cmd = [keytool, "-list", "-v", "-keystore", str(keystore), "-alias", alias]
    store_pass = props.get("STORE_PASSWORD", "").strip()
    key_pass = props.get("KEY_PASSWORD", "").strip()
    if store_pass:
        cmd.extend(["-storepass", store_pass])
    if key_pass:
        cmd.extend(["-keypass", key_pass])

    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0:
        print(result.stderr or result.stdout, file=sys.stderr)
        raise SystemExit(result.returncode)

    fingerprints = re.findall(r"SHA256:\s*([0-9A-Fa-f:]+)", result.stdout)
    if not fingerprints:
        print(result.stdout)
        print("No SHA256 line found in keytool output.", file=sys.stderr)
        raise SystemExit(1)

    # Render expects comma-separated SHA-256 strings (colon-separated hex).
    normalized = [fp.strip().upper() for fp in fingerprints]
    value = ",".join(normalized)

    print("\nPaste into Render -> Environment:")
    print(f"ANDROID_SHA256_CERT_FINGERPRINTS={value}")
    print("\nRedeploy the web service, then verify:")
    print("  python scripts/verify_production_host.py --host https://YOUR_HOST --require-app-links")


if __name__ == "__main__":
    main()
