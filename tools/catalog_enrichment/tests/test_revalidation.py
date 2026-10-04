"""Re-validation of legacy evidence (fetch_snapshot.py): re-fetch -> preserved snapshot + sha256 -> existing quotes re-checked.
All offline: the network is replaced by an injected fetcher; scratch dirs hold the snapshots."""
import copy
import hashlib
import json
import sys
import tempfile
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(HERE))
import enrichment_lib as L  # noqa: E402
import fetch_snapshot as F  # noqa: E402

NOW = "2026-10-03T12:00:00Z"
SENT1 = "The Acme Roadster 2.5L Petrol is available with 4WD."
SENT2 = "Seats: 7 seats are standard on every Roadster."
FILLER = " The Roadster range is described in detail on this page, including engines, transmissions, equipment and warranty terms for the market."
QUOTE1 = "2.5L Petrol is available with 4WD"
QUOTE2 = "7 seats are standard"


def html(*sentences, filler=True):
    body = "".join(f"<p>{s}</p>" for s in sentences) + (f"<p>{FILLER}</p>" if filler else "")
    return f"<html><head><title>Acme Roadster</title></head><body>{body}</body></html>".encode("utf-8")


def make_pdf(text):
    """Minimal one-page text PDF (hand built, valid xref) so PDF extraction/hashing is exercised for real."""
    stream = f"BT /F1 10 Tf 20 700 Td ({text}) Tj ET".encode("latin-1")
    objs = [b"<< /Type /Catalog /Pages 2 0 R >>", b"<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
            b"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 3000 792] /Contents 4 0 R /Resources << /Font << /F1 5 0 R >> >> >>",
            b"<< /Length %d >>\nstream\n" % len(stream) + stream + b"\nendstream", b"<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>"]
    out, offs = b"%PDF-1.4\n", []
    for i, o in enumerate(objs, 1):
        offs.append(len(out))
        out += b"%d 0 obj\n" % i + o + b"\nendobj\n"
    xref = len(out)
    out += b"xref\n0 %d\n0000000000 65535 f \n" % (len(objs) + 1) + b"".join(b"%010d 00000 n \n" % o for o in offs)
    return out + b"trailer\n<< /Size %d /Root 1 0 R >>\nstartxref\n%d\n%%%%EOF\n" % (len(objs) + 1, xref)


def ok(raw, url, ctype="text/html"):
    return {"ok": True, "status": 200, "final_url": url, "content_type": ctype, "raw": raw, "error": None}


def fail(url, status=403):
    return {"ok": False, "status": status, "final_url": url, "content_type": "text/html", "raw": b"", "error": f"HTTP {status}"}


def rec(rid, sid, text, **kw):
    return {
        "record_id": rid, "brand": "Acme", "model": "Roadster", "year_from": 2020, "year_to": 2020, "market": None, "trim": None, "variant": None,
        "body_type": None, "drivetrain": kw.pop("drivetrain", None), "seats": kw.pop("seats", None),
        "engine": {"displacement_raw": kw.pop("disp", None), "fuel_type": kw.pop("fuel", None), "cylinders": None, "horsepower": None, "torque": None},
        "transmission": {"type": None, "gears": None}, "evidence": {"source_id": sid, "supporting_text": text},
    }


def legacy_source(sid, url, retrieval="fetched_full_text", state="RETRIEVED_UNVERIFIABLE", tier=1):
    return {"url": url, "name": sid, "tier": tier, "host_type": "manufacturer_domain", "retrieval": retrieval, "accessed_at": "2026-10-03",
            "integrity": {"state": state, "retrieved_at": "2026-10-03", "content_sha256": None, "snapshot_path": None,
                          "origin": "migration:legacy_no_snapshot" if state == "RETRIEVED_UNVERIFIABLE" else "migration:snippet_retrieval", "note": "legacy"}}


