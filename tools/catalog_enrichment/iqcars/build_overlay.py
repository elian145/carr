#!/usr/bin/env python3
"""Build the CarNet <- IQ Cars CANDIDATE OVERLAY (ADDITIVE, MODEL-LEVEL, NOT CONNECTED TO THE APP).

READ-ONLY on assets/ and on raw/ + generated/iqcars_model_options.json. Writes only under iqcars/generated/:

  carnet_iqcars_overlay_candidate.json            the overlay (additions only)
  carnet_iqcars_overlay_summary.json              A. overlay summary
  carnet_iqcars_overlay_exclusions.json           B. everything that was left out, and why
  carnet_iqcars_overlay_possible_duplicate_trims.json   C. possible duplicate trims (held for review, never merged)
  carnet_iqcars_overlay_high_impact.json          D. models ranked by number of additions + Iraqi-market priority models
  carnet_iqcars_overlay_samples.json / .md        before/after samples
  carnet_iqcars_overlay_validation.json           validation results (also enforced by tests)

Rules
  * ADDITIVE ONLY: a value is emitted only if it is absent from CarNet after safe normalization. Nothing is removed.
  * MODEL-LEVEL ONLY: trims_add / engine_sizes_add / cylinders_add are independent lists. No trim->engine->cylinder
    relationship is created or implied. The 58-model brand-new exact dataset is NOT merged here.
  * IDENTITY: only models matched by EXACT canonical identity (compare_carnet.match_models). Ambiguous and unmatched
    IQ models never enter the overlay; 'Toyota Land Cruiser FJ' is additionally excluded explicitly.
  * ENGINES: every IQ engine value keeps raw + normalized size + qualifier (4.5TD -> raw '4.5TD', size '4.5L', qualifier 'TD').
    The picker list `engine_sizes_add` holds sizes only. Nothing is inferred from TD/T (fuel) or from displacement (cylinders).
  * CYLINDERS: only counts IQ explicitly supplies. Unusual counts (1, 2, 16 ...) are kept but flagged, never silently dropped.
  * TRIMS: only safe normalization (done upstream). A trim that is only a punctuation/case lookalike of a CarNet trim, or of
    another IQ trim (EX.R vs EXR, 'Twin-Turbo' vs 'Twin Turbo'), is NOT added and NOT merged: it is HELD for human review.
  * UNRESTRICTED DEFAULT LISTS: IQ returns the identical full list (all 139 engines / all 10 cylinder counts) for dozens of
    unrelated models (EVs, Mirai, Bugatti-less models...). A list shared verbatim by many models carries no model-specific
    information, so it is excluded (and reported) instead of being added to CarNet.
"""
from __future__ import annotations

import hashlib
import json
import sys
from collections import Counter, defaultdict
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
sys.path.insert(0, str(HERE.parent))
from model_boundaries import ModelIndex  # noqa: E402
from compare_carnet import carnet_profiles, carnet_trims, match_models  # noqa: E402
from normalize import loose_key  # noqa: E402
from canonical_io import write_text_canonical  # noqa: E402

REPO = HERE.parents[2]
GEN = HERE / "generated"
RAW_CATALOG = HERE / "raw" / "iqcars_catalog.json"
IQ_PATH = GEN / "iqcars_model_options.json"
OUT = {
    "overlay": GEN / "carnet_iqcars_overlay_candidate.json",
    "summary": GEN / "carnet_iqcars_overlay_summary.json",
    "exclusions": GEN / "carnet_iqcars_overlay_exclusions.json",
    "dups": GEN / "carnet_iqcars_overlay_possible_duplicate_trims.json",
    "impact": GEN / "carnet_iqcars_overlay_high_impact.json",
    "samples_json": GEN / "carnet_iqcars_overlay_samples.json",
    "samples_md": GEN / "carnet_iqcars_overlay_samples.md",
    "validation": GEN / "carnet_iqcars_overlay_validation.json",
}

# Explicit exclusions on top of the automatic ambiguity detection (until reviewed by a human).
EXPLICIT_EXCLUSIONS = {("Toyota", "Land Cruiser FJ"): "explicitly excluded until reviewed (near-sibling of Toyota Land Cruiser)"}
# Value-level quarantine: an IQ cylinder count that contradicts better evidence is kept in the raw IQ response and in the audit/
# provenance, but is never proposed and never exported to the runtime overlay. (brand, model) -> {count: reason}.
QUARANTINED_CYLINDERS = {
    ("Geely", "Cityray"): {3: "IQ used-car cylinder list [3] is disjoint from the exact brand-new dataset [4] and from CarNet [4]"},
}
PLACEHOLDER_TRIMS = {"other", ""}
TYPICAL_CYLINDERS = {3, 4, 5, 6, 8, 10, 12}   # outside this set => kept, but flagged UNUSUAL_CYLINDER_COUNT
DEFAULT_DUMP_MIN_MODELS = 20                   # an identical list shared by >= this many models ...
DEFAULT_DUMP_MIN_LEN = 8                       # ... and at least this long, is an unrestricted default list

