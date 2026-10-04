#!/usr/bin/env python3
"""Brand-scale enrichment workflow (tooling only; never writes under assets/ or lib/).

Same evidence -> validators -> union -> comparison pipeline as the 3-model pilot, run per BRAND and per research BATCH.
Research itself (finding sources, quoting them) stays a controlled, human/agent-reviewed step: this tool never crawls.
Whatever evidence is authored must still pass the deterministic validators (traceability of every raw value to its
own supporting_text, vocabulary, model identity, no duplicate ids, manifest guard).

  python tools/catalog_enrichment/brand_enrichment.py --brand Toyota                 # inventory + research plan
  python tools/catalog_enrichment/brand_enrichment.py --brand Toyota --batch 1       # validate + generate + compare + coverage + plan update
  python tools/catalog_enrichment/brand_enrichment.py --brand Toyota --batch 1 --step validate|generate|compare|manifest|summary
  python tools/catalog_enrichment/brand_enrichment.py --brand Toyota --step inventory|plan
  python tools/catalog_enrichment/brand_enrichment.py --brand Toyota --step integrity   # add missing evidence-integrity blocks (deterministic, never upgrades)

Evidence integrity (rules/source_rules.json -> evidence_integrity): a value is VERIFIED only from a tier 1-3 source whose
content was preserved (FULL_TEXT_VERIFIED / PDF_VERIFIED, sha256-checked snapshot) AND whose quote is found in that snapshot.

Evidence lives in evidence/<brand>/<model>.json (pilot files evidence/<brand>_<model>.json are reused in place, never copied).
Generated unions live in generated/<brand>/<model>.union.json (pilot unions are reused and re-verified, never rewritten).
Rules: rules/brand_enrichment_rules.json. Deterministic: no clocks (dates come from the evidence files), no randomness.
"""
from __future__ import annotations

import argparse
import json
import math
import sys
from collections import Counter, defaultdict
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import enrichment_lib as L  # noqa: E402
import model_boundaries as mb  # noqa: E402

RULES_PATH = HERE / "rules" / "brand_enrichment_rules.json"
RULES = json.loads(RULES_PATH.read_text(encoding="utf-8"))
EVID, GEN, REP = HERE / "evidence", HERE / "generated", HERE / "reports"
SCHEMA_INVENTORY = "carnet.brand_inventory/1"
SCHEMA_PLAN = "carnet.brand_research_plan/1"
SCHEMA_BATCH_COMPARISON = "carnet.brand_batch_comparison/1"
COV_DIMS: list[str] = RULES["coverage"]["dimensions"]
MODEL_STATUSES = RULES["model_status"]["values"]


# ----------------------------------------------------------------------------------------------------------------
# paths
# ----------------------------------------------------------------------------------------------------------------
def evidence_path(brand: str, model: str) -> Path:
    """evidence/<brand>/<model>.json for new work; a pilot file evidence/<brand>_<model>.json is reused if it exists."""
    legacy = EVID / f"{L.slug(brand)}_{L.slug(model)}.json"
    new = EVID / L.slug(brand) / f"{L.slug(model)}.json"
    if new.exists():
        return new
    return legacy if legacy.exists() else new


def is_pilot_file(p: Path) -> bool:
    return p.parent == EVID


def union_path(brand: str, model: str) -> Path:
    return GEN / f"{L.slug(brand)}_{L.slug(model)}.union.json" if is_pilot_file(evidence_path(brand, model)) else GEN / L.slug(brand) / f"{L.slug(model)}.union.json"


def rel(p: Path) -> str:
    return p.relative_to(HERE).as_posix()


def manifest_path(brand: str) -> Path:
    return REP / f"{L.slug(brand)}_evidence_manifest.json"


def plan_path(brand: str) -> Path:
    return REP / f"{L.slug(brand)}_research_plan.json"


def inventory_path(brand: str) -> Path:
    return REP / f"{L.slug(brand)}_inventory.json"


def comparison_path(brand: str, batch: int) -> Path:
    return REP / f"{L.slug(brand)}_batch_{batch}_comparison.json"


