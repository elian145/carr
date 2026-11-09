#!/usr/bin/env python3
"""F-20: dev/stage Firebase configs must not point at the prod project.

Reads android/app/src/{dev,stage,prod}/google-services.json and
ios/Runner/GoogleService-Info.plist (repo config only, no network, no secrets
printed) and checks, per flavor:

* ``project_info.project_id`` of a dev/stage file differs from the prod project
  (and, when expected IDs are configured, equals the expected ID);
* the file has a client for that flavor's applicationId;
* a dev/stage file does not carry the prod project number, the prod package, a
  prod app id or a prod API key (values are never printed).

Expected project IDs come from scripts/firebase_expected_projects.json and can be
overridden by CARNET_FIREBASE_{PROD,DEV,STAGE}_PROJECT_ID. A value that is empty
or starts with ``REPLACE_WITH_`` is "not configured".

Modes / exit codes
  default   shared dev/stage project -> ``::warning::`` only (owner must first create
            separate Firebase projects, docs/OWNER_ACTIONS.md F-20). A configured
            expected ID that does not match, unreadable/missing files or a missing
            flavor client are always errors. Exit 1 on any error.
  --strict  (or CARNET_FIREBASE_STRICT=1) shared-project violations also fail.
  --release --flavor <dev|stage|prod> [--platform android|ios|all]
            FAIL-CLOSED release verification of ONE flavor: the expected project ID
            for that flavor MUST be configured, the config MUST match it, dev/stage
            violations are errors, and the iOS plist (a single prod-project file with
            no dev/stage variant) is only valid for the prod flavor. There is no
            warn-only path.

Exit codes: 0 = ok, 1 = error / violation that is fatal in the chosen mode.
"""
from __future__ import annotations

import argparse
import json
import os
import plistlib
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
NON_PROD = ("dev", "stage")
ALL_FLAVORS = ("prod", *NON_PROD)
EXPECTED_FILE = os.path.join("scripts", "firebase_expected_projects.json")
ENV_OVERRIDE = {
    "prod": "CARNET_FIREBASE_PROD_PROJECT_ID",
    "dev": "CARNET_FIREBASE_DEV_PROJECT_ID",
    "stage": "CARNET_FIREBASE_STAGE_PROJECT_ID",
}
PLACEHOLDER_PREFIX = "REPLACE_WITH_"


# Android applicationId per flavor (android/app/build.gradle.kts; pinned by a test).
FLAVOR_APP_IDS = {
    "dev": "com.carzo.app.dev",
    "stage": "com.carzo.app.stage",
    "prod": "com.carnetiq.app",
}
# iOS has one target / one plist (ios/Runner.xcodeproj PRODUCT_BUNDLE_IDENTIFIER).
IOS_BUNDLE_ID = "com.carzo.app"


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


def _configured(value) -> str:
    """Return the stripped value, or '' when empty / an owner placeholder."""
    v = str(value or "").strip()
    return "" if (not v or v.startswith(PLACEHOLDER_PREFIX)) else v


def load_expected(root: str = ROOT, env=None) -> dict[str, str]:
    """Expected project ID per flavor ('' = not configured). Env beats the JSON file."""
    env = os.environ if env is None else env
    from_file: dict = {}
    try:
        with open(os.path.join(root, EXPECTED_FILE), encoding="utf-8") as fh:
            from_file = json.load(fh)
    except (OSError, ValueError):
        pass  # treated as "nothing configured": release mode then fails closed
    out: dict[str, str] = {}
    for flavor in ALL_FLAVORS:
        entry = from_file.get(flavor) if isinstance(from_file, dict) else None
        file_value = entry.get("project_id") if isinstance(entry, dict) else ""
        env_value = env.get(ENV_OVERRIDE[flavor])
        out[flavor] = _configured(env_value) if env_value is not None and env_value.strip() else _configured(file_value)
    return out


def _ios_plist(root: str) -> dict:
    with open(os.path.join(root, "ios", "Runner", "GoogleService-Info.plist"), "rb") as fh:
        return plistlib.load(fh)


def check(
    root: str = ROOT,
    expected: dict[str, str] | None = None,
    *,
    release: bool = False,
    flavors: tuple[str, ...] = ALL_FLAVORS,
    platforms: tuple[str, ...] = ("android",),
) -> tuple[list[str], list[str]]:
    """Return (errors, violations).

    errors are always fatal; violations (dev/stage sharing prod identifiers) are fatal
    in strict and release mode. ``expected`` maps flavor -> configured project ID
    ('' = not configured); None means "no pinning" (legacy lint behaviour).
    """
    errors: list[str] = []
    violations: list[str] = []
    pin = expected or {}

    if release:
        for flavor in flavors:
            if not pin.get(flavor):
                errors.append(
                    f"release verification of the {flavor} flavor requires an expected Firebase project ID "
                    f"({ENV_OVERRIDE[flavor]} or {EXPECTED_FILE}); none is configured (fail-closed)"
                )

    if "android" in platforms:
        _check_android(root, pin, flavors, errors, violations)
    if "ios" in platforms:
        _check_ios(root, pin, flavors, release, errors)
    return errors, violations


