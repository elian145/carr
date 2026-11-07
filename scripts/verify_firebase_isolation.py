#!/usr/bin/env python3
"""F-20: dev/stage Android Firebase configs must not point at the prod project.

Reads android/app/src/{dev,stage,prod}/google-services.json (repo config only,
no network, no secrets printed) and compares ``project_info.project_id``.

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


def project_id(root: str, flavor: str) -> str:
    path = os.path.join(root, "android", "app", "src", flavor, "google-services.json")
    with open(path, encoding="utf-8") as fh:
        return str(json.load(fh)["project_info"]["project_id"])


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