# ----------------------------------------------------------------------------------------------------------------
# 1. inventory
# ----------------------------------------------------------------------------------------------------------------
def _brand_models(cat: dict, brand: str) -> list[str]:
    if brand not in cat["models"]:
        raise SystemExit(f"brand {brand!r} is not in assets/car_catalog.json")
    return list(cat["models"][brand])


def _sibling_info(mi: mb.ModelIndex, brand: str, model: str, groups: list[dict]) -> dict:
    longer = sorted({c for (b, a, c) in mi.prefix_pairs() if b == brand and a == model})
    shorter = sorted({a for (b, a, c) in mi.prefix_pairs() if b == brand and c == model})
    group_mates = sorted({m for g in groups if g["brand"] == brand and model in g["models"] for m in g["models"] if m != model})
    return {"longer_siblings": longer, "shorter_parents": shorter, "must_remain_distinct_with": group_mates}


def _sparse_flags(spec_rows: int, newest: int | None, trim_count: int, dim_counts: dict[str, int]) -> list[str]:
    r = RULES["inventory"]["sparse_flags"]
    flags = []
    if spec_rows < r["few_rows"]["max_spec_rows_exclusive"]:
        flags.append("few_rows")
    if newest is None or newest < r["no_recent_years"]["newest_year_below"]:
        flags.append("no_recent_years")
    if trim_count < r["few_trims"]["max_catalog_trims_exclusive"]:
        flags.append("few_trims")
    missing = [d for d in r["missing_dimensions"]["dimensions"] if dim_counts.get(d, 0) == 0]
    if missing:
        flags.append("missing_dimensions:" + ",".join(missing))
    return flags


def build_inventory(brand: str) -> dict:
    ctx = L.load_current_carnet()
    cat, mi, audit = ctx["cat"], ctx["models"], ctx["audit"]
    groups = json.loads((HERE / "rules" / "model_boundaries.json").read_text(encoding="utf-8")).get("must_remain_distinct", [])
    models_out = []
    for m in _brand_models(cat, brand):
        cur = L.current_carnet(ctx, brand, m)
        _bid, legacy = audit.family_rows(ctx["idx"], brand, m)
        rows, excluded = mi.split_dataset_rows(brand, m, legacy)
        years_from = [r["year_from"] for r in rows]
        years_end = [r["year_end_raw"] for r in rows if r["year_end_raw"]]
        newest = max(years_from + years_end) if rows else None
        trims = (cat["trimsByBrandModel"].get(brand) or {}).get(m) or []
        trim_keys = sorted({L.trim_key(t) for t in trims if L.trim_key(t)})
        dims = {d: [x["value"] for x in cur["dimensions"][d]] for d in COV_DIMS}
        dim_counts = {d: len(v) for d, v in dims.items()}
        flags = _sparse_flags(len(rows), newest, len(trim_keys), dim_counts)
        sib = _sibling_info(mi, brand, m, groups)
        b = cur["boundary"]
        borrowed = sum(v for k, v in b["excluded_by_reason"].items() if k.startswith("belongs_to:"))
        quarantined = sum(v for k, v in b["excluded_by_reason"].items() if k.startswith(("ambiguous_qualifier", "distinct_vehicle_qualifier")))
        if borrowed:
            risk = "HIGH"  # the app's loose prefix rule would hand this model rows that belong to a sibling
        elif sib["longer_siblings"] or sib["shorter_parents"] or sib["must_remain_distinct_with"]:
            risk = "MEDIUM"
        else:
            risk = "LOW"
        ep = evidence_path(brand, m)
        ev = None
        if ep.exists():
            doc = L.read_json(ep)
            ev = {"evidence_file": rel(ep), "record_count": len(doc["records"]), "source_count": len(doc["sources"]), "researched_at": doc["researched_at"], "pilot_evidence": is_pilot_file(ep)}
        models_out.append(
            {
                "model": m,
                "legacy_spec_rows": len(rows),
                "legacy_dataset_model_names": len(cur["dataset_model_names"]),
                "catalog_trim_count": len(trim_keys),
                "catalog_trims": [L.trim_display(t) or t for t in sorted({t for t in trims if L.trim_key(t)}, key=lambda x: L.trim_key(x))],
                "newest_legacy_model_year": newest,
                "oldest_legacy_model_year": min(years_from) if rows else None,
                "sparse_or_incomplete": bool(flags),
                "sparse_flags": flags,
                "collision_risk": risk,
                "collision_detail": {
                    **sib,
                    "legacy_loose_rule_rows": len(legacy),
                    "rows_borrowed_from_siblings_by_loose_rule": borrowed,
                    "rows_quarantined_ambiguous_qualifier": quarantined,
                },
                "has_enrichment_evidence": ev is not None,
                "enrichment_evidence": ev,
                "current_known_dimensions": {
                    "trims": dims["trims"],
                    "engines": dims["engine_sizes"],
                    "cylinders": dims["cylinders"],
                    "fuel": dims["fuel_types"],
                    "transmission": dims["transmissions"],
                    "drivetrain": dims["drivetrains"],
                    "seating": dims["seats"],
                    "body_type": dims["body_types"],
                },
            }
        )
    risk_counts = Counter(x["collision_risk"] for x in models_out)
    return {
        "schema_version": SCHEMA_INVENTORY,
        "brand": brand,
        "read_only": True,
        "source": "assets/car_catalog.json (canonical model list) + assets/car_spec_dataset.json (legacy rows resolved by model_boundaries.py). Nothing under assets/ or lib/ is written.",
        "rules": "rules/brand_enrichment_rules.json -> inventory",
        "totals": {
            "models": len(models_out),
            "models_with_zero_legacy_rows": sum(1 for x in models_out if x["legacy_spec_rows"] == 0),
            "models_sparse_or_incomplete": sum(1 for x in models_out if x["sparse_or_incomplete"]),
            "models_with_enrichment_evidence": sum(1 for x in models_out if x["has_enrichment_evidence"]),
            "legacy_spec_rows": sum(x["legacy_spec_rows"] for x in models_out),
            "collision_risk": dict(sorted(risk_counts.items())),
        },
        "models": models_out,
    }


