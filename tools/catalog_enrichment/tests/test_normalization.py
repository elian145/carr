"""Unit tests for the enrichment pilot (run: python -m unittest discover -s tools/catalog_enrichment/tests -t tools/catalog_enrichment)."""
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import enrichment_lib as L  # noqa: E402


class FuelTests(unittest.TestCase):
    def test_petrol_synonyms(self):
        for raw in ("Petrol", "Gasoline", "Petrol (Gasoline)", "gasoline", "Unleaded", "Gas", "ガソリン（レギュラー）"):
            self.assertEqual(L.norm_fuel(raw)[0], "Petrol", raw)

    def test_diesel_hybrid(self):
        self.assertEqual(L.norm_fuel("Turbo Diesel")[0], "Diesel")
        self.assertEqual(L.norm_fuel("軽油")[0], "Diesel")
        self.assertEqual(L.norm_fuel("i-FORCE MAX Hybrid")[0], "Hybrid")
        self.assertEqual(L.norm_fuel("Plug-in Hybrid")[0], "Plug-in Hybrid")

    def test_ecoboost_alone_is_not_a_fuel(self):
        v, flags = L.norm_fuel("EcoBoost")
        self.assertIsNone(v)
        self.assertTrue(flags[0].startswith("unmapped:"))

    def test_null_stays_null(self):
        self.assertEqual(L.norm_fuel(None), (None, []))


class DrivetrainTests(unittest.TestCase):
    def test_4wd_family(self):
        for raw in ("4x4", "4WD", "Four-wheel drive", "Full-Time 4-Wheel Drive", "Part-Time 4x4", "full-time 4WD", "Full-time four-wheel drive"):
            self.assertEqual(L.norm_drivetrain(raw)[0], "4WD", raw)

    def test_awd_is_distinct_from_4wd(self):
        for raw in ("AWD", "All Wheel Drive", "Electronic On-Demand All-Wheel Drive (AWD)"):
            self.assertEqual(L.norm_drivetrain(raw)[0], "AWD", raw)

    def test_fwd_rwd(self):
        self.assertEqual(L.norm_drivetrain("Front-Wheel Drive (FWD)")[0], "FWD")
        self.assertEqual(L.norm_drivetrain("RWD")[0], "RWD")

    def test_4x2_is_not_guessed(self):
        v, flags = L.norm_drivetrain("4x2")
        self.assertIsNone(v)
        self.assertEqual(flags, ["two_wheel_drive_axle_unspecified"])


class TransmissionTests(unittest.TestCase):
    def test_families_and_gears(self):
        t, _ = L.norm_transmission("10-Speed SelectShift AT")
        self.assertEqual((t["family"], t["gears"]), ("Automatic", 10))
        t, _ = L.norm_transmission("Direct Shift-8AT")
        self.assertEqual((t["family"], t["gears"]), ("Automatic", 8))
        t, _ = L.norm_transmission("6 Super-ECT")
        self.assertEqual((t["family"], t["gears"]), ("Automatic", 6))
        t, _ = L.norm_transmission("5-speed manual")
        self.assertEqual((t["family"], t["gears"]), ("Manual", 5))


class ScalarTests(unittest.TestCase):
    def test_displacement(self):
        d, _ = L.norm_displacement("2.3L")
        self.assertEqual((d["cc"], d["label"]), (None, "2.3L"))  # nominal litres never invent cc
        d, _ = L.norm_displacement({"value": 2.754, "unit": "L"})
        self.assertEqual((d["cc"], d["label"]), (2754, "2.8L"))
        d, _ = L.norm_displacement({"value": 3198, "unit": "cm3"})
        self.assertEqual((d["cc"], d["label"]), (3198, "3.2L"))
        d, _ = L.norm_displacement("3.5-liter")
        self.assertEqual(d["label"], "3.5L")
        d, _ = L.norm_displacement({"value": 1996, "unit": "cc"})
        self.assertEqual(d["label"], "2.0L")

    def test_cylinders(self):
        for raw, n in (("I-4", 4), ("V6", 6), ("5 Cylinder", 5), ("4-Cyl.", 4), ("four-cylinder", 4), ("直列4気筒", 4), ("In-line 4 Cylinder", 4), (8, 8)):
            self.assertEqual(L.norm_cylinders(raw)[0], n, raw)

    def test_seats(self):
        self.assertEqual(L.norm_seats("7-seater")[0], 7)
        self.assertEqual(L.norm_seats("up to eight"), (8, ["seats_is_maximum"]))
        self.assertEqual(L.norm_seats(5), (5, []))

    def test_body(self):
        self.assertEqual(L.norm_body("SUV")[0], "SUV")
        self.assertEqual(L.norm_body("Off-road vehicle")[0], "SUV")
        self.assertEqual(L.norm_body("Pick-up")[0], "Pickup")

    def test_units(self):
        self.assertAlmostEqual(L.norm_horsepower({"value": 415, "unit": "PS"})[0], 409.3, places=1)
        self.assertAlmostEqual(L.norm_horsepower({"value": 125, "unit": "kW"})[0], 167.6, places=1)
        self.assertEqual(L.norm_torque({"value": 465, "unit": "lb-ft"})[0], 630)
        self.assertEqual(L.norm_torque({"value": 71.4, "unit": "kgm"})[0], 700)

    def test_trim(self):
        self.assertEqual(L.trim_key("  GR-Sport "), L.trim_key("GR SPORT"))
        self.assertNotEqual(L.trim_key("GXR"), L.trim_key("GX-R"))
        self.assertEqual(L.trim_display("PLATINUM"), "Platinum")
        self.assertEqual(L.trim_display("xle"), "XLE")
        self.assertEqual(L.trim_display("GR SPORT"), "GR Sport")
        self.assertEqual(L.trim_display("VX-R"), "VX-R")
        self.assertEqual(L.trim_display("Titanium+"), "Titanium+")
        self.assertIsNone(L.trim_key("Other"))

    def test_market(self):
        self.assertEqual(L.norm_market("UAE")[0], "gcc")
        self.assertEqual(L.norm_market("Middle East"), ("gcc", ["market_approximate"]))
        self.assertEqual(L.norm_market("Australia")[0], "other:au")
        self.assertIsNone(L.norm_market("Global")[0])


