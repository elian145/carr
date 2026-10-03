"""Deterministic canonical Brand+Model matching: prefix/suffix collisions must never merge distinct models."""
import json
import random
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import enrichment_lib as L  # noqa: E402
import model_boundaries as mb  # noqa: E402

CAT = {
    "models": {
        "Toyota": ["Camry", "Camry Solara", "Corolla", "Corolla Cross", "GR Corolla", "Highlander", "Grand Highlander", "Land Cruiser", "Land Cruiser 70", "Land Cruiser Prado", "Prius", "Prius C"],
        "Ford": ["Bronco", "Bronco Sport", "Everest", "Explorer", "Explorer Sport Trac"],
        "Land Rover": ["Defender", "Discovery", "Discovery Sport", "Range Rover Sport"],
        "Volkswagen": ["Tiguan", "Golf", "Golf R"],
        "Honda": ["Civic", "Civic Type R"],
        "Mazda": ["6", "6 Wagon"],
    },
    "trimsByBrandModel": {
        "Toyota": {"Land Cruiser": ["GX", "VX", "Other"], "Corolla": ["GR", "LE"], "Camry": ["SE", "XSE"]},
        "Ford": {"Bronco": ["Badlands"]},
    },
}
RULES = {"aliases": {}, "qualifier_trims": {}, "qualifier_distinct": {}}


def idx(rules=None):
    return mb.ModelIndex(CAT, rules if rules is not None else RULES)


class CanonicalIdentity(unittest.TestCase):
    def test_exact_identity_only(self):
        i = idx()
        self.assertEqual(i.canonical_model("Toyota", "Land Cruiser"), "Land Cruiser")
        self.assertEqual(i.canonical_model("toyota", "LAND-CRUISER"), "Land Cruiser")  # case / hyphen only
        self.assertEqual(i.canonical_model("Toyota", "Land Cruiser Prado"), "Land Cruiser Prado")
        self.assertNotEqual(i.canonical_model("Toyota", "Land Cruiser Prado"), "Land Cruiser")
        self.assertIsNone(i.canonical_model("Toyota", "Land Cruiser 2 4"))  # a prefix is NOT an identity
        self.assertIsNone(i.canonical_model("Toyota", "Cruiser"))
        self.assertIsNone(i.canonical_model("Nope", "Camry"))

    def test_catalog_prefix_pairs_are_found(self):
        pairs = set(i for i in idx().prefix_pairs())
        for p in (("Toyota", "Land Cruiser", "Land Cruiser Prado"), ("Toyota", "Land Cruiser", "Land Cruiser 70"), ("Toyota", "Corolla", "Corolla Cross"),
                  ("Ford", "Bronco", "Bronco Sport"), ("Land Rover", "Discovery", "Discovery Sport"), ("Honda", "Civic", "Civic Type R"), ("Mazda", "6", "6 Wagon")):
            self.assertIn(p, pairs)
        # Highlander / Grand Highlander is a SUFFIX relationship, not a prefix one
        self.assertNotIn(("Toyota", "Highlander", "Grand Highlander"), pairs)

    def test_aliases_are_explicit_and_validated(self):
        i = idx({"aliases": {"Toyota": {"Landcruiser": "Land Cruiser"}}, "qualifier_trims": {}, "qualifier_distinct": {}})
        self.assertEqual(i.canonical_model("Toyota", "Landcruiser"), "Land Cruiser")
        self.assertEqual(i.resolve("Toyota", "Landcruiser 4 5 (190 Hp)").model, "Land Cruiser")
        with self.assertRaises(ValueError):
            idx({"aliases": {"Toyota": {"Foo": "Not A Model"}}})
        with self.assertRaises(ValueError):  # alias must not shadow a different canonical model
            idx({"aliases": {"Toyota": {"Land Cruiser Prado": "Land Cruiser"}}})

    def test_duplicate_model_keys_in_catalog_fail_loudly(self):
        with self.assertRaises(ValueError):
            mb.ModelIndex({"models": {"X": ["Foo Bar", "foo-bar"]}}, RULES)