# ----------------------------------------------------------------------------------------------------------------
# 2. deterministic research batches
# ----------------------------------------------------------------------------------------------------------------
def priority(inv_model: dict) -> dict:
    p = RULES["batching"]["priority"]
    flags = inv_model["sparse_flags"]
    n_flags = min(len(flags), p["sparse_flag_count_cap"])
    newest = inv_model["newest_legacy_model_year"]
    recent = newest is not None and newest >= RULES["inventory"]["recent_year_at_least"]
    presence = inv_model["legacy_spec_rows"] >= 1 or inv_model["catalog_trim_count"] >= 1
    score = p["w_sparse"] * n_flags + p["w_recent"] * (1 if recent else 0) + p["w_presence"] * (1 if presence else 0)
    return {"score": score, "sparse_flag_count": n_flags, "recent": recent, "presence": presence}


def batch_sizes(n: int) -> list[int]:
    target = RULES["batching"]["target_batch_size"]
    k = math.ceil(n / target)
    base, extra = divmod(n, k)
    return [base + (1 if i < extra else 0) for i in range(k)]


def make_batches(inv: dict) -> list[list[dict]]:
    ranked = []
    for m in inv["models"]:
        pr = priority(m)
        ranked.append((m, pr))
    ranked.sort(key=lambda t: (-t[1]["score"], -t[0]["catalog_trim_count"], t[0]["model"].casefold(), t[0]["model"]))
    out, i = [], 0
    for size in batch_sizes(len(ranked)):
        out.append(ranked[i : i + size])
        i += size
    assert sum(len(b) for b in out) == len(inv["models"]) and len({m["model"] for b in out for m, _ in b}) == len(inv["models"])
    return out


# ----------------------------------------------------------------------------------------------------------------
# 3. evidence -> union -> coverage -> status
# ----------------------------------------------------------------------------------------------------------------
def source_text_dir(p: Path) -> Path:
    return p.parent / "_source_text"


def evidence_integrity(doc: dict, root: Path = HERE) -> dict:
    """Integrity summary of one evidence document: counts per state + how many records pass the integrity test."""
    errs, texts, assess = L.verify_snapshots(doc, root)
    c = L.integrity_counts(doc)
    return {
        "records_by_state": c["records"],
        "sources_by_state": c["sources"],
        "records_passing_integrity_test": sum(1 for a in assess.values() if a["eligible"]),
        "records_quote_validated": sum(1 for a in assess.values() if a["quote_validated"]),
        "errors": errs,
        "assessments": assess,
    }


