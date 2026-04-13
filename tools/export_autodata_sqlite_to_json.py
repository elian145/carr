#!/usr/bin/env python3
"""
Export c:\\Users\\VeeStore\\auto data scraper\\autodata.sqlite into
assets/car_spec_dataset.json (format expected by lib/services/car_spec_index.dart).

Usage (from repo root):
  python tools/export_autodata_sqlite_to_json.py
"""

from __future__ import annotations

import argparse
import json
import re
import sqlite3
from datetime import datetime
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
DEFAULT_SQLITE = Path(r"c:\Users\VeeStore\auto data scraper\autodata.sqlite")
OUT_JSON = REPO / "assets" / "car_spec_dataset.json"

YEAR_RE = re.compile(r"\b(19|20)\d{2}\b")
CC_RE = re.compile(r"(\d+)\s*cm", re.IGNORECASE)
L100_RE = re.compile(r"(\d+(?:\.\d+)?)\s*l/100\s*km", re.IGNORECASE)
DECIMAL_RE = re.compile(r"(?<=\d)\.(?=\d)")


# Map scraped names to CarCatalog spellings where they differ.
BRAND_ALIASES = {
    "AUDI": "Audi",
    "ChangAn": "Changan",
    "BAIC": "Baic",
}


def flatten_specs(specs_json: str | None) -> dict[str, str]:
    if not specs_json:
        return {}
    try:
        specs = json.loads(specs_json)
    except json.JSONDecodeError:
        return {}
    out: dict[str, str] = {}
    for content in specs.values():
        if not isinstance(content, list):
            continue
        for it in content:
            if isinstance(it, dict) and it.get("key"):
                k = str(it["key"])
                v = it.get("value")
                out[k] = (str(v) if v is not None else "").strip()
    return out


def parse_year(flat: dict[str, str]) -> int | None:
    start = flat.get("Start of production", "")
    m = YEAR_RE.search(start)
    if m:
        return int(m.group(0))
    return None


def production_year_range(flat: dict[str, str]) -> tuple[int, int] | None:
    """
    Inclusive [start, end] from Start/End of production.
    Missing or unparseable end → same as start (single-year row).
    Phrases like "present" / "still in production" → end = current calendar year.
    """
    start = parse_year(flat)
    if start is None:
        return None
    end_raw = flat.get("End of production", "") or ""
    end_lower = end_raw.lower().strip()
    m_end = YEAR_RE.search(end_raw)
    if m_end:
        end = int(m_end.group(0))
    elif any(
        phrase in end_lower
        for phrase in (
            "present",
            "still in production",
            "currently in production",
        )
    ):
        end = datetime.now().year
    else:
        end = start
    if end < start:
        start, end = end, start
    cap = datetime.now().year + 1
    if end > cap:
        end = cap
    return (start, end)


def parse_displacement_cc(flat: dict[str, str]) -> int | None:
    raw = flat.get("Engine displacement", "")
    if not raw:
        return None
    line = raw.split("\n")[0].strip()
    m = CC_RE.search(line)
    if m:
        return int(m.group(1))
    return None


def parse_fuel_l100(flat: dict[str, str]) -> float | None:
    for key in (
        "Fuel consumption (economy) - combined",
        "Combined fuel consumption (WLTP)",
        "Fuel consumption (economy) - combined (NEDC)",
        "Fuel consumption (economy) - combined (WLTC)",
        "Fuel consumption (economy) - combined (EPA)",
    ):
        raw = flat.get(key, "")
        if not raw:
            continue
        first_line = raw.split("\n")[0]
        m = L100_RE.search(first_line)
        if m:
            return float(m.group(1))
    return None


def map_fuel_type(performance_fuel: str) -> str:
    t = performance_fuel.lower()
    if "diesel" in t:
        return "Diesel"
    if "electric" in t and "hybrid" not in t:
        return "Electric"
    if "hybrid" in t:
        return "Hybrid"
    return "Petrol (Gasoline)"


def map_transmission(gearbox: str) -> str:
    g = gearbox.lower()
    if "manual" in g:
        return "Manual"
    return "Automatic"


def map_drivetrain(drive_wheel: str, arch: str) -> str:
    blob = f"{drive_wheel} {arch}".lower()
    if "all wheel" in blob or "awd" in blob:
        return "AWD"
    if "four wheel" in blob or "4wd" in blob or "4-wheel" in blob:
        return "4WD"
    if "rear" in blob:
        return "RWD"
    if "front" in blob:
        return "FWD"
    return ""


def map_body_type(body: str) -> str:
    return body.split("\n")[0].strip() if body else ""


def cylinders_alignment(flat: dict[str, str]) -> str | None:
    cfg = (flat.get("Engine configuration") or "").lower()
    n = (flat.get("Number of cylinders") or "").strip()
    if not n.isdigit():
        return None
    if "v-engine" in cfg or cfg.startswith("v "):
        return f"v {n}"
    if "inline" in cfg:
        return f"inline {n}"
    if "boxer" in cfg:
        return f"boxer {n}"
    if "w-engine" in cfg:
        return f"w {n}"
    return f"inline {n}"


