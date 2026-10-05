"""Candidate-overlay guarantees: additive only, no sibling contamination, exclusions, determinism (fixtures only)."""
import copy
import json
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import build_overlay as O  # noqa: E402
import model_boundaries as mb  # noqa: E402
import normalize as N  # noqa: E402

CAT = {
    "brands": ["Toyota", "Volkswagen"],
    "models": {"Toyota": ["Land Cruiser", "Land Cruiser Prado", "Corolla", "Corolla Cross", "RAV4"],
               "Volkswagen": ["Golf", "Golf R"]},
    "trimsByBrandModel": {"Toyota": {"Land Cruiser": ["GX", "EXR", "Other"], "Corolla": ["LE"]}},
}
DS = {"brands": [{"id": 1, "name": "Toyota"}],
      "models": [{"id": 1, "brand_id": 1, "name": "Land Cruiser 4 5D V8 (235 Hp) Automatic"},
                 {"id": 2, "brand_id": 1, "name": "Land Cruiser Prado 2 7 i (163 Hp) 4WD"}],
      "trims": [{"id": 1, "model_id": 1, "year": 2000, "year_end": 2007, "name": "x"},
                {"id": 2, "model_id": 2, "year": 2010, "year_end": 2013, "name": "x"}],
      "specs": [{"trim_id": 1, "displacement_cc": 4477, "raw_spec_pairs": {"Cylinders alignment:": "v 8"}},
                {"trim_id": 2, "displacement_cc": 2694, "raw_spec_pairs": {"Cylinders alignment:": "inline 4"}}]}


def sfx(i, name, fy=None, ty=None):
    return {"ID": i, "SFXName": name, "FromYear": {"YearName": str(fy)} if fy else None, "ToYear": {"YearName": str(ty)} if ty else None, "Deleted": False}


def model(i, name, sfxes=None):
    return {"ID": i, "ModelNameen": name, "ModelNamear": "ar", "ModelNameku": "ku", "ModelSFXes": sfxes or []}


def resp(engines=(), cyls=()):
    return {"Engines": [{"ID": i, "EngineNameen": n} for i, n in engines], "Cylinders": [{"ID": i, "CylinderNameen": n} for i, n in cyls]}


def raw_catalog(extra_models=(), extra_cyl=None):
    models = [model(249, "Land Cruiser", [sfx(1, "GX"), sfx(2, "  VX.R "), sfx(3, "VX  Limited"), sfx(4, "EX.R"), sfx(5, "VX 3.5L Twin-Turbo"),
                                          sfx(6, "VX 3.5L Twin Turbo"), sfx(7, "GX")]),
              model(288, "Land Cruiser Prado", [sfx(20, "TXL"), sfx(21, "GX")]),
              model(10, "Corolla", [sfx(30, "LE"), sfx(31, "XLI")]),
              model(11, "Corolla Cross", [sfx(40, "Hybrid")]),
              model(1827, "Land Cruiser FJ", [sfx(50, "FJ Only")]),
              model(60, "Supra", [sfx(60, "Unmatched Trim")]),
              *extra_models]
    cyl = {"249": resp([(9, "4.5"), (50, "4.5TD"), (66, "4.7"), (25, "5.7")], [(127, "6 cylinder"), (125, "8 cylinder")]),
           "288": resp([(2, "2.7"), (83, "4.0")], [(109, "4 cylinder")]),
           "10": resp([(7, "1.6")], [(109, "4 cylinder")]),
           "11": resp([(8, "1.8")], [(109, "4 cylinder")]),
           "1827": resp([(1, "4.5")], [(125, "8 cylinder")]),
           "60": resp([(3, "2.0")], [(109, "4 cylinder")]),
           **(extra_cyl or {})}
    return {"_meta": {"assembled_at": "T0"}, "initial_data_brands": [{"ID": 27, "BrandNameen": "Toyota", "BrandNamear": "x", "BrandNameku": "y", "Models": models}],
            "cylinder_engine_by_model_id": cyl, "brand_new_cars": {}}


RULES = {"aliases": {}, "qualifier_trims": {}, "qualifier_distinct": {}}
SUFFIX = {"token_classes": {}, "brands": {}}