def verify_source_quotes(doc: dict, p: Path | None = None, root: Path = HERE) -> tuple[list[str], dict[str, int]]:
    """Snapshot/hash/quote verification for a doc (kept as the single entry point used by validate)."""
    info = evidence_integrity(doc, root)
    return info["errors"], {"quote_validated_records": info["records_quote_validated"], "records_passing_integrity_test": info["records_passing_integrity_test"]}


def prepare_brand(brand: str) -> list[str]:
    """Derive normalized/confidence/source fields for every NEW (non-pilot) evidence file of the brand (idempotent)."""
    done = []
    d = EVID / L.slug(brand)
    for p in sorted(d.glob("*.json")) if d.exists() else []:
        doc = L.read_json(p)
        L.write_json(p, L.prepare_evidence(doc))
        done.append(p.name)
    return done


def migrate_brand_integrity(brand: str) -> list[str]:
    """--step integrity: add integrity blocks to sources lacking one (all of the brand's evidence files incl. pilot files)."""
    out = []
    d = EVID / L.slug(brand)
    files = sorted(d.glob("*.json")) if d.exists() else []
    files += sorted(EVID.glob(f"{L.slug(brand)}_*.json"))
    for p in files:
        doc, log = L.migrate_integrity(L.read_json(p), source_text_dir(p))
        if log:
            L.write_json(p, L.prepare_evidence(doc))
        out.append(f"{rel(p)}: " + (f"{len(log)} source(s): " + ", ".join(log) if log else "already migrated"))
    return out


def load_validated(brand: str, model: str, mi: mb.ModelIndex, manifest: dict | None):
    p = evidence_path(brand, model)
    doc = L.read_json(p)
    errs = L.validate_evidence(doc, mi)
    errs = errs + L.verify_snapshots(doc)[0]
    merrs, notes = L.check_manifest(doc, (manifest or {}).get(p.stem))
    return doc, errs + merrs, notes, L.boundary_warnings(doc, mi)


def build_model_union(brand: str, model: str, doc: dict) -> dict:
    p = evidence_path(brand, model)
    conflicts = L.detect_conflicts(doc["records"], f"{L.slug(brand)}-{L.slug(model)}")
    return L.build_union(doc, conflicts, evidence_file=f"evidence/{p.relative_to(EVID).as_posix()}")


def _scope(rec: dict) -> tuple:
    n = rec.get("normalized") or {}
    return (n.get("market") or "?", rec.get("generation") or (f"y{rec['year_from']}" if rec.get("year_from") else "?"))


def coverage(doc: dict, union: dict, assess: dict | None = None) -> dict:
    """Per-dimension research coverage class (RULES -> coverage). Describes the evidence collected, not completeness."""
    by_id = {r["record_id"]: r for r in doc["records"]}
    if assess is None:
        assess = L.assess_records(doc, L.load_snapshots(doc)[0])
    out = {}
    for dim in COV_DIMS:
        det = union["details"][dim]
        ver = [d for d in det if d["status"] == "VERIFIED"]
        nsr = [d for d in det if d["status"] == "NEEDS_SOURCE_RETRIEVAL"]
        prov = [d for d in det if d["status"] == "PROVISIONAL"]
        conf = [c["conflict_id"] for c in union["conflicts"] if c["field"] in L.DIM_CONFLICT_FIELDS[dim]]
        # only records that pass the integrity test (tier 1-3 + preserved snapshot + quote found) count towards source/scope breadth
        ver_recs = [by_id[r] for d in ver for r in d["record_ids"] if r in by_id and assess[r]["eligible"]]
        sources = sorted({r["evidence"]["source_id"] for r in ver_recs})
        scopes = sorted({_scope(r) for r in ver_recs})
        if conf:
            cls = "CONFLICT"
        elif not ver and not prov and not nsr:
            cls = "NO_EVIDENCE"
        elif ver and (len(sources) >= 2 or len(scopes) >= 2):
            cls = "GOOD"
        else:
            cls = "PARTIAL"
        out[dim] = {
            "class": cls,
            "verified_values": len(ver),
            "needs_source_retrieval_values": len(nsr),
            "provisional_only_values": len(prov),
            "verified_source_count": len(sources),
            "verified_scope_count": len(scopes),
            "conflicts": conf,
        }
    return out


