"""Brand-aware suffix grammars: recover legitimate engine/powertrain suffixes, never merge sibling models."""
import json
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import matching_audit as ma  # noqa: E402
import model_boundaries as mb  # noqa: E402

_CACHE = {}


def real():
    """(rules-enabled index, rules-disabled index, dataset rows) on the real catalog/dataset - strict rule loading."""
    if not _CACHE:
        i1, cat, ds = mb.load_index(use_suffix_rules=True)
        i0, _, _ = mb.load_index(use_suffix_rules=False)
        rows = ma.load_rows(ds)
        _CACHE.update(i1=i1, i0=i0, rows=rows, res0=ma.resolve_all(i0, rows), res1=ma.resolve_all(i1, rows))
    return _CACHE


def toy(models, grammars, brand="Acme", classes=None, strict=True, trims=None):
    cat = {"models": {brand: models}, "trimsByBrandModel": {brand: trims or {}}}
    sr = {"token_classes": classes or {}, "brands": {brand: {"grammars": grammars}}}
    return mb.ModelIndex(cat, {"aliases": {}, "qualifier_trims": {}, "qualifier_distinct": {}}, suffix_rules=sr, strict_suffix_rules=strict)


class RuleFileIntegrity(unittest.TestCase):
    def test_loads_strictly_on_real_catalog_and_ids_are_unique(self):
        ids = real()["i1"].grammar_ids()
        self.assertEqual(len(ids), len(set(ids)))
        self.assertGreaterEqual(len(ids), 10)

    def test_no_grammar_accepts_a_sibling_models_tail(self):
        self.assertEqual(real()["i1"].sibling_safety_violations(), [])

    def test_every_grammar_model_is_a_catalog_model(self):
        rules = json.loads(mb.SUFFIX_RULES_PATH.read_text(encoding="utf-8"))
        cat = json.loads((mb.REPO / "assets" / "car_catalog.json").read_text(encoding="utf-8"))
        for b, spec in rules["brands"].items():
            for g in spec["grammars"]:
                for m in g["models"]:
                    if m != "*":
                        self.assertIn(m, cat["models"][b], f"{g['id']}: {m}")

    def test_interpreter_errors_are_loud(self):
        with self.assertRaises(ValueError):  # unknown placeholder
            toy(["Alpha"], [{"id": "g", "kind": "k", "models": {"Alpha": {}}, "qualifier_regex": "{nope}"}])
        with self.assertRaises(ValueError):  # model not in catalog (strict)
            toy(["Alpha"], [{"id": "g", "kind": "k", "models": {"Beta": {}}, "qualifier_regex": "x"}])
        with self.assertRaises(ValueError):  # duplicate ids
            g = {"id": "g", "kind": "k", "models": {"Alpha": {}}, "qualifier_regex": "x"}
            toy(["Alpha"], [g, dict(g)])
        # lenient mode (shipped rules on a tiny catalog) silently skips what is not there
        toy(["Alpha"], [{"id": "g", "kind": "k", "models": {"Beta": {}}, "qualifier_regex": "x"}], strict=False)


