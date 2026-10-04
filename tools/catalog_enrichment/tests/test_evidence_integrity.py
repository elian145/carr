"""Evidence integrity: source AUTHORITY (tier) is separate from EVIDENCE INTEGRITY (was the content retrieved, preserved,
hashed and the quote found in it?). Only tier 1-3 + FULL_TEXT_VERIFIED/PDF_VERIFIED + validated quote can be VERIFIED."""
import copy
import hashlib
import json
import sys
import tempfile
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(HERE))
import brand_enrichment as B  # noqa: E402
import enrichment_lib as L  # noqa: E402
import model_boundaries as mb  # noqa: E402

PAGE = "The Acme Roadster 2.5L Petrol is available with 4WD. Seats: 7 seats."


def rec(rid, sid, text, **kw):
    r = {
        "record_id": rid, "brand": "Acme", "model": "Roadster", "year_from": 2020, "year_to": 2020, "market": None, "trim": None, "variant": None,
        "body_type": None, "drivetrain": kw.pop("drivetrain", None), "seats": kw.pop("seats", None),
        "engine": {"displacement_raw": kw.pop("disp", None), "fuel_type": kw.pop("fuel", None), "cylinders": None, "horsepower": None, "torque": None},
        "transmission": {"type": None, "gears": None}, "evidence": {"source_id": sid, "supporting_text": text},
    }
    assert not kw
    return r


class Fixture(unittest.TestCase):
    """A scratch 'tools root' (evidence/ snapshots live under it) so snapshot reads/tampering are real file operations."""

    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.root = Path(self._tmp.name)
        (self.root / "evidence" / "t" / "_source_text").mkdir(parents=True)

    def tearDown(self):
        self._tmp.cleanup()

    def snapshot(self, sid, text=PAGE):
        f = self.root / "evidence" / "t" / "_source_text" / f"{sid}.txt"
        f.write_bytes(text.encode("utf-8"))
        return {"content_sha256": hashlib.sha256(text.encode("utf-8")).hexdigest(), "snapshot_path": f"evidence/t/_source_text/{sid}.txt"}

    def source(self, sid, tier, state, retrieval=None, url=None, text=PAGE, host="manufacturer_domain"):
        verifiable = state in L.VERIFIED_ELIGIBLE_STATES
        if retrieval is None:
            retrieval = "pdf_downloaded_and_parsed" if state == "PDF_VERIFIED" else ("search_snippet_only" if state == "SNIPPET_ONLY" else "fetched_full_text")
        integ = {"state": state, "retrieved_at": "2026-10-03", "content_sha256": None, "snapshot_path": None, "origin": "authored", "note": None}
        if verifiable:
            integ.update(self.snapshot(sid, text))
        return {"url": url or f"https://example.test/{sid}", "name": sid, "tier": tier, "host_type": host, "retrieval": retrieval, "accessed_at": "2026-10-03", "integrity": integ}

    def doc(self, sources, records):
        return L.prepare_evidence({"schema_version": L.SCHEMA_EVIDENCE, "brand": "Acme", "model": "Roadster", "researched_at": "2026-10-03", "sources": sources, "records": records})

    def union(self, d):
        assert L.validate_evidence(d) == [], L.validate_evidence(d)
        return L.build_union(d, L.detect_conflicts(d["records"], "acme-roadster"), root=self.root)

    def one(self, tier, state, **kw):
        d = self.doc({"S1": self.source("S1", tier, state, **kw)}, [rec("AC-001", "S1", "2.5L Petrol is available with 4WD", disp="2.5L", fuel="Petrol", drivetrain="4WD")])
        return d, self.union(d)


