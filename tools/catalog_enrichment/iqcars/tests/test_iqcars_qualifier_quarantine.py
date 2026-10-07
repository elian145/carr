"""Committed qualifier-quarantine audit (generated/iqcars_qualifier_quarantine_audit.json): internal consistency guards.

READ-ONLY audit: these tests do not assert that the app behaves a certain way, only that the report is complete and coherent.
"""
import json
import sys
import unittest
from collections import Counter
from pathlib import Path

HERE = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(HERE))
sys.path.insert(0, str(HERE.parent))
AUDIT = json.loads((HERE / "generated" / "iqcars_qualifier_quarantine_audit.json").read_text(encoding="utf-8"))
FAMILY = json.loads((HERE / "generated" / "iqcars_family_matching_audit.json").read_text(encoding="utf-8"))
S = AUDIT["summary"]
CLASSES = {"SAFE_TRIM_OR_VARIANT", "OTHER_MODEL_OR_SIBLING", "AMBIGUOUS", "MALFORMED_OR_NOISY"}


class QualifierQuarantineAudit(unittest.TestCase):
    def test_every_quarantined_row_is_audited_exactly_once_and_classified(self):
        rows = AUDIT["rows"]
        self.assertEqual(len(rows), S["1_total_quarantined_rows"])
        self.assertEqual(len({r["dataset_model_id"] for r in rows}), len(rows))
        self.assertEqual({r["class"] for r in rows} - CLASSES, set())
        c = Counter(r["class"] for r in rows)
        self.assertEqual((c["SAFE_TRIM_OR_VARIANT"], c["OTHER_MODEL_OR_SIBLING"], c["AMBIGUOUS"], c["MALFORMED_OR_NOISY"]),
                         (S["3_SAFE_TRIM_OR_VARIANT"], S["4_OTHER_MODEL_OR_SIBLING"], S["5_AMBIGUOUS"], S["6_MALFORMED_OR_NOISY"]))
        self.assertEqual(len({(r["flutter_brand"], r["flutter_model"]) for r in rows}), S["2_affected_models"])
        for r in rows:
            self.assertTrue(r["qualifier"] is not None and r["rule"] and r["tooling_status"] in ("ambiguous_qualifier", "distinct_vehicle_qualifier"))

    def test_the_audited_set_is_exactly_the_flutter_vs_tooling_gap_reported_by_the_matching_audit(self):
        gap = FAMILY["summary"]["NOT_PORTED_qualifier_quarantine"]
        self.assertEqual(S["1_total_quarantined_rows"], sum(gap["rows_kept_by_strict_but_not_accepted_by_tooling_by_tooling_status"].values()))
        self.assertEqual(S["2_affected_models"], gap["models_affected"])

    def test_the_experiment_is_clean(self):
        self.assertEqual(S["models_changed_outside_the_316 (must be 0)"], [])
        self.assertEqual(S["dart_dump_parity_failures (must be 0)"], [])
        self.assertEqual(S["rows_shared_by_more_than_one_catalog_model"], 0)

    def test_runtime_impact_is_measured_for_every_affected_model(self):
        self.assertEqual(len(AUDIT["models"]), S["2_affected_models"])
        self.assertEqual(sum(1 for m in AUDIT["models"] if m["changed"]["engines"]), S["7_models_whose_engines_change"])
        self.assertEqual(sum(1 for m in AUDIT["models"] if m["changed"]["cylinders"]), S["8_models_whose_cylinders_change"])
        self.assertEqual(sum(1 for m in AUDIT["models"] if m["changed"]["other_fields_any"]), S["9_models_whose_other_fields_change"])
        self.assertEqual(sum(1 for m in AUDIT["models"] if m["current"]["has_coverage"] and not m["strict"]["has_coverage"]),
                         S["10_models_that_would_lose_all_baseline_coverage"])

    def test_report_sections_exist(self):
        self.assertGreaterEqual(len(AUDIT["top_30_high_risk_models"]), 30)
        self.assertTrue(AUDIT["groups_by_qualifier_phrase"] and AUDIT["groups_by_head_token"])
        names = {(m["brand"], m["model"]) for m in AUDIT["important_models"]}
        for k in [("Toyota", "Land Cruiser"), ("Toyota", "Land Cruiser Prado"), ("Toyota", "Corolla"), ("BMW", "X5"), ("Lexus", "RX"),
                  ("Ford", "Mustang"), ("Volkswagen", "Golf R"), ("Nissan", "Patrol")]:
            self.assertIn(k, names)
        self.assertTrue(AUDIT["recommendation"]["decision"])

    def test_selective_exclusion_is_a_strict_subset_with_known_models(self):
        sel = AUDIT["proposed_selective_exclusion"]
        self.assertEqual(sel["rows_removed"], S["4_OTHER_MODEL_OR_SIBLING"] + S["6_MALFORMED_OR_NOISY"])
        self.assertLess(sel["rows_removed"], S["1_total_quarantined_rows"])
        # nothing outside the audited models can change
        affected = {(m["brand"], m["model"]) for m in AUDIT["models"]}
        for m in sel["changed_models"]:
            self.assertIn((m["brand"], m["model"]), affected)


if __name__ == "__main__":
    unittest.main()
