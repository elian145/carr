"""LOCKED CarNet vocabulary (carnet.vocabulary/1): fuel, drivetrain, two-level transmission."""
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import enrichment_lib as L  # noqa: E402

V = L.NORM["locked_vocabulary"]


class FuelVocabulary(unittest.TestCase):
    def test_petrol_is_canonical_for_all_spellings(self):
        for raw in ("Petrol", "Gasoline", "gasoline", "Unleaded", "Unleaded Petrol", "Petrol (Gasoline)", "Gas", "Premium unleaded gasoline", "ガソリン（レギュラー）"):
            self.assertEqual(L.norm_fuel(raw)[0], "Petrol", raw)

    def test_hybrid_is_never_petrol(self):
        for raw in ("Hybrid", "Petrol Hybrid", "Gasoline hybrid", "Full Hybrid", "HEV", "Hybrid Electric Vehicle (Petrol)", "i-FORCE MAX Hybrid", "2.5L Hybrid gasoline"):
            self.assertEqual(L.norm_fuel(raw)[0], "Hybrid", raw)
            self.assertNotEqual(L.norm_fuel(raw)[0], "Petrol", raw)

    def test_plug_in_is_separate_from_hybrid_and_petrol(self):
        for raw in ("Plug-in Hybrid", "PHEV", "plug in hybrid petrol"):
            self.assertEqual(L.norm_fuel(raw)[0], "Plug-in Hybrid", raw)

    def test_diesel_and_electric(self):
        self.assertEqual(L.norm_fuel("Diesel")[0], "Diesel")
        self.assertEqual(L.norm_fuel("Turbo Diesel")[0], "Diesel")
        self.assertEqual(L.norm_fuel("Electric")[0], "Electric")

    def test_vocabulary_lists_are_locked(self):
        self.assertEqual(V["fuel_type"], ["Petrol", "Diesel", "Electric", "Hybrid", "Plug-in Hybrid"])
        self.assertEqual(L.NORM["fuel_type"]["canonical"], V["fuel_type"])

    def test_hybrid_and_petrol_are_different_configurations_in_the_union(self):
        # same engine size, one hybrid one petrol: never a conflict, both values survive
        a = {"normalized": _norm(fuel_type="Hybrid", horsepower_hp=200.0), "year_from": None, "year_to": None, "variant": None}
        b = {"normalized": _norm(fuel_type="Petrol", horsepower_hp=150.0), "year_from": None, "year_to": None, "variant": None}
        self.assertFalse(L.compatible(a, b)[0])


class DrivetrainVocabulary(unittest.TestCase):
    def test_4x4_family_is_4wd(self):
        for raw in ("4x4", "4X4", "4×4", "4WD", "4 WD", "Four-wheel drive", "Four wheel drive", "4-wheel drive", "full-time 4WD", "Full-Time Four-Wheel Drive", "part-time 4WD", "Part-time 4x4"):
            self.assertEqual(L.norm_drivetrain(raw)[0], "4WD", raw)

    def test_awd_is_never_4wd_and_4wd_never_awd(self):
        for raw in ("AWD", "All-Wheel Drive", "All wheel drive", "Electronic On-Demand All-Wheel Drive (AWD)", "E-Four"):
            self.assertEqual(L.norm_drivetrain(raw)[0], "AWD", raw)
        self.assertNotEqual(L.norm_drivetrain("AWD")[0], L.norm_drivetrain("4WD")[0])
        self.assertNotIn("4WD", set(L.NORM["drivetrain"]["legacy_collapse"].values()))  # only used by the informational legacy_view

    def test_fwd_rwd(self):
        self.assertEqual(L.norm_drivetrain("Front-wheel drive")[0], "FWD")
        self.assertEqual(L.norm_drivetrain("RWD")[0], "RWD")

    def test_two_wheel_drive_without_axle_is_null(self):
        for raw in ("4x2", "4×2", "2WD", "Two-wheel drive"):
            v, flags = L.norm_drivetrain(raw)
            self.assertIsNone(v, raw)
            self.assertEqual(flags, ["two_wheel_drive_axle_unspecified"], raw)

    def test_vocabulary_lists_are_locked(self):
        self.assertEqual(V["drivetrain"], ["FWD", "RWD", "AWD", "4WD"])
        self.assertEqual(L.NORM["drivetrain"]["canonical"], V["drivetrain"])


