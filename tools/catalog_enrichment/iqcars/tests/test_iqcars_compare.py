"""Identity-safety + comparison semantics for compare_carnet (uses CarNet's real model_boundaries on tiny fixtures)."""
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import compare_carnet as K  # noqa: E402
import model_boundaries as mb  # noqa: E402

CAT = {
    "models": {"Toyota": ["Land Cruiser", "Land Cruiser Prado", "Corolla", "Corolla Cross", "Yaris", "Yaris Cross", "RAV4"],
               "Volkswagen": ["Golf", "Golf R"], "Land Rover": ["Discovery", "Discovery Sport"], "BMW": ["3-Series"]},
    "trimsByBrandModel": {"Toyota": {"Land Cruiser": ["GX", "EXR", "VX", "Other", "Land Cruiser Only"]}},
}
RULES = {"aliases": {}, "qualifier_trims": {}, "qualifier_distinct": {}}
SUFFIX = {"token_classes": {}, "brands": {}}


def idx():
    return mb.ModelIndex(CAT, RULES, SUFFIX, use_suffix_rules=False)


def iq(i, brand, name):
    return {"brand": brand, "brand_id": 1, "model": name, "model_id": i}


class Identity(unittest.TestCase):
    def test_siblings_match_only_their_own_exact_identity(self):
        m, un, amb = K.match_models(idx(), [iq(1, "Toyota", "Land Cruiser"), iq(2, "Toyota", "Land Cruiser Prado"), iq(3, "Toyota", "Corolla"),
                                           iq(4, "Toyota", "Corolla Cross"), iq(5, "Toyota", "Yaris"), iq(6, "Toyota", "Yaris Cross"),
                                           iq(7, "Volkswagen", "Golf"), iq(8, "Volkswagen", "Golf R"),
                                           iq(9, "Land Rover", "Discovery"), iq(10, "Land Rover", "Discovery Sport")])
        self.assertEqual({x["iq_model_id"]: x["carnet_model"] for x in m},
                         {1: "Land Cruiser", 2: "Land Cruiser Prado", 3: "Corolla", 4: "Corolla Cross", 5: "Yaris", 6: "Yaris Cross",
                          7: "Golf", 8: "Golf R", 9: "Discovery", 10: "Discovery Sport"})
        self.assertEqual((un, amb), ([], []))

    def test_unknown_sibling_is_ambiguous_never_forced(self):
        m, un, amb = K.match_models(idx(), [iq(1, "Toyota", "Land Cruiser FJ"), iq(2, "Toyota", "Land Cruiser Prado 250"), iq(3, "Volkswagen", "Golf GTI")])
        self.assertEqual(m, [])
        self.assertEqual({a["iq_model"]: a["reason"] for a in amb},
                         {"Land Cruiser FJ": "near_sibling_of:Land Cruiser", "Land Cruiser Prado 250": "near_sibling_of:Land Cruiser Prado",
                          "Golf GTI": "near_sibling_of:Golf"})

    def test_compact_key_lookalike_is_ambiguous(self):
        m, un, amb = K.match_models(idx(), [iq(1, "Toyota", "RAV 4")])
        self.assertEqual(m, [])
        self.assertEqual(amb[0]["reason"], "compact_key_equal_but_not_exact_identity")
        self.assertEqual(amb[0]["carnet_candidates"], ["RAV4"])

    def test_unmatched_brand_and_model(self):
        m, un, amb = K.match_models(idx(), [iq(1, "Nope", "X"), iq(2, "Toyota", "Supra")])
        self.assertEqual({u["iq_model"]: u["reason"] for u in un}, {"X": "brand_not_in_carnet_catalog", "Supra": "model_not_in_carnet_catalog"})

    def test_two_iq_models_for_one_carnet_model_are_ambiguous(self):
        m, un, amb = K.match_models(idx(), [iq(1, "BMW", "3-Series"), iq(2, "BMW", "3 Series")])
        self.assertEqual(m, [])
        self.assertEqual({a["iq_model_id"] for a in amb}, {1, 2})
        self.assertTrue(all(a["reason"] == "several_iq_models_map_to_one_carnet_model" for a in amb))

    def test_carnet_profiles_do_not_cross_sibling_boundaries(self):
        ds = {"brands": [{"id": 1, "name": "Toyota"}],
              "models": [{"id": 1, "brand_id": 1, "name": "Land Cruiser Prado 2 7 i (163 Hp) 4WD"},
                         {"id": 2, "brand_id": 1, "name": "Land Cruiser 4 5D V8 (235 Hp) Automatic"},
                         {"id": 3, "brand_id": 1, "name": "Corolla Cross 1 8 Hybrid (140 Hp)"}],
              "trims": [{"id": 1, "model_id": 1, "year": 2010, "year_end": 2013, "name": "x"},
                        {"id": 2, "model_id": 2, "year": 2000, "year_end": 2007, "name": "x"},
                        {"id": 3, "model_id": 3, "year": 2021, "year_end": 2024, "name": "x"}],
              "specs": [{"trim_id": 1, "displacement_cc": 2694, "raw_spec_pairs": {"Cylinders alignment:": "inline 4"}},
                        {"trim_id": 2, "displacement_cc": 4477, "raw_spec_pairs": {"Cylinders alignment:": "v 8"}},
                        {"trim_id": 3, "displacement_cc": 1798, "raw_spec_pairs": {"Cylinders alignment:": "inline 4"}}]}
        prof, _ = K.carnet_profiles(idx(), ds)
        self.assertEqual((prof[("Toyota", "Land Cruiser Prado")]["engines"], prof[("Toyota", "Land Cruiser Prado")]["cylinders"]), ({"2.7L"}, {4}))
        self.assertEqual((prof[("Toyota", "Land Cruiser")]["engines"], prof[("Toyota", "Land Cruiser")]["cylinders"]), ({"4.5L"}, {8}))
        self.assertEqual(prof[("Toyota", "Corolla Cross")]["engines"], {"1.8L"})
        self.assertNotIn(("Toyota", "Corolla"), prof)


