"""Runtime overlay asset (assets/car_iqcars_overlay.json) export guards.

The asset is the ONLY IQ Cars data the app ships. It must be (a) exactly what the exporter derives from the reviewed candidate,
(b) free of every excluded/held/contaminated value, and (c) free of research metadata.
"""
import copy
import json
import re
import sys
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(HERE))
import export_runtime_overlay as E  # noqa: E402

CAND = json.loads(E.CANDIDATE.read_text(encoding="utf-8"))
EXC = json.loads(E.EXCLUSIONS.read_text(encoding="utf-8"))
ASSET = json.loads(E.OUT.read_text(encoding="utf-8"))
MODELS = {(b, m): v for b, ms in ASSET.items() if not b.startswith("_") for m, v in ms.items()}


class AssetMatchesCandidate(unittest.TestCase):
    def test_asset_is_up_to_date(self):
        self.assertEqual(E.OUT.read_bytes().replace(b"\r\n", b"\n"), E.render(E.build(CAND, EXC)))

    def test_meta_counts(self):
        self.assertEqual(ASSET["_meta"]["models"], len(MODELS))
        self.assertEqual(ASSET["_meta"]["source_sha256"], E._sha256(E.CANDIDATE))

    def test_deterministic(self):
        self.assertEqual(E.render(E.build(CAND, EXC)), E.render(E.build(copy.deepcopy(CAND), copy.deepcopy(EXC))))

    def test_compact(self):
        self.assertLess(E.OUT.stat().st_size, 150_000)


class AssetContent(unittest.TestCase):
    def test_only_expected_keys(self):
        for key, v in MODELS.items():
            self.assertLessEqual(set(v), {"trims_add", "engine_variants_add", "cylinders"}, key)
            self.assertTrue(v, key)

    def test_format_version(self):
        self.assertEqual(ASSET["_meta"]["format"], 3)

    def test_no_research_metadata(self):
        text = E.OUT.read_text(encoding="utf-8")
        for banned in ("http", "iq_", "raw", "evidence", "possible_duplicate", "comparison", "excluded", "ambiguous"):
            self.assertNotIn(banned, text.lower().replace("source_sha256", "").replace('"source"', ""), banned)

    def test_engine_variants_wellformed_sorted_and_unique(self):
        for key, v in MODELS.items():
            toks = v.get("engine_variants_add", [])
            self.assertTrue(all(E.VARIANT_RE.match(t) for t in toks), key)
            self.assertEqual(toks, sorted(set(toks), key=E._variant_key), key)

    def test_qualifier_is_preserved_not_collapsed(self):
        # Prado: IQ has 2.4T. The tooling comparison is displacement-only (CarNet already has 2.4), so the candidate lists
        # the variant as informational only -- the runtime asset must still carry it with its qualifier.
        prado = MODELS[("Toyota", "Land Cruiser Prado")]["engine_variants_add"]
        self.assertIn("2.4T", prado)
        self.assertNotIn("2.4", prado)
        self.assertIn("2.8TD", prado)
        # every candidate variant (added or informational) reaches the asset with its qualifier
        by_cand = {(m["brand"], m["model"]): m for m in CAND["models"]}
        dflt = {(e["brand"], e["model"]) for e in EXC["unrestricted_default_engine_lists"]}
        for key, v in MODELS.items():
            if key in dflt:
                continue
            c = by_cand[key]
            if c.get("cylinders_only"):
                self.assertNotIn("engine_variants_add", v, key)  # cylinders-only entries carry nothing else
                continue
            rows = (c.get("engine_variants") or []) + (c.get("informational_engine_variants_on_sizes_carnet_already_has") or [])
            want = {r["size"][:-1] + (r.get("qualifier") or "") for r in rows}
            self.assertEqual(set(v.get("engine_variants_add", [])), want, key)

    def test_4_5_and_4_5td_both_survive(self):
        lc = MODELS[("Toyota", "Land Cruiser")]["engine_variants_add"]
        self.assertIn("4.5", lc)
        self.assertIn("4.5TD", lc)

    def test_cylinders_ascending_ints(self):
        for key, v in MODELS.items():
            c = v.get("cylinders", [])
            self.assertTrue(all(isinstance(x, int) for x in c), key)
            self.assertEqual(c, sorted(set(c)), key)

    def test_exclusions_stay_out(self):
        blocked = set()
        for sec in ("ambiguous_iq_models", "unmatched_iq_models", "explicitly_excluded_models"):
            blocked |= {(e["iq_brand"], e["iq_model"]) for e in EXC[sec]}
        self.assertFalse(blocked & set(MODELS))
        self.assertNotIn(("Toyota", "Land Cruiser FJ"), MODELS)

    def test_held_trims_stay_out(self):
        held = {(e["brand"], e["model"], e["iq_trim"]) for e in EXC["trims_held_for_review"]}
        self.assertEqual(len(held), 98)
        for (b, m, t) in held:
            self.assertNotIn(t, MODELS.get((b, m), {}).get("trims_add", []), (b, m, t))

    def test_default_lists_not_leaked(self):
        for sec, field in (("unrestricted_default_engine_lists", "engine_variants_add"),
                           ("unrestricted_default_cylinder_lists", "cylinders")):
            for e in EXC[sec]:
                self.assertEqual(MODELS.get((e["brand"], e["model"]), {}).get(field, []), [], e)

    def test_land_cruiser_and_prado_are_separate_entries(self):
        # Each model keeps its own independent entry; the exporter never merges one into the other.
        self.assertIn(("Toyota", "Land Cruiser"), MODELS)
        by_cand = {(m["brand"], m["model"]): m for m in CAND["models"]}
        for key in (("Toyota", "Land Cruiser"), ("Toyota", "Land Cruiser Prado")):
            if key in MODELS:
                self.assertEqual(MODELS[key].get("trims_add", []), by_cand[key]["trims_add"], key)

    def test_everest(self):
        v = MODELS[("Ford", "Everest")]
        self.assertEqual(v["trims_add"], ["Titanium", "Trend", "Ambiente"])
        self.assertEqual(v["engine_variants_add"], ["2.0TD", "2.2TD", "2.3T", "2.5", "2.7T", "3.0TD", "3.2TD"])


