#!/usr/bin/env python3
"""READ-ONLY catalog inspector / gap reporter (design prototype).

Reads assets/car_catalog.json and assets/car_spec_dataset.json and NEVER writes to
them. Mirrors the app's resolution rules from lib/services/car_spec_index_*.dart so
the numbers match what Sell / Search actually offer.

Usage (repo root):
  python tools/catalog_enrichment/catalog_audit_readonly.py --make Ford --model Everest
  python tools/catalog_enrichment/catalog_audit_readonly.py --global
  python tools/catalog_enrichment/catalog_audit_readonly.py --make Ford --model Everest --json out.json
"""
from __future__ import annotations

import argparse
import datetime as _dt
import json
import re
import sys
from collections import Counter, defaultdict
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
CATALOG = REPO / "assets" / "car_catalog.json"
DATASET = REPO / "assets" / "car_spec_dataset.json"

# Mirrors _kCatalogStaleExportGraceYears / _openEndedModelYearCap in car_spec_index_parse.dart
STALE_GRACE_YEARS = 10


def cap_year() -> int:
    return _dt.date.today().year + 1


def load():
    cat = json.loads(CATALOG.read_text(encoding="utf-8"))
    ds = json.loads(DATASET.read_text(encoding="utf-8"))
    return cat, ds


def name_matches_family(dataset_name: str, family: str) -> bool:
    """_datasetNameMatchesAppFamily"""
    dn = dataset_name.strip().lower()
    fl = family.strip().lower()
    if not dn or not fl:
        return False
    if dn == fl or dn.startswith(fl + " "):
        return True
    return dn.split()[0] == fl


def nominal_liters(label: str | None):
    """_nominalLitersFromCatalogLabel"""
    if not label:
        return None
    n = label.lower()
    m = re.search(r"(\d+\.\d+)\s*l(?:iter)?\b", n)
    if m:
        return float(m.group(1))
    m = re.search(r"\b(\d)\s+(\d{2})\s*l(?:iter)?\b", n)
    if m:
        return int(m.group(1)) + int(m.group(2)) / 100
    m = re.search(r"\b(\d)\s+(\d)\s*l(?:iter)?\b", n)
    if m:
        return int(m.group(1)) + int(m.group(2)) / 10
    m = re.search(r"\b(\d)\s+(\d)\s+(?!l(?:iter)?\b)(?=[a-z0-9(])", n)
    if m:
        return int(m.group(1)) + int(m.group(2)) / 10
    return None


def resolve_liters(spec: dict, label: str):
    cc = spec.get("displacement_cc")
    from_cc = cc / 1000 if cc and cc > 0 else None
    from_name = nominal_liters(label)
    if from_name is not None and from_cc is not None:
        return from_name if abs(from_name - from_cc) <= 0.2 else from_cc
    return from_cc if from_cc is not None else from_name


def cylinders(spec: dict):
    txt = (spec.get("raw_spec_pairs") or {}).get("Cylinders alignment:")
    if not txt:
        return None
    m = re.search(r"(?:line|inline|v|w|boxer)\s*(\d+)", txt, re.I)
    if m:
        return int(m.group(1))
    m = re.search(r"\b(\d+)\s*$", txt.strip())
    return int(m.group(1)) if m else None


def build_index(ds):
    brands = {b["id"]: b["name"] for b in ds["brands"]}
    by_brand = defaultdict(list)
    for m in ds["models"]:
        by_brand[m["brand_id"]].append(m)
    trim_by_model = defaultdict(list)
    for t in ds["trims"]:
        trim_by_model[t["model_id"]].append(t)
    spec_by_trim = {s["trim_id"]: s for s in ds["specs"]}
    return brands, by_brand, trim_by_model, spec_by_trim


def family_rows(ds_idx, brand: str, model: str):
    brands, by_brand, trim_by_model, spec_by_trim = ds_idx
    bid = next((i for i, n in brands.items() if n.lower().strip() == brand.lower().strip()), None)
    if bid is None:
        return None, []
    rows = []
    for m in sorted(by_brand[bid], key=lambda x: x["name"].lower()):
        if not name_matches_family(m["name"], model):
            continue
        for t in trim_by_model.get(m["id"], []):
            s = spec_by_trim.get(t["id"], {})
            ye = t.get("year_end") or max(t["year"], cap_year())
            rows.append(
                {
                    "dataset_model_id": m["id"],
                    "dataset_trim_id": t["id"],
                    "name": m["name"],
                    "year_from": t["year"],
                    "year_to": ye,
                    "year_end_raw": t.get("year_end"),
                    "fuel_type": s.get("fuel_type"),
                    "transmission": s.get("transmission"),
                    "drivetrain": s.get("drivetrain"),
                    "body_type": s.get("body_type"),
                    "seats": s.get("seats"),
                    "displacement_cc": s.get("displacement_cc"),
                    "liters_resolved": resolve_liters(s, f"{m['name']} {t['name']}"),
                    "cylinders": cylinders(s),
                    "l_per_100km": s.get("fuel_consumption_l_100km"),
                    "raw_spec_pairs": s.get("raw_spec_pairs"),
                }
            )
    return bid, rows