class InterpreterMechanics(unittest.TestCase):
    G = [{"id": "g1", "kind": "engine_designation", "models": {"X5": {"n": "5"}}, "qualifier_regex": "{n}\\d{2}(?:{letters})?"}]
    C = {"letters": "i|d"}

    def test_fullmatch_only_no_trailing_words(self):
        i = toy(["X5"], self.G, classes=self.C)
        self.assertEqual(i.resolve("Acme", "X5 540d (300 Hp)").status, "suffix_rule")
        for bad in ("X5 540d special edition (300 Hp)", "X5 540dx (300 Hp)", "X5 m540d (300 Hp)", "X5 640d (300 Hp)", "X5 sport 540d (300 Hp)"):
            self.assertEqual(i.resolve("Acme", bad).outcome, mb.QUARANTINED, bad)

    def test_model_variable_must_agree_with_model(self):
        i = toy(["X5", "X6"], [{"id": "g1", "kind": "k", "models": {"X5": {"n": "5"}, "X6": {"n": "6"}}, "qualifier_regex": "{n}\\d{2}"}])
        self.assertEqual(i.resolve("Acme", "X5 540 (1 Hp)").outcome, mb.MATCHED)
        self.assertEqual(i.resolve("Acme", "X5 640 (1 Hp)").outcome, mb.QUARANTINED)
        self.assertEqual(i.resolve("Acme", "X6 640 (1 Hp)").outcome, mb.MATCHED)

    def test_grammar_applies_only_to_its_models(self):
        i = toy(["X5", "X7"], [{"id": "g1", "kind": "k", "models": {"X5": {}}, "qualifier_regex": "\\d{2}d"}])
        self.assertEqual(i.resolve("Acme", "X5 30d (1 Hp)").outcome, mb.MATCHED)
        self.assertEqual(i.resolve("Acme", "X7 30d (1 Hp)").outcome, mb.QUARANTINED)

    def test_quantifier_braces_are_not_placeholders(self):
        i = toy(["Alpha"], [{"id": "g1", "kind": "k", "models": {"Alpha": {}}, "qualifier_regex": "\\d{2,3}"}])
        self.assertEqual(i.resolve("Acme", "Alpha 300 (1 Hp)").outcome, mb.MATCHED)

    def test_sibling_self_check_detects_a_bad_grammar(self):
        bad = toy(["Alpha", "Alpha Sport"], [{"id": "g1", "kind": "k", "models": {"Alpha": {}}, "qualifier_regex": "[a-z]+"}])
        v = bad.sibling_safety_violations()
        self.assertEqual([(x["model"], x["sibling"], x["tail"]) for x in v], [("Alpha", "Alpha Sport", "sport")])
        good = toy(["Alpha", "Alpha Sport"], [{"id": "g1", "kind": "k", "models": {"Alpha": {}}, "qualifier_regex": "\\d{3}"}])
        self.assertEqual(good.sibling_safety_violations(), [])

    def test_longest_canonical_model_wins_before_any_grammar(self):
        i = toy(["X5", "X5 M"], [{"id": "g1", "kind": "k", "models": {"X5": {}}, "qualifier_regex": "m \\d{2}"}])
        r = i.resolve("Acme", "X5 M 4 4 (600 Hp)")
        self.assertEqual((r.model, r.status), ("X5 M", "engine_descriptor"))
        # 'm 50' after the shorter model is a grammar match only when the longer sibling is not a prefix
        self.assertEqual(i.resolve("Acme", "X5 M 50 (1 Hp)").model, "X5 M")

    def test_wildcard_grammar_covers_all_models_and_keeps_the_self_check(self):
        i = toy(["Alpha", "Beta"], [{"id": "g1", "kind": "k", "models": {"*": {}}, "qualifier_regex": "g\\d \\d"}])
        self.assertEqual(i.resolve("Acme", "Beta g1 6 (1 Hp)").outcome, mb.MATCHED)
        self.assertFalse(i.has_grammar("Acme", "Alpha"))  # wildcard is not a model-specific rule

    def test_rules_disabled_reproduces_strict_baseline(self):
        i = toy(["X5"], self.G, classes=self.C)
        i.use_suffix_rules = False
        self.assertEqual(i.resolve("Acme", "X5 540d (300 Hp)").status, "ambiguous_qualifier")