class FullCylinderSets(unittest.TestCase):
    """Runtime `cylinders` is the FULL approved IQ set (never a diff against the tooling's CarNet baseline)."""

    def test_runtime_cylinders_equal_candidate_full_set(self):
        by_cand = {(m["brand"], m["model"]): m for m in CAND["models"]}
        for key, c in by_cand.items():
            self.assertEqual(MODELS.get(key, {}).get("cylinders", []), sorted(c["cylinders"]), key)
            self.assertLessEqual(set(c["cylinders_add"]), set(c["cylinders"]), key)

    def test_no_cylinders_add_in_runtime_asset(self):
        self.assertNotIn("cylinders_add", E.OUT.read_text(encoding="utf-8"))

    def test_bmw_series_carry_full_sets(self):
        self.assertEqual(MODELS[("BMW", "4-Series")]["cylinders"], [4, 6])
        self.assertEqual(MODELS[("BMW", "5-Series")]["cylinders"], [4, 6, 8, 10])  # was the diff [10]
        self.assertEqual(MODELS[("BMW", "6-Series")]["cylinders"], [6, 8, 10])

    def test_rare_explicit_counts_preserved(self):
        self.assertEqual(MODELS[("Bugatti", "Veyron")]["cylinders"], [16])
        self.assertEqual(MODELS[("Fiat", "500")]["cylinders"], [2, 4])
        self.assertEqual(MODELS[("Polaris", "Ranger 570")]["cylinders"], [1])

    def test_geely_cityray_quarantine(self):
        q = [(e["brand"], e["model"], e["value"]) for e in EXC["quarantined_cylinder_values"]]
        self.assertEqual(q, [("Geely", "Cityray", 3)])
        self.assertNotIn(3, MODELS.get(("Geely", "Cityray"), {}).get("cylinders", []))
        # quarantining the cylinder must not drop the model's engine data (format-2 scope unchanged)
        self.assertEqual(MODELS[("Geely", "Cityray")], {"engine_variants_add": ["1.5T"]})
        by_cand = {(m["brand"], m["model"]): m for m in CAND["models"]}
        if ("Geely", "Cityray") in by_cand:
            self.assertNotIn(3, by_cand[("Geely", "Cityray")]["cylinders"])
            self.assertNotIn(3, by_cand[("Geely", "Cityray")]["cylinders_add"])

    def test_raw_iq_response_keeps_the_quarantined_value(self):
        raw = json.loads((HERE / "generated" / "iqcars_model_options.json").read_text(encoding="utf-8"))
        rec = next(m for m in raw["models"] if m["brand"] == "Geely" and m["model"] == "Cityray")
        self.assertIn(3, [r["count"] for r in rec["cylinder_records"] if r["parsed"]])

    def test_exporter_rejects_quarantined_value(self):
        c = copy.deepcopy(CAND)
        c["models"].append({"brand": "Geely", "model": "Cityray", "trims_add": ["X"], "engine_sizes_add": [], "cylinders_add": [3], "cylinders": [3]})
        for m in list(c["models"][:-1]):
            if (m["brand"], m["model"]) == ("Geely", "Cityray"):
                c["models"].remove(m)
        with self.assertRaises(SystemExit):
            E.build(c, EXC)

    def test_exporter_rejects_add_not_subset_of_full_set(self):
        c = copy.deepcopy(CAND)
        c["models"].append({"brand": "Zed", "model": "Zeta", "trims_add": [], "engine_sizes_add": [], "cylinders_add": [10], "cylinders": []})
        with self.assertRaises(SystemExit):
            E.build(c, EXC)


