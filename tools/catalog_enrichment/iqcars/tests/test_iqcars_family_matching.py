"""Committed family-matching audit (generated/iqcars_family_matching_audit.json): sibling isolation guards."""
import json
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parents[1]
AUDIT = json.loads((HERE / "generated" / "iqcars_family_matching_audit.json").read_text(encoding="utf-8"))


class FamilyMatchingAudit(unittest.TestCase):
    def test_python_rederivation_matches_the_dart_matcher(self):
        self.assertEqual(AUDIT["summary"]["python_vs_dart_parity_failures"], [])

    def test_every_change_is_clear_sibling_contamination(self):
        self.assertEqual(set(AUDIT["summary"]["classification"]), {"CLEAR SIBLING CONTAMINATION"})
        for i in AUDIT["changed_models"]:
            self.assertGreater(i["strict_rows"], 0, i["model"])
            self.assertEqual(set(i["removed_rows_belong_to"]), set(i["tooling_owner_of_removed_rows"]), i["model"])

    def test_no_coverage_lost(self):
        self.assertEqual(AUDIT["summary"]["models_whose_coverage_changed"], 0)
        for i in AUDIT["changed_models"]:
            self.assertTrue(i["coverage_strict"], i["model"])

    def test_land_cruiser_and_prado_are_disjoint(self):
        a = AUDIT["land_cruiser_acceptance"]
        self.assertEqual(a["land_cruiser_strict_rows_that_are_prado_rows"], [])
        self.assertEqual(a["prado_strict_rows_that_are_land_cruiser_only_rows"], [])
        self.assertEqual(a["rows_shared_between_the_two_strict_sets"], [])
        self.assertTrue(a["land_cruiser_rows_removed_were_all_prado_named"])
        self.assertEqual((a["Land Cruiser"]["old_rows"], a["Land Cruiser"]["strict_rows"]), (151, 74))
        self.assertEqual((a["Land Cruiser Prado"]["old_rows"], a["Land Cruiser Prado"]["strict_rows"]), (77, 77))

    def test_required_pairs_are_among_the_changed_models(self):
        changed = {(i["brand"], i["model"]) for i in AUDIT["changed_models"]}
        for k in [("Toyota", "Land Cruiser"), ("Toyota", "Corolla"), ("Volkswagen", "Golf"), ("Ford", "Bronco"),
                  ("Mitsubishi", "Pajero"), ("Land Rover", "Discovery"), ("Volkswagen", "Passat"), ("Renault", "Megane")]:
            self.assertIn(k, changed)


if __name__ == "__main__":
    unittest.main()