class BrandSuffixAcceptance(unittest.TestCase):
    def r(self, brand, name):
        return real()["i1"].resolve(brand, name)

    def assertMatched(self, brand, name, model, rule=None):
        x = self.r(brand, name)
        self.assertEqual((x.outcome, x.model), (mb.MATCHED, model), f"{name}: {x}")
        if rule:
            self.assertEqual(x.rule, rule)

    def assertQuarantined(self, brand, name, model=None):
        x = self.r(brand, name)
        self.assertEqual(x.outcome, mb.QUARANTINED, f"{name}: {x}")
        if model:
            self.assertEqual(x.model, model)

    def test_bmw(self):
        for n, m in [("3 Series 320d (190 Hp)", "3-Series"), ("3 Series 330i (255 Hp) xDrive", "3-Series"), ("3 Series M340i (374 Hp)", "3-Series"),
                     ("5 Series 530e iPerformance (252 Hp)", "5-Series"), ("7 Series 740Li (326 Hp)", "7-Series"), ("1 Series 116i (109 Hp)", "1-Series"),
                     ("X5 40i (340 Hp)", "X5"), ("X5 M50d (400 Hp)", "X5"), ("X5 4 6is (347 Hp)", "X5"), ("X3 30d (258 Hp)", "X3")]:
            self.assertMatched("BMW", n, m)
        self.assertMatched("BMW", "X1 25Li (1 Hp)", "X1")
        self.assertMatched("BMW", "XM 50e (1 Hp)", "XM")

    def test_bmw_series_digit_must_match_the_model(self):
        self.assertQuarantined("BMW", "3 Series 520d (190 Hp)", "3-Series")
        self.assertQuarantined("BMW", "5 Series 320d (190 Hp)", "5-Series")
        self.assertQuarantined("BMW", "X6 M (575 Hp)", "X6")  # bare 'M' is a performance sub-model, not a powertrain code
        self.assertQuarantined("BMW", "X5 M Competition (625 Hp)", "X5")
        self.assertQuarantined("BMW", "5 Series 520d Special Edition (190 Hp)", "5-Series")

    def test_mercedes(self):
        for n, m in [("E-Class E 220 d (194 Hp)", "E-Class"), ("C-Class C 300 (258 Hp)", "C-Class"), ("GLC GLC 300 (258 Hp)", "GLC"),
                     ("A-Class A 200 (163 Hp)", "A-Class"), ("S-Class S 500 V8 (455 Hp)", "S-Class"), ("CLA CLA 250 (211 Hp)", "CLA"),
                     ("Vito 114 CDI (136 Hp)", "Vito"), ("S-Class 300 SE (188 Hp)", "S-Class"), ("G-Class 300 GD (113 Hp)", "G-Class")]:
            self.assertMatched("Mercedes-Benz", n, m)
        x = self.r("Mercedes-Benz", "C-Class AMG C 63 S V8 (510 Hp)")
        self.assertEqual((x.outcome, x.rule), (mb.MATCHED, "mb_class_designation_amg"))
        self.assertIn("variant:amg_performance", x.flags)

    def test_mercedes_class_letter_must_match_the_model(self):
        self.assertQuarantined("Mercedes-Benz", "C-Class E 220 d (194 Hp)", "C-Class")
        self.assertQuarantined("Mercedes-Benz", "E-Class C 220 d (194 Hp)", "E-Class")
        self.assertQuarantined("Mercedes-Benz", "GLC GLE 300 (258 Hp)", "GLC")

    def test_mercedes_sibling_models_are_not_swallowed(self):
        x = self.r("Mercedes-Benz", "AMG GT 63 S V8 (639 Hp)")  # standalone catalog model, never an AMG variant of a class
        self.assertEqual(x.model, "AMG GT")
        self.assertNotEqual(x.rule, "mb_class_designation_amg")
        self.assertEqual(self.r("Mercedes-Benz", "GLE Coupe GLE 450 (367 Hp)").model, "GLE Coupe")
        self.assertEqual(self.r("Mercedes-Benz", "EQE SUV EQE 350 (292 Hp)").model, "EQE SUV")
        # 'sec' is its own catalog model; an S-Class '500 SEC' is NOT recovered as S-Class
        self.assertQuarantined("Mercedes-Benz", "S-Class 500 SEC V8 (231 Hp)", "S-Class")
        self.assertQuarantined("Mercedes-Benz", "EQS SUV EQS 450 (333 Hp)", "EQS")  # body-style sibling stays isolated
        self.assertQuarantined("Mercedes-Benz", "Vito eVito 111 (116 Hp)", "Vito")

    def test_audi(self):
        self.assertMatched("Audi", "A6 50 TDI V6 (286 Hp) quattro", "A6", "audi_power_level_designation")
        self.assertMatched("Audi", "A6 45 TFSI (245 Hp) quattro", "A6")  # also a catalog trim: either path is MATCHED
        self.assertMatched("Audi", "A4 40 TDI (190 Hp)", "A4")
        self.assertMatched("Audi", "Q5 55 TFSI e (367 Hp)", "Q5")
        self.assertMatched("Audi", "Q7 50 TDI V6 (286 Hp)", "Q7")
        for bad in ("A6 e-tron (1 Hp)", "A6 Competition (1 Hp)", "A3 g-tron (1 Hp)", "A6 45 TFSI performance (1 Hp)"):
            self.assertQuarantined("Audi", bad)
        self.assertEqual(self.r("Audi", "Q4 e-tron 40 (204 Hp)").model, "Q4 e-tron")  # own catalog model wins

    def test_lexus(self):
        self.assertMatched("Lexus", "RX 350 V6 (277 Hp)", "RX")
        self.assertMatched("Lexus", "NX 300h (197 Hp)", "NX")
        self.assertMatched("Lexus", "RX 350L V6 (290 Hp)", "RX", "lexus_rx_long_wheelbase_designation")
        self.assertQuarantined("Lexus", "IS 250C AWD (204 Hp)", "IS")  # 'IS C' is its own model
        self.assertQuarantined("Lexus", "RX 350 F Sport V6 (277 Hp)", "RX")  # trim words are not powertrain tokens
        self.assertQuarantined("Lexus", "LS 460 L V8 (380 Hp)", "LS")
        self.assertEqual(self.r("Lexus", "IS F 5 0 V8 (423 Hp)").model, "IS F")

    def test_other_brands(self):
        self.assertMatched("Jaguar", "XF 20d (180 Hp)", "XF")
        self.assertMatched("Jaguar", "F-Type P380 V6 (380 Hp)", "F-Type")
        self.assertQuarantined("Jaguar", "F-Type R (550 Hp)", "F-Type")
        self.assertQuarantined("Jaguar", "F-Type SVR (575 Hp)", "F-Type")
        self.assertMatched("Hyundai", "Sonata G2 5 GDI (180 Hp)", "Sonata")
        self.assertMatched("Kia", "Sonet G1 0 T GDI (120 Hp)", "Sonet")
        self.assertQuarantined("Hyundai", "i30 N Performance (275 Hp)", "i30")

    def test_trim_vs_engine_suffix_are_distinguished(self):
        # catalog trim -> accepted as trim_qualifier (a different, pre-existing path); engine label -> suffix_rule
        t = self.r("Audi", "A3 S line (1 Hp)")
        self.assertEqual(t.status, "trim_qualifier")
        e = self.r("Audi", "A3 35 TFSI (150 Hp)")
        self.assertIn(e.status, ("trim_qualifier", "suffix_rule"))  # '35 TFSI' is also a catalog trim of A3
        self.assertEqual(self.r("Audi", "A6 50 TDI V6 (286 Hp)").status, "suffix_rule")
        self.assertEqual(self.r("BMW", "X5 M Sport (1 Hp)").status, "trim_qualifier")  # catalog trim, not a descriptor
        self.assertEqual(self.r("BMW", "X5 M Sport (1 Hp)").rule, None)


