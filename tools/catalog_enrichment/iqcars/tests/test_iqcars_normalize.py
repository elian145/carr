"""Offline tests for iqcars/normalize.py and extract_iqcars.assemble.
Run: python -m pytest tools/catalog_enrichment/iqcars/tests -q"""
import copy
import json
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import extract_iqcars as X  # noqa: E402
import normalize as N  # noqa: E402


class EngineSize(unittest.TestCase):
    def test_same_displacement_same_display(self):
        for raw in ("2300 cc", "2300cc", "2.3", "2.3L", "2.3 L", "2,3", "2300"):
            with self.subTest(raw=raw):
                self.assertEqual(N.parse_engine(raw)["display"], "2.3L")

    def test_cc_rounds_like_marketing_size(self):
        self.assertEqual(N.parse_engine("1998 cc")["display"], "2.0L")
        self.assertEqual(N.parse_engine("1,600 cc")["display"], "1.6L")
        self.assertEqual(N.parse_engine("2494 cc")["display"], "2.5L")

    def test_qualifiers_preserved_not_interpreted(self):
        for raw, disp, q in (("4.2TD", "4.2L", "TD"), ("4.5TD", "4.5L", "TD"), ("3.5T", "3.5L", "T"), ("2.0 Turbo", "2.0L", "TURBO"),
                             ("4.5", "4.5L", ""), ("1.6 hev", "1.6L", "HEV")):
            with self.subTest(raw=raw):
                p = N.parse_engine(raw)
                self.assertEqual((p["display"], p["qualifier"]), (disp, q))
                self.assertEqual(p["raw"], raw)

    def test_same_size_different_qualifier_stays_distinct_variants(self):
        out = N.normalize_model_options({"Engines": [{"ID": 9, "EngineNameen": "4.5"}, {"ID": 50, "EngineNameen": "4.5TD"},
                                                     {"ID": 51, "EngineNameen": "4.5 TD"}], "Cylinders": []})
        self.assertEqual(out["engine_sizes"], ["4.5L"])  # union by size
        self.assertEqual([(v["display"], v["qualifier"]) for v in out["engine_variants"]], [("4.5L", ""), ("4.5L", "TD")])
        td = next(v for v in out["engine_variants"] if v["qualifier"] == "TD")
        self.assertEqual(td["raw_values"], ["4.5TD", "4.5 TD"])  # raw preserved, both IDs kept
        self.assertEqual(td["engine_ids"], [50, 51])
        self.assertEqual(len(out["engine_records"]), 3)  # per-ID records never merged

    def test_unparseable_is_kept_not_guessed(self):
        for raw in ("75 kWh", "Electric", "", None, "250"):
            with self.subTest(raw=raw):
                self.assertFalse(N.parse_engine(raw)["parsed"])
        out = N.normalize_model_options({"Engines": [{"ID": 1, "EngineNameen": "Electric"}], "Cylinders": []})
        self.assertEqual(out["engine_sizes"], [])
        self.assertEqual(out["engine_records"][0]["raw"], "Electric")
        self.assertFalse(out["engine_records"][0]["parsed"])


class Cylinders(unittest.TestCase):
    def test_parse(self):
        self.assertEqual(N.parse_cylinder("6 cylinder")["count"], 6)
        self.assertEqual(N.parse_cylinder("12 Cylinders")["count"], 12)
        self.assertFalse(N.parse_cylinder("Electric")["parsed"])

    def test_never_inferred_from_engine_size(self):
        out = N.normalize_model_options({"Engines": [{"ID": 1, "EngineNameen": "4.0"}, {"ID": 2, "EngineNameen": "1.0"}], "Cylinders": []})
        self.assertEqual(out["engine_sizes"], ["1.0L", "4.0L"])
        self.assertEqual(out["cylinders"], [])
        self.assertEqual(out["cylinder_records"], [])