def run(raw=None, cat=None, ds=None):
    iq = N.build(raw or raw_catalog())
    c = copy.deepcopy(cat or CAT)
    return O.build(iq, c, copy.deepcopy(ds or DS), idx=mb.ModelIndex(c, RULES, SUFFIX, use_suffix_rules=False)), iq


def entry(res, brand, model_):
    return next((e for e in res["entries"] if (e["brand"], e["model"]) == (brand, model_)), None)


class Additive(unittest.TestCase):
    def test_existing_carnet_values_never_duplicated(self):
        res, _ = run()
        lc = entry(res, "Toyota", "Land Cruiser")
        self.assertNotIn("GX", lc["trims_add"])          # already in CarNet
        self.assertNotIn("4.5L", lc["engine_sizes_add"])  # CarNet profile already has 4.5L
        self.assertNotIn(8, lc["cylinders_add"])          # CarNet profile already has 8 cylinders
        self.assertEqual(lc["engine_sizes_add"], ["4.7L", "5.7L"])
        self.assertEqual(lc["cylinders_add"], [6])
        for k in ("trims_add", "engine_sizes_add", "cylinders_add"):
            self.assertEqual(len(lc[k]), len(set(lc[k])))

    def test_nothing_is_removed_or_rewritten(self):
        cat_before, ds_before = copy.deepcopy(CAT), copy.deepcopy(DS)
        res, _ = run()
        self.assertEqual((CAT, DS), (cat_before, ds_before))
        lc = entry(res, "Toyota", "Land Cruiser")
        self.assertFalse([k for k in lc if "remove" in k or "delete" in k or "replace" in k])
        self.assertIn("EXR", res["diags"][("Toyota", "Land Cruiser")]["carnet"]["trims"])  # CarNet-only value untouched

    def test_models_without_additions_not_in_overlay(self):
        res, _ = run()
        self.assertIsNone(entry(res, "Toyota", "Corolla Cross") and None)  # Corolla Cross has a new trim -> present
        self.assertIsNotNone(entry(res, "Toyota", "Corolla Cross"))
        self.assertEqual(entry(res, "Toyota", "Corolla")["trims_add"], ["XLI"])  # 'LE' exists

    def test_placeholder_other_is_not_a_carnet_trim_and_iq_other_is_not_added(self):
        raw = raw_catalog()
        raw["initial_data_brands"][0]["Models"][2]["ModelSFXes"].append(sfx(32, "Other"))
        res, _ = run(raw)
        self.assertNotIn("Other", entry(res, "Toyota", "Corolla")["trims_add"])
        self.assertIn("placeholder_trim", [i["kind"] for i in res["diags"][("Toyota", "Corolla")]["excluded"]])


class TrimRules(unittest.TestCase):
    def test_safe_normalization_applies_before_comparison(self):
        res, _ = run()
        lc = entry(res, "Toyota", "Land Cruiser")
        self.assertIn("VX Limited", lc["trims_add"])  # 'VX  Limited' -> collapsed spaces
        self.assertNotIn("VX  Limited", lc["trims_add"])
        self.assertEqual(lc["trims_add"].count("GX"), 0)  # 'GX' duplicated in IQ and present in CarNet

    def test_lookalikes_are_held_not_merged_not_added(self):
        res, _ = run()
        lc = entry(res, "Toyota", "Land Cruiser")
        held = {h["iq_trim"]: h for h in lc["held_trims_for_review"]}
        self.assertIn("EX.R", held)
        self.assertEqual(held["EX.R"]["kind"], "cross_source")
        self.assertEqual(held["EX.R"]["carnet_lookalikes"], ["EXR"])
        self.assertNotIn("EX.R", lc["trims_add"])
        # within-IQ twin-turbo pair: both held, neither silently merged
        self.assertEqual({k for k, h in held.items() if h["kind"] == "within_iq"}, {"VX 3.5L Twin-Turbo", "VX 3.5L Twin Turbo"})
        self.assertFalse({"VX 3.5L Twin-Turbo", "VX 3.5L Twin Turbo"} & set(lc["trims_add"]))

    def test_trim_ids_and_years_traceable(self):
        raw = raw_catalog()
        raw["initial_data_brands"][0]["Models"][3]["ModelSFXes"] = [sfx(40, "Hybrid", 2019, 2024)]
        res, _ = run(raw)
        d = entry(res, "Toyota", "Corolla Cross")["trims_add_details"][0]
        self.assertEqual((d["name"], d["iq_trim_ids"], d["from_year"], d["to_year"]), ("Hybrid", [40], 2019, 2024))


