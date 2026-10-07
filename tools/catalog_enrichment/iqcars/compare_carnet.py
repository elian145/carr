#!/usr/bin/env python3
"""Compare the normalized IQ Cars model options with CarNet (READ-ONLY on assets/; writes only under iqcars/generated).

  generated/iqcars_model_options.json  vs  assets/car_catalog.json + assets/car_spec_dataset.json
  -> generated/iqcars_model_matching_report.json   matched / unmatched / ambiguous model identities
  -> generated/iqcars_vs_carnet_comparison.json    per matched Brand+Model: trims / engines / cylinders
  -> generated/iqcars_coverage_report.json         coverage metrics (IQ Cars vs CarNet)

Model identity (safety first)
  * An IQ model is MATCHED only by EXACT canonical identity via CarNet's model_boundaries.ModelIndex.canonical_model
    (key equality or an explicit alias). Never by prefix, never fuzzily.
  * Everything else is reported, never forced: UNMATCHED (no counterpart) or AMBIGUOUS (near sibling such as
    'Land Cruiser FJ' vs 'Land Cruiser', a compact-key lookalike such as 'RAV 4' vs 'RAV4', or several IQ models
    competing for one CarNet model). Ambiguous models are excluded from value comparison.

CarNet values
  * TRIMS     : assets/car_catalog.json trimsByBrandModel (the list the app offers); the 'Other' placeholder is excluded.
  * ENGINES   : displacement (1 decimal, 'X.YL') of dataset rows that ModelIndex ACCEPTS for exactly that model
                (quarantined / sibling rows are excluded, so Prado rows never feed Land Cruiser).
  * CYLINDERS : cylinder count of those same accepted rows (catalog_audit_readonly.cylinders).

Comparison semantics
  * Trim equality is EXACT (after the same safe normalization IQ uses: NFKC + whitespace). Case/punctuation-only
    lookalikes ('EX.R' vs 'EXR') are NOT equal: they appear in both MISSING/ONLY lists AND are flagged POSSIBLE_DUPLICATES.
  * ONLY_IN_CARNET is information, not an error. Nothing is proposed for removal from CarNet.
  * IQ engine qualifiers (T/TD/...) are ignored for the CarNet comparison (CarNet has none); variants stay in the IQ file.
"""
from __future__ import annotations

import json
import sys
from collections import Counter, defaultdict
from decimal import ROUND_HALF_UP, Decimal
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
sys.path.insert(0, str(HERE.parent))
from model_boundaries import ACCEPTED, REJECTED, ModelIndex, mkey  # noqa: E402
from catalog_audit_readonly import cylinders as ds_cylinders, resolve_liters  # noqa: E402
from normalize import loose_key, norm_ws  # noqa: E402
from canonical_io import write_text_canonical  # noqa: E402

REPO = HERE.parents[2]
GEN = HERE / "generated"
IQ_PATH = GEN / "iqcars_model_options.json"
PLACEHOLDER_TRIMS = {"other"}


def compact(s: str) -> str:
    return loose_key(s)


def liters_display(liters: float) -> str:
    return f"{Decimal(str(round(liters, 4))).quantize(Decimal('0.1'), rounding=ROUND_HALF_UP):.1f}L"


# ------------------------------------------------------------------ CarNet side (read-only)
def carnet_profiles(idx: ModelIndex, ds: dict):
    brands = {b["id"]: b["name"] for b in ds["brands"]}
    trims_by_model = defaultdict(list)
    for t in ds["trims"]:
        trims_by_model[t["model_id"]].append(t)
    spec_by_trim = {s["trim_id"]: s for s in ds["specs"]}
    prof: dict[tuple[str, str], dict] = defaultdict(lambda: {"engines": set(), "cylinders": set(), "dataset_rows": 0})
    st = Counter()
    for m in ds["models"]:
        bname = idx.brand_name(brands.get(m["brand_id"], ""))
        if bname is None:
            st["dataset_models_brand_not_in_catalog"] += 1
            continue
        r = idx.resolve(bname, m["name"])
        if r.status not in ACCEPTED:
            st["dataset_models_not_accepted_for_any_model(" + r.outcome + ")"] += 1
            continue
        p = prof[(bname, r.model)]
        for t in trims_by_model.get(m["id"], []):
            s = spec_by_trim.get(t["id"], {})
            p["dataset_rows"] += 1
            lit = resolve_liters(s, f"{m['name']} {t['name']}")
            if lit:
                p["engines"].add(liters_display(lit))
            cyl = ds_cylinders(s)
            if cyl:
                p["cylinders"].add(cyl)
        st["dataset_models_accepted"] += 1
    return prof, dict(st)