class TransmissionVocabulary(unittest.TestCase):
    def t(self, raw, gears=None):
        return L.norm_transmission(raw, gears)

    def test_cvt_keeps_variant_inside_automatic_family(self):
        t, _ = self.t("CVT")
        self.assertEqual((t["family"], t["variant"]), ("Automatic", "CVT"))
        t, _ = self.t("Super CVT-i")
        self.assertEqual((t["family"], t["variant"]), ("Automatic", "CVT"))
        t, _ = self.t("Continuously Variable Transmission")
        self.assertEqual((t["family"], t["variant"]), ("Automatic", "CVT"))

    def test_e_cvt_is_distinct_from_cvt(self):
        for raw in ("e-CVT", "E-CVT", "ECVT", "Electronic Continuous Variable Transmission (E-CVT)"):
            t, _ = self.t(raw)
            self.assertEqual((t["family"], t["variant"]), ("Automatic", "e-CVT"), raw)

    def test_dct_amt_conventional(self):
        t, _ = self.t("8-speed dual-clutch")
        self.assertEqual((t["family"], t["variant"], t["gears"]), ("Automatic", "DCT", 8))
        t, _ = self.t("7-speed DSG")
        self.assertEqual((t["family"], t["variant"], t["gears"]), ("Automatic", "DCT", 7))
        t, _ = self.t("5-speed AMT")
        self.assertEqual((t["family"], t["variant"], t["gears"]), ("Automatic", "AMT", 5))
        t, _ = self.t("Automated manual transmission")
        self.assertEqual((t["family"], t["variant"]), ("Automatic", "AMT"))
        t, _ = self.t("6-speed torque converter automatic")
        self.assertEqual((t["family"], t["variant"], t["gears"]), ("Automatic", "Conventional automatic", 6))

    def test_plain_automatic_does_not_invent_a_variant(self):
        for raw in ("Automatic", "8AT", "6-speed automatic", "10-Speed Automatic Transmission"):
            t, _ = self.t(raw)
            self.assertEqual(t["family"], "Automatic", raw)
            self.assertIsNone(t["variant"], raw)

    def test_other_explicit_source_wording_is_kept_as_variant(self):
        t, _ = self.t("10-Speed Automatic Transmission with SelectShift")
        self.assertEqual((t["family"], t["variant"], t["gears"]), ("Automatic", "SelectShift", 10))
        t, _ = self.t("Direct Shift-10AT")
        self.assertEqual((t["variant"], t["gears"]), ("Direct Shift", 10))
        t, _ = self.t("6 Super ECT")
        self.assertEqual((t["variant"], t["gears"]), ("Super ECT", 6))
        t, _ = self.t("8-speed Electronically Controlled Automatic Transmission with intelligence (ECT-i)")
        self.assertEqual((t["variant"], t["gears"]), ("ECT-i", 8))

    def test_canonical_variant_wins_but_named_system_is_kept(self):
        t, _ = self.t("Direct Shift CVT")
        self.assertEqual((t["family"], t["variant"]), ("Automatic", "CVT"))
        self.assertEqual(t["named_systems"], ["Direct Shift"])

    def test_gears_are_preserved_where_stated_even_for_cvt(self):
        t, flags = self.t("CVT with 10-speed sequential shift")
        self.assertEqual((t["variant"], t["gears"]), ("CVT", 10))
        self.assertIn("gears_stated_for_cvt", flags)
        t, flags = self.t("e-CVT", gears=8)
        self.assertEqual(t["gears"], 8)
        self.assertIn("gears_stated_for_cvt", flags)
        t, _ = self.t(None, gears=6)
        self.assertEqual(t["gears"], 6)

    def test_manual(self):
        t, _ = self.t("6-speed manual")
        self.assertEqual((t["family"], t["variant"], t["gears"]), ("Manual", None, 6))

    def test_unmapped_is_flagged_not_guessed(self):
        t, flags = self.t("Quantum drive")
        self.assertIsNone(t["family"])
        self.assertTrue(flags[0].startswith("unmapped:transmission"))

    def test_vocabulary_lists_are_locked(self):
        self.assertEqual(V["transmission_family"], ["Automatic", "Manual"])
        self.assertEqual(V["transmission_variant_canonical"], ["Conventional automatic", "CVT", "e-CVT", "DCT", "AMT"])
        self.assertEqual(L.NORM["transmission"]["canonical_variant"], V["transmission_variant_canonical"])

    def test_raw_string_is_never_overwritten_by_prepare(self):
        doc = L.read_json(L.HERE / "evidence" / "toyota_camry.json")
        cvt = [r for r in doc["records"] if "CVT" in (r["transmission"]["type"] or "")]
        self.assertTrue(cvt)
        for r in cvt:
            self.assertEqual(r["normalized"]["transmission_family"], "Automatic")
            self.assertEqual(r["normalized"]["transmission_variant"], "e-CVT")


class EvidenceUsesOnlyLockedValues(unittest.TestCase):
    def test_every_normalized_value_in_pilot_evidence_is_canonical(self):
        for name in ("ford_everest", "toyota_land_cruiser", "toyota_camry"):
            for r in L.read_json(L.HERE / "evidence" / f"{name}.json")["records"]:
                n = r["normalized"]
                self.assertIn(n["fuel_type"], V["fuel_type"] + [None], r["record_id"])
                self.assertIn(n["drivetrain"], V["drivetrain"] + [None], r["record_id"])
                self.assertIn(n["transmission_family"], V["transmission_family"] + [None], r["record_id"])
                self.assertNotIn("transmission_type", n)


def _norm(**kw):
    base = {
        "market": None, "trim": None, "trim_key": None, "engine_group": "2.5L", "fuel_type": None, "seats_is_maximum": False,
        "displacement_cc": None, "cylinders": None, "horsepower_hp": None, "torque_nm": None, "transmission_family": None,
        "transmission_variant": None, "transmission_gears": None, "drivetrain": None, "body_type": None, "seats": None, "doors": None,
    }
    base.update(kw)
    return base


if __name__ == "__main__":
    unittest.main()