def _check_android(root, pin, flavors, errors, violations) -> None:
    try:
        prod = project_id(root, "prod")
    except (OSError, KeyError, ValueError) as exc:
        errors.append(f"prod google-services.json unreadable: {type(exc).__name__}")
        return
    configs: dict[str, dict] = {}
    for flavor in ALL_FLAVORS:
        if flavor not in flavors and flavor != "prod":
            continue
        try:
            configs[flavor] = _load(root, flavor)
        except (OSError, ValueError) as exc:
            if flavor in flavors:
                errors.append(f"{flavor} google-services.json unreadable: {type(exc).__name__}")
            continue
        if flavor not in flavors:
            continue
        want = FLAVOR_APP_IDS[flavor]
        if want not in {_package(c) for c in _clients(configs[flavor])}:
            errors.append(f"{flavor} google-services.json has no client for package '{want}'")
        try:
            pid = str(configs[flavor]["project_info"]["project_id"])
        except (KeyError, TypeError):
            errors.append(f"{flavor} google-services.json has no project_info.project_id")
            continue
        if pin.get(flavor) and pid != pin[flavor]:
            errors.append(
                f"{flavor} google-services.json project '{pid}' != expected '{pin[flavor]}'"
            )
        # A project can never be both prod and non-prod: pinned dev/stage IDs must not equal prod's.
        if flavor in NON_PROD and pid == prod:
            violations.append(f"{flavor} flavor uses the production Firebase project '{pid}'")
        if flavor == "prod":
            for other in NON_PROD:
                if pin.get(other) and pin.get(other) == pid:
                    errors.append(f"prod google-services.json uses the {other} Firebase project '{pid}'")
    prod_cfg = configs.get("prod")
    if prod_cfg is None:
        return
    prod_number = str(prod_cfg.get("project_info", {}).get("project_number", ""))
    prod_app_ids = {_app_id(c) for c in _clients(prod_cfg)} - {""}
    prod_keys = _api_keys(prod_cfg)
    for flavor in NON_PROD:
        cfg = configs.get(flavor)
        if flavor not in flavors or cfg is None:
            continue
        if str(cfg.get("project_info", {}).get("project_id", "")) == prod:
            continue  # already reported as sharing the prod project
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


def _check_ios(root, pin, flavors, release, errors) -> None:
    try:
        plist = _ios_plist(root)
    except (OSError, ValueError, plistlib.InvalidFileException) as exc:
        if release:
            errors.append(f"iOS GoogleService-Info.plist unreadable: {type(exc).__name__}")
        return
    non_prod = [f for f in flavors if f in NON_PROD]
    if non_prod and release:
        errors.append(
            "iOS has a single (production-project) GoogleService-Info.plist and no dev/stage variant: "
            f"a {'/'.join(non_prod)} iOS release build would use production Firebase"
        )
    bundle = str(plist.get("BUNDLE_ID", ""))
    if bundle != IOS_BUNDLE_ID:
        errors.append(f"iOS GoogleService-Info.plist BUNDLE_ID '{bundle}' != '{IOS_BUNDLE_ID}'")
    pid = str(plist.get("PROJECT_ID", ""))
    if "prod" in flavors and pin.get("prod") and pid != pin["prod"]:
        errors.append(f"iOS GoogleService-Info.plist project '{pid}' != expected prod '{pin['prod']}'")
    for other in NON_PROD:
        if pin.get(other) and pin[other] == pid:
            errors.append(f"iOS GoogleService-Info.plist uses the {other} Firebase project '{pid}'")


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--strict", action="store_true", help="fail on shared project")
    ap.add_argument("--release", action="store_true", help="fail-closed release verification (needs --flavor)")
    ap.add_argument("--flavor", choices=ALL_FLAVORS, help="flavor being built/released (required with --release)")
    ap.add_argument("--platform", choices=("android", "ios", "all"), default=None)
    ap.add_argument("--root", default=ROOT)
    args = ap.parse_args(argv)
    if args.release and not args.flavor:
        ap.error("--release requires --flavor")
    strict = args.strict or args.release or os.environ.get("CARNET_FIREBASE_STRICT", "").strip() in ("1", "true", "yes")
    flavors = (args.flavor,) if args.flavor else ALL_FLAVORS
    # Lint (no --platform) checks Android always and the iOS plist when it exists; release
    # verification only checks what the build ships.
    platform = args.platform or ("all" if args.release else "android")
    platforms = ("android", "ios") if platform == "all" else (platform,)
    expected = load_expected(args.root)
    errors, violations = check(
        args.root, expected, release=args.release, flavors=flavors, platforms=platforms
    )
    if not args.release:
        for flavor in flavors:
            if not expected.get(flavor):
                print(
                    f"::warning::F-20 no expected Firebase project ID configured for '{flavor}' "
                    f"({ENV_OVERRIDE[flavor]} / {EXPECTED_FILE}); mismatch cannot be detected"
                )
    for e in errors:
        print(f"ERROR: {e}")
    for v in violations:
        if strict:
            print(f"ERROR: F-20 {v}")
        else:
            print(f"::warning::F-20 {v} (create separate dev/stage projects)")
    if errors or (violations and strict):
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