class PrefixSuffixCollisions(unittest.TestCase):
    def setUp(self):
        self.i = idx()

    def belongs(self, brand, selected, name):
        return self.i.accepts(brand, selected, name).accepted and self.i.resolve(brand, name).model == self.i.canonical_model(brand, selected)

    def test_land_cruiser_is_not_land_cruiser_prado(self):
        n = "Land Cruiser Prado 2 7 (163 Hp) 4WD"
        self.assertEqual(self.i.resolve("Toyota", n).model, "Land Cruiser Prado")
        self.assertTrue(self.belongs("Toyota", "Land Cruiser Prado", n))
        self.assertFalse(self.belongs("Toyota", "Land Cruiser", n))
        self.assertIn("belongs_to_other_model", self.i.accepts("Toyota", "Land Cruiser", n).flags)
        self.assertTrue(self.belongs("Toyota", "Land Cruiser", "Land Cruiser 4 5 24V (FZJ80) (190 Hp)"))
        self.assertFalse(self.belongs("Toyota", "Land Cruiser Prado", "Land Cruiser 4 5 24V (FZJ80) (190 Hp)"))

    def test_legacy_rule_would_have_merged_them(self):
        self.assertTrue(mb.legacy_family_match("Land Cruiser Prado 2 7 (163 Hp)", "Land Cruiser"))  # the old bug
        self.assertFalse(self.belongs("Toyota", "Land Cruiser", "Land Cruiser Prado 2 7 (163 Hp)"))

    def test_other_prefix_pairs(self):
        cases = [
            ("Toyota", "Corolla", "Corolla Cross", "Corolla Cross 1 8 (122 Hp) Hybrid e-CVT"),
            ("Ford", "Bronco", "Bronco Sport", "Bronco Sport 1 5 (181 Hp)"),
            ("Land Rover", "Discovery", "Discovery Sport", "Discovery Sport 2 0 (240 Hp)"),
            ("Honda", "Civic", "Civic Type R", "Civic Type R 2 0 (306 Hp)"),
            ("Ford", "Explorer", "Explorer Sport Trac", "Explorer Sport Trac 4 0 V6 (210 Hp)"),
            ("Toyota", "Camry", "Camry Solara", "Camry Solara 2 4 (157 Hp)"),
            ("Volkswagen", "Golf", "Golf R", "Golf R 2 0 TSI (300 Hp)"),
        ]
        for brand, short, long_, name in cases:
            self.assertTrue(self.belongs(brand, long_, name), name)
            self.assertFalse(self.belongs(brand, short, name), name)

    def test_suffix_collision_highlander_vs_grand_highlander(self):
        self.assertTrue(self.belongs("Toyota", "Grand Highlander", "Grand Highlander 2 5 (245 Hp) Hybrid e-CVT"))
        self.assertFalse(self.belongs("Toyota", "Highlander", "Grand Highlander 2 5 (245 Hp) Hybrid e-CVT"))
        self.assertTrue(self.belongs("Toyota", "Highlander", "Highlander 2 5 (243 Hp) Hybrid e-CVT"))
        self.assertFalse(self.belongs("Toyota", "Grand Highlander", "Highlander 2 5 (243 Hp) Hybrid e-CVT"))

    def test_longest_catalog_name_wins_with_digits(self):
        r = self.i.resolve("Toyota", "Land Cruiser 70 2 4 (110 Hp) 4WD")
        self.assertEqual((r.model, r.status), ("Land Cruiser 70", "engine_descriptor"))
        self.assertFalse(self.belongs("Toyota", "Land Cruiser", "Land Cruiser 70 2 4 (110 Hp) 4WD"))
        r = self.i.resolve("Mazda", "6 Wagon 2 5 (192 Hp)")
        self.assertEqual(r.model, "6 Wagon")

    def test_whole_word_prefix_only(self):
        self.assertEqual(self.i.resolve("Honda", "Civics 1 8").status, "unresolved")  # 'civic' is not a whole-word prefix of 'civics'
        self.assertEqual(self.i.resolve("Toyota", "Priusx 1 8").status, "unresolved")

    def test_models_not_in_catalog_never_join_a_neighbour(self):
        r = self.i.resolve("Land Rover", "Range Rover 3 0 TD (211 Hp)")  # catalog has only 'Range Rover Sport'
        self.assertEqual(r.status, "unresolved")
        self.assertIsNone(r.model)
        r = self.i.accepts("Volkswagen", "Tiguan", "Tiguan Allspace 2 0 TSI (180 Hp)")  # not a catalog model
        self.assertFalse(r.accepted)
        self.assertEqual(r.status, "ambiguous_qualifier")
        self.assertTrue(self.belongs("Volkswagen", "Tiguan", "Tiguan 2 0 TSI (180 Hp)"))

    def test_ambiguous_qualifier_is_quarantined_trim_qualifier_is_accepted(self):
        self.assertEqual(self.i.resolve("Toyota", "Land Cruiser GX 4 5d V8 (272 Hp) AWD Automatic").status, "trim_qualifier")  # GX is a catalog trim
        self.assertEqual(self.i.resolve("Toyota", "Land Cruiser GXL 4 5d V8 (272 Hp)").status, "ambiguous_qualifier")  # GXL is not
        self.assertEqual(self.i.resolve("Toyota", "Land Cruiser Prado First Edition 2 8 D-4D (204 Hp)").status, "ambiguous_qualifier")
        self.assertFalse(self.belongs("Toyota", "Land Cruiser Prado", "Land Cruiser Prado First Edition 2 8 D-4D (204 Hp)"))
        self.assertEqual(self.i.resolve("Toyota", "Corolla Verso 1 8 VVT-i (129 Hp)").status, "ambiguous_qualifier")
        self.assertEqual(self.i.resolve("Ford", "Bronco Badlands 2 7 (330 Hp)").status, "trim_qualifier")

    def test_a_trim_word_that_spells_another_model_is_flagged(self):
        r = self.i.resolve("Toyota", "Corolla GR 1 6 (300 Hp) GR-FOUR iMT")
        self.assertEqual(r.status, "trim_qualifier")
        self.assertIn("qualifier_overlaps_other_model:GR Corolla", r.flags)

    def test_explicit_distinct_qualifier_overrides_nothing_silently(self):
        i = idx({"aliases": {}, "qualifier_trims": {}, "qualifier_distinct": {"Toyota": {"Land Cruiser": {"GX": "pretend decision"}}}})
        self.assertEqual(i.resolve("Toyota", "Land Cruiser GX 4 5d V8").status, "distinct_vehicle_qualifier")

    def test_engine_descriptor_forms(self):
        for name in ("Corolla 1 6 (110 Hp)", "Corolla 1 33 Dual VVT-i (100 Hp)", "Corolla 2 7l (163 Hp)", "Corolla 1100 (60 Hp)", "Corolla 2 4i 16V (152 Hp)", "Corolla 77 kWh (221 Hp) Electric", "Corolla (2018)", "Corolla"):
            r = self.i.resolve("Toyota", name)
            self.assertTrue(r.accepted and r.model == "Corolla", name)
        self.assertFalse(self.i.resolve("Toyota", "Corolla 200 4 5").accepted)  # 3-digit number is not an engine: quarantined


