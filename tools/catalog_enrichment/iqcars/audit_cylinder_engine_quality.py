#!/usr/bin/env python3
"""READ-ONLY data-quality audit of IQ Cars cylinder / engine data and of the app's EFFECTIVE output.

Reads (never writes anything but its own two reports):
  raw/iqcars_catalog.json                         IQ raw responses (Cylinders[] / Engines[] per model id)
  generated/iqcars_model_options.json             normalized IQ lists
  generated/carnet_iqcars_overlay_candidate.json  reviewed candidate overlay
  generated/carnet_iqcars_overlay_exclusions.json what the candidate already refuses
  generated/iqcars_model_matching_report.json     IQ model id -> CarNet Brand + Model
  generated/iqcars_vs_carnet_comparison.json      tooling's view of CarNet (canonical model mapping)
  generated/iqcars_brand_new_exact_configs.json   exact trim -> engine -> cylinder rows (58 models)
  generated/iqcars_audit_effective_options.json   what the APP resolves (Dart probe, the UI's own resolvers)
  ../../../assets/car_iqcars_overlay.json         the runtime overlay actually shipped

Writes:
  generated/iqcars_cylinder_engine_quality_audit.json
  generated/iqcars_cylinder_engine_quality_audit.md

Nothing here changes any asset, any overlay or any app code. Verdicts are REVIEW SUGGESTIONS:
  SAFE        nothing suspicious (or an unusual value independently confirmed by CarNet's own spec rows)
  REVIEW      unusual and NOT independently confirmed: a human should look (never removed automatically)
  QUARANTINE  strong evidence only: documented shared-default contamination, a repeated identical suspicious
              response that CarNet independently contradicts, a direct conflict with exact brand-new data, or a
              malformed / unparseable source value (that VALUE only)
"""
from __future__ import annotations

import hashlib
import json
import re
import sys
from collections import Counter, defaultdict
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
from canonical_io import write_text_canonical  # noqa: E402

GEN = HERE / "generated"
RAW = HERE / "raw"
ASSET = HERE.parents[2] / "assets" / "car_iqcars_overlay.json"

RARE = {1, 2, 10, 12, 16}  # legitimate for a few exotic / off-road models, but unusual for most
# --- thresholds (also written into the report) ---------------------------------------------------------
SHARED_SIG_MIN_MODELS = 3       # an identical response seen on >= this many models ...
SHARED_SIG_MIN_BRANDS = 2       # ... across >= this many distinct brands is a "shared response pattern"
ENGINE_LARGE_LIST = 12          # engine VARIANTS per model (real maximum in the overlay is 13)
ENGINE_SINGLETON_MIN_L, ENGINE_SINGLETON_MAX_L = 0.6, 8.5
QUARANTINE_SIG_MIN_MODELS = 5   # strong-evidence threshold for a repeated suspicious response ...
QUARANTINE_SIG_MIN_BRANDS = 3
QUARANTINE_SIG_CONTRADICTED = 0.5  # ... AND this share of members that have CarNet data must be contradicted by it

ENGINE_OK = re.compile(r"^(\d{1,2}\.\d{1,2})(TD|TC|T|D)?$")  # 6.75 (Rolls-Royce / Bentley V8) is a real displacement
TWO_DECIMAL = re.compile(r"^\d{1,2}\.\d{2}")


def load(p: Path):
    return json.loads(p.read_text(encoding="utf-8"))


def sig_hash(sig) -> str:
    return hashlib.sha1(json.dumps(sig, sort_keys=True).encode()).hexdigest()[:12]


def key(b, m):
    return f"{b}|{m}"


