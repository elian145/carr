"""Union generation: VERIFIED vs PROVISIONAL, conflicts kept unresolved, detailed records retained."""
import copy
import random
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import enrichment_lib as L  # noqa: E402


def src(tier, host="manufacturer_domain", retrieval="fetched_full_text"):
    return {"url": f"https://example.test/t{tier}", "name": f"tier {tier} source", "tier": tier, "host_type": host, "retrieval": retrieval, "accessed_at": "2026-10-03"}


def rec(rid, sid, text, **kw):
    r = {
        "record_id": rid, "brand": "Acme", "model": "Roadster", "year_from": kw.pop("year_from", 2020), "year_to": kw.pop("year_to", 2020),
        "market": kw.pop("market", None), "trim": kw.pop("trim", None), "variant": kw.pop("variant", None), "body_type": kw.pop("body_type", None),
        "drivetrain": kw.pop("drivetrain", None), "seats": kw.pop("seats", None),
        "engine": {"displacement_raw": kw.pop("disp", None), "fuel_type": kw.pop("fuel", None), "cylinders": kw.pop("cyl", None),
                   "horsepower": kw.pop("hp", None), "torque": kw.pop("tq", None)},
        "transmission": {"type": kw.pop("trans", None), "gears": kw.pop("gears", None)},
        "evidence": {"source_id": sid, "supporting_text": text},
    }
    assert not kw, kw
    return r


def doc(records, sources=None):
    d = {
        "schema_version": L.SCHEMA_EVIDENCE, "brand": "Acme", "model": "Roadster", "researched_at": "2026-10-03",
        "sources": sources or {"T1": src(1), "T3": src(3, "official_distributor_domain"), "T4": src(4, "independent"), "T5": src(5, "independent")},
        "records": records,
    }
    return L.prepare_evidence(d)


def union_of(records, **kw):
    d = doc(records, **kw)
    assert L.validate_evidence(d) == [], L.validate_evidence(d)
    conflicts = L.detect_conflicts(d["records"], "acme-roadster")
    return d, L.build_union(d, conflicts), conflicts


class VerifiedVsProvisional(unittest.TestCase):
    def test_tier1_value_is_verified_and_in_union(self):
        _, u, _ = union_of([rec("AC-001", "T1", "2.5L Petrol 4WD", disp="2.5L", fuel="Petrol", drivetrain="4WD")])
        self.assertEqual(u["union"]["fuel_types"], ["Petrol"])
        self.assertEqual(u["union"]["drivetrains"], ["4WD"])
        self.assertEqual(u["union"]["engine_sizes"], ["2.5L"])
        self.assertEqual(u["provisional_only"]["fuel_types"], [])

    def test_tier3_regional_distributor_is_verified(self):
        _, u, _ = union_of([rec("AC-001", "T3", "Diesel", fuel="Diesel")])
        self.assertEqual(u["union"]["fuel_types"], ["Diesel"])

    def test_tier4_and_tier5_only_values_are_provisional_and_not_in_the_union(self):
        _, u, _ = union_of([
            rec("AC-001", "T1", "2.5L Petrol", disp="2.5L", fuel="Petrol"),
            rec("AC-002", "T4", "AWD 7 seats", drivetrain="AWD", seats="7 seats"),
            rec("AC-003", "T5", "Diesel", fuel="Diesel"),
        ])
        self.assertEqual(u["union"]["drivetrains"], [])
        self.assertEqual(u["provisional_only"]["drivetrains"], ["AWD"])
        self.assertEqual(u["union"]["seats"], [])
        self.assertEqual(u["provisional_only"]["seats"], [7])
        self.assertEqual(u["union"]["fuel_types"], ["Petrol"])
        self.assertEqual(u["provisional_only"]["fuel_types"], ["Diesel"])
        st = {x["value"]: x["status"] for x in u["details"]["fuel_types"]}
        self.assertEqual(st, {"Petrol": "VERIFIED", "Diesel": "PROVISIONAL"})

    def test_tier1_support_makes_a_value_verified_even_if_tier5_also_says_it(self):
        _, u, _ = union_of([rec("AC-001", "T5", "AWD", drivetrain="AWD"), rec("AC-002", "T1", "AWD", drivetrain="AWD")])
        self.assertEqual(u["union"]["drivetrains"], ["AWD"])
        self.assertEqual(u["details"]["drivetrains"][0]["record_ids"], ["AC-001", "AC-002"])

    def test_production_policy_never_includes_provisional(self):
        _, u, _ = union_of([rec("AC-001", "T5", "Diesel", fuel="Diesel")])
        self.assertFalse(u["production_policy"]["includes_provisional"])
        self.assertEqual(u["production_policy"]["production_bound_section"], "union")
        self.assertEqual(u["production_policy"]["review_status"], "UNREVIEWED")
        self.assertEqual(u["union"]["fuel_types"], [])
        self.assertEqual(u["provisional_only"]["fuel_types"], ["Diesel"])

    def test_tier5_disagreement_does_not_demote_a_tier1_value(self):
        _, u, c = union_of([
            rec("AC-001", "T1", "2.5L 200 hp", disp="2.5L", hp={"value": 200, "unit": "hp"}),
            rec("AC-002", "T5", "2.5L 190 hp", disp="2.5L", hp={"value": 190, "unit": "hp"}),
        ])
        self.assertEqual(len(c), 1)
        self.assertEqual(u["union"]["engine_sizes"], ["2.5L"])
        self.assertEqual(u["conflicts"][0]["resolution"].split(" ")[0], "UNRESOLVED")

    def test_two_tier1_records_that_contradict_are_both_demoted_and_both_kept(self):
        d, u, c = union_of([
            rec("AC-001", "T1", "2.5L AWD", disp="2.5L", drivetrain="AWD"),
            rec("AC-002", "T1", "2.5L 4WD", disp="2.5L", drivetrain="4WD"),
        ])
        self.assertEqual(len(c), 1)
        self.assertEqual(c[0]["field"], "drivetrain")
        self.assertEqual(sorted(v["value"] for v in c[0]["values"]), ["4WD", "AWD"])
        self.assertEqual(u["union"]["drivetrains"], [])  # nothing is silently chosen
        self.assertEqual(u["provisional_only"]["drivetrains"], ["4WD", "AWD"])
        self.assertEqual(u["production_policy"]["unresolved_conflicts"], 1)
        self.assertTrue(u["production_policy"]["conflicts_block_promotion_until_reviewed"])
        self.assertEqual(len(d["records"]), 2)

    def test_tier1_disagreement_for_a_different_market_is_not_a_conflict(self):
        _, u, c = union_of([
            rec("AC-001", "T1", "2.5L AWD", disp="2.5L", drivetrain="AWD", market="UAE"),
            rec("AC-002", "T1", "2.5L 4WD", disp="2.5L", drivetrain="4WD", market="Australia"),
        ])
        self.assertEqual(c, [])
        self.assertEqual(u["union"]["drivetrains"], ["4WD", "AWD"])


