"""Dry-run quote-repair proposals (quote_repair.py).

Unit tests use synthetic snapshots (offline, no files). The real-data tests read the committed pilot evidence, its re-validation
reports and the stored candidate snapshots, and prove that the tool is read-only, deterministic and conservative."""
import contextlib
import copy
import hashlib
import io
import json
import sys
import tempfile
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(HERE))
import enrichment_lib as L  # noqa: E402
import quote_repair as Q  # noqa: E402

MODEL = "Acme Roadster"
FILLER = "The Roadster range is described in detail on this page, including engines, transmissions, equipment and warranty terms for the market.\n"


def rec(quote, trim=None, year=None, hp=None, tq=None, **eng):
    e = {"display_name": None, "displacement_raw": None, "cylinders": None, "fuel_type": None, "aspiration": None, "horsepower": None, "torque": None}
    e.update(eng)
    if hp:
        e["horsepower"] = {"value": hp[0], "unit": hp[1]}
    if tq:
        e["torque"] = {"value": tq[0], "unit": tq[1]}
    return {"record_id": "T-001", "brand": "Acme", "model": "Roadster", "year_from": year, "year_to": year, "market": None, "trim": trim, "variant": None,
            "body_type": None, "doors": None, "seats": None, "drivetrain": None, "engine": e,
            "transmission": {"type": None, "gears": None}, "notes": None, "evidence": {"source_id": "T-S1", "supporting_text": quote}}


def run(record, snapshot_text, trims=("Base", "Sport")):
    return Q.analyze_record(record, Q.Snap(snapshot_text), list(trims), MODEL)