class Comparison(unittest.TestCase):
    def iq_rec(self, trims, sizes, cyls, dup=()):
        return {"brand_id": 1, "model_id": 1, "model": "Land Cruiser", "trims": trims, "engine_sizes": sizes,
                "engine_variants": [{"raw_values": [s[:-1]], "display": s, "qualifier": ""} for s in sizes], "cylinders": cyls,
                "possible_duplicate_trims": list(dup)}

    def run_cmp(self, rec, prof=None):
        m = {"carnet_brand": "Toyota", "carnet_model": "Land Cruiser", "via": "exact_key"}
        return K.compare_model(m, rec, CAT, prof if prof is not None else {("Toyota", "Land Cruiser"): {"engines": {"4.0L", "4.5L"}, "cylinders": {6, 8}, "dataset_rows": 9}})

    def test_missing_only_and_common(self):
        c = self.run_cmp(self.iq_rec(["GX", "VX", "VX.R"], ["4.0L", "4.6L"], [6]))
        self.assertEqual(c["TRIMS"]["COMMON"], ["GX", "VX"])
        self.assertEqual(c["TRIMS"]["MISSING_FROM_CARNET"], ["VX.R"])
        self.assertEqual(c["TRIMS"]["ONLY_IN_CARNET"], ["EXR", "Land Cruiser Only"])  # 'Other' placeholder excluded, nothing called wrong
        self.assertEqual((c["ENGINES"]["MISSING_FROM_CARNET"], c["ENGINES"]["ONLY_IN_CARNET"]), (["4.6L"], ["4.5L"]))
        self.assertEqual((c["CYLINDERS"]["MISSING_FROM_CARNET"], c["CYLINDERS"]["ONLY_IN_CARNET"]), ([], [8]))

    def test_lookalike_trims_not_merged_but_flagged(self):
        c = self.run_cmp(self.iq_rec(["EX.R"], [], []))
        self.assertEqual(c["TRIMS"]["MISSING_FROM_CARNET"], ["EX.R"])
        self.assertIn("EXR", c["TRIMS"]["ONLY_IN_CARNET"])
        cross = c["TRIMS"]["POSSIBLE_DUPLICATES"]["cross_source"]
        self.assertEqual(len(cross), 1)
        self.assertEqual((cross[0]["iq"], cross[0]["carnet"], cross[0]["status"]), (["EX.R"], ["EXR"], "POSSIBLE_DUPLICATES"))

    def test_within_iq_possible_duplicates_surface(self):
        dup = [{"status": "POSSIBLE_DUPLICATES", "names": ["A-B", "A B"]}]
        c = self.run_cmp(self.iq_rec(["A-B", "A B"], [], [], dup))
        self.assertEqual(c["TRIMS"]["POSSIBLE_DUPLICATES"]["within_iq"], dup)
        self.assertEqual(c["TRIMS"]["MISSING_FROM_CARNET"], ["A-B", "A B"])

    def test_carnet_without_data_flagged(self):
        c = self.run_cmp(self.iq_rec([], ["2.0L"], [4]), prof={})
        self.assertFalse(c["carnet_has_data"]["engines"])
        self.assertEqual(c["ENGINES"]["MISSING_FROM_CARNET"], ["2.0L"])

    def test_iq_qualifier_variants_kept_for_reference_only(self):
        r = self.iq_rec([], ["4.5L"], [])
        r["engine_variants"] = [{"raw_values": ["4.5"], "display": "4.5L", "qualifier": ""}, {"raw_values": ["4.5TD"], "display": "4.5L", "qualifier": "TD"}]
        c = self.run_cmp(r)
        self.assertEqual(c["ENGINES"]["COMMON"], ["4.5L"])
        self.assertEqual(c["ENGINES"]["IQ_CARS_VARIANTS_RAW"], [["4.5"], ["4.5TD"]])


if __name__ == "__main__":
    unittest.main()