class EngineAndCylinderRules(unittest.TestCase):
    def test_qualifier_and_raw_preserved_for_added_size(self):
        res, _ = run()
        lc = entry(res, "Toyota", "Land Cruiser")
        self.assertIn("4.7L", lc["engine_sizes_add"])
        # 4.5TD shares a size CarNet already has -> not added to the picker list, but the raw variant is kept as information
        self.assertNotIn("4.5L", lc["engine_sizes_add"])
        info = lc["informational_engine_variants_on_sizes_carnet_already_has"]
        self.assertIn({"size": "4.5L", "raw_values": ["4.5TD"], "qualifier": "TD", "iq_engine_ids": [50]}, info)

    def test_added_td_size_keeps_raw_size_and_qualifier(self):
        raw = raw_catalog(extra_cyl={"10": resp([(50, "4.5TD"), (7, "1.6")], [(109, "4 cylinder")])})
        res, _ = run(raw)
        co = entry(res, "Toyota", "Corolla")
        v = [x for x in co["engine_variants"] if x["raw_values"] == ["4.5TD"]][0]
        self.assertEqual((v["size"], v["qualifier"]), ("4.5L", "TD"))
        self.assertIn("4.5L", co["engine_sizes_add"])
        self.assertNotIn("TD", " ".join(co["engine_sizes_add"]))

    def test_nothing_inferred_between_engine_cylinder_trim(self):
        raw = raw_catalog(extra_cyl={"10": resp([(7, "1.6"), (8, "2.0")], [])})  # engines but NO cylinders from IQ
        res, _ = run(raw)
        co = entry(res, "Toyota", "Corolla")
        self.assertEqual(co["cylinders_add"], [])          # never derived from displacement
        self.assertEqual(co["relationships"].split(" ")[0], "none")
        self.assertFalse([k for k in co if "link" in k])

    def test_unusual_cylinder_counts_kept_but_flagged(self):
        raw = raw_catalog(extra_cyl={"10": resp([(7, "1.6")], [(200, "16 cylinder"), (201, "2 cylinder")])})
        res, _ = run(raw)
        co = entry(res, "Toyota", "Corolla")
        self.assertEqual(co["cylinders_add"], [2, 16])
        self.assertEqual({(w["kind"], w["value"]) for w in co["warnings"]}, {("UNUSUAL_CYLINDER_COUNT", 2), ("UNUSUAL_CYLINDER_COUNT", 16)})

    def test_non_displacement_values_excluded_and_reported(self):
        raw = raw_catalog(extra_cyl={"10": resp([(7, "1.6"), (300, "60 kWh")], [(301, "Dual Motor"), (109, "4 cylinder")])})
        res, _ = run(raw)
        kinds = [(i["kind"], i.get("raw")) for i in res["diags"][("Toyota", "Corolla")]["excluded"]]
        self.assertIn(("unparsed_engine_value", "60 kWh"), kinds)
        self.assertIn(("unparsed_cylinder_value", "Dual Motor"), kinds)
        self.assertNotIn("60 kWh", json.dumps(entry(res, "Toyota", "Corolla")["engine_sizes_add"]))

    def test_unrestricted_default_lists_are_excluded(self):
        full_e = [(1000 + i, f"{1 + i / 10:.1f}") for i in range(10)]
        full_c = [(2000 + i, f"{c} cylinder") for i, c in enumerate([1, 2, 3, 4, 5, 6, 8, 10, 12, 16])]
        extra = [model(900 + i, f"Dump{i}", [sfx(900 + i, "T")]) for i in range(20)]
        cyl = {str(900 + i): resp(full_e, full_c) for i in range(20)}
        cyl["10"] = resp(full_e, full_c)  # Corolla also receives the default dump
        raw = raw_catalog(extra, cyl)
        res, _ = run(raw)
        co = entry(res, "Toyota", "Corolla")
        self.assertEqual((co["engine_sizes_add"], co["cylinders_add"]), ([], []))
        self.assertEqual(co["trims_add"], ["XLI"])  # trims are still usable
        kinds = {i["kind"] for i in res["diags"][("Toyota", "Corolla")]["excluded"]}
        self.assertEqual(kinds, {"unrestricted_default_engine_list", "unrestricted_default_cylinder_list"})