class TrimSafeNormalization(unittest.TestCase):
    def S(self, i, name, **kw):
        return {"ID": i, "SFXName": name, "FromYear": None, "ToYear": None, "Deleted": False, **kw}

    def test_whitespace_and_unicode_only(self):
        recs, union, st, _ = N.normalize_trims([self.S(1, "VX.R "), self.S(2, " GR HEV"), self.S(3, "GX.R  Full   Option "),
                                                self.S(4, "G\u00a0X"), self.S(5, "\uff36\uff38"), self.S(6, "A\u200bB")])
        self.assertEqual(union, ["VX.R", "GR HEV", "GX.R Full Option", "G X", "VX", "AB"])
        self.assertEqual([r["trim_name_raw"] for r in recs][:3], ["VX.R ", " GR HEV", "GX.R  Full   Option "])  # raw kept
        self.assertEqual(st["name_changed_by_normalization"], 6)

    def test_case_and_punctuation_never_normalized_or_merged(self):
        _, union, _, _ = N.normalize_trims([self.S(1, "VX 3.5L Twin-Turbo"), self.S(2, "VX 3.5L Twin Turbo"), self.S(3, "EX.R"),
                                            self.S(4, "EXR"), self.S(5, "Mid Grade"), self.S(6, "Mid grade"), self.S(7, "GX"), self.S(8, "GXR")])
        self.assertEqual(len(union), 8)

    def test_exact_duplicates_removed_but_all_ids_kept_in_records(self):
        recs, union, st, _ = N.normalize_trims([self.S(1, "VX"), self.S(2, "VX "), self.S(3, "VX", FromYear={"YearName": "1980"})])
        self.assertEqual(union, ["VX"])
        self.assertEqual([r["trim_id"] for r in recs], [1, 2, 3])
        self.assertEqual(st["exact_duplicate_records_removed"], 2)
        self.assertEqual(recs[2]["from_year"], 1980)

    def test_possible_duplicates_flagged_not_merged(self):
        _, union, _, pos = N.normalize_trims([self.S(1, "VX 3.5L Twin-Turbo"), self.S(2, "VX 3.5L Twin Turbo"), self.S(3, "EX.R"),
                                              self.S(4, "EXR"), self.S(5, "GX"), self.S(6, "Mid Grade"), self.S(7, "Mid grade")])
        got = {tuple(sorted(p["names"])) for p in pos}
        self.assertEqual(got, {("VX 3.5L Twin Turbo", "VX 3.5L Twin-Turbo"), ("EX.R", "EXR"), ("Mid Grade", "Mid grade")})
        self.assertTrue(all(p["status"] == "POSSIBLE_DUPLICATES" for p in pos))
        self.assertEqual(len(union), 7)

    def test_deleted_and_empty_kept_in_records_excluded_from_union(self):
        recs, union, st, _ = N.normalize_trims([self.S(1, "A", Deleted=True), self.S(2, "  "), self.S(3, "B")])
        self.assertEqual(union, ["B"])
        self.assertEqual({r["trim_id"]: r.get("excluded_from_union") for r in recs}, {1: "deleted", 2: "empty_name", 3: None})
        self.assertEqual((st["deleted"], st["empty_name"]), (1, 1))

    def test_record_fields(self):
        recs, _, _, _ = N.normalize_trims([self.S(7, "GX ", FromYear={"YearName": "2008"}, ToYear={"YearName": "2021"})])
        self.assertEqual(recs[0], {"trim_id": 7, "trim_name_raw": "GX ", "trim_name_normalized": "GX", "from_year": 2008, "to_year": 2021})


def model(i, name, sfx=None):
    return {"ID": i, "ModelNameen": name, "ModelNamear": "ar-" + name, "ModelNameku": "ku-" + name, "ModelSFXes": sfx or []}


def catalog(models, cyl=None, bnc=None):
    return {"_meta": {"assembled_at": "T0"}, "initial_data_brands": [{"ID": 27, "BrandNameen": "Toyota", "BrandNamear": "x", "BrandNameku": "y", "Models": models}],
            "cylinder_engine_by_model_id": cyl or {}, "brand_new_cars": bnc or {}}


