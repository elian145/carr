#!/usr/bin/env python3
"""
HTTP preflight against a deployed CarNet API host (default: Render production).

Critical checks (exit 1 on failure):
  - GET /health
  - GET /api/cars
  - GET /api/config/trust
  - GET /terms and GET /privacy

Store deep-link checks (exit 1 only with --require-app-links):
  - GET /.well-known/assetlinks.json
  - GET /.well-known/apple-app-site-association

Run:
  python scripts/verify_production_host.py
  python scripts/verify_production_host.py --host https://carr-5hrm.onrender.com
  python scripts/verify_production_host.py --require-app-links
"""

from __future__ import annotations

import argparse
import json
import re
import sys
import urllib.error
import urllib.request
from typing import Any

DEFAULT_HOST = "https://carr-5hrm.onrender.com"


def _fetch(url: str, timeout: float) -> tuple[int, bytes, dict[str, str]]:
    req = urllib.request.Request(
        url,
        headers={"Accept": "application/json, text/html, */*", "User-Agent": "CarNet-verify/1.0"},
    )
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            return resp.status, resp.read(), dict(resp.headers)
    except urllib.error.HTTPError as e:
        return e.code, e.read(), dict(e.headers)


def _json(body: bytes) -> Any:
    if not body:
        return None
    return json.loads(body.decode("utf-8", errors="replace"))


def _check_critical(host: str, timeout: float, require_production_ready: bool = False) -> list[str]:
    errors: list[str] = []
    base = host.rstrip("/")

    code, body, _ = _fetch(f"{base}/health", timeout)
    if code != 200:
        errors.append(f"/health returned {code}")
    else:
        data = _json(body)
        if not (isinstance(data, dict) and data.get("status") == "ok"):
            errors.append("/health JSON missing status=ok")
        elif require_production_ready and isinstance(data, dict):
            if not data.get("redis_configured"):
                errors.append("/health redis_configured=false (set REDIS_URL on Render)")
            else:
                print("OK: redis_configured=true")
            upload = data.get("upload_persistence")
            if upload not in ("r2", "disk"):
                errors.append(
                    f"/health upload_persistence={upload!r} "
                    "(set R2_* including R2_PUBLIC_URL, or absolute UPLOAD_FOLDER)"
                )
            else:
                print(f"OK: upload_persistence={upload}")
            if data.get("app_links_android") is True:
                print("OK: /health app_links_android=true")
            if data.get("app_links_ios") is True:
                print("OK: /health app_links_ios=true")

    code, body, _ = _fetch(f"{base}/api/cars", timeout)
    if code != 200:
        errors.append(f"/api/cars returned {code}")
    else:
        data = _json(body)
        if not isinstance(data, dict) or "cars" not in data:
            errors.append("/api/cars JSON missing cars array")

    code, body, _ = _fetch(f"{base}/api/config/trust", timeout)
    if code != 200:
        errors.append(f"/api/config/trust returned {code}")
    else:
        data = _json(body)
        if not isinstance(data, dict):
            errors.append("/api/config/trust invalid JSON")
        elif not (data.get("support_email") or "").strip():
            errors.append("/api/config/trust missing support_email")

    for path in ("/terms", "/privacy"):
        code, body, headers = _fetch(f"{base}{path}", timeout)
        if code != 200:
            errors.append(f"{path} returned {code}")
            continue
        ctype = (headers.get("Content-Type") or "").lower()
        if "html" not in ctype and b"<html" not in body.lower():
            errors.append(f"{path} did not look like HTML")

    return errors


def _note(required: bool, errors: list[str], msg: str, ok: str | None = None) -> None:
    if required:
        errors.append(msg)
    else:
        print(f"WARN: {msg}")
    if ok and not required:
        print(ok)