class TraceTests(unittest.TestCase):
    def test_untraceable_value_is_caught(self):
        rec = {"evidence": {"supporting_text": "The Everest has a 2.0L Turbo Diesel making 170 hp"},
               "engine": {"displacement_raw": "2.0L", "fuel_type": "Diesel", "horsepower": {"value": 170, "unit": "hp"}, "torque": {"value": 405, "unit": "Nm"}},
               "transmission": {}}
        bad = L.trace_check(rec)
        self.assertEqual(bad, ["engine.torque.value=405"])


class ConflictTests(unittest.TestCase):
    def _rec(self, rid, **n):
        base = {"market": None, "trim": None, "trim_key": None, "engine_group": "2.0L", "fuel_type": None, "seats_is_maximum": False,
                "displacement_cc": None, "cylinders": None, "horsepower_hp": None, "torque_nm": None, "transmission_family": None, "transmission_variant": None,
                "transmission_gears": None, "drivetrain": None, "body_type": None, "seats": None, "doors": None}
        base.update(n)
        return {"record_id": rid, "year_from": None, "year_to": None, "variant": None, "normalized": base,
                "evidence": {"source_id": "S", "source_tier": 1}}

    def test_conflict_detected_and_preserved(self):
        c = L.detect_conflicts([self._rec("A", horsepower_hp=170.0), self._rec("B", horsepower_hp=168.0)], "t")
        self.assertEqual(len(c), 1)
        self.assertEqual(c[0]["severity"], "possible_year_unspecified")
        self.assertEqual([v["record_id"] for v in c[0]["values"]], ["A", "B"])

    def test_tolerance(self):
        self.assertEqual(L.detect_conflicts([self._rec("A", horsepower_hp=409.3), self._rec("B", horsepower_hp=409.0)], "t"), [])

    def test_hybrid_vs_petrol_same_engine_is_not_a_conflict(self):
        self.assertEqual(L.detect_conflicts([self._rec("A", fuel_type="Hybrid", horsepower_hp=326.0), self._rec("B", fuel_type="Petrol", horsepower_hp=277.0)], "t"), [])

    def test_different_markets_never_conflict(self):
        self.assertEqual(L.detect_conflicts([self._rec("A", market="gcc", horsepower_hp=100.0), self._rec("B", market="other:au", horsepower_hp=200.0)], "t"), [])


class PilotFilesTests(unittest.TestCase):
    def test_evidence_files_validate(self):
        for name in ("ford_everest", "toyota_land_cruiser", "toyota_camry"):
            doc = L.read_json(L.HERE / "evidence" / f"{name}.json")
            self.assertEqual(L.validate_evidence(doc), [], name)

    def test_prepare_is_idempotent(self):
        doc = L.read_json(L.HERE / "evidence" / "toyota_camry.json")
        self.assertEqual(L.prepare_evidence(doc), L.prepare_evidence(L.prepare_evidence(doc)))

    def test_no_writes_under_assets(self):
        with self.assertRaises(SystemExit):
            L.assert_not_production(L.REPO / "assets" / "x.json")
        with self.assertRaises(SystemExit):
            L.assert_not_production(L.REPO / "lib" / "x.dart")


if __name__ == "__main__":
    unittest.main()