class SafeRepairs(unittest.TestCase):
    def test_whitespace_only_reflow(self):
        snap = FILLER + "The Acme Roadster 2.5L\nPetrol engine delivers 201 hp\nwith 4WD as standard.\n" + FILLER
        old = "The Acme Roadster 2.5L Petrol engine delivers 201 hp with 4WD as standard."
        r = run(rec(old, displacement_raw="2.5L", fuel_type="Petrol", hp=(201, "hp")), snap)
        self.assertEqual(r["classification"], Q.SAFE, r["reason"])
        self.assertIn("The Acme Roadster 2.5L\nPetrol", snap)  # the exact (un-normalised) text is what is in the snapshot ...
        self.assertTrue(all(s in L._ws(snap) for s in r["proposed_segments"]))  # ... and the proposal reads from it
        self.assertEqual(r["confidence"], "HIGH")

    def test_punctuation_only_change(self):
        snap = FILLER + "The Roadster\u2019s 2.5L petrol engine \u2013 rated at 201 hp \u2013 drives all four wheels.\n" + FILLER
        old = "The Roadster's 2.5L petrol engine - rated at 201 hp - drives all four wheels."
        r = run(rec(old, displacement_raw="2.5L", fuel_type="petrol", hp=(201, "hp")), snap)
        self.assertEqual(r["classification"], Q.SAFE, r["reason"])
        self.assertIn("\u2019", r["proposed_exact_quote"])  # exact snapshot characters, not the old straight quote
        self.assertNotIn("Roadster's", r["proposed_exact_quote"])

    def test_non_breaking_space_and_case(self):
        snap = FILLER + "ACME ROADSTER 2.5L\u00a0PETROL delivers 201\u00a0hp and 250\u00a0Nm.\n" + FILLER
        old = "Acme Roadster 2.5L Petrol delivers 201 hp and 250 Nm."
        r = run(rec(old, displacement_raw="2.5L", fuel_type="Petrol", hp=(201, "hp"), tq=(250, "Nm")), snap)
        self.assertEqual(r["classification"], Q.SAFE, r["reason"])
        self.assertIn("\u00a0", snap)  # the snapshot really holds non-breaking spaces; the validator collapses them like any whitespace
        self.assertTrue(all(s in L._ws(snap) for s in r["proposed_segments"]))

    def test_unit_written_with_a_dot(self):
        snap = FILLER + "| Acme Roadster 2.4L turbo | 243 kW (330 PS) | 630 N\u00b7m |\n" + FILLER
        old = "Acme Roadster 2.4L turbo 330 PS 630 Nm"
        r = run(rec(old, displacement_raw="2.4L", aspiration="turbo", hp=(330, "PS"), tq=(630, "Nm")), snap)
        self.assertEqual(r["classification"], Q.SAFE, r["reason"])

    TABLE = (FILLER + "Gasoline specifications\n| Grade | Seating | Engine | Transmission | Price |\n| --- | --- | --- | --- | --- |\n"
             "| GX | 5 | V35A (3.5-liter) | Direct Shift-10AT | 5,100,000 |\n| AX | 7 | V35A (3.5-liter) | Direct Shift-10AT | 5,500,000 |\n" + FILLER)

    def _table_rec(self, trim, seats):
        r = rec("Gasoline specifications Grade Seating Engine Transmission Price %s %d V35A (3.5-liter) Direct Shift-10AT" % (trim, seats),
                trim=trim, displacement_raw="3.5-liter", fuel_type="Gasoline")
        r["seats"] = seats
        r["transmission"]["type"] = "Direct Shift-10AT"
        return r

    def test_table_reflow(self):
        r = run(self._table_rec("GX", 5), self.TABLE, trims=("GX", "AX"))
        self.assertEqual(r["classification"], Q.SAFE, r["reason"])
        self.assertIn("| GX | 5 | V35A (3.5-liter) | Direct Shift-10AT", r["proposed_exact_quote"])
        self.assertNotIn("AX", r["proposed_exact_quote"])  # the neighbouring row is not swept in

    def test_table_second_row_never_borrows_the_first_row(self):
        # AX is the second row; the only contiguous slice from the header to it contains the GX row, so it is not auto-repaired
        r = run(self._table_rec("AX", 7), self.TABLE, trims=("GX", "AX"))
        if r["classification"] == Q.SAFE:
            self.assertNotIn("GX", r["proposed_exact_quote"])
        else:
            self.assertEqual(r["classification"], Q.MANUAL)

    def test_table_seats_of_another_row_do_not_count(self):
        # GX is a 5-seater in the snapshot; an authored GX with 7 seats must not be 'repaired' with the AX row's 7
        r = run(self._table_rec("GX", 7), self.TABLE, trims=("GX", "AX"))
        self.assertNotEqual(r["classification"], Q.SAFE)

    def test_same_value_in_exact_preserved_text(self):
        snap = FILLER + "The Acme Roadster 2.5L Petrol delivers 201 hp.\n" + FILLER
        old = "The Acme Roadster 2.5L Petrol delivers 201 hp."
        r = run(rec(old, displacement_raw="2.5L", fuel_type="Petrol", hp=(201, "hp")), snap)
        self.assertEqual(r["classification"], Q.SAFE, r["reason"])
        self.assertEqual(L._ws(r["proposed_exact_quote"]), L._ws(old))

    def test_ellipsis_spliced_old_quote_gets_exact_segments(self):
        snap = FILLER + "The Acme Roadster 2.5L Petrol delivers 201 hp.\n" + FILLER * 3 + "Every Roadster seats up to seven adults.\n" + FILLER
        old = "The Acme Roadster 2.5L Petrol delivers 201 hp. Every Roadster seats up to seven adults."
        r = run(rec(old, displacement_raw="2.5L", fuel_type="Petrol", hp=(201, "hp")), snap)
        self.assertEqual(r["classification"], Q.SAFE, r["reason"])
        self.assertTrue(all(s in L._ws(snap) for s in L.quote_segments(r["proposed_exact_quote"])))