class Partitioning(unittest.TestCase):
    ROWS = [{"name": n} for n in (
        "Land Cruiser 4 5 24V (FZJ80) (190 Hp)", "Land Cruiser Prado 2 7 (163 Hp)", "Land Cruiser GX 4 5d V8", "Land Cruiser GXL 4 5d V8",
        "Land Cruiser 70 2 4 (110 Hp)", "Land Cruiser 3 5L V6 (415 Hp)", "Land Cruiser Prado First Edition 2 8 (204 Hp)",
    )]

    def test_every_row_is_accounted_for(self):
        acc, exc = idx().split_dataset_rows("Toyota", "Land Cruiser", self.ROWS)
        self.assertEqual(len(acc) + sum(len(v) for v in exc.values()), len(self.ROWS))
        self.assertEqual(sorted(r["name"] for r in acc), ["Land Cruiser 3 5L V6 (415 Hp)", "Land Cruiser 4 5 24V (FZJ80) (190 Hp)", "Land Cruiser GX 4 5d V8"])
        self.assertEqual(sorted(exc), ["ambiguous_qualifier:Land Cruiser", "ambiguous_qualifier:Land Cruiser Prado", "belongs_to:Land Cruiser 70", "belongs_to:Land Cruiser Prado"])

    def test_order_independent(self):
        base = idx().split_dataset_rows("Toyota", "Land Cruiser", self.ROWS)
        rows = list(self.ROWS)
        random.Random(7).shuffle(rows)
        acc, exc = idx().split_dataset_rows("Toyota", "Land Cruiser", rows)
        self.assertEqual(sorted(r["name"] for r in acc), sorted(r["name"] for r in base[0]))
        self.assertEqual({k: sorted(x["name"] for x in v) for k, v in exc.items()}, {k: sorted(x["name"] for x in v) for k, v in base[1].items()})

    def test_non_canonical_selected_model_accepts_nothing(self):
        acc, exc = idx().split_dataset_rows("Toyota", "Land Cruiser 2 4", self.ROWS)
        self.assertEqual(acc, [])