SAMPLE_MODELS = [("Ford", "Everest"), ("Toyota", "Land Cruiser"), ("Toyota", "Land Cruiser Prado"), ("Toyota", "Camry"),
                 ("Lexus", "LX"), ("Nissan", "Patrol"), ("BMW", "X5"), ("Volkswagen", "Golf R")]
PRIORITY_MODELS = {
    "Toyota": ["Land Cruiser", "Land Cruiser Prado", "Camry", "Corolla", "Hilux", "RAV4"],
    "Lexus": ["LX", "GX", "RX", "ES"],
    "Ford": ["Everest", "Explorer", "Expedition", "F-150"],
    "Chevrolet": ["Tahoe", "Suburban", "Silverado", "Camaro"],
    "Nissan": ["Patrol", "Sunny", "Altima", "X-Trail"],
    "BMW": ["X1", "X3", "X5", "3-Series", "5-Series"],
    "Volkswagen": ["Golf", "Golf R", "Tiguan"],
}


def sha256(p: Path) -> str:
    return hashlib.sha256(p.read_bytes()).hexdigest()


def dump(obj) -> str:
    return json.dumps(obj, ensure_ascii=False, indent=1) + "\n"


# ------------------------------------------------------------------ unrestricted default lists
def default_dump_signatures(models: list[dict]) -> dict:
    """Signatures (sorted ID tuples) of engine / cylinder lists shared verbatim by many models."""
    out = {}
    for kind, recs, idkey in (("engines", "engine_records", "engine_id"), ("cylinders", "cylinder_records", "cylinder_id")):
        c = Counter(tuple(sorted(r[idkey] for r in m[recs])) for m in models)
        out[kind] = {sig: n for sig, n in c.items() if len(sig) >= DEFAULT_DUMP_MIN_LEN and n >= DEFAULT_DUMP_MIN_MODELS}
    return out


# ------------------------------------------------------------------ per-model overlay entry
def _size_key(s: str) -> float:
    return float(s[:-1])


