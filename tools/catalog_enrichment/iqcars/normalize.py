#!/usr/bin/env python3
"""Normalize the RAW IQ Cars catalog into candidate enrichment datasets (offline; never touches assets/).

  raw/iqcars_catalog.json -> generated/iqcars_model_options.json          (used-car catalog: MODEL-LEVEL independent lists)
                          -> generated/iqcars_brand_new_exact_configs.json (brand-new catalog: exact trim->engine->cylinder rows)

Hard rules
  * Model identity = IQ Cars (brand_id, model_id). Names are never used to merge or combine models
    (Land Cruiser != Land Cruiser Prado, Corolla != Corolla Cross, ...).
  * The used-car catalog gives INDEPENDENT per-model lists: trims[], engines[], cylinders[]. No trim->engine,
    trim->cylinder or engine->cylinder relationship is ever inferred from them. Links exist only in the brand-new
    catalog, which is written to its own file and never folded into the model-level union.
  * Trims - SAFE normalization only: Unicode NFKC, strip, collapse repeated whitespace, EXACT duplicate removal.
    Case, punctuation and wording are never touched. 'VX 3.5L Twin-Turbo' vs 'VX 3.5L Twin Turbo', 'EX.R' vs 'EXR'
    stay separate and are flagged as POSSIBLE_DUPLICATES for human review.
  * Engines: '2300 cc' / '2.3' / '2.3L' / '2.3 L' -> '2.3L'. Qualifiers (T, TD, ...) are preserved verbatim (upper-cased)
    and never interpreted. Cylinders are taken only from IQ's own cylinder list; never inferred from displacement.
  * Nothing is dropped silently: every raw record is kept (per-ID *_records) and unparsable values are listed.
  * Output is deterministic: no timestamps / randomness; same raw input -> byte-identical output.

Usage:
  python normalize.py                               # both outputs
  python normalize.py --only "Toyota:Land Cruiser"  # single-model sample -> generated/samples/
"""
from __future__ import annotations

import argparse
import json
import re
import sys
import unicodedata
from collections import Counter, defaultdict
from decimal import ROUND_HALF_UP, Decimal
from pathlib import Path

HERE = Path(__file__).resolve().parent
CATALOG_PATH = HERE / "raw" / "iqcars_catalog.json"
OUT_MODELS = HERE / "generated" / "iqcars_model_options.json"
OUT_BRAND_NEW = HERE / "generated" / "iqcars_brand_new_exact_configs.json"
SAMPLES_OUT = HERE / "generated" / "samples"

try:  # reuse CarNet's canonical key so downstream matching lines up
    sys.path.insert(0, str(HERE.parent))
    from model_boundaries import mkey  # type: ignore
except Exception:  # pragma: no cover
    def mkey(s):
        return re.sub(r"\s+", " ", re.sub(r"[-_/]", " ", (s or "").casefold())).strip()

_ENGINE_RE = re.compile(r"^(?P<num>\d+(?:[.,]\d+)?)\s*(?P<unit>cc|ltr|liter|litre|l)?\s*(?P<q>[A-Za-z][A-Za-z0-9.\- ]*)?$", re.I)
_CYL_RE = re.compile(r"^(?P<n>\d{1,2})\s*[- ]?\s*cyl(?:inders?)?\b", re.I)
MIN_L, MAX_L = Decimal("0.1"), Decimal("16.0")
_INVISIBLE = re.compile("[\u200b\u200c\u200d\u2060\ufeff]")


def norm_ws(s) -> str:
    """Unicode NFKC + strip + collapse repeated whitespace. Case and punctuation untouched."""
    s = unicodedata.normalize("NFKC", "" if s is None else str(s))
    s = _INVISIBLE.sub("", s)
    return re.sub(r"\s+", " ", s).strip()


def loose_key(s) -> str:
    """Review-only key (case/punctuation/spacing blind). NEVER used to merge, only to flag POSSIBLE_DUPLICATES."""
    return re.sub(r"[\W_]+", "", unicodedata.normalize("NFKC", "" if s is None else str(s)).casefold())


