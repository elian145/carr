#!/usr/bin/env python3
"""READ-ONLY audit of the Flutter model-family matcher: sibling isolation (shorter model must not absorb a longer sibling).

Compares, for every catalog model (1635):
  OLD     the matcher the app shipped before this change (legacy | hyphen-spaced | reviewed alias; NO sibling boundary)
          -- taken from a Dart dump (`--old`), and re-derived here as a parity check
  STRICT  the new matcher: OLD, minus every row that a MORE SPECIFIC catalog model of the same brand also claims
          (longest canonical model wins) -- taken from a Dart dump (`--new`), and re-derived here
  TOOLING the catalog-enrichment reference (`model_boundaries.ModelIndex.resolve`, longest canonical prefix + qualifier
          acceptance), used to prove every removed row really belongs to that sibling

Dart dumps come from tools/catalog_enrichment/iqcars/audit/effective_options_dump_test.dart.

  python tools/catalog_enrichment/iqcars/audit_family_matching.py --old OLD_DUMP.json --new NEW_DUMP.json

Writes generated/iqcars_family_matching_audit.json and .md (canonical CRLF). Nothing else is touched.
"""
from __future__ import annotations

import argparse
import json
import re
import sys
from collections import Counter, defaultdict
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
sys.path.insert(0, str(HERE.parent))
from canonical_io import write_text_canonical  # noqa: E402
from model_boundaries import ModelIndex  # noqa: E402

REPO = HERE.parents[2]
GEN = HERE / "generated"
ALIASES = {("ram", "2500"): ["2500/3500 2500"]}  # reviewed alias (mirrors _reviewedDatasetFamilyPrefixes)


def skey(s: str) -> str:
    """Dart `carSpecSpacedNameKey`."""
    return re.sub(r"\s+", " ", re.sub(r"[-_]", " ", s.lower())).strip()


def matches(brand: str, fam: str, dn: str) -> bool:
    """Dart `carSpecDatasetNameMatchesFamily`."""
    f, d = fam.strip().lower(), dn.strip().lower()
    if not f or not d:
        return False
    if d == f or d.startswith(f + " ") or d.split()[0] == f:
        return True
    fk, dk = skey(f), skey(d)
    if dk == fk or dk.startswith(fk + " "):
        return True
    flat = re.sub(r"\s+", " ", d)
    return any(flat == p or flat.startswith(p + " ") for p in ALIASES.get((skey(brand), fk), []))