def build_entry(m: dict, iq: dict, cat: dict, prof: dict, dumps: dict) -> tuple[dict, dict]:
    """Returns (entry, diagnostics). `entry` may be empty of additions; the caller decides about inclusion."""
    b, model = m["carnet_brand"], m["carnet_model"]
    p = prof.get((b, model)) or {"engines": set(), "cylinders": set()}
    c_trims = carnet_trims(cat, b, model)
    c_eng = sorted(p["engines"], key=_size_key)
    c_cyl = sorted(p["cylinders"])
    diag = {"brand": b, "model": model, "iq_model_id": iq["model_id"], "carnet": {"trims": c_trims, "engine_sizes": c_eng, "cylinders": c_cyl},
            "excluded": [], "held_trims": [], "warnings": []}

    # ---------------- trims
    c_set = set(c_trims)
    c_loose: dict[str, list[str]] = defaultdict(list)
    for t in c_trims:
        c_loose[loose_key(t)].append(t)
    within = {}  # trim name -> duplicate group (names) inside IQ
    for g in iq["possible_duplicate_trims"]:
        for n in g["names"]:
            within[n] = g
    by_name = defaultdict(list)
    for r in iq["trim_records"]:
        if not r.get("excluded_from_union"):
            by_name[r["trim_name_normalized"]].append(r)
    trims_add, trims_add_records, seen = [], [], set()
    for t in iq["trims"]:
        if t in seen:
            continue
        seen.add(t)
        if t.casefold() in PLACEHOLDER_TRIMS:
            diag["excluded"].append({"kind": "placeholder_trim", "value": t})
            continue
        if t in c_set:
            continue  # already in CarNet after normalization
        lk = loose_key(t)
        if lk and lk in c_loose:
            diag["held_trims"].append({"kind": "cross_source", "iq_trim": t, "carnet_lookalikes": c_loose[lk], "loose_key": lk,
                                       "iq_trim_ids": [r["trim_id"] for r in by_name.get(t, [])]})
            continue
        if t in within:
            g = within[t]
            diag["held_trims"].append({"kind": "within_iq", "iq_trim": t, "iq_group": g["names"], "loose_key": g["loose_key"],
                                       "iq_trim_ids": [r["trim_id"] for r in by_name.get(t, [])]})
            continue
        trims_add.append(t)
        trims_add_records.append({"name": t, "iq_trim_ids": [r["trim_id"] for r in by_name.get(t, [])],
                                  "from_year": min([r["from_year"] for r in by_name.get(t, []) if r.get("from_year")] or [None], default=None),
                                  "to_year": (None if any(r.get("to_year") in (None, 0) for r in by_name.get(t, []))
                                              else max([r["to_year"] for r in by_name.get(t, [])], default=None))})

    # ---------------- engines
    engine_sizes_add, variants_add, variants_existing = [], [], []
    eng_sig = tuple(sorted(r["engine_id"] for r in iq["engine_records"]))
    if iq["engine_records"] and eng_sig in dumps["engines"]:
        diag["excluded"].append({"kind": "unrestricted_default_engine_list", "values": len(eng_sig),
                                 "shared_by_models": dumps["engines"][eng_sig]})
    else:
        for r in iq["engine_records"]:
            if not r["parsed"]:
                diag["excluded"].append({"kind": "unparsed_engine_value", "raw": r["raw"], "engine_id": r["engine_id"]})
        sizes = sorted({r["displacement_normalized"] for r in iq["engine_records"] if r["parsed"]}, key=_size_key)
        engine_sizes_add = [s for s in sizes if s not in set(c_eng)]
        for v in iq["engine_variants"]:
            row = {"size": v["display"], "raw_values": list(v["raw_values"]), "qualifier": v["qualifier"], "iq_engine_ids": list(v["engine_ids"])}
            (variants_add if v["display"] in engine_sizes_add else variants_existing).append(row)
    # ---------------- cylinders
    # `cylinders` = the FULL approved IQ set for the model (what the runtime overlay carries; the app computes
    # CarNet-baseline UNION this set itself). `cylinders_add` = the diff against the TOOLING's CarNet baseline, kept for
    # reports only -- it must never be the runtime payload because the app's own baseline can differ (e.g. empty).
    cylinders_add, cylinders_full = [], []
    cylinders_add_unquarantined = []  # the pre-quarantine diff: decides the export SCOPE (engines/trims) only
    cyl_sig = tuple(sorted(r["cylinder_id"] for r in iq["cylinder_records"]))
    if iq["cylinder_records"] and cyl_sig in dumps["cylinders"]:
        diag["excluded"].append({"kind": "unrestricted_default_cylinder_list", "values": len(cyl_sig),
                                 "shared_by_models": dumps["cylinders"][cyl_sig]})
    else:
        for r in iq["cylinder_records"]:
            if not r["parsed"]:
                diag["excluded"].append({"kind": "unparsed_cylinder_value", "raw": r["raw"], "cylinder_id": r["cylinder_id"]})
        quarantined = QUARANTINED_CYLINDERS.get((b, model), {})
        approved = {r["count"] for r in iq["cylinder_records"] if r["parsed"]}
        cylinders_add_unquarantined = sorted(approved - set(c_cyl))
        for c in sorted(approved & set(quarantined)):
            diag["excluded"].append({"kind": "quarantined_cylinder_value", "value": c, "reason": quarantined[c]})
        approved -= set(quarantined)
        cylinders_full = sorted(approved)
        cylinders_add = sorted(approved - set(c_cyl))
    for c in cylinders_add:
        if c not in TYPICAL_CYLINDERS:
            diag["warnings"].append({"kind": "UNUSUAL_CYLINDER_COUNT", "value": c, "note": "kept; supplied explicitly by IQ Cars; review"})

    cyl_ids = {r["count"]: r["cylinder_id"] for r in iq["cylinder_records"] if r["parsed"]}
    entry = {
        "brand": b, "model": model, "iq_brand_id": iq["brand_id"], "iq_model_id": iq["model_id"], "iq_model_name": iq["model"],
        "matched_via": m["via"],
        "trims_add": trims_add,
        "trims_add_details": trims_add_records,
        "engine_sizes_add": engine_sizes_add,
        "engine_variants": variants_add,
        # "cylinders_only": the model has no trim/engine-size/cylinder DIFF (nothing to add against the tooling's CarNet
        # baseline), so before format 3 it had no runtime entry at all. It now carries its full approved cylinder set
        # (and nothing else) so the app never depends on the tooling baseline equalling its own.
        "cylinders_only": not (trims_add or engine_sizes_add or cylinders_add_unquarantined),
        "cylinders": cylinders_full,
        "cylinders_iq_ids": {str(c): cyl_ids[c] for c in cylinders_full},
        "cylinders_add": cylinders_add,
        "cylinders_add_iq_ids": {str(c): cyl_ids[c] for c in cylinders_add},
        "warnings": diag["warnings"],
        "held_trims_for_review": diag["held_trims"],
        "informational_engine_variants_on_sizes_carnet_already_has": variants_existing,
        "relationships": "none (model-level independent lists; no trim/engine/cylinder links)",
    }
    return entry, diag