class Base(unittest.TestCase):
    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.root = Path(self._tmp.name)
        self.snap_dir = self.root / "evidence" / "t" / "_source_text"
        self.addCleanup(self._tmp.cleanup)

    def doc(self, sources, records):
        d = L.prepare_evidence({"schema_version": L.SCHEMA_EVIDENCE, "brand": "Acme", "model": "Roadster", "researched_at": "2026-10-03", "sources": sources, "records": records})
        self.assertEqual(L.validate_evidence(d), [])
        return d

    def legacy(self, url="https://example.test/page", **kw):
        return self.doc({"S1": legacy_source("S1", url, **kw)},
                        [rec("AC-001", "S1", QUOTE1, disp="2.5L", fuel="Petrol", drivetrain="4WD"), rec("AC-002", "S1", QUOTE2, seats=7)])

    def run_revalidation(self, d, pages, **kw):
        fetcher = lambda url: pages[url]  # noqa: E731
        new, entries = F.revalidate_doc(d, self.snap_dir, NOW, fetcher=fetcher, root=self.root, **kw)
        return L.prepare_evidence(new), entries

    def union(self, d):
        return L.build_union(d, L.detect_conflicts(d["records"], "acme-roadster"), root=self.root)


class LegacyRefetchVerifies(Base):
    def test_legacy_source_successfully_refetched_becomes_verified(self):
        d = self.legacy()
        self.assertEqual(L.source_integrity_state(d["sources"]["S1"]), "RETRIEVED_UNVERIFIABLE")
        self.assertEqual(self.union(d)["verified"]["drivetrains"], [])
        new, entries = self.run_revalidation(d, {"https://example.test/page": ok(html(SENT1, SENT2), "https://example.test/page")})
        integ = new["sources"]["S1"]["integrity"]
        self.assertEqual(integ["state"], "FULL_TEXT_VERIFIED")
        self.assertEqual(integ["origin"], "revalidation:refetch")
        self.assertEqual(integ["previous_state"], "RETRIEVED_UNVERIFIABLE")
        self.assertEqual(integ["retrieved_at"], NOW)
        self.assertEqual(integ["http_status"], 200)
        self.assertEqual(entries[0]["outcome"], "CONFIRMED")
        # the preserved file exists, its bytes hash to the recorded sha256, and the strict validators accept it
        snap = self.root / integ["snapshot_path"]
        self.assertTrue(snap.is_file())
        self.assertEqual(hashlib.sha256(snap.read_bytes()).hexdigest(), integ["content_sha256"])
        self.assertEqual(L.validate_evidence(new), [])
        errs, texts, assess = L.verify_snapshots(new, self.root)
        self.assertEqual(errs, [])
        self.assertTrue(all(a["eligible"] for a in assess.values()))
        u = self.union(new)
        self.assertEqual(u["verified"]["drivetrains"], ["4WD"])
        self.assertEqual(u["verified"]["seats"], [7])
        self.assertEqual(u["needs_source_retrieval"]["drivetrains"], [])

    def test_a_snippet_source_that_is_fetched_is_upgraded_only_on_actual_content(self):
        d = self.doc({"S1": legacy_source("S1", "https://example.test/page", retrieval="search_snippet_only", state="SNIPPET_ONLY")},
                     [rec("AC-001", "S1", QUOTE1, drivetrain="4WD")])
        new, _ = self.run_revalidation(d, {"https://example.test/page": ok(html(SENT1), "https://example.test/page")})
        s = new["sources"]["S1"]
        self.assertEqual(s["integrity"]["state"], "FULL_TEXT_VERIFIED")
        self.assertEqual(s["retrieval"], "fetched_full_text")  # kept consistent with the new state
        self.assertIn("search-result snippet", s["notes"])
        self.assertEqual(L.validate_evidence(new), [])

    def test_already_verified_revalidated_sources_are_not_refetched_without_force(self):
        d = self.legacy()
        new, _ = self.run_revalidation(d, {"https://example.test/page": ok(html(SENT1, SENT2), "https://example.test/page")})

        def boom(url):
            raise AssertionError("must not fetch")
        again, entries = F.revalidate_doc(new, self.snap_dir, "2027-01-01T00:00:00Z", fetcher=boom, root=self.root)
        self.assertEqual(entries[0]["outcome"], "SKIPPED_ALREADY_VERIFIED")
        self.assertEqual(again, new)