class ModelIdentity(unittest.TestCase):
    def test_siblings_stay_separate(self):
        cat = catalog([model(249, "Land Cruiser"), model(288, "Land Cruiser Prado"), model(1, "Corolla"), model(2, "Corolla Cross"),
                       model(3, "Yaris"), model(4, "Yaris Cross")],
                      cyl={"249": {"Engines": [{"ID": 1, "EngineNameen": "4.5"}], "Cylinders": [{"ID": 1, "CylinderNameen": "8 cylinder"}]},
                           "288": {"Engines": [{"ID": 2, "EngineNameen": "2.7"}], "Cylinders": [{"ID": 2, "CylinderNameen": "4 cylinder"}]}})
        out = N.build(cat)
        by = {r["model_id"]: r for r in out["models"]}
        self.assertEqual(len(by), 6)
        self.assertEqual((by[249]["engine_sizes"], by[249]["cylinders"]), (["4.5L"], [8]))
        self.assertEqual((by[288]["engine_sizes"], by[288]["cylinders"]), (["2.7L"], [4]))
        self.assertEqual(by[1]["engine_sizes"], [])  # Corolla untouched by Corolla Cross
        self.assertNotIn("model_key_collisions_not_merged", out["conflicts"])

    def test_key_collision_reported_not_merged(self):
        out = N.build(catalog([model(10, "3-Series"), model(11, "3 Series")]))
        self.assertEqual(len(out["models"]), 2)
        self.assertEqual(len(out["conflicts"]["model_key_collisions_not_merged"]), 1)

    def test_names_and_ids_preserved(self):
        r = N.build(catalog([model(5, "RAV4")]))["models"][0]
        self.assertEqual((r["brand_id"], r["model_id"], r["names"]["model"]["ar"], r["names"]["model"]["ku"]), (27, 5, "ar-RAV4", "ku-RAV4"))


class IndependentLists(unittest.TestCase):
    def test_used_car_lists_have_no_links(self):
        sfx = [{"ID": 1, "SFXName": "XLT", "Deleted": False}, {"ID": 2, "SFXName": "Sport", "Deleted": False}]
        cat = catalog([model(7, "M", sfx)], cyl={"7": {"Engines": [{"ID": 1, "EngineNameen": "2.3"}, {"ID": 2, "EngineNameen": "3.0TD"}],
                                                        "Cylinders": [{"ID": 1, "CylinderNameen": "4 cylinder"}, {"ID": 2, "CylinderNameen": "6 cylinder"}]}})
        r = N.build(cat)["models"][0]
        self.assertEqual(r["relationships"]["trim_engine_cylinder_links"], "none_provided")
        self.assertEqual((r["trims"], r["engine_sizes"], r["cylinders"]), (["XLT", "Sport"], ["2.3L", "3.0L"], [4, 6]))
        ids = {"trim_records": "trim_id", "engine_records": "engine_id", "cylinder_records": "cylinder_id"}
        for k, own in ids.items():
            for rec in r[k]:
                self.assertEqual({x for x in rec if x in ids.values()}, {own}, "a record references only its own ID kind")
        self.assertNotIn("exact_configurations", json.dumps(r))  # brand-new relationships never leak into the union

    def test_coverage_metrics(self):
        sfx = [{"ID": 1, "SFXName": "A", "Deleted": False}]
        cat = catalog([model(1, "All", sfx), model(2, "TrimOnly", sfx), model(3, "None")],
                      cyl={"1": {"Engines": [{"ID": 1, "EngineNameen": "2.0"}], "Cylinders": [{"ID": 1, "CylinderNameen": "4 cylinder"}]}, "3": {}})
        c = N.build(cat)["_meta"]["coverage"]
        self.assertEqual((c["models"], c["models_with_trims"], c["models_with_engines"], c["models_with_cylinders"], c["models_with_all_3"],
                          c["models_with_none"], c["models_without_cylinder_engine_response"]), (3, 2, 1, 1, 1, 1, 1))