def n_additions(e: dict) -> int:
    return len(e["trims_add"]) + len(e["engine_sizes_add"]) + len(e["cylinders_add"])


# ------------------------------------------------------------------ the whole build
def build(iq: dict, cat: dict, ds: dict, idx: ModelIndex | None = None) -> dict:
    idx = idx or ModelIndex(cat, use_suffix_rules=True, strict_suffix_rules=True)
    prof, _ = carnet_profiles(idx, ds)
    iq_models = iq["models"]
    iq_by_id = {r["model_id"]: r for r in iq_models}
    matched, unmatched, ambiguous = match_models(idx, iq_models)
    dumps = default_dump_signatures(iq_models)

    explicit = [x for x in matched if (x["carnet_brand"], x["carnet_model"]) in EXPLICIT_EXCLUSIONS or
                (x["iq_brand"], x["iq_model"]) in EXPLICIT_EXCLUSIONS]
    matched_ok = [x for x in matched if x not in explicit]
    explicit_all = [{"iq_brand": x["iq_brand"], "iq_model": x["iq_model"], "iq_model_id": x["iq_model_id"],
                     "reason": EXPLICIT_EXCLUSIONS.get((x["iq_brand"], x["iq_model"]), "explicit")} for x in explicit]
    # Explicit exclusions that are already ambiguous/unmatched (e.g. Land Cruiser FJ) are documented here too.
    for a in ambiguous + unmatched:
        key = (a["iq_brand"], a["iq_model"])
        if key in EXPLICIT_EXCLUSIONS:
            explicit_all.append({"iq_brand": a["iq_brand"], "iq_model": a["iq_model"], "iq_model_id": a["iq_model_id"],
                                 "reason": EXPLICIT_EXCLUSIONS[key], "also_reported_as": a["reason"]})

    entries, diags, no_add = [], {}, []
    for x in sorted(matched_ok, key=lambda x: (x["carnet_brand"], x["carnet_model"])):
        e, d = build_entry(x, iq_by_id[x["iq_model_id"]], cat, prof, dumps)
        diags[(e["brand"], e["model"])] = d
        if n_additions(e) or e["cylinders"] or not e["cylinders_only"]:
            entries.append(e)
        else:
            no_add.append({"brand": e["brand"], "model": e["model"], "iq_model_id": e["iq_model_id"],
                           "held_trims": len(d["held_trims"]), "excluded_items": [i["kind"] for i in d["excluded"]]})
    return {"entries": entries, "diags": diags, "no_additions": no_add, "matched": matched, "matched_ok": matched_ok,
            "unmatched": unmatched, "ambiguous": ambiguous, "explicit": explicit_all, "dumps": dumps, "idx": idx,
            "iq_by_id": iq_by_id}