class RealCatalog(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.mi, cls.cat, cls.ds = mb.load_index()

    def test_pilot_models_are_canonical(self):
        for b, m in (("Ford", "Everest"), ("Toyota", "Land Cruiser"), ("Toyota", "Camry")):
            self.assertEqual(self.mi.canonical_model(b, m), m)

    def test_must_remain_distinct_models_exist_and_have_distinct_identity(self):
        rules = json.loads(mb.RULES_PATH.read_text(encoding="utf-8"))
        for group in rules["must_remain_distinct"]:
            canon = [self.mi.canonical_model(group["brand"], m) for m in group["models"]]
            self.assertNotIn(None, canon, group)
            self.assertEqual(len(set(canon)), len(canon), group)

    def test_watchlist_names_are_really_not_catalog_models(self):
        rules = json.loads(mb.RULES_PATH.read_text(encoding="utf-8"))
        for w in rules["watchlist_not_in_catalog"]:
            if w["name"] in ("Range Rover", "Tiguan Allspace"):
                self.assertIsNone(self.mi.canonical_model(w["brand"], w["name"]), w)

    def test_no_prado_row_resolves_to_land_cruiser(self):
        brands = {b["id"]: b["name"] for b in self.ds["brands"]}
        n_prado = 0
        for m in self.ds["models"]:
            if brands[m["brand_id"]] != "Toyota" or not m["name"].startswith("Land Cruiser Prado"):
                continue
            n_prado += 1
            r = self.mi.resolve("Toyota", m["name"])
            self.assertEqual(r.model, "Land Cruiser Prado", m["name"])
        self.assertGreater(n_prado, 50)

    def test_no_row_of_a_longer_sibling_is_ever_given_to_the_shorter_model(self):
        brands = {b["id"]: b["name"] for b in self.ds["brands"]}
        names = {}
        for m in self.ds["models"]:
            names.setdefault(brands[m["brand_id"]], []).append(m["name"])
        for b, short, long_ in self.mi.prefix_pairs():
            for n in names.get(b, []):
                if mb.mkey(n) == mb.mkey(long_) or mb.mkey(n).startswith(mb.mkey(long_) + " "):
                    r = self.mi.accepts(b, short, n)
                    self.assertFalse(r.accepted and r.model == self.mi.canonical_model(b, short), (b, short, long_, n))

    def test_pilot_evidence_is_bound_to_canonical_models(self):
        for name in ("ford_everest", "toyota_land_cruiser", "toyota_camry"):
            doc = L.read_json(L.HERE / "evidence" / f"{name}.json")
            self.assertEqual(L.validate_evidence(doc, self.mi), [], name)

    def test_land_cruiser_evidence_does_not_mention_prado(self):
        doc = L.read_json(L.HERE / "evidence" / "toyota_land_cruiser.json")
        self.assertEqual(L.boundary_warnings(doc, self.mi), [])

    def test_evidence_bound_to_wrong_model_is_rejected(self):
        doc = L.read_json(L.HERE / "evidence" / "toyota_land_cruiser.json")
        doc["records"][0]["model"] = "Land Cruiser Prado"
        errs = L.validate_evidence(doc, self.mi)
        self.assertTrue(any("resolves to" in e for e in errs), errs)

    def test_boundary_warning_detects_sibling_mention(self):
        doc = L.read_json(L.HERE / "evidence" / "toyota_land_cruiser.json")
        doc["records"][0]["evidence"]["supporting_text"] += " Also sold as the Land Cruiser Prado."
        self.assertTrue(L.boundary_warnings(doc, self.mi))


class CurrentCarnetBoundaries(unittest.TestCase):
    def test_land_cruiser_current_values_exclude_prado_rows(self):
        ctx = L.load_current_carnet()
        cur = L.current_carnet(ctx, "Toyota", "Land Cruiser")
        b = cur["boundary"]
        self.assertLess(b["strict_rows"], b["legacy_family_rows"])
        self.assertTrue(all(not n.startswith("Land Cruiser Prado") for n in cur["dataset_model_names"]))
        self.assertGreater(b["excluded_by_reason"].get("belongs_to:Land Cruiser Prado", 0), 50)

    def test_non_canonical_model_raises(self):
        ctx = L.load_current_carnet()
        with self.assertRaises(ValueError):
            L.current_carnet(ctx, "Toyota", "Land Cruiser Prad")


if __name__ == "__main__":
    unittest.main()
