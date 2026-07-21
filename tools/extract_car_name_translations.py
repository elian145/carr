"""One-time / regen helper: rebuild locale JSON from an old monolithic Dart file.

Prefer editing assets/i18n/car_names_{ar,ku}.json directly; those are the
source of truth after M-08.
"""
from __future__ import annotations

import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DART = ROOT / "lib" / "data" / "car_name_translations.dart"
OUT_DIR = ROOT / "assets" / "i18n"


def extract_map(text: str, name: str) -> dict[str, str]:
    m = re.search(
        rf"static const Map<String, String> {name} = \{{(.*?)\n  \}};",
        text,
        re.S,
    )
    if not m:
        raise SystemExit(f"missing map {name} (file may already be the thin loader)")
    body = m.group(1)
    entries = re.findall(r"'((?:\\'|[^'])*)'\s*:\s*'((?:\\'|[^'])*)'", body)
    out: dict[str, str] = {}
    for key, value in entries:
        key = key.replace("\\'", "'")
        value = value.replace("\\'", "'")
        out[key] = value
    return out


def main() -> None:
    text = DART.read_text(encoding="utf-8")
    packs = {
        "ar": {
            "brands": extract_map(text, "_brandAr"),
            "models": extract_map(text, "_modelAr"),
            "trims": extract_map(text, "_trimAr"),
        },
        "ku": {
            "brands": extract_map(text, "_brandKu"),
            "models": extract_map(text, "_modelKu"),
            "trims": extract_map(text, "_trimKu"),
        },
    }
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    for locale, pack in packs.items():
        path = OUT_DIR / f"car_names_{locale}.json"
        path.write_text(
            json.dumps(pack, ensure_ascii=False, separators=(",", ":")),
            encoding="utf-8",
        )
        print(
            f"{path.name}: brands={len(pack['brands'])} "
            f"models={len(pack['models'])} trims={len(pack['trims'])} "
            f"bytes={path.stat().st_size}"
        )


if __name__ == "__main__":
    main()
