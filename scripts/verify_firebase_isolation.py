#!/usr/bin/env python3
"""F-20: dev/stage Android Firebase configs must not point at the prod project.

Reads android/app/src/{dev,stage,prod}/google-services.json (repo config only,
no network, no secrets printed) and compares ``project_info.project_id``. It also
errors if a flavor's file lacks a client for that flavor's applicationId, and flags
(violation) a dev/stage file that carries the prod project number, the prod package,
a prod app id or a prod API key (values are never printed). iOS has a single
GoogleService-Info.plist and no flavors, so it is not covered (owner decision).

Exit codes: 0 = isolated; 1 = a non-prod flavor shares the prod project AND
``--strict`` was given; otherwise a violation only prints a ``::warning::``
(GitHub annotation) and exits 0, because the owner must first create separate
Firebase projects (docs/OWNER_ACTIONS.md, F-20). Missing files always fail.
"""
from __future__ import annotations

import argparse
import json
import os
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
NON_PROD = ("dev", "stage")


# Android applicationId per flavor (android/app/build.gradle.kts; pinned by a test).
FLAVOR_APP_IDS = {
    "dev": "com.carzo.app.dev",
    "stage": "com.carzo.app.stage",
    "prod": "com.carnetiq.app",
}


def _load(root: str, flavor: str) -> dict:
    path = os.path.join(root, "android", "app", "src", flavor, "google-services.json")
    with open(path, encoding="utf-8") as fh:
        return json.load(fh)


def project_id(root: str, flavor: str) -> str:
    return str(_load(root, flavor)["project_info"]["project_id"])


def _clients(cfg: dict) -> list[dict]:
    return [c for c in cfg.get("client", []) if isinstance(c, dict)]


def _package(client: dict) -> str:
    return str(client.get("client_info", {}).get("android_client_info", {}).get("package_name", ""))


def _app_id(client: dict) -> str:
    return str(client.get("client_info", {}).get("mobilesdk_app_id", ""))


def _api_keys(cfg: dict) -> set[str]:
    return {
        str(k["current_key"])
        for c in _clients(cfg)
        for k in c.get("api_key", [])
        if isinstance(k, dict) and k.get("current_key")
    }


def check(root: str = ROOT) -> tuple[list[str], list[str]]:
    """Return (errors, violations)."""
    errors: list[str] = []
    violations: list[str] = []
    try:
        prod = project_id(root, "prod")
    except (OSError, KeyError, ValueError) as exc:
        return [f"prod google-services.json unreadable: {type(exc).__name__}"], []
    for flavor in NON_PROD:
        try:
            pid = project_id(root, flavor)
        except (OSError, KeyError, ValueError) as exc:
            errors.append(f"{flavor} google-services.json unreadable: {type(exc).__name__}")
            continue
        if pid == prod:
            violations.append(
                f"{flavor} flavor uses the production Firebase project '{pid}'"
            )
    # Flavor consistency + deeper isolation (never prints key values).
    configs: dict[str, dict] = {}
    for flavor in ("prod", *NON_PROD):
        try:
            configs[flavor] = _load(root, flavor)
        except (OSError, ValueError):
            continue  # already reported above
        want = FLAVOR_APP_IDS[flavor]
        if want not in {_package(c) for c in _clients(configs[flavor])}:
            errors.append(f"{flavor} google-services.json has no client for package '{want}'")
    prod_cfg = configs.get("prod")
    if prod_cfg is not None:
        prod_number = str(prod_cfg.get("project_info", {}).get("project_number", ""))
        prod_app_ids = {_app_id(c) for c in _clients(prod_cfg)} - {""}
        prod_keys = _api_keys(prod_cfg)
        for flavor in NON_PROD:
            cfg = configs.get(flavor)
            if cfg is None or str(cfg.get("project_info", {}).get("project_id", "")) == prod:
                continue  # unreadable, or already reported as sharing the prod project
            info = cfg.get("project_info", {})
            if prod_number and str(info.get("project_number", "")) == prod_number:
                violations.append(f"{flavor} flavor has the production Firebase project number")
            if FLAVOR_APP_IDS["prod"] in {_package(c) for c in _clients(cfg)}:
                violations.append(
                    f"{flavor} config contains the production package '{FLAVOR_APP_IDS['prod']}'"
                )
            if prod_app_ids & {_app_id(c) for c in _clients(cfg)}:
                violations.append(f"{flavor} config reuses a production Firebase app id")
            if prod_keys & _api_keys(cfg):
                violations.append(f"{flavor} config reuses a production Firebase API key")
    return errors, violations


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--strict", action="store_true", help="fail on shared project")
    ap.add_argument("--root", default=ROOT)
    args = ap.parse_args(argv)
    errors, violations = check(args.root)
    for e in errors:
        print(f"ERROR: {e}")
    for v in violations:
        print(f"::warning::F-20 {v} (create separate dev/stage projects)")
    if errors or (violations and args.strict):
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