def integrity_verified_tier123_records(assess: dict) -> int:
    """Tier 1-3 records that pass the integrity test (preserved snapshot of the source, quote found in it)."""
    return sum(1 for a in assess.values() if a["eligible"])


def model_status(cov: dict | None, record_count: int, integrity_verified_records: int = 0) -> str:
    if not cov or record_count == 0:
        return "NOT_STARTED"
    r = RULES["model_status"]
    if any(c["class"] == "CONFLICT" for c in cov.values()):
        return "CONFLICT"
    good = sum(1 for c in cov.values() if c["class"] == "GOOD")
    if (
        good >= r["researched_min_good"]
        and all(cov[d]["class"] != "NO_EVIDENCE" for d in r["researched_required_non_empty"])
        and (integrity_verified_records > 0 or not r.get("researched_requires_integrity_verified_tier123_record", False))
    ):
        return "RESEARCHED"
    if sum(1 for c in cov.values() if c["verified_values"] > 0) >= r["partial_min_dimensions_with_verified"]:
        return "PARTIALLY_RESEARCHED"
    return "NEEDS_MORE_SOURCES"


def batch_status(statuses: list[str]) -> str:
    started = sum(1 for s in statuses if s != "NOT_STARTED")
    if started == 0:
        return "NOT_STARTED"
    return "IN_PROGRESS" if started < len(statuses) else "RESEARCHED_PENDING_REVIEW"


def model_state(brand: str, model: str, mi: mb.ModelIndex) -> dict:
    """Everything the plan/comparison need for one model that may or may not have evidence yet."""
    p = evidence_path(brand, model)
    if not p.exists():
        return {"model": model, "status": "NOT_STARTED", "evidence_record_count": 0, "conflicts": [], "provisional_values": {}, "needs_source_retrieval_values": {}, "evidence_integrity": None, "unresearched_fields": list(COV_DIMS), "coverage": None, "doc": None, "union": None}
    doc = L.read_json(p)
    union = build_model_union(brand, model, doc)
    info = evidence_integrity(doc)
    cov = coverage(doc, union, info["assessments"])
    integ = {k: info[k] for k in ("records_by_state", "sources_by_state", "records_passing_integrity_test")}
    return {
        "evidence_integrity": integ,
        "model": model,
        "status": model_status(cov, len(doc["records"]), info["records_passing_integrity_test"]),
        "evidence_record_count": len(doc["records"]),
        "conflicts": [c["conflict_id"] for c in union["conflicts"]],
        "provisional_values": {d: v for d, v in union["provisional_only"].items() if v},
        "needs_source_retrieval_values": {d: v for d, v in union["needs_source_retrieval"].items() if v},
        "unresearched_fields": [d for d in COV_DIMS if cov[d]["class"] == "NO_EVIDENCE"],
        "coverage": cov,
        "doc": doc,
        "union": union,
    }