class EligibilityRule(Fixture):
    def test_tier1_full_text_validated_is_verified(self):
        _, u = self.one(1, "FULL_TEXT_VERIFIED")
        self.assertEqual(u["verified"]["fuel_types"], ["Petrol"])
        self.assertEqual(u["verified"]["drivetrains"], ["4WD"])
        self.assertEqual(u["generated_from"]["records_passing_integrity_test"], 1)

    def test_tier1_snippet_only_is_not_verified(self):
        _, u = self.one(1, "SNIPPET_ONLY")
        self.assertEqual(u["verified"]["fuel_types"], [])
        self.assertEqual(u["needs_source_retrieval"]["fuel_types"], ["Petrol"])
        self.assertEqual(u["provisional_only"]["fuel_types"], [])
        self.assertEqual(u["details"]["fuel_types"][0]["status"], "NEEDS_SOURCE_RETRIEVAL")

    def test_tier2_pdf_with_validated_quote_is_verified(self):
        _, u = self.one(2, "PDF_VERIFIED")
        self.assertEqual(u["verified"]["engine_sizes"], ["2.5L"])
        self.assertEqual(u["details"]["engine_sizes"][0]["integrity_states"], ["PDF_VERIFIED"])

    def test_tier3_with_unavailable_page_is_not_verified(self):
        _, u = self.one(3, "UNAVAILABLE", host="official_distributor_domain")
        self.assertTrue(all(not v for v in u["verified"].values()))
        self.assertEqual(u["needs_source_retrieval"]["drivetrains"], ["4WD"])

    def test_tier3_retrieved_but_never_preserved_is_not_verified(self):
        _, u = self.one(3, "RETRIEVED_UNVERIFIABLE", host="official_distributor_domain")
        self.assertTrue(all(not v for v in u["verified"].values()))
        self.assertEqual(u["needs_source_retrieval"]["fuel_types"], ["Petrol"])

    def test_tier4_and_tier5_stay_provisional_even_with_a_validated_snapshot(self):
        for tier, state in ((4, "FULL_TEXT_VERIFIED"), (5, "PDF_VERIFIED"), (5, "SNIPPET_ONLY")):
            _, u = self.one(tier, state, host="independent")
            self.assertTrue(all(not v for v in u["verified"].values()), (tier, state))
            self.assertTrue(all(not v for v in u["needs_source_retrieval"].values()), (tier, state))
            self.assertEqual(u["provisional_only"]["fuel_types"], ["Petrol"], (tier, state))

    def test_snippet_and_full_text_support_for_the_same_value_is_verified_by_the_full_text_source(self):
        d = self.doc(
            {"S1": self.source("S1", 1, "SNIPPET_ONLY"), "S2": self.source("S2", 2, "PDF_VERIFIED")},
            [rec("AC-001", "S1", "2.5L Petrol is available with 4WD", disp="2.5L", fuel="Petrol"), rec("AC-002", "S2", "Petrol is available with 4WD", fuel="Petrol")],
        )
        u = self.union(d)
        self.assertEqual(u["verified"]["fuel_types"], ["Petrol"])
        self.assertEqual(u["needs_source_retrieval"]["fuel_types"], [])
        row = u["details"]["fuel_types"][0]
        self.assertEqual(row["status"], "VERIFIED")
        self.assertEqual(row["integrity_states"], ["PDF_VERIFIED", "SNIPPET_ONLY"])
        self.assertEqual(row["record_ids"], ["AC-001", "AC-002"])  # the snippet record is kept
        self.assertEqual(row["validated_record_ids"], ["AC-002"])
        # the snippet-only engine size stays unverified
        self.assertEqual(u["needs_source_retrieval"]["engine_sizes"], ["2.5L"])

    def test_sections_are_disjoint_and_union_is_an_alias_of_verified(self):
        d = self.doc(
            {"S1": self.source("S1", 1, "FULL_TEXT_VERIFIED"), "S2": self.source("S2", 1, "SNIPPET_ONLY"), "S3": self.source("S3", 5, "SNIPPET_ONLY", host="independent")},
            [rec("AC-001", "S1", "2.5L Petrol", disp="2.5L", fuel="Petrol"), rec("AC-002", "S2", "4WD", drivetrain="4WD"), rec("AC-003", "S3", "7 seats", seats="7 seats")],
        )
        u = self.union(d)
        self.assertEqual(u["verified"], u["union"])
        self.assertEqual(u["verified"]["engine_sizes"], ["2.5L"])
        self.assertEqual(u["needs_source_retrieval"]["drivetrains"], ["4WD"])
        self.assertEqual(u["provisional_only"]["seats"], [7])
        for dim in u["verified"]:
            sets = [set(map(str, u[s][dim])) for s in ("verified", "needs_source_retrieval", "provisional_only")]
            self.assertEqual(sum(len(x) for x in sets), len(set().union(*sets)), dim)

    def test_integrity_is_not_inferred_from_tier_or_from_the_declared_retrieval_method(self):
        # a tier 1 source whose retrieval says 'fetched_full_text' but whose integrity is RETRIEVED_UNVERIFIABLE
        d, u = self.one(1, "RETRIEVED_UNVERIFIABLE", retrieval="fetched_full_text")
        self.assertTrue(all(not v for v in u["verified"].values()))
        # and the claimed state alone is not enough: with no readable snapshot nothing is eligible
        d2, _ = self.one(1, "FULL_TEXT_VERIFIED")
        u2 = L.build_union(d2, [], root=self.root / "elsewhere")
        self.assertTrue(all(not v for v in u2["verified"].values()))

    def test_a_conflict_between_tier123_records_still_demotes_a_validated_value(self):
        d = self.doc(
            {"S1": self.source("S1", 1, "FULL_TEXT_VERIFIED", text="2.5L AWD 2.5L 4WD")},
            [rec("AC-001", "S1", "2.5L AWD", disp="2.5L", drivetrain="AWD"), rec("AC-002", "S1", "2.5L 4WD", disp="2.5L", drivetrain="4WD")],
        )
        u = self.union(d)
        self.assertEqual(u["verified"]["drivetrains"], [])
        self.assertEqual(u["provisional_only"]["drivetrains"], ["4WD", "AWD"])