class InaccessibleStaysNonVerified(Base):
    def test_inaccessible_legacy_source_is_unavailable_and_not_verified(self):
        d = self.legacy()
        new, entries = self.run_revalidation(d, {"https://example.test/page": fail("https://example.test/page", 403)})
        integ = new["sources"]["S1"]["integrity"]
        self.assertEqual(integ["state"], "UNAVAILABLE")
        self.assertEqual(integ["origin"], "revalidation:refetch_unavailable")
        self.assertIsNone(integ["content_sha256"])
        self.assertIsNone(integ["snapshot_path"])
        self.assertEqual(entries[0]["error"], "HTTP 403")
        self.assertFalse(self.snap_dir.exists())  # nothing preserved
        self.assertEqual(L.validate_evidence(new), [])
        u = self.union(new)
        self.assertEqual(u["verified"]["drivetrains"], [])
        self.assertEqual(u["needs_source_retrieval"]["drivetrains"], ["4WD"])  # kept, not deleted, not promoted

    def test_snippet_only_source_stays_snippet_only_when_refetch_fails(self):
        d = self.doc({"S1": legacy_source("S1", "https://example.test/page", retrieval="search_snippet_only", state="SNIPPET_ONLY")},
                     [rec("AC-001", "S1", QUOTE1, drivetrain="4WD")])
        new, _ = self.run_revalidation(d, {"https://example.test/page": fail("https://example.test/page", 429)})
        self.assertEqual(new["sources"]["S1"]["integrity"]["state"], "SNIPPET_ONLY")
        self.assertEqual(new["sources"]["S1"]["retrieval"], "search_snippet_only")
        self.assertEqual(self.union(new)["verified"]["drivetrains"], [])

    def test_javascript_shell_with_no_text_is_unavailable(self):
        d = self.legacy()
        shell = b"<html><head><title>x</title><script>var a=1;</script></head><body><div id='app'></div></body></html>"
        new, _ = self.run_revalidation(d, {"https://example.test/page": ok(shell, "https://example.test/page")})
        self.assertEqual(new["sources"]["S1"]["integrity"]["state"], "UNAVAILABLE")
        self.assertIn("no usable text", new["sources"]["S1"]["integrity"]["note"])