# ------------------------------------------------------------------ engines / cylinders
def _l_display(liters: Decimal) -> tuple[str, float]:
    q = liters.quantize(Decimal("0.1"), rounding=ROUND_HALF_UP)
    return f"{q:.1f}L", float(q)


def parse_engine(raw) -> dict:
    s = norm_ws(raw)
    out = {"raw": raw, "display": None, "displacement_l": None, "displacement_cc": None, "qualifier": "", "parsed": False}
    m = _ENGINE_RE.match(s)
    if not m:
        out["note"] = "unrecognized format"
        return out
    unit = (m.group("unit") or "").casefold()
    num_s = m.group("num")
    if re.fullmatch(r"\d{1,2},\d{3}", num_s) and unit == "cc":
        num_s = num_s.replace(",", "")
    else:
        num_s = num_s.replace(",", ".")
    val = Decimal(num_s)
    if unit == "cc":
        liters, cc = val / 1000, int(val)
    elif unit:
        liters, cc = val, None
    elif val >= 500 and val == val.to_integral_value():
        liters, cc = val / 1000, int(val)
        out["note"] = "unit inferred as cc"
    elif val < 100:
        liters, cc = val, None
    else:
        out["note"] = "ambiguous bare number"
        return out
    if not (MIN_L <= liters <= MAX_L):
        out["note"] = "outside plausible displacement range"
        return out
    out["display"], out["displacement_l"] = _l_display(liters)
    out["displacement_cc"] = cc
    out["qualifier"] = norm_ws(m.group("q") or "").upper()
    out["parsed"] = True
    return out


def parse_cylinder(raw) -> dict:
    m = _CYL_RE.match(norm_ws(raw))
    return {"raw": raw, "count": int(m.group("n")) if m else None, "parsed": bool(m)}


def _year(y) -> int | None:
    try:
        return int(y["YearName"]) if y else None
    except (KeyError, TypeError, ValueError):
        return None


# ------------------------------------------------------------------ trims
def normalize_trims(sfxes):
    """-> (trim_records, trims_union, stats, possible_duplicates)

    trim_records: ONE record per IQ trim ID (nothing merged): trim_id, trim_name_raw, trim_name_normalized, from_year, to_year.
    trims_union : unique normalized names (EXACT duplicate removal only), in IQ ID order.
    """
    records, stats, by_name = [], Counter(), {}
    for s in sorted(sfxes or [], key=lambda x: x.get("ID") or 0):
        raw = s.get("SFXName")
        name = norm_ws(raw)
        rec = {"trim_id": s.get("ID"), "trim_name_raw": raw, "trim_name_normalized": name,
               "from_year": _year(s.get("FromYear")), "to_year": _year(s.get("ToYear"))}
        if raw is not None and name != raw:
            stats["name_changed_by_normalization"] += 1
        if s.get("Deleted"):
            rec["excluded_from_union"] = "deleted"
            stats["deleted"] += 1
        elif not name:
            rec["excluded_from_union"] = "empty_name"
            stats["empty_name"] += 1
        else:
            by_name.setdefault(name, []).append(rec["trim_id"])
        records.append(rec)
    union = list(by_name)
    dup = {n: ids for n, ids in by_name.items() if len(ids) > 1}
    stats["exact_duplicate_names"] = len(dup)
    stats["exact_duplicate_records_removed"] = sum(len(i) - 1 for i in dup.values())
    groups: dict[str, list[str]] = defaultdict(list)
    for n in union:
        groups[loose_key(n)].append(n)
    possible = [{"status": "POSSIBLE_DUPLICATES", "loose_key": k, "names": v, "trim_ids": {n: by_name[n] for n in v}}
                for k, v in groups.items() if k and len(v) > 1]
    return records, union, dict(stats), possible