class NotSafe(unittest.TestCase):
    def test_different_horsepower_is_a_factual_change(self):
        snap = FILLER + "The Acme Roadster 2.5L hybrid delivers 232 net combined hp for strong acceleration.\n" + FILLER
        old = "The Acme Roadster 2.5L hybrid delivers 225 net combined hp for strong acceleration."
        r = run(rec(old, displacement_raw="2.5L", fuel_type="hybrid", hp=(225, "hp")), snap)
        self.assertEqual(r["classification"], Q.FACT, r["reason"])
        self.assertIsNone(r["proposed_exact_quote"])
        self.assertEqual(r["factual_change"]["authored"], "225")
        self.assertIn("232", r["factual_change"]["snapshot_numbers"])

    def test_different_torque_displacement_seats_gears_are_factual_changes(self):
        for old_phrase, new_phrase, kw in [
            ("delivers 250 Nm of torque", "delivers 270 Nm of torque", {"tq": (250, "Nm")}),
            ("with a 2.0L turbo engine", "with a 2.4L turbo engine", {"displacement_raw": "2.0L"}),
        ]:
            snap = FILLER + f"The Acme Roadster {new_phrase} for the market.\n" + FILLER
            r = run(rec(f"The Acme Roadster {old_phrase} for the market.", **kw), snap)
            self.assertNotEqual(r["classification"], Q.SAFE, (old_phrase, r["reason"]))

    def test_shared_snapshot_each_record_matches_its_own_values(self):
        snap = FILLER + "The Acme Roadster 2.5L Petrol delivers 201 hp. The Acme Roadster 3.5L V6 Petrol delivers 301 hp.\n" + FILLER
        a = run(rec("The Acme Roadster 2.5L Petrol delivers 201 hp.", displacement_raw="2.5L", fuel_type="Petrol", hp=(201, "hp")), snap)
        b = run(rec("The Acme Roadster 3.5L V6 Petrol delivers 300 hp.", displacement_raw="3.5L", fuel_type="Petrol", hp=(300, "hp")), snap)
        self.assertEqual(a["classification"], Q.SAFE, a["reason"])
        self.assertNotEqual(b["classification"], Q.SAFE)  # the same source never lends a quote to a record with a different value

    def test_value_not_stated_any_more(self):
        snap = FILLER + "The Acme Roadster 2.5L Petrol is a comfortable family car.\n" + FILLER
        r = run(rec("The Acme Roadster 2.5L Petrol delivers 201 hp.", displacement_raw="2.5L", fuel_type="Petrol", hp=(201, "hp")), snap)
        self.assertEqual(r["classification"], Q.MANUAL)
        self.assertIn("engine.horsepower", r["authored_values_unsupported"])

    def test_different_year_context_is_not_safe(self):
        snap = FILLER + "The 2019 Acme Roadster 2.5L Petrol delivers 201 hp.\n" + FILLER
        r = run(rec("The Acme Roadster 2.5L Petrol delivers 201 hp.", year=2026, displacement_raw="2.5L", fuel_type="Petrol", hp=(201, "hp")), snap)
        self.assertEqual(r["classification"], Q.MANUAL)
        self.assertEqual(r["reason_code"], "YEAR_CONTEXT")
        ok = run(rec("The Acme Roadster 2.5L Petrol delivers 201 hp.", year=2019, displacement_raw="2.5L", fuel_type="Petrol", hp=(201, "hp")), snap)
        self.assertEqual(ok["classification"], Q.SAFE, ok["reason"])  # same text, matching year -> fine

    def test_different_trim_context_is_not_safe(self):
        snap = FILLER + "The Acme Roadster Sport 2.5L Petrol delivers 201 hp.\n" + FILLER
        old = "The Acme Roadster Base 2.5L Petrol delivers 201 hp."
        r = run(rec(old, trim="Base", displacement_raw="2.5L", fuel_type="Petrol", hp=(201, "hp")), snap)
        self.assertNotEqual(r["classification"], Q.SAFE, r["reason"])
        self.assertIn("trim", r["authored_values_unsupported"])

    def test_trim_listed_next_to_other_trims_is_not_safe(self):
        snap = FILLER + "Trims: Base Sport. The Acme Roadster Base Sport 2.5L Petrol delivers 201 hp.\n" + FILLER
        r = run(rec("The Acme Roadster Base 2.5L Petrol delivers 201 hp.", trim="Base", displacement_raw="2.5L", fuel_type="Petrol", hp=(201, "hp")), snap)
        self.assertNotEqual(r["classification"], Q.SAFE, r["reason"])

    def test_ambiguous_surrounding_text_needs_manual_review(self):
        para = "The Acme Roadster 2.5L Petrol delivers 201 hp on every model in the range.\n"
        snap = FILLER + para + FILLER + para + FILLER
        r = run(rec(para.strip(), displacement_raw="2.5L", fuel_type="Petrol", hp=(201, "hp")), snap)
        self.assertEqual(r["classification"], Q.MANUAL)
        self.assertEqual(r["reason_code"], "AMBIGUOUS_LOCATION")

    def test_old_quote_not_in_snapshot_at_all(self):
        r = run(rec("Something entirely different was written here originally.", displacement_raw="2.5L"), FILLER * 3)
        self.assertEqual(r["classification"], Q.MANUAL)

    def test_no_snapshot(self):
        r = Q.analyze_record(rec("The Acme Roadster 2.5L Petrol delivers 201 hp.", displacement_raw="2.5L"), None, [], MODEL)
        self.assertEqual((r["classification"], r["reason_code"]), (Q.MANUAL, "NO_SNAPSHOT"))

    def test_model_must_stay_named(self):
        snap = FILLER.replace("Roadster", "Vehicle") + "The Acme Roadster 2.5L Petrol delivers 201 hp.\n"
        r = run(rec("The Acme Roadster 2.5L Petrol delivers 201 hp.", displacement_raw="2.5L", hp=(201, "hp")), snap)
        self.assertEqual(r["classification"], Q.SAFE)
        self.assertIn("Roadster", r["proposed_exact_quote"])  # pruning never drops the model name the old quote used

    def test_column_ambiguity_is_never_resolved_by_guessing(self):
        snap = FILLER + "Acme Roadster Output 201 hp 250 hp 301 hp\n" + FILLER
        r = run(rec("Acme Roadster Output 201 hp 250 hp 301 hp", hp=(250, "hp")), snap)
        self.assertEqual(r["classification"], Q.MANUAL)
        self.assertEqual(r["reason_code"], "COLUMN_OR_VARIANT_AMBIGUITY")