def build_plan(brand: str, inv: dict, mi: mb.ModelIndex) -> dict:
    batches = make_batches(inv)
    out = []
    for i, items in enumerate(batches, 1):
        states = {m["model"]: model_state(brand, m["model"], mi) for m, _ in items}
        statuses = [states[m["model"]]["status"] for m, _ in items]
        prov = {k: s["provisional_values"] for k, s in states.items() if s["provisional_values"]}
        out.append(
            {
                "batch_id": f"{L.slug(brand)}-batch-{i:02d}",
                "batch_number": i,
                "models": [m["model"] for m, _ in items],
                "status": batch_status(statuses),
                "evidence_record_count": sum(s["evidence_record_count"] for s in states.values()),
                "conflicts": {k: s["conflicts"] for k, s in states.items() if s["conflicts"]},
                "provisional_values": prov,
                "needs_source_retrieval_values": {k: s["needs_source_retrieval_values"] for k, s in states.items() if s["needs_source_retrieval_values"]},
                "unresearched_fields": {k: s["unresearched_fields"] for k, s in states.items() if s["unresearched_fields"]},
                "model_status": {k: s["status"] for k, s in states.items()},
                "evidence_integrity": {k: s["evidence_integrity"] for k, s in states.items() if s.get("evidence_integrity")},
                "model_plan": [
                    {
                        "model": m["model"],
                        "priority_score": pr["score"],
                        "sparse_flags": m["sparse_flags"],
                        "recent": pr["recent"],
                        "legacy_spec_rows": m["legacy_spec_rows"],
                        "newest_legacy_model_year": m["newest_legacy_model_year"],
                        "collision_risk": m["collision_risk"],
                        "siblings_to_keep_separate": sorted(set(m["collision_detail"]["longer_siblings"] + m["collision_detail"]["shorter_parents"] + m["collision_detail"]["must_remain_distinct_with"])),
                        "existing_evidence": m["enrichment_evidence"]["evidence_file"] if m["enrichment_evidence"] else None,
                    }
                    for m, pr in items
                ],
            }
        )
    all_models = [m for b in out for m in b["models"]]
    counts = Counter(s for b in out for s in b["model_status"].values())
    return {
        "schema_version": SCHEMA_PLAN,
        "brand": brand,
        "rules": "rules/brand_enrichment_rules.json -> batching",
        "note": "Deterministic: batch membership depends only on the inventory (never on research results), so it never reshuffles between runs. Status words are RESEARCHED / PARTIALLY_RESEARCHED / NEEDS_MORE_SOURCES / CONFLICT / NOT_STARTED - never 'complete'. RESEARCHED means the evidence thresholds in the rules were met for the markets/generations listed in each evidence file's coverage statement.",
        "model_count": len(all_models),
        "batch_count": len(out),
        "all_models_assigned_exactly_once": len(all_models) == len(set(all_models)) == inv["totals"]["models"],
        "model_status_counts": dict(sorted(counts.items())),
        "batches": out,
    }


# ----------------------------------------------------------------------------------------------------------------
# 4. batch comparison
# ----------------------------------------------------------------------------------------------------------------
def build_batch_comparison(brand: str, batch: dict, mi: mb.ModelIndex, ctx: dict) -> dict:
    models = []
    for m in batch["models"]:
        st = model_state(brand, m, mi)
        if st["union"] is None:
            models.append({"brand": brand, "model": m, "status": "NOT_STARTED", "note": "no evidence yet"})
            continue
        cur = L.current_carnet(ctx, brand, m)
        cmp_ = L.compare_model(st["union"], cur)
        cov = st["coverage"]
        for d in COV_DIMS:
            e = cmp_["dimensions"][d]
            e["research_coverage"] = cov[d]["class"]
            e["UNKNOWN_NOT_YET_RESEARCHED"] = (
                {"all_current_values_unverified": True, "reason": "no VERIFIED, NEEDS_SOURCE_RETRIEVAL or PROVISIONAL evidence for this dimension"} if cov[d]["class"] == "NO_EVIDENCE" else False
            )
        models.append(
            {
                **cmp_,
                "status": st["status"],
                "research_coverage": {d: cov[d] for d in COV_DIMS},
                "unresearched_fields": st["unresearched_fields"],
                "evidence_integrity": st["evidence_integrity"],
                "evidence_file": rel(evidence_path(brand, m)),
                "union_file": rel(union_path(brand, m)),
                "evidence_record_count": st["evidence_record_count"],
                "evidence_coverage_statement": st["doc"].get("coverage", []),
            }
        )
    return {
        "schema_version": SCHEMA_BATCH_COMPARISON,
        "brand": brand,
        "batch_id": batch["batch_id"],
        "read_only": True,
        "note": "CURRENT_CARNET is read through catalog_audit_readonly.py + model_boundaries.py; nothing under assets/ or lib/ is written. NEW_VERIFIED holds only values whose supporting source content was preserved (FULL_TEXT_VERIFIED / PDF_VERIFIED) and whose quote was found in it; tier 1-3 values backed only by snippets or unvalidated retrievals are NEW_NEEDS_SOURCE_RETRIEVAL, tier 4-5 values NEW_PROVISIONAL_ONLY. ONLY_IN_CARNET means 'not verified by the research collected so far', NOT 'wrong'. UNKNOWN_NOT_YET_RESEARCHED marks dimensions with no evidence at all. Vocabulary is LOCKED (rules/normalization_rules.json); 'legacy_view' blocks are informational only.",
        "models": models,
    }


