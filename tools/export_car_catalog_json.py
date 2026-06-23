#!/usr/bin/env python3
"""Export embedded CarCatalog to assets/car_catalog.json for lazy loading.

Run from repo root after updating catalog:
  python tools/export_car_catalog_json.py

Then add to pubspec.yaml assets:
  - assets/car_catalog.json
"""
from __future__ import annotations

import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DART = ROOT / "lib" / "data" / "car_catalog.dart"
OUT = ROOT / "assets" / "car_catalog.json"


def main() -> None:
    text = DART.read_text(encoding="utf-8")
    brands_match = re.search(
        r"static final List<String> brands = \[(.*?)\];",
        text,
        re.DOTALL,
    )
    if not brands_match:
        print("Could not parse brands from car_catalog.dart", file=sys.stderr)
        raise SystemExit(1)
    brands = [
        m.group(1) or m.group(2)
        for m in re.finditer(r"'((?:\\'|[^'])*)'", brands_match.group(1))
    ]
    payload = {
        "brands": brands,
        "models": {},
        "trimsByBrandModel": {},
        "_note": "Regenerate models/trims via tools/extract_car_catalog.py when migrating fully",
    }
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(json.dumps(payload, indent=2), encoding="utf-8")
    print(f"Wrote {OUT.relative_to(ROOT)} ({len(brands)} brands)")


if __name__ == "__main__":
    main()