def rows_visible_for_year(rows, year: int):
    """What _catalogSellRowsDeduped would union for an empty trim at `year`
    (strict coverage, else the stale-export tail rule)."""
    cap = cap_year()
    out = []
    for r in rows:
        strict = r["year_from"] <= year <= r["year_to"]
        if strict:
            out.append((r, "strict"))
            continue
        if year > cap or r["year_from"] > year:
            continue
        if year > r["year_to"] and r["year_to"] >= cap - STALE_GRACE_YEARS:
            out.append((r, "tail-reuse"))
    return out


def report_model(cat, ds_idx, brand, model):
    rep = {"brand": brand, "model": model}
    rep["in_car_catalog_models"] = model in (cat["models"].get(brand) or [])
    rep["catalog_trims"] = (cat["trimsByBrandModel"].get(brand) or {}).get(model)
    bid, rows = family_rows(ds_idx, brand, model)
    rep["dataset_brand_id"] = bid
    rep["dataset_rows"] = rows
    if rows:
        rep["years_in_dataset_raw"] = [min(r["year_from"] for r in rows), max((r["year_end_raw"] or r["year_from"]) for r in rows)]
        by_year = {}
        for y in range(rep["years_in_dataset_raw"][0], cap_year() + 1):
            vis = rows_visible_for_year(rows, y)
            labels = sorted({(r["liters_resolved"], r["cylinders"], r["fuel_type"], r["transmission"], r["drivetrain"], r["seats"]) for r, _ in vis}, key=lambda t: tuple(str(x) for x in t))
            by_year[y] = {
                "variant_rows": len(vis),
                "strict_rows": sum(1 for _, k in vis if k == "strict"),
                "engines": sorted({f"{r['liters_resolved']}L/{r['cylinders']}cyl/{r['fuel_type']}" for r, _ in vis}),
            }
        rep["sell_search_visible_by_year"] = by_year
        rep["incomplete_fields"] = {
            "seats_missing": [r["name"] for r in rows if not r["seats"]],
            "displacement_missing": [r["name"] for r in rows if not r["displacement_cc"]],
            "cylinders_missing": [r["name"] for r in rows if r["cylinders"] is None],
            "drivetrain_empty": [r["name"] for r in rows if not r["drivetrain"]],
            "fuel_l100_missing": [r["name"] for r in rows if r["l_per_100km"] is None],
        }
    return rep


def print_model_report(rep):
    print(f"== {rep['brand']} {rep['model']} ==")
    print("in car_catalog.json models list :", rep["in_car_catalog_models"])
    print("car_catalog.json trims          :", rep["catalog_trims"])
    print("dataset brand id                :", rep["dataset_brand_id"])
    rows = rep["dataset_rows"]
    print(f"dataset rows (family match)     : {len(rows)}")
    for r in rows:
        print(
            f"  [{r['dataset_model_id']}] {r['name']!r}  {r['year_from']}-{r['year_end_raw']}  "
            f"{r['liters_resolved']}L {r['cylinders']}cyl {r['fuel_type']} | {r['transmission']} | {r['drivetrain']} | "
            f"{r['body_type']} | seats={r['seats']} | cc={r['displacement_cc']} | L/100={r['l_per_100km']}"
        )
    if rows:
        print("years in dataset (raw)          :", rep["years_in_dataset_raw"])
        print("\nWhat Sell/Search would union per model year (empty trim):")
        for y, v in rep["sell_search_visible_by_year"].items():
            print(f"  {y}: rows={v['variant_rows']:>2} (strict={v['strict_rows']}) engines={v['engines']}")
        print("\nIncomplete fields:")
        for k, v in rep["incomplete_fields"].items():
            print(f"  {k}: {len(v)} {v if v else ''}")