class ChangedSourceIsNotProof(Base):
    def test_changed_page_without_the_original_quote_is_not_verified(self):
        d = self.legacy()
        changed = html("The Acme Roadster now ships with a 2.0L turbo engine and front-wheel drive.", "Five seats.")
        new, entries = self.run_revalidation(d, {"https://example.test/page": ok(changed, "https://example.test/page")})
        integ = new["sources"]["S1"]["integrity"]
        self.assertEqual(integ["state"], "RETRIEVED_UNVERIFIABLE")  # fetched, but the content does not support the citation
        self.assertEqual(integ["origin"], "revalidation:refetch_content_mismatch")
        self.assertIsNone(integ["content_sha256"])
        self.assertEqual(entries[0]["outcome"], "CONTENT_MISMATCH")
        self.assertEqual(entries[0]["records_confirmed"], 0)
        self.assertEqual([u["record_id"] for u in entries[0]["records_unconfirmed"]], ["AC-001", "AC-002"])
        self.assertTrue(all(u["missing_segments"] for u in entries[0]["records_unconfirmed"]))
        u = self.union(new)
        self.assertEqual(u["verified"]["drivetrains"], [])
        self.assertEqual(u["needs_source_retrieval"]["drivetrains"], ["4WD"])
        # the authored quote is NOT silently rewritten to match the new page
        self.assertEqual([r["evidence"]["supporting_text"] for r in new["records"]], [QUOTE1, QUOTE2])

    def test_partially_changed_page_verifies_only_the_records_whose_quote_is_still_there(self):
        d = self.legacy()
        partly = html(SENT1, "Five seats are standard on every Roadster.")
        new, entries = self.run_revalidation(d, {"https://example.test/page": ok(partly, "https://example.test/page")})
        integ = new["sources"]["S1"]["integrity"]
        self.assertEqual(integ["state"], "FULL_TEXT_VERIFIED")
        self.assertEqual(integ["unconfirmed_record_ids"], ["AC-002"])
        self.assertEqual(entries[0]["outcome"], "PARTIAL_CONFIRMED")
        errs, _, assess = L.verify_snapshots(new, self.root)
        self.assertEqual(errs, [])
        self.assertTrue(assess["AC-001"]["eligible"])
        self.assertFalse(assess["AC-002"]["eligible"])
        u = self.union(new)
        self.assertEqual(u["verified"]["drivetrains"], ["4WD"])
        self.assertEqual(u["verified"]["seats"], [])
        self.assertEqual(u["needs_source_retrieval"]["seats"], [7])

    def test_the_unconfirmed_listing_cannot_be_used_to_hide_a_failing_quote(self):
        d = self.legacy()
        partly = html(SENT1, "Five seats are standard on every Roadster.")
        new, _ = self.run_revalidation(d, {"https://example.test/page": ok(partly, "https://example.test/page")})
        # (a) dropping the listing makes the missing quote a hard validation error again
        hidden = copy.deepcopy(new)
        del hidden["sources"]["S1"]["integrity"]["unconfirmed_record_ids"]
        self.assertTrue(any("quote segment not found" in e for e in L.verify_snapshots(hidden, self.root)[0]))
        # (b) listing a record whose quote IS in the snapshot is rejected as a stale listing
        wrong = copy.deepcopy(new)
        wrong["sources"]["S1"]["integrity"]["unconfirmed_record_ids"] = ["AC-001", "AC-002"]
        self.assertTrue(any("AC-001" in e for e in L.verify_snapshots(wrong, self.root)[0]))

    def test_typographic_difference_is_diagnosed_but_never_verified(self):
        d = self.doc({"S1": legacy_source("S1", "https://example.test/page")}, [rec("AC-001", "S1", "Camry's all-hybrid powertrain with 4WD", drivetrain="4WD")])
        page = html("Camry\u2019s all-hybrid powertrain with 4WD is standard.")
        new, entries = self.run_revalidation(d, {"https://example.test/page": ok(page, "https://example.test/page")})
        self.assertEqual(entries[0]["records_unconfirmed"][0]["diagnosis"], "typographic_or_case_only")
        self.assertEqual(new["sources"]["S1"]["integrity"]["state"], "RETRIEVED_UNVERIFIABLE")
        self.assertEqual(self.union(new)["verified"]["drivetrains"], [])


