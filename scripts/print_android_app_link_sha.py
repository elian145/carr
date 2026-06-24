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

import re
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from android_jdk_tools import (
    find_jdk_tool,
    load_signing_properties,
    resolve_keystore,
)


def main() -> None:
    loaded = load_signing_properties()
    if loaded[0] is None:
        print(
            "No signing.properties found. Copy android/signing.properties.example.",
            file=sys.stderr,
        )
        print("\nUpload keystore fingerprint:", file=sys.stderr)
        print("  keytool -list -v -keystore release-keystore.jks -alias upload", file=sys.stderr)
        print(
            "\nOr use Play Console -> Release -> Setup -> App signing key certificate",
            file=sys.stderr,
        )
        raise SystemExit(1)

    props, props_path = loaded
    store_file = props.get("STORE_FILE", "").strip()
    alias = props.get("KEY_ALIAS", "upload").strip() or "upload"
    if not store_file:
        print(f"STORE_FILE is empty in {props_path}", file=sys.stderr)
        raise SystemExit(1)

    keystore = resolve_keystore(store_file)
    if keystore is None:
        print(f"Keystore not found: {store_file}", file=sys.stderr)
        raise SystemExit(1)

    print(f"Using keystore: {keystore} (alias={alias})")
    keytool = find_jdk_tool("keytool")
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

    normalized = [fp.strip().upper() for fp in fingerprints]
    value = ",".join(normalized)

    print("\nPaste into Render -> Environment:")
    print(f"ANDROID_SHA256_CERT_FINGERPRINTS={value}")
    print("\nRedeploy the web service, then verify:")
    print("  python scripts/verify_production_host.py --host https://YOUR_HOST --require-app-links")


if __name__ == "__main__":
    main()