def normalize_model_options(resp):
    """Used-car cylinder-and-engine response -> independent model-level lists (+ per-ID source records)."""
    resp = resp or {}
    eng_records, variants = [], {}
    for e in resp.get("Engines") or []:
        raw = e.get("EngineNameen")
        p = parse_engine(raw)
        rec = {"engine_id": e.get("ID"), "raw": raw, "parsed": p["parsed"], "displacement_normalized": p["display"],
               "displacement_l": p["displacement_l"], "displacement_cc": p["displacement_cc"], "qualifier": p["qualifier"]}
        if p.get("note"):
            rec["note"] = p["note"]
        eng_records.append(rec)
        if p["parsed"]:
            v = variants.setdefault((p["display"], p["qualifier"]), {"display": p["display"], "displacement_l": p["displacement_l"],
                                                                      "qualifier": p["qualifier"], "engine_ids": [], "raw_values": []})
            v["engine_ids"].append(e.get("ID"))
            v["raw_values"].append(raw)
    cyl_records = []
    for c in resp.get("Cylinders") or []:
        p = parse_cylinder(c.get("CylinderNameen"))
        cyl_records.append({"cylinder_id": c.get("ID"), "raw": p["raw"], "count": p["count"], "parsed": p["parsed"]})
    eng_variants = sorted(variants.values(), key=lambda v: (v["displacement_l"], v["qualifier"]))
    return {
        "engine_sizes": sorted({v["display"] for v in eng_variants}, key=lambda d: float(d[:-1])),
        "engine_variants": eng_variants,
        "engine_records": eng_records,
        "cylinders": sorted({c["count"] for c in cyl_records if c["parsed"]}),
        "cylinder_records": cyl_records,
    }