class PdfRefetch(Base):
    URL = "https://example.test/spec.pdf"
    PDF_TEXT = SENT1.replace("(", "").replace(")", "") + " " + SENT2 + FILLER

    def test_pdf_refetch_is_pdf_verified_and_hash_checked(self):
        raw = make_pdf(self.PDF_TEXT)
        d = self.doc({"S1": legacy_source("S1", self.URL, retrieval="pdf_downloaded_and_parsed")}, [rec("AC-001", "S1", QUOTE1, drivetrain="4WD"), rec("AC-002", "S1", QUOTE2, seats=7)])
        new, entries = self.run_revalidation(d, {self.URL: ok(raw, self.URL, "application/pdf")})
        integ = new["sources"]["S1"]["integrity"]
        self.assertEqual(integ["state"], "PDF_VERIFIED")
        self.assertTrue(integ["extractor"].startswith("pypdf/"))
        self.assertEqual(integ["raw_sha256"], hashlib.sha256(raw).hexdigest())  # hash of the downloaded document
        snap = self.root / integ["snapshot_path"]
        self.assertEqual(hashlib.sha256(snap.read_bytes()).hexdigest(), integ["content_sha256"])  # hash of the preserved text
        self.assertEqual(L.verify_snapshots(new, self.root)[0], [])
        self.assertEqual(self.union(new)["verified"]["drivetrains"], ["4WD"])
        # tampering with the preserved text is detected
        snap.write_bytes(snap.read_bytes() + b"tampered\n")
        self.assertTrue(any("sha256" in e for e in L.verify_snapshots(new, self.root)[0]))

    def test_a_pdf_state_requires_a_pdf_source(self):
        d = self.legacy()  # URL is not a .pdf and retrieval is fetched_full_text
        new, _ = self.run_revalidation(d, {"https://example.test/page": ok(html(SENT1, SENT2), "https://example.test/page")})
        bad = copy.deepcopy(new)
        bad["sources"]["S1"]["integrity"]["state"] = "PDF_VERIFIED"
        self.assertTrue(any("PDF_VERIFIED requires a PDF source" in e for e in L.validate_evidence(bad)))


class MigrationPreservesIdentity(Base):
    def test_ids_quotes_urls_and_model_identity_are_preserved(self):
        d = self.legacy()
        new, _ = self.run_revalidation(d, {"https://example.test/page": ok(html(SENT1), "https://example.test/page")})
        self.assertEqual([r["record_id"] for r in new["records"]], [r["record_id"] for r in d["records"]])
        for a, b in zip(d["records"], new["records"]):
            self.assertEqual(L.authored_fingerprint(a), L.authored_fingerprint(b), a["record_id"])  # raw authored fields untouched
        self.assertEqual((new["brand"], new["model"]), (d["brand"], d["model"]))
        for sid in d["sources"]:
            for k in ("url", "name", "tier", "host_type", "accessed_at"):
                self.assertEqual(new["sources"][sid][k], d["sources"][sid][k])
        manifest = L.evidence_manifest(d)
        self.assertEqual(L.check_manifest(new, manifest), ([], []))  # the manifest guard still passes

    def test_the_real_pilot_manifest_still_holds_after_revalidation(self):
        manifest = L.read_json(HERE / "reports" / "evidence_manifest.json")
        for n in ("ford_everest", "toyota_land_cruiser", "toyota_camry"):
            d = L.read_json(HERE / "evidence" / f"{n}.json")
            self.assertEqual(L.check_manifest(d, manifest[n]), ([], []), n)
            ids = [r["record_id"] for r in d["records"]]
            self.assertEqual(ids, sorted(set(ids)))  # unchanged ids, none lost or duplicated
            self.assertEqual(len(ids), manifest[n]["record_count"])

    def test_every_real_pilot_source_was_attempted_and_reported(self):
        for n in ("ford_everest", "toyota_land_cruiser", "toyota_camry"):
            d = L.read_json(HERE / "evidence" / f"{n}.json")
            rep = L.read_json(HERE / "reports" / f"{n}_revalidation.json")
            self.assertEqual(sorted(a["source_id"] for a in rep["attempts"]), sorted(d["sources"]), n)
            for a in rep["attempts"]:
                self.assertEqual(a["new_state"], L.source_integrity_state(d["sources"][a["source_id"]]), (n, a["source_id"]))
                self.assertEqual(a["url"], d["sources"][a["source_id"]]["url"])