# ------------------------------------------------------------------ reports
def make_reports(res: dict, iq: dict, cat: dict, input_hashes: dict) -> dict:
    entries, diags = res["entries"], res["diags"]
    tot = {"trims_add": sum(len(e["trims_add"]) for e in entries),
           "engine_sizes_add": sum(len(e["engine_sizes_add"]) for e in entries),
           "engine_variants_on_added_sizes": sum(len(e["engine_variants"]) for e in entries),
           "cylinders_add": sum(len(e["cylinders_add"]) for e in entries)}
    held = [(b, m, h) for (b, m), d in sorted(diags.items()) for h in d["held_trims"]]
    dump_eng = sorted(({"brand": d["brand"], "model": d["model"], "iq_model_id": d["iq_model_id"], **i}
                       for d in diags.values() for i in d["excluded"] if i["kind"] == "unrestricted_default_engine_list"),
                      key=lambda r: (r["brand"], r["model"]))
    dump_cyl = sorted(({"brand": d["brand"], "model": d["model"], "iq_model_id": d["iq_model_id"], **i}
                       for d in diags.values() for i in d["excluded"] if i["kind"] == "unrestricted_default_cylinder_list"),
                      key=lambda r: (r["brand"], r["model"]))
    unparsed = sorted(({"brand": d["brand"], "model": d["model"], "iq_model_id": d["iq_model_id"], **i}
                       for d in diags.values() for i in d["excluded"] if i["kind"].startswith(("unparsed", "placeholder"))),
                      key=lambda r: (r["brand"], r["model"], r["kind"]))
    unusual = sorted(({"brand": e["brand"], "model": e["model"], **w} for e in entries for w in e["warnings"]),
                     key=lambda r: (r["brand"], r["model"], r["value"]))

    summary = {
        "status": "CANDIDATE - NOT connected to CarNet; additive; model-level only",
        "inputs_sha256": input_hashes,
        "models": {
            "iq_models": len(iq["models"]), "matched_exact_identity": len(res["matched"]),
            "eligible_after_explicit_exclusions": len(res["matched_ok"]),
            "included_in_overlay": len(res["entries"]), "matched_but_no_additions": len(res["no_additions"]),
            "excluded_ambiguous": len(res["ambiguous"]), "excluded_unmatched": len(res["unmatched"]),
            "excluded_explicit": len(res["explicit"]),
            "total_not_in_overlay": len(iq["models"]) - len(res["entries"]),
        },
        "additions": tot,
        "models_with_additions_by_dimension": {
            "trims": sum(1 for e in entries if e["trims_add"]), "engine_sizes": sum(1 for e in entries if e["engine_sizes_add"]),
            "cylinders": sum(1 for e in entries if e["cylinders_add"]),
            "cylinders_full_approved_set": sum(1 for e in entries if e["cylinders"])},
        "held_for_review": {"trims_held": len(held), "models_with_held_trims": len({(b, m) for b, m, _ in held}),
                            "by_kind": dict(Counter(h["kind"] for _, _, h in held))},
        "unrestricted_default_lists_excluded": {
            "models_with_default_engine_list": len(dump_eng), "models_with_default_cylinder_list": len(dump_cyl),
            "note": "IQ Cars returns the identical full list (139 engines / 10 cylinder counts) for these unrelated models; it is not model-specific information"},
        "unusual_cylinder_counts_flagged": len(unusual),
        "unparsed_or_placeholder_values_excluded": len(unparsed),
        "rules": __doc__.split("Rules")[1].strip(),
    }
    exclusions = {
        "_meta": {"note": "Everything IQ Cars supplied that is NOT in the overlay, and why. Nothing here is considered wrong; it is simply not proposed."},
        "ambiguous_iq_models": sorted(res["ambiguous"], key=lambda r: (r["iq_brand"], r["iq_model"])),
        "unmatched_iq_models": sorted(res["unmatched"], key=lambda r: (r["iq_brand"], r["iq_model"])),
        "explicitly_excluded_models": res["explicit"],
        "unrestricted_default_engine_lists": dump_eng,
        "unrestricted_default_cylinder_lists": dump_cyl,
        "unparsed_or_placeholder_values": unparsed,
        "quarantined_cylinder_values": sorted(
            ({"brand": d["brand"], "model": d["model"], "iq_model_id": d["iq_model_id"], "value": i["value"], "reason": i["reason"]}
             for d in diags.values() for i in d["excluded"] if i["kind"] == "quarantined_cylinder_value"),
            key=lambda r: (r["brand"], r["model"], r["value"])),
        "trims_held_for_review": [{"brand": b, "model": m, **h} for b, m, h in held],
        "matched_models_with_no_additions": res["no_additions"],
        "counts": {k: v for k, v in summary["models"].items()} | {
            "default_engine_list_models": len(dump_eng), "default_cylinder_list_models": len(dump_cyl),
            "trims_held": len(held), "unparsed_or_placeholder": len(unparsed)},
    }
    dup_groups = []
    for b, m, h in held:
        dup_groups.append({"brand": b, "model": m, "status": "POSSIBLE_DUPLICATES_HELD_FOR_REVIEW", **h})
    dups = {"_meta": {"rule": "Never auto-merged. The IQ trim in a possible-duplicate relationship is neither added nor merged until a human decides.",
                      "cross_source_groups": sum(1 for h in dup_groups if h["kind"] == "cross_source"),
                      "within_iq_trims_held": sum(1 for h in dup_groups if h["kind"] == "within_iq")},
            "groups": dup_groups}
    ranked = sorted(entries, key=lambda e: (-n_additions(e), e["brand"], e["model"]))
    by_key = {(e["brand"], e["model"]): e for e in entries}
    matched_keys = {(x["carnet_brand"], x["carnet_model"]) for x in res["matched"]}
    rank_of = {(e["brand"], e["model"]): i + 1 for i, e in enumerate(ranked)}
    prio = []
    for b, ms in PRIORITY_MODELS.items():
        for mname in ms:
            in_cat = mname in cat["models"].get(b, [])
            e = by_key.get((b, mname))
            if e is not None:
                status = "included_in_overlay"
            elif (b, mname) in diags:
                status = "matched_but_no_additions"
            elif (b, mname) in matched_keys:
                status = "matched_but_explicitly_excluded"
            elif in_cat:
                status = "no_exact_iq_match_in_carnet_catalog"
            else:
                status = "exact_name_not_in_carnet"
            prio.append({"brand": b, "model": mname, "status": status, "exact_name_in_carnet": in_cat, "matched_to_iq": (b, mname) in matched_keys,
                         "in_overlay": e is not None, "rank": rank_of.get((b, mname)),
                         "additions": None if e is None else {"trims": len(e["trims_add"]), "engine_sizes": len(e["engine_sizes_add"]),
                                                              "cylinders": len(e["cylinders_add"]), "total": n_additions(e)},
                         "held_trims": len(diags[(b, mname)]["held_trims"]) if (b, mname) in diags else None,
                         "note": None if in_cat else "exact canonical name not found in CarNet (not substituted)"})
    impact = {"_meta": {"ranking": "by total additions (trims + engine sizes + cylinders); ties by brand, model"},
              "top_models": [{"rank": i + 1, "brand": e["brand"], "model": e["model"], "total": n_additions(e), "trims": len(e["trims_add"]),
                              "engine_sizes": len(e["engine_sizes_add"]), "cylinders": len(e["cylinders_add"])} for i, e in enumerate(ranked[:100])],
              "priority_models": prio}
    return {"summary": summary, "exclusions": exclusions, "dups": dups, "impact": impact}