class LockedVocabularyInUnion(unittest.TestCase):
    def test_petrol_spellings_collapse_to_one_value(self):
        _, u, _ = union_of([
            rec("AC-001", "T1", "Gasoline", fuel="Gasoline"),
            rec("AC-002", "T1", "Unleaded", fuel="Unleaded"),
            rec("AC-003", "T1", "Petrol (Gasoline)", fuel="Petrol (Gasoline)"),
        ])
        self.assertEqual(u["union"]["fuel_types"], ["Petrol"])

    def test_hybrid_stays_separate_from_petrol(self):
        _, u, c = union_of([
            rec("AC-001", "T1", "2.5L Petrol 150 hp", disp="2.5L", fuel="Petrol", hp={"value": 150, "unit": "hp"}),
            rec("AC-002", "T1", "2.5L Hybrid 200 hp", disp="2.5L", fuel="Hybrid", hp={"value": 200, "unit": "hp"}),
        ])
        self.assertEqual(u["union"]["fuel_types"], ["Hybrid", "Petrol"])
        self.assertEqual(c, [])  # a hybrid and a petrol of the same size are different configurations

    def test_awd_and_4wd_are_separate_values(self):
        _, u, _ = union_of([
            rec("AC-001", "T1", "AWD", drivetrain="AWD", market="UAE"),
            rec("AC-002", "T1", "4x4", drivetrain="4x4", market="Australia"),
            rec("AC-003", "T1", "Full-time four-wheel drive", drivetrain="Full-time four-wheel drive", market="Japan"),
        ])
        self.assertEqual(u["union"]["drivetrains"], ["4WD", "AWD"])

    def test_two_level_transmission_in_union(self):
        _, u, _ = union_of([
            rec("AC-001", "T1", "CVT", trans="CVT", market="UAE"),
            rec("AC-002", "T1", "8-speed dual-clutch", trans="8-speed dual-clutch", market="Japan"),
            rec("AC-003", "T1", "E-CVT", trans="E-CVT", market="Australia"),
            rec("AC-004", "T1", "6-speed manual", trans="6-speed manual", market="Thailand"),
        ])
        self.assertEqual(u["union"]["transmissions"], ["Automatic", "Manual"])
        self.assertEqual(sorted(u["union"]["transmission_variants"]), ["CVT", "DCT", "e-CVT"])
        self.assertEqual(u["union"]["transmission_gears"], [6, 8])

    def test_cvt_vs_e_cvt_in_same_configuration_is_a_conflict(self):
        _, _, c = union_of([rec("AC-001", "T1", "CVT", trans="CVT"), rec("AC-002", "T1", "E-CVT", trans="E-CVT")])
        self.assertEqual([x["field"] for x in c], ["transmission_variant"])

    def test_a_named_system_never_conflicts_with_a_canonical_variant(self):
        _, _, c = union_of([rec("AC-001", "T1", "6-speed torque converter automatic", trans="6-speed torque converter automatic"), rec("AC-002", "T1", "6-speed SelectShift automatic", trans="6-speed SelectShift automatic")])
        self.assertEqual(c, [])