# ------------------------------------------------------------------ used-car model-level dataset
def build(catalog: dict, only: tuple[str, str] | None = None) -> dict:
    cyl_by_id = catalog.get("cylinder_engine_by_model_id") or {}
    models_out, stats, conflicts = [], Counter(), defaultdict(list)
    key_to_ids: dict[tuple, list] = defaultdict(list)
    all_trim_names, all_trim_exact = set(), set()
    raw_engine_values, engine_displays, engine_variant_keys, cyl_values = set(), set(), set(), set()
    n_possible_dup_groups = 0
    for b in catalog.get("initial_data_brands") or []:
        for m in b.get("Models") or []:
            if only and (b["BrandNameen"].casefold(), m["ModelNameen"].casefold()) != only:
                continue
            records, union, tstats, possible = normalize_trims(m.get("ModelSFXes"))
            resp = cyl_by_id.get(str(m["ID"]))
            opts = normalize_model_options(resp)
            rec = {
                "brand": b["BrandNameen"], "brand_id": b["ID"], "model": m["ModelNameen"], "model_id": m["ID"],
                "model_key": f"{mkey(b['BrandNameen'])}|{mkey(m['ModelNameen'])}",
                "names": {"brand": {"en": b.get("BrandNameen"), "ar": b.get("BrandNamear"), "ku": b.get("BrandNameku")},
                          "model": {"en": m.get("ModelNameen"), "ar": m.get("ModelNamear"), "ku": m.get("ModelNameku")}},
                "model_years": {"from": _year(m.get("FromYear")), "to": _year(m.get("ToYear"))},
                # ---- A. MODEL-LEVEL UNION (independent lists; no links between them) ----
                "trims": union,
                "engine_sizes": opts["engine_sizes"],
                "engine_variants": opts["engine_variants"],
                "cylinders": opts["cylinders"],
                # ---- B. SOURCE RECORDS (one per IQ ID, raw + normalized side by side) ----
                "trim_records": records,
                "engine_records": opts["engine_records"],
                "cylinder_records": opts["cylinder_records"],
                "possible_duplicate_trims": possible,
                "relationships": {"trim_engine_cylinder_links": "none_provided",
                                  "scope": "model_level_independent_lists"},
                "cylinder_engine_response_present": resp is not None,
                "trim_normalization_stats": tstats,
            }
            models_out.append(rec)
            key_to_ids[(b["ID"], rec["model_key"])].append(m["ID"])
            has_t, has_e, has_c = bool(union), bool(opts["engine_sizes"]), bool(opts["cylinders"])
            stats["models"] += 1
            stats["models_with_trims"] += has_t
            stats["models_with_engines"] += has_e
            stats["models_with_cylinders"] += has_c
            stats["models_with_all_3"] += has_t and has_e and has_c
            stats["models_with_none"] += not (has_t or has_e or has_c)
            stats["models_without_cylinder_engine_response"] += resp is None
            stats["trim_records"] += len(records)
            stats["possible_duplicate_trim_groups"] += len(possible)
            for k in ("name_changed_by_normalization", "exact_duplicate_records_removed", "deleted", "empty_name"):
                stats["trim_" + k] += tstats.get(k, 0)
            n_possible_dup_groups += len(possible)
            for t in union:
                all_trim_exact.add(t)
                all_trim_names.add((b["ID"], m["ID"], t))
            for er in opts["engine_records"]:
                raw_engine_values.add(er["raw"])
            engine_displays.update(opts["engine_sizes"])
            engine_variant_keys.update((v["display"], v["qualifier"]) for v in opts["engine_variants"])
            cyl_values.update(opts["cylinders"])
            who = {"model_id": m["ID"], "brand": b["BrandNameen"], "model": m["ModelNameen"]}
            for p in possible:
                conflicts["possible_duplicate_trims"].append({**who, **p})
            unp_e = [er for er in opts["engine_records"] if not er["parsed"]]
            unp_c = [cr for cr in opts["cylinder_records"] if not cr["parsed"]]
            if unp_e:
                conflicts["engine_unparsed"].append({**who, "values": unp_e})
            if unp_c:
                conflicts["cylinder_unparsed"].append({**who, "values": unp_c})
            if resp is not None and not (opts["engine_records"] or opts["cylinder_records"]):
                conflicts["response_without_engines_or_cylinders"].append(who)
    for (bid, mk), ids in key_to_ids.items():
        if len(ids) > 1:
            conflicts["model_key_collisions_not_merged"].append({"brand_id": bid, "model_key": mk, "model_ids": ids})
    return {
        "_meta": {
            "dataset": "IQ Cars used-car catalog, MODEL-LEVEL independent lists (candidate; not connected to the app)",
            "derived_from_raw_assembled_at": (catalog.get("_meta") or {}).get("assembled_at"),
            "fields_in_scope": "brand, model, trims, engine sizes (+qualifier variants), cylinders",
            "semantics": {
                "trims / engine_sizes / engine_variants / cylinders": "model-level lists; NO trim->engine->cylinder links exist or are implied",
                "trim_records / engine_records / cylinder_records": "one per IQ ID with raw + normalized values",
                "possible_duplicate_trims": "POSSIBLE_DUPLICATES flagged for review, never merged",
            },
            "coverage": {
                "brands": len({r["brand_id"] for r in models_out}),
                **{k: stats[k] for k in ("models", "models_with_trims", "models_with_engines", "models_with_cylinders",
                                           "models_with_all_3", "models_with_none", "models_without_cylinder_engine_response")},
                "total_trim_records": stats["trim_records"],
                "unique_trim_names_exact": len(all_trim_exact),
                "unique_raw_engine_values": len(raw_engine_values),
                "unique_engine_sizes": len(engine_displays),
                "unique_engine_size_qualifier_variants": len(engine_variant_keys),
                "unique_cylinder_values": sorted(cyl_values),
                "possible_duplicate_trim_groups": stats["possible_duplicate_trim_groups"],
                "trim_normalization": {k: stats[k] for k in stats if k.startswith("trim_") and k != "trim_records"},
            },
            "conflicts_summary": {k: len(v) for k, v in conflicts.items()},
        },
        "models": models_out,
        "conflicts": dict(conflicts),
    }