class BrandNewExact(unittest.TestCase):
    def bnc(self):
        row = {"ID": 1424, "BrandNewCarId": 660, "BrandNewCar": {"ModelId": 249, "Year": {"YearName": "2027"},
                                                                 "Brand": {"ID": 27, "BrandNameen": "Toyota"}, "Model": {"ID": 249, "ModelNameen": "Land Cruiser"}},
               "ModelSFXId": 7091, "ModelSFX": {"SFXName": " Mid grade "}, "EngineId": 55, "Engine": {"EngineNameen": "2.7"},
               "CylinderId": 109, "Cylinder": {"CylinderNameen": "4 cylinder"}, "HorsePower": 164.0, "FuelId": 1}
        row2 = {**row, "ID": 1425, "ModelSFXId": 7092, "ModelSFX": {"SFXName": "Top"}, "EngineId": 69, "Engine": {"EngineNameen": "4.0"},
                "CylinderId": 127, "Cylinder": {"CylinderNameen": "6 cylinder"}}
        return {"entries_by_id": {"660": {"ID": 660, "ModelId": 249, "BrandId": 27, "Year": {"YearName": "2027"},
                                          "Brand": {"BrandNameen": "Toyota"}, "Model": {"ModelNameen": "Land Cruiser"}}},
                "sfxes_by_brand_new_car_id": {"660": [row, row2]}}

    def test_exact_rows_keep_trim_engine_cylinder_together(self):
        cat = catalog([model(249, "Land Cruiser", [{"ID": 1, "SFXName": "Mid grade", "Deleted": False}])],
                      cyl={"249": {"Engines": [{"ID": 69, "EngineNameen": "4.0"}], "Cylinders": [{"ID": 127, "CylinderNameen": "6 cylinder"}]}}, bnc=self.bnc())
        used = N.build(cat)
        out = N.build_brand_new(cat, used)
        c0, c1 = out["exact_configurations"]
        self.assertEqual((c0["trim"]["trim_name_normalized"], c0["engine"]["displacement_normalized"], c0["cylinder"]["count"]), ("Mid grade", "2.7L", 4))
        self.assertEqual((c1["trim"]["trim_name_normalized"], c1["engine"]["displacement_normalized"], c1["cylinder"]["count"]), ("Top", "4.0L", 6))
        self.assertEqual(c0["trim"]["trim_name_raw"], " Mid grade ")
        self.assertEqual(out["_meta"]["analysis"]["distinct_trim_engine_cylinder_triples"], 2)
        # the used-car union is NOT changed by the exact rows
        self.assertEqual(used["models"][0]["engine_sizes"], ["4.0L"])
        self.assertEqual(used["models"][0]["cylinders"], [6])

    def test_agreement_and_conflict_flagged_never_overridden(self):
        cat = catalog([model(249, "Land Cruiser", [{"ID": 1, "SFXName": "Mid grade", "Deleted": False}])],
                      cyl={"249": {"Engines": [{"ID": 69, "EngineNameen": "4.0"}], "Cylinders": [{"ID": 127, "CylinderNameen": "6 cylinder"}]}}, bnc=self.bnc())
        out = N.build_brand_new(cat, N.build(cat))
        a0, a1 = (c["comparison_with_used_car_union"] for c in out["exact_configurations"])
        self.assertEqual((a0["trim"], a0["engine"], a0["cylinder"]), ("AGREE_EXACT", "CONFLICT_NOT_IN_USED_LIST", "CONFLICT_NOT_IN_USED_LIST"))
        self.assertEqual((a1["trim"], a1["engine"], a1["cylinder"]), ("CONFLICT_NOT_IN_USED_LIST", "AGREE_EXACT_VARIANT", "AGREE_EXACT"))
        # row 1: engine + cylinder conflict; row 2: trim conflict  => 3 flagged, 3 agreements, nothing overridden
        self.assertEqual(out["_meta"]["analysis"]["conflict_count"], 3)
        self.assertEqual(len(out["conflicts"]), 3)
        self.assertEqual(out["_meta"]["analysis"]["agreement_with_used_car_union"]["trim:AGREE_EXACT"], 1)

    def test_model_absent_from_used_catalog(self):
        cat = catalog([model(1, "Other")], bnc=self.bnc())
        out = N.build_brand_new(cat, N.build(cat))
        self.assertEqual(out["exact_configurations"][0]["comparison_with_used_car_union"]["trim"], "MODEL_NOT_IN_USED_CATALOG")

    def test_possible_trim_match_is_flagged_not_agreed(self):
        cat = catalog([model(249, "Land Cruiser", [{"ID": 1, "SFXName": "Mid-Grade", "Deleted": False}])], bnc=self.bnc())
        out = N.build_brand_new(cat, N.build(cat))
        self.assertEqual(out["exact_configurations"][0]["comparison_with_used_car_union"]["trim"], "POSSIBLE_MATCH_NOT_EXACT")