def main() -> int:
    raw = load(RAW / "iqcars_catalog.json")
    opts = load(GEN / "iqcars_model_options.json")
    cand = load(GEN / "carnet_iqcars_overlay_candidate.json")
    excl = load(GEN / "carnet_iqcars_overlay_exclusions.json")
    match = load(GEN / "iqcars_model_matching_report.json")
    comp = load(GEN / "iqcars_vs_carnet_comparison.json")
    exact = load(GEN / "iqcars_brand_new_exact_configs.json")
    eff_dump = load(GEN / "iqcars_audit_effective_options.json")
    # The Dart probe writes LF; every generated artifact is canonical CRLF (see canonical_io).
    write_text_canonical(GEN / "iqcars_audit_effective_options.json", json.dumps(eff_dump, ensure_ascii=False, indent=1) + "\n")
    asset = load(ASSET)

    cyl_by_id = raw["cylinder_engine_by_model_id"]
    brand_cat = {b["ID"]: (b.get("Category") or {}).get("ShowRoomCategoryen") for b in raw["initial_data_brands"]}
    opt_by_id = {m["model_id"]: m for m in opts["models"]}
    cand_by = {key(m["brand"], m["model"]): m for m in cand["models"]}
    comp_by = {key(m["brand"], m["model"]): m for m in comp["models"]}
    eff_by = {key(m["brand"], m["model"]): m for m in eff_dump["models"]}
    excl_cyl_ids = {e["iq_model_id"] for e in excl["unrestricted_default_cylinder_lists"]}
    excl_eng_ids = {e["iq_model_id"] for e in excl["unrestricted_default_engine_lists"]}

    exact_rows = defaultdict(list)
    for r in exact["exact_configurations"]:
        exact_rows[key(r["brand"], r["model"])].append(r)

    # ------------------------------------------------------------------ per-model record
    rows = []
    for mt in match["matched"]:
        b, m, mid = mt["carnet_brand"], mt["carnet_model"], mt["iq_model_id"]
        k = key(b, m)
        r = cyl_by_id.get(str(mid)) or {}
        o = opt_by_id.get(mid) or {}
        c = cand_by.get(k)
        cmp_ = comp_by.get(k) or {}
        e = eff_by.get(k) or {}
        a = asset.get(b, {}).get(m, {})

        raw_cyl = [(x["ID"], x["CylinderNameen"]) for x in (r.get("Cylinders") or [])]
        raw_eng = [(x["ID"], x["EngineNameen"]) for x in (r.get("Engines") or [])]
        cyl_recs = o.get("cylinder_records") or []
        eng_recs = o.get("engine_records") or []
        tool_eng = (cmp_.get("ENGINES") or {}).get("CARNET") or []

        rows.append({
            "brand": b, "model": m, "iq_brand_id": mt["iq_brand_id"], "iq_model_id": mid,
            "brand_category": brand_cat.get(mt["iq_brand_id"]),
            "iq_raw": {"cylinders": [n for _, n in raw_cyl], "cylinder_ids": [i for i, _ in raw_cyl],
                       "engines": [n for _, n in raw_eng], "engine_ids": [i for i, _ in raw_eng]},
            "iq_normalized": {
                "cylinders": sorted({x["count"] for x in cyl_recs if x.get("parsed")}),
                "cylinders_unparsed": sorted({x["raw"] for x in cyl_recs if not x.get("parsed")}),
                "engine_values": sorted({x["raw"] for x in eng_recs}),
                "engine_sizes_l": sorted({x["displacement_l"] for x in eng_recs
                                          if x.get("parsed") and x.get("displacement_l") is not None}),
                "engines_unparsed": sorted({x["raw"] for x in eng_recs if not x.get("parsed")})},
            "listed_in_default_cylinder_exclusion": mid in excl_cyl_ids,
            "listed_in_default_engine_exclusion": mid in excl_eng_ids,
            "carnet_tooling": {"cylinders": (cmp_.get("CYLINDERS") or {}).get("CARNET") or [], "engines": tool_eng,
                               "dataset_rows": (cmp_.get("carnet_has_data") or {}).get("dataset_rows")},
            "carnet_app_baseline": {"has_coverage": e.get("has_coverage"), "cylinders": e.get("baseline_cylinders") or [],
                                    "engines": e.get("baseline_engines") or []},
            "candidate": {"cylinders": (c or {}).get("cylinders", []), "cylinders_add": (c or {}).get("cylinders_add", []),
                          "engine_sizes_add": (c or {}).get("engine_sizes_add", []),
                          "engine_variants_new_size": [v["raw_values"][0] for v in (c or {}).get("engine_variants", [])]},
            "runtime_asset": {"cylinders": a.get("cylinders", []), "engine_variants_add": a.get("engine_variants_add", [])},
            "effective": {"search_cylinders": e.get("search_cylinders"), "search_engines": e.get("search_engines"),
                          "sell_cylinders": e.get("sell_cylinders"),
                          "search_cylinders_generic": e.get("search_cylinders_generic"),
                          "search_engines_generic": e.get("search_engines_generic"),
                          "sell_cylinders_generic": e.get("sell_cylinders_generic"),
                          "app_cylinders": e.get("effective_cylinders") or [], "app_engines": e.get("effective_engines") or []},
            "flags": [], "engine_flags": [], "exact_flags": [],
            "verdict": {"cylinders": "SAFE", "engines": "SAFE"},
            "reasons": {"cylinders": [], "engines": []},
            "quarantined_values": {"cylinders": [], "engines": []},
        })

    # ------------------------------------------------------------------ repeated response signatures
    def group(field_fn, label):
        g = defaultdict(list)
        for r in rows:
            g[json.dumps(field_fn(r), sort_keys=True)].append(r)
        out = []
        for s, rs in g.items():
            sig = json.loads(s)
            out.append({"kind": label, "signature": sig, "hash": sig_hash(sig), "models": len(rs),
                        "brands": len({r["brand"] for r in rs}),
                        "examples": [f'{r["brand"]} {r["model"]}' for r in sorted(rs, key=lambda r: (r["brand"], r["model"]))[:8]],
                        "_rows": rs})
        out.sort(key=lambda x: (-x["models"], str(x["signature"])))
        return out

    cyl_groups = group(lambda r: {"counts": r["iq_normalized"]["cylinders"], "unparsed": r["iq_normalized"]["cylinders_unparsed"]}, "cylinders")
    eng_groups = group(lambda r: sorted(r["iq_raw"]["engines"]), "engines")

    def has_rare(sig):
        return any(c in RARE for c in sig["counts"])

    def carnet_cyl(r):
        """CarNet's own cylinder evidence for a model: tooling (all accepted dataset rows) U app baseline."""
        return set(r["carnet_tooling"]["cylinders"]) | {int(x) for x in r["carnet_app_baseline"]["cylinders"]}

    for g in cyl_groups:
        sig = g["signature"]
        g["unusual"] = has_rare(sig)  # placeholders (EV motors) next to real counts are normal for PHEVs
        g["shared_pattern"] = g["models"] >= SHARED_SIG_MIN_MODELS and g["brands"] >= SHARED_SIG_MIN_BRANDS and g["unusual"]
        with_cn = [r for r in g["_rows"] if carnet_cyl(r)]
        contradicted = [r for r in with_cn if not set(sig["counts"]) <= carnet_cyl(r)]
        g["members_with_carnet_cylinders"] = len(with_cn)
        g["members_carnet_does_not_contain_all_iq_counts"] = len(contradicted)
        g["carnet_contradiction_share"] = round(len(contradicted) / len(with_cn), 3) if with_cn else None
        g["carnet_confirms_rare_counts_for"] = sum(1 for r in with_cn if (set(sig["counts"]) & RARE) <= carnet_cyl(r))
        g["quarantine_candidate"] = bool(
            g["shared_pattern"] and g["models"] >= QUARANTINE_SIG_MIN_MODELS and g["brands"] >= QUARANTINE_SIG_MIN_BRANDS
            and g["carnet_contradiction_share"] is not None and g["carnet_contradiction_share"] >= QUARANTINE_SIG_CONTRADICTED)
        g["known_default_list"] = g["models"] >= 20 and len(sig["counts"]) >= 8
        for r in g["_rows"]:
            r["_cyl_group"] = g
    for g in eng_groups:
        g["unusual"] = len(g["signature"]) >= 6
        g["shared_pattern"] = g["models"] >= SHARED_SIG_MIN_MODELS and g["brands"] >= SHARED_SIG_MIN_BRANDS and g["unusual"]
        g["known_default_list"] = g["models"] >= 20 and len(g["signature"]) >= 8
        for r in g["_rows"]:
            r["_eng_group"] = g

    def exact_info(r):
        er = exact_rows.get(key(r["brand"], r["model"]))
        if not er:
            return None
        cyls = sorted({x["cylinder"]["count"] for x in er if (x.get("cylinder") or {}).get("parsed")})
        engs = sorted({x["engine"]["raw"] for x in er if (x.get("engine") or {}).get("parsed")})
        pairs = defaultdict(set)
        for x in er:
            if (x.get("engine") or {}).get("parsed") and (x.get("cylinder") or {}).get("parsed"):
                pairs[x["engine"]["raw"]].add(x["cylinder"]["count"])
        return {"rows": len(er), "cylinders": cyls, "engines": engs,
                "engine_to_cylinders": {k: sorted(v) for k, v in pairs.items()}, "years": sorted({x["year"] for x in er})}

    # ------------------------------------------------------------------ flags + verdicts
    for r in rows:
        iqc = r["iq_normalized"]["cylinders"]
        base_app = [int(x) for x in r["carnet_app_baseline"]["cylinders"]]
        tool = r["carnet_tooling"]["cylinders"]
        e = r["effective"]
        g = r["_cyl_group"]
        known_cyl_default = r["listed_in_default_cylinder_exclusion"]
        cn = carnet_cyl(r)

        # ---------------- cylinders
        if e["search_cylinders_generic"]:
            r["flags"].append("GENERIC_FALLBACK_SEARCH")
        if e["sell_cylinders_generic"]:
            r["flags"].append("GENERIC_FALLBACK_SELL")
        if len(iqc) == 1 and iqc[0] in RARE:
            r["flags"].append("RARE_SINGLETON_IQ")
        if len(e["app_cylinders"]) == 1 and int(e["app_cylinders"][0]) in RARE:
            r["flags"].append("RARE_SINGLETON_EFFECTIVE")
        if tool and iqc and not set(tool) & set(iqc):
            r["flags"].append("LARGE_DISAGREEMENT_TOOLING")
        if base_app and iqc and not set(base_app) & set(iqc):
            r["flags"].append("LARGE_DISAGREEMENT_APP")
        if g["shared_pattern"] and iqc and not known_cyl_default:
            r["flags"].append("SHARED_RESPONSE_PATTERN")
        if r["brand_category"] == "Cars" and iqc and set(iqc) <= RARE:
            r["flags"].append("PASSENGER_MODEL_RARE_COUNT")
        if known_cyl_default:
            r["flags"].append("KNOWN_DEFAULT_CYLINDER_LIST")
        if r["iq_normalized"]["cylinders_unparsed"] and not known_cyl_default:
            r["flags"].append("PLACEHOLDER_OR_UNPARSEABLE_CYLINDER_VALUE")
            r["quarantined_values"]["cylinders"] = list(r["iq_normalized"]["cylinders_unparsed"])
        if set(tool) and not base_app:
            r["flags"].append("BASELINE_MISMATCH_TOOLING_HAS_APP_EMPTY")
        approved_iq = set() if known_cyl_default else set(iqc)
        dropped = sorted(approved_iq - {int(x) for x in e["app_cylinders"]})
        r["iq_cylinders_not_reaching_app"] = dropped
        if dropped:
            r["flags"].append("IQ_CYLINDERS_NOT_REACHING_APP")
        if (iqc and r["iq_normalized"]["engine_values"] and not known_cyl_default
                and all(v in r["iq_normalized"]["engines_unparsed"] for v in r["iq_normalized"]["engine_values"])):
            r["flags"].append("ENGINE_CYLINDER_CONFLICT_ELECTRIC_ENGINES_WITH_CYLINDERS")

        # ---------------- engines
        ev = r["iq_normalized"]["engine_values"]
        known_eng_default = r["listed_in_default_engine_exclusion"]
        r["engine_variant_count"] = len(ev)
        if e["search_engines_generic"]:
            r["engine_flags"].append("GENERIC_ENGINE_FALLBACK")
        if known_eng_default:
            r["engine_flags"].append("KNOWN_DEFAULT_ENGINE_LIST")
        if r["_eng_group"]["shared_pattern"] and not known_eng_default:
            r["engine_flags"].append("SHARED_ENGINE_SIGNATURE")
        if len(ev) > ENGINE_LARGE_LIST and not known_eng_default:
            r["engine_flags"].append("LARGE_ENGINE_LIST")
        if r["iq_normalized"]["engines_unparsed"] and not known_eng_default:
            r["engine_flags"].append("PLACEHOLDER_OR_NON_DISPLACEMENT_ENGINE")
            r["quarantined_values"]["engines"] = list(r["iq_normalized"]["engines_unparsed"])
        bad = [v for v in ev if v not in r["iq_normalized"]["engines_unparsed"] and not ENGINE_OK.match(v)]
        if bad and not known_eng_default:
            r["engine_flags"].append("MALFORMED_ENGINE_VALUE")
            r["malformed_engine_values"] = bad
        two_dec = [v for v in ev if TWO_DECIMAL.match(v) and not known_eng_default]
        if two_dec:
            r["engine_flags"].append("TWO_DECIMAL_DISPLACEMENT_ROUNDED")
            r["two_decimal_engine_values"] = two_dec
        sizes = r["iq_normalized"]["engine_sizes_l"]
        if len(sizes) == 1 and not known_eng_default and not (ENGINE_SINGLETON_MIN_L <= sizes[0] <= ENGINE_SINGLETON_MAX_L):
            r["engine_flags"].append("SUSPICIOUS_ENGINE_SINGLETON")
        tool_eng_l = {float(x.rstrip("L")) for x in r["carnet_tooling"]["engines"] if re.match(r"^\d+(\.\d+)?L$", x)}
        if tool_eng_l and sizes and not known_eng_default and not tool_eng_l & set(sizes):
            r["engine_flags"].append("DISJOINT_CARNET_VS_IQ_ENGINES")
        app_eng_l = {float(x.split()[0]) for x in r["carnet_app_baseline"]["engines"]}
        if app_eng_l and sizes and not known_eng_default and not app_eng_l & set(sizes):
            r["engine_flags"].append("DISJOINT_APP_BASELINE_VS_IQ_ENGINES")

        # ---------------- exact brand-new cross-check
        ex = exact_info(r)
        r["exact_brand_new"] = ex
        if ex and not known_cyl_default:
            exc = set(ex["cylinders"])
            if exc and iqc and not exc <= set(iqc):
                r["exact_flags"].append("EXACT_CYLINDER_NOT_IN_IQ_MODEL_LEVEL")
            if exc and iqc and not exc & set(iqc):
                r["exact_flags"].append("EXACT_CYLINDER_DISJOINT_FROM_IQ_MODEL_LEVEL")
            if exc and base_app and not exc <= set(base_app):
                r["exact_flags"].append("EXACT_CYLINDER_NOT_IN_APP_BASELINE")
            rare_unconfirmed = sorted((set(iqc) & RARE) - exc)
            if exc and rare_unconfirmed:
                r["exact_flags"].append("RARE_IQ_CYLINDER_NOT_CONFIRMED_BY_EXACT")
                r["exact_rare_unconfirmed"] = rare_unconfirmed
            exe = set(ex["engines"])
            if exe and ev and not exe <= set(ev):
                r["exact_flags"].append("EXACT_ENGINE_NOT_IN_IQ_MODEL_LEVEL")
            if any(len(v) > 1 for v in ex["engine_to_cylinders"].values()):
                r["exact_flags"].append("EXACT_SAME_ENGINE_MULTIPLE_CYLINDER_COUNTS")
        elif ex and known_cyl_default:
            exc = set(ex["cylinders"])
            if exc and not exc >= set(iqc):
                r["exact_flags"].append("DEFAULT_LIST_CONTRADICTED_BY_EXACT")

        # ---------------- verdicts: cylinders
        cv, cr = "SAFE", []
        rare_here = set(iqc) & RARE
        rare_confirmed = rare_here and rare_here <= cn
        if known_cyl_default:
            cv, cr = "QUARANTINE", ["known shared default cylinder list (already excluded from the overlay)"]
        elif "EXACT_CYLINDER_DISJOINT_FROM_IQ_MODEL_LEVEL" in r["exact_flags"]:
            cv, cr = "QUARANTINE", [f"IQ model-level {iqc} is disjoint from exact brand-new rows {ex['cylinders']}"
                                    + (f" (CarNet agrees with exact: {sorted(cn)})" if cn & set(ex["cylinders"]) else "")]
        elif g["quarantine_candidate"] and has_rare(g["signature"]) and not rare_confirmed:
            cv, cr = "QUARANTINE", [f"identical unusual response {g['signature']['counts']} on {g['models']} models / {g['brands']} brands, "
                                    f"CarNet contradicts it for {int(g['carnet_contradiction_share'] * 100)}% of members with CarNet data"]
        else:
            rv = []
            if "RARE_SINGLETON_IQ" in r["flags"] and not rare_confirmed:
                rv.append("RARE_SINGLETON_NOT_CONFIRMED_BY_CARNET")
            if "PASSENGER_MODEL_RARE_COUNT" in r["flags"] and not rare_confirmed:
                rv.append("PASSENGER_MODEL_RARE_COUNT_NOT_CONFIRMED_BY_CARNET")
            if "SHARED_RESPONSE_PATTERN" in r["flags"] and rare_here and not rare_confirmed:
                rv.append("SHARED_UNUSUAL_RESPONSE_NOT_CONFIRMED_BY_CARNET")
            if "LARGE_DISAGREEMENT_TOOLING" in r["flags"] or "LARGE_DISAGREEMENT_APP" in r["flags"]:
                rv.append("LARGE_DISAGREEMENT_WITH_CARNET")
            if "ENGINE_CYLINDER_CONFLICT_ELECTRIC_ENGINES_WITH_CYLINDERS" in r["flags"]:
                rv.append("ENGINE_CYLINDER_CONFLICT_ELECTRIC_ENGINES_WITH_CYLINDERS")
            if "EXACT_CYLINDER_NOT_IN_IQ_MODEL_LEVEL" in r["exact_flags"]:
                rv.append("EXACT_CYLINDER_NOT_IN_IQ_MODEL_LEVEL")
            if "RARE_IQ_CYLINDER_NOT_CONFIRMED_BY_EXACT" in r["exact_flags"] and not rare_confirmed:
                rv.append("RARE_IQ_CYLINDER_NOT_CONFIRMED_BY_EXACT")
            if rv:
                cv, cr = "REVIEW", rv
        if cv == "SAFE" and rare_here:
            cr = [f"rare count(s) {sorted(rare_here)} confirmed by CarNet's own spec rows"]
        r["verdict"]["cylinders"], r["reasons"]["cylinders"] = cv, cr

        # ---------------- verdicts: engines
        ev_v, er_ = "SAFE", []
        eg = r["_eng_group"]
        if known_eng_default:
            ev_v, er_ = "QUARANTINE", ["known shared 139-engine default list (already excluded from the overlay)"]
        elif "MALFORMED_ENGINE_VALUE" in r["engine_flags"]:
            ev_v, er_ = "QUARANTINE", ["malformed engine value in the source: " + ", ".join(r["malformed_engine_values"])]
        elif ("SHARED_ENGINE_SIGNATURE" in r["engine_flags"] and eg["models"] >= QUARANTINE_SIG_MIN_MODELS
              and eg["brands"] >= QUARANTINE_SIG_MIN_BRANDS):
            ev_v, er_ = "QUARANTINE", [f"identical {len(eg['signature'])}-engine response on {eg['models']} models / {eg['brands']} brands"]
        else:
            rv = [f for f in r["engine_flags"] if f in (
                "SHARED_ENGINE_SIGNATURE", "LARGE_ENGINE_LIST", "PLACEHOLDER_OR_NON_DISPLACEMENT_ENGINE", "SUSPICIOUS_ENGINE_SINGLETON",
                "DISJOINT_CARNET_VS_IQ_ENGINES", "DISJOINT_APP_BASELINE_VS_IQ_ENGINES", "TWO_DECIMAL_DISPLACEMENT_ROUNDED")]
            if "EXACT_ENGINE_NOT_IN_IQ_MODEL_LEVEL" in r["exact_flags"]:
                rv.append("EXACT_ENGINE_NOT_IN_IQ_MODEL_LEVEL")
            if rv:
                ev_v, er_ = "REVIEW", rv
        r["verdict"]["engines"], r["reasons"]["engines"] = ev_v, er_

        if e["search_engines_generic"]:
            if known_eng_default:
                r["generic_engine_fallback_reason"] = "IQ_RESPONSE_IS_THE_SHARED_139_ENGINE_DEFAULT_LIST (excluded)"
            elif not ev:
                r["generic_engine_fallback_reason"] = "IQ_RESPONSE_HAS_NO_ENGINES"
            elif not r["iq_normalized"]["engine_sizes_l"]:
                r["generic_engine_fallback_reason"] = "IQ_ONLY_PLACEHOLDERS (e.g. Single Motor / Dual Motor)"
            else:
                r["generic_engine_fallback_reason"] = "OTHER"

        # ---------------- why does the UI show the generic ladder?
        if e["search_cylinders_generic"]:
            if known_cyl_default:
                why = "IQ_RESPONSE_IS_THE_SHARED_DEFAULT_LIST (excluded)"
            elif dropped:
                why = "IQ_HAS_COUNTS_BUT_THEY_NEVER_REACH_THE_APP (diff-export vs empty app baseline)"
            elif not iqc and not r["iq_normalized"]["cylinders_unparsed"]:
                why = "IQ_RESPONSE_HAS_NO_CYLINDERS"
            elif not iqc:
                why = "IQ_ONLY_PLACEHOLDERS (e.g. Single Motor / Dual Motor)"
            elif set(tool) and not base_app:
                why = "APP_BASELINE_EMPTY_WHILE_TOOLING_HAS_CARNET_CYLINDERS"
            else:
                why = "OTHER"
            r["generic_fallback_reason"] = why

    # ------------------------------------------------------------------ aggregates
    def models_with(flag, field="flags"):
        return [r for r in rows if flag in r[field]]

    def brief(r):
        return f'{r["brand"]} {r["model"]}'

    cyl_flag_names = ["GENERIC_FALLBACK_SEARCH", "GENERIC_FALLBACK_SELL", "RARE_SINGLETON_IQ", "RARE_SINGLETON_EFFECTIVE",
                      "LARGE_DISAGREEMENT_TOOLING", "LARGE_DISAGREEMENT_APP", "SHARED_RESPONSE_PATTERN", "PASSENGER_MODEL_RARE_COUNT",
                      "KNOWN_DEFAULT_CYLINDER_LIST", "PLACEHOLDER_OR_UNPARSEABLE_CYLINDER_VALUE", "BASELINE_MISMATCH_TOOLING_HAS_APP_EMPTY",
                      "IQ_CYLINDERS_NOT_REACHING_APP", "ENGINE_CYLINDER_CONFLICT_ELECTRIC_ENGINES_WITH_CYLINDERS"]
    eng_flag_names = ["GENERIC_ENGINE_FALLBACK", "KNOWN_DEFAULT_ENGINE_LIST", "SHARED_ENGINE_SIGNATURE", "LARGE_ENGINE_LIST",
                      "PLACEHOLDER_OR_NON_DISPLACEMENT_ENGINE", "MALFORMED_ENGINE_VALUE", "TWO_DECIMAL_DISPLACEMENT_ROUNDED", "SUSPICIOUS_ENGINE_SINGLETON",
                      "DISJOINT_CARNET_VS_IQ_ENGINES", "DISJOINT_APP_BASELINE_VS_IQ_ENGINES"]
    exact_flag_names = ["EXACT_CYLINDER_NOT_IN_IQ_MODEL_LEVEL", "EXACT_CYLINDER_DISJOINT_FROM_IQ_MODEL_LEVEL", "EXACT_CYLINDER_NOT_IN_APP_BASELINE",
                        "RARE_IQ_CYLINDER_NOT_CONFIRMED_BY_EXACT", "EXACT_ENGINE_NOT_IN_IQ_MODEL_LEVEL",
                        "EXACT_SAME_ENGINE_MULTIPLE_CYLINDER_COUNTS", "DEFAULT_LIST_CONTRADICTED_BY_EXACT"]
    flag_counts = {f: len(models_with(f)) for f in cyl_flag_names}
    eng_flag_counts = {f: len(models_with(f, "engine_flags")) for f in eng_flag_names}
    exact_flag_counts = {f: len(models_with(f, "exact_flags")) for f in exact_flag_names}

    review_cyl = [r for r in rows if r["verdict"]["cylinders"] == "REVIEW"]
    quar_cyl = [r for r in rows if r["verdict"]["cylinders"] == "QUARANTINE"]
    quar_cyl_new = [r for r in quar_cyl if not r["listed_in_default_cylinder_exclusion"]]
    review_eng = [r for r in rows if r["verdict"]["engines"] == "REVIEW"]
    quar_eng = [r for r in rows if r["verdict"]["engines"] == "QUARANTINE"]
    quar_eng_new = [r for r in quar_eng if not r["listed_in_default_engine_exclusion"]]
    suspicious_cyl = review_cyl + quar_cyl_new
    suspicious_eng = review_eng + quar_eng_new
    has_cov = [r for r in rows if r["carnet_app_baseline"]["has_coverage"]]
    gap = [r for r in rows if not r["carnet_app_baseline"]["has_coverage"] and (r["carnet_tooling"]["dataset_rows"] or 0) > 0]

    singleton_iq, singleton_eff = Counter(), Counter()
    for r in rows:
        iqc = r["iq_normalized"]["cylinders"]
        if len(iqc) == 1 and iqc[0] in RARE:
            singleton_iq[iqc[0]] += 1
        ec = r["effective"]["app_cylinders"]
        if len(ec) == 1 and int(ec[0]) in RARE:
            singleton_eff[int(ec[0])] += 1

    generic_reasons = Counter(r["generic_fallback_reason"] for r in rows if "generic_fallback_reason" in r)
    generic_eng_reasons = Counter(r["generic_engine_fallback_reason"] for r in rows if "generic_engine_fallback_reason" in r)
    rare_models_confirmed = sum(1 for r in rows if "RARE_SINGLETON_IQ" in r["flags"] and r["verdict"]["cylinders"] == "SAFE")

    summary = {
        "catalog_models_audited": len(rows),
        "app_has_coverage": len(has_cov),
        "app_no_coverage": len(rows) - len(has_cov),
        "app_no_coverage_but_tooling_maps_carnet_dataset_rows": len(gap),
        "search_generic_cylinder_fallback_models": flag_counts["GENERIC_FALLBACK_SEARCH"],
        "sell_generic_cylinder_fallback_models": flag_counts["GENERIC_FALLBACK_SELL"],
        "search_generic_cylinder_fallback_reasons": dict(generic_reasons.most_common()),
        "search_generic_engine_fallback_models": eng_flag_counts["GENERIC_ENGINE_FALLBACK"],
        "search_generic_engine_fallback_reasons": dict(generic_eng_reasons.most_common()),
        "models_with_iq_approved_cylinder_data(parsed, not default-list)": sum(
            1 for r in rows if r["iq_normalized"]["cylinders"] and not r["listed_in_default_cylinder_exclusion"]),
        "models_whose_runtime_asset_carries_full_cylinder_set": sum(1 for r in rows if r["runtime_asset"]["cylinders"]),
        "models_where_iq_cylinders_do_not_reach_app": flag_counts["IQ_CYLINDERS_NOT_REACHING_APP"],
        "baseline_mismatch_tooling_has_app_empty": flag_counts["BASELINE_MISMATCH_TOOLING_HAS_APP_EMPTY"],
        "suspicious_cylinder_models(REVIEW + new QUARANTINE)": len(suspicious_cyl),
        "rare_singleton_iq_models": flag_counts["RARE_SINGLETON_IQ"],
        "rare_singleton_iq_by_count": dict(sorted(singleton_iq.items())),
        "rare_singleton_iq_models_confirmed_by_carnet(SAFE)": rare_models_confirmed,
        "rare_singleton_effective_models": flag_counts["RARE_SINGLETON_EFFECTIVE"],
        "rare_singleton_effective_by_count": dict(sorted(singleton_eff.items())),
        "passenger_model_rare_count_models": flag_counts["PASSENGER_MODEL_RARE_COUNT"],
        "repeated_cylinder_signatures(shared_pattern, excl. default list)": sum(
            1 for g in cyl_groups if g["shared_pattern"] and not g["known_default_list"]),
        "repeated_cylinder_signatures_incl_default_list": sum(1 for g in cyl_groups if g["shared_pattern"]),
        "suspicious_engine_models(REVIEW + new QUARANTINE)": len(suspicious_eng),
        "repeated_engine_signatures(shared_pattern, excl. default list)": sum(
            1 for g in eng_groups if g["shared_pattern"] and not g["known_default_list"]),
        "repeated_engine_signatures_incl_default_list": sum(1 for g in eng_groups if g["shared_pattern"]),
        "cylinder_verdicts": dict(Counter(r["verdict"]["cylinders"] for r in rows)),
        "engine_verdicts": dict(Counter(r["verdict"]["engines"] for r in rows)),
        "quarantine_cylinders_total_incl_already_excluded": len(quar_cyl),
        "quarantine_cylinders_NEW_recommendations": len(quar_cyl_new),
        "quarantine_engines_total_incl_already_excluded": len(quar_eng),
        "quarantine_engines_NEW_recommendations": len(quar_eng_new),
        "models_with_placeholder_cylinder_values(values-only quarantine, not exported)": flag_counts["PLACEHOLDER_OR_UNPARSEABLE_CYLINDER_VALUE"],
        "models_with_placeholder_engine_values(values-only quarantine, not exported)": eng_flag_counts["PLACEHOLDER_OR_NON_DISPLACEMENT_ENGINE"],
        "review_cylinder_models": len(review_cyl),
        "review_engine_models": len(review_eng),
        "models_with_exact_brand_new_rows": sum(1 for r in rows if r["exact_brand_new"]),
    }

    def strip(r):
        return {k: v for k, v in r.items() if not k.startswith("_")}

    def public_groups(gs, n):
        return [{k: v for k, v in g.items() if k != "_rows"} for g in gs[:n]]

    out = {
        "_meta": {
            "name": "iqcars_cylinder_engine_quality_audit",
            "status": "READ-ONLY AUDIT. Nothing here changes the runtime overlay, the candidate or any app code.",
            "thresholds": {"SHARED_SIG_MIN_MODELS": SHARED_SIG_MIN_MODELS, "SHARED_SIG_MIN_BRANDS": SHARED_SIG_MIN_BRANDS,
                           "ENGINE_LARGE_LIST": ENGINE_LARGE_LIST, "RARE_CYLINDER_COUNTS": sorted(RARE),
                           "QUARANTINE_SIG_MIN_MODELS": QUARANTINE_SIG_MIN_MODELS, "QUARANTINE_SIG_MIN_BRANDS": QUARANTINE_SIG_MIN_BRANDS,
                           "QUARANTINE_SIG_CONTRADICTED_SHARE": QUARANTINE_SIG_CONTRADICTED,
                           "ENGINE_SINGLETON_LITRES": [ENGINE_SINGLETON_MIN_L, ENGINE_SINGLETON_MAX_L]},
            "verdict_meaning": {"SAFE": "nothing suspicious, or unusual but confirmed by CarNet's own spec rows",
                                "REVIEW": "unusual and not independently confirmed; human review, never auto-removed",
                                "QUARANTINE": "strong evidence only; a recommendation, NOT applied"},
            "sources": ["raw/iqcars_catalog.json", "generated/iqcars_model_options.json", "generated/carnet_iqcars_overlay_candidate.json",
                        "generated/carnet_iqcars_overlay_exclusions.json", "generated/iqcars_model_matching_report.json",
                        "generated/iqcars_vs_carnet_comparison.json", "generated/iqcars_brand_new_exact_configs.json",
                        "generated/iqcars_audit_effective_options.json (Dart probe of the app's real resolvers)",
                        "assets/car_iqcars_overlay.json"],
        },
        "summary": summary,
        "flag_counts": {"cylinders": flag_counts, "engines": eng_flag_counts, "exact_cross_check": exact_flag_counts},
        "cylinder_signature_groups": public_groups(cyl_groups, 60),
        "engine_signature_groups": public_groups(eng_groups, 40),
        "app_vs_tooling_coverage_gap_models": [{"brand": r["brand"], "model": r["model"], "dataset_rows": r["carnet_tooling"]["dataset_rows"],
                                                "tooling_cylinders": r["carnet_tooling"]["cylinders"],
                                                "iq_cylinders": r["iq_normalized"]["cylinders"],
                                                "effective_app_cylinders": r["effective"]["app_cylinders"]} for r in gap],
        "models": [strip(r) for r in rows],
    }
    write_text_canonical(GEN / "iqcars_cylinder_engine_quality_audit.json", json.dumps(out, ensure_ascii=False, indent=1) + "\n")

    # ------------------------------------------------------------------ human summary
    L, P = [], None
    P = L.append
    P("# IQ Cars cylinder / engine quality audit (read-only)\n")
    P("Nothing in the runtime overlay, the candidate or the app was changed. Verdicts are suggestions only.\n")
    P("## Summary numbers\n")
    for k, v in summary.items():
        P(f"- **{k}**: {v}")
    P("\n## Flag counts\n")
    P("| flag | models |\n|---|---|")
    for grp, d in (("cyl", flag_counts), ("eng", eng_flag_counts), ("exact", exact_flag_counts)):
        for f, n in d.items():
            P(f"| {grp}:{f} | {n} |")
    P("\n## Repeated IQ response signatures: Cylinders[] (top 30)\n")
    P("`CarNet contradicts` = share of members that have CarNet cylinder data where that data does not contain all IQ counts.\n")
    P("| signature (counts) | placeholders | models | brands | shared | CarNet contradicts | examples |\n|---|---|---|---|---|---|---|")
    for g in cyl_groups[:30]:
        sg = g["signature"]
        cc = g["carnet_contradiction_share"]
        P(f"| {sg['counts']}{' (default list)' if g['known_default_list'] else ''} | {len(sg['unparsed'])} | {g['models']} | {g['brands']} | {g['shared_pattern']} | "
          f"{'n/a' if cc is None else str(int(cc * 100)) + '%'} | {'; '.join(g['examples'][:5])} |")
    P("\n## Repeated IQ response signatures: Engines[] (top 20)\n")
    P("| #engines | models | brands | shared | engines | examples |\n|---|---|---|---|---|---|")
    for g in eng_groups[:20]:
        sg = g["signature"]
        P(f"| {len(sg)}{' (default list)' if g['known_default_list'] else ''} | {g['models']} | {g['brands']} | {g['shared_pattern']} | "
          f"{', '.join(sg[:10])}{'...' if len(sg) > 10 else ''} | {'; '.join(g['examples'][:4])} |")
    P("\n## Generic cylinder ladder shown with Brand+Model selected: why\n")
    for k, v in generic_reasons.most_common():
        P(f"- {k}: {v}")
    P("\n## Generic engine ladder shown with Brand+Model selected: why\n")
    for k, v in generic_eng_reasons.most_common():
        P(f"- {k}: {v}")
    P("\n## App baseline empty although the tooling maps CarNet dataset rows (family-name matching gap)\n")
    for r in gap:
        P(f"- {brief(r)}: {r['carnet_tooling']['dataset_rows']} dataset rows; tooling cyl {r['carnet_tooling']['cylinders']}; IQ cyl {r['iq_normalized']['cylinders']}; app effective {r['effective']['app_cylinders']}")
    P("\n## Cylinder QUARANTINE recommendations (not already excluded)\n")
    for r in quar_cyl_new:
        P(f"- {brief(r)}: {'; '.join(r['reasons']['cylinders'])}")
    if not quar_cyl_new:
        P("- none")
    P("\n## Engine QUARANTINE recommendations (not already excluded)\n")
    for r in quar_eng_new:
        P(f"- {brief(r)}: {'; '.join(r['reasons']['engines'])}")
    if not quar_eng_new:
        P("- none")
    P("\n## Exact brand-new cross-check (58 models): flagged\n")
    for r in rows:
        if r["exact_flags"]:
            ex = r["exact_brand_new"]
            P(f"- {brief(r)}: {', '.join(r['exact_flags'])}; exact cyl {ex['cylinders']} eng {ex['engines']}; IQ cyl {r['iq_normalized']['cylinders']}; CarNet(app baseline) cyl {r['carnet_app_baseline']['cylinders']}")
    P("\n## Cylinder REVIEW models\n")
    for r in review_cyl:
        P(f"- {brief(r)}: {', '.join(r['reasons']['cylinders'])} | IQ {r['iq_normalized']['cylinders']} | app baseline {r['carnet_app_baseline']['cylinders']} | tooling {r['carnet_tooling']['cylinders']}")
    P("\n## Engine REVIEW models\n")
    for r in review_eng:
        P(f"- {brief(r)}: {', '.join(r['reasons']['engines'])} | {len(r['iq_normalized']['engine_values'])} engine values")
    write_text_canonical(GEN / "iqcars_cylinder_engine_quality_audit.md", "\n".join(L) + "\n")

    print(json.dumps(summary, indent=1))
    print(json.dumps({"flags": flag_counts, "engine": eng_flag_counts, "exact": exact_flag_counts}, indent=1))
    return 0


if __name__ == "__main__":
    sys.exit(main())
