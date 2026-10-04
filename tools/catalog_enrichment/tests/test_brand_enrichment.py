"""Brand-scale enrichment (Toyota Batch 1): inventory, deterministic batching, evidence integrity, pilot reuse, sibling
isolation, VERIFIED vs PROVISIONAL separation, union + comparison generation, source-quote validation, determinism."""
import copy
import json
import random
import re
import sys
import unittest
from collections import Counter
from pathlib import Path

HERE = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(HERE))
import brand_enrichment as B  # noqa: E402
import enrichment_lib as L  # noqa: E402
import model_boundaries as mb  # noqa: E402

BRAND = "Toyota"
BATCH1 = ["bZ3", "bZ3X", "bZ4X", "Urban Cruiser", "Frontlander", "Grand Highlander", "Prius Prime", "Veloz", "Wigo", "Yaris Cross"]
REPO = HERE.parents[1]


def _ts(p: Path):
    return p.stat().st_mtime_ns


class Base(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.inv = B.build_inventory(BRAND)
        cls.mi = mb.load_index()[0]
        cls.plan = B.build_plan(BRAND, cls.inv, cls.mi)
        cls.b1 = cls.plan["batches"][0]

    def inv_model(self, name):
        return next(m for m in self.inv["models"] if m["model"] == name)


class InventoryGeneration(Base):
    def test_every_toyota_catalog_model_is_inventoried_once(self):
        names = [m["model"] for m in self.inv["models"]]
        self.assertEqual(len(names), len(set(names)))
        self.assertEqual(self.inv["totals"]["models"], len(names))
        self.assertGreaterEqual(len(names), 80)
        for old in ("Corona", "Celica", "Tercel", "Carina"):  # older models are never dropped
            self.assertIn(old, names)

    def test_required_fields_per_model(self):
        need = {"model", "legacy_spec_rows", "catalog_trim_count", "newest_legacy_model_year", "sparse_flags", "collision_risk",
                "has_enrichment_evidence", "current_known_dimensions"}
        dims = {"trims", "engines", "cylinders", "fuel", "transmission", "drivetrain", "seating", "body_type"}
        for m in self.inv["models"]:
            self.assertTrue(need <= set(m), m["model"])
            self.assertEqual(set(m["current_known_dimensions"]), dims, m["model"])
            self.assertIn(m["collision_risk"], ("HIGH", "MEDIUM", "LOW"))

    def test_zero_row_models_are_flagged_sparse(self):
        zero = [m for m in self.inv["models"] if m["legacy_spec_rows"] == 0]
        self.assertTrue(zero)
        for m in zero:
            self.assertTrue(m["sparse_or_incomplete"], m["model"])
            self.assertIn("few_rows", m["sparse_flags"])

    def test_sibling_and_prefix_collision_risk_is_reported(self):
        lc = self.inv_model("Land Cruiser")
        self.assertIn("Land Cruiser Prado", lc["collision_detail"]["must_remain_distinct_with"] + lc["collision_detail"]["longer_siblings"])
        self.assertNotEqual(lc["collision_risk"], "LOW")
        self.assertIn("Yaris", self.inv_model("Yaris Cross")["collision_detail"]["shorter_parents"])
        self.assertIn("Prius", self.inv_model("Prius Prime")["collision_detail"]["shorter_parents"])

    def test_pilot_models_show_existing_evidence(self):
        self.assertTrue(self.inv_model("Camry")["has_enrichment_evidence"])
        self.assertTrue(self.inv_model("Land Cruiser")["has_enrichment_evidence"])

    def test_inventory_does_not_touch_production_files(self):
        before = {p: _ts(p) for p in (REPO / "assets").glob("car_*.json")}
        B.build_inventory(BRAND)
        self.assertEqual(before, {p: _ts(p) for p in before})


class DeterministicBatching(Base):
    def test_every_model_in_exactly_one_batch(self):
        flat = [m for b in self.plan["batches"] for m in b["models"]]
        self.assertEqual(len(flat), len(set(flat)))
        self.assertEqual(set(flat), {m["model"] for m in self.inv["models"]})
        self.assertTrue(self.plan["all_models_assigned_exactly_once"])

    def test_batches_are_balanced_around_ten(self):
        sizes = [len(b["models"]) for b in self.plan["batches"]]
        self.assertTrue(all(8 <= s <= 11 for s in sizes), sizes)
        self.assertLessEqual(max(sizes) - min(sizes), 1)
        self.assertEqual(sum(sizes), self.inv["totals"]["models"])

    def test_input_order_does_not_change_batches(self):
        shuffled = copy.deepcopy(self.inv)
        random.Random(7).shuffle(shuffled["models"])
        a = [[m["model"] for m, _ in items] for items in B.make_batches(self.inv)]
        b = [[m["model"] for m, _ in items] for items in B.make_batches(shuffled)]
        self.assertEqual(a, b)

    def test_priority_never_increases_across_batches(self):
        batches = B.make_batches(self.inv)
        for earlier, later in zip(batches, batches[1:]):
            self.assertGreaterEqual(min(p["score"] for _, p in earlier), max(p["score"] for _, p in later))

    def test_batch_1_is_the_committed_toyota_batch(self):
        self.assertEqual(self.b1["models"], BATCH1)
        self.assertEqual(self.b1["batch_id"], "toyota-batch-01")

    def test_pilot_models_are_not_in_batch_1(self):
        self.assertNotIn("Land Cruiser", self.b1["models"])
        self.assertNotIn("Camry", self.b1["models"])


class EvidenceIntegrity(Base):
    def _files(self):
        return sorted((HERE / "evidence").glob("*.json")) + sorted((HERE / "evidence").glob("*/*.json"))

    def test_no_duplicate_evidence_ids_anywhere(self):
        seen = {}
        for p in self._files():
            doc = L.read_json(p)
            ids = [r["record_id"] for r in doc["records"]]
            self.assertEqual(len(ids), len(set(ids)), p.name)
            for i in ids:
                self.assertRegex(i, r"^[A-Z]{2}-\d{3}$")
                self.assertNotIn(i, seen, f"{i} in {p.name} and {seen.get(i)}")
                seen[i] = p.name

    def test_batch_1_evidence_validates(self):
        for m in BATCH1:
            doc = L.read_json(B.evidence_path(BRAND, m))
            self.assertEqual(L.validate_evidence(doc, self.mi), [], m)
            self.assertEqual(B.verify_source_quotes(doc, B.evidence_path(BRAND, m))[0], [], m)

    def test_every_nonnull_value_traces_to_its_own_quote(self):
        for m in BATCH1:
            for r in L.read_json(B.evidence_path(BRAND, m))["records"]:
                self.assertEqual(L.trace_check(r), [], f"{m} {r['record_id']}")

    def test_every_record_carries_full_provenance(self):
        for m in BATCH1:
            doc = L.read_json(B.evidence_path(BRAND, m))
            for r in doc["records"]:
                ev = r["evidence"]
                for k in ("source_url", "source_name", "source_tier", "accessed_at", "supporting_text"):
                    self.assertTrue(ev.get(k), f"{r['record_id']} missing {k}")
                self.assertTrue(r["market"], r["record_id"])

    def test_unsupported_value_is_rejected(self):
        doc = copy.deepcopy(L.read_json(B.evidence_path(BRAND, "Wigo")))
        doc["records"][3]["engine"]["horsepower"]["value"] = 999
        self.assertTrue(L.validate_evidence(doc, self.mi))

    def test_unmapped_vocabulary_is_rejected(self):
        doc = copy.deepcopy(L.read_json(B.evidence_path(BRAND, "Veloz")))
        doc["records"][0]["market"] = "Atlantis"
        self.assertTrue(any("market" in e for e in L.validate_evidence(L.prepare_evidence(doc), self.mi)))

    def test_duplicate_record_id_is_rejected(self):
        doc = copy.deepcopy(L.read_json(B.evidence_path(BRAND, "Wigo")))
        doc["records"][1]["record_id"] = doc["records"][0]["record_id"]
        self.assertTrue(L.validate_evidence(doc, self.mi))


class PilotReuse(Base):
    def test_land_cruiser_and_camry_use_the_pilot_files_in_place(self):
        for model, slug in (("Land Cruiser", "land_cruiser"), ("Camry", "camry")):
            p = B.evidence_path(BRAND, model)
            self.assertEqual(p, HERE / "evidence" / f"toyota_{slug}.json")
            self.assertTrue(B.is_pilot_file(p))
            self.assertEqual(B.union_path(BRAND, model), HERE / "generated" / f"toyota_{slug}.union.json")
            self.assertFalse((HERE / "evidence" / "toyota" / f"{slug}.json").exists(), "pilot evidence must not be copied")

    def test_pilot_unions_regenerate_identically_and_are_not_rewritten(self):
        for model in ("Land Cruiser", "Camry"):
            p = B.union_path(BRAND, model)
            before = (p.read_bytes(), _ts(p))
            union = B.build_model_union(BRAND, model, L.read_json(B.evidence_path(BRAND, model)))
            self.assertEqual(json.loads(json.dumps(union)), L.read_json(p))
            B.cmd_generate(BRAND, {"models": [model]})
            self.assertEqual(before, (p.read_bytes(), _ts(p)))

    def test_pilot_manifest_guard_still_passes(self):
        pilot_manifest = L.read_json(HERE / "reports" / "evidence_manifest.json")
        total = 0
        for model in ("Land Cruiser", "Camry"):
            p = B.evidence_path(BRAND, model)
            doc = L.read_json(p)
            total += len(doc["records"])
            self.assertEqual(L.check_manifest(doc, pilot_manifest.get(p.stem))[0], [], model)
        self.assertGreater(total, 0)

    def test_pilot_models_are_reported_with_pilot_evidence_in_the_plan(self):
        state = {m["model"]: m for b in self.plan["batches"] for m in b["model_plan"]}
        self.assertEqual(state["Land Cruiser"]["existing_evidence"], "evidence/toyota_land_cruiser.json")
        self.assertEqual(state["Camry"]["existing_evidence"], "evidence/toyota_camry.json")
        status = {k: v for b in self.plan["batches"] for k, v in b["model_status"].items()}
        # after the pilot sources were re-fetched, only the records whose quotes were found in a preserved snapshot are
        # VERIFIED. After the approved HIGH-confidence quote repairs Land Cruiser has enough of them to be RESEARCHED and Camry is PARTIALLY_RESEARCHED
        # (CM-S1, whose page now states a different horsepower, is still unresolved).
        self.assertEqual(status["Land Cruiser"], "RESEARCHED")
        self.assertEqual(status["Camry"], "PARTIALLY_RESEARCHED")


class SiblingIsolation(Base):
    def test_every_record_resolves_to_its_own_file_model(self):
        for m in BATCH1:
            for r in L.read_json(B.evidence_path(BRAND, m))["records"]:
                self.assertEqual(self.mi.canonical_model(BRAND, r["model"]), m, r["record_id"])

    def test_record_for_a_sibling_model_is_rejected(self):
        for file_model, wrong in (("Yaris Cross", "Yaris"), ("Prius Prime", "Prius"), ("Grand Highlander", "Highlander"), ("bZ3X", "bZ3")):
            doc = copy.deepcopy(L.read_json(B.evidence_path(BRAND, file_model)))
            doc["records"][0]["model"] = wrong
            self.assertTrue(L.validate_evidence(doc, self.mi), f"{file_model} accepted a {wrong} record")

    def test_plan_lists_siblings_to_keep_separate(self):
        plan = {m["model"]: m for b in self.plan["batches"] for m in b["model_plan"]}
        self.assertIn("Yaris", plan["Yaris Cross"]["siblings_to_keep_separate"])
        self.assertIn("Prius", plan["Prius Prime"]["siblings_to_keep_separate"])
        self.assertIn("Highlander", plan["Grand Highlander"]["siblings_to_keep_separate"])
        self.assertIn("Land Cruiser Prado", plan["Land Cruiser"]["siblings_to_keep_separate"])
        self.assertIn("Corolla Cross", plan["Corolla"]["siblings_to_keep_separate"])

    def test_prius_prime_evidence_never_cites_the_prius_hybrid_page(self):
        doc = L.read_json(B.evidence_path(BRAND, "Prius Prime"))
        for s in doc["sources"].values():
            self.assertNotIn("toyota.com/priusprime", s["url"])
        for r in doc["records"]:
            self.assertIn("prime", r["evidence"]["supporting_text"].lower() + " " + doc["sources"][r["evidence"]["source_id"]]["name"].lower())

    def test_bz4x_rename_is_bridged_by_an_official_statement(self):
        doc = L.read_json(B.evidence_path(BRAND, "bZ4X"))
        quotes = " ".join(r["evidence"]["supporting_text"] for r in doc["records"])
        self.assertIn("switching from the Toyota bZ4X to the Toyota bZ", quotes)


class VerifiedVsProvisional(Base):
    def union(self, m):
        return L.read_json(B.union_path(BRAND, m))

    def test_tier4_tier5_only_model_has_empty_verified_union(self):
        u = self.union("Frontlander")
        self.assertTrue(all(not v for v in u["union"].values()), u["union"])
        self.assertEqual(u["provisional_only"]["engine_sizes"], ["2.0L"])
        self.assertEqual(u["provisional_only"]["fuel_types"], ["Hybrid", "Petrol"])

    def test_mixed_model_keeps_tiers_apart(self):
        u = self.union("bZ3X")
        # tier 1 but only a search snippet -> NOT verified; tier 5 -> provisional (even its validated PDF)
        self.assertEqual(u["union"]["fuel_types"], [])
        self.assertEqual(u["needs_source_retrieval"]["fuel_types"], ["Electric"])
        self.assertEqual(u["needs_source_retrieval"]["body_types"], ["SUV"])
        self.assertEqual(u["union"]["seats"], [])  # tier 5 only
        self.assertEqual(u["provisional_only"]["seats"], [5])
        self.assertEqual(u["provisional_only"]["drivetrains"], ["FWD"])
        self.assertIn("430 Air", u["provisional_only"]["trims"])
        self.assertEqual(u["union"]["trims"], [])

    def test_provisional_values_never_leak_into_union_or_policy(self):
        for m in BATCH1:
            u = self.union(m)
            for dim, vals in u["provisional_only"].items():
                self.assertFalse(set(map(str, vals)) & set(map(str, u["union"][dim])), f"{m}.{dim}")
            self.assertFalse(u["production_policy"]["includes_provisional"])
            self.assertEqual(u["production_policy"]["review_status"], "UNREVIEWED")

    def test_vocabulary_is_locked_and_not_collapsed(self):
        gh, yc, pp = self.union("Grand Highlander"), self.union("Yaris Cross"), self.union("Prius Prime")
        self.assertIn("Hybrid", gh["union"]["fuel_types"])
        self.assertIn("Petrol", gh["union"]["fuel_types"])  # 2.4L turbo gas stays Petrol, hybrids are not folded in
        self.assertEqual(yc["union"]["fuel_types"], ["Hybrid"])
        self.assertEqual(pp["union"]["fuel_types"], ["Plug-in Hybrid"])
        self.assertEqual(yc["union"]["transmission_variants"], ["e-CVT"])
        self.assertIn("CVT", pp["union"]["transmission_variants"])
        for m in BATCH1:
            u = self.union(m)
            self.assertTrue(set(u["union"]["fuel_types"]) <= {"Petrol", "Diesel", "Electric", "Hybrid", "Plug-in Hybrid"})
            self.assertTrue(set(u["union"]["drivetrains"]) <= {"FWD", "RWD", "AWD", "4WD"})
            self.assertTrue(set(u["union"]["transmissions"]) <= {"Automatic", "Manual"})

    def test_unknown_values_stay_empty(self):
        self.assertEqual(self.union("Prius Prime")["union"]["seats"], [])  # no source states it -> not inferred
        self.assertEqual(self.union("Prius Prime")["union"]["body_types"], [])
        self.assertEqual(self.union("Wigo")["union"]["drivetrains"], [])


class UnionAndComparisonGeneration(Base):
    def test_unions_on_disk_equal_regenerated_unions(self):
        for m in BATCH1:
            doc = L.read_json(B.evidence_path(BRAND, m))
            self.assertEqual(json.loads(json.dumps(B.build_model_union(BRAND, m, doc))), L.read_json(B.union_path(BRAND, m)), m)

    def test_union_dimensions_are_complete(self):
        dims = {"trims", "engine_sizes", "cylinders", "fuel_types", "transmissions", "transmission_variants", "transmission_gears", "drivetrains", "body_types", "seats", "doors"}
        for m in BATCH1:
            u = L.read_json(B.union_path(BRAND, m))
            self.assertEqual(set(u["union"]), dims)
            self.assertEqual(set(u["provisional_only"]), dims)

    def test_comparison_on_disk_equals_regenerated(self):
        ctx = L.load_current_carnet()
        rep = B.build_batch_comparison(BRAND, self.b1, ctx["models"], ctx)
        self.assertEqual(json.loads(json.dumps(rep)), L.read_json(B.comparison_path(BRAND, 1)))

    def test_comparison_has_all_required_blocks_for_every_batch_1_model(self):
        rep = L.read_json(B.comparison_path(BRAND, 1))
        self.assertEqual([m["model"] for m in rep["models"]], BATCH1)
        for m in rep["models"]:
            for dim in B.COV_DIMS:
                d = m["dimensions"][dim]
                for k in ("CURRENT_CARNET", "NEW_VERIFIED", "MISSING_FROM_CARNET", "ONLY_IN_CARNET", "CONFLICTS", "UNKNOWN_NOT_YET_RESEARCHED", "research_coverage"):
                    self.assertIn(k, d, f"{m['model']}.{dim}")
                self.assertIn(d["research_coverage"], ("GOOD", "PARTIAL", "NO_EVIDENCE", "CONFLICT"))
                if d["research_coverage"] == "NO_EVIDENCE":
                    self.assertTrue(d["UNKNOWN_NOT_YET_RESEARCHED"])
                    self.assertEqual(d["NEW_VERIFIED"], [])
                else:
                    self.assertFalse(d["UNKNOWN_NOT_YET_RESEARCHED"])

    def test_only_in_carnet_is_kept_not_treated_as_wrong(self):
        rep = {m["model"]: m for m in L.read_json(B.comparison_path(BRAND, 1))["models"]}
        uc = rep["Urban Cruiser"]["dimensions"]
        self.assertTrue(any(x["value"] == "Petrol" for x in uc["fuel_types"]["ONLY_IN_CARNET"]))  # legacy petrol rows are NOT dismissed
        self.assertEqual(uc["fuel_types"]["NEW_VERIFIED"], ["Electric"])
        gh = rep["Grand Highlander"]["dimensions"]
        self.assertIn("Hybrid", gh["fuel_types"]["MISSING_FROM_CARNET"])  # hybrid is not silently equal to the legacy Petrol

    def test_status_words_are_the_allowed_set_and_never_claim_completeness(self):
        allowed = {"NOT_STARTED", "NEEDS_MORE_SOURCES", "PARTIALLY_RESEARCHED", "RESEARCHED", "CONFLICT"}
        for b in self.plan["batches"]:
            self.assertTrue(set(b["model_status"].values()) <= allowed)
        text = json.dumps(self.plan) + json.dumps(L.read_json(B.comparison_path(BRAND, 1)))
        for bad in ("COMPLETE", "DONE", "FULL_COVERAGE", "confidence_score"):
            self.assertNotIn(bad, text)

    def test_snippet_only_or_unofficial_models_are_not_marked_researched(self):
        st = {k: v for k, v in self.b1["model_status"].items()}
        self.assertEqual(st["Frontlander"], "NEEDS_MORE_SOURCES")
        self.assertEqual(st["bZ3X"], "NEEDS_MORE_SOURCES")
        self.assertNotEqual(st["Veloz"], "RESEARCHED")  # every Veloz source is a search snippet
        self.assertNotEqual(st["Wigo"], "RESEARCHED")

    def test_coverage_classes_follow_the_rules(self):
        cov = {k: B.coverage(L.read_json(B.evidence_path(BRAND, k)), L.read_json(B.union_path(BRAND, k))) for k in ("Frontlander", "bZ4X")}
        self.assertEqual(cov["Frontlander"]["engine_sizes"]["class"], "PARTIAL")  # provisional only
        self.assertEqual(cov["Frontlander"]["trims"]["class"], "NO_EVIDENCE")
        self.assertEqual(cov["bZ4X"]["drivetrains"]["class"], "GOOD")  # several sources and markets
        self.assertEqual(cov["bZ4X"]["engine_sizes"]["class"], "NO_EVIDENCE")  # electric: nothing to map, stays unknown


class SourceQuoteValidation(Base):
    """Real Toyota evidence through B.verify_source_quotes (snapshot hash + quote check). The full integrity matrix with
    scratch snapshots lives in test_evidence_integrity.py."""

    def _load(self, model="Yaris Cross"):
        p = B.evidence_path(BRAND, model)
        return L.read_json(p), p

    def test_real_preserved_sources_verify(self):
        doc, p = self._load()
        errs, stats = B.verify_source_quotes(doc, p)
        self.assertEqual(errs, [])
        self.assertEqual(stats["quote_validated_records"], len(doc["records"]))
        self.assertEqual(stats["records_passing_integrity_test"], len(doc["records"]))

    def test_preserved_snapshots_exist_and_match_their_recorded_hash(self):
        n = 0
        for m in BATCH1:
            doc, p = self._load(m)
            for sid, s in doc["sources"].items():
                integ = s["integrity"]
                if integ["state"] in L.VERIFIED_ELIGIBLE_STATES:
                    n += 1
                    f = L.HERE / integ["snapshot_path"]
                    self.assertTrue(f.exists(), sid)
                    self.assertEqual(L._sha256_file_bytes(f.read_bytes()), integ["content_sha256"], sid)
        self.assertGreaterEqual(n, 13)

    def test_a_fabricated_quote_is_caught(self):
        doc, p = self._load()
        doc["records"][1]["evidence"]["supporting_text"] += " \u2026 the 1.5 hybrid makes 999 bhp"
        errs, _ = B.verify_source_quotes(doc, p)
        self.assertTrue(any("not found" in e for e in errs))

    def test_a_tampered_hash_is_caught(self):
        doc, p = self._load()
        sid = next(iter(doc["sources"]))
        doc["sources"][sid]["integrity"]["content_sha256"] = "0" * 64
        self.assertTrue(any("hash" in e for e in B.verify_source_quotes(doc, p)[0]))

    def test_a_missing_snapshot_is_caught(self):
        doc, p = self._load()
        sid = next(iter(doc["sources"]))
        doc["sources"][sid]["integrity"]["snapshot_path"] = "evidence/toyota/_source_text/NOPE.txt"
        self.assertTrue(any("missing" in e for e in B.verify_source_quotes(doc, p)[0]))

    def test_snippet_only_records_are_reported_as_unvalidated_not_verified(self):
        doc, p = self._load("Veloz")
        errs, stats = B.verify_source_quotes(doc, p)
        self.assertEqual(errs, [])
        self.assertEqual(stats["quote_validated_records"], 0)
        self.assertEqual(stats["records_passing_integrity_test"], 0)
        self.assertTrue(all(s["integrity"]["state"] == "SNIPPET_ONLY" for s in doc["sources"].values()))

    def test_quote_segments_must_each_appear_verbatim(self):
        doc, p = self._load("Prius Prime")
        r = next(x for x in doc["records"] if "\u2026" in x["evidence"]["supporting_text"])
        r["evidence"]["supporting_text"] = r["evidence"]["supporting_text"].replace("2.0L", "9.9L", 1)
        self.assertTrue(B.verify_source_quotes(doc, p)[0])


class DeterministicReports(Base):
    def test_inventory_plan_and_comparison_are_reproducible(self):
        inv2 = B.build_inventory(BRAND)
        self.assertEqual(json.dumps(self.inv, sort_keys=True), json.dumps(inv2, sort_keys=True))
        plan2 = B.build_plan(BRAND, inv2, self.mi)
        self.assertEqual(json.dumps(self.plan, sort_keys=True), json.dumps(plan2, sort_keys=True))

    def test_committed_reports_are_in_sync_with_the_tooling(self):
        self.assertEqual(json.loads(json.dumps(self.inv)), L.read_json(B.inventory_path(BRAND)))
        self.assertEqual(json.loads(json.dumps(self.plan)), L.read_json(B.plan_path(BRAND)))

    def test_reports_contain_no_clock_values(self):
        for p in (B.inventory_path(BRAND), B.plan_path(BRAND), B.comparison_path(BRAND, 1), B.manifest_path(BRAND)):
            self.assertIsNone(re.search(r"20\d\d-\d\d-\d\dT\d\d:\d\d", p.read_text(encoding="utf-8")), p.name)

    def test_manifest_guard_matches_every_batch_1_file(self):
        manifest = L.read_json(B.manifest_path(BRAND))
        for m in BATCH1:
            p = B.evidence_path(BRAND, m)
            self.assertEqual(L.check_manifest(L.read_json(p), manifest.get(p.stem))[0], [], m)

    def test_research_plan_schema_fields(self):
        for b in self.plan["batches"]:
            for k in ("batch_id", "models", "status", "evidence_record_count", "conflicts", "provisional_values", "unresearched_fields"):
                self.assertIn(k, b)
        self.assertEqual(self.b1["status"], "RESEARCHED_PENDING_REVIEW")
        self.assertEqual(Counter(self.b1["model_status"].values())["NOT_STARTED"], 0)
        for b in self.plan["batches"][1:]:
            # batch 7 only differs because the two pilot models (Land Cruiser, Camry) were researched before this task
            self.assertEqual(b["status"], "IN_PROGRESS" if b["batch_number"] == 7 else "NOT_STARTED", b["batch_id"])

    def test_only_batch_1_has_evidence(self):
        for b in self.plan["batches"][1:]:
            if b["batch_number"] == 7:  # pilot models Land Cruiser + Camry already had evidence before this task
                continue
            self.assertEqual(b["evidence_record_count"], 0, b["batch_id"])


if __name__ == "__main__":
    unittest.main()