def sample_for(res: dict, iq: dict, key: tuple[str, str]) -> dict:
    d = res["diags"].get(key)
    if d is None:
        return {"brand": key[0], "model": key[1], "status": "not in eligible matched set"}
    iq_rec = res["iq_by_id"][d["iq_model_id"]]
    e = next((x for x in res["entries"] if (x["brand"], x["model"]) == key), None)
    return {
        "brand": key[0], "model": key[1], "iq_model_id": d["iq_model_id"],
        "CURRENT_CARNET": d["carnet"],
        "IQ_CARS": {"trims": iq_rec["trims"], "engine_sizes": iq_rec["engine_sizes"],
                    "engine_variants_raw": [{"size": v["display"], "qualifier": v["qualifier"], "raw": v["raw_values"]} for v in iq_rec["engine_variants"]],
                    "cylinders": iq_rec["cylinders"]},
        "PROPOSED_ADDITIONS": None if e is None else {k: e[k] for k in ("trims_add", "engine_sizes_add", "engine_variants", "cylinders_add")},
        "POSSIBLE_DUPLICATES_AND_WARNINGS": {"held_trims_for_review": d["held_trims"], "warnings": d["warnings"], "excluded": d["excluded"],
                                              "within_iq_possible_duplicates": iq_rec["possible_duplicate_trims"]},
    }


def samples_markdown(samples: list[dict]) -> str:
    L = ["# IQ Cars overlay - before/after samples (CANDIDATE, not integrated)", ""]
    for s in samples:
        L += [f"## {s['brand']} {s['model']}", ""]
        if "CURRENT_CARNET" not in s:
            L += [s.get("status", ""), ""]
            continue
        c, q, p, w = s["CURRENT_CARNET"], s["IQ_CARS"], s["PROPOSED_ADDITIONS"], s["POSSIBLE_DUPLICATES_AND_WARNINGS"]
        L += ["**CURRENT CARNET**", f"- trims ({len(c['trims'])}): {', '.join(c['trims']) or '-'}",
              f"- engine sizes: {', '.join(c['engine_sizes']) or '-'}", f"- cylinders: {', '.join(map(str, c['cylinders'])) or '-'}", "",
              "**IQ CARS**", f"- trims ({len(q['trims'])}): {', '.join(q['trims']) or '-'}",
              f"- engine sizes: {', '.join(q['engine_sizes']) or '-'}",
              f"- engine variants (raw): {', '.join('/'.join(v['raw']) + (' [' + v['qualifier'] + ']' if v['qualifier'] else '') for v in q['engine_variants_raw']) or '-'}",
              f"- cylinders: {', '.join(map(str, q['cylinders'])) or '-'}", "", "**PROPOSED ADDITIONS**"]
        if p is None:
            L += ["- (none)"]
        else:
            L += [f"- trims ({len(p['trims_add'])}): {', '.join(p['trims_add']) or '-'}",
                  f"- engine sizes: {', '.join(p['engine_sizes_add']) or '-'}",
                  f"- engine variants kept: {', '.join('/'.join(v['raw_values']) + ('[' + v['qualifier'] + ']' if v['qualifier'] else '') for v in p['engine_variants']) or '-'}",
                  f"- cylinders: {', '.join(map(str, p['cylinders_add'])) or '-'}"]
        L += ["", "**POSSIBLE DUPLICATES / WARNINGS**"]
        items = []
        for h in w["held_trims_for_review"]:
            items.append(f"- HELD ({h['kind']}): `{h['iq_trim']}` ~ {h.get('carnet_lookalikes') or h.get('iq_group')}")
        for x in w["warnings"]:
            items.append(f"- {x['kind']}: {x['value']}")
        for x in w["excluded"]:
            items.append(f"- EXCLUDED {x['kind']}" + (f" ({x.get('values')} values shared by {x.get('shared_by_models')} models)" if 'values' in x else ""))
        L += items or ["- none"]
        L.append("")
    return "\n".join(L) + "\n"