class Determinism(Base):
    def test_same_inputs_give_byte_identical_output(self):
        pages = {"https://example.test/page": ok(html(SENT1, "Five seats."), "https://example.test/page")}
        outs = []
        for i in range(2):
            self.setUp()
            new, _ = self.run_revalidation(self.legacy(), pages)
            snap = (self.root / new["sources"]["S1"]["integrity"]["snapshot_path"]).read_bytes()
            u = self.union(new)
            outs.append((json.dumps(new, sort_keys=True), snap, json.dumps(u, sort_keys=True)))
        self.assertEqual(outs[0], outs[1])

    def test_pilot_unions_regenerate_identically_from_the_committed_evidence(self):
        for n in ("ford_everest", "toyota_land_cruiser", "toyota_camry"):
            d = L.read_json(HERE / "evidence" / f"{n}.json")
            conflicts = L.detect_conflicts(d["records"], n.replace("_", "-"))
            a = L.build_union(d, conflicts)
            b = L.build_union(copy.deepcopy(L.prepare_evidence(copy.deepcopy(d))), conflicts)
            self.assertEqual(a, b, n)
            self.assertEqual(a, L.read_json(HERE / "generated" / f"{n}.union.json"), n)

    def test_html_extraction_is_deterministic(self):
        raw = html(SENT1, SENT2)
        self.assertEqual(F.html_to_text(raw), F.html_to_text(raw))
        self.assertEqual(F.snapshot_bytes("a\n\n"), b"a\n")


class StaleProposals(unittest.TestCase):
    def proposal(self, **status):
        return {"schema_version": "carnet.catalog_patch/1", "applied": False, "sources": {"S1": {"integrity": {"state": "FULL_TEXT_VERIFIED"}}}, "patches": [],
                "proposal_status": {"state": "current", "actionable": True, "evidence_integrity_version": L.PROPOSAL_INTEGRITY_VERSION, **status}}

    def test_a_correct_current_proposal_is_actionable(self):
        p = self.proposal()
        self.assertEqual(L.proposal_problems(p), [])
        self.assertEqual(L.validate_proposal(p), [])
        L.assert_proposal_actionable(p)

    def test_a_proposal_without_status_is_not_actionable(self):
        p = self.proposal()
        del p["proposal_status"]
        self.assertTrue(L.proposal_problems(p))
        self.assertTrue(L.validate_proposal(p))
        with self.assertRaises(L.ProposalNotActionable):
            L.assert_proposal_actionable(p)

    def test_stale_proposal_is_refused_even_if_it_claims_to_be_actionable(self):
        p = self.proposal(state="stale", stale_reason="pre-integrity evidence")
        self.assertTrue(any("actionable" in e for e in L.validate_proposal(p)))  # inconsistent declaration is a validation error
        with self.assertRaises(L.ProposalNotActionable):
            L.assert_proposal_actionable(p)
        p["proposal_status"]["actionable"] = False
        self.assertEqual(L.validate_proposal(p), [])  # a correctly declared stale proposal is valid ...
        with self.assertRaises(L.ProposalNotActionable):  # ... and still cannot be applied
            L.assert_proposal_actionable(p)

    def test_a_stale_proposal_must_explain_why(self):
        p = self.proposal(state="stale", actionable=False)
        self.assertTrue(any("stale_reason" in e for e in L.validate_proposal(p)))

    def test_an_old_integrity_version_or_unverified_source_is_not_actionable(self):
        self.assertTrue(L.proposal_problems(self.proposal(evidence_integrity_version=None)))
        p = self.proposal()
        p["sources"]["S1"]["integrity"]["state"] = "SNIPPET_ONLY"
        self.assertTrue(any("S1" in x for x in L.proposal_problems(p)))
        p = self.proposal()
        p["applied"] = True
        self.assertTrue(L.proposal_problems(p))

    def test_the_real_ford_everest_proposal_is_marked_stale_and_blocked(self):
        for f in sorted(L.PROPOSALS.glob("*.json")):
            doc = L.read_json(f)
            ps = doc["proposal_status"]
            self.assertEqual(ps["state"], "stale", f.name)
            self.assertIs(ps["actionable"], False, f.name)
            self.assertIs(ps["never_apply_to_production"], True, f.name)
            self.assertFalse(doc["applied"], f.name)
            self.assertEqual(L.validate_proposal(doc), [], f.name)
            with self.assertRaises(L.ProposalNotActionable):
                L.assert_proposal_actionable(doc)


if __name__ == "__main__":
    unittest.main()