class SnapshotIntegrity(Fixture):
    def verified_doc(self):
        return self.doc({"S1": self.source("S1", 1, "FULL_TEXT_VERIFIED")}, [rec("AC-001", "S1", "2.5L Petrol is available with 4WD", disp="2.5L", fuel="Petrol")])

    def test_untouched_snapshot_validates(self):
        d = self.verified_doc()
        errs, texts, assess = L.verify_snapshots(d, self.root)
        self.assertEqual(errs, [])
        self.assertTrue(assess["AC-001"]["eligible"])
        self.assertTrue(assess["AC-001"]["quote_validated"])

    def test_tampered_cached_source_fails_validation_and_blocks_verification(self):
        d = self.verified_doc()
        (self.root / d["sources"]["S1"]["integrity"]["snapshot_path"]).write_text(PAGE.replace("Petrol", "Diesel"), encoding="utf-8")
        errs, _, assess = L.verify_snapshots(d, self.root)
        self.assertTrue(any("hash does not match" in e for e in errs), errs)
        self.assertFalse(assess["AC-001"]["eligible"])
        u = L.build_union(d, [], root=self.root)
        self.assertEqual(u["verified"]["fuel_types"], [])
        self.assertEqual(u["needs_source_retrieval"]["fuel_types"], ["Petrol"])  # evidence kept, no longer verified

    def test_tampered_recorded_hash_fails_validation(self):
        d = self.verified_doc()
        d["sources"]["S1"]["integrity"]["content_sha256"] = "0" * 64
        self.assertTrue(any("hash does not match" in e for e in L.verify_snapshots(d, self.root)[0]))

    def test_missing_snapshot_file_fails_validation(self):
        d = self.verified_doc()
        (self.root / d["sources"]["S1"]["integrity"]["snapshot_path"]).unlink()
        self.assertTrue(any("missing" in e for e in L.verify_snapshots(d, self.root)[0]))

    def test_snapshot_path_cannot_escape_evidence_dir(self):
        d = self.verified_doc()
        d["sources"]["S1"]["integrity"]["snapshot_path"] = "../outside.txt"
        self.assertTrue(any("outside evidence/" in e for e in L.verify_snapshots(d, self.root)[0]))

    def test_missing_quote_fails_validation_and_blocks_verification(self):
        d = self.verified_doc()
        d["records"][0]["evidence"]["supporting_text"] = "2.5L Petrol with a 9000 hp motor"
        errs, _, assess = L.verify_snapshots(d, self.root)
        self.assertTrue(any("quote segment not found" in e for e in errs), errs)
        self.assertEqual(assess["AC-001"]["reason"], "quote_not_in_snapshot")
        self.assertEqual(L.build_union(d, [], root=self.root)["verified"]["fuel_types"], [])

    def test_every_segment_of_a_multi_passage_quote_must_be_present(self):
        d = self.verified_doc()
        d["records"][0]["evidence"]["supporting_text"] = "2.5L Petrol \u2026 Seats: 7 seats"
        self.assertEqual(L.verify_snapshots(d, self.root)[0], [])
        d["records"][0]["evidence"]["supporting_text"] = "2.5L Petrol \u2026 Seats: 9 seats"
        self.assertTrue(L.verify_snapshots(d, self.root)[0])

    def test_validation_uses_only_the_preserved_content_whitespace_normalised(self):
        d = self.doc({"S1": self.source("S1", 1, "FULL_TEXT_VERIFIED", text="2.5L\n   Petrol\tis available")}, [rec("AC-001", "S1", "2.5L Petrol is available", disp="2.5L", fuel="Petrol")])
        self.assertEqual(L.verify_snapshots(d, self.root)[0], [])

    def test_regeneration_is_deterministic(self):
        d = self.verified_doc()
        a = L.build_union(d, [], root=self.root)
        b = L.build_union(copy.deepcopy(d), [], root=self.root)
        self.assertEqual(json.dumps(a, sort_keys=True), json.dumps(b, sort_keys=True))


