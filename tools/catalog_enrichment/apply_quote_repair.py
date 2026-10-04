#!/usr/bin/env python3
"""Apply APPROVED, HIGH-confidence pilot quote repairs (proposed by quote_repair.py). Tooling only: never touches assets/ or lib/.

  python tools/catalog_enrichment/apply_quote_repair.py --dry-run --expect-count 22      # plan only, writes nothing
  python tools/catalog_enrichment/apply_quote_repair.py --expect-count 22                # apply
  python tools/catalog_enrichment/apply_quote_repair.py --expect-count 1 --evidence-id FE-014   # apply a chosen subset

Approval scope (enforced here, not just by the report): classification == SAFE_QUOTE_REPAIR AND confidence == HIGH.
Refused whatever the command line says: MEDIUM confidence, FACTUAL_CHANGE, NEEDS_MANUAL_REVIEW, anything that is not an
outstanding proposal, and the hard-blocked ids below (CM-001: the page now states 232 hp where the evidence says 225 hp;
FE-035: medium confidence, awaiting human review). The expected number of repairs must be given (--expect-count): if the
fresh report does not produce exactly that many eligible proposals NOTHING is applied.

What changes, per approved record: ONLY evidence.supporting_text (replaced by text copied verbatim from the canonical snapshot).
What changes, per source: the integrity block (state, snapshot_path, content_sha256, origin, note, unconfirmed_record_ids) -
and only after the candidate snapshot (reports/quote_repair_snapshots/...) has been re-validated (sha256 equals the content hash
recorded by the re-validation fetch, canonical snapshot bytes, long enough, contains every replacement segment) and copied
BYTE-FOR-BYTE to evidence/_source_text/<SOURCE_ID>.txt. The candidate copy is left where it is (nothing is deleted).
Every applied repair is appended to reports/pilot_quote_repair_audit.json (old quote, new quote, snapshot hash, time); that file
is a review artefact and never read by union generation.

Before anything is written the complete result is validated in a scratch directory (record structure, traceability, snapshot
hashes, exact unconfirmed listing, factual fields identical, no unapproved record becomes verified). Re-running is a no-op.
"""
from __future__ import annotations

import argparse
import copy
import datetime as _dt
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import enrichment_lib as L  # noqa: E402
import fetch_snapshot as F  # noqa: E402
import quote_repair as Q  # noqa: E402

AUDIT_SCHEMA = "carnet.quote_repair_audit/1"
REASON = "quote_repair"
ORIGIN = "quote_repair:promoted_candidate_snapshot"
HARD_BLOCK = {
    "CM-001": "FACTUAL_CHANGE: the evidence says 225 hp, the current page says 232 hp. A changed fact is never repaired as formatting.",
    "FE-035": "MEDIUM confidence: awaiting human review; only HIGH-confidence proposals are approved.",
}


class ApplyError(Exception):
    pass