def carnet_trims(cat: dict, brand: str, model: str) -> list[str]:
    raw = ((cat.get("trimsByBrandModel") or {}).get(brand) or {}).get(model) or []
    out, seen = [], set()
    for t in raw:
        n = norm_ws(t)
        if not n or n.casefold() in PLACEHOLDER_TRIMS or n in seen:
            continue
        seen.add(n)
        out.append(n)
    return out


# ------------------------------------------------------------------ identity matching
def match_models(idx: ModelIndex, iq_models: list[dict]):
    matched, unmatched, ambiguous = [], [], []
    by_target: dict[tuple[str, str], list[dict]] = defaultdict(list)
    for r in iq_models:
        who = {"iq_brand": r["brand"], "iq_brand_id": r["brand_id"], "iq_model": r["model"], "iq_model_id": r["model_id"]}
        b = idx.brand_name(r["brand"])
        if b is None:
            unmatched.append({**who, "reason": "brand_not_in_carnet_catalog"})
            continue
        canon = idx.canonical_model(b, r["model"])
        if canon:
            by_target[(b, canon)].append({**who, "carnet_brand": b, "carnet_model": canon,
                                          "via": "exact_key" if mkey(canon) == mkey(r["model"]) else "explicit_alias"})
            continue
        cand = [m for m in idx.models[b] if compact(m) == compact(r["model"])]
        if cand:
            ambiguous.append({**who, "reason": "compact_key_equal_but_not_exact_identity", "carnet_candidates": cand})
            continue
        res = idx.resolve(b, r["model"])
        if res.model:
            ambiguous.append({**who, "reason": f"near_sibling_of:{res.model}", "boundary_status": res.status,
                              "remainder": res.remainder, "carnet_candidates": [res.model]})
        else:
            unmatched.append({**who, "reason": "model_not_in_carnet_catalog"})
    for (b, canon), lst in by_target.items():
        if len(lst) == 1:
            matched.append(lst[0])
        else:  # several IQ models compete for one CarNet model: never guess
            for x in lst:
                ambiguous.append({k: x[k] for k in ("iq_brand", "iq_brand_id", "iq_model", "iq_model_id")} |
                                 {"reason": "several_iq_models_map_to_one_carnet_model", "carnet_candidates": [canon]})
    return matched, unmatched, ambiguous


# ------------------------------------------------------------------ per-model comparison
def _cmp(carnet: list, iq: list, key=lambda x: x) -> dict:
    cs, is_ = {key(x) for x in carnet}, {key(x) for x in iq}
    return {"CARNET": carnet, "IQ_CARS": iq,
            "COMMON": [x for x in iq if key(x) in cs],
            "MISSING_FROM_CARNET": [x for x in iq if key(x) not in cs],
            "ONLY_IN_CARNET": [x for x in carnet if key(x) not in is_]}