# ------------------------------------------------------------------ brand-new catalog (exact relationships)
def build_brand_new(catalog: dict, model_options: dict | None = None) -> dict:
    bnc = catalog.get("brand_new_cars") or {}
    entries = bnc.get("entries_by_id") or {}
    sfx_by = bnc.get("sfxes_by_brand_new_car_id") or {}
    used = {r["model_id"]: r for r in (model_options or {}).get("models", [])}
    cfgs, field_counts, rows_total = [], Counter(), 0
    entry_out = []
    for bid in sorted(entries, key=int):
        e = entries[bid]
        entry_out.append({"brand_new_car_id": e["ID"], "brand": (e.get("Brand") or {}).get("BrandNameen"),
                          "brand_id": e.get("BrandId"), "model": (e.get("Model") or {}).get("ModelNameen"),
                          "model_id": e.get("ModelId"), "year": _year(e.get("Year")),
                          "exact_configuration_rows": len(sfx_by.get(bid) or [])})
    for bid in sorted(sfx_by, key=int):
        e = entries.get(bid) or {}
        for r in sfx_by[bid] or []:
            rows_total += 1
            for k, v in r.items():
                if v not in (None, "", [], {}):
                    field_counts[k] += 1
            bn = r.get("BrandNewCar") or {}
            model, brand = bn.get("Model") or e.get("Model") or {}, bn.get("Brand") or e.get("Brand") or {}
            eng = parse_engine((r.get("Engine") or {}).get("EngineNameen")) if r.get("Engine") else None
            cyl = parse_cylinder((r.get("Cylinder") or {}).get("CylinderNameen")) if r.get("Cylinder") else None
            cfg = {
                "brand_new_car_id": r.get("BrandNewCarId"), "brand_new_car_sfx_id": r.get("ID"),
                "brand": brand.get("BrandNameen"), "brand_id": brand.get("ID"),
                "model": model.get("ModelNameen"), "model_id": model.get("ID"),
                "year": _year(bn.get("Year")) or _year(e.get("Year")),
                "trim": {"trim_id": r.get("ModelSFXId"), "trim_name_raw": (r.get("ModelSFX") or {}).get("SFXName"),
                         "trim_name_normalized": norm_ws((r.get("ModelSFX") or {}).get("SFXName"))},
                "engine": None if not eng else {"engine_id": r.get("EngineId"), "raw": eng["raw"], "displacement_normalized": eng["display"],
                                                "qualifier": eng["qualifier"], "parsed": eng["parsed"]},
                "cylinder": None if not cyl else {"cylinder_id": r.get("CylinderId"), "raw": cyl["raw"], "count": cyl["count"],
                                                  "parsed": cyl["parsed"]},
            }
            cfg["comparison_with_used_car_union"] = _agreement(cfg, used.get(cfg["model_id"]))
            cfgs.append(cfg)
    agree = Counter()
    conflicts = []
    for c in cfgs:
        for dim, st in c["comparison_with_used_car_union"].items():
            if dim == "model_in_used_catalog":
                continue
            agree[f"{dim}:{st}"] += 1
            if st.startswith("CONFLICT"):
                conflicts.append({"brand_new_car_sfx_id": c["brand_new_car_sfx_id"], "brand": c["brand"], "model": c["model"],
                                  "model_id": c["model_id"], "dimension": dim, "status": st,
                                  "brand_new_value": (c["trim"]["trim_name_normalized"] if dim == "trim" else
                                                      (c["engine"] or {}).get("raw") if dim == "engine" else (c["cylinder"] or {}).get("raw"))})
    triples = defaultdict(set)
    for c in cfgs:
        triples[c["model_id"]].add((c["trim"]["trim_name_normalized"], (c["engine"] or {}).get("raw"), (c["cylinder"] or {}).get("count")))
    return {
        "_meta": {
            "dataset": "IQ Cars brand-new-car catalog: EXACT trim->engine->cylinder rows (kept separate from the used-car union)",
            "derived_from_raw_assembled_at": (catalog.get("_meta") or {}).get("assembled_at"),
            "semantics": "Each configuration row is an exact IQ-published link. Never merged into model-level lists; neither source overrides the other.",
            "analysis": {
                "entries": len(entry_out),
                "models_represented": len({e["model_id"] for e in entry_out}),
                "models_with_exact_configurations": len({c["model_id"] for c in cfgs}),
                "exact_configuration_records": len(cfgs),
                "fields_available_in_raw_rows(non-null counts)": dict(sorted(field_counts.items())),
                "fields_extracted_here": ["trim", "engine", "cylinder", "year", "model identity"],
                "distinct_trim_engine_cylinder_triples": sum(len(v) for v in triples.values()),
                "agreement_with_used_car_union": dict(sorted(agree.items())),
                "conflict_count": len(conflicts),
            },
        },
        "entries": entry_out,
        "exact_configurations": cfgs,
        "conflicts": conflicts,
    }