# ------------------------------------------------------------------ validation
def validate(res: dict, iq: dict, cat: dict, raw: dict) -> dict:
    idx = res["idx"]
    entries = res["entries"]
    checks, fails = {}, []

    def check(name, ok, detail=None):
        checks[name] = bool(ok)
        if not ok:
            fails.append({"check": name, "detail": detail})

    ambiguous_ids = {a["iq_model_id"] for a in res["ambiguous"]}
    unmatched_ids = {a["iq_model_id"] for a in res["unmatched"]}
    ids = [e["iq_model_id"] for e in entries]
    check("no_unmatched_iq_model_in_overlay", not (set(ids) & unmatched_ids), sorted(set(ids) & unmatched_ids))
    check("no_ambiguous_iq_model_in_overlay", not (set(ids) & ambiguous_ids), sorted(set(ids) & ambiguous_ids))
    check("land_cruiser_fj_not_in_overlay", not any(e["iq_model_name"] == "Land Cruiser FJ" for e in entries))
    check("one_overlay_entry_per_iq_model", len(ids) == len(set(ids)))
    check("one_overlay_entry_per_carnet_model", len({(e["brand"], e["model"]) for e in entries}) == len(entries))
    # identity: overlay model must be the exact canonical CarNet model of the IQ model
    bad = [e for e in entries if idx.canonical_model(e["brand"], e["iq_model_name"]) != e["model"] or e["model"] not in cat["models"].get(e["brand"], [])]
    check("overlay_model_is_exact_canonical_identity", not bad, [(e["brand"], e["model"]) for e in bad])
    # additive only / no duplicates
    dup, present = [], []
    for e in entries:
        d = res["diags"][(e["brand"], e["model"])]["carnet"]
        for k, ck in (("trims_add", "trims"), ("engine_sizes_add", "engine_sizes"), ("cylinders_add", "cylinders")):
            if len(e[k]) != len(set(e[k])):
                dup.append((e["brand"], e["model"], k))
            if set(e[k]) & set(d[ck]):
                present.append((e["brand"], e["model"], k))
    check("no_duplicate_additions", not dup, dup)
    check("no_addition_already_in_carnet", not present, present)
    # sibling isolation: every addition must trace back to the model's own IQ ids in the RAW data
    raw_models = {}
    for br in raw["initial_data_brands"]:
        for mo in br.get("Models") or []:
            raw_models[mo["ID"]] = {s["ID"] for s in (mo.get("ModelSFXes") or [])}
    leaks = []
    seen_trim_ids: dict[int, int] = {}
    for e in entries:
        resp = raw["cylinder_engine_by_model_id"].get(str(e["iq_model_id"])) or {}
        raw_eng = {x["ID"] for x in resp.get("Engines") or []}
        raw_cyl = {x["ID"] for x in resp.get("Cylinders") or []}
        for t in e["trims_add_details"]:
            for tid in t["iq_trim_ids"]:
                if tid not in raw_models.get(e["iq_model_id"], set()):
                    leaks.append((e["brand"], e["model"], "trim", tid))
                if tid in seen_trim_ids and seen_trim_ids[tid] != e["iq_model_id"]:
                    leaks.append((e["brand"], e["model"], "trim_shared_with_other_model", tid))
                seen_trim_ids[tid] = e["iq_model_id"]
        for v in e["engine_variants"]:
            for eid in v["iq_engine_ids"]:
                if eid not in raw_eng:
                    leaks.append((e["brand"], e["model"], "engine", eid))
        for c, cid in {**e["cylinders_iq_ids"], **e["cylinders_add_iq_ids"]}.items():
            if cid not in raw_cyl:
                leaks.append((e["brand"], e["model"], "cylinder", cid))
    check("every_addition_traces_to_own_iq_model_in_raw", not leaks, leaks[:20])
    # engine variants: size + qualifier + raw preserved, and consistent with the raw string
    badv = []
    for e in entries:
        for v in e["engine_variants"]:
            if not v["raw_values"] or v["size"] not in e["engine_sizes_add"]:
                badv.append((e["brand"], e["model"], v))
    check("engine_variants_have_raw_and_belong_to_added_sizes", not badv, badv[:5])
    # no trim/engine/cylinder link fields anywhere
    check("no_relationship_fields", all("relationships" in e and not any(k in e for k in ("trim_engine", "engine_cylinder", "links")) for e in entries))
    return {"checks": checks, "failures": fails, "ok": not fails}