def load(p: Path):
    return json.loads(Path(p).read_text(encoding="utf-8"))


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--old", required=True)
    ap.add_argument("--new", required=True)
    args = ap.parse_args()

    cat = load(REPO / "assets" / "car_catalog.json")
    ds = load(REPO / "assets" / "car_spec_dataset.json")
    old = {(m["brand"], m["model"]): m for m in load(args.old)["models"]}
    new = {(m["brand"], m["model"]): m for m in load(args.new)["models"]}
    ov = load(REPO / "assets" / "car_iqcars_overlay.json")

    brands = {b["id"]: b["name"] for b in ds["brands"]}
    rows_by_brand: dict[str, list[str]] = defaultdict(list)
    for m in ds["models"]:
        rows_by_brand[skey(brands[m["brand_id"]])].append(m["name"])
    idx = ModelIndex(cat, use_suffix_rules=True, strict_suffix_rules=True)

    def rows_of(brand):
        return sorted(rows_by_brand.get(skey(brand), []))

    # ------------------------------------------------------------ re-derive OLD / STRICT in python (parity with Dart)
    parity_fail = []
    derived_old, derived_strict, removed_owner = {}, {}, {}
    for brand, models in cat["models"].items():
        rows = rows_of(brand)
        for mo in models:
            o = [r for r in rows if matches(brand, mo, r)]
            longer = [x for x in models if skey(x).startswith(skey(mo) + " ")]
            s, rem = [], {}
            for r in o:
                owners = [x for x in longer if matches(brand, x, r)]
                if owners:
                    rem[r] = max(owners, key=lambda x: len(skey(x)))
                else:
                    s.append(r)
            derived_old[(brand, mo)], derived_strict[(brand, mo)], removed_owner[(brand, mo)] = o, s, rem
            if sorted(o) != old[(brand, mo)]["family_rows"] or sorted(s) != new[(brand, mo)]["family_rows"]:
                parity_fail.append(f"{brand}|{mo}")

    # ------------------------------------------------------------ tooling reference per model
    tool_rows: dict[tuple, list[str]] = defaultdict(list)
    tool_status: dict[tuple, dict[str, tuple]] = {}
    for brand, models in cat["models"].items():
        for r in rows_of(brand):
            res = idx.resolve(brand, r)
            tool_status[(brand, r)] = (res.status, res.model)
            if res.accepted and res.model:
                tool_rows[(brand, res.model)].append(r)

    changed = [k for k in derived_old if sorted(derived_old[k]) != sorted(derived_strict[k])]
    items = []
    for k in sorted(changed):
        brand, mo = k
        rem = removed_owner[k]
        owners = Counter(rem.values())
        tool_owner = Counter((tool_status[(brand, r)][1] or "<unresolved>") for r in rem)
        agree = all(tool_status[(brand, r)][1] == o for r, o in rem.items())
        o_, n_ = old[k], new[k]
        other_changed = [f for f in ("body", "fuel", "drive", "transmission", "seating") if o_["baseline_other"][f] != n_["baseline_other"][f]]
        if not agree:
            klass, why = "NEEDS REVIEW", "tooling resolves some removed rows to a different model than the longer catalog sibling"
        elif not derived_strict[k]:
            klass, why = "NEEDS REVIEW", "model would lose ALL its rows (coverage lost)"
        else:
            klass, why = "CLEAR SIBLING CONTAMINATION", "every removed row's longest canonical model (app and tooling) is the longer sibling"
        items.append({
            "brand": brand, "model": mo,
            "old_rows": len(derived_old[k]), "strict_rows": len(derived_strict[k]), "rows_removed": len(rem),
            "removed_rows_belong_to": dict(owners), "tooling_owner_of_removed_rows": dict(tool_owner),
            "removed_row_examples": sorted(rem)[:6],
            "old_engines": o_["baseline_engines"], "strict_engines": n_["baseline_engines"],
            "old_cylinders": o_["baseline_cylinders"], "strict_cylinders": n_["baseline_cylinders"],
            "old_other_options": o_["baseline_other"], "strict_other_options": n_["baseline_other"],
            "other_option_fields_changed": other_changed,
            "coverage_old": o_["has_coverage"], "coverage_strict": n_["has_coverage"],
            "classification": klass, "reason": why,
        })

    # ------------------------------------------------------------ strict vs tooling (qualifier quarantine NOT ported)
    kept_rows_tooling_quarantines = Counter()
    models_with_qualifier_gap = set()
    tooling_only_rows = Counter()
    for k, srows in derived_strict.items():
        trows = set(tool_rows.get(k, []))
        for r in srows:
            if r not in trows:
                st = tool_status[(k[0], r)][0]
                kept_rows_tooling_quarantines[st] += 1
                models_with_qualifier_gap.add(k)
        for r in trows - set(srows):
            tooling_only_rows[tool_status[(k[0], r)][0]] += 1

    eff_changed = lambda f: sum(1 for k in new if old[k][f] != new[k][f])  # noqa: E731
    summary = {
        "catalog_models": len(new),
        "models_whose_matched_rows_changed": len(changed),
        "models_whose_baseline_engines_changed": eff_changed("baseline_engines"),
        "models_whose_baseline_cylinders_changed": eff_changed("baseline_cylinders"),
        "models_whose_other_options_changed": sum(1 for k in new if old[k]["baseline_other"] != new[k]["baseline_other"]),
        "models_whose_coverage_changed": eff_changed("has_coverage"),
        "models_whose_effective_search_engines_changed": eff_changed("search_engines"),
        "models_whose_effective_search_cylinders_changed": eff_changed("search_cylinders"),
        "models_whose_effective_sell_cylinders_changed": eff_changed("sell_cylinders"),
        "classification": dict(Counter(i["classification"] for i in items)),
        "python_vs_dart_parity_failures": parity_fail,
        "strict_rows_total_old": sum(len(v) for v in derived_old.values()),
        "strict_rows_total_new": sum(len(v) for v in derived_strict.values()),
        "NOT_PORTED_qualifier_quarantine": {
            "note": "The tooling additionally quarantines a row when the text between the model and the engine is not a known trim/grammar "
                    "(e.g. 'Corolla Verso 1 8'). That is a separate, much broader filter; it is NOT part of the sibling boundary and is not ported.",
            "rows_kept_by_strict_but_not_accepted_by_tooling_by_tooling_status": dict(kept_rows_tooling_quarantines),
            "models_affected": len(models_with_qualifier_gap),
            "rows_accepted_by_tooling_but_not_in_strict_by_tooling_status": dict(tooling_only_rows),
        },
    }

    def stat(brand, mo):
        k = (brand, mo)
        return {"old_rows": len(derived_old[k]), "strict_rows": len(derived_strict[k]),
                "old_engines": old[k]["baseline_engines"], "strict_engines": new[k]["baseline_engines"],
                "old_cylinders": old[k]["baseline_cylinders"], "strict_cylinders": new[k]["baseline_cylinders"],
                "iq_overlay": ov.get(brand, {}).get(mo, {})}

    lc, pr = ("Toyota", "Land Cruiser"), ("Toyota", "Land Cruiser Prado")
    lc_rows, pr_rows = set(derived_strict[lc]), set(derived_strict[pr])
    lc_only_old = set(derived_old[lc]) - set(derived_old[pr])
    acceptance = {
        "Land Cruiser": stat(*lc), "Land Cruiser Prado": stat(*pr),
        "land_cruiser_strict_rows_that_are_prado_rows": sorted(r for r in lc_rows if r.lower().startswith("land cruiser prado")),
        "prado_strict_rows_that_are_land_cruiser_only_rows": sorted(r for r in pr_rows if not r.lower().startswith("land cruiser prado")),
        "land_cruiser_rows_removed_were_all_prado_named": all(r.lower().startswith("land cruiser prado") for r in removed_owner[lc]),
        "rows_shared_between_the_two_strict_sets": sorted(lc_rows & pr_rows),
        "old_land_cruiser_rows_that_were_not_prado_named": len(lc_only_old),
    }

    out = {"_meta": {"name": "iqcars_family_matching_audit", "read_only": True,
                     "algorithm": ("row R belongs to catalog model M iff M matches R (legacy: equality / '<M> ...' prefix / first token; "
                                   "hyphen-underscore->space whole-word prefix; reviewed alias) AND no catalog model of the same brand "
                                   "that is a whole-word extension of M also matches R (longest canonical model wins)")},
           "summary": summary, "land_cruiser_acceptance": acceptance, "changed_models": items}
    write_text_canonical(GEN / "iqcars_family_matching_audit.json", json.dumps(out, ensure_ascii=False, indent=1) + "\n")

    L = ["# Flutter model-family matcher: sibling isolation audit", "", "```json", json.dumps(summary, ensure_ascii=False, indent=1), "```", "",
         "## Changed models", "", "| model | old rows | strict rows | removed rows belong to | engines old -> strict | cylinders old -> strict | class |", "|---|---|---|---|---|---|---|"]
    for i in items:
        L.append(f"| {i['brand']} {i['model']} | {i['old_rows']} | {i['strict_rows']} | {i['removed_rows_belong_to']} | "
                 f"{len(i['old_engines'])} -> {len(i['strict_engines'])} | {','.join(i['old_cylinders'])} -> {','.join(i['strict_cylinders'])} | {i['classification']} |")
    write_text_canonical(GEN / "iqcars_family_matching_audit.md", "\n".join(L) + "\n")
    print(json.dumps(summary, ensure_ascii=False, indent=1))
    return 0


if __name__ == "__main__":
    sys.exit(main())
