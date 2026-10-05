"""apply_quote_repair.py: only approved HIGH-confidence SAFE repairs are applied, nothing else changes, the old quote is kept.

Behavioural tests run in a scratch copy of the pilot that is rebuilt from the committed result by REVERTING the 22 applied
repairs (old quotes from the audit file, promoted snapshots removed, integrity blocks put back to RETRIEVED_UNVERIFIABLE). Applying
to that scratch copy must reproduce the committed evidence byte for byte. Nothing here touches the real tree or the network."""
import contextlib
import copy
import hashlib
import io
import json
import re
import shutil
import sys
import tempfile
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(HERE))
import apply_quote_repair as A  # noqa: E402
import enrichment_lib as L  # noqa: E402
import quote_repair as Q  # noqa: E402

STEMS = [s for s, _ in Q.PILOT]
AUDIT = HERE / "reports" / "pilot_quote_repair_audit.json"
NOW = "2000-01-01T00:00:00Z"
HEAD_RE = re.compile(r"^Quote repair applied to [^()]*\(reports/pilot_quote_repair_audit\.json\)\. ")


def tree_hash(root, *rel):
    h = hashlib.sha256()
    for r in rel:
        for p in sorted((Path(root) / r).rglob("*")):
            if p.is_file() and "__pycache__" not in p.parts:
                h.update(p.relative_to(root).as_posix().encode() + b"\0" + p.read_bytes())
    return h.hexdigest()


def make_pre_apply_root(dst: Path) -> Path:
    """Scratch copy of the pilot as it was before the approved repairs were applied."""
    audit = L.read_json(AUDIT)
    by_stem = {}
    for e in audit["entries"]:
        by_stem.setdefault(Path(e["evidence_file"]).stem, []).append(e)
    (dst / "evidence" / "_source_text").mkdir(parents=True)
    (dst / "reports").mkdir()
    shutil.copytree(Q.SNAP_DIR, dst / "reports" / "quote_repair_snapshots")
    for stem in STEMS:
        doc = L.read_json(HERE / "evidence" / f"{stem}.json")
        for sid, s in doc["sources"].items():
            integ = s["integrity"]
            if integ.get("snapshot_path"):
                if integ["origin"] != A.ORIGIN:
                    shutil.copyfile(HERE / integ["snapshot_path"], dst / integ["snapshot_path"])
        approved = {e["evidence_id"]: e for e in by_stem.get(stem, [])}
        for r in doc["records"]:
            if r["record_id"] in approved:
                r["evidence"]["supporting_text"] = approved[r["record_id"]]["previous_quote"]
        for sid, s in doc["sources"].items():
            integ = s["integrity"]
            if integ["origin"] == A.ORIGIN:  # promoted: back to the unpreserved state
                integ.update(state="RETRIEVED_UNVERIFIABLE", content_sha256=None, snapshot_path=None, origin="revalidation:refetch_content_mismatch", note="reverted for test")
                integ.pop("unconfirmed_record_ids", None)
            elif any(e["source_id"] == sid for e in approved.values()):
                integ["unconfirmed_record_ids"] = sorted(set(integ.get("unconfirmed_record_ids", [])) | {i for i, e in approved.items() if e["source_id"] == sid})
            s["integrity"] = {k: v for k, v in integ.items()}
        L.write_json(dst / "evidence" / f"{stem}.json", L.prepare_evidence(doc))
        rep = L.read_json(HERE / "reports" / f"{stem}_revalidation.json")
        for att in rep["attempts"]:
            if "note" in att:
                att["note"] = HEAD_RE.sub("", att["note"])
        L.write_json(dst / "reports" / f"{stem}_revalidation.json", rep)
    return dst