# ------------------------------------------------------------------ main
def run() -> dict:
    iq = json.loads(IQ_PATH.read_text(encoding="utf-8"))
    cat = json.loads((REPO / "assets" / "car_catalog.json").read_text(encoding="utf-8"))
    ds = json.loads((REPO / "assets" / "car_spec_dataset.json").read_text(encoding="utf-8"))
    raw = json.loads(RAW_CATALOG.read_text(encoding="utf-8"))
    hashes = {"raw/iqcars_catalog.json": sha256(RAW_CATALOG), "generated/iqcars_model_options.json": sha256(IQ_PATH),
              "assets/car_catalog.json": sha256(REPO / "assets" / "car_catalog.json"),
              "assets/car_spec_dataset.json": sha256(REPO / "assets" / "car_spec_dataset.json")}
    res = build(iq, cat, ds)
    rep = make_reports(res, iq, cat, hashes)
    val = validate(res, iq, cat, raw)
    samples = [sample_for(res, iq, k) for k in SAMPLE_MODELS]
    overlay = {
        "_meta": {
            "name": "carnet_iqcars_overlay_candidate", "status": "CANDIDATE - not connected to the app; do not merge without review",
            "semantics": ("ADDITIVE, MODEL-LEVEL. Each entry lists only values that IQ Cars supplies and CarNet lacks (after safe normalization). "
                          "trims_add / engine_sizes_add / cylinders_add are INDEPENDENT lists; no trim->engine->cylinder relationship is implied. "
                          "Nothing is ever removed from CarNet."),
            "inputs_sha256": hashes, "models_in_overlay": len(res["entries"]),
            "totals": rep["summary"]["additions"],
            "engine_notes": "engine_variants keep raw value + size + qualifier (e.g. raw '4.5TD' -> size '4.5L', qualifier 'TD'); no fuel/cylinder inference.",
            "cylinder_notes": "integers, as CarNet represents them; only counts explicitly supplied by IQ Cars.",
        },
        "models": res["entries"],
    }
    return {"overlay": overlay, "reports": rep, "validation": val, "samples": samples, "result": res}


def write_all(out: dict) -> None:
    GEN.mkdir(parents=True, exist_ok=True)
    write_text_canonical(OUT["overlay"], dump(out["overlay"]))
    write_text_canonical(OUT["summary"], dump(out["reports"]["summary"]))
    write_text_canonical(OUT["exclusions"], dump(out["reports"]["exclusions"]))
    write_text_canonical(OUT["dups"], dump(out["reports"]["dups"]))
    write_text_canonical(OUT["impact"], dump(out["reports"]["impact"]))
    write_text_canonical(OUT["samples_json"], dump(out["samples"]))
    write_text_canonical(OUT["samples_md"], samples_markdown(out["samples"]))
    write_text_canonical(OUT["validation"], dump(out["validation"]))


def main() -> int:
    before = {p: sha256(p) for p in (RAW_CATALOG, IQ_PATH)}
    out = run()
    write_all(out)
    after = {p: sha256(p) for p in (RAW_CATALOG, IQ_PATH)}
    out["validation"]["checks"]["raw_and_normalized_iq_inputs_unchanged"] = before == after
    print(json.dumps(out["reports"]["summary"], ensure_ascii=False, indent=1).split('"rules"')[0])
    print(json.dumps(out["validation"], ensure_ascii=False, indent=1))
    return 0 if out["validation"]["ok"] and before == after else 1


if __name__ == "__main__":
    sys.exit(main())