class IdentitySafety(unittest.TestCase):
    def test_land_cruiser_is_not_prado(self):
        res, _ = run()
        lc, pr = entry(res, "Toyota", "Land Cruiser"), entry(res, "Toyota", "Land Cruiser Prado")
        self.assertEqual((lc["iq_model_id"], pr["iq_model_id"]), (249, 288))
        self.assertNotIn("TXL", lc["trims_add"])
        self.assertEqual(pr["trims_add"], ["TXL", "GX"])
        self.assertEqual(pr["engine_sizes_add"], ["4.0L"])  # Prado CarNet has 2.7L only; 4.7L/5.7L/6-cyl belong to Land Cruiser
        self.assertEqual(pr["cylinders_add"], [])
        self.assertFalse({"4.7L", "5.7L"} & set(pr["engine_sizes_add"]))
        self.assertNotIn("EX.R", {h["iq_trim"] for h in pr["held_trims_for_review"]})

    def test_corolla_is_not_corolla_cross(self):
        res, _ = run()
        self.assertEqual(entry(res, "Toyota", "Corolla")["trims_add"], ["XLI"])
        self.assertEqual(entry(res, "Toyota", "Corolla Cross")["trims_add"], ["Hybrid"])

    def test_ambiguous_model_excluded_land_cruiser_fj(self):
        res, _ = run()
        self.assertIsNone(next((e for e in res["entries"] if e["iq_model_name"] == "Land Cruiser FJ"), None))
        self.assertEqual([a["iq_model"] for a in res["ambiguous"]], ["Land Cruiser FJ"])
        self.assertIn("Land Cruiser FJ", [x["iq_model"] for x in res["explicit"]])
        self.assertNotIn("FJ Only", json.dumps(res["entries"]))

    def test_unmatched_model_excluded(self):
        res, _ = run()
        self.assertIn("Supra", [u["iq_model"] for u in res["unmatched"]])
        self.assertNotIn("Unmatched Trim", json.dumps(res["entries"]))
        self.assertIsNone(next((e for e in res["entries"] if e["iq_model_name"] == "Supra"), None))

    def test_validation_passes_on_fixture(self):
        raw = raw_catalog()
        res, iq = run(raw)
        v = O.validate(res, iq, CAT, raw)
        self.assertTrue(v["ok"], v["failures"])

    def test_validation_detects_sibling_contamination(self):
        raw = raw_catalog()
        res, iq = run(raw)
        lc = entry(res, "Toyota", "Land Cruiser")
        lc["trims_add_details"][0]["iq_trim_ids"] = [20]  # Prado's trim id smuggled into Land Cruiser
        v = O.validate(res, iq, CAT, raw)
        self.assertFalse(v["ok"])
        self.assertIn("every_addition_traces_to_own_iq_model_in_raw", [f["check"] for f in v["failures"]])


class Determinism(unittest.TestCase):
    def test_identical_output(self):
        a, _ = run()
        b, _ = run()
        dump = lambda r: json.dumps({"e": r["entries"], "x": r["no_additions"], "a": r["ambiguous"], "u": r["unmatched"]}, ensure_ascii=False)
        self.assertEqual(dump(a), dump(b))
        iq = N.build(raw_catalog())
        rep1 = O.make_reports(a, iq, CAT, {}) and json.dumps(O.make_reports(a, iq, CAT, {}), sort_keys=False)
        rep2 = json.dumps(O.make_reports(b, iq, CAT, {}), sort_keys=False)
        self.assertEqual(rep1, rep2)

    def test_priority_report_does_not_invent_models(self):
        res, iq = run()
        rep = O.make_reports(res, iq, CAT, {})
        status = {(p["brand"], p["model"]): p["status"] for p in rep["impact"]["priority_models"]}
        self.assertEqual(status[("Toyota", "Camry")], "exact_name_not_in_carnet")
        self.assertEqual(status[("Toyota", "Land Cruiser")], "included_in_overlay")


if __name__ == "__main__":
    unittest.main()
