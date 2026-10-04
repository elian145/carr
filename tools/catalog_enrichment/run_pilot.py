#!/usr/bin/env python3
"""Run the CarNet enrichment pilot (tooling only; never writes under assets/ or lib/).

  python tools/catalog_enrichment/run_pilot.py prepare    # expand sources, score confidence, normalize (in place in evidence/)
  python tools/catalog_enrichment/run_pilot.py integrity  # add the evidence-integrity block to sources that lack one (deterministic migration)
  python tools/catalog_enrichment/run_pilot.py validate   # structure + traceability + unmapped-value checks
  python tools/catalog_enrichment/run_pilot.py generate   # conflicts + model unions -> generated/*.union.json
  python tools/catalog_enrichment/run_pilot.py compare    # unions vs CURRENT CarNet (read-only) -> reports/pilot_comparison.json
  python tools/catalog_enrichment/run_pilot.py manifest   # record authored fingerprints of every evidence record (no-silent-loss guard)
  python tools/catalog_enrichment/run_pilot.py boundaries # reports/model_collisions.json (catalog prefix collisions + old-rule contamination)
  python tools/catalog_enrichment/run_pilot.py all        # prepare, validate, generate, compare
  python tools/catalog_enrichment/run_pilot.py summary    # print a compact text summary of the generated files
"""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

import enrichment_lib as L

EVID = L.HERE / "evidence"
GEN = L.HERE / "generated"
REP = L.HERE / "reports"
PILOT = [("Ford", "Everest"), ("Toyota", "Land Cruiser"), ("Toyota", "Camry")]


def evidence_path(brand, model) -> Path:
    return EVID / f"{L.slug(brand)}_{L.slug(model)}.json"


def cmd_prepare():
    for b, m in PILOT:
        p = evidence_path(b, m)
        doc = L.read_json(p)
        L.write_json(p, L.prepare_evidence(doc))
        print(f"prepared {p.relative_to(L.REPO)}")


MANIFEST = REP / "evidence_manifest.json"


def _models():
    import model_boundaries as mb

    return mb.load_index()[0]


def cmd_integrity():
    """Add the evidence-integrity block to pilot sources that lack one (deterministic, never upgrades to *_VERIFIED
    without a preserved snapshot whose hash matches; pilot sources have none -> RETRIEVED_UNVERIFIABLE / SNIPPET_ONLY)."""
    for b, m in PILOT:
        p = evidence_path(b, m)
        doc, log = L.migrate_integrity(L.read_json(p), p.parent / "_source_text")
        if log:
            L.write_json(p, doc)
        print(f"{p.name}: integrity added to {len(log)} source(s)" + (": " + ", ".join(log) if log else " (already present)"))


def cmd_validate() -> int:
    bad = 0
    mi = _models()
    manifest = L.read_json(MANIFEST) if MANIFEST.exists() else {}
    for b, m in PILOT:
        p = evidence_path(b, m)
        doc = L.read_json(p)
        errs = L.validate_evidence(doc, mi)
        errs += L.verify_snapshots(doc)[0]
        merrs, mnotes = L.check_manifest(doc, manifest.get(p.stem))
        errs += merrs
        ic = L.integrity_counts(doc)["records"]
        print(f"{p.name}: {'OK' if not errs else str(len(errs)) + ' error(s)'}  records={len(doc['records'])}  integrity={ {k: v for k, v in ic.items() if v} }")
        for e in errs:
            print("   -", e)
        for w in L.boundary_warnings(doc, mi):
            print("   ! boundary warning:", w)
        for n in mnotes:
            print("   ~", n)
        bad += len(errs)
    for pp in sorted(L.PROPOSALS.glob("*.json")):  # proposals must declare whether they are current; stale ones must be non-actionable
        pdoc = L.read_json(pp)
        perrs = L.validate_proposal(pdoc)
        actionable = not L.proposal_problems(pdoc)
        print(f"proposals/{pp.name}: {'OK' if not perrs else str(len(perrs)) + ' error(s)'}  state={(pdoc.get('proposal_status') or {}).get('state')}  actionable={actionable}")
        for e in perrs:
            print("   -", e)
        bad += len(perrs)
    return 1 if bad else 0


def cmd_manifest():
    """Record the authored fingerprint of every evidence record (run after reviewing evidence changes)."""
    out = {}
    for b, m in PILOT:
        p = evidence_path(b, m)
        out[p.stem] = L.evidence_manifest(L.read_json(p))
    L.write_json(MANIFEST, out)
    print(f"wrote {MANIFEST.relative_to(L.REPO)}  " + ", ".join(f"{k}={v['record_count']}" for k, v in out.items()))