class StructureRules(Fixture):
    def test_integrity_block_is_required(self):
        d = self.doc({"S1": self.source("S1", 1, "SNIPPET_ONLY")}, [rec("AC-001", "S1", "Petrol", fuel="Petrol")])
        del d["sources"]["S1"]["integrity"]
        self.assertTrue(any("integrity block is required" in e for e in L.validate_evidence(d)))

    def test_unknown_state_is_rejected(self):
        d = self.doc({"S1": self.source("S1", 1, "SNIPPET_ONLY")}, [rec("AC-001", "S1", "Petrol", fuel="Petrol")])
        d["sources"]["S1"]["integrity"]["state"] = "TRUSTED"
        self.assertTrue(any("integrity.state" in e for e in L.validate_evidence(d)))

    def test_verified_states_require_hash_and_snapshot(self):
        d = self.doc({"S1": self.source("S1", 1, "FULL_TEXT_VERIFIED")}, [rec("AC-001", "S1", "Petrol", fuel="Petrol")])
        d["sources"]["S1"]["integrity"]["content_sha256"] = None
        d["sources"]["S1"]["integrity"]["snapshot_path"] = None
        errs = L.validate_evidence(d)
        self.assertTrue(any("content_sha256" in e for e in errs) and any("snapshot_path" in e for e in errs), errs)

    def test_a_snippet_retrieval_cannot_claim_full_text(self):
        d = self.doc({"S1": self.source("S1", 1, "FULL_TEXT_VERIFIED", retrieval="search_snippet_only")}, [rec("AC-001", "S1", "Petrol", fuel="Petrol")])
        self.assertTrue(any("impossible for retrieval=search_snippet_only" in e for e in L.validate_evidence(d)))

    def test_pdf_verified_needs_a_pdf_source(self):
        d = self.doc({"S1": self.source("S1", 2, "PDF_VERIFIED", retrieval="fetched_full_text", url="https://example.test/page.html")}, [rec("AC-001", "S1", "Petrol", fuel="Petrol")])
        self.assertTrue(any("PDF_VERIFIED requires a PDF source" in e for e in L.validate_evidence(d)))
        d["sources"]["S1"]["url"] = "https://example.test/brochure.pdf"
        self.assertEqual([e for e in L.validate_evidence(d) if "PDF" in e], [])

    def test_unverified_states_cannot_carry_a_hash(self):
        d = self.doc({"S1": self.source("S1", 1, "SNIPPET_ONLY")}, [rec("AC-001", "S1", "Petrol", fuel="Petrol")])
        d["sources"]["S1"]["integrity"]["content_sha256"] = "a" * 64
        self.assertTrue(any("must not carry content_sha256" in e for e in L.validate_evidence(d)))

    def test_records_carry_their_source_integrity_state(self):
        d = self.doc({"S1": self.source("S1", 1, "SNIPPET_ONLY")}, [rec("AC-001", "S1", "Petrol", fuel="Petrol")])
        self.assertEqual(d["records"][0]["evidence"]["source_integrity"], "SNIPPET_ONLY")