def utc_now() -> str:
    return _dt.datetime.now(_dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


# ----------------------------------------------------------------------------------------------------------------
# eligibility
# ----------------------------------------------------------------------------------------------------------------
def refusal(p: dict | None, evidence_id: str) -> str | None:
    """Why `evidence_id` may not be applied (None = it may)."""
    if evidence_id in HARD_BLOCK:
        return f"{evidence_id} is hard-blocked - {HARD_BLOCK[evidence_id]}"
    if p is None:
        return f"{evidence_id} is not an outstanding proposal (unknown, already applied, or already verified)"
    if p["classification"] != Q.SAFE:
        return f"{evidence_id} is {p['classification']} ({p['reason_code']}); only SAFE_QUOTE_REPAIR may be applied"
    if p.get("confidence") != "HIGH":
        return f"{evidence_id} has {p.get('confidence')} confidence; only HIGH confidence may be applied"
    if not p.get("proposed_exact_quote"):
        return f"{evidence_id} carries no proposed quote"
    return None


def eligible(report: dict) -> list[dict]:
    return [p for p in report["proposals"] if refusal(p, p["evidence_id"]) is None]


# ----------------------------------------------------------------------------------------------------------------
# helpers
# ----------------------------------------------------------------------------------------------------------------
def _authored_view(rec: dict) -> dict:
    """Everything about a record except derived fields (two views are equal iff no authored value differs)."""
    r = copy.deepcopy(rec)
    r.pop("normalized", None)
    r.pop("normalization_flags", None)
    (r.get("engine") or {}).pop("displacement_cc", None)
    for k in L._DERIVED_EVIDENCE_KEYS:
        (r.get("evidence") or {}).pop(k, None)
    return r


def _norm_text(raw: bytes) -> str:
    return L._ws(raw.decode("utf-8"))


def _unconfirmed(doc: dict, sid: str, norm: str) -> list[str]:
    return sorted(r["record_id"] for r in doc["records"] if r["evidence"]["source_id"] == sid
                  and any(g not in norm for g in L.quote_segments(r["evidence"]["supporting_text"])))


def _validate_candidate(sid: str, cand: Path, expected_sha: str, segments: list[str]) -> bytes:
    """Re-validate a candidate snapshot before it may become canonical evidence."""
    if not cand.is_file():
        raise ApplyError(f"{sid}: candidate snapshot {cand} is missing")
    raw = cand.read_bytes()
    if Q._sha(raw) != expected_sha:
        raise ApplyError(f"{sid}: candidate snapshot sha256 {Q._sha(raw)[:16]}... differs from the hash recorded by the re-validation fetch {expected_sha[:16]}...")
    try:
        text = raw.decode("utf-8")
    except UnicodeDecodeError as e:
        raise ApplyError(f"{sid}: candidate snapshot is not valid UTF-8: {e}")
    if F.snapshot_bytes(text) != raw:
        raise ApplyError(f"{sid}: candidate snapshot is not in the canonical snapshot byte form")
    if len(text.strip()) < F.MIN_TEXT_CHARS:
        raise ApplyError(f"{sid}: candidate snapshot has no usable text")
    norm = L._ws(text)
    for g in segments:
        if g not in norm:
            raise ApplyError(f"{sid}: replacement segment not found verbatim in the candidate snapshot: {g[:80]!r}")
    return raw


def _promoted_integrity(src: dict, old: dict, sha: str, path: str, n_recs: int, n_missing: int) -> dict:
    integ = {k: old[k] for k in ("retrieved_at", "retrieved_by", "final_url", "http_status", "content_type", "raw_sha256", "extractor") if k in old}
    pdf = L.is_pdf_source(src) and "pdf" in str(old.get("extractor") or "").lower()
    integ.update(
        previous_state=old["state"], state="PDF_VERIFIED" if pdf else "FULL_TEXT_VERIFIED", content_sha256=sha, snapshot_path=path, origin=ORIGIN,
        note=(f"Content retrieved at {old['retrieved_at']} (hash recorded by the re-validation fetch). Re-validated from the stored candidate snapshot and promoted to "
              "canonical evidence after review of the quote repair (reports/pilot_quote_repair_audit.json). "
              + (f"{n_missing} of {n_recs} records' quotes are NOT in the content (listed in unconfirmed_record_ids, never verified)." if n_missing
                 else "Every cited quote is in the preserved content.")),
    )
    return integ


# ----------------------------------------------------------------------------------------------------------------
# plan (reads and validates; writes nothing)
# ----------------------------------------------------------------------------------------------------------------
def build_plan(root: Path = HERE, snap_dir: Path | None = None, ids: list[str] | None = None, expect_count: int | None = None, now: str | None = None) -> dict:
    now = now or utc_now()
    snap_dir = snap_dir or root / "reports" / "quote_repair_snapshots"
    report = Q.build_report(root, snap_dir)
    by_id = {p["evidence_id"]: p for p in report["proposals"]}
    audit_path = root / "reports" / "pilot_quote_repair_audit.json"
    audit = L.read_json(audit_path) if audit_path.exists() else {
        "schema_version": AUDIT_SCHEMA, "tooling_only": True,
        "note": "One entry per applied pilot quote repair. Review artefact: never read by union generation.", "entries": []}
    plan = {"selected": [], "snapshots": {}, "evidence": {}, "revalidation": {}, "audit": audit, "audit_path": audit_path, "noop": False, "report": report}

    if ids:
        bad = [r for r in (refusal(by_id.get(i), i) for i in dict.fromkeys(ids)) if r]
        if bad:
            raise ApplyError("refused, nothing applied:\n  " + "\n  ".join(bad))
        selected = [by_id[i] for i in dict.fromkeys(ids)]
    else:
        selected = eligible(report)
    if not selected:
        if audit["entries"]:  # re-run after a successful apply
            plan["noop"] = True
            return plan
        raise ApplyError("no eligible HIGH-confidence proposal and nothing applied before")
    if expect_count is not None and len(selected) != expect_count:
        raise ApplyError(f"expected exactly {expect_count} eligible HIGH-confidence proposals but the fresh report produces {len(selected)}: "
                         f"{[p['evidence_id'] for p in selected]}. STOP - nothing applied.")
    selected.sort(key=lambda p: p["evidence_id"])
    plan["selected"] = selected
    approved_ids = {p["evidence_id"] for p in selected}

    stems = sorted({Path(p["evidence_file"]).stem for p in selected})
    old_docs = {s: L.read_json(root / "evidence" / f"{s}.json") for s in stems}
    new_docs = {s: copy.deepcopy(d) for s, d in old_docs.items()}
    reval = {s: L.read_json(root / "reports" / f"{s}_revalidation.json") for s in stems}
    reval_by = {s: {a["source_id"]: a for a in r["attempts"]} for s, r in reval.items()}
    new_snaps: dict[str, bytes] = {}  # canonical relative path -> validated bytes about to be created
    promoted: dict[tuple, bytes] = {}
    per_source: dict[tuple, list[dict]] = {}
    for p in selected:
        per_source.setdefault((Path(p["evidence_file"]).stem, p["source_id"]), []).append(p)

    # 1. re-validate the candidate snapshots that are about to become canonical evidence
    for (stem, sid), props in sorted(per_source.items()):
        if not props[0]["application_requires_snapshot_promotion"]:
            continue
        att = reval_by[stem].get(sid)
        if not att or not att.get("content_sha256"):
            raise ApplyError(f"{sid}: no re-validation fetch hash recorded")
        raw = _validate_candidate(sid, root / props[0]["snapshot_path"], att["content_sha256"], [g for p in props for g in p["proposed_segments"]])
        rel = f"evidence/_source_text/{sid}.txt"
        if (root / rel).exists() and (root / rel).read_bytes() != raw:
            raise ApplyError(f"{sid}: {rel} already exists with different content; refusing to overwrite a preserved snapshot")
        new_snaps[rel] = raw
        promoted[(stem, sid)] = raw

    # 2. replace the quotes (the only authored field that changes)
    for p in selected:
        stem = Path(p["evidence_file"]).stem
        rec = next((r for r in new_docs[stem]["records"] if r["record_id"] == p["evidence_id"]), None)
        if rec is None or rec["evidence"]["source_id"] != p["source_id"]:
            raise ApplyError(f"{p['evidence_id']}: record/source not found in {p['evidence_file']}")
        if rec["evidence"]["supporting_text"] != p["old_quote"]:
            raise ApplyError(f"{p['evidence_id']}: the current quote is not the one the proposal was computed from")
        rec["evidence"]["supporting_text"] = p["proposed_exact_quote"]

    # 3. integrity blocks of the affected sources
    for (stem, sid), props in sorted(per_source.items()):
        doc = new_docs[stem]
        src = doc["sources"][sid]
        recs = [r for r in doc["records"] if r["evidence"]["source_id"] == sid]
        if (stem, sid) in promoted:
            raw = promoted[(stem, sid)]
            miss = _unconfirmed(doc, sid, _norm_text(raw))
            src["integrity"] = _promoted_integrity(src, old_docs[stem]["sources"][sid]["integrity"], Q._sha(raw), f"evidence/_source_text/{sid}.txt", len(recs), len(miss))
            verified_now = {r["record_id"] for r in recs if r["record_id"] not in miss}
            wanted = {p["evidence_id"] for p in props}
            if verified_now != wanted:  # a record nobody approved must never become verified as a side effect
                raise ApplyError(f"{sid}: promoting the snapshot would verify {sorted(verified_now - wanted)} / not verify {sorted(wanted - verified_now)}; not exactly the approved records")
        else:
            if L.source_integrity_state(src) not in L.VERIFIED_ELIGIBLE_STATES:
                raise ApplyError(f"{sid}: no preserved snapshot and the proposal does not require promotion")
            miss = _unconfirmed(doc, sid, _norm_text((root / src["integrity"]["snapshot_path"]).read_bytes()))
        if miss:
            src["integrity"]["unconfirmed_record_ids"] = miss
        else:
            src["integrity"].pop("unconfirmed_record_ids", None)
        doc["sources"][sid] = L._order_source(src)

    # 4. derived fields, then prove that only the approved quotes (and the integrity blocks) differ
    for stem in stems:
        new_docs[stem] = L.prepare_evidence(new_docs[stem])
        old, new = old_docs[stem], new_docs[stem]
        if [r["record_id"] for r in old["records"]] != [r["record_id"] for r in new["records"]]:
            raise ApplyError(f"{stem}: record ids / order changed")
        for ro, rn in zip(old["records"], new["records"]):
            vo, vn = _authored_view(ro), _authored_view(rn)
            if ro["record_id"] in approved_ids:
                vo["evidence"].pop("supporting_text")
                vn["evidence"].pop("supporting_text")
            if vo != vn:
                raise ApplyError(f"{ro['record_id']}: an authored field other than the quote would change")
        for sid, so in old["sources"].items():
            a, b = copy.deepcopy(so), copy.deepcopy(new["sources"][sid])
            a.pop("integrity", None)
            b.pop("integrity", None)
            if a != b:
                raise ApplyError(f"{stem} {sid}: source fields other than integrity would change")
        for k in old:
            if k not in ("records", "sources", "schema_version") and old[k] != new[k]:
                raise ApplyError(f"{stem}: top-level field {k} would change")

    # 5. validate the complete result in a scratch directory
    with tempfile.TemporaryDirectory() as td:
        troot = Path(td)
        for stem in stems:
            doc = new_docs[stem]
            errs = L.validate_evidence(doc)
            for s in doc["sources"].values():
                if L.source_integrity_state(s) in L.VERIFIED_ELIGIBLE_STATES:
                    rel = s["integrity"]["snapshot_path"]
                    (troot / rel).parent.mkdir(parents=True, exist_ok=True)
                    (troot / rel).write_bytes(new_snaps[rel] if rel in new_snaps else (root / rel).read_bytes())
            verr, _t, assess = L.verify_snapshots(doc, troot)
            errs += verr
            for pid in sorted(approved_ids):
                if pid in assess and not assess[pid]["eligible"]:
                    errs.append(f"{pid}: still not verified after the repair ({assess[pid]['reason']})")
            if errs:
                raise ApplyError(f"{stem}: the result does not validate, nothing applied:\n  " + "\n  ".join(errs[:10]))

    # 6. refreshed re-validation reports (offline, same diagnosis as fetch_snapshot) and audit entries
    for stem in stems:
        doc = new_docs[stem]
        rep = copy.deepcopy(reval[stem])
        for att in rep["attempts"]:
            sid = att["source_id"]
            touched = [p for p in selected if p["source_id"] == sid]
            if not touched:
                continue
            integ = doc["sources"][sid]["integrity"]
            norm = _norm_text(new_snaps[integ["snapshot_path"]] if integ["snapshot_path"] in new_snaps else (root / integ["snapshot_path"]).read_bytes())
            recs = [r for r in doc["records"] if r["evidence"]["source_id"] == sid]
            missing = {r["record_id"]: [g for g in L.quote_segments(r["evidence"]["supporting_text"]) if g not in norm] for r in recs}
            missing = {k: v for k, v in missing.items() if v}
            head = "Quote repair applied to " + ", ".join(sorted(p["evidence_id"] for p in touched)) + " (reports/pilot_quote_repair_audit.json). "
            att.update(new_state=integ["state"], outcome="PARTIAL_CONFIRMED" if missing else "CONFIRMED", records_total=len(recs), records_confirmed=len(recs) - len(missing),
                       records_unconfirmed=[{"record_id": k, "diagnosis": F._diagnose(v, norm), "missing_segments": [g[:140] for g in v]} for k, v in sorted(missing.items())],
                       note=head + (integ["note"] if (stem, sid) in promoted else (att.get("note") or "")))
        plan["revalidation"][stem] = rep
    for p in selected:
        promo = p["application_requires_snapshot_promotion"]
        plan["audit"]["entries"].append({
            "evidence_id": p["evidence_id"], "evidence_file": p["evidence_file"], "source_id": p["source_id"], "reason": REASON,
            "previous_quote": p["old_quote"], "replacement_quote": p["proposed_exact_quote"],
            "proposal_classification": p["classification"], "proposal_confidence": p["confidence"], "proposal_reason_code": p["reason_code"],
            "snapshot_path": f"evidence/_source_text/{p['source_id']}.txt" if promo else p["snapshot_path"],
            "snapshot_sha256": p["snapshot_sha256"], "snapshot_promoted_from": p["snapshot_path"] if promo else None, "applied_at": now,
        })
    plan["audit"]["entries"].sort(key=lambda e: e["evidence_id"])
    plan["evidence"], plan["snapshots"] = new_docs, new_snaps
    return plan


def write_plan(plan: dict, root: Path = HERE) -> list[str]:
    written = []
    for rel, raw in sorted(plan["snapshots"].items()):
        dest = root / rel
        dest.parent.mkdir(parents=True, exist_ok=True)
        dest.write_bytes(raw)
        if Q._sha(dest.read_bytes()) != Q._sha(raw):
            raise ApplyError(f"{rel}: written snapshot does not hash to the validated bytes")
        written.append(rel)
    for stem, rep in sorted(plan["revalidation"].items()):
        L.write_json(root / "reports" / f"{stem}_revalidation.json", rep)
        written.append(f"reports/{stem}_revalidation.json")
    L.write_json(plan["audit_path"], plan["audit"])
    written.append(plan["audit_path"].relative_to(root).as_posix())
    for stem, doc in sorted(plan["evidence"].items()):
        L.write_json(root / "evidence" / f"{stem}.json", doc)
        written.append(f"evidence/{stem}.json")
    return written


# ----------------------------------------------------------------------------------------------------------------
def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--expect-count", type=int, help="the number of eligible HIGH-confidence proposals the reviewer approved (required to write)")
    ap.add_argument("--evidence-id", action="append", help="apply only this id (repeatable); refused unless eligible")
    ap.add_argument("--dry-run", action="store_true", help="plan and validate, write nothing")
    a = ap.parse_args(argv)
    if a.expect_count is None and not a.dry_run:
        ap.error("--expect-count is required when writing")
    try:
        plan = build_plan(ids=a.evidence_id, expect_count=a.expect_count)
        if plan["noop"]:
            print(f"nothing to apply: no outstanding eligible proposal ({len(plan['audit']['entries'])} repairs already applied, see reports/pilot_quote_repair_audit.json)")
            return 0
        sel = plan["selected"]
        print(f"eligible HIGH-confidence SAFE_QUOTE_REPAIR proposals: {len(sel)}: " + ", ".join(p["evidence_id"] for p in sel))
        print("snapshots to promote: " + (", ".join(sorted(plan["snapshots"])) or "none"))
        if a.dry_run:
            print("dry run: nothing written")
            return 0
        for f in write_plan(plan):
            print("wrote", f)
    except ApplyError as e:
        print(f"REFUSED: {e}")
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