def cmd_boundaries():
    import model_boundaries as mb

    mi, _cat, ds = mb.load_index()
    rep = mb.collision_report(mi, ds)
    L.write_json(REP / "model_collisions.json", rep)
    print(f"wrote reports/model_collisions.json pairs={rep['catalog_prefix_pair_count']} contaminating_pairs={rep['pairs_where_old_rule_contaminates']} rows={rep['dataset_rows_contaminating_shorter_models_under_old_rule']}")


def cmd_generate():
    for b, m in PILOT:
        doc = L.read_json(evidence_path(b, m))
        conflicts = L.detect_conflicts(doc["records"], f"{L.slug(b)}-{L.slug(m)}")
        union = L.build_union(doc, conflicts)
        out = GEN / f"{L.slug(b)}_{L.slug(m)}.union.json"
        L.write_json(out, union)
        print(f"generated {out.relative_to(L.REPO)}  records={union['generated_from']['record_count']} conflicts={len(conflicts)}")


def cmd_compare():
    ctx = L.load_current_carnet()
    report = {
        "schema_version": L.SCHEMA_COMPARISON,
        "read_only": True,
        "note": "CURRENT_CARNET is read from assets/ through catalog_audit_readonly.py; nothing under assets/ or lib/ was modified. "
        "ONLY_IN_CARNET means 'not found in the evidence collected by this pilot' (the pilot covered selected generations/markets), NOT 'wrong'. "
        "Dataset rows are assigned to a model by the deterministic resolver in model_boundaries.py (NOT the app's prefix heuristic): 'Land Cruiser Prado' rows never count as 'Land Cruiser'; rows with an ambiguous qualifier are quarantined (see current_carnet_meta.boundary). "
        "Vocabulary is LOCKED (rules/normalization_rules.json -> locked_vocabulary): Petrol canonical, Hybrid separate, AWD != 4WD, transmission family + variant. 'legacy_view' blocks are informational only.",
        "models": [],
    }
    for b, m in PILOT:
        union = L.read_json(GEN / f"{L.slug(b)}_{L.slug(m)}.union.json")
        cur = L.current_carnet(ctx, b, m)
        report["models"].append(L.compare_model(union, cur))
    L.write_json(REP / "pilot_comparison.json", report)
    print(f"wrote {(REP / 'pilot_comparison.json').relative_to(L.REPO)}")


def cmd_summary():
    for b, m in PILOT:
        u = L.read_json(GEN / f"{L.slug(b)}_{L.slug(m)}.union.json")
        print(f"\n=== {b} {m}: {u['generated_from']['record_count']} records, {u['generated_from']['source_count']} sources, tiers {u['generated_from']['records_by_source_tier']}")
        for d in L.DIMENSIONS:
            print(f"  {d:19} VERIFIED {u['verified'][d]}   NEEDS-SOURCE-RETRIEVAL {u['needs_source_retrieval'][d]}   PROVISIONAL-only {u['provisional_only'][d]}")
        print(f"  conflicts: {len(u['conflicts'])}")
        for c in u["conflicts"]:
            print(f"    {c['conflict_id']} {c['field']} [{c['engine_group']}] {c['severity']}: " + "; ".join(f"{v['record_id']}={v['value']}" for v in c["values"]))
    p = REP / "pilot_comparison.json"
    if p.exists():
        r = L.read_json(p)
        for mm in r["models"]:
            print(f"\n--- COMPARISON {mm['brand']} {mm['model']}")
            for d in L.COMPARISON_DIMS_REQUESTED:
                e = mm["dimensions"][d]
                print(f"  {d}: CURRENT={e['CURRENT_CARNET']}")
                print(f"      MISSING_FROM_CARNET={e['MISSING_FROM_CARNET']}  PROVISIONAL_NOT_IN_CARNET={e['PROVISIONAL_NOT_IN_CARNET']}")
                print(f"      ONLY_IN_CARNET={[(x['value'], x.get('flag')) for x in e['ONLY_IN_CARNET']]}  CONFLICTS={[c['conflict_id'] for c in e['CONFLICTS']]}")


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("cmd", choices=["prepare", "integrity", "validate", "generate", "compare", "all", "summary", "manifest", "boundaries"])
    a = ap.parse_args(argv)
    if a.cmd == "integrity":
        cmd_integrity()
    elif a.cmd == "manifest":
        cmd_manifest()
    elif a.cmd == "boundaries":
        cmd_boundaries()
    elif a.cmd == "prepare":
        cmd_prepare()
    elif a.cmd == "validate":
        return cmd_validate()
    elif a.cmd == "generate":
        cmd_generate()
    elif a.cmd == "compare":
        cmd_compare()
    elif a.cmd == "summary":
        cmd_summary()
    else:
        cmd_prepare()
        if cmd_validate():
            return 1
        cmd_generate()
        cmd_compare()
        cmd_summary()
    return 0


if __name__ == "__main__":
    sys.exit(main())