def compare_model(m: dict, iq: dict, cat: dict, prof: dict) -> dict:
    b, canon = m["carnet_brand"], m["carnet_model"]
    p = prof.get((b, canon)) or {"engines": set(), "cylinders": set(), "dataset_rows": 0}
    c_trims = carnet_trims(cat, b, canon)
    c_eng = sorted(p["engines"], key=lambda d: float(d[:-1]))
    c_cyl = sorted(p["cylinders"])
    trims = _cmp(c_trims, iq["trims"])
    c_loose, i_loose = defaultdict(list), defaultdict(list)
    for t in c_trims:
        c_loose[loose_key(t)].append(t)
    for t in iq["trims"]:
        i_loose[loose_key(t)].append(t)
    cross = [{"status": "POSSIBLE_DUPLICATES", "loose_key": k, "iq": i_loose[k], "carnet": c_loose[k]}
             for k in sorted(i_loose) if k and k in c_loose and set(i_loose[k]) != set(c_loose[k])]
    trims["POSSIBLE_DUPLICATES"] = {"cross_source": cross, "within_iq": iq["possible_duplicate_trims"]}
    engines = _cmp(c_eng, iq["engine_sizes"])
    engines["IQ_CARS_VARIANTS_RAW"] = [v["raw_values"] for v in iq["engine_variants"]]
    return {
        "brand": b, "model": canon, "iq_brand_id": iq["brand_id"], "iq_model_id": iq["model_id"], "iq_model_name": iq["model"],
        "matched_via": m["via"],
        "carnet_has_data": {"trims": bool(c_trims), "engines": bool(c_eng), "cylinders": bool(c_cyl), "dataset_rows": p["dataset_rows"]},
        "iq_has_data": {"trims": bool(iq["trims"]), "engines": bool(iq["engine_sizes"]), "cylinders": bool(iq["cylinders"])},
        "TRIMS": trims, "ENGINES": engines, "CYLINDERS": _cmp(c_cyl, iq["cylinders"]),
    }


def pct(a: int, b: int) -> float:
    return round(100.0 * a / b, 1) if b else 0.0