class Scratch(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        if not AUDIT.is_file() or not (Q.SNAP_DIR / "toyota_camry" / "CM-S1.txt").is_file():
            raise unittest.SkipTest("repairs not applied yet / candidate snapshots missing")
        cls.tmp = tempfile.TemporaryDirectory()
        cls.pre = make_pre_apply_root(Path(cls.tmp.name) / "pre")
        cls.pre_hash = tree_hash(cls.pre, "evidence", "reports")
        cls.plan = A.build_plan(cls.pre, expect_count=22, now=NOW)

    @classmethod
    def tearDownClass(cls):
        cls.tmp.cleanup()

    def fresh(self):
        d = Path(self.tmp.name) / f"w{len(list(Path(self.tmp.name).iterdir()))}"
        shutil.copytree(self.pre, d)
        return d


class Scope(Scratch):
    def test_scratch_really_is_the_pre_apply_state(self):
        self.assertEqual(tree_hash(self.pre, "evidence", "reports"), self.pre_hash)
        rep = self.plan["report"]
        self.assertEqual(sum(p["classification"] == Q.SAFE for p in rep["proposals"]), 23)

    def test_only_high_confidence_safe_proposals_are_selected(self):
        sel = self.plan["selected"]
        self.assertEqual(len(sel), 22)
        for p in sel:
            self.assertEqual((p["classification"], p["confidence"]), (Q.SAFE, "HIGH"), p["evidence_id"])
        ids = {p["evidence_id"] for p in sel}
        self.assertNotIn("FE-035", ids)
        self.assertNotIn("CM-001", ids)
        self.assertEqual(ids, {e["evidence_id"] for e in L.read_json(AUDIT)["entries"]})  # the same 22 as the committed apply

    def test_medium_confidence_is_refused(self):
        p = next(p for p in self.plan["report"]["proposals"] if p["evidence_id"] == "FE-035")
        self.assertEqual((p["classification"], p["confidence"]), (Q.SAFE, "MEDIUM"))
        self.assertIn("hard-blocked", A.refusal(p, "FE-035"))
        with self.assertRaises(A.ApplyError):
            A.build_plan(self.pre, ids=["FE-035"], expect_count=1, now=NOW)
        other = dict(p, evidence_id="ZZ-1")  # not hard-blocked: still refused for being MEDIUM
        self.assertIn("MEDIUM", A.refusal(other, "ZZ-1"))

    def test_factual_change_is_refused_even_by_id(self):
        p = next(p for p in self.plan["report"]["proposals"] if p["evidence_id"] == "CM-001")
        self.assertEqual(p["classification"], Q.FACT)
        with self.assertRaises(A.ApplyError) as cm:
            A.build_plan(self.pre, ids=["CM-001"], expect_count=1, now=NOW)
        self.assertIn("CM-001", str(cm.exception))
        self.assertIn("FACTUAL_CHANGE", A.refusal(dict(p, evidence_id="ZZ-2"), "ZZ-2"))

    def test_cm_001_is_blocked_even_if_the_report_said_it_was_safe(self):
        liar = {"classification": Q.SAFE, "confidence": "HIGH", "reason_code": "X", "proposed_exact_quote": "225 net combined hp"}
        self.assertIsNotNone(A.refusal(liar, "CM-001"))
        self.assertIsNotNone(A.refusal(liar, "FE-035"))
        self.assertEqual(A.eligible({"proposals": [dict(liar, evidence_id="CM-001"), dict(liar, evidence_id="FE-035")]}), [])
        self.assertIsNone(A.refusal(dict(liar, evidence_id="ZZ-3"), "ZZ-3"))

    def test_manual_review_is_refused(self):
        manual = [p for p in self.plan["report"]["proposals"] if p["classification"] == Q.MANUAL]
        self.assertGreater(len(manual), 50)
        for p in manual[:5]:
            self.assertIn("NEEDS_MANUAL_REVIEW", A.refusal(p, p["evidence_id"]))
        with self.assertRaises(A.ApplyError):
            A.build_plan(self.pre, ids=["CM-002", "FE-014"], expect_count=2, now=NOW)  # one refused id stops the whole run

    def test_unknown_or_already_verified_id_is_refused(self):
        with self.assertRaises(A.ApplyError):
            A.build_plan(self.pre, ids=["FE-001-NOPE"], expect_count=1, now=NOW)

    def test_wrong_expected_count_stops_everything(self):
        w = self.fresh()
        before = tree_hash(w, "evidence", "reports")
        for n in (21, 23, 0):
            with self.assertRaises(A.ApplyError):
                A.build_plan(w, expect_count=n, now=NOW)
        self.assertEqual(tree_hash(w, "evidence", "reports"), before)


class Result(Scratch):
    def test_ids_and_factual_fields_do_not_change(self):
        for stem in STEMS:
            old = L.read_json(self.pre / "evidence" / f"{stem}.json")
            new = self.plan["evidence"].get(stem)
            if new is None:
                continue
            approved = {p["evidence_id"] for p in self.plan["selected"]}
            self.assertEqual([r["record_id"] for r in old["records"]], [r["record_id"] for r in new["records"]])
            for ro, rn in zip(old["records"], new["records"]):
                vo, vn = A._authored_view(ro), A._authored_view(rn)
                if ro["record_id"] in approved:
                    self.assertNotEqual(vo["evidence"]["supporting_text"], vn["evidence"]["supporting_text"])
                    vo["evidence"].pop("supporting_text")
                    vn["evidence"].pop("supporting_text")
                self.assertEqual(vo, vn, ro["record_id"])  # every vehicle value, id, source id, year, market, trim, ... identical
            for sid, so in old["sources"].items():
                a, b = copy.deepcopy(so), copy.deepcopy(new["sources"][sid])
                a.pop("integrity"), b.pop("integrity")
                self.assertEqual(a, b, sid)  # source url / name / tier / ... identical

    def test_only_expected_files_are_written(self):
        w = self.fresh()
        plan = A.build_plan(w, expect_count=22, now=NOW)
        written = set(A.write_plan(plan, w))
        allowed = {f"evidence/{s}.json" for s in STEMS} | {f"reports/{s}_revalidation.json" for s in STEMS} | {"reports/pilot_quote_repair_audit.json"}
        promoted = {f"evidence/_source_text/{s}.txt" for s in ("FE-S4", "LC-S1", "LC-S2", "LC-S4", "LC-S6", "CM-S3", "CM-S4")}
        self.assertEqual(written, allowed | promoted)
        self.assertFalse(any("toyota/" in f for f in written))  # Toyota Batch 1 is never touched

    def test_round_trip_reproduces_the_committed_evidence_exactly(self):
        w = self.fresh()
        A.write_plan(A.build_plan(w, expect_count=22, now=NOW), w)
        for stem in STEMS:
            self.assertEqual((w / "evidence" / f"{stem}.json").read_bytes(), (HERE / "evidence" / f"{stem}.json").read_bytes(), stem)
            self.assertEqual((w / "reports" / f"{stem}_revalidation.json").read_bytes(), (HERE / "reports" / f"{stem}_revalidation.json").read_bytes(), stem)
        for e in L.read_json(AUDIT)["entries"]:
            self.assertEqual((w / e["snapshot_path"]).read_bytes(), (HERE / e["snapshot_path"]).read_bytes(), e["evidence_id"])

    def test_rerun_is_idempotent(self):
        w = self.fresh()
        A.write_plan(A.build_plan(w, expect_count=22, now=NOW), w)
        after_first = tree_hash(w, "evidence", "reports")
        again = A.build_plan(w, expect_count=22, now="2001-02-03T04:05:06Z")
        self.assertTrue(again["noop"])
        self.assertEqual(tree_hash(w, "evidence", "reports"), after_first)
        self.assertEqual(len(L.read_json(w / "reports" / "pilot_quote_repair_audit.json")["entries"]), 22)

    def test_audit_keeps_the_old_quote(self):
        w = self.fresh()
        A.write_plan(A.build_plan(w, expect_count=22, now=NOW), w)
        audit = L.read_json(w / "reports" / "pilot_quote_repair_audit.json")
        self.assertEqual(audit["schema_version"], A.AUDIT_SCHEMA)
        self.assertEqual(len(audit["entries"]), 22)
        old = {r["record_id"]: r["evidence"]["supporting_text"] for s in STEMS for r in L.read_json(self.pre / "evidence" / f"{s}.json")["records"]}
        new = {r["record_id"]: r["evidence"]["supporting_text"] for s in STEMS for r in L.read_json(w / "evidence" / f"{s}.json")["records"]}
        for e in audit["entries"]:
            self.assertEqual(e["previous_quote"], old[e["evidence_id"]])
            self.assertEqual(e["replacement_quote"], new[e["evidence_id"]])
            self.assertNotEqual(e["previous_quote"], e["replacement_quote"])
            self.assertEqual((e["reason"], e["proposal_classification"], e["proposal_confidence"], e["applied_at"]), ("quote_repair", Q.SAFE, "HIGH", NOW))
        self.assertEqual([e["evidence_id"] for e in audit["entries"]], sorted(e["evidence_id"] for e in audit["entries"]))

    def test_audit_does_not_influence_union_generation(self):
        w = self.fresh()
        A.write_plan(A.build_plan(w, expect_count=22, now=NOW), w)
        for stem in STEMS:
            doc = L.read_json(w / "evidence" / f"{stem}.json")
            conflicts = L.detect_conflicts(doc["records"], stem.replace("_", "-"))
            u1 = L.build_union(doc, conflicts, root=w)
            (w / "reports" / "pilot_quote_repair_audit.json").write_text("{}", encoding="utf-8")  # the audit is not an input
            self.assertEqual(u1, L.build_union(doc, conflicts, root=w))

    def test_report_afterwards_is_deterministic_and_drops_the_applied_records(self):
        w = self.fresh()
        A.write_plan(A.build_plan(w, expect_count=22, now=NOW), w)
        r1, r2 = Q.build_report(w, w / "reports" / "quote_repair_snapshots"), Q.build_report(w, w / "reports" / "quote_repair_snapshots")
        self.assertEqual(json.dumps(r1, sort_keys=True), json.dumps(r2, sort_keys=True))
        ids = {p["evidence_id"] for p in r1["proposals"]}
        applied = {e["evidence_id"] for e in L.read_json(w / "reports" / "pilot_quote_repair_audit.json")["entries"]}
        self.assertFalse(ids & applied)
        by = {p["evidence_id"]: p for p in r1["proposals"]}
        self.assertEqual(r1["summary"]["unresolved_records_analyzed"], 86 - 22)
        self.assertEqual(r1["summary"]["by_classification"], {Q.SAFE: 1, Q.FACT: 1, Q.MANUAL: 62})
        self.assertEqual((by["FE-035"]["classification"], by["FE-035"]["confidence"]), (Q.SAFE, "MEDIUM"))  # kept for later human review
        self.assertEqual(by["CM-001"]["classification"], Q.FACT)
        self.assertEqual(r1["summary"]["by_classification"], Q.build_report(w, w / "reports" / "quote_repair_snapshots")["summary"]["by_classification"])

    def test_nothing_unapproved_becomes_verified(self):
        w = self.fresh()
        A.write_plan(A.build_plan(w, expect_count=22, now=NOW), w)
        approved = {e["evidence_id"] for e in L.read_json(w / "reports" / "pilot_quote_repair_audit.json")["entries"]}
        before = {}
        for s in STEMS:
            d = L.read_json(self.pre / "evidence" / f"{s}.json")
            before.update({k: a["eligible"] for k, a in L.verify_snapshots(d, self.pre)[2].items()})
        for s in STEMS:
            d = L.read_json(w / "evidence" / f"{s}.json")
            errs, _t, assess = L.verify_snapshots(d, w)
            self.assertEqual(errs, [], s)
            self.assertEqual(L.validate_evidence(d), [], s)
            for rid, a in assess.items():
                self.assertEqual(a["eligible"], before[rid] or rid in approved, rid)


class Snapshots(Scratch):
    def test_promoted_snapshots_are_canonical_and_hash_matches(self):
        w = self.fresh()
        A.write_plan(A.build_plan(w, expect_count=22, now=NOW), w)
        for e in L.read_json(AUDIT)["entries"]:
            doc = L.read_json(w / e["evidence_file"])
            integ = doc["sources"][e["source_id"]]["integrity"]
            raw = (w / integ["snapshot_path"]).read_bytes()
            self.assertEqual(hashlib.sha256(raw).hexdigest(), integ["content_sha256"])
            self.assertEqual(integ["content_sha256"], e["snapshot_sha256"])
            self.assertTrue(integ["snapshot_path"].startswith("evidence/_source_text/"))
            self.assertIn(integ["state"], ("FULL_TEXT_VERIFIED", "PDF_VERIFIED"))
            rec = next(r for r in doc["records"] if r["record_id"] == e["evidence_id"])
            norm = L._ws(raw.decode("utf-8"))
            segs = L.quote_segments(rec["evidence"]["supporting_text"])
            self.assertEqual(segs, L.quote_segments(e["replacement_quote"]))
            self.assertTrue(segs and all(s in norm for s in segs), e["evidence_id"])  # exact text from the canonical snapshot
            if e["snapshot_promoted_from"]:
                self.assertEqual(integ["origin"], A.ORIGIN)
                self.assertEqual(raw, (w / e["snapshot_promoted_from"]).read_bytes())  # byte-for-byte copy of the candidate
                self.assertEqual(integ["previous_state"], "RETRIEVED_UNVERIFIABLE")

    def test_tampered_candidate_is_refused(self):
        w = self.fresh()
        cand = w / "reports" / "quote_repair_snapshots" / "toyota_camry" / "CM-S3.txt"
        cand.write_bytes(cand.read_bytes() + b"tampered\n")
        before = tree_hash(w, "evidence", "reports")
        with self.assertRaises(A.ApplyError):  # the tampered candidate no longer matches the re-validation hash: its proposals vanish, the count stops the run
            A.build_plan(w, expect_count=22, now=NOW)
        self.assertEqual(tree_hash(w, "evidence", "reports"), before)
        good = (self.pre / "reports" / "quote_repair_snapshots" / "toyota_camry" / "CM-S3.txt").read_bytes()
        with self.assertRaises(A.ApplyError) as cm:  # and the promotion step itself re-checks the hash
            A._validate_candidate("CM-S3", cand, hashlib.sha256(good).hexdigest(), [])
        self.assertIn("sha256", str(cm.exception))

    def test_existing_different_canonical_snapshot_is_never_overwritten(self):
        w = self.fresh()
        (w / "evidence" / "_source_text" / "LC-S2.txt").write_bytes(b"something else\n")
        with self.assertRaises(A.ApplyError) as cm:
            A.build_plan(w, expect_count=22, now=NOW)
        self.assertIn("refusing to overwrite", str(cm.exception))

    def test_candidate_must_be_canonical_snapshot_bytes(self):
        w = self.fresh()
        cand = w / "reports" / "quote_repair_snapshots" / "toyota_camry" / "CM-S4.txt"
        raw = cand.read_bytes()
        with self.assertRaises(A.ApplyError):
            A._validate_candidate("CM-S4", cand, hashlib.sha256(raw).hexdigest(), ["text that is not in the snapshot"])
        cand.write_bytes(raw.rstrip(b"\n"))  # no trailing newline: not the canonical byte form (hash is also checked first)
        with self.assertRaises(A.ApplyError):
            A._validate_candidate("CM-S4", cand, hashlib.sha256(cand.read_bytes()).hexdigest(), [])

    def test_promotion_that_would_verify_an_unapproved_record_is_refused(self):
        w = self.fresh()
        cand = (w / "reports" / "quote_repair_snapshots" / "toyota_land_cruiser" / "LC-S1.txt").read_text(encoding="utf-8")
        verbatim = L._ws(cand)[200:260]  # an exact passage of the page
        p = w / "evidence" / "toyota_land_cruiser.json"
        doc = L.read_json(p)
        next(r for r in doc["records"] if r["record_id"] == "LC-003")["evidence"]["supporting_text"] = verbatim  # LC-003 is NOT approved
        L.write_json(p, doc)
        with self.assertRaises(A.ApplyError) as cm:
            A.build_plan(w, expect_count=22, now=NOW)
        self.assertIn("LC-003", str(cm.exception))


class RealTree(unittest.TestCase):
    """The committed result."""

    @classmethod
    def setUpClass(cls):
        if not AUDIT.is_file():
            raise unittest.SkipTest("repairs not applied yet")
        cls.audit = L.read_json(AUDIT)

    def test_exactly_the_22_high_confidence_repairs_are_recorded(self):
        ids = [e["evidence_id"] for e in self.audit["entries"]]
        self.assertEqual(len(ids), 22)
        self.assertEqual(len(set(ids)), 22)
        self.assertNotIn("FE-035", ids)
        self.assertNotIn("CM-001", ids)

    def test_fe_035_and_cm_001_are_untouched(self):
        rep = L.read_json(Q.REPORT)
        by = {p["evidence_id"]: p for p in rep["proposals"]}
        fe, cm = by["FE-035"], by["CM-001"]
        self.assertEqual((fe["classification"], fe["confidence"]), (Q.SAFE, "MEDIUM"))
        self.assertEqual(cm["classification"], Q.FACT)
        recs = {r["record_id"]: r for s in STEMS for r in L.read_json(HERE / "evidence" / f"{s}.json")["records"]}
        self.assertEqual(recs["FE-035"]["evidence"]["supporting_text"], fe["old_quote"])
        self.assertEqual(recs["CM-001"]["evidence"]["supporting_text"], cm["old_quote"])
        self.assertIn("225 net combined hp", recs["CM-001"]["evidence"]["supporting_text"])
        self.assertEqual(recs["CM-001"]["engine"]["horsepower"]["value"], 225)
        cm_doc = L.read_json(HERE / "evidence" / "toyota_camry.json")
        self.assertEqual(L.source_integrity_state(cm_doc["sources"]["CM-S1"]), "RETRIEVED_UNVERIFIABLE")  # no snapshot promoted for the changed page
        self.assertFalse((HERE / "evidence" / "_source_text" / "CM-S1.txt").exists())

    def test_cli_refuses_cm_001_and_fe_035_without_touching_anything(self):
        before = tree_hash(HERE, "evidence", "generated", "reports")
        for i in ("CM-001", "FE-035"):
            with contextlib.redirect_stdout(io.StringIO()) as out:
                rc = A.main(["--evidence-id", i, "--expect-count", "1"])
            self.assertEqual(rc, 2, i)
            self.assertIn("REFUSED", out.getvalue())
        self.assertEqual(tree_hash(HERE, "evidence", "generated", "reports"), before)

    def test_cli_rerun_is_a_noop(self):
        before = tree_hash(HERE, "evidence", "generated", "reports")
        with contextlib.redirect_stdout(io.StringIO()) as out:
            rc = A.main(["--expect-count", "22"])
        self.assertEqual(rc, 0)
        self.assertIn("nothing to apply", out.getvalue())
        self.assertEqual(tree_hash(HERE, "evidence", "generated", "reports"), before)

    def test_applied_records_are_no_longer_outstanding(self):
        rep = L.read_json(Q.REPORT)
        self.assertFalse({p["evidence_id"] for p in rep["proposals"]} & {e["evidence_id"] for e in self.audit["entries"]})
        self.assertEqual(rep["summary"]["unresolved_records_analyzed"], 64)

    def test_audit_validates_against_the_manifest_semantics(self):
        manifest = L.read_json(HERE / "reports" / "evidence_manifest.json")
        for s in STEMS:
            errs, notes = L.check_manifest(L.read_json(HERE / "evidence" / f"{s}.json"), manifest[s])
            self.assertEqual((errs, notes), ([], []), s)

    # The frozen Batch 1 set. Later batches (Batch 2 ...) add further files next to these under evidence/toyota/, so this test
    # pins the Batch 1 files by NAME through their manifest instead of counting everything in the directory.
    TOYOTA_BATCH_1 = ["bz3", "bz3x", "bz4x", "frontlander", "grand_highlander", "prius_prime", "urban_cruiser", "veloz", "wigo", "yaris_cross"]

    def test_toyota_batch_1_is_unchanged(self):
        manifest = L.read_json(HERE / "reports" / "toyota_evidence_manifest.json")
        self.assertEqual(sorted(manifest), self.TOYOTA_BATCH_1)  # the manifest still freezes exactly Batch 1
        files = [HERE / "evidence" / "toyota" / f"{stem}.json" for stem in self.TOYOTA_BATCH_1]
        for f in files:
            self.assertTrue(f.is_file(), f.name)
            errs, notes = L.check_manifest(L.read_json(f), manifest.get(f.stem))
            self.assertEqual((errs, notes), ([], []), f.name)
        v = n = 0
        for stem in self.TOYOTA_BATCH_1:
            u = L.read_json(HERE / "generated" / "toyota" / f"{stem}.union.json")
            v += sum(len(x) for x in u["verified"].values())
            n += sum(len(x) for x in u["needs_source_retrieval"].values())
        self.assertEqual((v, n), (54, 36))


if __name__ == "__main__":
    unittest.main()
