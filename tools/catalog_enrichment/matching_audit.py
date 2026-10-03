#!/usr/bin/env python3
"""Measure and audit dataset-row -> canonical-model matching (tooling only, read-only on assets/).

Every dataset row ends in exactly one of MATCHED / QUARANTINED / UNRESOLVED, with and without the brand
suffix grammars (rules/brand_model_suffix_rules.json). Deterministic: no clocks, no randomness, no network.

  python tools/catalog_enrichment/matching_audit.py report     # writes reports/model_matching_*.json
  python tools/catalog_enrichment/matching_audit.py summary    # prints the headline numbers
  python tools/catalog_enrichment/matching_audit.py ledger OUT.tsv   # full per-row ledger (not stored in the repo)
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
import model_boundaries as mb  # noqa: E402
from model_boundaries import MATCHED, QUARANTINED, UNRESOLVED, mkey  # noqa: E402

BASELINE_COMMIT = "ac91f611525bdb49a755c66005ae2a3f8590886a"
REPORTS = HERE / "reports"

# Pairs that must never be merged (brand, shorter canonical model, longer canonical model/alias-free name).
REQUIRED_SIBLING_PAIRS = [
    ("Toyota", "Land Cruiser", "Land Cruiser Prado"),
    ("Volkswagen", "Golf", "Golf R"),
    ("Land Rover", "Discovery", "Discovery Sport"),
    ("Ford", "Bronco", "Bronco Sport"),
    ("Toyota", "Corolla", "Corolla Cross"),
    ("Toyota", "Corolla", "GR Corolla"),
    ("Mitsubishi", "Pajero", "Pajero Sport"),
    ("Volkswagen", "Passat", "Passat CC"),
    ("Renault", "Megane", "Megane GT"),
]


# --------------------------------------------------------------------------------------------------------------
def load_rows(ds: dict) -> list[dict]:
    brands = {b["id"]: b["name"] for b in ds["brands"]}
    return [{"id": m["id"], "brand": brands[m["brand_id"]], "name": m["name"]} for m in ds["models"]]


def heuristics() -> dict:
    return json.loads(mb.SUFFIX_RULES_PATH.read_text(encoding="utf-8"))["audit_heuristics"]


def shape(q: str, pw: set[str]) -> str:
    out = []
    for t in q.split():
        if re.fullmatch(r"\d+", t):
            out.append("N")
        elif re.search(r"\d", t) and re.search(r"[a-z]", t):
            out.append("A")
        elif t in pw:
            out.append("P")
        elif len(t) == 1:
            out.append("l")
        else:
            out.append("w")
    return " ".join(out) or "-"


def heuristic_class(q: str, pw: set[str]) -> str:
    """Triage only (reports). likely_powertrain_suffix / likely_sibling_or_trim_word / unclear."""
    toks = q.split()
    if not toks:
        return "unclear"
    has_digit = any(re.search(r"\d", t) for t in toks)
    unknown = [t for t in toks if re.fullmatch(r"[a-z]+", t) and len(t) > 1 and t not in pw]
    has_pw = any(t in pw for t in toks)
    if not unknown and (has_digit or has_pw):
        return "likely_powertrain_suffix"
    if unknown and not has_digit:
        return "likely_sibling_or_trim_word"
    return "unclear"


def review_category(idx: mb.ModelIndex, brand: str, model: str, q: str, h: dict) -> str:
    if idx.has_grammar(brand, model):
        return f"{re.sub(r'[^a-z]', '', brand.split('-')[0].casefold())}_unknown_suffix"
    toks = q.split()
    if any(re.search(r"\d", t) for t in toks):
        return "unknown_engine_code"
    if len(toks) <= h["unknown_trim_max_tokens"] and all(len(t) <= h["unknown_trim_max_token_len"] for t in toks):
        return "unknown_trim"
    return "possible_sibling_model"


def resolve_all(idx: mb.ModelIndex, rows: list[dict]) -> list[mb.Resolution]:
    return [idx.resolve(r["brand"], r["name"]) for r in rows]


def outcome_counts(res: list[mb.Resolution]) -> dict:
    c = Counter(r.outcome for r in res)
    return {"MATCHED": c[MATCHED], "QUARANTINED": c[QUARANTINED], "UNRESOLVED": c[UNRESOLVED], "total": len(res)}


def ledger_lines(rows, res) -> list[str]:
    return [f"{r['id']}\t{x.outcome}\t{x.status}\t{x.model or ''}\t{x.rule or ''}" for r, x in zip(rows, res)]


def ledger_sha(rows, res) -> str:
    return hashlib.sha256("\n".join(ledger_lines(rows, res)).encode("utf-8")).hexdigest()


def top(counter: Counter, n: int) -> list:
    return [[k, v] for k, v in sorted(counter.items(), key=lambda kv: (-kv[1], str(kv[0])))[:n]]


def stride_sample(items: list, n: int) -> list:
    if len(items) <= n:
        return items
    step = len(items) / n
    return [items[int(i * step)] for i in range(n)]


# --------------------------------------------------------------------------------------------------------------
def baseline_report(idx0: mb.ModelIndex, rows, res0, h) -> dict:
    pw = set(h["powertrain_words"])
    quar = [(r, x) for r, x in zip(rows, res0) if x.outcome == QUARANTINED]
    by_brand = Counter(r["brand"] for r, _ in quar)
    by_reason = Counter(x.status for _, x in quar)
    by_pattern = Counter(shape(x.qualifier, pw) for _, x in quar)
    by_first = Counter(x.qualifier.split()[0] if x.qualifier else "(none)" for _, x in quar)
    by_class = Counter(heuristic_class(x.qualifier, pw) for _, x in quar)
    by_model = Counter((r["brand"], x.model) for r, x in quar)
    groups: Counter = Counter()
    for r, x in quar:
        groups[(r["brand"], x.model, x.qualifier.split()[0] if x.qualifier else "(none)", shape(x.qualifier, pw), x.status)] += 1
    unresolved = Counter(("brand_not_in_catalog" if "brand_not_in_catalog" in x.flags else "no_canonical_model_prefix") for x in res0 if x.outcome == UNRESOLVED)
    class_by_brand: dict[str, Counter] = defaultdict(Counter)
    for r, x in quar:
        class_by_brand[r["brand"]][heuristic_class(x.qualifier, pw)] += 1
    return {
        "schema_version": "carnet.model_matching_report/1",
        "kind": "baseline",
        "baseline_commit": BASELINE_COMMIT,
        "suffix_rules_enabled": False,
        "outcomes": outcome_counts(res0),
        "dataset_status_counts": dict(Counter(x.status for x in res0)),
        "quarantined_total": len(quar),
        "quarantined_by_reason": dict(by_reason),
        "quarantined_rows_per_brand": [[b, n] for b, n in top(by_brand, len(by_brand))],
        "top_20_quarantined_brands": [
            {"brand": b, "rows": n, "pct_of_quarantined": round(100 * n / len(quar), 2), "heuristic_classes": dict(class_by_brand[b])}
            for b, n in top(by_brand, 20)
        ],
        "quarantined_rows_per_pattern": top(by_pattern, 60),
        "quarantined_rows_per_first_token_after_model": top(by_first, 60),
        "quarantined_rows_per_model_top60": [{"brand": b, "model": m, "rows": n} for (b, m), n in top(by_model, 60)],
        "triage_heuristic_classes": {
            "note": "Descriptive triage of the baseline quarantine by qualifier shape (rules/brand_model_suffix_rules.json -> audit_heuristics). NOT used for matching.",
            "likely_safe_engine_or_powertrain_suffix": by_class["likely_powertrain_suffix"],
            "likely_genuine_sibling_other_model_or_trim_word": by_class["likely_sibling_or_trim_word"],
            "unclear": by_class["unclear"],
            "unresolved_no_canonical_candidate": sum(unresolved.values()),
            "unresolved_breakdown": dict(unresolved),
        },
        "groups_brand_model_firsttoken_pattern_reason_top150": [
            {"brand": b, "model": m, "first_token": ft, "pattern": p, "reason": rs, "rows": n}
            for (b, m, ft, p, rs), n in sorted(groups.items(), key=lambda kv: (-kv[1], kv[0]))[:150]
        ],
        "group_count_total": len(groups),
    }


def collision_checks(idx1: mb.ModelIndex, rows, res1) -> dict:
    """Sibling-contamination measures for the post-rule resolver."""
    by_brand_names: dict[str, list[tuple[dict, mb.Resolution]]] = defaultdict(list)
    for r, x in zip(rows, res1):
        by_brand_names[r["brand"]].append((r, x))
    pairs = []
    total_bad = 0
    for b, short, long_ in idx1.prefix_pairs():
        sk, lk = mkey(short), mkey(long_)
        contaminated = [
            r["name"] for r, x in by_brand_names.get(b, [])
            if x.accepted and x.model == short and (mkey(r["name"]) == lk or mkey(r["name"]).startswith(lk + " "))
        ]
        total_bad += len(contaminated)
        if contaminated:
            pairs.append({"brand": b, "shorter": short, "longer": long_, "rows": len(contaminated), "examples": contaminated[:3]})
    required = []
    for b, short, long_ in REQUIRED_SIBLING_PAIRS:
        in_cat = b in idx1.models and short in idx1.models[b] and long_ in idx1.models[b]
        row = {"brand": b, "shorter": short, "longer": long_, "both_in_catalog": in_cat}
        if in_cat:
            names = by_brand_names.get(b, [])
            row["rows_matched_to_shorter"] = sum(1 for _, x in names if x.accepted and x.model == short)
            row["rows_matched_to_longer"] = sum(1 for _, x in names if x.accepted and x.model == long_)
            row["rows_matched_to_shorter_whose_name_starts_with_longer"] = sum(
                1 for r, x in names
                if x.accepted and x.model == short and (mkey(r["name"]) == mkey(long_) or mkey(r["name"]).startswith(mkey(long_) + " "))
            )
        required.append(row)
    return {
        "catalog_prefix_pairs": len(idx1.prefix_pairs()),
        "rows_matched_to_shorter_model_whose_name_starts_with_longer_sibling": total_bad,
        "contaminated_pairs": pairs,
        "required_sibling_pairs": required,
        "grammar_sibling_self_check_violations": idx1.sibling_safety_violations(),
    }


def false_match_suspects(idx1: mb.ModelIndex, rows, res1) -> list[dict]:
    """Independent check on rule-recovered rows: does the accepted qualifier contain another canonical model name of the
    same brand (token-aligned)? If so the row might really be that sibling. Expected: none."""
    out = []
    for r, x in zip(rows, res1):
        if x.status != "suffix_rule":
            continue
        qpad = f" {x.qualifier} "
        for k, canon in idx1.model_keys(r["brand"]).items():
            if canon != x.model and f" {k} " in qpad:
                out.append({"brand": r["brand"], "name": r["name"], "resolved_model": x.model, "qualifier": x.qualifier, "contains_model": canon, "rule": x.rule})
    return out


def recovery_report(idx0, idx1, rows, res0, res1, h) -> dict:
    pw = set(h["powertrain_words"])
    base_q = sum(1 for x in res0 if x.outcome == QUARANTINED)
    o0, o1 = outcome_counts(res0), outcome_counts(res1)
    recovered = [(r, x1) for r, x0, x1 in zip(rows, res0, res1) if x0.outcome != MATCHED and x1.outcome == MATCHED]
    regress = [r["name"] for r, x0, x1 in zip(rows, res0, res1) if x0.outcome == MATCHED and not (x1.outcome == MATCHED and x1.model == x0.model)]
    # rows whose resolved model changed even though both matched
    model_changed = [r["name"] for r, x0, x1 in zip(rows, res0, res1) if x0.outcome == MATCHED and x1.outcome == MATCHED and x1.model != x0.model]
    from_unresolved = [r["name"] for r, x0, x1 in zip(rows, res0, res1) if x0.outcome == UNRESOLVED and x1.outcome != UNRESOLVED]
    brand0, brand1 = defaultdict(Counter), defaultdict(Counter)
    for r, x0, x1 in zip(rows, res0, res1):
        brand0[r["brand"]][x0.outcome] += 1
        brand1[r["brand"]][x1.outcome] += 1
    improved = []
    for b in sorted(brand0):
        d = brand1[b][MATCHED] - brand0[b][MATCHED]
        if d:
            improved.append({
                "brand": b, "recovered_rows": d,
                "before": {k: brand0[b][k] for k in (MATCHED, QUARANTINED, UNRESOLVED)},
                "after": {k: brand1[b][k] for k in (MATCHED, QUARANTINED, UNRESOLVED)},
                "pct_of_brand_quarantine_recovered": round(100 * d / brand0[b][QUARANTINED], 1) if brand0[b][QUARANTINED] else None,
            })
    improved.sort(key=lambda d: (-d["recovered_rows"], d["brand"]))
    # per rule
    by_rule: dict[str, list] = defaultdict(list)
    for r, x1 in recovered:
        by_rule[x1.rule].append((r, x1))
    overlapping = 0
    for r, x1 in recovered:
        if len(idx1.matching_grammars(r["brand"], x1.model, x1.qualifier)) > 1:
            overlapping += 1
    rules = []
    for rid in idx1.grammar_ids():
        items = sorted(by_rule.get(rid, []), key=lambda t: (t[0]["brand"], t[1].model, t[0]["name"], t[0]["id"]))
        quals = Counter(x.qualifier for _, x in items)
        rules.append({
            "rule": rid,
            "brand": items[0][0]["brand"] if items else None,
            "rows_recovered": len(items),
            "models": dict(Counter(x.model for _, x in items)),
            "top_qualifiers": top(quals, 12),
            "examples": [{"dataset_name": r["name"], "resolved_model": x.model, "accepted_qualifier": x.qualifier, "flags": x.flags} for r, x in stride_sample(items, 6)],
        })
    # still quarantined (after) + review queue
    still = [(r, x) for r, x in zip(rows, res1) if x.outcome == QUARANTINED]
    cat = Counter()
    queue: dict[tuple, dict] = {}
    for r, x in still:
        c = review_category(idx1, r["brand"], x.model, x.qualifier, h)
        cat[c] += 1
        k = (c, r["brand"], x.model, x.qualifier)
        e = queue.setdefault(k, {"category": c, "brand": r["brand"], "model": x.model, "qualifier": x.qualifier, "rows": 0, "examples": []})
        e["rows"] += 1
        if len(e["examples"]) < 3:
            e["examples"].append(r["name"])
    still_by_brand = Counter(r["brand"] for r, _ in still)
    cls_after = Counter(heuristic_class(x.qualifier, pw) for _, x in still)
    rep = {
        "schema_version": "carnet.model_matching_report/1",
        "kind": "recovery",
        "baseline_commit": BASELINE_COMMIT,
        "before": o0,
        "after": o1,
        "baseline_quarantined": base_q,
        "recovered_rows": len(recovered),
        "recovered_pct_of_baseline_quarantined": round(100 * len(recovered) / base_q, 2),
        "recovered_by_status": dict(Counter(x.status for _, x in recovered)),
        "recovered_from_unresolved": len(from_unresolved),
        "recovered_triage_classes": dict(Counter(heuristic_class(x.qualifier, pw) for _, x in recovered)),
        "brands_improved": improved,
        "rules": rules,
        "still_quarantined": len(still),
        "still_quarantined_by_review_category": dict(sorted(cat.items(), key=lambda kv: (-kv[1], kv[0]))),
        "still_quarantined_top_brands": top(still_by_brand, 20),
        "still_quarantined_triage_classes": dict(cls_after),
        "safety": {
            "matched_rows_lost_or_reassigned_vs_baseline": len(regress) + len(model_changed),
            "matched_rows_lost_or_reassigned_examples": (regress + model_changed)[:5],
            "new_rows_accepted_by_more_than_one_grammar": overlapping,
            "suspected_false_matches": false_match_suspects(idx1, rows, res1),
            **collision_checks(idx1, rows, res1),
        },
        "row_accounting": {
            "dataset_rows": len(rows),
            "outcome_sum_after": sum(o1[k] for k in (MATCHED, QUARANTINED, UNRESOLVED)),
            "outcome_sum_before": sum(o0[k] for k in (MATCHED, QUARANTINED, UNRESOLVED)),
            "ledger_sha256_before": ledger_sha(rows, res0),
            "ledger_sha256_after": ledger_sha(rows, res1),
        },
    }
    qlist = sorted(queue.values(), key=lambda e: (e["category"], -e["rows"], e["brand"], str(e["model"]), e["qualifier"]))
    review = {
        "schema_version": "carnet.model_matching_review_queue/1",
        "note": "Rows still QUARANTINED after the brand suffix grammars. Each entry needs a human decision (add a rule/alias/trim, or leave quarantined). Categories are triage labels only.",
        "total_rows": len(still),
        "unique_entries": len(qlist),
        "rows_per_category": dict(sorted(cat.items(), key=lambda kv: (-kv[1], kv[0]))),
        "category_definitions": {
            "<brand>_unknown_suffix": "the model HAS a grammar for this brand but the qualifier is outside it (new letter code, edition word, body variant...)",
            "unknown_engine_code": "no grammar for the model; the qualifier has a digit-bearing token that looks like an engine/variant code",
            "unknown_trim": "no grammar; 1-2 short alphabetic badge-like tokens (RS, GT, ST, N...)",
            "possible_sibling_model": "no grammar; alphabetic word(s) that may be a different model/body/edition (Verso, Majesta, Super Duty, Connect...)",
        },
        "entries": qlist,
    }
    return rep, review


def full_report() -> tuple[dict, dict, dict, dict]:
    idx1, cat, ds = mb.load_index(use_suffix_rules=True)
    idx0, _, _ = mb.load_index(use_suffix_rules=False)
    rows = load_rows(ds)
    h = heuristics()
    res0, res1 = resolve_all(idx0, rows), resolve_all(idx1, rows)
    base = baseline_report(idx0, rows, res0, h)
    rec, review = recovery_report(idx0, idx1, rows, res0, res1, h)
    return base, rec, review, {"rows": rows, "res0": res0, "res1": res1}


def main(argv=None) -> int:
    argv = argv if argv is not None else sys.argv[1:]
    if not argv or argv[0] not in ("report", "summary", "ledger"):
        print(__doc__)
        return 2
    base, rec, review, ctx = full_report()
    if argv[0] == "ledger":
        Path(argv[1]).write_text("\n".join(ledger_lines(ctx["rows"], ctx["res1"])) + "\n", encoding="utf-8")
        print(f"wrote {argv[1]}")
        return 0
    if argv[0] == "report":
        from enrichment_lib import write_json  # refuses to write under assets/ or lib/

        write_json(REPORTS / "model_matching_baseline.json", base)
        write_json(REPORTS / "model_matching_recovery.json", rec)
        write_json(REPORTS / "model_matching_review_queue.json", review)
    print("before:", rec["before"])
    print("after: ", rec["after"])
    print(f"recovered {rec['recovered_rows']} of {rec['baseline_quarantined']} quarantined ({rec['recovered_pct_of_baseline_quarantined']}%)")
    print("safety:", {k: v for k, v in rec["safety"].items() if k in ("matched_rows_lost_or_reassigned_vs_baseline", "rows_matched_to_shorter_model_whose_name_starts_with_longer_sibling")}, "false-match suspects:", len(rec["safety"]["suspected_false_matches"]))
    return 0


if __name__ == "__main__":
    sys.exit(main())