class Determinism(unittest.TestCase):
    def test_same_input_identical_output(self):
        cat = catalog([model(1, "A", [{"ID": 2, "SFXName": "X ", "Deleted": False}, {"ID": 1, "SFXName": "Y", "Deleted": False}]),
                       model(2, "B")], cyl={"1": {"Engines": [{"ID": 3, "EngineNameen": "2.0TD"}, {"ID": 1, "EngineNameen": "1.6"}],
                                                "Cylinders": [{"ID": 1, "CylinderNameen": "4 cylinder"}]}})
        a = json.dumps(N.build(copy.deepcopy(cat)), ensure_ascii=False)
        b = json.dumps(N.build(copy.deepcopy(cat)), ensure_ascii=False)
        self.assertEqual(a, b)
        self.assertNotIn("generated_at", a)
        self.assertEqual(json.dumps(N.build_brand_new(cat, N.build(cat))), json.dumps(N.build_brand_new(cat, N.build(cat))))


class RawPreservation(unittest.TestCase):
    def test_assemble_keeps_every_response_key_and_raw_strings(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        raw_dir = Path(tmp.name) / "raw"
        cache = raw_dir / "cache"
        cache.mkdir(parents=True)
        brands = [{"ID": 27, "BrandNameen": "Toyota", "BrandNamear": "\u062a\u0648\u064a\u0648\u062a\u0627", "BrandNameku": "\u062a\u06c6\u06cc\u06c6\u062a\u0627", "Extra": {"keep": 1},
                   "Models": [{"ID": 249, "ModelNameen": "Land Cruiser", "ModelNamear": "ar", "ModelNameku": "ku", "Weird": [1, 2],
                               "ModelSFXes": [{"ID": 3974, "SFXName": "VX.R ", "FromYearId": 40, "FromYear": {"ID": 40, "YearName": "1990"}, "Deleted": False}]}]}]
        (cache / "app_initial_data_en.json").write_text(json.dumps({"FilterConfig": {"Brands": brands}}, ensure_ascii=False), encoding="utf-8")
        resp = {"Cylinders": [{"ID": 127, "CylinderNameen": "6 cylinder", "CylinderNamear": "6 x", "CylinderNameku": "6 y", "Sort": 0}],
                "Engines": [{"ID": 50, "EngineNameen": "4.5TD", "EngineNamear": "4.5TD", "EngineNameku": "4.5TD", "Sort": 0}],
                "Specifications": [{"ID": 1, "Specificationen": "Sunroof"}], "SeatNumbers": [{"ID": 3, "SeatNumberNameen": "5"}], "FutureKey": "x"}
        (cache / "cylinder_engine_model_249.json").write_text(json.dumps(resp, ensure_ascii=False), encoding="utf-8")
        saved = (X.RAW_DIR, X.CACHE_DIR, X.CATALOG_PATH)
        X.RAW_DIR, X.CACHE_DIR, X.CATALOG_PATH = raw_dir, cache, raw_dir / "iqcars_catalog.json"
        try:
            self.assertEqual(X.cmd_assemble(None), 0)
        finally:
            X.RAW_DIR, X.CACHE_DIR, X.CATALOG_PATH = saved
        cat = json.loads((raw_dir / "iqcars_catalog.json").read_text(encoding="utf-8"))
        self.assertEqual(cat["cylinder_engine_by_model_id"]["249"], resp)  # complete, verbatim (incl. SeatNumbers, FutureKey)
        self.assertEqual(cat["initial_data_brands"], brands)  # verbatim incl. unknown keys, raw trim whitespace, ar/ku names
        self.assertEqual(cat["initial_data_brands"][0]["Models"][0]["ModelSFXes"][0]["SFXName"], "VX.R ")
        # normalization never mutates the raw artifact
        before = json.dumps(cat, sort_keys=True)
        N.build(cat)
        N.build_brand_new(cat, N.build(cat))
        self.assertEqual(before, json.dumps(cat, sort_keys=True))


if __name__ == "__main__":
    unittest.main()
