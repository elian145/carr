#!/usr/bin/env python3
"""Export embedded CarCatalog to assets/car_catalog.json.

Preferred (full brands + models + trims):
  flutter pub run bin/export_car_catalog.dart

This script delegates to the Dart exporter when `dart` is on PATH.
"""
from __future__ import annotations

import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def main() -> None:
    flutter = shutil.which("flutter")
    if flutter is None:
        print(
            "flutter not found on PATH; run: flutter pub run bin/export_car_catalog.dart",
            file=sys.stderr,
        )
        raise SystemExit(1)
    subprocess.run(
        [flutter, "pub", "run", "bin/export_car_catalog.dart"],
        cwd=ROOT,
        check=True,
    )


if __name__ == "__main__":
    main()