def _check_app_links(host: str, timeout: float, required: bool) -> list[str]:
    errors: list[str] = []
    base = host.rstrip("/")
    sha256_re = re.compile(r"^[0-9A-F]{2}(:[0-9A-F]{2}){31}$")

    code, body, _ = _fetch(f"{base}/.well-known/assetlinks.json", timeout)
    if code != 200:
        _note(
            required,
            errors,
            f"assetlinks.json returned {code} (set ANDROID_SHA256_CERT_FINGERPRINTS on Render)",
        )
    else:
        data = _json(body)
        if not isinstance(data, list) or not data:
            _note(required, errors, "assetlinks.json empty")
        else:
            target = (data[0].get("target") or {}) if isinstance(data[0], dict) else {}
            pkg = target.get("package_name")
            fps = target.get("sha256_cert_fingerprints") or []
            if pkg != "com.carzo.app":
                _note(
                    required,
                    errors,
                    f"assetlinks package_name={pkg!r}, expected com.carzo.app",
                )
            elif not isinstance(fps, list) or not fps:
                _note(required, errors, "assetlinks.json missing sha256_cert_fingerprints")
            else:
                bad = [
                    fp
                    for fp in fps
                    if not isinstance(fp, str) or not sha256_re.match(fp.strip().upper())
                ]
                if bad:
                    _note(
                        required,
                        errors,
                        f"assetlinks.json has invalid SHA-256 fingerprint(s): {bad[:2]!r}",
                    )
                else:
                    print(f"OK: assetlinks.json ({len(fps)} fingerprint(s))")

    code, body, _ = _fetch(f"{base}/.well-known/apple-app-site-association", timeout)
    if code != 200:
        _note(
            required,
            errors,
            f"apple-app-site-association returned {code} (set APPLE_TEAM_ID on Render)",
        )
    else:
        data = _json(body)
        details = (
            ((data or {}).get("applinks") or {}).get("details") or []
            if isinstance(data, dict)
            else []
        )
        if not details:
            _note(required, errors, "AASA missing applinks.details")
        else:
            app_id = (details[0] or {}).get("appID", "")
            if not str(app_id).endswith(".com.carzo.app"):
                _note(required, errors, f"AASA appID={app_id!r}")
            else:
                print(f"OK: AASA appID={app_id}")

    return errors


def _check_push_health(host: str, timeout: float, required: bool) -> list[str]:
    errors: list[str] = []
    base = host.rstrip("/")
    code, body, _ = _fetch(f"{base}/health/push", timeout)
    if code != 200:
        _note(required, errors, f"/health/push returned {code}")
        return errors
    data = _json(body)
    if not isinstance(data, dict):
        _note(required, errors, "/health/push invalid JSON")
        return errors
    if data.get("credentials_oauth_ok") is True:
        print("OK: FCM credentials (/health/push)")
    elif data.get("credentials_present") is True:
        _note(required, errors, "FCM credentials present but OAuth check failed")
    else:
        _note(
            required,
            errors,
            "FCM not configured (set FIREBASE_SERVICE_ACCOUNT_BASE64 on Render)",
        )
    return errors


def main() -> None:
    p = argparse.ArgumentParser(description="Verify deployed CarNet API host")
    p.add_argument("--host", default=DEFAULT_HOST, help="API origin (no /api suffix)")
    p.add_argument(
        "--timeout",
        type=float,
        default=90.0,
        help="Per-request timeout seconds (Render cold start)",
    )
    p.add_argument(
        "--require-app-links",
        action="store_true",
        help="Fail if Android/iOS well-known files are not configured",
    )
    p.add_argument(
        "--require-push",
        action="store_true",
        help="Fail if FCM push credentials are not configured",
    )
    p.add_argument(
        "--require-production-ready",
        action="store_true",
        help="Fail if Redis or upload persistence are not configured on /health",
    )
    p.add_argument(
        "--require-upload-persistence",
        action="store_true",
        help="Fail if /health upload_persistence is not r2 or disk (ignores Redis)",
    )
    args = p.parse_args()
    host = args.host.strip().rstrip("/")
    if not host.startswith("https://"):
        print("FAIL: --host must use https://", file=sys.stderr)
        raise SystemExit(1)

    print(f"Checking {host} (timeout={args.timeout}s)")

    errors = _check_critical(
        host, args.timeout, require_production_ready=args.require_production_ready
    )
    if args.require_upload_persistence and not args.require_production_ready:
        # Dedicated upload check without requiring Redis.
        code, body, _ = _fetch(f"{host.rstrip('/')}/health", args.timeout)
        if code != 200:
            errors.append(f"/health returned {code}")
        else:
            data = _json(body)
            upload = (data or {}).get("upload_persistence") if isinstance(data, dict) else None
            if upload not in ("r2", "disk"):
                errors.append(
                    f"/health upload_persistence={upload!r} "
                    "(set R2_* including R2_PUBLIC_URL, or absolute UPLOAD_FOLDER)"
                )
            else:
                print(f"OK: upload_persistence={upload}")
    for e in errors:
        print(f"FAIL: {e}", file=sys.stderr)

    link_errors = _check_app_links(host, args.timeout, args.require_app_links)
    for e in link_errors:
        print(f"FAIL: {e}", file=sys.stderr)

    push_errors = _check_push_health(host, args.timeout, required=args.require_push)
    for e in push_errors:
        print(f"FAIL: {e}", file=sys.stderr)

    if errors or link_errors or push_errors:
        raise SystemExit(1)

    print("All requested production checks passed.")


if __name__ == "__main__":
    main()