class UnionProperties(unittest.TestCase):
    RECS = [
        rec("AC-001", "T1", "GXR 2.5L Petrol 4WD SUV 7 seats", disp="2.5L", fuel="Petrol", drivetrain="4WD", body_type="SUV", seats="7 seats", market="UAE", trim="GXR"),
        rec("AC-002", "T3", "gxr 2.5L Petrol 4WD SUV 7 seats", disp="2.5L", fuel="Petrol", drivetrain="4WD", body_type="SUV", seats="7 seats", market="KSA", trim="gxr"),
        rec("AC-003", "T1", "ZX 3.5L Diesel V6 AWD 5 seats", disp="3.5L", fuel="Diesel", cyl="V6", drivetrain="AWD", seats="5 seats", market="Japan", trim="ZX"),
    ]

    def test_values_are_unique_normalized_and_sorted(self):
        _, u, _ = union_of(self.RECS)
        un = u["union"]
        for k, v in un.items():
            self.assertEqual(len(v), len(set(v)), k)
        self.assertEqual(un["trims"], ["GXR", "ZX"])  # 'GXR' and 'gxr' are one trim
        self.assertEqual(un["engine_sizes"], ["2.5L", "3.5L"])
        self.assertEqual(un["seats"], [5, 7])

    def test_every_record_is_retained_and_traceable(self):
        d, u, _ = union_of(self.RECS)
        self.assertEqual(u["generated_from"]["record_count"], len(self.RECS))
        seen = {rid for dim in u["details"].values() for x in dim for rid in x["record_ids"]}
        self.assertEqual(seen, {r["record_id"] for r in self.RECS})
        for r in d["records"]:  # detailed metadata survives alongside the union
            for k in ("brand", "model", "generation", "year_from", "year_to", "market", "trim", "variant", "engine", "transmission", "drivetrain", "evidence", "normalized"):
                self.assertIn(k, r)

    def test_order_of_records_does_not_change_the_union(self):
        _, a, _ = union_of(self.RECS)
        shuffled = copy.deepcopy(self.RECS)
        random.Random(3).shuffle(shuffled)
        _, b, _ = union_of(shuffled)
        self.assertEqual(a["union"], b["union"])
        self.assertEqual(a["provisional_only"], b["provisional_only"])
        self.assertEqual(a["details"], b["details"])

    def test_generation_is_deterministic(self):
        _, a, _ = union_of(self.RECS)
        _, b, _ = union_of(self.RECS)
        self.assertEqual(a, b)

    def test_unknown_stays_unknown(self):
        _, u, _ = union_of(self.RECS)
        self.assertEqual(u["union"]["doors"], [])
        self.assertIn("doors", u["empty_dimensions"])

    def test_ungrounded_value_is_a_validation_error(self):
        d = doc([rec("AC-001", "T1", "2.5L Petrol", disp="2.5L", fuel="Petrol", drivetrain="4WD")])  # '4WD' not in the quote
        self.assertTrue(any("drivetrain" in e for e in L.validate_evidence(d)))


class PilotUnions(unittest.TestCase):
    NAMES = ("ford_everest", "toyota_land_cruiser", "toyota_camry")

    def test_generated_files_match_a_fresh_regeneration(self):
        for n in self.NAMES:
            d = L.read_json(L.HERE / "evidence" / f"{n}.json")
            fresh = L.build_union(d, L.detect_conflicts(d["records"], n.replace("_", "-")))
            on_disk = L.read_json(L.HERE / "generated" / f"{n}.union.json")
            self.assertEqual(fresh, on_disk, n)

    def test_no_provisional_value_leaks_into_the_union_section(self):
        for n in self.NAMES:
            u = L.read_json(L.HERE / "generated" / f"{n}.union.json")
            for dim, vals in u["union"].items():
                prov = set(map(str, u["provisional_only"][dim]))
                self.assertFalse(prov & set(map(str, vals)), (n, dim))
            for dim, det in u["details"].items():
                verified = [x["value"] for x in det if x["status"] == "VERIFIED"]
                self.assertEqual(sorted(map(str, verified)), sorted(map(str, u["union"][dim])), (n, dim))

    def test_land_cruiser_pilot_keeps_awd_provisional_and_4wd_verified(self):
        u = L.read_json(L.HERE / "generated" / "toyota_land_cruiser.union.json")
        self.assertEqual(u["union"]["drivetrains"], ["4WD"])
        self.assertEqual(u["provisional_only"]["drivetrains"], ["AWD"])
        self.assertIn("Hybrid", u["union"]["fuel_types"])
        self.assertNotIn("Hybrid", u["union"]["transmission_variants"])

    def test_record_ids_never_disappear(self):
        manifest = L.read_json(L.HERE / "reports" / "evidence_manifest.json")
        for n in self.NAMES:
            d = L.read_json(L.HERE / "evidence" / f"{n}.json")
            errs, _ = L.check_manifest(d, manifest[n])
            self.assertEqual(errs, [], n)


if __name__ == "__main__":
    unittest.main()