class ExporterGuards(unittest.TestCase):
    def _cand_with(self, **fields):
        c = copy.deepcopy(CAND)
        c["models"].append({"brand": "Zed", "model": "Zeta", "trims_add": [], "engine_sizes_add": [], "cylinders_add": [], "cylinders": [], **fields})
        return c

    def test_rejects_qualifier_engine_values(self):
        with self.assertRaises(SystemExit):
            E.build(self._cand_with(engine_sizes_add=["2.0L TD"]), EXC)

    def test_rejects_excluded_model(self):
        e = EXC["explicitly_excluded_models"][0]
        c = copy.deepcopy(CAND)
        c["models"].append({"brand": e["iq_brand"], "model": e["iq_model"], "trims_add": ["X"], "engine_sizes_add": [], "cylinders_add": [], "cylinders": []})
        with self.assertRaises(SystemExit):
            E.build(c, EXC)

    def test_rejects_long_default_like_lists(self):
        with self.assertRaises(SystemExit):
            E.build(self._cand_with(engine_sizes_add=[f"{i // 10}.{i % 10}L" for i in range(5, 40)]), EXC)

    def test_variant_qualifier_kept_and_equal_sizes_not_merged(self):
        v = [
            {"size": "2.4L", "qualifier": "T", "raw_values": ["2.4T"]},
            {"size": "2.4L", "qualifier": "", "raw_values": ["2.4"]},
            {"size": "2.4L", "qualifier": "D", "raw_values": ["2.4D"]},
        ]
        doc = E.build(self._cand_with(engine_variants=v, engine_sizes_add=["2.4L"]), EXC)
        self.assertEqual(doc["Zed"]["Zeta"]["engine_variants_add"], ["2.4", "2.4D", "2.4T"])

    def test_informational_variants_on_existing_sizes_are_exported(self):
        info = [{"size": "2.4L", "qualifier": "T", "raw_values": ["2.4T"]}]
        doc = E.build(self._cand_with(informational_engine_variants_on_sizes_carnet_already_has=info), EXC)
        self.assertEqual(doc["Zed"]["Zeta"]["engine_variants_add"], ["2.4T"])

    def test_rejects_unsupported_qualifier(self):
        v = [{"size": "2.4L", "qualifier": "HYBRIDX", "raw_values": ["2.4HYBRIDX"]}]
        with self.assertRaises(SystemExit):
            E.build(self._cand_with(engine_variants=v), EXC)

    def test_default_engine_list_models_never_export_engines(self):
        e = EXC["unrestricted_default_engine_lists"][0]
        c = copy.deepcopy(CAND)
        for m in c["models"]:
            if (m["brand"], m["model"]) == (e["brand"], e["model"]):
                m["engine_variants"] = [{"size": "2.4L", "qualifier": "T", "raw_values": ["2.4T"]}]
        with self.assertRaises(SystemExit):
            E.build(c, EXC)

    def test_rejects_too_many_cylinders(self):
        with self.assertRaises(SystemExit):
            E.build(self._cand_with(cylinders=[1, 2, 3, 4, 5, 6, 8]), EXC)

    def test_rejects_held_trim(self):
        h = EXC["trims_held_for_review"][0]
        c = copy.deepcopy(CAND)
        c["models"].append({"brand": h["brand"], "model": h["model"], "trims_add": [h["iq_trim"]], "engine_sizes_add": [], "cylinders_add": [], "cylinders": []})
        with self.assertRaises(SystemExit):
            E.build(c, EXC)


if __name__ == "__main__":
    unittest.main()
