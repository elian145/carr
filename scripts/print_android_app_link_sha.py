#!/usr/bin/env python3
"""
Print SHA-256 certificate fingerprint(s) for Render env ANDROID_SHA256_CERT_FINGERPRINTS.

Reads signing.properties from the repo root (or android/signing.properties), runs
keytool, and prints a comma-separated value ready to paste into Render.

Usage (from repo root):
  python scripts/print_android_app_link_sha.py
  python scripts/print_android_app_link_sha.py --verify-host https://carr-5hrm.onrender.com

If signing.properties is missing, prints manual steps and exits 1.
"""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
import urllib.error
import urllib.request
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from android_jdk_tools import (
    find_jdk_tool,
    load_signing_properties,
    resolve_keystore,
)

DEFAULT_HOST = "https://carr-5hrm.onrender.com"


def _local_fingerprints() -> list[str]:
    loaded = load_signing_properties()
    if loaded[0] is None:
        print(
            "No signing.properties found. Copy android/signing.properties.example.",
            file=sys.stderr,
        )
        print("\nUpload keystore fingerprint:", file=sys.stderr)
        print(
            "  keytool -list -v -keystore release-keystore.jks -alias upload",
            file=sys.stderr,
        )
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

    return [fp.strip().upper() for fp in fingerprints]


def _remote_fingerprints(host: str, timeout: float = 90.0) -> list[str]:
    url = f"{host.rstrip('/')}/.well-known/assetlinks.json"
    req = urllib.request.Request(
        url,
        headers={"Accept": "application/json", "User-Agent": "CarNet-app-links/1.0"},
    )
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            body = resp.read()
            code = resp.status
    except urllib.error.HTTPError as e:
        print(f"FAIL: {url} returned {e.code}", file=sys.stderr)
        raise SystemExit(1) from e
    except Exception as e:
        print(f"FAIL: could not fetch {url}: {e}", file=sys.stderr)
        raise SystemExit(1) from e

    if code != 200:
        print(f"FAIL: {url} returned {code}", file=sys.stderr)
        raise SystemExit(1)

    try:
        data = json.loads(body.decode("utf-8"))
    except json.JSONDecodeError as e:
        print(f"FAIL: assetlinks.json is not valid JSON: {e}", file=sys.stderr)
        raise SystemExit(1) from e

    if not isinstance(data, list) or not data:
        print("FAIL: assetlinks.json empty or invalid", file=sys.stderr)
        raise SystemExit(1)

    target = (data[0].get("target") or {}) if isinstance(data[0], dict) else {}
    pkg = target.get("package_name")
    if pkg != "com.carzo.app":
        print(f"FAIL: package_name={pkg!r}, expected com.carzo.app", file=sys.stderr)
        raise SystemExit(1)

    fps = target.get("sha256_cert_fingerprints") or []
    if not isinstance(fps, list) or not fps:
        print("FAIL: sha256_cert_fingerprints missing", file=sys.stderr)
        raise SystemExit(1)

    return [str(fp).strip().upper() for fp in fps]


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Print or verify Android App Links SHA-256 fingerprints"
    )
    parser.add_argument(
        "--verify-host",
        nargs="?",
        const=DEFAULT_HOST,
        default=None,
        help=(
            "Fetch deployed assetlinks.json and confirm the local upload "
            f"keystore SHA is included (default host: {DEFAULT_HOST})"
        ),
    )
    args = parser.parse_args()

    local = _local_fingerprints()
    value = ",".join(local)

    print("\nPaste into Render -> Environment:")
    print(f"ANDROID_SHA256_CERT_FINGERPRINTS={value}")
    print("\nAfter Play App Signing is enabled, append the Play Console")
    print("'App signing key certificate' SHA-256 (comma-separated), then redeploy.")

    if args.verify_host is None:
        print("\nVerify production:")
        print(
            "  python scripts/print_android_app_link_sha.py "
            f"--verify-host {DEFAULT_HOST}"
        )
        print(
            "  python scripts/verify_production_host.py "
            f"--host {DEFAULT_HOST} --require-app-links"
        )
        return

    host = args.verify_host.strip() or DEFAULT_HOST
    print(f"\nChecking {host}/.well-known/assetlinks.json …")
    remote = _remote_fingerprints(host)
    missing = [fp for fp in local if fp not in remote]
    if missing:
        print(
            "FAIL: local upload keystore SHA(s) not present on the host:",
            file=sys.stderr,
        )
        for fp in missing:
            print(f"  {fp}", file=sys.stderr)
        print(
            "\nSet ANDROID_SHA256_CERT_FINGERPRINTS on Render (include the value "
            "printed above), redeploy, then re-run --verify-host.",
            file=sys.stderr,
        )
        raise SystemExit(1)

    print(f"OK: local upload keystore SHA is present ({len(remote)} fingerprint(s) on host)")
    extra = [fp for fp in remote if fp not in local]
    if extra:
        print(
            f"Note: host also has {len(extra)} additional fingerprint(s) "
            "(e.g. Play App Signing) — that is expected."
        )


if __name__ == "__main__":
    main()