class Migration(Fixture):
    def legacy(self, retrieval, sha=None, url="https://example.test/p"):
        s = {"url": url, "name": "x", "tier": 1, "host_type": "manufacturer_domain", "retrieval": retrieval, "accessed_at": "2026-10-03"}
        if sha:
            s["sha256"] = sha
        return {"brand": "Acme", "model": "Roadster", "sources": {"S1": s}}

    def migrate(self, doc):
        return L.migrate_integrity(doc, self.root / "evidence" / "t" / "_source_text", root=self.root)[0]["sources"]["S1"]["integrity"]

    def test_snippet_retrieval_becomes_snippet_only(self):
        i = self.migrate(self.legacy("search_snippet_only"))
        self.assertEqual((i["state"], i["content_sha256"], i["snapshot_path"], i["origin"]), ("SNIPPET_ONLY", None, None, "migration:snippet_retrieval"))

    def test_full_text_claim_without_snapshot_is_never_upgraded(self):
        for retrieval in ("fetched_full_text", "pdf_downloaded_and_parsed", "search_tool_full_text"):
            i = self.migrate(self.legacy(retrieval))
            self.assertEqual(i["state"], "RETRIEVED_UNVERIFIABLE", retrieval)
            self.assertIsNone(i["content_sha256"])
            self.assertEqual(i["origin"], "migration:legacy_no_snapshot")

    def test_matching_cached_snapshot_is_migrated_to_a_verified_state(self):
        self.snapshot("S1")
        sha = hashlib.sha256(PAGE.encode("utf-8")).hexdigest()
        i = self.migrate(self.legacy("search_tool_full_text", sha))
        self.assertEqual((i["state"], i["content_sha256"], i["snapshot_path"]), ("FULL_TEXT_VERIFIED", sha, "evidence/t/_source_text/S1.txt"))
        j = self.migrate(self.legacy("search_tool_full_text", sha, url="https://example.test/b.pdf"))
        self.assertEqual(j["state"], "PDF_VERIFIED")

    def test_mismatching_cache_is_not_trusted(self):
        self.snapshot("S1")
        i = self.migrate(self.legacy("search_tool_full_text", "f" * 64))
        self.assertEqual(i["state"], "RETRIEVED_UNVERIFIABLE")

    def test_migration_is_idempotent_and_never_overwrites(self):
        doc = self.legacy("fetched_full_text")
        once, log1 = L.migrate_integrity(doc, self.root, root=self.root)
        twice, log2 = L.migrate_integrity(once, self.root, root=self.root)
        self.assertEqual(once, twice)
        self.assertEqual((len(log1), len(log2)), (1, 0))
        once["sources"]["S1"]["integrity"]["state"] = "UNAVAILABLE"
        self.assertEqual(L.migrate_integrity(once, self.root, root=self.root)[0]["sources"]["S1"]["integrity"]["state"], "UNAVAILABLE")