# ----------------------------------------------------------------------------------------------------------------
# commands
# ----------------------------------------------------------------------------------------------------------------
def _inv(brand):
    inv = build_inventory(brand)
    return inv


def cmd_inventory(brand: str):
    inv = build_inventory(brand)
    L.write_json(inventory_path(brand), inv)
    t = inv["totals"]
    print(f"wrote {rel(inventory_path(brand))}  models={t['models']} sparse={t['models_sparse_or_incomplete']} zero_rows={t['models_with_zero_legacy_rows']} with_evidence={t['models_with_enrichment_evidence']} risk={t['collision_risk']}")
    return inv


def cmd_plan(brand: str, inv: dict | None = None):
    inv = inv or build_inventory(brand)
    mi = mb.load_index()[0]
    plan = build_plan(brand, inv, mi)
    L.write_json(plan_path(brand), plan)
    print(f"wrote {rel(plan_path(brand))}  batches={plan['batch_count']} models={plan['model_count']} status={plan['model_status_counts']}")
    return plan


def _batch(brand: str, n: int) -> dict:
    plan = L.read_json(plan_path(brand)) if plan_path(brand).exists() else cmd_plan(brand)
    for b in plan["batches"]:
        if b["batch_number"] == n:
            return b
    raise SystemExit(f"{brand}: no batch {n} (have 1..{plan['batch_count']})")


def cmd_validate(brand: str, batch: dict) -> int:
    mi = mb.load_index()[0]
    manifest = L.read_json(manifest_path(brand)) if manifest_path(brand).exists() else {}
    pilot_manifest = L.read_json(REP / "evidence_manifest.json") if (REP / "evidence_manifest.json").exists() else {}
    bad = 0
    seen_ids: dict[str, str] = {}
    for m in batch["models"]:
        p = evidence_path(brand, m)
        if not p.exists():
            print(f"{m}: NO EVIDENCE FILE (status NOT_STARTED)")
            continue
        doc, errs, notes, warns = load_validated(brand, m, mi, {**pilot_manifest, **manifest})
        # record ids must be unique across the whole brand (they prefix-scope per model file)
        for r in doc["records"]:
            if r["record_id"] in seen_ids and seen_ids[r["record_id"]] != m:
                errs.append(f"{r['record_id']}: duplicate record_id across models ({seen_ids[r['record_id']]} vs {m})")
            seen_ids[r["record_id"]] = m
        print(f"{m}: {'OK' if not errs else str(len(errs)) + ' error(s)'}  records={len(doc['records'])} sources={len(doc['sources'])}  [{rel(p)}]")
        for e in errs:
            print("   -", e)
        for w in warns:
            print("   ! boundary warning:", w)
        for n in notes:
            print("   ~", n)
        bad += len(errs)
    return 1 if bad else 0


def cmd_generate(brand: str, batch: dict) -> int:
    mi = mb.load_index()[0]
    bad = 0
    for m in batch["models"]:
        p = evidence_path(brand, m)
        if not p.exists():
            continue
        doc = L.read_json(p)
        union = build_model_union(brand, m, doc)
        out = union_path(brand, m)
        if is_pilot_file(p):
            # pilot evidence is REUSED: the existing union must be exactly what the validators regenerate (no rewrite)
            same = out.exists() and L.read_json(out) == json.loads(json.dumps(union))
            print(f"reused pilot union {rel(out)}  identical_to_regenerated={same}")
            bad += not same
            continue
        L.write_json(out, union)
        print(f"generated {rel(out)}  records={union['generated_from']['record_count']} conflicts={len(union['conflicts'])} tiers={union['generated_from']['records_by_source_tier']}")
    return 1 if bad else 0