class SiblingIsolationOnRealData(unittest.TestCase):
    PAIRS = ma.REQUIRED_SIBLING_PAIRS

    def test_required_pairs_exist_in_catalog(self):
        i = real()["i1"]
        for b, s, l in self.PAIRS:
            self.assertIn(s, i.models[b])
            self.assertIn(l, i.models[b])

    def test_rows_named_for_the_longer_model_never_resolve_to_the_shorter(self):
        c = real()
        pairs_with_rows = 0
        for b, short, long_ in self.PAIRS:
            lk = mb.mkey(long_)
            n = 0
            for r, x in zip(c["rows"], c["res1"]):
                k = mb.mkey(r["name"])
                if r["brand"] == b and (k == lk or k.startswith(lk + " ")):
                    n += 1
                    self.assertEqual(x.model, long_, f"{b}: {r['name']} -> {x.model}")
            pairs_with_rows += n > 0  # e.g. GR Corolla has no dataset rows today
        self.assertGreaterEqual(pairs_with_rows, len(self.PAIRS) - 1)

    def test_no_suffix_rule_row_belongs_to_a_sibling_by_name(self):
        c = real()
        self.assertEqual(ma.false_match_suspects(c["i1"], c["rows"], c["res1"]), [])
        self.assertEqual(ma.collision_checks(c["i1"], c["rows"], c["res1"])["rows_matched_to_shorter_model_whose_name_starts_with_longer_sibling"], 0)

    def test_corolla_gr_corolla_not_auto_merged(self):
        i = real()["i1"]
        self.assertEqual(i.resolve("Toyota", "GR Corolla 1 6 (304 Hp)").model, "GR Corolla")
        self.assertNotEqual(i.resolve("Toyota", "GR Corolla 1 6 (304 Hp)").model, "Corolla")
        x = i.resolve("Toyota", "Corolla GR 1 6 (304 Hp)")
        self.assertIn("qualifier_overlaps_other_model:GR Corolla", x.flags)  # flagged, still not merged silently
        self.assertEqual(i.resolve("Toyota", "Corolla Cross 2 0 (170 Hp)").model, "Corolla Cross")
        self.assertEqual(i.resolve("Toyota", "Land Cruiser Prado 2 7 (163 Hp)").model, "Land Cruiser Prado")
        self.assertEqual(i.resolve("Land Rover", "Discovery Sport 2 0 (240 Hp)").model, "Discovery Sport")
        self.assertEqual(i.resolve("Ford", "Bronco Sport 1 5 (181 Hp)").model, "Bronco Sport")
        self.assertEqual(i.resolve("Mitsubishi", "Pajero Sport 2 4 (181 Hp)").model, "Pajero Sport")
        self.assertEqual(i.resolve("Volkswagen", "Passat CC 2 0 (170 Hp)").model, "Passat CC")
        self.assertEqual(i.resolve("Renault", "Megane GT 1 6 (205 Hp)").model, "Megane GT")
        self.assertEqual(i.resolve("Volkswagen", "Golf R 2 0 (310 Hp)").model, "Golf R")

    def test_suffix_rules_never_match_these_sibling_tails(self):
        i = real()["i1"]
        for b, short, long_ in self.PAIRS:
            tail = mb.mkey(long_)[len(mb.mkey(short)):].strip()
            if mb.mkey(long_).startswith(mb.mkey(short) + " "):
                self.assertEqual(i.matching_grammars(b, short, tail), [], f"{short} would accept {tail!r}")