class ToyotaBatch1(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.mi = mb.load_index()[0]
        cls.models = ["bZ3", "bZ3X", "bZ4X", "Urban Cruiser", "Frontlander", "Grand Highlander", "Prius Prime", "Veloz", "Wigo", "Yaris Cross"]
        cls.docs = {m: L.read_json(B.evidence_path("Toyota", m)) for m in cls.models}
        cls.unions = {m: L.read_json(B.union_path("Toyota", m)) for m in cls.models}

    def test_every_source_has_an_integrity_state_and_nothing_is_inferred_from_tier(self):
        for m, d in self.docs.items():
            self.assertEqual(L.validate_evidence(d, self.mi), [], m)
            for sid, s in d["sources"].items():
                st = s["integrity"]["state"]
                self.assertIn(st, L.INTEGRITY_STATES)
                if s["retrieval"] == "search_snippet_only":
                    self.assertEqual(st, "SNIPPET_ONLY", (m, sid))
                if st in L.VERIFIED_ELIGIBLE_STATES:
                    self.assertTrue(s["integrity"]["content_sha256"] and s["integrity"]["snapshot_path"], (m, sid))

    def test_preserved_snapshots_validate_every_quote_that_claims_them(self):
        for m, d in self.docs.items():
            errs, _, assess = L.verify_snapshots(d)
            self.assertEqual(errs, [], m)
            for rid, a in assess.items():
                if a["state"] in L.VERIFIED_ELIGIBLE_STATES:
                    self.assertTrue(a["quote_validated"], (m, rid))

    def test_snippet_only_models_have_nothing_verified(self):
        for m in ("bZ3", "bZ3X", "Frontlander", "Veloz", "Wigo"):
            self.assertTrue(all(not v for v in self.unions[m]["verified"].values()), m)
            self.assertEqual(self.unions[m]["generated_from"]["records_passing_integrity_test"], 0, m)

    def test_tier123_snippet_values_are_needs_source_retrieval_and_tier45_are_provisional(self):
        self.assertEqual(self.unions["Veloz"]["needs_source_retrieval"]["trims"], ["E", "G", "V"])
        self.assertEqual(self.unions["Wigo"]["needs_source_retrieval"]["engine_sizes"], ["1.0L"])
        self.assertEqual(self.unions["bZ3X"]["needs_source_retrieval"]["fuel_types"], ["Electric"])  # tier 1 snippet
        self.assertEqual(self.unions["bZ3X"]["provisional_only"]["trims"][0], "430 Air")  # tier 5
        self.assertEqual(self.unions["Frontlander"]["needs_source_retrieval"]["fuel_types"], [])
        self.assertEqual(self.unions["Frontlander"]["provisional_only"]["fuel_types"], ["Hybrid", "Petrol"])

    def test_mixed_model_keeps_only_validated_values(self):
        uc = self.unions["Urban Cruiser"]
        self.assertEqual({k: v for k, v in uc["verified"].items() if v}, {"fuel_types": ["Electric"], "drivetrains": ["FWD"], "body_types": ["SUV"]})
        self.assertEqual(uc["needs_source_retrieval"]["trims"], ["Design", "Excel", "Icon"])
        self.assertEqual(self.unions["bZ4X"]["verified"]["trims"], ["Design", "Icon", "Limited", "XLE"])

    def test_fully_validated_models_are_unchanged(self):
        for m in ("bZ4X", "Grand Highlander", "Prius Prime", "Yaris Cross"):
            u = self.unions[m]
            self.assertTrue(any(u["verified"].values()), m)
            self.assertEqual(u["verified"], u["union"])

    def test_record_counts_by_state_add_up(self):
        for m, d in self.docs.items():
            ic = self.unions[m]["generated_from"]["records_by_integrity_state"]
            self.assertEqual(sum(ic.values()), len(d["records"]), m)
            self.assertEqual(ic, L.integrity_counts(d)["records"], m)

    def test_unions_on_disk_equal_regenerated(self):
        for m, d in self.docs.items():
            self.assertEqual(json.loads(json.dumps(B.build_model_union("Toyota", m, d))), self.unions[m], m)

    def test_no_evidence_record_was_deleted(self):
        manifest = L.read_json(B.manifest_path("Toyota"))
        for m, d in self.docs.items():
            stem = B.evidence_path("Toyota", m).stem
            self.assertEqual(L.check_manifest(d, manifest[stem])[0], [], m)
            self.assertEqual(sorted(manifest[stem]["records"]), sorted(r["record_id"] for r in d["records"]), m)


class StatusAndCoverage(unittest.TestCase):
    def cov(self, good_dims, verified=True):
        base = {"class": "NO_EVIDENCE", "verified_values": 0, "needs_source_retrieval_values": 0, "provisional_only_values": 0, "verified_source_count": 0, "verified_scope_count": 0, "conflicts": []}
        out = {}
        for d in B.COV_DIMS:
            out[d] = dict(base, **({"class": "GOOD", "verified_values": 1 if verified else 0} if d in good_dims else {"class": "PARTIAL", "needs_source_retrieval_values": 1}))
        return out

    def test_researched_needs_an_integrity_verified_tier123_record(self):
        cov = self.cov(B.COV_DIMS)
        self.assertEqual(B.model_status(cov, 20, integrity_verified_records=3), "RESEARCHED")
        self.assertNotEqual(B.model_status(cov, 20, integrity_verified_records=0), "RESEARCHED")

    def test_many_snippet_only_values_never_make_a_model_researched(self):
        st = {m: s for b in L.read_json(B.plan_path("Toyota"))["batches"] for m, s in b["model_status"].items()}
        for m in ("Veloz", "Wigo", "bZ3", "bZ3X", "Frontlander"):
            self.assertEqual(st[m], "NEEDS_MORE_SOURCES", m)

    def test_snippet_only_dimensions_are_partial_not_good(self):
        d = L.read_json(B.evidence_path("Toyota", "Veloz"))
        cov = B.coverage(d, L.read_json(B.union_path("Toyota", "Veloz")))
        for dim in ("trims", "engine_sizes", "seats"):
            self.assertEqual(cov[dim]["class"], "PARTIAL", dim)
            self.assertEqual(cov[dim]["verified_values"], 0)
            self.assertGreater(cov[dim]["needs_source_retrieval_values"], 0)

    def test_validated_sources_still_make_dimensions_good(self):
        d = L.read_json(B.evidence_path("Toyota", "bZ4X"))
        cov = B.coverage(d, L.read_json(B.union_path("Toyota", "bZ4X")))
        self.assertEqual(cov["drivetrains"]["class"], "GOOD")
        self.assertGreaterEqual(cov["drivetrains"]["verified_source_count"], 2)

    def test_status_vocabulary_is_unchanged_and_never_complete(self):
        self.assertEqual(B.MODEL_STATUSES, ["NOT_STARTED", "NEEDS_MORE_SOURCES", "PARTIALLY_RESEARCHED", "RESEARCHED", "CONFLICT"])
        self.assertNotIn("COMPLETE", json.dumps(L.read_json(B.plan_path("Toyota"))))


class ComparisonSplit(unittest.TestCase):
    def test_new_verified_excludes_needs_source_retrieval(self):
        rep = {m["model"]: m for m in L.read_json(B.comparison_path("Toyota", 1))["models"]}
        v = rep["Veloz"]["dimensions"]["trims"]
        self.assertEqual(v["NEW_VERIFIED"], [])
        self.assertEqual(v["NEW_NEEDS_SOURCE_RETRIEVAL"], ["E", "G", "V"])
        self.assertEqual(v["MISSING_FROM_CARNET"], [])
        self.assertEqual(v["NEEDS_SOURCE_RETRIEVAL_NOT_IN_CARNET"], ["E", "G", "V"])
        self.assertEqual(rep["Yaris Cross"]["dimensions"]["fuel_types"]["MISSING_FROM_CARNET"], ["Hybrid"])
        self.assertEqual(rep["Veloz"]["evidence_integrity"]["records_by_state"]["SNIPPET_ONLY"], 8)

    def test_carnet_values_supported_only_by_unvalidated_evidence_are_not_called_wrong_or_confirmed(self):
        rep = {m["model"]: m for m in L.read_json(B.comparison_path("Toyota", 1))["models"]}
        f = rep["Veloz"]["dimensions"]["fuel_types"]
        self.assertEqual(f["CURRENT_CARNET"], ["Petrol"])
        self.assertEqual(f["CARNET_VALUE_ONLY_NEEDS_SOURCE_RETRIEVAL"], ["Petrol"])
        self.assertEqual(f["ONLY_IN_CARNET"], [])
        self.assertEqual(f["MATCHED"], [])


class PilotRegression(unittest.TestCase):
    NAMES = ("ford_everest", "toyota_land_cruiser", "toyota_camry")

    def test_pilot_evidence_records_are_untouched(self):
        manifest = L.read_json(HERE / "reports" / "evidence_manifest.json")
        for n in self.NAMES:
            d = L.read_json(HERE / "evidence" / f"{n}.json")
            errs, notes = L.check_manifest(d, manifest[n])
            self.assertEqual((errs, notes), ([], []), n)

    def test_pilot_states_are_honest(self):
        counts = {}
        for n in self.NAMES:
            d = L.read_json(HERE / "evidence" / f"{n}.json")
            self.assertEqual(L.validate_evidence(d), [], n)
            c = L.integrity_counts(d)["records"]
            counts[n] = c
            self.assertEqual(sum(c.values()), len(d["records"]), n)
        # FE-S1 + FE-S7 could not be re-fetched (HTTP 403) and stay search snippets; FE-S2 / FE-S6 are UNAVAILABLE
        self.assertEqual(counts["ford_everest"]["SNIPPET_ONLY"], 7)
        self.assertEqual(counts["ford_everest"]["UNAVAILABLE"], 14)
        self.assertEqual(counts["toyota_land_cruiser"]["UNAVAILABLE"], 3)  # LC-S12 (tier 5) answered HTTP 429
        # CM-S2 (8 records) + CM-S3 (7) + CM-S4 (1): CM-S3 / CM-S4 were promoted after the HIGH-confidence quote repairs were approved
        self.assertEqual(counts["toyota_camry"]["FULL_TEXT_VERIFIED"], 16)
        self.assertEqual(counts["toyota_camry"]["RETRIEVED_UNVERIFIABLE"], 7)  # CM-S1 (the page now states 232 hp, not 225 hp) stays unresolved

    def test_pilot_values_survive_as_needs_source_retrieval_not_deleted(self):
        u = L.read_json(HERE / "generated" / "toyota_camry.union.json")
        self.assertIn("XLE", u["verified"]["trims"])  # CM-S2 records whose quote was found in the preserved snapshot
        self.assertIn("Nightshade", u["needs_source_retrieval"]["trims"])  # CM-S1 quote no longer in the page -> not verified, not deleted
        self.assertEqual(u["verified"]["fuel_types"], ["Hybrid", "Petrol"])  # now backed by the repaired CM-S3 / CM-S2 quotes
        for lost in ("LE HEV", "Lumiere HEV"):  # trims whose only evidence is unconfirmed stay NEEDS_SOURCE_RETRIEVAL
            self.assertIn(lost, u["needs_source_retrieval"]["trims"])
        self.assertEqual(u["generated_from"]["record_count"], 23)


if __name__ == "__main__":
    unittest.main()