def traction_label(flat: dict[str, str]) -> str:
    return (flat.get("Drive wheel") or "").split("\n")[0].strip()


def format_model_label(model_name: str, trim_name: str) -> str:
    raw = f"{model_name.strip()} {trim_name.strip()}".strip()
    raw = DECIMAL_RE.sub(" ", raw)
    raw = re.sub(r"\s+", " ", raw)
    return raw


def parse_seats(flat: dict[str, str]) -> int | None:
    s = flat.get("Seats", "").strip()
    if s.isdigit():
        v = int(s)
        return v if v > 0 else None
    m = re.match(r"^(\d+)", s)
    if m:
        v = int(m.group(1))
        return v if v > 0 else None
    return None


def main() -> None:
    ap = argparse.ArgumentParser(description="Export autodata.sqlite to car_spec_dataset.json")
    ap.add_argument(
        "--sqlite",
        type=Path,
        default=DEFAULT_SQLITE,
        help=f"Path to autodata.sqlite (default: {DEFAULT_SQLITE})",
    )
    ap.add_argument(
        "--out",
        type=Path,
        default=OUT_JSON,
        help=f"Output JSON path (default: {OUT_JSON})",
    )
    args = ap.parse_args()
    src = args.sqlite.expanduser().resolve()
    out_path = args.out
    if not src.is_file():
        raise SystemExit(f"SQLite file not found: {src}")

    conn = sqlite3.connect(src)
    conn.row_factory = sqlite3.Row
    rows = list(conn.execute("SELECT * FROM trims ORDER BY car_id"))

    name_to_bid: dict[str, int] = {}
    brands: list[dict] = []
    next_brand_id = 1

    models: list[dict] = []
    trims: list[dict] = []
    specs: list[dict] = []

    for row in rows:
        raw_brand = (row["brand_name"] or "").strip() or "Unknown"
        brand_name = BRAND_ALIASES.get(raw_brand, raw_brand)
        if brand_name not in name_to_bid:
            name_to_bid[brand_name] = next_brand_id
            brands.append({"id": next_brand_id, "name": brand_name})
            next_brand_id += 1
        brand_id = name_to_bid[brand_name]

        model_name = (row["model_name"] or "").strip()
        trim_name = (row["trim_name"] or "").strip()
        label = format_model_label(model_name, trim_name)
        car_id = int(row["car_id"])
        flat = flatten_specs(row["specs_json"])

        yr = production_year_range(flat)
        if yr is None:
            continue
        year_start, year_end = yr

        disp = parse_displacement_cc(flat)
        fuel = map_fuel_type(flat.get("Fuel Type", ""))
        trans = map_transmission(flat.get("Number of gears and type of gearbox", ""))
        drive = map_drivetrain(
            flat.get("Drive wheel", ""),
            flat.get("Drivetrain Architecture", ""),
        )
        body = map_body_type(flat.get("Body type", ""))
        seats = parse_seats(flat)
        l100 = parse_fuel_l100(flat)

        cyl = cylinders_alignment(flat)
        raw_pairs: dict[str, str] = {}
        if flat.get("Engine displacement"):
            raw_pairs["Displacement:"] = re.sub(
                r"\s+", " ", flat["Engine displacement"].replace("\n", " ")
            ).strip()
        if cyl:
            raw_pairs["Cylinders alignment:"] = cyl
        tr = traction_label(flat)
        if tr:
            raw_pairs["Traction:"] = tr
        nedc = flat.get("Fuel consumption (economy) - combined (NEDC)")
        if nedc:
            raw_pairs["EU NEDC/Australia ADR82:"] = nedc.split("\n")[0].strip()

        models.append({"id": car_id, "brand_id": brand_id, "name": label})
        trims.append(
            {
                "id": car_id,
                "model_id": car_id,
                "year": year_start,
                "year_end": year_end,
                "name": label,
            }
        )
        spec_obj: dict = {
            "trim_id": car_id,
            "raw_spec_pairs": raw_pairs,
            "fuel_type": fuel,
            "transmission": trans,
            "drivetrain": drive,
            "body_type": body,
        }
        if disp is not None:
            spec_obj["displacement_cc"] = disp
        if seats is not None:
            spec_obj["seats"] = seats
        if l100 is not None:
            spec_obj["fuel_consumption_l_100km"] = l100
        specs.append(spec_obj)

    payload = {
        "brands": brands,
        "models": models,
        "trims": trims,
        "specs": specs,
    }

    out_path.parent.mkdir(parents=True, exist_ok=True)
    with out_path.open("w", encoding="utf-8") as f:
        json.dump(payload, f, ensure_ascii=False, separators=(",", ":"))

    print(f"Wrote {out_path}")
    print(
        f"brands={len(brands)} models={len(models)} trims={len(trims)} specs={len(specs)}"
    )


if __name__ == "__main__":
    main()