def cmd_manifest(brand: str, batch: dict):
    out = L.read_json(manifest_path(brand)) if manifest_path(brand).exists() else {}
    for m in batch["models"]:
        p = evidence_path(brand, m)
        if p.exists() and not is_pilot_file(p):  # pilot records are already fingerprinted in evidence_manifest.json
            out[p.stem] = L.evidence_manifest(L.read_json(p))
    L.write_json(manifest_path(brand), dict(sorted(out.items())))
    print(f"wrote {rel(manifest_path(brand))}  " + ", ".join(f"{k}={v['record_count']}" for k, v in sorted(out.items())))


def cmd_compare(brand: str, batch: dict):
    ctx = L.load_current_carnet()
    mi = ctx["models"]
    rep = build_batch_comparison(brand, batch, mi, ctx)
    p = comparison_path(brand, batch["batch_number"])
    L.write_json(p, rep)
    print(f"wrote {rel(p)}")
    return rep


def cmd_summary(brand: str, batch: dict):
    mi = mb.load_index()[0]
    for m in batch["models"]:
        st = model_state(brand, m, mi)
        if st["union"] is None:
            print(f"\n=== {brand} {m}: NOT_STARTED")
            continue
        u = st["union"]
        print(f"\n=== {brand} {m}: {st['status']}  {u['generated_from']['record_count']} records, {u['generated_from']['source_count']} sources, tiers {u['generated_from']['records_by_source_tier']}")
        ei = st["evidence_integrity"]
        print(f"  integrity records {ei['records_by_state']}  passing_integrity_test={ei['records_passing_integrity_test']}")
        for d in L.DIMENSIONS:
            c = st["coverage"].get(d, {}).get("class", "-")
            print(f"  {d:22} [{c:11}] VERIFIED {u['verified'][d]}   NEEDS-SOURCE-RETRIEVAL {u['needs_source_retrieval'][d]}   PROVISIONAL-only {u['provisional_only'][d]}")
        print(f"  conflicts: {len(u['conflicts'])}")
        for c in u["conflicts"]:
            print(f"    {c['conflict_id']} {c['field']} [{c['engine_group']}] {c['severity']}: " + "; ".join(f"{v['record_id']}={v['value']}" for v in c["values"]))


def run_batch(brand: str, n: int, step: str = "all") -> int:
    prepared = prepare_brand(brand)
    if prepared:
        print(f"prepared (derived fields recomputed, authored fields untouched): {len(prepared)} evidence file(s)")
    inv = cmd_inventory(brand)
    plan = cmd_plan(brand, inv)  # statuses reflect evidence on disk
    batch = next(b for b in plan["batches"] if b["batch_number"] == n)
    print(f"\nbatch {batch['batch_id']}: {batch['models']}")
    if step == "validate":
        return cmd_validate(brand, batch)
    if step == "manifest":
        cmd_manifest(brand, batch)
        return 0
    if step == "generate":
        return cmd_generate(brand, batch)
    if step == "compare":
        cmd_compare(brand, batch)
        return 0
    if step == "summary":
        cmd_summary(brand, batch)
        return 0
    if cmd_validate(brand, batch):
        return 1
    if cmd_generate(brand, batch):
        return 1
    cmd_compare(brand, batch)
    cmd_plan(brand, inv)  # refresh statuses after generation
    cmd_summary(brand, batch)
    return 0


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--brand", required=True)
    ap.add_argument("--batch", type=int)
    ap.add_argument("--step", choices=["all", "inventory", "plan", "validate", "generate", "compare", "manifest", "summary", "integrity"], default="all")
    a = ap.parse_args(argv)
    if a.step == "integrity":  # brand-level, explicit, idempotent migration of sources that carry no integrity block
        for line in migrate_brand_integrity(a.brand):
            print(line)
        return 0
    if a.batch is None:
        if a.step in ("all", "inventory", "plan"):
            if a.step in ("all", "plan"):
                prepare_brand(a.brand)
            inv = cmd_inventory(a.brand) if a.step in ("all", "inventory") else build_inventory(a.brand)
            if a.step in ("all", "plan"):
                cmd_plan(a.brand, inv)
            return 0
        ap.error("--batch is required for this step")
    if a.step in ("inventory", "plan"):
        ap.error("inventory/plan are brand-level; omit --batch")
    return run_batch(a.brand, a.batch, a.step)


if __name__ == "__main__":
    sys.exit(main())