def global_report(cat, ds, ds_idx):
    brands, by_brand, trim_by_model, spec_by_trim = ds_idx
    ds_brand_by_lower = {n.lower().strip(): i for i, n in brands.items()}
    out = {}
    out["catalog_brands"] = len(cat["brands"])
    out["dataset_brands"] = len(brands)
    out["catalog_brands_without_dataset_brand"] = sorted(b for b in cat["brands"] if b.lower().strip() not in ds_brand_by_lower)
    models_total = models_uncovered = models_no_trims = 0
    uncovered_examples = []
    for b, ms in cat["models"].items():
        bid = ds_brand_by_lower.get(b.lower().strip())
        for m in ms:
            models_total += 1
            has_cov = bid is not None and any(name_matches_family(x["name"], m) for x in by_brand[bid])
            if not has_cov:
                models_uncovered += 1
                if len(uncovered_examples) < 15:
                    uncovered_examples.append(f"{b} {m}")
            tr = (cat["trimsByBrandModel"].get(b) or {}).get(m)
            if not tr:
                models_no_trims += 1
    out["catalog_models_total"] = models_total
    out["catalog_models_with_no_spec_dataset_coverage"] = models_uncovered
    out["catalog_models_with_no_trim_list"] = models_no_trims
    out["uncovered_examples"] = uncovered_examples

    sp = ds["specs"]
    n = len(sp)
    out["dataset_spec_rows"] = n
    out["spec_rows_missing"] = {
        "seats": sum(1 for s in sp if not s.get("seats")),
        "displacement_cc": sum(1 for s in sp if not s.get("displacement_cc")),
        "cylinders": sum(1 for s in sp if cylinders(s) is None),
        "drivetrain_empty": sum(1 for s in sp if not s.get("drivetrain")),
        "transmission_empty": sum(1 for s in sp if not s.get("transmission")),
        "fuel_type_empty": sum(1 for s in sp if not s.get("fuel_type")),
        "body_type_empty": sum(1 for s in sp if not s.get("body_type")),
    }
    out["fuel_type_values"] = Counter(s.get("fuel_type") for s in sp).most_common()
    out["transmission_values"] = Counter(s.get("transmission") for s in sp).most_common()
    out["drivetrain_values"] = Counter(s.get("drivetrain") for s in sp).most_common()
    out["body_type_values_top"] = Counter(s.get("body_type") for s in sp).most_common(15)
    out["spec_keys_present"] = Counter(k for s in sp for k in s).most_common()
    out["raw_spec_pair_keys"] = Counter(k for s in sp for k in (s.get("raw_spec_pairs") or {})).most_common()
    # Hybrid / PHEV: dataset has no hybrid fuel_type at all
    out["has_hybrid_fuel_rows"] = any("hybrid" in str(s.get("fuel_type", "")).lower() for s in sp)
    # Newest model year in the dataset
    out["max_year_end"] = max((t.get("year_end") or t["year"]) for t in ds["trims"])
    stale = Counter()
    for t in ds["trims"]:
        stale[t.get("year_end") or t["year"]] += 1
    out["trim_rows_by_last_year_top"] = sorted(stale.items(), reverse=True)[:8]
    # duplicate (brand, name, year, year_end) rows
    seen = Counter()
    for m in ds["models"]:
        for t in trim_by_model.get(m["id"], []):
            seen[(m["brand_id"], m["name"], t["year"], t.get("year_end"))] += 1
    out["duplicate_name_year_rows"] = sum(1 for v in seen.values() if v > 1)
    return out


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--make")
    ap.add_argument("--model")
    ap.add_argument("--global", dest="glob", action="store_true")
    ap.add_argument("--json", help="write report JSON to this path (must NOT be under assets/)")
    a = ap.parse_args(argv)
    if not (a.glob or (a.make and a.model)):
        ap.error("pass --make/--model and/or --global")
    if a.json and Path(a.json).resolve().is_relative_to((REPO / "assets").resolve()):
        ap.error("refusing to write under assets/ (read-only tool)")
    cat, ds = load()
    ds_idx = build_index(ds)
    result = {}
    if a.make and a.model:
        rep = report_model(cat, ds_idx, a.make, a.model)
        print_model_report(rep)
        result["model_report"] = rep
    if a.glob:
        g = global_report(cat, ds, ds_idx)
        print("\n== GLOBAL ==")
        print(json.dumps(g, indent=2, ensure_ascii=False))
        result["global"] = g
    if a.json:
        Path(a.json).write_text(json.dumps(result, indent=2, ensure_ascii=False, default=str), encoding="utf-8")
    return 0


if __name__ == "__main__":
    sys.exit(main())