def _pilot():
    out = {}
    for stem, name in Q.PILOT:
        out[stem] = (name, L.read_json(HERE / "evidence" / f"{stem}.json"))
    return out


def _tree_hash(*dirs):
    h = hashlib.sha256()
    for d in dirs:
        for p in sorted(Path(d).rglob("*")):
            if p.is_file() and "__pycache__" not in p.parts:
                h.update(p.relative_to(HERE).as_posix().encode() + b"\0" + p.read_bytes())
    return h.hexdigest()


class RealPilot(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        if not (Q.SNAP_DIR / "toyota_camry" / "CM-S1.txt").is_file():
            raise unittest.SkipTest("candidate snapshots not present (run quote_repair.py --collect)")
        cls.before = _tree_hash(HERE / "evidence", HERE / "generated")
        cls.report = Q.build_report()
        cls.report2 = Q.build_report()
        cls.by_id = {p["evidence_id"]: p for p in cls.report["proposals"]}

    def test_deterministic(self):
        self.assertEqual(json.dumps(self.report, sort_keys=True), json.dumps(self.report2, sort_keys=True))
        with tempfile.TemporaryDirectory() as td:
            a, b = Path(td) / "a.json", Path(td) / "b.json"
            L.write_json(a, self.report)
            L.write_json(b, self.report2)
            self.assertEqual(a.read_bytes(), b.read_bytes())

    def test_committed_report_is_current(self):
        p = Q.REPORT
        self.assertTrue(p.is_file(), "run: python tools/catalog_enrichment/quote_repair.py")
        with tempfile.TemporaryDirectory() as td:
            t = Path(td) / "fresh.json"
            L.write_json(t, self.report)
            self.assertEqual(p.read_bytes(), t.read_bytes(), "reports/pilot_quote_repair_proposals.json is stale - re-run quote_repair.py")

    def test_no_evidence_or_generated_file_was_modified(self):
        self.assertEqual(self.before, _tree_hash(HERE / "evidence", HERE / "generated"))
        for f, sha in self.report["evidence_files_analyzed"].items():
            self.assertEqual(sha, hashlib.sha256((HERE / f).read_bytes()).hexdigest())

    def test_main_writes_only_the_report(self):
        before = _tree_hash(HERE / "evidence", HERE / "generated", HERE / "proposals", HERE / "rules")
        with tempfile.TemporaryDirectory() as td:
            out = Path(td) / "r.json"
            with contextlib.redirect_stdout(io.StringIO()):
                self.assertEqual(Q.main(["--out", str(out)]), 0)
            self.assertEqual(json.loads(out.read_text(encoding="utf-8")), self.report)
        self.assertEqual(before, _tree_hash(HERE / "evidence", HERE / "generated", HERE / "proposals", HERE / "rules"))

    def test_every_unresolved_record_exactly_once(self):
        expected = set()
        for stem, (name, doc) in _pilot().items():
            _e, _t, assess = L.verify_snapshots(doc, HERE)
            expected |= {r["record_id"] for r in doc["records"] if not assess[r["record_id"]]["eligible"]}
        ids = [p["evidence_id"] for p in self.report["proposals"]]
        self.assertEqual(len(ids), len(set(ids)))
        self.assertEqual(set(ids), expected)
        self.assertEqual(self.report["summary"]["unresolved_records_analyzed"], len(expected))
        by = self.report["summary"]["by_classification"]
        self.assertEqual(sum(by.values()), len(expected))
        for name, c in self.report["summary"]["by_model"].items():
            self.assertEqual(c["analyzed"], c[Q.SAFE] + c[Q.FACT] + c[Q.MANUAL])

    def test_every_proposed_quote_is_verbatim_in_its_snapshot(self):
        safe = [p for p in self.report["proposals"] if p["classification"] == Q.SAFE]
        self.assertTrue(safe)
        for p in safe:
            f = HERE / p["snapshot_path"]
            raw = f.read_bytes()
            self.assertEqual(hashlib.sha256(raw).hexdigest(), p["snapshot_sha256"], p["evidence_id"])
            text = L._ws(raw.decode("utf-8"))
            segs = L.quote_segments(p["proposed_exact_quote"])
            self.assertEqual(segs, p["proposed_segments"], p["evidence_id"])
            self.assertTrue(segs and all(s and s in text for s in segs), p["evidence_id"])

    def test_safe_proposals_pass_the_standard_traceability_check_for_their_own_record(self):
        recs = {r["record_id"]: r for _s, (_n, d) in _pilot().items() for r in d["records"]}
        for p in self.report["proposals"]:
            if p["classification"] != Q.SAFE:
                continue
            probe = copy.deepcopy(recs[p["evidence_id"]])
            probe["evidence"]["supporting_text"] = p["proposed_exact_quote"]
            self.assertEqual(L.trace_check(probe), [], p["evidence_id"])
            self.assertEqual(p["authored_values_unsupported"], [])
            self.assertTrue(p["authored_values_supported"])

    def test_only_safe_proposals_carry_a_quote(self):
        for p in self.report["proposals"]:
            if p["classification"] == Q.SAFE:
                self.assertIn(p["confidence"], ("HIGH", "MEDIUM"))
            else:
                self.assertIsNone(p["proposed_exact_quote"])
                self.assertEqual(p["proposed_segments"], [])

    def test_cm_s1_225_vs_232_hp_is_a_factual_change_never_a_repair(self):
        cm1 = self.by_id["CM-001"]
        self.assertEqual(cm1["classification"], Q.FACT)
        self.assertNotEqual(cm1["classification"], Q.SAFE)
        self.assertIsNone(cm1["proposed_exact_quote"])
        self.assertEqual(cm1["factual_change"]["authored"], "225")
        self.assertIn("232", cm1["factual_change"]["snapshot_numbers"])
        # the rest of the revised page is not repaired automatically either
        for p in self.report["proposals"]:
            if p["source_id"] == "CM-S1":
                self.assertNotEqual(p["classification"], Q.SAFE, p["evidence_id"])

    def test_factual_change_records_are_not_in_the_restored_values(self):
        sim = self.report["verified_values_if_all_safe_repairs_were_approved"]
        for m in sim["by_model"].values():
            self.assertEqual(m["simulation_validation_errors"], [])
            self.assertEqual(m["no_longer_verified"], {})  # nothing that is verified today is lost
            self.assertGreaterEqual(m["verified_values_after"], m["verified_values_before"])
        total = sim["total"]
        self.assertEqual(total["before"], sum(m["verified_values_before"] for m in sim["by_model"].values()))
        self.assertEqual(total["after"], sum(m["verified_values_after"] for m in sim["by_model"].values()))
        self.assertEqual(sim["by_model"]["Ford Everest"]["verified_values_before"] > 0, True)

    def test_no_snapshot_records_stay_manual(self):
        for p in self.report["proposals"]:
            if p["snapshot_kind"] == "none":
                self.assertEqual((p["classification"], p["reason_code"]), (Q.MANUAL, "NO_SNAPSHOT"), p["evidence_id"])

    def test_candidate_snapshots_match_the_revalidation_hash(self):
        for p in self.report["proposals"]:
            if p["snapshot_kind"] == "candidate_not_yet_preserved":
                stem = Path(p["evidence_file"]).stem
                reval = {a["source_id"]: a for a in L.read_json(HERE / "reports" / f"{stem}_revalidation.json")["attempts"]}
                self.assertEqual(p["snapshot_sha256"], reval[p["source_id"]]["content_sha256"])
                self.assertTrue(p["application_requires_snapshot_promotion"])

    def test_simulation_applies_nothing_to_the_real_files(self):
        self.assertFalse(self.report["applied"])
        self.assertTrue(self.report["dry_run"])


if __name__ == "__main__":
    unittest.main()