class OutcomesAndDeterminism(unittest.TestCase):
    def test_three_states_and_no_row_dropped(self):
        c = real()
        self.assertEqual(len(c["res1"]), len(c["rows"]))
        self.assertEqual({x.outcome for x in c["res1"]}, {mb.MATCHED, mb.QUARANTINED, mb.UNRESOLVED})
        n = ma.outcome_counts(c["res1"])
        self.assertEqual(n["MATCHED"] + n["QUARANTINED"] + n["UNRESOLVED"], len(c["rows"]))
        i = c["i1"]
        self.assertEqual(i.resolve("NoSuchBrand", "Foo 1 0 (1 Hp)").outcome, mb.UNRESOLVED)
        self.assertEqual(i.resolve("BMW", "Zzz 1 0 (1 Hp)").outcome, mb.UNRESOLVED)
        self.assertEqual(i.resolve("BMW", "3 Series 320d (1 Hp)").outcome, mb.MATCHED)
        self.assertEqual(i.resolve("BMW", "3 Series Weird Thing (1 Hp)").outcome, mb.QUARANTINED)

    def test_baseline_with_rules_disabled_is_the_recorded_baseline(self):
        n = ma.outcome_counts(real()["res0"])
        self.assertEqual((n["MATCHED"], n["QUARANTINED"], n["UNRESOLVED"], n["total"]), (24910, 8274, 8946, 42130))

    def test_rules_only_ever_move_quarantined_rows_to_matched(self):
        c = real()
        for r, a, b in zip(c["rows"], c["res0"], c["res1"]):
            if a.outcome == mb.MATCHED:
                self.assertEqual((b.outcome, b.model, b.status), (a.outcome, a.model, a.status), r["name"])
            elif a.outcome == mb.UNRESOLVED:
                self.assertEqual(b.outcome, mb.UNRESOLVED, r["name"])
            else:
                self.assertEqual(b.model, a.model, r["name"])  # same canonical candidate, just accepted

    def test_recovery_is_substantial_and_bounded(self):
        c = real()
        rec = sum(1 for a, b in zip(c["res0"], c["res1"]) if a.outcome != b.outcome)
        self.assertGreater(rec, 5000)
        self.assertLess(rec, 8274)  # the genuine siblings / editions / trims stay quarantined

    def test_pilot_models_unchanged(self):
        c = real()
        for b, m in (("Ford", "Everest"), ("Toyota", "Land Cruiser"), ("Toyota", "Camry")):
            a = sorted(r["id"] for r, x in zip(c["rows"], c["res0"]) if r["brand"] == b and x.accepted and x.model == m)
            z = sorted(r["id"] for r, x in zip(c["rows"], c["res1"]) if r["brand"] == b and x.accepted and x.model == m)
            self.assertEqual(a, z, f"{b} {m}")
        lc = [r for r, x in zip(c["rows"], c["res1"]) if r["brand"] == "Toyota" and x.accepted and x.model == "Land Cruiser"]
        self.assertEqual(len(lc), 73)
        self.assertFalse([r for r in lc if "prado" in r["name"].lower()])

    def test_deterministic_across_index_rebuilds(self):
        i2, _, ds = mb.load_index()
        rows = ma.load_rows(ds)
        res2 = ma.resolve_all(i2, rows)
        c = real()
        self.assertEqual(ma.ledger_sha(rows, res2), ma.ledger_sha(c["rows"], c["res1"]))
        base1, rec1, rev1, _ = ma.full_report()
        base2, rec2, rev2, _ = ma.full_report()
        for a, b in ((base1, base2), (rec1, rec2), (rev1, rev2)):
            self.assertEqual(json.dumps(a, sort_keys=True), json.dumps(b, sort_keys=True))

    def test_review_queue_accounts_for_every_remaining_quarantined_row(self):
        _b, rec, review, ctx = ma.full_report()
        self.assertEqual(review["total_rows"], rec["still_quarantined"])
        self.assertEqual(sum(e["rows"] for e in review["entries"]), rec["still_quarantined"])
        self.assertEqual(sum(review["rows_per_category"].values()), rec["still_quarantined"])
        self.assertEqual(rec["row_accounting"]["outcome_sum_after"], rec["row_accounting"]["dataset_rows"])
        self.assertEqual(rec["safety"]["matched_rows_lost_or_reassigned_vs_baseline"], 0)
        self.assertEqual(rec["safety"]["suspected_false_matches"], [])

    def test_committed_reports_match_a_fresh_run(self):
        _b, rec, review, _ = ma.full_report()
        for name, fresh in (("model_matching_recovery.json", rec), ("model_matching_review_queue.json", review)):
            p = ma.REPORTS / name
            if p.exists():
                self.assertEqual(json.loads(p.read_text(encoding="utf-8")), json.loads(json.dumps(fresh, ensure_ascii=False)), f"{name} is stale - run matching_audit.py report")


if __name__ == "__main__":
    unittest.main()