def _agreement(cfg: dict, used_rec: dict | None) -> dict:
    if used_rec is None:
        return {"model_in_used_catalog": False, "trim": "MODEL_NOT_IN_USED_CATALOG", "engine": "MODEL_NOT_IN_USED_CATALOG",
                "cylinder": "MODEL_NOT_IN_USED_CATALOG"}
    out = {"model_in_used_catalog": True}
    name = cfg["trim"]["trim_name_normalized"]
    if not name:
        out["trim"] = "NOT_PROVIDED"
    elif name in used_rec["trims"]:
        out["trim"] = "AGREE_EXACT"
    elif loose_key(name) in {loose_key(t) for t in used_rec["trims"]}:
        out["trim"] = "POSSIBLE_MATCH_NOT_EXACT"
    else:
        out["trim"] = "CONFLICT_NOT_IN_USED_LIST"
    e = cfg["engine"]
    if not e or not e["parsed"]:
        out["engine"] = "NOT_PROVIDED"
    elif (e["displacement_normalized"], e["qualifier"]) in {(v["display"], v["qualifier"]) for v in used_rec["engine_variants"]}:
        out["engine"] = "AGREE_EXACT_VARIANT"
    elif e["displacement_normalized"] in used_rec["engine_sizes"]:
        out["engine"] = "AGREE_SIZE_ONLY"
    else:
        out["engine"] = "CONFLICT_NOT_IN_USED_LIST"
    c = cfg["cylinder"]
    if not c or not c["parsed"]:
        out["cylinder"] = "NOT_PROVIDED"
    elif c["count"] in used_rec["cylinders"]:
        out["cylinder"] = "AGREE_EXACT"
    else:
        out["cylinder"] = "CONFLICT_NOT_IN_USED_LIST"
    return out


def _dump(path: Path, obj) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(obj, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--catalog", default=str(CATALOG_PATH))
    ap.add_argument("--only", default="", help='"Brand:Model" -> single-model sample')
    a = ap.parse_args(argv)
    cat = json.loads(Path(a.catalog).read_text(encoding="utf-8"))
    if a.only:
        b, _, m = a.only.partition(":")
        only = (b.strip().casefold(), m.strip().casefold())
        out = build(cat, only)
        path = SAMPLES_OUT / (re.sub(r"[^a-z0-9]+", "_", f"{only[0]}_{only[1]}").strip("_") + ".normalized.json")
        _dump(path, out)
        print(f"wrote {path}")
        return 0
    models = build(cat)
    _dump(OUT_MODELS, models)
    bn = build_brand_new(cat, models)
    _dump(OUT_BRAND_NEW, bn)
    print(f"wrote {OUT_MODELS}\nwrote {OUT_BRAND_NEW}")
    print(json.dumps(models["_meta"]["coverage"], indent=1))
    print(json.dumps(bn["_meta"]["analysis"], indent=1)[:1500])
    return 0


if __name__ == "__main__":
    sys.exit(main())