def main() -> int:
    iq = json.loads(IQ_PATH.read_text(encoding="utf-8"))
    cat = json.loads((REPO / "assets" / "car_catalog.json").read_text(encoding="utf-8"))
    ds = json.loads((REPO / "assets" / "car_spec_dataset.json").read_text(encoding="utf-8"))
    idx = ModelIndex(cat, use_suffix_rules=True, strict_suffix_rules=True)
    prof, prof_stats = carnet_profiles(idx, ds)
    iq_models = iq["models"]
    iq_by_id = {r["model_id"]: r for r in iq_models}
    matched, unmatched, ambiguous = match_models(idx, iq_models)
    matched_carnet = {(x["carnet_brand"], x["carnet_model"]) for x in matched}
    carnet_unmatched = [{"brand": b, "model": m} for b, ms in sorted(cat["models"].items()) for m in ms if (b, m) not in matched_carnet]
    comps = [compare_model(x, iq_by_id[x["iq_model_id"]], cat, prof) for x in matched]

    def tot(dim, k):
        return sum(len(c[dim][k]) for c in comps)

    def with_data(dim, key):  # restrict to models where CarNet has data for that dimension
        return [c for c in comps if c["carnet_has_data"][key]]

    summary = {}
    for dim, key in (("TRIMS", "trims"), ("ENGINES", "engines"), ("CYLINDERS", "cylinders")):
        wd = with_data(dim, key)
        summary[dim] = {
            "values_IQ_CARS": tot(dim, "IQ_CARS"), "values_CARNET": tot(dim, "CARNET"), "COMMON": tot(dim, "COMMON"),
            "MISSING_FROM_CARNET": tot(dim, "MISSING_FROM_CARNET"), "ONLY_IN_CARNET": tot(dim, "ONLY_IN_CARNET"),
            "models_where_iq_has_values_missing_from_carnet": sum(1 for c in comps if c[dim]["MISSING_FROM_CARNET"]),
            "models_where_carnet_has_values_not_in_iq": sum(1 for c in comps if c[dim]["ONLY_IN_CARNET"]),
            "models_where_carnet_has_no_data_at_all": sum(1 for c in comps if not c["carnet_has_data"][key]),
            "restricted_to_models_where_carnet_has_data": {
                "models": len(wd),
                "MISSING_FROM_CARNET": sum(len(c[dim]["MISSING_FROM_CARNET"]) for c in wd),
                "ONLY_IN_CARNET": sum(len(c[dim]["ONLY_IN_CARNET"]) for c in wd),
                "COMMON": sum(len(c[dim]["COMMON"]) for c in wd)},
        }
    summary["TRIMS"]["POSSIBLE_DUPLICATES_cross_source_groups"] = sum(len(c["TRIMS"]["POSSIBLE_DUPLICATES"]["cross_source"]) for c in comps)
    summary["TRIMS"]["POSSIBLE_DUPLICATES_within_iq_groups"] = sum(len(c["TRIMS"]["POSSIBLE_DUPLICATES"]["within_iq"]) for c in comps)

    # ---- coverage vs CarNet
    cn_models = [(b, m) for b, ms in cat["models"].items() for m in ms]

    def cn_flags(b, m):
        p = prof.get((b, m)) or {"engines": (), "cylinders": ()}
        return bool(carnet_trims(cat, b, m)), bool(p["engines"]), bool(p["cylinders"])

    cn_f = [cn_flags(b, m) for b, m in cn_models]
    cn_cov = {"models": len(cn_models), "models_with_trims": sum(f[0] for f in cn_f), "models_with_engines": sum(f[1] for f in cn_f),
              "models_with_cylinders": sum(f[2] for f in cn_f), "models_with_all_3": sum(all(f) for f in cn_f),
              "models_with_none": sum(not any(f) for f in cn_f)}
    iq_cov = dict(iq["_meta"]["coverage"])
    for d in (cn_cov, iq_cov):
        n = d["models"]
        d["pct"] = {k: pct(d[k], n) for k in ("models_with_trims", "models_with_engines", "models_with_cylinders", "models_with_all_3", "models_with_none")}
    mm = len(comps)
    matched_cov = {"models": mm,
                   "iq_with_trims": sum(c["iq_has_data"]["trims"] for c in comps), "carnet_with_trims": sum(c["carnet_has_data"]["trims"] for c in comps),
                   "iq_with_engines": sum(c["iq_has_data"]["engines"] for c in comps), "carnet_with_engines": sum(c["carnet_has_data"]["engines"] for c in comps),
                   "iq_with_cylinders": sum(c["iq_has_data"]["cylinders"] for c in comps), "carnet_with_cylinders": sum(c["carnet_has_data"]["cylinders"] for c in comps),
                   "iq_with_all_3": sum(all(c["iq_has_data"].values()) for c in comps),
                   "carnet_with_all_3": sum(all(c["carnet_has_data"][k] for k in ("trims", "engines", "cylinders")) for c in comps)}
    matched_cov["pct"] = {k: pct(v, mm) for k, v in matched_cov.items() if k != "models"}

    matching = {
        "_meta": {"rule": "MATCHED only by exact canonical identity (ModelIndex.canonical_model); ambiguous/unmatched are never forced",
                  "counts": {"iq_models": len(iq_models), "matched": len(matched), "unmatched_iq_models": len(unmatched),
                             "ambiguous_iq_models": len(ambiguous), "carnet_models": len(cn_models),
                             "unmatched_carnet_models": len(carnet_unmatched),
                             "matched_via_alias": sum(1 for x in matched if x["via"] == "explicit_alias"),
                             "unmatched_reasons": dict(Counter(x["reason"] for x in unmatched)),
                             "ambiguous_reasons": dict(Counter(x["reason"].split(":")[0] for x in ambiguous))},
                  "carnet_dataset_resolution": prof_stats},
        "matched": sorted(matched, key=lambda x: (x["carnet_brand"], x["carnet_model"])),
        "unmatched_iq_models": unmatched, "ambiguous_iq_models": ambiguous, "unmatched_carnet_models": carnet_unmatched,
    }
    GEN.mkdir(parents=True, exist_ok=True)
    write_text_canonical(GEN / "iqcars_model_matching_report.json", json.dumps(matching, ensure_ascii=False, indent=1) + "\n")
    write_text_canonical(GEN / "iqcars_vs_carnet_comparison.json", json.dumps(
        {"_meta": {"semantics": __doc__.split("Comparison semantics")[1].strip(), "matched_models": mm, "summary": summary},
         "models": sorted(comps, key=lambda c: (c["brand"], c["model"]))}, ensure_ascii=False, indent=1) + "\n")
    write_text_canonical(GEN / "iqcars_coverage_report.json", json.dumps(
        {"IQ_CARS": iq_cov, "CARNET": cn_cov, "MATCHED_MODELS_ONLY": matched_cov, "comparison_summary": summary,
         "identity": matching["_meta"]["counts"]}, ensure_ascii=False, indent=1) + "\n")
    print(json.dumps({"identity": matching["_meta"]["counts"], "coverage": {"IQ": iq_cov, "CarNet": cn_cov, "matched": matched_cov},
                      "summary": summary}, ensure_ascii=False, indent=1))
    return 0


if __name__ == "__main__":
    sys.exit(main())
